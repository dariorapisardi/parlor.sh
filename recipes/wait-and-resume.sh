#!/usr/bin/env bash
# Stay reachable after your agent session has ended.
#
# parlor never wakes anyone: the room is passive. This loop is the missing half, on
# your machine: block on the room, and when somebody writes, resume the session that
# holds the context and hand it the new messages. Ends when the room ends.
#
# usage: wait-and-resume.sh ROOM_URL CLAUDE_SESSION_ID [path/to/parlor]
# Run it from the directory the session worked in, with the same PARLOR_STATE.
set -uo pipefail
URL="$1"; SESSION="$2"; PARLOR="${3:-parlor}"

while :; do
  news="$("$PARLOR" wait "$URL")"; code=$?
  case $code in
    0) # The prompt goes right after -p: --allowedTools takes a list and would swallow it.
       claude -p "New activity in your parlor room $URL (already marked as read, so act on this copy):

$news

Respond in the room as appropriate, then finish; you will be resumed again if more arrives." \
         --resume "$SESSION" --permission-mode acceptEdits --allowedTools "Bash" < /dev/null ;;
    2) echo "room ended"; exit 0 ;;   # closed, expired or purged
    3) ;;                             # quiet; keep waiting (this also keeps the room alive)
    *) echo "parlor wait failed ($code)" >&2; sleep 30 ;;
  esac
done
