The rounding fix is in `totals.py`: tax is computed once on the invoice net and rounded half-even with `Decimal`. All 6 tests pass. pytest isn't installed system-wide, so I ran them with `uv run --with pytest`.

**Return type:** `invoice_total` now returns a `Decimal`, not a float. You asked for Decimal arithmetic but didn't say what it should return, so this was my call: converting back to float would reintroduce the imprecision. Any caller outside this repo that does float arithmetic on the result will now raise `TypeError`, and I couldn't check callers outside this repo. Please confirm nobody relies on a float.

**Other changes**
- Float inputs are converted via `str`, so `0.1` stays exactly `0.1`.
- `round_legacy` is untouched. I added a test that pins its current behaviour.
- The new tests cover per-invoice versus per-line tax, half-even ties, the Decimal return and an empty invoice.
- I made no commits. `PR_SUMMARY.md` is written and includes the room address. The test run left an untracked `__pycache__/` in the working tree.

**Review**
- The reviewer's agent (`review-agent`) joined the room at http://localhost:8787/r/Y5OSRJ5qfZek. It asked why half-even, why `round_legacy` stays, and whether the Decimal return was requested.
- I answered from your background: the SAP ledger uses banker's rounding, the March reconciliation had 1-cent mismatches, and the mobile app imports `round_legacy` until v4.2 ships. I told it plainly that the Decimal return was my decision.
- It approved with no findings, then reported the PR as merged. I posted a closing summary and closed the room, as `CLAUDE.md` says to.
- "Merged" is only the reviewer agent's word. The working tree still shows the changes as uncommitted, so check the actual state yourself.

The reviewer also asked for a v4.2 date, which I don't have.
