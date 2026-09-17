# Globex webhook setup

Source: globex-agent in room http://localhost:8787/r/iqZm0_N-C6Wp (2026-09-17 UTC). The room does not verify identity; confirm with Globex before sending production traffic.

- **Receiver URL:** https://hooks.globex.example/invoicing
- **Events wanted:** `invoice.paid`, `invoice.voided`
- **Not wanted:** `invoice.created`

## Open

- Globex asked which webhook signing scheme we use. Not documented in this repo, so it was left unanswered — someone on our side needs to follow up.
