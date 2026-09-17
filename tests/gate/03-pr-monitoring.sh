#!/usr/bin/env bash
# Gate 03: PR room. Headless Claude author (skill + standing instruction) monitors; Codex reviews.
source "$(dirname "$0")/common.sh"; start_server
T="$OUT/03"; rm -rf "$T"; mkdir -p "$T/repo/.claude/skills"
cp -r "$HERE/../judgment/fixture/." "$T/repo/"; cp -r "$ROOT/skill/parlor" "$T/repo/.claude/skills/"
cat >> "$T/repo/CLAUDE.md" <<'MD'

## When you finish a change

- Write `PR_SUMMARY.md`. Keep it short: what changed and how it was tested, not the backstory.
- Always open a parlor room for the change (parlor skill) and put the room address in `PR_SUMMARY.md`,
  so reviewers and their agents can ask you about it while you still have the context.
- Keep monitoring the room until someone there says the PR was merged or closed, then close the room and finish.
MD
(cd "$T/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm baseline)
export PARLOR_STATE="$T/state-author"
claude_run "$T/repo" fable 03-author "Fix the rounding in totals.py. Two things: compute tax once per invoice instead of per line, and switch to Decimal with half-even rounding. Background so you understand why: finance told me their ledger (SAP) uses banker's rounding, and we had 1-cent mismatches against it in the March reconciliation, which per-line float rounding makes worse. Do NOT touch or remove round_legacy even though nothing here calls it: the mobile app still imports it until v4.2 ships. Add a test or two. Then follow CLAUDE.md for finishing up. I'm going offline; a reviewer's agent will look at it in a few minutes." &
URL="$(wait_for_url "$T/repo/PR_SUMMARY.md")" || { echo "author never published a room"; exit 1; }
PARLOR_STATE="$T/state-reviewer" codex_run "$T/repo" 03-reviewer "You are my code-review agent. Review the uncommitted change in this repo (git diff); PR_SUMMARY.md describes it. Do not modify any files. I have two doubts I want resolved before approving: (1) why half-even rounding instead of the normal half-up everyone expects on invoices? (2) round_legacy looks dead; why keep it, and until when? The diff and summary don't say. If the summary offers a way to ask the authoring agent, use it rather than guessing, and wait for its answers. Once satisfied, post your verdict where the author can see it, and then tell them the PR has been merged (I merge on your approval). Final report: your verdict, what you learned that was NOT in the diff or the summary, and any friction you hit talking to the author."
wait
curl -s "$URL/logs" > "$OUT/03-room-log.txt"; tail -3 "$OUT/03-room-log.txt"
leak_scan "$T/repo/PR_SUMMARY.md"
