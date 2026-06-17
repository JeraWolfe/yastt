#!/usr/bin/env bash
# YASTT -- token_log hook (macOS / Linux). Wired to UserPromptSubmit.
# Logs the previous turn's token usage to ~/.claude/yastt/token_usage.csv.
# Requires: jq. ALPHA: ported from the Windows PowerShell hook; not yet tested on macOS/Linux.
# Always exits 0 -- a logging hook must never break the prompt.

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' | tr -d '-')
session=${sid:0:8}; session=${session:-????????}
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then exit 0; fi

# Last assistant entry that carries usage.
last=$(jq -c 'select(.type=="assistant" and ((.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0) > 0)) | {i:(.message.usage.input_tokens//0),cw:(.message.usage.cache_creation_input_tokens//0),cr:(.message.usage.cache_read_input_tokens//0),o:(.message.usage.output_tokens//0),ep:(.entrypoint//""),m:(.message.model//"")}' "$transcript" 2>/dev/null | tail -n 1)
[ -z "$last" ] && exit 0

inp=$(printf '%s' "$last" | jq -r '.i'); cw=$(printf '%s' "$last" | jq -r '.cw')
cr=$(printf '%s' "$last"  | jq -r '.cr'); out=$(printf '%s' "$last" | jq -r '.o')
ep=$(printf '%s' "$last"  | jq -r '.ep'); model=$(printf '%s' "$last" | jq -r '.m')

# Ship labels: CLI, DESK (desktop app), WEB. PLAN (planner) is cloud -> never seen by a local hook.
case "$ep" in cli) who=CLI;; desktop|app) who=DESK;; web) who=WEB;; *) who='?';; esac

ml=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
if   [[ "$ml" == *opus*  ]]; then ri=15.00; ro=75.00; rcw=18.75; rcr=1.50; win=1000000
elif [[ "$ml" == *haiku* ]]; then ri=0.80;  ro=4.00;  rcw=1.00;  rcr=0.08; win=200000
else                              ri=3.00;  ro=15.00; rcw=3.75;  rcr=0.30; win=200000
fi

fill=$((inp + cw + cr))
plain=$((inp - cw - cr)); [ "$plain" -lt 0 ] && plain=0
metrics=$(awk -v p="$plain" -v o="$out" -v cw="$cw" -v cr="$cr" -v ri="$ri" -v ro="$ro" -v rcw="$rcw" -v rcr="$rcr" -v fill="$fill" -v win="$win" 'BEGIN{
  c=(p/1e6*ri)+(o/1e6*ro)+(cw/1e6*rcw)+(cr/1e6*rcr);
  ch=(fill>0)?cr/fill:0;
  pc=(win>0)?int((fill/win)*100+0.5):0; if(pc>100)pc=100;
  printf "%.4f %.3f %d", c, ch, pc;
}')
cost=$(echo "$metrics" | cut -d' ' -f1)
cache=$(echo "$metrics" | cut -d' ' -f2)
pct=$(echo "$metrics" | cut -d' ' -f3)

data_dir="$HOME/.claude/yastt"; mkdir -p "$data_dir"
log="$data_dir/token_usage.csv"
master_log="$data_dir/yastt_log.csv"
header="TokenDelta,TokenTotal,Percentage,Date,Time,Flag,Session,Who,Model,Cost,CacheRatio"
[ -f "$log" ] || echo "$header" > "$log"

# Walk the CSV backward and find the most recent prior row of the SAME session AND SAME model.
# That row's TokenTotal (index 1, field 2) is the in-thread previous context fill.
prev=$(awk -F',' -v want_session="$session" -v want_model="$model" '
  NF>=9 && $7==want_session && $9==want_model { last=$2 }
  END { if (last != "") print last }
' "$log")
prev_found=1
case "${prev:-}" in ''|*[!0-9]*) prev=0; prev_found=0;; esac

if [ "$prev_found" -eq 1 ]; then
  delta=$((fill - prev)); flag=""
  if [ "$delta" -lt 0 ]; then delta=$fill; flag="C"; fi
else
  # New thread (first row for this session+model): no compact flag.
  delta=$fill; flag=""
fi

row="$delta,$fill,$pct,$(date +%Y-%m-%d),$(date +%H:%M:%S),$flag,$session,$who,$model,$cost,$cache"
echo "$row" >> "$log"

# Append the SAME row to the never-scrubbed master log (append-only; no scrub/trim ever).
[ -f "$master_log" ] || echo "$header" > "$master_log"
echo "$row" >> "$master_log"
exit 0
