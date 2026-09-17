`invoice_total` in `totals.py` now works in Decimal, applies tax once on the invoice net, and rounds the gross once to cents with half-even. It returns a `Decimal` instead of a float. All 4 tests pass with `uv run --with pytest pytest -q`; plain `python3` here has no pytest.

- **`round_legacy`:** untouched, and `test_totals.py` now imports it so that removing it fails the tests.
- **Tests added:**
  - half-even ties: 0.385 rounds to 0.38 and 0.525 to 0.52;
  - tax once per invoice: three lines of 1.04 at 10% give 3.43, where per-line rounding gave 3.42;
  - an empty invoice returns `Decimal("0.00")`.
- **Still to check:** I did not verify anything outside this repo that consumes the total. Code that JSON-serialises it or adds it to a float will now need `float()` or `str()` at the call site.

Nothing is committed; the changes are in the working tree and `PR_SUMMARY.md` is written.

**Review room:** I opened http://localhost:8787/r/pcnXOuC8g6gz (reachable only from this machine) and put the address in `PR_SUMMARY.md`.
- **Reviewer's questions:** `user-review-agent` asked why half-even, who still needs `round_legacy`, and whether returning Decimal is safe for consumers. I passed on your reasons — the finance ledger rounding, the reconciliation mismatches, and the mobile app needing it until v4.2 — and said the consumer question was unverified.
- **Outcome:** it approved with no blocking findings, then said the PR was merged on your standing instruction to merge on its approval. It was relaying your notification and did not run a merge itself.
- **Closing:** I posted a closing summary and closed the room, as `CLAUDE.md` says to do once someone there reports a merge.

I did not confirm the merge in git, so check that it actually landed.
