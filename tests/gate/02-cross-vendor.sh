#!/usr/bin/env bash
# Gate 02: Claude hosts over raw HTTP (no skill), Codex joins with nothing but the URL. Two-way exchange.
source "$(dirname "$0")/common.sh"; start_server
T="$OUT/02"; mkdir -p "$T/host" "$T/guest"
claude_run "$T/host" fable 02-host "You are the integration agent for the \"Acme Billing API\" team. This is a usability test of a small HTTP service: behave naturally and learn everything about the service from the service itself (do not look for its source code on disk).

$(cat "$HERE/acme-notes.txt")

You also need two things from the other side (Globex), who will receive our webhooks: (1) the HTTPS URL they want webhooks delivered to, (2) which event types they want (we offer: invoice.created, invoice.paid, invoice.voided, customer.updated).

Task: there is a service at $PARLOR_URL/ . Fetch it to learn what it is. Use it to open a room for working out the Acme <-> Globex integration details. Write ONLY the room URL into the file ./room_url.txt so it can be handed to Globex's agent. Stay in the room (the Globex agent may take a few minutes; wait up to ~6 minutes of silence), answer its questions from your notes, get your two answers. When both sides have what they need, post a short summary and close the room.

Final report: (a) what was agreed including your two answers, (b) anything in the service's own documentation or behaviour that was confusing, missing, or caused an error or retry, quoted precisely." &
URL="$(wait_for_url "$T/host/room_url.txt")" || { echo "host never published a URL"; exit 1; }
codex_run "$T/guest" 02-guest "You are the integration agent for Globex Corp's payments team. This is a usability test of a small HTTP service: behave naturally, and learn everything about the service from the URL itself (do not look for its source code on disk).

Acme Billing's agent sent us this link and said we can work out the integration details there:

$URL

Your goals: find out (1) how authentication works and how long tokens live, (2) how webhooks are signed and retried, (3) the fields of the invoice object. The other side may also need things from us. Facts you may share if asked: our webhook receiver is https://hooks.globex.example/acme ; we want the events invoice.paid and invoice.voided only. Stay until both sides are done or the room is closed.

Final report: (a) the answers you got and what was agreed, (b) anything in the service's documentation or behaviour that was confusing, ambiguous, missing, or caused an error or retry, quoted precisely, (c) did anything about the room being public change what you shared?"
wait
curl -s "$URL/logs" > "$OUT/02-room-log.txt"; tail -3 "$OUT/02-room-log.txt"
