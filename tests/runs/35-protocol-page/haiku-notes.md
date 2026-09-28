# Notes on Parlor Protocol Reference

## Ambiguities and Clarifications from Implementation

### 1. **Wait Behavior with Multiple Concurrent Messages**

The protocol states: "A wait is woken by anything from someone else... returning as soon as something arrives."

**Ambiguity:** It's unclear whether a single wait can accumulate multiple messages before returning, or if it returns immediately with just the first new message.

**Finding:** In practice, the wait returns as soon as ANY new message becomes available. When Alice waits with `since=1`, and Bob joins (creating message 2), Alice's wait completes and returns only message 2. A subsequent post by Bob (message 3) is not included in that response—Alice must do a follow-up read to see it. This is true even if the post happens while the wait is still in flight on the network.

**Implication:** To see multiple messages from the same participant in a single wait response, they would need to be created atomically (impossible with separate HTTP requests), or you must do sequential reads.

### 2. **Message Order and Cursor Semantics**

The protocol is clear that messages are numbered sequentially (1, 2, 3...) and every reader sees the same order. It's also clear that `since=N` returns messages with id > N.

**Clarification:** The cursor is simply the id of the last message you've seen. To continue from where you left off, you use `since=<your_last_cursor>` in the next request.

### 3. **Read Without Wait Timing**

The protocol says reads without `wait` return immediately if messages exist, or return empty if not.

**Clarification:** A read with `since=<current_last_message_id>` and no wait (or `wait=0`) returns nothing (empty messages array) if no new messages have arrived. This is useful for polling without blocking.

### 4. **Status Codes and Error Handling**

The protocol documents error codes like `room_closed` (410), which are returned when attempting to post to a closed room.

**Clarification:** These are JSON responses with `{"error": "...", "code": "...", "hint": "..."}` structure. The HTTP status code (410) matches the condition, and the `code` field contains the machine-readable identifier.

### 5. **Host-Only Message in Closing**

The protocol states: "The host can always close with a final message, even in a full room."

**Clarification:** This space is explicitly reserved—the room tracks a one-message buffer for the host's closing message, ensuring the close can never fail due to room capacity, even if the message limit has been reached.

### 6. **Message Format Ambiguity**

The protocol describes two message formats: JSON (default) and text (with `format=text`).

**Clarification:** When posting, the body is interpreted as:
- JSON if `Content-Type` contains `json` OR the first non-space character is `{`
- Otherwise, the entire body is the message as-is (no form-decoding)

When reading, both formats return the same information; the format parameter only affects the response representation.

### 7. **Token Security Model**

The protocol notes tokens are "bearer secrets" and "whoever holds it speaks as that handle."

**Clarification:** There is no per-request signing or HMAC. A token in an Authorization header can be revoked only by deleting the room (or waiting for TTL expiry). Sharing a token grants full access to that participant's identity. This is by design for simplicity.

### 8. **Participant Limit and Leaving**

The protocol mentions "participant limit (people who left still count)".

**Clarification:** Once someone joins a room, they count against the limit even after leaving. The 50-person limit includes both active and departed participants. This prevents name-squatting attacks.

## Script-Specific Notes

The client.py script demonstrates:
- Creating a room (implicit host role for creator)
- Joining an existing room as a guest
- Waiting for messages (with potential for timing issues in batching)
- Posting text messages
- Closing a room with a final message
- Error handling when posting to a closed room

The pattern of doing a follow-up read when initial wait doesn't capture expected messages reflects the fundamental behavior that waits return on the first new message, not after collecting a batch.
