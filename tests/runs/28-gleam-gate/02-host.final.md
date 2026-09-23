The exchange is complete and the room is closed. The room URL is in `room_url.txt` as a bare URL with no trailing newline.

**(a) What was agreed**

- **Globex webhook URL:** https://hooks.globex.example/acme
- **Event types Globex wants:** invoice.paid and invoice.voided only. They declined invoice.created and customer.updated.
- **Status of the agreement:** requirements only. Both sides recorded that nothing has been configured or enabled, and that Acme will enable delivery after credentials and the signing secret are exchanged out of band.
- **Answered from my notes:** auth flow and token lifetime, rate limit, webhook signing header, retry window, at-least-once with dedupe on event_id, idempotency window, pagination, sandbox URL and reset, amount and currency conventions, and the invoice fields and statuses.
- **Open items assigned to Acme** because my notes did not cover them: OAuth scopes, whether the token URL sits under /v2, credential placement and content type for the token request, the API Authorization header scheme, the exact signed payload and encoding for X-Acme-Signature, timestamp or replay validation, which HTTP statuses count as delivery failure plus per-attempt timeout and retry schedule, the types of description and quantity, optional or nullable fields, id formats, the webhook event envelope, and the production base URL. Globex explicitly refused to treat my "anything other than 2xx retries" guess as confirmed.

**(b) Service documentation and behaviour notes**

No request failed and nothing needed a retry. The whole exchange took ten messages. Points that were confusing or inconsistent:

- **Install URL differs between pages.** The root page says `curl -s http://localhost:8787/cli > ~/.local/bin/parlor`. The CLI's own header says `curl -s https://parlor.sh/cli > ~/.local/bin/parlor`. Its usage text says `PARLOR_URL (service, default https://parlor.sh)` while the script's `BASE` line reads `"${PARLOR_URL:-http://localhost:8787}"`.
- **The transcript footer does not match its description.** The room page says the footer carries ` | left: B bytes, M messages` and names an `X-Room-Bytes-Left` header. The footer I actually received was `--- cursor: 3 | status: open | present: 2/2 | left: 9998 messages`, with no byte count. The same page also says "A room holds unlimited bytes of message text", so the byte figure is documented in two places and contradicted in a third.
- **The state line is easy to misread.** It reads `Status: **open** (deleted 30 days after its last activity (2026-09-23T20:53:07.166Z))`. The timestamp is the last activity, not the deletion date, and the nested parentheses invite the wrong reading.
- **Closed-room error code differs from the docs.** The room page says posts after close "get 410". A tokenless post got `HTTP/1.1 401 Unauthorized`, and a post with my host token got a 200-style JSON body `{"error":"room is closed","hint":"No more posts. The log is still readable."}` through the CLI, which does not surface the HTTP status. I did not confirm whether that second response was a 410.
- **The create command needed a fix-up for this task.** `parlor create` prints the URL with a trailing newline, so I rewrote `room_url.txt` to hold only the URL. The `invite with:` line goes to stderr, which kept it out of the file but is not mentioned in the usage text.
- **Mild tension in the invitation guidance.** The root page says "Hand over the room URL, nothing else" and in the same section offers the `share` sentence as the invitation text.
- **Bash tool timeout versus wait.** The docs say `wait` blocks up to 540 seconds by default. The harness kills commands at 120 seconds unless told otherwise, so I had to raise the tool timeout for every wait. The docs mention this for HTTP clients but not for command runners.
