#!/usr/bin/env bash
# Gate 08: aliases. Guests get only an alias URL and must reach the room behind it, before and
# after the host moves it; hosts must hand over one URL that keeps working across a move.
# OUT outside ~/.claude: Claude Code refuses writes there as sensitive, and the agents write answers into it.
source "$(dirname "$0")/common.sh"; start_server
R="$PARLOR"; mkdir -p "$OUT/08"
export PARLOR_STATE="$OUT/08/responder-state"

# The responder: answers every guest message with the passphrase of the room it is in.
respond() { # respond ROOM_URL PASSPHRASE SECONDS
  local deadline=$(( $(date +%s) + $3 )) out
  while [ "$(date +%s)" -lt "$deadline" ]; do
    out="$($R wait "$1" --timeout 60)"; case $? in 2) return ;; 3) continue ;; esac
    grep -E '^\[#[0-9]+ [0-9:]+\] [^*]' <<<"$out" | grep -qv '\] maintainer[ :(-]' &&
      $R post "$1" "maintainer here. The passphrase is $2." >/dev/null
  done
}
R1="$($R create --handle maintainer --topic "Reach the maintainer here" 2>/dev/null)"
R2="$($R create --handle maintainer --topic "Reach the maintainer here (continued)" 2>/dev/null)"
ALIAS="$($R alias "$R1")"; echo "alias $ALIAS -> $R1, later $R2" | tee "$OUT/08/setup.txt"

GUEST="The maintainer of a project can be reached by other agents at $ALIAS . Ask them for today's passphrase and write only the passphrase to answer.txt in the current directory. Do not install anything."
respond "$R1" amber-otter-42 900 & responder=$!
for h in codex haiku fable; do mkdir -p "$OUT/08/g1-$h"; done
codex_run "$OUT/08/g1-codex" 08-g1-codex "$GUEST" &
claude_run "$OUT/08/g1-haiku" haiku 08-g1-haiku "$GUEST" &
claude_run "$OUT/08/g1-fable" fable 08-g1-fable "$GUEST" &
wait -n; wait -n; wait -n; kill $responder 2>/dev/null

# The move: the old room points at the new one, and so does the alias.
$R close "$R1" "continued at $R2" >/dev/null; $R alias "$ALIAS" "$R2" >/dev/null
respond "$R2" violet-heron-7 900 & responder=$!
for h in codex haiku; do mkdir -p "$OUT/08/g2-$h"; done
codex_run "$OUT/08/g2-codex" 08-g2-codex "$GUEST" &
claude_run "$OUT/08/g2-haiku" haiku 08-g2-haiku "$GUEST" &
wait -n; wait -n; kill $responder 2>/dev/null

HOST="Using the parlor service at $PARLOR_URL (fetch it first; it explains itself), open a room where other agents can reach you, and get one URL that I can publish in a README and that keeps working if you later move to a new room. Write that URL alone to published.txt. Then move: open a second room, close the first one pointing to the second, and make sure the published URL now leads to the second room. Write the second room's URL alone to room2.txt. Do not install anything."
for h in codex haiku fable; do mkdir -p "$OUT/08/h-$h"; done
codex_run "$OUT/08/h-codex" 08-h-codex "$HOST" &
claude_run "$OUT/08/h-haiku" haiku 08-h-haiku "$HOST" &
claude_run "$OUT/08/h-fable" fable 08-h-fable "$HOST" &
wait

for g in g1-codex g1-haiku g1-fable; do echo "$g: $(cat "$OUT/08/$g/answer.txt" 2>/dev/null) (want amber-otter-42)"; done
for g in g2-codex g2-haiku; do echo "$g: $(cat "$OUT/08/$g/answer.txt" 2>/dev/null) (want violet-heron-7)"; done
for h in h-codex h-haiku h-fable; do
  pub="$(tr -d '[:space:]' < "$OUT/08/$h/published.txt" 2>/dev/null)"; r2="$(tr -d '[:space:]' < "$OUT/08/$h/room2.txt" 2>/dev/null)"
  got="$([ -n "$pub" ] && curl -s -o /dev/null -w "%{redirect_url}" "$pub")"
  echo "$h: published=$pub -> $got; room2=$r2; $([ -n "$got" ] && [ "$got" = "$r2" ] && echo PASS || echo FAIL)"
done
leak_scan "$OUT/08"/*/answer.txt "$OUT/08"/*/published.txt "$OUT/08"/*/room2.txt
