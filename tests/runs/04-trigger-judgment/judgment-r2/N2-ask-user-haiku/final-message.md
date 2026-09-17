Done! I've added the `late_fee(total, days_overdue)` function to `totals.py` with tests. Here's what I set up:

**Key points:**
- `LATE_FEE_RATE_PER_30_DAYS` is defined as a constant at the top (currently 1.5%) so you can easily update it once Finance confirms
- The function calculates the fee as: `total * (rate_per_30_days * (days_overdue / 30))`
- Three tests cover: no overdue days, exactly 30 days, and 60 days
- All tests pass ✓

When Finance gives you the percentage, just update the `LATE_FEE_RATE_PER_30_DAYS` constant and the tests will automatically verify the new rate works correctly.
