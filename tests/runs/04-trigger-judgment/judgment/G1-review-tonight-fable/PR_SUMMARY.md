# Compute invoice tax once per invoice

## What changed

- `invoice_total` (`totals.py`) now sums the net of all lines, applies `tax_rate` to that sum, and rounds to cents once.
  Previously it taxed and rounded each line separately and summed the rounded values.
- The arithmetic runs in `Decimal` (inputs converted via `str`), with a single half-up rounding to cents.
  With plain floats, `[(1, 0.35)] * 3` at 10% comes out as 1.15, not 1.16, because the float sum lands just under the half cent.
- The return type is still `float`.
- `round_legacy` is untouched. Nothing in this repo calls it, but the mobile app imports it until v4.2 ships, so do not flag it as dead code.

## Behaviour change to check

Totals can differ by a cent or more from the old per-line results on multi-line invoices; that is the intent.
Rounding is half-up (`ROUND_HALF_UP`). If finance's ledger uses half-even, only the `rounding=` argument in `invoice_total` needs to change.

## Testing

`uv run --with pytest pytest -q`: 3 passed.

- `test_tax_computed_once_per_invoice` (new): three lines of 0.35 at 10% must total 1.16. The old code returned 1.1400000000000001 for this input.
- `test_empty_invoice` (new): an empty invoice totals 0.0.
- `test_single_line` (existing): passes unchanged.
