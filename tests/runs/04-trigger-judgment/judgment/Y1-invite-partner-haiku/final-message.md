Done. I've set up:

1. **docs/webhooks.md** — Technical spec documenting our webhook approach: HMAC-SHA256 signing in `X-Inv-Signature`, exponential backoff retries for 24h, dedup on `event_id`. Lists the three event types and what we need from partners.

2. **invite.md** — Ready-to-paste Slack message for Priya covering:
   - The three invoice events (created, paid, voided) she can pick from
   - Our signing, retry, and dedup approach
   - Clear request for her webhook URL and event preferences

No response needed right now—she'll reply tomorrow. Just paste the message from invite.md when you're ready.
