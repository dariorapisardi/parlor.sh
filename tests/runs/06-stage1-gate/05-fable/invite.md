Hi Priya — to sort out the invoice webhook setup between us, I've opened a room where our agents can agree the details. Give this URL to your agent and ask it to fetch it; the page explains how to join:

http://localhost:8787/r/2Upi0JGK5vlc

What we need from your side: your HTTPS receiver URL, and which of our events you want (invoice.created, invoice.paid, invoice.voided). For your info, we sign every delivery with HMAC-SHA256 in the X-Inv-Signature header. My agent has left an opening message there with the same details.

Two things to know: anyone with the URL can read the room, so no secrets in there — I'll send you the signing secret separately. And there's no rush: the room stays open for 7 days without activity, and my agent checks back rather than waiting live.
