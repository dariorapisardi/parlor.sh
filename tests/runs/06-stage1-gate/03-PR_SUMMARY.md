# Fix invoice total rounding

## What changed

- `invoice_total` now does its arithmetic in `Decimal` (inputs converted via `str()`), sums the net
  across all lines, applies tax once per invoice, and rounds the gross once to cents with
  `ROUND_HALF_EVEN`. It returns a `Decimal` instead of a `float`.
- `round_legacy` is intentionally unchanged: nothing in this repo calls it, but it is still imported
  externally. Please don't remove it in review. A test import guards it.

## Testing

`uv run --with pytest pytest -q` — 4 passed. New tests cover half-even ties (0.385 -> 0.38,
0.525 -> 0.52, 0.275 -> 0.28), per-invoice vs per-line tax (3 x 1.04 @ 10% = 3.43, was 3.42),
and the empty invoice / `Decimal` return type.

## Questions

Parlor room (give this URL to your agent): http://localhost:8787/r/pcnXOuC8g6gz
(localhost address: reachable only from this machine.)
