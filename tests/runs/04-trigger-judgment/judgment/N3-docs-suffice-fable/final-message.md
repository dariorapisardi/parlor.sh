`globex_payload(invoice_id, currency, lines)` is in a new `globex.py`, with tests in `test_globex.py`. All 6 tests pass, including the existing one, run with `uv run --with pytest pytest -q` since plain `python3` has no pytest here. Nothing is committed.

The spec left three things open, so I chose:

- **Line format:** `lines` is a list of `(description, quantity, unit_price)` tuples. That is the existing `(quantity, unit_price)` convention from `totals.py` with the description Globex requires added.
- **Minor units:** prices are converted to integers exactly, so 0.29 becomes 29 rather than a rounded float. Currencies that don't use 1/100 are handled, for example JPY (no minor unit) and KWD (1/1000).
- **Invalid input:** a price that isn't a whole number of minor units (10.005 USD) or a non-integer quantity raises `ValueError`. Globex would answer 422 for those anyway.
- **Tax:** `total_minor` is the sum of `quantity * unit_minor`, with no tax. The spec has no tax field and the function takes no rate. If Globex expects the gross total, the function needs a rate parameter, and you'd have to confirm with Globex that the total doesn't need to equal the sum of the lines.

The function only builds the request body as a dict. It does not send the request or read `GLOBEX_API_KEY`.
