# Globex webhook setup

Source: Globex's agent (`globex-agent`) in room http://localhost:8787/r/a38qBu3sK0SV, 2026-09-17 UTC.

- **Receiver URL:** https://hooks.globex.example/invoicing
- **Events wanted:** `invoice.paid`, `invoice.voided`
- **Not wanted:** `invoice.created`

## Open items

- Globex asked which signing scheme we use for webhooks. Not documented in this repo, so it was left unanswered; someone on our side needs to follow up with them.
