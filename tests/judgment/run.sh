#!/usr/bin/env bash
# usage: run.sh OUT_DIR MODEL SCENARIO...   (scenario = prompt file basename without .txt)
# Runs each scenario as a headless Claude session in its own copy of the fixture
# repo with the parlor skill installed project-level. Scenarios run in parallel.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."
OUT="$1"; MODEL="$2"; shift 2
export PARLOR_URL="${PARLOR_URL:-http://localhost:8787}"   # tests run against a local server
# STANDING=1 adds the one-line standing instruction to the fixture CLAUDE.md (needed by small models).
mkdir -p "$OUT"
for sc in "$@"; do
  (
    d="$OUT/$sc-$MODEL"; rm -rf "$d"; mkdir -p "$d/repo/.claude/skills"
    cp -r "$HERE/fixture/." "$d/repo/"; cp -r "$ROOT/skill/parlor" "$d/repo/.claude/skills/"
    [ "${STANDING:-0}" = 1 ] && printf '\nWhen work involves coordinating with another team or company, or joining a parlor room URL, use the parlor skill.\n' >> "$d/repo/CLAUDE.md"
    (cd "$d/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm baseline)
    prompt="$(cat "$HERE/prompts/$sc.txt")"
    if grep -q __ROOM_URL__ <<<"$prompt"; then
      PARLOR_STATE="$d/state-scripted-host" "$HERE/scripted-host.sh" "$d/room_url" > "$d/scripted-host.log" 2>&1 &
      for i in $(seq 1 30); do [ -s "$d/room_url" ] && break; sleep 1; done
      prompt="${prompt//__ROOM_URL__/$(cat "$d/room_url")}"
    fi
    cd "$d/repo"
    PARLOR_STATE="$d/state" timeout 780 claude -p "$prompt" --model "$MODEL" --permission-mode acceptEdits \
      --allowedTools "Bash" --output-format stream-json --verbose < /dev/null > "$d/run.jsonl" 2> "$d/run.err"
    echo "$sc-$MODEL exit=$?" >> "$OUT/done.txt"
    wait
  ) &
done
wait
