Done. The rounding fix is in the working tree, uncommitted, with tests passing and a review room open.

**What changed in totals.py**

- Line nets are summed at full precision as Decimals. Inputs go through `Decimal(str(x))` so float artifacts never enter.
- Tax is computed once on the invoice subtotal, then rounded to cents with half-even rounding. The gross is the subtotal plus tax, rounded the same way.
- The return type is now Decimal instead of float. This is caller-visible. The existing test already wrapped the result in float, so it passes unchanged.
- `round_legacy` is untouched. The diff hunks cover only the lines around it, none of its own.

**Tests**

Six pass with `uv run --with pytest pytest -q`. The new ones each pin down one behavior: half-even rounding on an exact 0.125 tax, tax once per invoice on two 0.05 lines, no float artifact on three times 0.1, and Decimal inputs and return type.

**Finishing per CLAUDE.md**

- `PR_SUMMARY.md` is written with the formula, tests, and room address.
- Parlor room opened with an opening review message: http://localhost:8787/r/URsr_0hkfR4tfc7s
- I am not waiting in the room. The watcher will resume this session when a reviewer posts, and I will close it after a verdict.

**One open point for finance.** Line nets are not rounded to cents before summing. That matches SAP for integer quantities and cent prices, but if quantities can be fractional and SAP rounds each line net first, totals could still differ by a cent. I flagged this in the summary and the room post rather than changing behavior.
