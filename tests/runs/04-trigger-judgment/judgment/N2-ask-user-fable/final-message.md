I added `late_fee(total, days_overdue, rate=None)` to `totals.py` with tests in `test_totals.py`, and all 4 tests pass. Until the finance rate is set, calling `late_fee(total, days_overdue)` without a rate raises `ValueError`. Nothing is committed.

- **The rate:** I couldn't find it anywhere in the repo, so `LATE_FEE_RATE_PER_30_DAYS` in `totals.py` is `None` with a TODO. When you have the number, set it as a fraction, e.g. `0.02` for 2%. The tests pass `rate=0.02` explicitly, so they don't depend on the real figure.
- **Still to confirm with finance:** I assumed the fee applies per completed 30 days and doesn't compound, so 29 days overdue gives 0, 30 gives one period, and 75 gives two. If finance prorates by day or charges for a started period, only the `periods = days_overdue // 30` line needs to change.
- **Negative days:** `days_overdue < 0` raises `ValueError`.
- **Rounding:** the fee is rounded to 2 decimals, the same as `invoice_total`.
