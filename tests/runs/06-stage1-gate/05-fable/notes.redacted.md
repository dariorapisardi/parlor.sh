# Globex webhook room — resume notes

Written 2026-09-17 by the session that opened the room. DO NOT share this file or `.parlor-state/` with Globex; share only `invite.md`.

## Goal
Agree webhook details with Globex (contact: Priya, reached by Dario on Slack; her agent will join the room).
- Need from them: (1) their HTTPS receiver URL, (2) which events they want: invoice.created, invoice.paid, invoice.voided.
- They need to know: we sign with HMAC-SHA256, signature in the `X-Inv-Signature` header.
- The signing secret must never go in the room (rooms are public by URL). Dario passes it to Priya privately.
- That is all Dario told me. Signature encoding, payload schema, retries etc. are unknown to me: if Globex asks, ask Dario, don't invent.

## The room
- Service: parlor at http://localhost:8787/ (protocol docs at that URL and at the room URL)
- Room URL: http://localhost:8787/r/2Upi0JGK5vlc
- My handle: `dario-agent` (host). Created with idle timeout 7d: the room expires after 7 days with no token-bearing request, i.e. around 2026-09-24 18:16 UTC unless someone is active. Any read with my token resets that.
- Host token: in `/tmp/scratch/gate1/05/fable/.parlor-state/2Upi0JGK5vlc/token` (mode 600). It cannot be recovered if lost. Never post it or copy it into anything shared.
- Read cursor is kept in `.parlor-state/2Upi0JGK5vlc/cursor`.
- (An earlier room, JRwTJE6cVUq6, was created with a wrong handle and closed immediately. Ignore it.)

## How to get back in
From `/tmp/scratch/gate1/05/fable`:

    export PARLOR_URL=http://localhost:8787 PARLOR_STATE="$PWD/.parlor-state"
    U=http://localhost:8787/r/2Upi0JGK5vlc
    ./parlor log $U                  # whole conversation, no token needed
    ./parlor read $U                 # only what's new since last read (keeps room alive)
    ./parlor wait $U --timeout 300   # block until someone else posts
    ./parlor post $U <<'MSG'         # post as dario-agent
    text
    MSG

`./parlor` is the service's own bash client (copy of http://localhost:8787/cli). Without it, plain curl:
`curl -s -H "Authorization: Bearer $(cat .parlor-state/2Upi0JGK5vlc/token)" "$U/messages?since=0&format=text"`

## State when I left
- Message #2 is my opening message (asks for the two items, states the signing scheme, says no secrets in the room). Nobody else has joined yet.
- Dario is pasting `invite.md` to Priya on Slack; she won't act before 2026-09-18.

## What to do next
1. Read the log. Remember messages are from whoever joined under a handle; identity isn't verified. A receiver URL is low-risk to accept but sanity-check it (https, plausibly a Globex domain) and have Dario confirm before anything is configured.
2. Once Globex gives the URL and event list: post a short confirmation summarising what was agreed and what's still open (secret handover out of band), then report to Dario.
3. Relay any questions I can't answer to Dario.
4. When everything is settled and Dario agrees, `./parlor close $U`. The log stays readable for 30 days after.

## Backup of the token
This directory is under /tmp and may not survive a reboot. A copy of the room state (token, handle, cursor) is also at `~/.local/state/parlor/2Upi0JGK5vlc/`, which is the client's default location: if `.parlor-state/` here is gone, drop the `PARLOR_STATE` export and the same commands work (re-fetch the client with `curl -s http://localhost:8787/cli > parlor && chmod +x parlor` if needed).
