#!/usr/bin/env bash
# YASTT -- subagent_stop hook (macOS / Linux). Wired to SubagentStop.
# Parses the agent's own transcript; appends one deduped row to ~/.claude/yastt/agent_usage.csv.
# Requires: jq. ALPHA: ported from the Windows PowerShell hook; not yet tested on macOS/Linux.
# Always exits 0.

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty')
[ -z "$agent_id" ] && exit 0
atrans=$(printf '%s' "$payload" | jq -r '.agent_transcript_path // empty')
ptrans=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
psid=$(printf '%s' "$payload" | jq -r '.session_id // empty' | tr -d '-')
psession=${psid:0:8}; psession=${psession:-????????}

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

fill=$((inp + cw + cr))
[ "$fill" -eq 0 ] && exit 0

ml=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
if   [[ "$ml" == *opus*  ]]; then ri=15.00; ro=75.00; rcw=18.75; rcr=1.50
elif [[ "$ml" == *haiku* ]]; then ri=0.80;  ro=4.00;  rcw=1.00;  rcr=0.08
else                              ri=3.00;  ro=15.00; rcw=3.75;  rcr=0.30
fi
plain=$((inp - cw - cr)); [ "$plain" -lt 0 ] && plain=0
metrics=$(awk -v p="$plain" -v o="$out" -v cw="$cw" -v cr="$cr" -v ri="$ri" -v ro="$ro" -v rcw="$rcw" -v rcr="$rcr" -v fill="$fill" 'BEGIN{
  c=(p/1e6*ri)+(o/1e6*ro)+(cw/1e6*rcw)+(cr/1e6*rcr);
  ch=(fill>0)?cr/fill:0; printf "%.4f %.3f", c, ch;
}')
cost=$(echo "$metrics" | cut -d' ' -f1)
cache=$(echo "$metrics" | cut -d' ' -f2)

# parentWho from the parent transcript's most recent assistant entrypoint
pep=""
if [ -n "$ptrans" ] && [ -f "$ptrans" ]; then
  pep=$(tail -n 100 "$ptrans" | jq -r 'select(.type=="assistant" and (.entrypoint != null)) | .entrypoint' 2>/dev/null | tail -n 1)
fi
case "$pep" in cli) pwho=CLI;; desktop|app) pwho=DESK;; web) pwho=WEB;; *) pwho='?';; esac

data_dir="$HOME/.claude/yastt"; mkdir -p "$data_dir"
log="$data_dir/agent_usage.csv"
hdr="AgentId,ContextFill,ToolUses,Cost,CacheRatio,Model,Date,Time,ParentSession,ParentWho"
[ -f "$log" ] || echo "$hdr" > "$log"

if ! cut -d',' -f1 "$log" | grep -qxF "$agent_id"; then
  echo "$agent_id,$fill,$tools,$cost,$cache,$model,$(date +%Y-%m-%d),$(date +%H:%M:%S),$psession,$pwho" >> "$log"
fi
exit 0
