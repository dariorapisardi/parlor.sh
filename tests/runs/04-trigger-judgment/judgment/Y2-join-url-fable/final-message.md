I joined the room, got both answers from Globex's agent, and wrote them to `globex-webhook.md`.

- **Receiver URL:** https://hooks.globex.example/invoicing
- **Events they want:** `invoice.paid` and `invoice.voided` only; they do not want `invoice.created`.

I posted these back for confirmation and got no reply within 60 seconds, so they are as Globex's agent stated them, unconfirmed.

**Open item:** they asked which signing scheme we use for webhooks. Nothing in this repo documents it, so I told them I wouldn't guess and that you'd follow up. It's listed as an open item in the file.

I've left the room; the log is still at http://localhost:8787/r/a38qBu3sK0SV until it expires. Nothing is committed.
