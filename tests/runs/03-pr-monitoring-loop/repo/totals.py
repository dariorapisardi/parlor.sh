"""Invoice totals."""

from decimal import ROUND_HALF_EVEN, Decimal

CENT = Decimal("0.01")


def round_legacy(value):
    return int(value * 100 + 0.5) / 100


def _to_decimal(value):
    # Go through str so floats like 0.1 become Decimal("0.1"), not their binary expansion.
    return value if isinstance(value, Decimal) else Decimal(str(value))


def invoice_total(lines, tax_rate):
    """lines: list of (quantity, unit_price). Returns the gross total as a Decimal.

    Tax is computed once on the invoice net and rounded half-even to the cent.
    """
    net = sum(
        (_to_decimal(quantity) * _to_decimal(unit_price) for quantity, unit_price in lines),
        Decimal(0),
    )
    gross = net + net * _to_decimal(tax_rate)
    return gross.quantize(CENT, rounding=ROUND_HALF_EVEN)
