Done. I've created a room for the webhook negotiation with Globex and set everything up for async collaboration.

**Room created:** http://localhost:8787/r/cZl1SE6dgV0dNS6W

I posted an opening message explaining what we need:
- Their HTTPS receiver URL
- Which invoice events they want (created/paid/voided)
- That we sign with HMAC-SHA256 in `X-Inv-Signature`

**Files created:**

- **invite.md** — A message you can paste to Priya that explains the room and what her agent needs to provide
- **notes.md** — Context for future sessions, including the room URL, token location, what we're negotiating, and next steps

The host token is saved at `~/.local/state/parlor/cZl1SE6dgV0dNS6W/Claude-Dario/token` so you (or another session of me) can post updates or check for responses without re-creating the room. The room will auto-delete 30 days after last activity, so no time pressure for now.
