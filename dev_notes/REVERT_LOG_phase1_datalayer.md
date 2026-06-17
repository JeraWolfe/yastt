# REVERT LOG — Phase 1 Data Layer (hooks only)

Baseline commit for full revert: **8565981**

Scope: four hook files only. No other file was edited. `server/cwatch.js` was read
read-only (scrub-safety confirmation) and NOT modified.

Full-file revert command (per file):

```
git checkout 8565981 -- hooks/token_log.ps1
git checkout 8565981 -- hooks/token_log.sh
git checkout 8565981 -- hooks/subagent_stop.ps1
git checkout 8565981 -- hooks/subagent_stop.sh
```

---

## hooks/token_log.ps1

### Change 1 — TASK A: same-session + same-model compact guard
Replaced the global "last row" `prev_total` lookup with a backward walk that matches
both Session (index 6) and Model (index 8); flag "C" only on a genuine in-thread
negative delta; fresh thread (no match) gets `delta = context_fill`, no flag.

### Change 2 — TASK B: append to never-scrubbed master log
After writing the row to token_usage.csv, the same row is also appended to a sibling
`yastt_log.csv` (created with the same header if absent). Append-only; no scrub.

Both changes live in one contiguous edited block. To hand-revert, restore the ORIGINAL
block below (replaces the new block from `$data_dir = Join-Path ...` through the closing `}`):

ORIGINAL SNIPPET:
```powershell
    $data_dir = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".claude\yastt"
    if (-not (Test-Path $data_dir)) { New-Item -ItemType Directory -Force -Path $data_dir | Out-Null }
    $log_file = Join-Path $data_dir "token_usage.csv"
    $header   = "TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio"
    $prev_total = 0

    if (-not (Test-Path $log_file)) {
        Set-Content $log_file $header -Encoding UTF8
    } else {
        $csv_lines = Get-Content $log_file -ErrorAction SilentlyContinue
        for ($i = $csv_lines.Count - 1; $i -ge 0; $i--) {
            $ln = $csv_lines[$i].Trim()
            if (-not [string]::IsNullOrWhiteSpace($ln) -and $ln -ne $header) {
                $parts = $ln.Split(',')
                if ($parts.Count -ge 2) {
                    try { $prev_total = [long]$parts[1] } catch { }
                }
                break
            }
        }
    }

    $delta = $context_fill - $prev_total
    $flag  = ""
    if ($delta -lt 0) {
        $delta = $context_fill
        $flag  = "C"
    }

    Add-Content $log_file "$delta,$context_fill,$pct,$date_str,$time_str,$flag,$session_id,$who,$last_model,$cost_str,$cache_ratio" -Encoding UTF8
}
```

Single-file revert: `git checkout 8565981 -- hooks/token_log.ps1`

---

## hooks/token_log.sh

### Change 1 — TASK A: same-session + same-model compact guard
Replaced `tail -n 1` global prev lookup with an awk backward-match on field 7 (Session)
and field 9 (Model); fresh thread gets `delta = fill`, no flag.

### Change 2 — TASK B: append to never-scrubbed master log
Added `master_log="$data_dir/yastt_log.csv"`, created with header if absent, and the
same `$row` appended to it. Append-only; no scrub.

NOTE: the row is now built once into `$row` (single `date` invocation pair) and written
to both files — functionally identical to the original two `date` calls in one echo.

ORIGINAL SNIPPET (replaces the new block from `data_dir=...` through `exit 0`):
```bash
data_dir="$HOME/.claude/yastt"; mkdir -p "$data_dir"
log="$data_dir/token_usage.csv"
header="TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio"
[ -f "$log" ] || echo "$header" > "$log"

prev=$(tail -n 1 "$log" | awk -F',' 'NF>=2{print $2}')
case "${prev:-}" in ''|*[!0-9]*) prev=0;; esac
delta=$((fill - prev)); flag=""
if [ "$delta" -lt 0 ]; then delta=$fill; flag="C"; fi

echo "$delta,$fill,$pct,$(date +%Y-%m-%d),$(date +%H:%M:%S),$flag,$session,$who,$model,$cost,$cache" >> "$log"
exit 0
```

Single-file revert: `git checkout 8565981 -- hooks/token_log.sh`

---

## hooks/subagent_stop.ps1

### Change 1 — TASK C: track min/max transcript timestamp
Added `$min_ts = $null` / `$max_ts = $null` initializers, and inside the transcript
parse loop a block that parses each entry's `timestamp` (ISO 8601 → UTC DateTime) and
updates min/max.

ORIGINAL SNIPPET A (init block):
```powershell
# Parse agent's own transcript for exact token usage
$ctx_input  = 0
$ctx_cw     = 0
$ctx_cr     = 0
$ctx_output = 0
$tool_uses  = 0
$model      = ""

if ($agent_transcript -and (Test-Path $agent_transcript)) {
    $lines = Get-Content $agent_transcript -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -eq "assistant" -and $entry.message.usage) {
```

### Change 2 — TASK C: compute Duration
Added a `$duration` computation block (whole ms between min/max; 0 if unavailable)
right after the `$context_fill -eq 0` guard.

ORIGINAL SNIPPET B:
```powershell
$context_fill = $ctx_input + $ctx_cw + $ctx_cr
if ($context_fill -eq 0) { exit 0 }
```

### Change 3 — TASK C: header gains Duration
ORIGINAL SNIPPET C:
```powershell
$agent_hdr = "AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho"
```

### Change 4 — TASK C: row write gains $duration
ORIGINAL SNIPPET D:
```powershell
    Add-Content $agent_log "$agent_id,$context_fill,$tool_uses,$cost_str,$cache_ratio,$model,$date_str,$time_str,$parent_session,$parentWho" -Encoding UTF8
```

Single-file revert: `git checkout 8565981 -- hooks/subagent_stop.ps1`

---

## hooks/subagent_stop.sh

### Change 1 — TASK C: compute Duration via jq + awk
Added `duration=0` to the init line, and inside the `[ -n "$atrans" ]` block a jq pass
that extracts each `.timestamp` (`fromdateiso8601 * 1000`) piped to awk for min/max ms
spread, then a numeric-guard `case`.

ORIGINAL SNIPPET A:
```bash
inp=0; cw=0; cr=0; out=0; model=""; tools=0
if [ -n "$atrans" ] && [ -f "$atrans" ]; then
  last=$(jq -c 'select(.type=="assistant" and (.message.usage != null)) | {i:(.message.usage.input_tokens//0),cw:(.message.usage.cache_creation_input_tokens//0),cr:(.message.usage.cache_read_input_tokens//0),o:(.message.usage.output_tokens//0),m:(.message.model//"")}' "$atrans" 2>/dev/null | tail -n 1)
  if [ -n "$last" ]; then
    inp=$(printf '%s' "$last" | jq -r '.i'); cw=$(printf '%s' "$last" | jq -r '.cw')
    cr=$(printf '%s' "$last"  | jq -r '.cr'); out=$(printf '%s' "$last" | jq -r '.o')
    model=$(printf '%s' "$last" | jq -r '.m')
  fi
  tools=$(jq -r 'select(.type=="user") | (.message.content // []) | if type=="array" then ([.[]|select(.type=="tool_result")]|length) else 0 end' "$atrans" 2>/dev/null | awk '{s+=$1} END{print s+0}')
fi
```

### Change 2 — TASK C: header gains Duration
ORIGINAL SNIPPET B:
```bash
hdr="AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho"
```

### Change 3 — TASK C: row write gains $duration
ORIGINAL SNIPPET C:
```bash
  echo "$agent_id,$fill,$tools,$cost,$cache,$model,$(date +%Y-%m-%d),$(date +%H:%M:%S),$psession,$pwho" >> "$log"
```

Single-file revert: `git checkout 8565981 -- hooks/subagent_stop.sh`

---

## cwatch.js scrub-safety finding (read-only, no edit)

Confirmed: `compactPipsWeek`, `bumpHourlyToWeekly`, and `runRollup` in server/cwatch.js
reference ONLY the `F` file map — `F.pips` (token_usage.csv), `F.hourly` (yastt_hourly.csv),
`F.weekly` (yastt_weekly.csv), and `F.state` (yastt_rollup_state.json). There is NO
reference to `yastt_log.csv` anywhere in cwatch.js. The new master log is therefore never
scrubbed. The static file route serves any `.csv` from DATA_DIR, so yastt_log.csv will be
readable by the dashboard but is never written/trimmed by the rollup.
