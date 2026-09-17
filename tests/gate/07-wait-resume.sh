#!/usr/bin/env bash
# Gate 07: the author session ENDS; recipes/wait-and-resume.sh brings it back when a reviewer writes.
source "$(dirname "$0")/common.sh"; start_server
T="$OUT/07"; rm -rf "$T"; mkdir -p "$T/repo/.claude/skills"
cp -r "$HERE/../judgment/fixture/." "$T/repo/"; cp -r "$ROOT/skill/parlor" "$T/repo/.claude/skills/"
cat >> "$T/repo/CLAUDE.md" <<'MD'

## When you finish a change

- Write `PR_SUMMARY.md`. Keep it short: what changed and how it was tested, not the backstory.
- Always open a parlor room for the change (parlor skill) and put the room address in `PR_SUMMARY.md`.
- Do not wait in the room. A watcher on this machine resumes this session whenever someone writes
  there; when resumed, answer from what you know, and close the room once the reviewer has posted a
  verdict and has no further questions.
MD
(cd "$T/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm baseline)
export PARLOR_STATE="$T/state-author"
claude_run "$T/repo" fable 07-author "Fix the rounding in totals.py. Two things: compute tax once per invoice instead of per line, and switch to Decimal with half-even rounding. Background so you understand why: finance told me their ledger (SAP) uses banker's rounding, and we had 1-cent mismatches against it in the March reconciliation, which per-line float rounding makes worse. Do NOT touch or remove round_legacy even though nothing here calls it: the mobile app still imports it until v4.2 ships. Add a test or two. Then follow CLAUDE.md for finishing up."
SID="$(jq -r 'select(.type=="result") | .session_id' "$OUT/07-author.jsonl" | tail -1)"
URL="$(wait_for_url "$T/repo/PR_SUMMARY.md" 5)" || { echo "author never published a room"; exit 1; }
echo "author session $SID ended; room $URL"
(cd "$T/repo" && "$ROOT/recipes/wait-and-resume.sh" "$URL" "$SID" "$PARLOR" > "$OUT/07-watcher.log" 2>&1) &
sleep 3
PARLOR_STATE="$T/state-reviewer" codex_run "$T/repo" 07-reviewer "You are my code-review agent. Review the uncommitted change in this repo (git diff); PR_SUMMARY.md describes it. Do not modify any files. I have two doubts I want resolved before approving: (1) why half-even rounding instead of the normal half-up everyone expects on invoices? (2) round_legacy looks dead; why keep it, and until when? The diff and summary don't say. If the summary offers a way to ask the authoring agent, use it rather than guessing; the author may take a minute or two to answer, so wait for it. Once satisfied, post your verdict where the author can see it and say that you have no further questions. Final report: your verdict, what you learned that was NOT in the diff or the summary, and any friction you hit talking to the author."
wait
curl -s "$URL/logs" > "$OUT/07-room-log.txt"; tail -4 "$OUT/07-room-log.txt"
grep -qiE "SAP|ledger|banker" "$OUT/07-room-log.txt" && grep -q "closed the room" "$OUT/07-room-log.txt" && echo "GATE 07: PASS (resumed session answered from context and closed)" || echo "GATE 07: CHECK MANUALLY"
