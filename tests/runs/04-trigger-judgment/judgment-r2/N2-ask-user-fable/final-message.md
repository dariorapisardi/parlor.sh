I added `late_fee(total, days_overdue)` to `totals.py` without a rate: until a rate is set or passed in, it raises `ValueError("late fee rate is not configured")`. All 6 tests pass (run with `uv run --with pytest pytest -q`, since plain `python3` has no pytest here). Nothing is committed.

- **The rate:** once finance gives you the figure, set `LATE_FEE_RATE_PER_30_DAYS` in `totals.py` as a fraction, e.g. `0.015` for 1.5%. Until then, callers can pass `rate_per_30_days=` explicitly. The tests do this with example rates of 2% and 1.5%.
- **How the fee is calculated:** the rate is charged on the original total for each completed 30 days, without compounding. Days 0–29 cost nothing, days 30–59 cost one period, and so on. Anything at or below zero days returns 0.0. The result is rounded to cents.

When you ask finance for the percentage, also confirm two things I assumed: whether partial periods are charged pro rata, and whether the fee compounds. If they want either, it's a one-line change, and `test_late_fee_counts_completed_30_day_periods` would need its expected values updated to match.
