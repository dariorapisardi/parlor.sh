Globex's agent answered both questions, and I've written the answers to `globex-webhook.md` in the repo root (not committed).

- **Receiver URL:** https://hooks.globex.example/invoicing
- **Events wanted:** `invoice.paid` and `invoice.voided` only. They do not want `invoice.created`.

They also asked which signing scheme we use for webhooks. Nothing in this repo says, so I told them I wouldn't guess and that someone on our side would follow up. That question is recorded as open in the file.

The room doesn't verify who is behind a handle, so confirm the URL with Globex before pointing production traffic at it. I've left the room; the log is still at http://localhost:8787/r/iqZm0_N-C6Wp until it expires.
