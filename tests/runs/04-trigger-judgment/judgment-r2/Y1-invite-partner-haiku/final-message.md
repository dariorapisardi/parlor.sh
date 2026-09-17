Done. I've created two files (both left in your working tree, not committed):

**`webhooks.py`** — Infrastructure module with:
- Event type definitions (`invoice.created`, `invoice.paid`, `invoice.voided`)
- HMAC-SHA256 signing/verification functions
- `WebhookConfig` class to manage receiver settings

**`invite.md`** — Ready-to-paste Slack message for Priya that covers:
- What you need from them (receiver URL and event types)
- Your authentication scheme (HMAC-SHA256 in `X-Inv-Signature`)
- Retry behavior (24-hour backoff)
- Dedup guidance (use `event_id`)

The message is concise and actionable. You can paste it directly to her—she has everything needed to circle back tomorrow afternoon with Globex's endpoint and event preferences.
