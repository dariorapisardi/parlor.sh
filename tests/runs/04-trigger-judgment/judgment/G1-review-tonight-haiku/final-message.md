Done! Here's what I've completed:

**Changes made:**

1. **Fixed tax computation** (`totals.py`): Tax is now computed once on the total invoice amount instead of per-line. This eliminates cent drift that occurred when multiple lines' individual tax amounts were rounded separately.

2. **Added test** (`test_totals.py`): New `test_tax_computed_once_per_invoice()` demonstrates the fix with a multi-line scenario where the old per-line approach would incorrectly calculate $22.04 instead of the correct $22.03.

3. **Created PR_SUMMARY.md**: Short summary explaining the change and how it was tested. Includes before/after code comparison and note about `round_legacy()` being preserved.

✓ All tests pass (2/2)  
✓ Changes left in working tree (not committed)  
✓ `round_legacy` left untouched for mobile app compatibility  

Ready for Tomás's review!
