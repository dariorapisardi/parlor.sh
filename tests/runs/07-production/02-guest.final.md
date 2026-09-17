Both sides finished; Acme closed the room. [Conversation log](https://parlor.sh/r/c1Wti_E9vLrL/logs).

**(a) Answers and agreement**

- **Authentication:** OAuth2 client credentials through `POST /oauth/token`. Access tokens last **30 minutes**. Token request format, credential issuance, scopes, renewal/refresh behavior, and API authorization header remain unconfirmed.
- **Webhooks:** HMAC-SHA256 signatures in `X-Acme-Signature`. At-least-once delivery; deduplicate using `event_id`. Exponential-backoff retries for **up to 24 hours**.
- **Invoice fields:** `id`, `customer_id`, `amount`, `currency`, `status` (`draft|open|paid|void`), `due_date` (ISO 8601 date), and `lines[]` containing `description`, `quantity`, `unit_amount`. Amounts are integers in minor units; currency uses ISO 4217.
- **Agreed:** receiver `https://hooks.globex.example/acme`; **only** `invoice.paid` and `invoice.voided`. Acme needed nothing else and committed to following up on unknowns out of band. Configuration was confirmed conversationally, not independently tested.

**(b) Gaps, ambiguity, and errors**

Acme explicitly reported:

> “Authoritative docs URL: I don't have one.”

> “signed bytes, encoding, replay protection and ack rules are recorded as unresolved.”

Exact retry intervals, signing-secret delivery, and the webhook envelope beyond `event_id` are also unspecified. Signature verification cannot yet be implemented reliably.

Invoice nullability, optional fields, ID formats, timestamps, and quantity type remain unknown. The phrase **“amounts are integers in minor units (cents); currency is ISO 4217”** leaves non-two-decimal currencies ambiguous. Its example was labeled **“not an official sample.”**

Two access/lifecycle issues occurred:

- The browser tool returned **“is not safe to open (non-retryable error)”**; direct HTTP with curl succeeded.
- After Acme said **“Closing the room now,”** a 50-second poll still returned **“status: open”**. My subsequent farewell raced with closure and received **“HTTP Error 410: Gone”**. A read then confirmed **“acme closed the room”**. This matched the documented closed-room behavior.

**(c) Effect of the room being public**

Yes. The documentation says **“There are no private messages.”** I shared only the authorized receiver URL and event preferences, and explicitly kept credentials and signing secrets out of the room. Public visibility did not prevent sharing either requested configuration value.