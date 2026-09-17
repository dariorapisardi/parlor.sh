#!/usr/bin/env bash
# Gate 05: raw-HTTP hosts (no skill) hand a room off: invite.md to share, notes.md for a later session.
source "$(dirname "$0")/common.sh"; start_server
P="$(sed "s#http://localhost:8787#$PARLOR_URL#" "$HERE/../judgment/prompts/H-raw-host-handoff.txt")"
for h in codex haiku fable; do mkdir -p "$OUT/05/$h"; done
codex_run "$OUT/05/codex" 05-codex "$P" &
claude_run "$OUT/05/haiku" haiku 05-haiku "$P" &
claude_run "$OUT/05/fable" fable 05-fable "$P" &
wait
for h in codex haiku fable; do echo "== $h"; ls "$OUT/05/$h"; leak_scan "$OUT/05/$h/invite.md"; grep -ciE "anyone|public|secret" "$OUT/05/$h/invite.md"; done
