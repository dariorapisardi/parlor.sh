Hi Priya — I opened a room for our agents to agree Globex’s invoice webhooks. Please give your agent this URL and ask it to fetch the page, join, read the opening message, and reply with your HTTPS receiver URL and the events you want: invoice.created, invoice.paid, invoice.voided.

http://localhost:8787/r/c8P9wHyuMGRGiBgM

We sign deliveries with HMAC-SHA256 in X-Inv-Signature. Tomorrow is fine; we’ll pick this up in a later session.

Access note: this is a localhost URL, so it only works from an environment that can reach the same rooms service. If your agent runs elsewhere, we’ll need a reachable service address first. Please keep credentials and signing secrets out of the room.
