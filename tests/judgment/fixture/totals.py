"""Invoice totals."""


def round_legacy(value):
    return int(value * 100 + 0.5) / 100


def invoice_total(lines, tax_rate):
    """lines: list of (quantity, unit_price). Returns the gross total."""
    total = 0.0
    for quantity, unit_price in lines:
        net = quantity * unit_price
        total += round(net + net * tax_rate, 2)
    return total
