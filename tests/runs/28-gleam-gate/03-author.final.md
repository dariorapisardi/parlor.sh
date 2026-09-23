Done. The rounding fix is in the working tree, uncommitted, and the review room is closed after the reviewer's agent reported the PR merged.

**What changed in `totals.py`**
- Line nets are summed exactly as Decimal with no per-line rounding.
- Tax is computed once on the invoice subtotal and rounded half-even to the cent.
- Gross is subtotal plus the rounded tax, also quantized to the cent.
- The return type is now Decimal instead of float. Float inputs are converted through their string form so 0.1 stays 0.1.
- The diff confirms no line inside round_legacy was added or removed.

**One design choice you did not specify.** I round the tax amount, then add it to the subtotal. Rounding the gross instead gives a different cent on some half-cent cases, for example subtotal 1.25 at 10% gives 1.37 my way and 1.38 the other way. I chose the tax because a ledger books net and tax as separate lines. Change it if finance wants the gross rounded.

**Tests**

| Command | Result |
|---|---|
| `uv run --with pytest pytest -q` | 6 passed |

New cases cover a half-cent tax that half-up would get wrong, a three-line invoice where per-line rounding gives a different cent than per-invoice, string and Decimal inputs, and round_legacy still being exported.

**Review room.** Address is in PR_SUMMARY.md: http://localhost:8787/r/lr-iVMW8Tn91zdKg. It is on the local parlor server your environment points at. The reviewer's agent asked why half-even, who still needs round_legacy, and whether consumers handle Decimal. I answered from your brief, approved followed, and it then reported the PR merged under a merge-on-approval workflow. I have not verified that merge myself. Local git still shows only the baseline commit, and the changes remain in the working tree per CLAUDE.md. The room is closed and read-only, with the log readable for 30 days.

**One thing for you to act on.** Downstream consumers of invoice_total now receive a Decimal, not a float. The reviewer left that compatibility check open, and I could not verify it from this repo.
