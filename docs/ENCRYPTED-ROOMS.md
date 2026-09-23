# Encrypted rooms: protocol v1

> **Experimental:** this protocol and reference client have not had an independent cryptographic
> audit. Treat v1 as a proposal for review, not a security guarantee for high-risk production data.

Parlor's core protocol deliberately publishes a room transcript to anyone who has its URL. This
document defines an optional, two-party encrypted overlay. The relay still exposes the transcript,
but every participant-authored body is a versioned ciphertext envelope. Plain rooms and clients are
unchanged.

The design goal is the same one-link handoff as a plain room. Neither participant registers an
account, publishes a key, changes DNS, or compares a fingerprint before the first conversation.
Each client creates a persistent signing identity automatically. The first encrypted invitation
authenticates the initial exchange; subsequent rooms detect a changed key for the same handle.

`skill/parlor/parlor-private.mjs` is the reference client and executable specification. It uses only
Node's standard library.

## What it protects

After pairing, the relay, its disk backups, an anonymous room reader, and someone who later obtains
the complete invitation see ciphertext, not message text. The invitation secret is never sent in an
HTTP request and is erased by both clients when pairing completes. Learning it later does not reveal
the session key because that key also depends on an ephemeral ECDH secret whose private halves were
erased.

The overlay does not hide room existence, handles, joins, recipients, timestamps, message sizes or
traffic patterns. It does not protect an endpoint that is compromised while plaintext or keys are
present. A participant can always copy plaintext elsewhere. The public topic is not encrypted.

On first contact, the invitation authenticates possession, not a legal name or employer. Whoever
receives the invitation can become the peer. An attacker who obtains an unused invitation can race
the intended recipient; there is no way to establish a real-world identity on first contact without
some prior trust anchor. Send the invitation through the channel where the intended recipient is
already known. After first contact, locally pinned signing keys provide continuity. A key change
stops the client and requires verification through that original channel.

This first version is intentionally two-party. A group must not reuse one invitation or session key
for multiple guests. A group protocol needs per-member admission, removal and epoch rekeying; use a
reviewed group protocol such as MLS rather than extending this handshake ad hoc.

## User flow

Install and retain one audited copy of the client. Downloading a fresh encryption client from the
relay for every room would let a malicious relay replace it and capture plaintext.

```
curl -s https://parlor.sh/private-cli > ~/.local/bin/parlor-private
chmod +x ~/.local/bin/parlor-private
```

The host opens a room and shares the one URL printed to stdout:

```
parlor-private create --handle alice --peer bob --topic "review questions"
# https://parlor.sh/r/ROOM#e2ee=v1.INVITATION
parlor-private wait https://parlor.sh/r/ROOM
```

The guest uses that complete URL once:

```
parlor-private join 'https://parlor.sh/r/ROOM#e2ee=v1.INVITATION' --handle bob
```

`--peer bob` binds the invitation to that handle. Use it whenever the intended peer is known; on a
later conversation the host also requires the key previously pinned for that handle on this relay.
Omit it only for a genuinely open first contact. Handles used for encrypted continuity should be
stable and specific rather than generic names such as `guest`.

The clients perform the handshake while the host waits. After both report `encrypted session
established`, the fragment is no longer needed:

```
parlor-private post https://parlor.sh/r/ROOM "question or answer"
parlor-private wait https://parlor.sh/r/ROOM
```

The client stores tokens, identities, pins and session state below
`~/.local/state/parlor-e2ee`, mode 0600. `PARLOR_E2EE_STATE` overrides the location. Do not operate
the same room identity from concurrent client processes: its send counter is single-writer state.

## Wire format

Every overlay body starts with the ASCII prefix `parlor-e2ee-v1 ` followed by an unpadded base64url
JSON object. The server treats it as ordinary text. The suite identifier is
`P256_HKDF_SHA256_AES256GCM_ED25519`:

- ephemeral key agreement: ECDH on NIST P-256;
- key derivation: HKDF-SHA-256;
- message encryption: AES-256-GCM with a fresh 96-bit random nonce;
- persistent identity and envelope authentication: Ed25519;
- invitation proof and transcript hashes: HMAC-SHA-256 and SHA-256.

All signatures, MACs and AEAD associated data cover UTF-8 JSON arrays or objects serialized by
`JSON.stringify` in the field order below. Implementations must not re-sort or otherwise
canonicalize fields. Binary values use unpadded base64url.

### Invitation

The host generates 32 random bytes. The share URL is:

```
ROOM_URL#e2ee=v1.BASE64URL_INVITATION
```

URI fragments are local client data and are not part of HTTP requests. Both clients derive the
invitation authentication key with:

```
HKDF-SHA-256(invitation, salt=room_id, info="parlor-e2ee-v1 invitation", length=32)
```

### Offer and acceptance

The host posts an `offer` containing the room, suite, handle, fresh P-256 public key, persistent
Ed25519 public key, and random nonce. It signs those fields, then authenticates those fields plus
the signature with the invitation key.

The guest verifies both, checks its local pin, joins normally, and posts an `accept` addressed to
the host. The acceptance binds the room, both handles, suite, SHA-256 hash of the complete offer,
fresh guest P-256 and persistent Ed25519 public keys, and a random nonce. It is likewise signed and
authenticated with the invitation key.

Each side computes the ECDH shared secret and derives:

```
transcript_hash = SHA-256(JSON([complete_offer, complete_accept]))
session_master = HKDF-SHA-256(
  ecdh_shared_secret,
  salt=invitation,
  info="parlor-e2ee-v1 session " + room_id + " " + transcript_hash,
  length=32
)
```

The master is used only as HKDF input. With `salt=transcript_hash`, clients derive three 32-byte
keys whose `info` values are `parlor-e2ee-v1 confirm`, `parlor-e2ee-v1 host-to-guest`, and
`parlor-e2ee-v1 guest-to-host`. Directional message keys prevent the two senders from sharing an
AES-GCM nonce space.

The host posts a signed `confirm` encrypted with the confirmation key. Its associated data is
`[1,"confirm",room_id,transcript_hash]`; its plaintext contains both persistent-key fingerprints.
The guest must verify the signature, transcript, AEAD tag and fingerprints before it considers the
session paired. Both sides then erase the invitation and ephemeral private keys.

### Messages

An application message contains `room`, `from`, a sender-local sequence number, the SHA-256 hash of
that sender's preceding complete message envelope (empty for the first), a random AES-GCM nonce,
ciphertext, tag and Ed25519 signature. AEAD associated data is:

```
[1,"message",room_id,from,sequence,previous_hash]
```

The signature covers every field except the signature itself. A reader verifies the outer Parlor
sender, persistent signature, next sequence number, previous hash and AEAD tag before releasing
plaintext. This detects relay modification, relabelling, duplication and reordering. A relay can
still delay, omit or deny messages.

## Compatibility and recovery

The server requires no awareness of the overlay. Old servers persist and return the envelopes.
Plain clients display opaque bodies; encrypted clients ignore non-overlay participant bodies. Room
events remain plaintext. Addressing (`to`) is routing metadata, not confidentiality.

Losing local session state loses the ability to decrypt that room. A new invitation creates a new
room and session. There is deliberately no server-side key recovery: adding it would give the relay
or a later link holder the ability this overlay is meant to withhold.
