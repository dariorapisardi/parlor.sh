#!/usr/bin/env bash
# Amendment 2026-09-21: bounded rooms, remaining capacity on reads, the host's last word via close.
# Runnable without agents: bash tests/runs/18-caps.sh   (see TESTLOG entry 18)
# Small caps so the wall is reachable: MAX_BODY 100, MAX_ROOM_BYTES 400 (=> 300 for posts), MAX_MESSAGES 4 (=> 3 posts).
set -u
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
PORT="${PORT_OVERRIDE:-8795}"
pass=0; fail=0
ok(){ printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL %s  (%s)\n' "$1" "$2"; fail=$((fail+1)); }
J='content-type: application/json'
mk(){ # mk NAME ENV... -> starts a server, sets ID HTOK GTOK
  rm -rf "$S/cdata"; mkdir -p "$S/cdata"
  env PORT=$PORT HOST=127.0.0.1 DATA_DIR="$S/cdata" "$@" node "$REPO/server.mjs" > "$S/caps.log" 2>&1 &
  NODE=$!; sleep 0.8
  C=$(curl -s -X POST "localhost:$PORT" -H "$J" -d '{"topic":"caps","handle":"host"}')
  ID=$(printf '%s' "$C" | grep -o '/r/[A-Za-z0-9_-]*' | head -1 | cut -d/ -f3)
  HTOK=$(printf '%s' "$C" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  GTOK=$(curl -s -X POST "localhost:$PORT/r/$ID/join" -H "$J" -d '{"handle":"guest"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
}
stop(){ kill -TERM $NODE 2>/dev/null; wait $NODE 2>/dev/null; }
post(){ curl -s -o "$S/out" -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/messages" -H "authorization: Bearer $1" -H 'content-type: text/plain' --data-binary "$2"; }
hdr(){ curl -s -D - -o /dev/null -H "authorization: Bearer $HTOK" "localhost:$PORT/r/$ID/messages?since=0" | tr -d '\r' | grep -i "^$1:" | awk '{print $2}'; }
footer(){ curl -s -H "authorization: Bearer $HTOK" "localhost:$PORT/r/$ID/messages?since=0&format=text" | tail -1; }

echo "--- byte cap: MAX_ROOM_BYTES=400 MAX_BODY=100 (posts get 300) ---"
mk MAX_ROOM_BYTES=400 MAX_BODY=100 MAX_MESSAGES=0
[ "$(hdr x-room-bytes-left)" = 300 ] && ok "fresh room reports 300 bytes left (cap minus reserve)" || no "bytes-left header" "$(hdr x-room-bytes-left)"
hdr x-room-messages-left | grep -q . && no "no messages-left header when MAX_MESSAGES=0" "present" || ok "no messages-left header when MAX_MESSAGES=0"
footer | grep -q 'left: 300 bytes' && ok "footer shows 'left: 300 bytes'" || no "footer" "$(footer)"
curl -s "localhost:$PORT/r/$ID" | grep -q 'Space left for posts: 300 bytes' && ok "room page shows space left" || no "room page" "$(curl -s localhost:$PORT/r/$ID | grep -i 'space left')"
[ "$(hdr x-room-bytes-left)" = 300 ] && ok "guest join (system line) did not consume capacity" || no "system lines excluded" "$(hdr x-room-bytes-left)"
c=$(post $GTOK "$(printf 'a%.0s' $(seq 90))"); [ "$c" = 201 ] && ok "guest posts 90 bytes" || no "90-byte post" "$c $(cat $S/out)"
c=$(post $HTOK "$(printf 'b%.0s' $(seq 90))"); [ "$c" = 201 ] && ok "host posts 90 bytes" || no "host 90-byte post" "$c"
[ "$(hdr x-room-bytes-left)" = 120 ] && ok "120 bytes left after 180 posted" || no "arithmetic" "$(hdr x-room-bytes-left)"
c=$(post $GTOK "$(printf 'd%.0s' $(seq 101))"); [ "$c" = 413 ] && ok "413 over MAX_BODY" || no "413" "$c $(cat $S/out)"
c=$(post $GTOK "$(printf 'c%.0s' $(seq 100))"); [ "$c" = 201 ] && [ "$(hdr x-room-bytes-left)" = 20 ] && ok "a 100-byte post fits in 120; 20 left" || no "100 in 120" "$c left=$(hdr x-room-bytes-left)"
c=$(post $GTOK "$(printf 'e%.0s' $(seq 50))"); [ "$c" = 403 ] && grep -q 'does not fit' $S/out && grep -q '50 bytes; 20 remain' $S/out && ok "403 'message does not fit' with both numbers (50 into 20)" || no "does-not-fit hint" "$c $(cat $S/out)"
c=$(post $HTOK "z"); [ "$c" = 201 ] && ok "a smaller post from someone else still goes in (room was not 'full')" || no "small post" "$c"
c=$(post $GTOK "$(printf 'g%.0s' $(seq 19))"); [ "$c" = 201 ] && [ "$(hdr x-room-bytes-left)" = 0 ] && ok "room filled to exactly 0 left" || no "fill" "$c left=$(hdr x-room-bytes-left)"
c=$(post $GTOK "x"); [ "$c" = 403 ] && grep -q 'room is full' $S/out && grep -q 'Only the host can end it' $S/out && ok "guest: 403 room is full, hint names the host's close" || no "full hint guest" "$c $(cat $S/out)"
c=$(post $HTOK "x"); [ "$c" = 403 ] && grep -q 'room is full' $S/out && ok "host: also 403 on /messages (one rule for everyone)" || no "full host" "$c $(cat $S/out)"
# a guest waits; the host closes with a pointer; the guest gets it in the same response
CUR=$(hdr x-room-cursor)
curl -s -o "$S/guest.txt" -D "$S/guest.h" -H "authorization: Bearer $GTOK" "localhost:$PORT/r/$ID/messages?since=$CUR&wait=20&format=text" &
W=$!; sleep 0.5
c=$(curl -s -o $S/out -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/close" -H "authorization: Bearer $HTOK" -H 'content-type: text/plain' --data-binary 'continued at http://localhost/r/NEXTROOM')
[ "$c" = 200 ] && grep -q '"status":"closed"' $S/out && ok "close with body on a full room: 200 closed" || no "close full" "$c $(cat $S/out)"
wait $W
grep -q 'host: continued at http://localhost/r/NEXTROOM' $S/guest.txt && grep -q 'host closed the room' $S/guest.txt && grep -q 'status: closed' $S/guest.txt \
  && ok "waiting guest received pointer + close line + closed status in one response" || no "guest wake" "$(cat $S/guest.txt)"
L=$(curl -s "localhost:$PORT/r/$ID/logs" | grep -c 'continued at'); [ "$L" = 1 ] && ok "pointer is in the log once" || no "log" "$L"
footer | grep -q 'left:' && no "closed room shows no 'left:'" "$(footer)" || ok "closed room footer has no 'left:'"
stop

echo "--- message cap: MAX_MESSAGES=4 (posts get 3) ---"
mk MAX_MESSAGES=4 MAX_ROOM_BYTES=0
[ "$(hdr x-room-messages-left)" = 3 ] && ok "fresh room: 3 messages left (4 minus the host's)" || no "messages-left" "$(hdr x-room-messages-left)"
hdr x-room-bytes-left | grep -q . && no "no bytes-left header when MAX_ROOM_BYTES=0" "present" || ok "no bytes-left header when MAX_ROOM_BYTES=0"
for i in 1 2 3; do post $GTOK "m$i" >/dev/null; done
[ "$(hdr x-room-messages-left)" = 0 ] && ok "0 left after 3 posts; 'guest joined' did not count" || no "count" "$(hdr x-room-messages-left)"
c=$(post $GTOK "m4"); [ "$c" = 403 ] && grep -q 'room is full' $S/out && ok "4th post: 403 room is full" || no "4th" "$c"
c=$(curl -s -o $S/out -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/close" -H "authorization: Bearer $HTOK" -H "$J" -d '{"body":"last word, as JSON"}')
[ "$c" = 200 ] && curl -s "localhost:$PORT/r/$ID/logs" | grep -q 'host: last word, as JSON' && ok "close with JSON body on a count-full room" || no "close json" "$c $(cat $S/out)"
N=$(curl -s "localhost:$PORT/r/$ID/logs?format=jsonl" | grep -c '"kind":"message"'); [ "$N" = 4 ] && ok "room ends with exactly MAX_MESSAGES participant messages" || no "final count" "$N"
stop

echo "--- close in a room that is not full, and with no body ---"
mk MAX_MESSAGES=0 MAX_ROOM_BYTES=0
post $GTOK "hello" >/dev/null
c=$(curl -s -o $S/out -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/close" -H "authorization: Bearer $HTOK" -H 'content-type: text/plain' --data-binary 'wrapping up: agreed on X')
[ "$c" = 200 ] && curl -s "localhost:$PORT/r/$ID/logs" | grep -q 'host: wrapping up' && ok "close with body works in any room" || no "close any" "$c"
footer | grep -q 'left:' && no "unlimited room shows no 'left:'" "$(footer)" || ok "unlimited room: footer has no 'left:'"
stop
mk MAX_MESSAGES=0 MAX_ROOM_BYTES=0
c=$(curl -s -o $S/out -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/close" -H "authorization: Bearer $HTOK")
[ "$c" = 200 ] && [ "$(curl -s "localhost:$PORT/r/$ID/logs?format=jsonl" | grep -c '"kind":"message"')" = 0 ] && ok "close with no body: no message appended (unchanged)" || no "close empty" "$c"
c=$(curl -s -o $S/out -w '%{http_code}' -X POST "localhost:$PORT/r/$ID/close" -H "authorization: Bearer $GTOK" --data-binary 'redirect!')
[ "$c" = 403 ] && ok "guest cannot write the last word (403)" || no "guest close" "$c"
stop

echo "--- the client: parlor create, then parlor close URL TEXT ---"
mk MAX_MESSAGES=0 MAX_ROOM_BYTES=0
export PARLOR_STATE="$S/pstate"; rm -rf "$PARLOR_STATE"
CLI="$REPO/skill/parlor/parlor"
URL=$(PARLOR_URL="http://localhost:$PORT" bash "$CLI" create --handle host --topic caps 2>&1 | grep -o "http://localhost:$PORT/r/[A-Za-z0-9_-]*" | head -1)
[ -n "$URL" ] && ok "client created a room and stored the host token" || no "client create" "no URL"
out=$(PARLOR_URL="http://localhost:$PORT" bash "$CLI" close "$URL" "continued at http://x/r/Y" 2>&1)
printf '%s' "$out" | grep -q '"status":"closed"' && curl -s "$URL/logs" | grep -q 'host: continued at http://x/r/Y' && ok "client close with TEXT posts the last word" || no "client close" "$out"
stop

echo "  --- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
