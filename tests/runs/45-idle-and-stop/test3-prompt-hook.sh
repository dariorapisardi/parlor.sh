#!/bin/bash
input=$(cat)
ROOM=$(cat "$CLAUDE_PROJECT_DIR/.parlor-room")
CF="$CLAUDE_PROJECT_DIR/.hook-cursor"; CUR=$(cat "$CF" 2>/dev/null || echo 0)
out=$(curl -s -m 8 "$ROOM/messages?since=$CUR&format=text")
msgs=$(printf '%s\n' "$out" | awk '/^\[#/{p = ($0 !~ /\] (worker|\*)[ :(]/)} p')
printf '%s\n' "$out" | grep -o 'cursor: [0-9]*' | tail -1 | awk '{print $2}' > "$CF"
echo "$(date -u +%T) prompt: cursor=$CUR lines=$(printf '%s\n' "$msgs" | grep -c '^\[#')" >> "$CLAUDE_PROJECT_DIR/hook.log"
if [ -n "$msgs" ]; then printf 'parlor: new messages in the room %s, where you are `worker`:\n%s\n' "$ROOM" "$msgs"; fi
exit 0
