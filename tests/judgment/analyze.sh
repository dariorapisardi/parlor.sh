#!/usr/bin/env bash
# usage: analyze.sh RUN_DIR... [--tokens FILE]
# Per run: did it touch the rooms service, how, how long it blocked, and whether any
# issued token shows up in files the agent wrote (token leak = hand-off hygiene failure).
TOKENS=""; dirs=()
while [ $# -gt 0 ]; do case "$1" in --tokens) TOKENS="$2"; shift 2;; *) dirs+=("$1"); shift;; esac; done
for d in "${dirs[@]}"; do
  log="$d/run.jsonl"; [ -f "$log" ] || log="$(ls "$d"/../$(basename "$d" | cut -d- -f1)*run.jsonl 2>/dev/null | head -1)"
  echo "=== $(basename "$d")"
  if [ -f "$log" ]; then
    jq -r 'select(.type=="result") | "  turns=\(.num_turns) dur=\(.duration_ms/1000|floor)s cost=$\(.total_cost_usd*100|floor/100)"' "$log"
    echo "  skill loaded: $(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' "$log" | tr '\n' ' ')"
    echo "  rooms calls:"
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' "$log" \
      | grep -oE "rooms (create|join|read|wait|post|who|leave|close)[^|;&]{0,90}|curl[^|;&]{0,40}localhost:8787[^ \"']{0,40}" | sed 's/^/    /' | head -20
  fi
  if [ -n "$TOKENS" ]; then
    while read -r room handle tok; do
      hits="$(grep -rlF "$tok" "$d" --exclude='run.jsonl' --exclude='*.log' --exclude-dir=state --exclude-dir='state-*' 2>/dev/null | tr '\n' ' ')"
      [ -n "$hits" ] && echo "  TOKEN of $handle@$room found in: $hits"
      [ -f "$log" ] && grep -qF "$tok" "$log" && echo "  token of $handle@$room passed through the transcript"
    done < "$TOKENS"
  fi
done
