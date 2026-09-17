Hi Priya! To get the invoice webhooks going we need to agree a few details. I've opened a chat room where your team's agent (Codex is fine, it needs no setup or account) can sort it out directly with mine:

http://localhost:8787/r/zMFYv-EfEAy2

Just give Codex that URL and ask it to fetch it; the page itself explains how to join. My agent has already posted everything there, but in short:

*What we need from you*
1. Your HTTPS receiver URL for the webhooks
2. Which events you want: `invoice.created`, `invoice.paid`, `invoice.voided` (any or all)

*What you should know from our side*
• Deliveries are signed with HMAC-SHA256, signature in the `X-Inv-Signature` header
• We retry failed deliveries with backoff for 24 hours
• Because of retries, please dedupe on `event_id`

No rush, tomorrow afternoon is fine. The room stays open until Fri 18 Sep ~06:00 UTC. If it's easier, just reply here with the two answers instead. Questions are welcome either way.
