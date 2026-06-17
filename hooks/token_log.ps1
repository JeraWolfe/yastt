#!/usr/bin/env pwsh
# YASTT -- token_log hook (Windows / PowerShell)
# Wired to UserPromptSubmit. Logs the PREVIOUS turn's token usage to ~/.claude/yastt/token_usage.csv.
# Reads transcript for per-turn usage; no context_window needed.
# TokenTotal  = full context fill (input + cache_creation + cache_read).
# Flag        = "C" when compact detected (delta went negative).
# Session     = first 8 chars of session_id for boundary tracking.
# Who         = client identity read from transcript entrypoint field.
# Model       = model name from last assistant entry.
# Cost        = per-turn cost in USD using model-specific rates.
# CacheRatio  = cache_read / context_fill (0.0-1.0 cache efficiency).
# Also scans user tool_result entries for Agent <usage> blocks -> agent_usage.csv.

param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$input_json = $Input | Out-String
if ([string]::IsNullOrWhiteSpace($input_json)) {
    $input_json = [Console]::In.ReadToEnd()
}

try {
    $data = $input_json | ConvertFrom-Json
} catch {
    exit 0
}

$transcript = $data.transcript_path
$session_id = if ($data.session_id) { ($data.session_id -replace '-','').Substring(0,8) } else { "????????" }

if ([string]::IsNullOrWhiteSpace($transcript) -or -not (Test-Path $transcript)) {
    exit 0
}

$last_input       = 0
$last_cache_w     = 0
$last_cache_r     = 0
$last_output      = 0
$last_entrypoint  = ""
$last_model       = ""
$found            = $false

$lines = Get-Content $transcript -ErrorAction SilentlyContinue
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $entry = $line | ConvertFrom-Json

        if ($entry.type -eq "assistant" -and $entry.message.usage) {
            $u = $entry.message.usage
            if ($u.input_tokens -or $u.cache_read_input_tokens -or $u.cache_creation_input_tokens) {
                $last_input      = if ($u.input_tokens)                { [long]$u.input_tokens }                else { 0 }
                $last_cache_w    = if ($u.cache_creation_input_tokens) { [long]$u.cache_creation_input_tokens } else { 0 }
                $last_cache_r    = if ($u.cache_read_input_tokens)     { [long]$u.cache_read_input_tokens }     else { 0 }
                $last_output     = if ($u.output_tokens)               { [long]$u.output_tokens }               else { 0 }
                $last_entrypoint = if ($entry.entrypoint)              { $entry.entrypoint }                    else { "" }
                $last_model      = if ($entry.message.model)           { $entry.message.model }                 else { "" }
                $found           = $true
            }
        }
    } catch { }
}

# Ship labels: CLI (command line), DESK (desktop app), WEB (browser). PLAN (planner) is assigned by session, not entrypoint.
$who = switch ($last_entrypoint) {
    "cli"     { "CLI" }
    "desktop" { "DESK" }
    "app"     { "DESK" }
    "web"     { "WEB" }
    default   { "?" }
}

$model_lower = $last_model.ToLower()
if ($model_lower -match 'opus') {
    $rate_in = 15.00; $rate_out = 75.00; $rate_cw = 18.75; $rate_cr = 1.50
} elseif ($model_lower -match 'haiku') {
    $rate_in = 0.80;  $rate_out = 4.00;  $rate_cw = 1.00;  $rate_cr = 0.08
} else {
    $rate_in = 3.00;  $rate_out = 15.00; $rate_cw = 3.75;  $rate_cr = 0.30
}

$now      = Get-Date
$date_str = $now.ToString("yyyy-MM-dd")
$time_str = $now.ToString("HH:mm:ss")

if ($found) {
    $plain_input = $last_input - $last_cache_w - $last_cache_r
    if ($plain_input -lt 0) { $plain_input = 0 }
    $cost = ($plain_input    / 1000000.0 * $rate_in)  +
            ($last_output    / 1000000.0 * $rate_out) +
            ($last_cache_w   / 1000000.0 * $rate_cw)  +
            ($last_cache_r   / 1000000.0 * $rate_cr)
    $cost_str = $cost.ToString("0.0000")

    $context_fill    = $last_input + $last_cache_w + $last_cache_r
    $context_window  = if ($model_lower -match 'opus') { 1000000.0 } else { 200000.0 }
    $pct             = [int][Math]::Round(($context_fill / $context_window) * 100)
    if ($pct -gt 100) { $pct = 100 }
    $cache_ratio  = if ($context_fill -gt 0) { [Math]::Round($last_cache_r / [double]$context_fill, 3) } else { 0 }

    $data_dir = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".claude\yastt"
    if (-not (Test-Path $data_dir)) { New-Item -ItemType Directory -Force -Path $data_dir | Out-Null }
    $log_file = Join-Path $data_dir "token_usage.csv"
    $header   = "TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio"
    $prev_total      = 0
    $prev_row_found  = $false

    if (-not (Test-Path $log_file)) {
        Set-Content $log_file $header -Encoding UTF8
    } else {
        # Walk backward and find the most recent prior row of the SAME session AND SAME model.
        # That row's TokenTotal (index 1) is the in-thread previous context fill.
        $csv_lines = Get-Content $log_file -ErrorAction SilentlyContinue
        for ($i = $csv_lines.Count - 1; $i -ge 0; $i--) {
            $ln = $csv_lines[$i].Trim()
            if ([string]::IsNullOrWhiteSpace($ln) -or $ln -eq $header) { continue }
            $parts = $ln.Split(',')
            if ($parts.Count -ge 9) {
                $row_session = $parts[6].Trim()
                $row_model   = $parts[8].Trim()
                if ($row_session -eq $session_id -and $row_model -eq $last_model) {
                    try { $prev_total = [long]$parts[1]; $prev_row_found = $true } catch { }
                    break
                }
            }
        }
    }

    if ($prev_row_found) {
        $delta = $context_fill - $prev_total
        $flag  = ""
        if ($delta -lt 0) {
            # Genuine in-thread context drop = a real compact.
            $delta = $context_fill
            $flag  = "C"
        }
    } else {
        # New thread (first row for this session+model): no compact flag.
        $delta = $context_fill
        $flag  = ""
    }

    $row = "$delta,$context_fill,$pct,$date_str,$time_str,$flag,$session_id,$who,$last_model,$cost_str,$cache_ratio"
    Add-Content $log_file $row -Encoding UTF8

    # Append the SAME row to the never-scrubbed master log (append-only; no scrub/trim ever).
    $master_log = Join-Path $data_dir "yastt_log.csv"
    if (-not (Test-Path $master_log)) {
        Set-Content $master_log $header -Encoding UTF8
    }
    Add-Content $master_log $row -Encoding UTF8
}

