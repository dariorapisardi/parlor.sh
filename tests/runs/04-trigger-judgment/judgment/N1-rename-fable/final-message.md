I renamed `invoice_total` to `compute_invoice_total` in `totals.py` (the definition) and `test_totals.py` (the import and the call). The test passes (1 passed); `python3` here has no pytest, so I ran it with `uv run --with pytest pytest -q`.

A search of the repo, including `docs/`, found no other references. I did not keep `invoice_total` as an alias, so any code outside this repo that imports the old name will break. Nothing is committed.
