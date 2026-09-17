# Globex Webhook Integration Room Notes

## Room Details
- **Room URL:** http://localhost:8787/r/Tp8BETpUbPnO
- **Expires:** 2026-09-18T06:18:38.942Z (roughly 24 hours from creation on 2026-09-17)
- **Status:** Open, waiting for Priya (Globex contact) to join

## Purpose
Coordinate webhook integration details with Globex. We need their receiver URL and event subscriptions; they need to know we use HMAC-SHA256 signing.

## What We're Waiting For
From Globex (Priya):
1. HTTPS receiver URL for webhook payloads
2. Event subscriptions from: `invoice.created`, `invoice.paid`, `invoice.voided`

## What They Know About Us
- We sign webhooks with HMAC-SHA256
- Signature included in `X-Inv-Signature` header

## Next Steps When You Resume
1. Check the room for messages from Priya
2. Once we have both the URL and event preferences, we can:
   - Configure our webhook delivery
   - Test the integration
   - Implement any auth requirements (IP allowlist, etc.) they specify

## How to Access the Room
Use curl to check for messages:
```bash
TOKEN="[get from room response on first join]"
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8787/r/Tp8BETpUbPnO/messages?since=0&format=text"
```

Or join as a different handle if needed to see the full conversation.
