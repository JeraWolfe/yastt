---
description: Start the YASTT server and open the live token dashboard.
---

Start the YASTT token-monitoring server (if it isn't already running) and open the dashboard in the browser.

## Steps

1. **Is it already up?** Request `http://localhost:8765/token_usage.csv`. If it returns 200, the server is running — skip to step 3.

2. **Start the server** (background/detached) with Node. Find `cwatch.js` at the first path that exists and run `node "<that path>"`:
   - `${CLAUDE_PLUGIN_ROOT}/server/cwatch.js`  — when installed as a plugin
   - `~/.claude/yastt/cwatch.js`  — when installed manually

   Windows (PowerShell):
   ```powershell
   $srv = if (Test-Path "$env:CLAUDE_PLUGIN_ROOT\server\cwatch.js") { "$env:CLAUDE_PLUGIN_ROOT\server\cwatch.js" } else { "$env:USERPROFILE\.claude\yastt\cwatch.js" }
   Start-Process node -ArgumentList "`"$srv`"" -WindowStyle Hidden
   ```
   macOS / Linux (bash):
   ```bash
   srv="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/server/cwatch.js}"; [ -f "$srv" ] || srv="$HOME/.claude/yastt/cwatch.js"
   nohup node "$srv" >/dev/null 2>&1 &
   ```

3. **Open the dashboard** `http://localhost:8765/token_usage.html`:
   - Windows: `Start-Process "http://localhost:8765/token_usage.html"`
   - macOS: `open "http://localhost:8765/token_usage.html"`
   - Linux: `xdg-open "http://localhost:8765/token_usage.html"`

The server reads/writes YASTT data in `~/.claude/yastt/` and reads Claude's OAuth token **read-only** (from `~/.claude/.credentials.json`) purely to show the live rate-limit gauges. The token stays in the local process — never transmitted, copied, or logged.
