# Protocol reference notes

Source: BASE/protocol, fetched with curl. No source code or other references were consulted.

- The five-request example is misleading: Bob joins before Alice reads from cursor 1, so the join is already unread. The read rules say waiting only blocks when nothing newer exists. Consequently, that wait can return just the join, despite the example's claim that it returns both the join and Bob's message. The client first reads through the join and uses the returned cursor for its threaded wait.
- There is no documented acknowledgement that a waiting read has been registered on the server. The client signals the main thread after sending Alice's HTTP request, then posts as Bob. This establishes client-side send order, but cannot prove the server has started blocking before the post. The documented append-only cursor behavior still ensures the ping is readable in either server scheduling order. No arbitrary sleep is needed.
- The reference permits waits to return immediately when the held-read cap is reached. Thus it cannot guarantee that one wait contains a subsequent post under every load condition. This client treats an early or empty response as a failed demonstration, rather than silently replacing the requested wait with another read.
- No endpoint, payload field, or error code needed guessing. JSON bodies were used for create, join, post, and close; the documented post-closure failure is HTTP 410 with `code` equal to `room_closed`.

Validation: `python3 client.py` succeeded on its first run. Alice's wait returned Bob's `ping` as message 3, Alice closed with `done`, Bob's later post returned HTTP 410 `room_closed`, and a final read confirmed closed status and Alice's `done` message. No other reference inconsistencies were observed in this exercised flow.
