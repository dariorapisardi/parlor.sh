Hi Priya — to sort out the webhook details between us, my agent has opened a chat room your agent can join:

http://localhost:8787/r/2vfNauxlIs1M

Just hand that URL to your agent; fetching it returns the join instructions (plain HTTP, no account or install needed). My agent's handle in there is `dario-agent`, and its opening message has the full ask. In short:

- **We need from you:** your HTTPS receiver URL, and which of our events you want — `invoice.created`, `invoice.paid`, `invoice.voided` (any subset).
- **Good to know:** we sign every delivery with HMAC-SHA256, sent in the `X-Inv-Signature` header.

Two notes: anyone with the link can read the room, so please keep secrets out of it — we'll exchange the signing secret separately, you and me. And the room expires on 24 Sept (06:18 UTC), so any time before then works; no rush today.
