"""Selling: posting price, duration, lot sizes, own lot state."""

from conftest import to_py


def lots(logic, *pairs):
    return logic.to_lua([{"qty": q, "price": p} for q, p in pairs])


def test_post_price_is_market_min_without_undercut(logic):
    s = logic.ns.Selling
    assert s.PostPrice(lots(logic, (5, 120), (3, 100)), None, 500) == 100
    assert s.PostPrice(lots(logic), None, 500) == 500
    assert s.PostPrice(lots(logic), None, None) == (None, "no_price")


def test_post_price_not_below_cost(logic):
    assert logic.ns.Selling.PostPrice(lots(logic, (5, 100)), 150.4, 500) == (151, "below_cost")


def test_duration(logic):
    s = logic.ns.Selling
    assert s.Duration(100, 10, 0, 120, 0) == "short"         # 10 units, 120/day -> 2 h
    assert s.Duration(100, 10, 40, 120, 0) == "long"         # 50 units -> 10 h
    assert s.Duration(100, 1, 0, None, 0) == "long"          # unknown speed
    assert s.Duration(100000, 1, 0, 120, 50000) == "long"    # expensive


def test_split(logic):
    s = logic.ns.Selling
    assert to_py(s.Split(45, True, 0)) == [45]
    assert to_py(s.Split(45, True, 20)) == [20, 20, 5]
    assert to_py(s.Split(3, False, 20)) == [1, 1, 1]


def test_lot_state(logic):
    s = logic.ns.Selling
    market = lots(logic, (5, 90), (10, 100), (20, 110))
    assert to_py(s.LotState(100, market, 10)) == {"cheaper": 5, "state": "ok"}
    assert to_py(s.LotState(120, market, 10)) == {"cheaper": 35, "state": "undercut"}
    assert to_py(s.LotState(80, market, None)) == {"cheaper": 0, "state": "ok"}


def test_without_own_removes_one_matching_lot(logic):
    s = logic.ns.Selling
    out = to_py(s.WithoutOwn(lots(logic, (1, 100), (1, 100), (2, 100)), 1, 100))
    assert out == [{"qty": 1, "price": 100}, {"qty": 2, "price": 100}]


def test_totals(logic):
    q = logic.to_lua([{"price": 100, "qty": 10, "deposit": 15}, {"price": 1000, "qty": 1, "deposit": 30}])
    assert to_py(logic.ns.Selling.Totals(q, 0.05)) == {"deposit": 45, "revenue": 950 + 950, "n": 2}
