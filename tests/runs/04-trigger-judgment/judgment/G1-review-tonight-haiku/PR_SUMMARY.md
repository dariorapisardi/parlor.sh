# Tax Calculation Fix: Compute Once Per Invoice

## What Changed
Fixed tax computation to calculate once per invoice instead of once per line item. Previously, `invoice_total()` rounded tax for each line independently, causing cent drift when multiple line items' tax amounts accumulated rounding errors.

### Before
```python
for quantity, unit_price in lines:
    net = quantity * unit_price
    total += round(net + net * tax_rate, 2)  # rounds per-line
```

### After
```python
net_total = sum(quantity * unit_price for all lines)
tax_total = net_total * tax_rate
return round(net_total + tax_total, 2)  # rounds once
```

## Testing
- Existing `test_single_line()` continues to pass
- Added `test_tax_computed_once_per_invoice()` which verifies the fix with a multi-line scenario where per-line rounding would produce incorrect results ($22.04 vs. correct $22.03)

## Note
Left `round_legacy()` untouched; it's still imported by the mobile app until v4.2.
