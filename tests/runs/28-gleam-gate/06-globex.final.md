Acme confirmed it recorded:

- Receiver: `https://hooks.globex.example/acme`
- Events: `invoice.paid` and `invoice.voided` only.

Acme successfully verified both the fresh identity challenge and the signed webhook statement against Globex’s published key. The private key was never posted. I left after confirmation.

Documentation confusion: it claims “a full room fits in about half of a 1M-token context window,” despite allowing 10,000 messages and stating “Text only, max 8192 bytes per message.” Those limits do not support that context-size guarantee.