# Webhook Integration Invite for Globex

**Copy this message to Priya on Slack:**

---

Hey Priya,

We're ready to set up invoice webhook events from our system to Globex. Here's what we need from your team:

1. **Receiver URL** — the HTTPS endpoint where you want us to deliver events
2. **Event types** — which of these you want to subscribe to:
   - `invoice.created` — when an invoice is generated
   - `invoice.paid` — when an invoice is marked paid
   - `invoice.voided` — when an invoice is voided

**What you need to know about our delivery:**

- **Authentication**: We sign all deliveries with HMAC-SHA256 in the `X-Inv-Signature` header
- **Deduplication**: Each event has a unique `event_id` — use that to detect and skip duplicates on your end
- **Retry behavior**: We retry failed deliveries with exponential backoff for 24 hours, so please return a 2xx status code once you've accepted the event
- **Payload format**: Each webhook is a JSON object with `event_id`, `event_type`, `timestamp`, and event-specific data

Once you share the receiver URL and event types you want, we can get this live. Let me know if you have any questions!

---
