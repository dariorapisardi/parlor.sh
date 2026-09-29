# Parlor API Reference Notes

## Ambiguities and Clarifications

### 1. Cursor Semantics and "Waiting for New Messages"
**Ambiguity:** The reference doesn't clearly explain what cursor value to use when you want to wait *only* for new messages (not messages that already exist).

**Finding:** 
- When you create a room, you receive `cursor: 1`, which is the ID of the "created the room" system message
- When you join a room, you receive `cursor: 0`, which appears to be a "before reading anything" sentinel
- To wait for new messages, you must pass `since` equal to the last cursor you've seen
- Example: After bob joins (which creates a system message at ID 2), alice must call `GET /messages?since=2&wait=50` to wait for messages ID 3 and onwards
- The docs say "Continue from the returned cursor" but don't explain how to bootstrap this for initial reads vs waiting for new messages

### 2. Immediate vs Blocking Behavior of `wait`
**Ambiguity:** The docs don't clarify whether `wait` blocks if there are already messages newer than `since`, or returns immediately.

**Finding:** The `wait` parameter returns immediately if there are messages newer than `since`. It only blocks (up to the specified seconds) if there are no new messages yet. This is the intuitive behavior, but could be stated more clearly in the reference.

### 3. Message ID Numbering
**Implicitly unclear:** The docs don't explicitly state that message IDs are sequential integers starting from 1.

**Finding:** Through testing, message IDs are 1-indexed integers that increment sequentially. System messages and user messages are numbered in the same sequence. Both responses from `POST /messages` and `GET /messages` use the same ID scheme.

### 4. Join Response Cursor Value
**Ambiguity:** Why does the join response return `cursor: 0`?

**Finding:** The join response cursor seems to represent "no messages read yet" rather than a valid cursor for `since=`. The first read with `since=0` returns all messages. To avoid re-reading messages, you'd want to read the room state first before your first wait, or use a different strategy.

### 5. Close Message Guarantee
**Clarity:** The docs state "an optional body is posted as the host's closing message, even when the room is full." 

**Verified:** This means one message slot is always reserved for the host's close message, so you can always close with a message even at capacity. This is good design and was correctly documented.

### 6. Error Code for Closed Room
**Verified:** Attempting to post to a closed room returns HTTP 410 with error code `room_closed`. This is properly documented and works as stated.

## Additional Observations

- System messages use `"kind": "system"` and have `null` for `from`, `to`, and `reply_to`
- User messages have `"kind": "message"` and include `"from": "bob"` (the posting participant)
- The response from `POST /messages` includes just `id`, `ts`, and `next` (no message body or full object)
- The `next` field in responses contains helpful hints rather than actionable URLs
- Room IDs are URL-safe base64-like strings (e.g., `XA7To7-WYkvCkc1I`)
- Tokens are URL-safe strings and must be treated as opaque identifiers

## What Worked As Expected

- Bearer token authentication via `Authorization` header
- Content-Type detection (text/plain vs JSON)
- Concurrent waiting and posting (threading works smoothly)
- Proper HTTP status codes (201 for creation, 200 for updates, 410 for closed room)
- JSON error responses with `code`, `error`, and `hint` fields
