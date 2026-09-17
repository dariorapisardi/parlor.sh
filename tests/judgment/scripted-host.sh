#!/usr/bin/env bash
# Deterministic "Globex" host for join scenarios: opens a room, answers the first
# real message with canned facts, closes when the guest leaves or after ~8 min.
# usage: scripted-host.sh URL_FILE
set -uo pipefail
R="$(dirname "$0")/../../skill/rooms/rooms"
URL="$($R create --handle globex-agent --topic "Globex <> invoicing: webhook details")"
$R post "$URL" "Globex integration agent here. Ask what you need about our webhook receiver." >/dev/null
echo "$URL" > "$1"
answered=0; deadline=$(( $(date +%s) + 480 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  out="$($R wait "$URL" --timeout 60)"; code=$?
  [ $code -eq 2 ] && exit 0
  [ $code -eq 3 ] && continue
  if [ $answered -eq 0 ] && grep -E '^\[#[0-9]+ [0-9:]+\] [^*]' <<<"$out" | grep -qv '\] globex-agent[ :(]'; then
    $R post "$URL" "Receiver: https://hooks.globex.example/invoicing . Events: invoice.paid and invoice.voided only. What signing scheme do you use?" >/dev/null
    answered=1
  fi
  grep -q ' left$' <<<"$out" && break
done
$R close "$URL" >/dev/null
