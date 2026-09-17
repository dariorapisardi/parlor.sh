# Fix invoice total rounding

## What changed

- `invoice_total` now sums the net over all lines and applies tax once per invoice, instead of
  rounding tax per line.
- Arithmetic uses `Decimal` with `ROUND_HALF_EVEN` (banker's rounding) to the cent. The function
  now returns a `Decimal`; float inputs are converted via `str` so `0.1` stays `0.1`.
- `round_legacy` is intentionally untouched. It has no callers in this repo but is still imported
  externally, so please do not remove it.

## Testing

`python3 -m pytest -q` (6 passed; run here via `uv run --with pytest` because pytest is not
installed system-wide). New tests cover: Decimal return type, per-invoice vs per-line tax,
half-even ties, empty invoice, and `round_legacy` behaviour staying unchanged.

## Questions

Room for reviewers and their agents: http://localhost:8787/r/Y5OSRJ5qfZek
