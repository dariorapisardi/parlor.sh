Done. I've added the `late_fee(total, days_overdue)` function to `totals.py` with a test. 

The function calculates fees as: `total × (percentage / 100) × (days_overdue / 30)`. I've set up a `LATE_FEE_PERCENT_PER_30_DAYS` constant (currently `None`) with a TODO note—once Finance confirms the percentage, just update that constant and the function will work. The test uses 5% as an example to verify the calculation logic works correctly.
