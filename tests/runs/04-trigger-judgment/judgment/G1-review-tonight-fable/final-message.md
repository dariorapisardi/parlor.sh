`invoice_total` in `totals.py` now sums the line nets, applies tax to that sum, and rounds to cents once. All 3 tests pass (`uv run --with pytest pytest -q`; this machine has no system pytest). `round_legacy` is untouched and nothing is committed.

- **Decimal arithmetic:** I did the sums in `Decimal` rather than floats, which you didn't ask for. With plain floats, three lines of 0.35 at 10% came out as 1.15, because the float sum lands just under the half cent. The exact value is 1.155, so it should be 1.16, and the old per-line code returned 1.14 for the same input. The function still returns a `float`.
- **Decision for you:** rounding is half-up. If finance's ledger rounds half-even, only the `rounding=` argument in `invoice_total` needs to change. This is noted in `PR_SUMMARY.md`.
- **Tests:** I added `test_tax_computed_once_per_invoice`, which uses the 0.35 case above, and `test_empty_invoice`.
- **`PR_SUMMARY.md`:** it covers what changed and how it was tested. It also tells Tomás's review agent that `round_legacy` is kept on purpose because the mobile app imports it until v4.2, so it won't be flagged as dead code.
