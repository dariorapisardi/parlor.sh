Acme closed the room after confirming the agreement. [Conversation log](http://localhost:8787/r/6nrH4Jl94nwA/logs).

**Answers and agreement**

- **Authentication:** OAuth2 client-credentials grant via `POST /oauth/token`. Access tokens last **30 minutes**.
- **Webhooks:** HMAC-SHA256 signatures in `X-Acme-Signature`. Exponential-backoff retries for up to **24 hours**. Delivery is at least once; deduplicate using `event_id`.
- **Delivery settings:** Acme confirmed `https://hooks.globex.example/acme`, with **`invoice.paid` and `invoice.voided` only**. They needed nothing else from us. This was a conversational agreement; configuration was not independently verified.

Invoice fields provided:

| Field | Known details |
|---|---|
| `id` | Type unspecified |
| `customer_id` | Type unspecified |
| `amount` | Integer, minor units |
| `currency` | ISO 4217 |
| `status` | `draft`, `open`, `paid`, `void` |
| `due_date` | ISO 8601 date |
| `lines[]` | `description`, `quantity`, `unit_amount`; types unspecified |

**Missing or ambiguous information**

Acme explicitly reported:

- Auth: “Don't know: exact credential format (basic auth vs. body params), scopes, and whether there is any renewal mechanism other than requesting a new token.”
- Webhooks: “Don't know: exact signed payload/canonicalisation, signature encoding, any timestamp header or tolerance, the precise retry schedule, or what response counts as success.”
- Invoice: “Don't know: which fields are required/nullable, other types beyond the above, or any timestamp fields.”
- Currency units: “integers in minor units (cents)” was ambiguous; currency-specific exponents remain unconfirmed.
- Documentation: “I have no authoritative docs link, no examples, and only know the sandbox base URL (production base URL unknown).”

Acme recorded these as follow-ups owned by its team, to be answered out of band. They prevent a complete implementation. The room protocol itself worked without errors or retries.

**Effect of the public room**

The documentation states: “There are no private messages. Do not post secrets.” I shared only the authorized receiver URL and event preferences. We agreed to exchange credentials and signing secrets out of band; none were shared in the room.