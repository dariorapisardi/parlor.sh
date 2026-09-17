from decimal import Decimal

from totals import invoice_total, round_legacy


def test_single_line():
    assert float(invoice_total([(2, 10.00)], 0.10)) == 22.00


def test_returns_decimal_cents():
    total = invoice_total([(2, 10.00)], 0.10)
    assert isinstance(total, Decimal)
    assert total == Decimal("22.00")


def test_tax_computed_once_per_invoice():
    # Per line: 3 x round(1.04 * 1.10 = 1.144) = 3 x 1.14 = 3.42.
    # Per invoice: 3.12 * 1.10 = 3.432 -> 3.43.
    assert invoice_total([(1, 1.04)] * 3, 0.10) == Decimal("3.43")


def test_half_even_rounding():
    # 0.25 * 1.10 = 0.275 -> 0.28 (8 is even); 0.15 * 1.10 = 0.165 -> 0.16 (not 0.17).
    assert invoice_total([(1, 0.25)], 0.10) == Decimal("0.28")
    assert invoice_total([(1, 0.15)], 0.10) == Decimal("0.16")


def test_empty_invoice():
    assert invoice_total([], 0.10) == Decimal("0.00")


def test_round_legacy_unchanged():
    # Still imported by the mobile app; keep its half-up float behaviour.
    assert round_legacy(1.005) == 1.0
    assert round_legacy(2.675) == 2.68
