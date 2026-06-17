#!/usr/bin/env pwsh
# YASTT -- subagent_stop hook (Windows / PowerShell)
# Wired to SubagentStop. Parses the agent's own transcript for exact token breakdown.
# Writes to agent_usage.csv (keyed on AgentId, deduped).
# Format: AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho

param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$input_json = $Input | Out-String
if ([string]::IsNullOrWhiteSpace($input_json)) {
    $input_json = [Console]::In.ReadToEnd()
}

try { $data = $input_json | ConvertFrom-Json } catch { exit 0 }

$agent_id       = if ($data.agent_id) { $data.agent_id } else { exit 0 }
$agent_transcript = $data.agent_transcript_path
$parent_transcript = $data.transcript_path
$parent_session = if ($data.session_id) { ($data.session_id -replace '-','').Substring(0,8) } else { "????????" }

# Parse agent's own transcript for exact token usage
$ctx_input  = 0
$ctx_cw     = 0
$ctx_cr     = 0
$ctx_output = 0
$tool_uses  = 0
$model      = ""
$min_ts     = $null
$max_ts     = $null

if ($agent_transcript -and (Test-Path $agent_transcript)) {
    $lines = Get-Content $agent_transcript -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            # Track earliest and latest per-line ISO 8601 timestamp for Duration.
            if ($entry.timestamp) {
                try {
                    $entry_ts = [DateTimeOffset]::Parse($entry.timestamp).UtcDateTime
                    if ($null -eq $min_ts -or $entry_ts -lt $min_ts) { $min_ts = $entry_ts }
                    if ($null -eq $max_ts -or $entry_ts -gt $max_ts) { $max_ts = $entry_ts }
                } catch {}
            }
            if ($entry.type -eq "assistant" -and $entry.message.usage) {
                $u = $entry.message.usage
                $ctx_input  = if ($u.input_tokens)                { [long]$u.input_tokens }                else { 0 }
                $ctx_cw     = if ($u.cache_creation_input_tokens) { [long]$u.cache_creation_input_tokens } else { 0 }
                $ctx_cr     = if ($u.cache_read_input_tokens)     { [long]$u.cache_read_input_tokens }     else { 0 }
                $ctx_output = if ($u.output_tokens)               { [long]$u.output_tokens }               else { 0 }
                $model      = if ($entry.message.model)           { $entry.message.model }                 else { $model }
            }
            if ($entry.type -eq "user" -and $entry.message.content) {
                $content = $entry.message.content
                if ($content -isnot [System.Array]) { $content = @($content) }
                $tool_uses += ($content | Where-Object { $_.type -eq "tool_result" }).Count
            }
        } catch {}
    }
}

$context_fill = $ctx_input + $ctx_cw + $ctx_cr
if ($context_fill -eq 0) { exit 0 }

# Duration = whole ms between first and last transcript timestamp; 0 if unavailable.
$duration = 0
if ($null -ne $min_ts -and $null -ne $max_ts) {
    $duration = [long][Math]::Round(($max_ts - $min_ts).TotalMilliseconds)
    if ($duration -lt 0) { $duration = 0 }
}

# Compute cost
$model_lower = $model.ToLower()
if ($model_lower -match 'opus') {
    $rate_in = 15.00; $rate_out = 75.00; $rate_cw = 18.75; $rate_cr = 1.50
} elseif ($model_lower -match 'haiku') {
    $rate_in = 0.80;  $rate_out = 4.00;  $rate_cw = 1.00;  $rate_cr = 0.08
} else {
    $rate_in = 3.00;  $rate_out = 15.00; $rate_cw = 3.75;  $rate_cr = 0.30
}
$plain_input = [Math]::Max(0, $ctx_input - $ctx_cw - $ctx_cr)
$cost = ($plain_input    / 1000000.0 * $rate_in)  +
        ($ctx_output     / 1000000.0 * $rate_out) +
        ($ctx_cw         / 1000000.0 * $rate_cw)  +
        ($ctx_cr         / 1000000.0 * $rate_cr)
$cost_str    = $cost.ToString("0.0000")
$cache_ratio = if ($context_fill -gt 0) { [Math]::Round($ctx_cr / [double]$context_fill, 3) } else { 0 }

# Get parentWho from parent transcript entrypoint
$parent_entrypoint = ""
if ($parent_transcript -and (Test-Path $parent_transcript)) {
    $parent_lines = Get-Content $parent_transcript -ErrorAction SilentlyContinue | Select-Object -Last 100
    foreach ($pline in $parent_lines) {
        if ([string]::IsNullOrWhiteSpace($pline)) { continue }
        try {
            $pentry = $pline | ConvertFrom-Json
            if ($pentry.type -eq "assistant" -and $pentry.entrypoint) {
                $parent_entrypoint = $pentry.entrypoint
            }
        } catch {}
    }
}
# Ship labels: CLI (command line), DESK (desktop app), WEB (browser). PLAN (planner) is assigned by session, not entrypoint.
$parentWho = switch ($parent_entrypoint) {
    "cli"     { "CLI" }
    "desktop" { "DESK" }
    "app"     { "DESK" }
    "web"     { "WEB" }
    default   { "?" }
}

$now      = Get-Date
$date_str = $now.ToString("yyyy-MM-dd")
$time_str = $now.ToString("HH:mm:ss")

$data_dir = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".claude\yastt"
if (-not (Test-Path $data_dir)) { New-Item -ItemType Directory -Force -Path $data_dir | Out-Null }
$agent_log = Join-Path $data_dir "agent_usage.csv"
$agent_hdr = "AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho,Duration"
$existing_ids = @()

if (-not (Test-Path $agent_log)) {
    Set-Content $agent_log $agent_hdr -Encoding UTF8
} else {
    $agent_lines = Get-Content $agent_log -ErrorAction SilentlyContinue
    foreach ($aln in $agent_lines) {
        if ([string]::IsNullOrWhiteSpace($aln) -or $aln -eq $agent_hdr) { continue }
        $aparts = $aln.Split(',')
        if ($aparts.Count -ge 1) { $existing_ids += $aparts[0].Trim() }
    }
}

if ($agent_id -notin $existing_ids) {
    Add-Content $agent_log "$agent_id,$context_fill,$tool_uses,$cost_str,$cache_ratio,$model,$date_str,$time_str,$parent_session,$parentWho,$duration" -Encoding UTF8
}
