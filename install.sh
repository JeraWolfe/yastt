#!/usr/bin/env bash
# YASTT manual installer (macOS / Linux).
# Copies the server + dashboard + hooks into ~/.claude/yastt, installs the skills, and wires the
# UserPromptSubmit + SubagentStop hooks into settings.json (merging, with a backup). Re-runnable.
# Requires: node (to run the server) and jq (for the hooks + this merge).
set -e

claude="$HOME/.claude"; data="$claude/yastt"; cmd="$claude/commands"; settings="$claude/settings.json"
src="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$data" "$cmd"

# 1. Server + dashboard + hooks -> ~/.claude/yastt
cp "$src/server/cwatch.js"        "$data/cwatch.js"
cp "$src/server/token_usage.html" "$data/token_usage.html"
cp "$src/hooks/token_log.sh"      "$data/token_log.sh";      chmod +x "$data/token_log.sh"
cp "$src/hooks/subagent_stop.sh"  "$data/subagent_stop.sh";  chmod +x "$data/subagent_stop.sh"

# 2. Skills -> ~/.claude/commands  (overwrites any same-named skill -- see README)
cp "$src/commands/cwatch.md"       "$cmd/cwatch.md"
cp "$src/commands/tokentracker.md" "$cmd/tokentracker.md"

command -v node >/dev/null 2>&1 || echo "WARNING: 'node' not found — the dashboard server needs Node.js."
command -v jq   >/dev/null 2>&1 || { echo "WARNING: 'jq' not found — the hooks and this installer need it. Install jq and re-run."; exit 1; }

# 3. Wire hooks into settings.json (merge; never duplicate; back up first)
logHook="bash \"$data/token_log.sh\""
agentHook="bash \"$data/subagent_stop.sh\""
[ -f "$settings" ] && cp "$settings" "$settings.bak" || echo '{}' > "$settings"

tmp="$(mktemp)"
jq --arg lc "$logHook" --arg ac "$agentHook" '
  .hooks //= {}
  | .hooks.UserPromptSubmit //= []
  | .hooks.SubagentStop //= []
  | (if any(.hooks.UserPromptSubmit[]?; (.hooks // [])[]?.command == $lc)
       then . else .hooks.UserPromptSubmit += [{hooks:[{type:"command",command:$lc}]}] end)
  | (if any(.hooks.SubagentStop[]?; (.hooks // [])[]?.command == $ac)
       then . else .hooks.SubagentStop += [{hooks:[{type:"command",command:$ac}]}] end)
' "$settings" > "$tmp" && mv "$tmp" "$settings"

echo ""
echo "YASTT installed (macOS/Linux)."
echo "  data + server: $data"
echo "  hooks wired:   $settings  (backup: settings.json.bak)"
echo "  skills:        /cwatch   /tokentracker"
echo ""
echo "Open /hooks once (or restart Claude Code) so the new hooks load, then run /cwatch."
