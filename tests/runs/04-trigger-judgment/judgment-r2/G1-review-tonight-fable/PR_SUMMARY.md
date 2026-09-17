# Compute tax once per invoice

## What changed

- `invoice_total` (`totals.py`) sums the line nets, applies tax once to the invoice net, and rounds once to the cent. Previously each line's gross was rounded and the rounded values were summed.
- Arithmetic is done in `Decimal` (inputs converted via `str`), rounded `ROUND_HALF_UP`. The return type is still `float`.
- `round_legacy` is intentionally unchanged.

## How it was tested

- New `test_tax_computed_once_per_invoice`: three lines of 0.33 at 10% give 1.09 (per-line rounding gave 1.08). It fails against the previous implementation and passes now.
- New `test_empty_invoice`: empty invoice totals 0.00.
- `uv run --with pytest pytest -q`: 3 passed.

## Reviewer questions

Context not in the diff is available in this room (reachable only from the machine the change was made on): http://localhost:8787/r/VorNWOO1_QDR
