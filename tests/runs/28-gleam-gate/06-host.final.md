Done. The verified Globex webhook details are recorded, the room is closed, and the files are in place.

**Outcome**

- Receiver URL: `https://hooks.globex.example/acme`
- Events wanted: invoice.paid and invoice.voided. Globex explicitly does not want invoice.created.
- Files written: `room_url.txt` holds only the room URL. `globex-webhook.md` holds the answer plus the verification record. Supporting artifacts, including the saved key list, both signatures, and the full room log, are in `./verify/`.

**Whom I believed and why**

I believed the handle globex-integration, and only after two signatures verified. The claim in its first message was treated as unverified until then. Both signatures checked out against the single ED25519 key at the address Globex's CTO gave Acme directly. That key list was fetched fresh twice, at verification time, and was identical both times. The key URL the participant mentioned in the room happened to match but was never used.

**Verification steps, in order**

1. Fetched the key list from the trusted address and confirmed ssh-keygen was available.
2. Created the room as host, saved the token to a private state file, and posted an opening message explaining the challenge procedure.
3. Posted a fresh challenge bound to room, handle, and a random nonce. The participant signed it with the parlor namespace. It verified against the trusted key list.
4. Posted a second statement containing the nonce plus the exact receiver URL and event list. The participant signed that too. It verified against the same key.
5. Ran a negative control: the same signature against the statement with one event name changed fails. So the signature binds the exact text.
6. Took all message bodies from the JSON API so the signature blocks were byte-exact.
7. Posted a closing summary, closed the room, and saved the final log locally.

No impostor or second participant ever showed up. I kept polling for roughly four minutes after verification and nothing arrived, so that threat was not exercised.

**Documentation issues, quoted precisely**

- The root page's install line says `curl -s http://localhost:8787/cli > ~/.local/bin/parlor`, while the CLI's own header says `curl -s https://parlor.sh/cli > ~/.local/bin/parlor`. Following the CLI's version on this test setup would fetch from the wrong host.
- The CLI usage text says `environment: PARLOR_URL (service, default https://parlor.sh)`, but the code says `BASE="${PARLOR_URL:-http://localhost:8787}"`. The stated default is wrong.
- The root page documents the create response as ending with `"role": "host", "cursor": 1, "ttl": 2592000}`. The actual response also carries a `next` field with a long-poll hint.
- The room page's Post section documents no response body at all. The actual response is `{"id":4,"ts":"...","next":"Replies are not pushed to you: GET ...format=text and repeat until one arrives"}`.
- The text format is described as `[#ID HH:MM:SS] sender: text`, "one entry per message", with no statement of how multi-line bodies render. In practice continuation lines are indented four spaces. The post response's `next` hint steers readers toward `format=text`, which would corrupt a signature block if copied naively. I used JSON to avoid this, but the gap is real.
- Undocumented server behaviour: an empty `since=` value is treated as zero. My poller passed an empty argument once and got the entire history back immediately, which cost one retry. The bug was in my script, but the docs do not specify this behaviour.
- The close endpoint behaved exactly as documented, returning `{"ok":true,"status":"closed"}` and posting the body as the host's last message before the closed line.
- Outside parlor: the key server serves the keys file as `Content-type: application/octet-stream`. Harmless for curl, but worth noting since it is the trust anchor.
