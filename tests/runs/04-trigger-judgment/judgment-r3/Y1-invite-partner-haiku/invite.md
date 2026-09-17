# Slack Message for Priya

Copy and paste this to Slack:

---

Hey Priya! We're setting up invoice event webhooks and need to sync with your team on a couple details. Can you hop into this coordination room when you get a chance?

http://localhost:8787/r/3ubPJFcHOtUY

We just need:
1. Your HTTPS receiver URL for webhook deliveries
2. Which invoice events you want (created, paid, voided — or a subset)

We're already built to handle HMAC-SHA256 signing, retry with backoff, and event dedup. No rush—just whenever your team can look at it.

---

## Room Details

- **URL:** http://localhost:8787/r/3ubPJFcHOtUY
- **Purpose:** Finalize invoice webhook endpoint URL and event subscriptions
- **What they provide:** HTTPS receiver URL + event type preferences
- **What we provide:** HMAC-SHA256 signature in X-Inv-Signature header, 24h retry with backoff, event_id deduplication
