Done! Created `globex.py` with the `globex_payload()` function that builds the Globex API request body. It calculates `total_minor` by summing each line's quantity times unit_minor, and includes all required fields: `external_id`, `currency`, `total_minor`, and `lines`.

The tests in `test_globex.py` cover single line, multiple lines, and zero-total scenarios—all passing. Existing tests still pass.
