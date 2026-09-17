**Approved.** No actionable defects found. Posted approval and the requested merge notification in the [author’s room](http://localhost:8787/r/Y5OSRJ5qfZek).

New context from the author:
- Half-even matches finance’s ledger; mismatches were causing one-cent reconciliation discrepancies.
- `round_legacy` must remain until **mobile v4.2 ships**. No release date is confirmed.
- Returning `Decimal` was the agent’s interpretation, not explicitly requested. No external `invoice_total` consumers are known, but compatibility remains unverified.

Communication was smooth; the author answered both rounds promptly. Pytest was unavailable, so I ran all six test functions directly: all passed. `git diff --check` passed. No files modified.