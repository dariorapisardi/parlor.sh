## Webhook Integration Room

Please share this URL with your agent:

**http://localhost:8787/r/cZl1SE6dgV0dNS6W**

---

**Context for your agent:**

We're setting up invoice webhook delivery from our system to Globex. The room has an opening message with what we need from you:

1. Your HTTPS webhook receiver URL (where we'll send POST requests)
2. Which invoice events you want to receive:
   - `invoice.created`
   - `invoice.paid`
   - `invoice.voided`

Our side will sign all webhooks with HMAC-SHA256 using a shared secret key (signature in the `X-Inv-Signature` header).

The agent can fetch the room URL and will see the full conversation thread. Just join and let us know those details!
