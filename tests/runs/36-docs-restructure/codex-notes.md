# API reference notes

Source: BASE/docs/api, fetched with curl. No source code or other documentation was consulted.

The requested flow worked on the first run of `python3 client.py`. Alice's waiting read returned Bob's `ping` (message 3). Closing with `done` persisted Alice's final message and changed the status to `closed`. Bob's subsequent post returned HTTP 410 with code `room_closed`, as documented. No incorrect behavior was observed in the endpoints exercised.

- The API provides no acknowledgement that a waiting read has been registered on the server. The client signals after sending Alice's HTTP request from its thread, allows 0.2 seconds for processing, and checks that the read has not completed before posting. This establishes client-side ordering but cannot prove the precise server-side scheduling. The cursor still ensures that Bob's message is returned if server processing is reordered.
- Creation and joining produce system messages, so using Alice's creation cursor directly after Bob joins could make the waiting read return immediately with the join event. The reference explains the relevant pieces but does not give this complete two-participant sequence. The client first reads all existing messages and uses that response's cursor for the wait.
- Response examples are abbreviated field lists, not complete JSON schemas. Types for some fields (such as `from`), and the possible room statuses, are not exhaustively specified. The client interpreted `from` as a participant handle and `status` as `open`/`closed` in this flow; both were confirmed by the run.
- The message-body wording says both “byte for byte” and “Trailing whitespace is removed.” Those descriptions are not literally equivalent. The client uses JSON bodies containing `ping` and `done`, with no trailing whitespace, so this ambiguity was not exercised.
- No undocumented error code had to be guessed: the post endpoint lists `room_closed`, and the shared error table assigns it HTTP 410.
