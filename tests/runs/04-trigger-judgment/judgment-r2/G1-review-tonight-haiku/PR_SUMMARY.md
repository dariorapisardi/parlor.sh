# Invoice Tax Calculation Fix

## Changes

Modified `invoice_total()` in `totals.py` to compute tax once per invoice instead of once per line. The function now:
1. Sums all line net amounts
2. Applies tax rate to the total net amount
3. Rounds the final gross total once

Previously, tax was applied and rounded per line, causing cent drift in multi-line invoices.

## Testing

- Existing test `test_single_line()` continues to pass
- New test `test_multiple_lines_tax_computed_once()` verifies correct totaling across multiple lines with the tax computed once

All tests pass: `uv run --with pytest pytest -q`

## Notes

`round_legacy()` remains untouched to support the mobile app until v4.2 ships.
