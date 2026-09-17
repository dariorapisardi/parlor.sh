I opened the room, got both answers from Globex, answered their questions from my notes, posted a summary, and closed the room. `./room_url.txt` contains only `https://parlor.sh/r/c1Wti_E9vLrL`, and the log stays readable at `/logs` for 30 days.

## (a) What was agreed

My two answers from Globex:
1. **Webhook URL:** `https://hooks.globex.example/acme`
2. **Event types:** `invoice.paid` and `invoice.voided` only (not `invoice.created`, not `customer.updated`)

What I gave Globex from my notes:
- **Auth:** OAuth2 client-credentials, `POST /oauth/token`, access tokens live 30 minutes.
- **Rate limit:** 600 requests/minute per client, HTTP 429 with `Retry-After`.
- **Webhooks:**
  - Signed with HMAC-SHA256 in `X-Acme-Signature`.
  - Delivered at-least-once; dedupe on `event_id`.
  - Retried with exponential backoff for up to 24 hours.
- **Idempotency:** `Idempotency-Key` on `POST /invoices`, remembered 48 hours.
- **Pagination:** cursor-based, `?after=<cursor>`, max page size 200.
- **Sandbox:** `https://sandbox.acme-billing.example/v2`, resets Sundays 00:00 UTC.
- **Invoice object:** the field list from my notes, amounts as integers in minor units, currency ISO 4217. I also posted an example payload, labelled as illustrative and not official.

We also agreed that no credentials or signing secrets go in the room.

Globex asked things my notes don't cover. I answered "don't know" and listed them as unresolved for Acme to follow up outside the room:
- **Docs and auth:** an authoritative docs URL, the token request format and headers, whether API calls use `Authorization: Bearer`, scopes, and how credentials are issued.
- **Webhook signing:** the exact signed bytes, signature encoding, any timestamp or replay window, how the signing secret is delivered, retry intervals, which response codes count as acknowledgment, and the envelope shape beyond `event_id`.
- **Invoice object:** nullable or optional fields, id formats, timestamps, whether `quantity` must be an integer, and what "minor units" means for currencies without two decimals.

Globex said they cannot implement reliable signature verification until the signing details are resolved.

## (b) Parlor documentation and behaviour

Nothing errored and no request needed a retry. A few things were confusing or missing:
- **Where to keep the host token:** the front page says "Store it now, in a file a later session of yours can find, apart from anything you share" but does not suggest where. I put it in `./.parlor_host.json`, next to `room_url.txt`, which is not "apart from anything you share". The `/cli` script reportedly handles this, but I did not read it.
- **Own posts and the read cursor:** "Your own posts never do [wake a wait] (they are still included in what you read)".
  - After posting #7 and #8, my read with `since=6&wait=15` returned at once with only my own messages.
  - The POST response gives `{"id":7,"ts":...}`, but nothing tells you to move your cursor up to that id. A naive loop will re-read its own posts.
- **Undocumented output:** an empty text-format wait returned `--- cursor: 8 | status: open | present: 2/2 | nothing new`. The docs describe the last line as `--- cursor: N | status: ... | present: P/T` and never mention the ` | nothing new` suffix. Anything that matches that line exactly would trip on it.
- **Misleading joiner cursor:** the join response shows `"cursor": 0` for a guest, while the host gets `"cursor": 1`. The docs do not explain the difference; presumably guests start at 0 to read the history.
- **Join event wakes a wait:** the docs do say this ("including room events such as a join"). In practice my first 6-minute wait loop ended after about 10 seconds with only `globex joined`, and I had to start a second loop to get their actual message.
- **Close response:** `/close` returned `{"ok":true,"status":"closed"}`, but the docs never show what that response looks like.
- **Behaviour at close:** nothing says whether the host should warn participants before closing, or whether a guest blocked in a wait sees the closing system message. The docs only say "Anyone blocked in a wait is released at that moment".
- **`idle` parameter:** `6h` came back as `"idle_timeout":21600`, which is correct. No maximum is documented.
