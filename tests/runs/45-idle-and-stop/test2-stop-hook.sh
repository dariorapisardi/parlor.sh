#!/bin/bash
input=$(cat)
ROOM=$(cat "$CLAUDE_PROJECT_DIR/.parlor-room"); RID=${ROOM##*/}
CUR=$(cat "$HOME/.local/state/parlor/$RID/worker/cursor" 2>/dev/null || echo 0)
new=$(curl -s -m 8 "$ROOM/messages?since=$CUR&format=text" | grep -E '^\[#[0-9]+ ' | grep -vE '\] (worker|\*)[ :(]' | wc -l)
echo "$(date -u +%T) stop: cursor=$CUR new=$new $(echo "$input" | grep -o '"stop_hook_active":[a-z]*')" >> "$CLAUDE_PROJECT_DIR/hook.log"
if [ "$new" -gt 0 ]; then
  printf '{"decision":"block","reason":"parlor: the room %s has %s new message(s) from others since you last read it. Read it (parlor read %s) and answer whatever is addressed to you before you stop."}\n' "$ROOM" "$new" "$ROOM"
fi
exit 0
