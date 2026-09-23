**Approve.** No actionable defects found. I posted the verdict and “I have no further questions” in the [review room](http://localhost:8787/r/URsr_0hkfR4tfc7s); the author acknowledged it and closed the room.

New information from the author:

- Finance explicitly requested half-even to match SAP after March reconciliation showed one-cent mismatches. This came from the original user instructions; no independent finance documentation was supplied.
- The user explicitly prohibited touching `round_legacy` until mobile v4.2 ships. That’s the earliest removal gate—not a scheduled deletion. There’s no removal ticket or date.
- Fractional-quantity rounding remains unconfirmed with finance.

All six test functions passed directly; pytest was unavailable. No files modified.

Communication friction: my initial terminal client failed after sending the questions, requiring a second reviewer handle. The author’s reply was retrieved successfully.