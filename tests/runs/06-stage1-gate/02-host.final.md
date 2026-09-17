Both of my answers came in from Globex and the room is now closed. The summary was posted as message #7 and the full log stays readable at `http://localhost:8787/r/6nrH4Jl94nwA/logs` for 30 days. `./room_url.txt` contains only the room URL, `http://localhost:8787/r/6nrH4Jl94nwA`.

## (a) What was agreed

- **Webhook URL (answer 1):** `https://hooks.globex.example/acme`
- **Event types (answer 2):** `invoice.paid` and `invoice.voided` only. Globex does not want `invoice.created` or `customer.updated`.
- Credentials and the webhook signing secret are exchanged out of band, not in the room. Both sides confirmed this.

I gave Globex the following from my notes:

- **Auth:** OAuth2 client-credentials via `POST /oauth/token`, with 30-minute access tokens.
- **Webhooks:** HMAC-SHA256 in `X-Acme-Signature`, exponential-backoff retries for up to 24 hours, and at-least-once delivery deduped on `event_id`.
- **Invoice object:** the field list, the four statuses, amounts as integers in minor units, ISO 4217 currency, and `due_date` as an ISO 8601 date.
- **Operational limits:** 600 requests/minute with 429 plus `Retry-After`. `Idempotency-Key` on `POST /invoices` is remembered for 48 hours. Pagination is cursor-based (`?after=<cursor>`) with a maximum page size of 200.
- **Sandbox:** the base URL, which resets every Sunday 00:00 UTC.

Globex asked for details my notes do not cover. I told them I don't know and recorded these as open follow-ups for the Acme team, with no defaults assumed:

1. Credential format for the token request, scopes, token renewal, and the production base URL.
2. For webhooks: the exact signed bytes and signature encoding, any timestamp or replay protection, the precise retry schedule, and what response counts as success.
3. A typed invoice and line schema with required/nullable fields, and any timestamp fields.
4. Whether "minor units (cents)" follows the currency-specific ISO 4217 exponent.
5. Sanitized examples: a token request, a signed webhook, and an invoice JSON.

## (b) Service documentation and behaviour

Nothing caused an error or a retry. Every call worked first time: create, post, long-poll, close and logs. The friction points were small:

- **Cursor after creating a room.** The create response says `"cursor": 0`, but message #1 already exists. I only learned that from a comment in the CLI script: `# message 1 is our own "created the room"`. The root page doesn't mention it.
- **`wait` wake-up rule.** The room page says "Your own posts never wake your own wait (they are still included in what you read)". It doesn't say that system events such as "globex joined" do wake a wait. That is sensible, but it cost me a wait/read cycle that returned only a join notice. A client also has to filter its own lines and notices itself, which the CLI does in `has_news`.
- **Where to keep the token.** The root page says: "Store it now, in a file a later session of yours can find, apart from anything you share." It gives no concrete location. My task put `room_url.txt` in the same directory, so I kept the token there in a mode-600 dotfile, `.parlor_create.json`. The docs could say "not in the same file as the URL" more explicitly.
- **CLI default base URL.** The script defaults to `BASE="${PARLOR_URL:-https://parlor.sh}"` even though it was served from `http://localhost:8787/cli`. Running `parlor create` as downloaded would therefore hit a different service unless `PARLOR_URL` is set. The root page's install line doesn't mention this. I avoided it by using raw curl.
- **Two ways to pass the join handle.** The room page shows `POST .../join?handle=YOUR_NAME` as a query parameter. The CLI sends it as a form field with `--data-urlencode "handle=$2"`. Both presumably work, since room creation is documented as "A JSON body or query parameters work too", but the join section doesn't say so.
- **Status line wording.** "Status: **open** (open; ends after 1 day without activity)" repeats the word "open".
- **`present: 2/2` after close.** The transcript footer still reads `present: 2/2` once the room is closed. That is slightly odd but harmless, since "present" is defined as participants who have not called leave.
