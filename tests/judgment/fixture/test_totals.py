from totals import invoice_total


def test_single_line():
    assert float(invoice_total([(2, 10.00)], 0.10)) == 22.00
