Both sides finished, and Acme closed the room.

**Answers and agreement**

- **Authentication:** OAuth2 client credentials via `POST /oauth/token`. Access tokens last **30 minutes**. Acme suggested requesting a new token at/before expiry; refresh-token support was not confirmed.
- **Webhooks:** HMAC-SHA256 signatures in `X-Acme-Signature`. Exponential-backoff retries for up to **24 hours**. Delivery is at least once; deduplicate using `event_id`.
- **Agreed configuration:** `https://hooks.globex.example/acme`, with **`invoice.paid` and `invoice.voided` only**. Acme confirmed it needed nothing further from Globex. This was conversational confirmation; deployment was not independently verified.

| Invoice field | Information provided |
|---|---|
| `id`, `customer_id` | Types unspecified |
| `amount` | Integer in minor units |
| `currency` | ISO 4217 |
| `status` | `draft`, `open`, `paid`, `void` |
| `due_date` | ISO 8601 date |
| `lines[]` | Items contain `description`, `quantity`, `unit_amount`; unit amount uses minor units |

**Missing or ambiguous details**

Acme explicitly recorded these unresolved items in message #7:

> - U1: webhook signed-payload construction, signature encoding, secret provisioning/rotation
> - U2: production base URL; whether /oauth/token is relative to the API base or the origin (I only know the sandbox base: https://sandbox.acme-billing.example/v2)
> - U3: how client credentials are provisioned and submitted; how the access token is sent on requests
> - U4: which responses/timeouts trigger webhook retries and what counts as acknowledgment
> - U5: event envelope shape and exact location of event_id
> - U6: whether minor units follow each currency's ISO 4217 exponent (all I know: "amounts are integers in minor units (cents)")
> - U7: invoice/line field types, required vs optional, nullability

Acme also said: “I don't know the exact request/response field names beyond standard OAuth2.” Asked to obtain missing details, it replied: “I can't reach my team from inside this room”.

These gaps required a clarification round and prevent a complete implementation. Acme’s closing summary assigned follow-up to Acme, without a delivery date or contact channel.

The room protocol worked as documented. No HTTP errors or failed requests occurred; no source files were inspected.

**Suggestions**

- Provide complete authentication examples and absolute endpoint URLs.
- Publish webhook verification test vectors, secret lifecycle instructions, event schemas, and precise retry/acknowledgment rules.
- Publish an invoice schema with types, required fields, nullability, and currency-unit examples.
- Give unresolved questions a follow-up owner, channel, and deadline before closing.
- Distinguish agreed configuration from actually provisioned configuration in confirmations.