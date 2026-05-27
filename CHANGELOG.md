# Changelog

Notable changes to YASTT. Loosely follows Keep a Changelog; versions follow SemVer (with pre‑release tags during alpha).

## [0.1.0-alpha] — 2026-05-27

First public alpha. Testing with a small group; actively updated.

### Added
- Local dashboard server (`cwatch.js`) on `localhost:8765`, serving a single‑file Chart.js dashboard.
- `UserPromptSubmit` + `SubagentStop` hooks logging per‑exchange and per‑agent token usage, cost, and cache ratio to `~/.claude/yastt/`.
- Live rate‑limit gauges (5h / 7‑day / per‑model utilization) via a server‑side proxy to Anthropic's usage endpoint — the OAuth token stays local, never logged or transmitted.
- LOD time zoom: `Full · Week · Day · 5h`; day `24h↔36h` toggle with adaptive midnight handling.
- Dynamic defaults on load (y‑scale 200K/1M, opening window, day span) derived from your data.
- Per‑client (CLI / DESK) lines + model filter; separate sub‑agent breakdown chart.
- Dormant retention ladder (pips → hourly → weekly) with a roll‑up → verify → scrub safety rule.
- Cross‑platform: PowerShell hooks (Windows) + bash hooks (macOS/Linux, needs `jq`); Node dispatcher for the plugin path.
- Manual installers (`install.ps1` / `install.sh`) plus a Claude Code plugin manifest + marketplace entry.

### Known issues
- Sub‑agent `ToolUses` logs as `0` (transcript parser gap).
- bash hooks ported but **untested** on macOS/Linux.
- Plugin server bootstrap is not yet one‑command (use the manual installer).
