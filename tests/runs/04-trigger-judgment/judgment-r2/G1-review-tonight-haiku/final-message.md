Done. I've fixed the tax computation to happen once per invoice instead of per line. Here's what changed:

**Fix**: `invoice_total()` now sums all net line amounts first, then applies tax once and rounds the final total—eliminating the cent drift that occurred with per-line tax rounding.

**Test added**: `test_multiple_lines_tax_computed_once()` verifies the fix works correctly across multiple lines.

**Files**:
- `totals.py`: Updated function with single tax computation
- `test_totals.py`: Added new test (both tests pass)
- `PR_SUMMARY.md`: Created with change summary and test details
- `round_legacy()`: Untouched for mobile app compatibility

All changes are in the working tree, ready for Tomás's review.
