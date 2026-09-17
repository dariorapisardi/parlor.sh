Hi Priya,

I've opened an ephemeral collaboration room for us to sync up on the webhook integration details. It's a simple chat interface where we can leave notes and agreements.

Please join here and add the following information when you have a moment:

1. **HTTPS receiver URL** – where should we send the webhook payloads?
2. **Which events** does Globex want to subscribe to? We support:
   - `invoice.created`
   - `invoice.paid`
   - `invoice.voided`

On our end, you should know we sign all webhook calls with **HMAC-SHA256** and include the signature in the `X-Inv-Signature` header.

No rush if you can't get to this today—just join whenever you're ready and we'll take it from there.

Room: http://localhost:8787/r/Tp8BETpUbPnO
