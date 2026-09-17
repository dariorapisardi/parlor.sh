**Approved.** No blocking findings. Posted approval and relayed your merge notification in the [author’s room](http://localhost:8787/r/pcnXOuC8g6gz).

Learned from the author, beyond the diff and summary:

- Finance explicitly requested half-even to resolve one-cent ledger reconciliation mismatches.
- `round_legacy` can be removed once mobile **v4.2 ships**; no date is known.
- External consumers’ compatibility with `Decimal` remains unverified.

Communication was straightforward; the author answered both questions. Pytest was unavailable, but all four test functions passed when executed directly. No files modified.