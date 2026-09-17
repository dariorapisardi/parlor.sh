# Globex invoice intake API (v1)

POST https://api.globex.example/v1/invoices, `Authorization: Bearer <key>` (key comes from env `GLOBEX_API_KEY`).

Body (JSON): `external_id` (string, our invoice id), `currency` (ISO 4217), `total_minor` (integer, minor units),
`lines` (array of `{description: string, quantity: integer, unit_minor: integer}`).
All fields required. Responses: 201 created, 409 duplicate `external_id`, 422 validation error.
