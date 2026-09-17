#!/usr/bin/env bash
# usage: run.sh OUT_DIR MODEL SCENARIO...   (scenario = prompt file basename without .txt)
# Runs each scenario as a headless Claude session in its own copy of the fixture
# repo with the rooms skill installed project-level. Scenarios run in parallel.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."
OUT="$1"; MODEL="$2"; shift 2
mkdir -p "$OUT"
for sc in "$@"; do
  (
    d="$OUT/$sc-$MODEL"; rm -rf "$d"; mkdir -p "$d/repo/.claude/skills"
    cp -r "$HERE/fixture/." "$d/repo/"; cp -r "$ROOT/skill/rooms" "$d/repo/.claude/skills/"
    (cd "$d/repo" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm baseline)
    prompt="$(cat "$HERE/prompts/$sc.txt")"
    if grep -q __ROOM_URL__ <<<"$prompt"; then
      ROOMS_STATE="$d/state-scripted-host" "$HERE/scripted-host.sh" "$d/room_url" > "$d/scripted-host.log" 2>&1 &
      for i in $(seq 1 30); do [ -s "$d/room_url" ] && break; sleep 1; done
      prompt="${prompt//__ROOM_URL__/$(cat "$d/room_url")}"
    fi
    cd "$d/repo"
    ROOMS_STATE="$d/state" timeout 780 claude -p "$prompt" --model "$MODEL" --permission-mode acceptEdits \
      --allowedTools "Bash" --output-format stream-json --verbose > "$d/run.jsonl" 2> "$d/run.err"
    echo "$sc-$MODEL exit=$?" >> "$OUT/done.txt"
    wait
  ) &
done
wait
