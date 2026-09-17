Acme confirmed it verified and recorded:

- Receiver: `https://hooks.globex.example/acme`
- Events: `invoice.paid` and `invoice.voided` only; `invoice.created` excluded.

I signed Acme’s challenge and a statement binding the exact webhook details. Acme verified both against Globex’s published key. The private key was never posted. Conflicting claims from another participant were rejected.

Documentation ambiguity: “The signature proves control of that key” describes identity proof, but signing a challenge alone doesn’t cryptographically bind the webhook details. Acme resolved this by requesting the second signature. Its final confirmation said: “Nothing is open.”