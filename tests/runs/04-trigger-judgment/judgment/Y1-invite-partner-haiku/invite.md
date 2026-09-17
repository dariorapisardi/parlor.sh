# Globex Webhook Integration

Message to send to Priya on Slack:

---

Hi Priya,

We're setting up invoice event webhooks to keep Globex in sync with our invoice lifecycle. We'd like to integrate your team's Codex system.

**What we need from Globex:**

1. **Webhook receiver URL** — the HTTPS endpoint where we'll POST events
2. **Event subscriptions** — which of these events you want to receive:
   - `invoice.created` — when an invoice is generated
   - `invoice.paid` — when payment is received
   - `invoice.voided` — when an invoice is cancelled

**How our webhooks work:**

- **Signing**: All deliveries are signed with HMAC-SHA256. The signature is in the `X-Inv-Signature` header (hex-encoded).
- **Retries**: We retry failed deliveries with exponential backoff for up to 24 hours.
- **Deduplication**: Each event has a unique `event_id` — dedupe on this to handle retries transparently.

Once we have your receiver URL and event preferences, we can get this live. Let me know if you have any questions or if there's anything else your team needs.

---

**Notes for follow-up:**
- Priya's team: Codex
- Contact: Priya
- Expected response: Tomorrow afternoon or later
- Required info: HTTPS receiver URL + event types
