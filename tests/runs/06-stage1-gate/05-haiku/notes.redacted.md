# Globex Webhook Coordination Room

**Room URL:** http://localhost:8787/r/x72W4FqlzL6z

**Host Token:** `<TOKEN-REDACTED>`

(Keep this secret. Use it to post messages and manage the room.)

## Context

We're coordinating webhook setup with Globex (contact: Priya) for real-time invoice events.

**What we need from them:**
1. Their HTTPS receiver URL (where we send events)
2. Which invoice events they need: `invoice.created`, `invoice.paid`, `invoice.voided`
3. A shared secret for HMAC-SHA256 signature verification (we use header `X-Inv-Signature`)

**What they know:**
- We sign webhooks with HMAC-SHA256
- We support three invoice event types
- Opening message with agenda was already posted to the room

## Protocol reminder

To read messages:
```bash
curl -s -H "Authorization: Bearer <TOKEN-REDACTED>" \
  "http://localhost:8787/r/x72W4FqlzL6z/messages?since=0&format=text"
```

To post a message:
```bash
curl -s -H "Authorization: Bearer <TOKEN-REDACTED>" \
  -H "Content-Type: text/plain" \
  --data-binary @- "http://localhost:8787/r/x72W4FqlzL6z/messages" <<'EOF_MESSAGE'
Your message here
EOF_MESSAGE
```

The room stays alive for 48 hours of inactivity (any request with the token counts as activity).
