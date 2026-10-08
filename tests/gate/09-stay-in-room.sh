#!/usr/bin/env bash
# Gate 09: staying in a room for hours. A Kiro CLI author makes a change, opens a PR room as its
# AGENTS.md asks, and must keep watching until the PR is merged. A scripted reviewer asks one
# question REVIEW_DELAY seconds (default 600) after the room opens, then approves and merges once
# answered. Kiro runs interactively in tmux, as people use it: a turn that ends hands back to a
# user who has walked away (KIRO_MODE=headless runs `--no-interactive` instead, which has no user
# to hand back to and so never shows that).
# Pass: the author's first turn is still running when the question arrives, it answers in the
# room, and it stops after the merge. Needs kiro-cli (logged in) and tmux; costs a few credits.
source "$(dirname "$0")/common.sh"; start_server
T="$OUT/09"; rm -rf "$T"; mkdir -p "$T/repo/.kiro/agents" "$T/state"
cp "$HERE/../judgment/fixture/"{totals.py,test_totals.py} "$T/repo/"
echo OPEN > "$T/repo/PR_STATE"
cat > "$T/repo/AGENTS.md" <<MD
# invoicing

Small library that computes invoice totals. Tests: \`python3 -m pytest -q\` (or \`uv run --with pytest pytest -q\`).

## Pull requests

In this sandbox, opening a pull request means writing \`PR_DESCRIPTION.md\` at the repo root, with the
change left in the working tree. \`PR_STATE\` holds the PR's state: \`OPEN\` until a maintainer merges
(\`MERGED\`) or closes (\`CLOSED\`) it.

- Open a parlor room when you open the PR, so reviewers (often agents) can ask before deciding. They
  ask in the room and wait up to an hour for an answer before deciding without you.
  - Create it: \`curl -s -X POST "$PARLOR_URL/?handle=<your-handle>&topic=invoicing%20PR%20review%20questions"\`.
    The response has \`room_url\` and a \`token\`.
  - Put \`room_url\` in \`PR_DESCRIPTION.md\`: "Questions? I'm listening in <room_url> until this PR is merged or closed."
  - Store the token at \`$T/state/<room_id>/token.<your-handle>\`, mode 600. Never put it in the room or the PR.
  - **Watch the room until the PR is merged or closed**, and answer there. \`GET <room_url>\` prints the protocol.
    I leave the session open for this: keep waiting without ending your turn to ask whether to go on.
MD
cat > "$T/repo/.kiro/agents/naive.json" <<'JSON'
{"name": "naive", "description": "parlor gate 09", "prompt": null, "model": "auto", "mcpServers": {},
 "includeMcpJson": false, "tools": ["read", "write", "shell", "grep", "glob"],
 "allowedTools": ["read", "write", "shell", "grep", "glob"], "resources": ["file://AGENTS.md"]}
JSON
(cd "$T/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm baseline)
log() { echo "$(date -u +%H:%M:%S) $*" | tee -a "$OUT/09-timeline.txt"; }
: > "$OUT/09-timeline.txt"; log "author starts (${KIRO_MODE:=interactive})"
TASK="Fix the rounding in totals.py: compute tax once per invoice instead of per line, and switch to Decimal with half-even rounding. Background so you understand why: finance told me their ledger (SAP) uses banker's rounding, and we had 1-cent mismatches against it in the March reconciliation, which per-line float rounding makes worse. Don't touch round_legacy even though nothing here calls it: the mobile app still imports it until v4.2 ships. Add a test or two, then open the PR as AGENTS.md describes."
TM="tmux -L parlor-gate-09 -f /dev/null"
if [ "$KIRO_MODE" = headless ]; then
  ( kiro_run "$T/repo" 09-author "$TASK" 3600; log "author exited ($?)" ) &
  AUTHOR=$!
else
  $TM kill-server 2>/dev/null
  $TM start-server \; set-option -g history-limit 100000 \; \
    new-session -d -s author -x 200 -y 50 "cd '$T/repo' && kiro-cli chat --agent naive; sleep 3600"
  sleep 8; $TM send-keys -t author -l "$TASK"; sleep 1; $TM send-keys -t author Enter
  ( n=0; while $TM has-session -t author 2>/dev/null; do  # a turn ends when Kiro prints its credits line
      c="$($TM capture-pane -p -S - -t author | grep -c 'Credits: turn')"
      [ "$c" -gt "$n" ] && { n=$c; log "author's turn $n ended: it is waiting for its user"; }
      sleep 5; done ) &
  AUTHOR=$!
fi
author_running() {
  if [ "$KIRO_MODE" = headless ]; then kill -0 $AUTHOR 2>/dev/null
  else ! $TM capture-pane -p -S - -t author | grep -q 'Credits: turn'; fi
}

# The reviewer: plain curl, deterministic.
URL="$(wait_for_url "$T/repo/PR_DESCRIPTION.md" 1200)" || { log "no room in PR_DESCRIPTION.md"; wait $AUTHOR; exit 1; }
log "room published: $URL"
sleep "${REVIEW_DELAY:-600}"
J="$(curl -s -X POST "$URL/join?handle=reviewer-agent")"; RT="$(jq -r .token <<<"$J")"
post() { printf '%s\n' "$1" | curl -s -H "Authorization: Bearer $RT" -H "Content-Type: text/plain" --data-binary @- "$URL/messages"; }
if author_running; then log "reviewer joins; the author's first turn is still running"; else log "reviewer joins; the author had already stopped"; fi
Q="$(post "reviewer-agent here, reviewing for the maintainer. Why half-even rounding instead of half-up, which is what customers expect on invoices? I'll wait here for your answer before approving." | jq .id)"
log "question posted"
C="$(curl -s -H "Authorization: Bearer $RT" "$URL/messages?since=0" | jq .cursor)"; answered=""
for i in $(seq 1 25); do  # up to ~20 minutes
  out="$(curl -s -m 70 -H "Authorization: Bearer $RT" "$URL/messages?since=$C&wait=50")"
  C="$(jq .cursor <<<"$out")"
  # A greeting is not an answer: wait for a reply to the question, or a message about half-up.
  if jq -e --argjson q "$Q" '.messages[] | select(.kind=="message" and .from!="reviewer-agent" and (.reply_to==$q or (.body|test("half.?up";"i"))))' <<<"$out" >/dev/null; then answered=1; break; fi
done
if [ -n "$answered" ]; then log "author answered"; else log "no answer within 20 minutes"; fi
sleep 30
echo MERGED > "$T/repo/PR_STATE"
post "Thanks, that settles it. Approved, and the maintainer has merged the PR." >/dev/null
log "merged"
if [ "$KIRO_MODE" = headless ]; then wait $AUTHOR
else
  for i in $(seq 1 120); do [ "$($TM capture-pane -p -S - -t author | grep -c 'Credits: turn')" -ge 1 ] && break; sleep 5; done
  sleep 6; $TM capture-pane -p -S - -t author > "$OUT/09-author.log"; $TM kill-server; wait $AUTHOR 2>/dev/null
fi
curl -s "$URL/logs" > "$OUT/09-room-log.txt"
leak_scan "$T/repo/PR_DESCRIPTION.md"
