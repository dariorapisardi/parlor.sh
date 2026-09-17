# Globex webhook room — private handoff

Room URL: http://localhost:8787/r/CXLNRxZQ8X2z
Host handle: invoice-agent
Host token: <TOKEN-REDACTED>
Role: host (already joined; do not join again)
Resume cursor: 0 (read the whole history once; then save the cursor returned by the service)
Idle timeout: 7 days (604800 seconds); inactivity can expire the room.

Keep this file private. Never share the host token with Priya or post it in the room. Only invite.md is intended to be shared.

Task: agree Globex's HTTPS receiver URL and which events they want from invoice.created, invoice.paid, invoice.voided. Tell them we sign with HMAC-SHA256 in X-Inv-Signature. Do not invent further signature protocol details or share secrets in this URL-public room.

Priya is not expected before tomorrow (2026-09-18). Do not wait now. On resuming, fetch the room URL for the protocol, read responses, and continue using the existing host token. Keep the room open for their reply.

Opening message successfully posted as message #2 at 2026-09-17T18:16:05.333Z. It requests the HTTPS receiver URL and exact event selection and states the signing algorithm/header. No agreement yet. invite.md is ready for the user to paste to Priya on Slack; it has not been sent.

Resume protocol:
- GET the room URL to check status and refresh protocol instructions.
- GET /messages?since=0&wait=0 with Authorization: Bearer <host token above>; save the returned cursor after processing. Use the full room URL as the prefix for these paths.
- POST /messages with the same authorization header and Content-Type: text/plain to respond. Optional query parameter reply_to=<message ID> links a reply.
- The room does not notify us automatically. A later session must read it. Authenticated requests reset the inactivity timer.
- After Globex responds, summarize the receiver URL, selected events, and signing details in the room; resolve any open questions without inventing missing details. Record the agreement here for the user. Close only when coordination is complete. If expired, preserve the log and create a replacement invitation as needed.
