import pytest

DAY = 24 * 60 * 60
NOW = 1_793_000_000


def lots(addon, *pairs):
    return addon.table(*[addon.table(price=p, qty=q) for p, q in pairs])


def scans(addon, *pairs):
    """pairs: (days ago, price)"""
    return addon.table(*[addon.table(time=NOW - int(d * DAY), price=p) for d, p in pairs])


@pytest.mark.parametrize(
    "values, expected",
    [([], None), ([5], 5), ([3, 1, 2], 2), ([4, 1, 3, 2], 2.5)],
)
def test_median(logic, values, expected):
    assert logic.ns.Stats.Median(logic.table(*values)) == expected


def test_percentile_interpolates(logic):
    t = logic.table(10, 20, 30, 40, 50)
    assert logic.ns.Stats.Percentile(t, 0) == 10
    assert logic.ns.Stats.Percentile(t, 0.5) == 30
    assert logic.ns.Stats.Percentile(t, 0.35) == pytest.approx(24)
    assert logic.ns.Stats.Percentile(t, 1) == 50


def test_money_split_and_cut(logic):
    m = logic.ns.Money
    assert m.Split(1_02_03) == (1, 2, 3)
    assert m.Split(-1_00_00) == (-1, 0, 0)
    assert m.AfterCut(10000, 0.05) == 9500
    assert m.AfterCut(99, 0.05) == 94


def test_scan_price_ignores_single_cheap_lot(logic):
    # TZ: one lot at 2 silver among a hundred at 1 gold barely moves the price.
    price = logic.ns.Pricing.ScanPrice(lots(logic, (200, 1), (10000, 100)))
    assert price == 10000


def test_scan_price_ignores_overpriced_tail(logic):
    price = logic.ns.Pricing.ScanPrice(lots(logic, (100, 200), (150, 100), (99999, 10)))
    # 310 units, cheapest 47 units are all @100
    assert price == 100


def test_scan_price_even_unit_count_averages(logic):
    # 14 units -> cheapest 15% = 3 units (ceil 2.1); odd -> unit #2
    assert logic.ns.Pricing.ScanPrice(lots(logic, (10, 1), (20, 1), (30, 12))) == 20
    # 20 units -> 3 units; force even with share 0.1 -> 2 units: (10 + 20) / 2
    assert logic.ns.Pricing.ScanPrice(lots(logic, (10, 1), (20, 1), (30, 18)), 0.1) == 15


def test_scan_price_empty_market(logic):
    assert logic.ns.Pricing.ScanPrice(logic.table()) is None
    assert logic.ns.Pricing.ScanPrice(lots(logic, (100, 0))) is None


def test_market_price_weights_recent_scans(logic):
    p = logic.ns.Pricing
    # Old scans at 100 (weight 1 x3), recent scans at 200 (weight 2 x2): 200 has 4 of 7 weight.
    data = scans(logic, (6, 100), (5, 100), (4, 100), (1, 200), (0.5, 200))
    assert p.MarketPrice(data, NOW) == 200
    # Without the weight the old price would win.
    p.RECENT_WEIGHT = 1
    assert p.MarketPrice(data, NOW) == 100


def test_market_price_ignores_scans_outside_window(logic):
    data = scans(logic, (30, 1), (8, 1), (2, 500))
    assert logic.ns.Pricing.MarketPrice(data, NOW) == 500
    assert logic.ns.Pricing.MarketPrice(scans(logic, (10, 5)), NOW) is None


def test_market_price_caution_levels(logic):
    data = scans(logic, *[(5, v) for v in (100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)])
    p = logic.ns.Pricing
    assert p.MarketPrice(data, NOW, "careful") < p.MarketPrice(data, NOW, "normal") < p.MarketPrice(data, NOW, "bold")


def test_new_item_threshold(logic):
    assert logic.ns.Pricing.IsNewItem(9)
    assert not logic.ns.Pricing.IsNewItem(10)
