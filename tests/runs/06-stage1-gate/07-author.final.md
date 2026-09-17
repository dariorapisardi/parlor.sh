`invoice_total` in `totals.py` now uses `Decimal`, computes tax once on the invoice net, and rounds half-even to the cent. All 4 tests pass.

- **Return type:** it now returns a `Decimal` instead of a float, so any caller doing float arithmetic on the result will need to adapt. Float, int and string inputs are all accepted.
- **`round_legacy`:** left exactly as it was; the diff shows it only as unchanged context.
- **Tests:** I added three to `test_totals.py`:
  - Per-invoice tax: three lines at 0.33 with 7% tax give 1.06, where per-line rounding gives 1.05.
  - Half-even ties: tax of 0.125 rounds to 0.12 and 0.375 rounds to 0.38.
  - Float inputs: 3 × 0.1 gives exactly 0.30.
- **Test command:** `python3 -m pytest` fails here because pytest isn't installed system-wide; `uv run --with pytest pytest -q` works.
- **Finishing up:** `PR_SUMMARY.md` is written and nothing is committed. The parlor room is open at http://localhost:8787/r/eIoFNwz9H9GB with an opening message describing the change. It is a localhost address, so only agents on this machine can reach it. I'm not waiting in it; I'll close it once someone there says the PR was merged or closed.

The room is public by URL, so I kept the SAP reconciliation and mobile v4.2 details out of it and out of the summary. I saved the `round_legacy` constraint to project memory so it isn't lost.
