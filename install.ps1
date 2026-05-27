#!/usr/bin/env pwsh
# YASTT manual installer (Windows / PowerShell).
# Copies the server + dashboard + hooks into ~/.claude/yastt, installs the skills, and wires the
# UserPromptSubmit + SubagentStop hooks into settings.json (merging, with a backup). Re-runnable.

$ErrorActionPreference = 'Stop'
$claude   = Join-Path $env:USERPROFILE '.claude'
$dataDir  = Join-Path $claude 'yastt'
$cmdDir   = Join-Path $claude 'commands'
$settings = Join-Path $claude 'settings.json'
$src      = $PSScriptRoot

New-Item -ItemType Directory -Force -Path $dataDir, $cmdDir | Out-Null

# 1. Server + dashboard + hooks -> ~/.claude/yastt
Copy-Item (Join-Path $src 'server\cwatch.js')         (Join-Path $dataDir 'cwatch.js') -Force
Copy-Item (Join-Path $src 'server\token_usage.html')  (Join-Path $dataDir 'token_usage.html') -Force
Copy-Item (Join-Path $src 'hooks\token_log.ps1')      (Join-Path $dataDir 'token_log.ps1') -Force
Copy-Item (Join-Path $src 'hooks\subagent_stop.ps1')  (Join-Path $dataDir 'subagent_stop.ps1') -Force

# 2. Skills -> ~/.claude/commands  (overwrites any same-named skill -- see README)
Copy-Item (Join-Path $src 'commands\cwatch.md')       (Join-Path $cmdDir 'cwatch.md') -Force
Copy-Item (Join-Path $src 'commands\tokentracker.md') (Join-Path $cmdDir 'tokentracker.md') -Force

# 3. Wire hooks into settings.json (merge; never duplicate; back up first)
$logHook   = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$dataDir\token_log.ps1`""
$agentHook = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$dataDir\subagent_stop.ps1`""

if (Test-Path $settings) {
  Copy-Item $settings "$settings.bak" -Force
  $cfg = Get-Content $settings -Raw | ConvertFrom-Json
} else {
  $cfg = [pscustomobject]@{}
}
if (-not $cfg.PSObject.Properties['hooks']) { $cfg | Add-Member hooks ([pscustomobject]@{}) -Force }

function Add-YasttHook($eventName, $command) {
  $existing = @()
  if ($cfg.hooks.PSObject.Properties[$eventName]) { $existing = @($cfg.hooks.$eventName) }
  foreach ($grp in $existing) {
    foreach ($h in @($grp.hooks)) { if ($h.command -eq $command) { return } }   # already wired
  }
  $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $command }) }
  $cfg.hooks | Add-Member $eventName (@($existing + $entry)) -Force
}
Add-YasttHook 'UserPromptSubmit' $logHook
Add-YasttHook 'SubagentStop'     $agentHook

$cfg | ConvertTo-Json -Depth 25 | Set-Content $settings -Encoding UTF8

Write-Host ""
Write-Host "YASTT installed (Windows)."
Write-Host "  data + server: $dataDir"
Write-Host "  hooks wired:   $settings  (backup: settings.json.bak)"
Write-Host "  skills:        /cwatch   /tokentracker"
Write-Host ""
Write-Host "Open /hooks once (or restart Claude Code) so the new hooks load, then run /cwatch."
