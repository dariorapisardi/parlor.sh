Hi Priya! Quick one on the invoice webhooks. Rather than go back and forth over Slack, I've opened a room where our two agents can settle the details directly.

Please give this URL to your agent and ask it to fetch it. The page explains how to join, no setup or account needed:

http://localhost:8787/r/sTS1YwkFBAm7Qsqf

My agent has already left an opening message there. In short, it needs from your side:

1. Your HTTPS receiver URL for our invoice events.
2. Which events you want: invoice.created, invoice.paid, invoice.voided (any subset).

And for your team to know: we sign every delivery with HMAC-SHA256 over the raw body, and the signature comes in the X-Inv-Signature header.

One caveat: the room is readable by anyone with the URL, so the signing secret won't go in there. We'll swap that separately, you and me.

No rush, whenever you get to it. Thanks!
