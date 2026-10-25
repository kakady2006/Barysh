"""Deals: which lots are worth buying and how much."""

import pytest

from conftest import to_py

CUT = 0.05


def opts(logic, **kw):
    o = {"cut": CUT, "minProfit": 100, "maxDays": 0}
    o.update(kw)
    return logic.to_lua(o)


def item(logic, lots, **kw):
    it = {"itemID": 1, "commodity": True, "lots": [{"qty": q, "price": p} for q, p in lots], "vendor": 0, "deposit": 0}
    it.update(kw)
    return logic.to_lua(it)


def rows(logic, it, o):
    return to_py(logic.ns.Deals.Evaluate(it, o))


def test_easy_money_below_vendor_price(logic):
    r = rows(logic, item(logic, [(5, 100), (5, 300)], vendor=150, commodity=False), opts(logic, minProfit=1))
    assert [x["type"] for x in r] == ["easy"]
    assert r[0]["profit"] == 5 * 50 and r[0]["days"] == 0


def test_resale_commodity_buys_up_to_best_amount(logic):
    # market 1000; lots 10@500, 10@600, 50@990. Selling price = min(market, next lot).
    it = item(logic, [(10, 500), (10, 600), (50, 990)], market=1000, perDay=30)
    r = rows(logic, it, opts(logic))
    assert len(r) == 1
    row = r[0]
    assert row["type"] == "resale"
    # buying both cheap lots: sale at min(1000, 990) = 990 * 0.95 = 940 net
    assert row["qty"] == 20 and row["maxPrice"] == 600
    assert row["value"] == 940
    assert row["profit"] == 20 * 940 - (5000 + 6000)
    assert row["days"] == pytest.approx(20 / 30)


def test_resale_buys_through_a_price_holding_lot(logic):
    # The lot at 100 alone is a loss (next lot 101), but with the 101 lot the price resets to the market.
    it = item(logic, [(1, 100), (1, 101), (5, 200)], market=180, perDay=10)
    r = rows(logic, it, opts(logic, minProfit=1))
    assert r[0]["qty"] == 2 and r[0]["value"] == 171
    assert r[0]["profit"] == 2 * 171 - 201


def test_resale_needs_sales(logic):
    it = item(logic, [(10, 100)], market=1000, perDay=0)
    assert rows(logic, it, opts(logic)) == []


def test_max_days_limits_amount(logic):
    it = item(logic, [(10, 100), (10, 120), (100, 900)], market=1000, perDay=10)
    assert rows(logic, it, opts(logic))[0]["qty"] == 120
    r = rows(logic, it, opts(logic, maxDays=2))
    assert r[0]["qty"] == 20 and r[0]["value"] == 855  # 10 per day x 2 days


def test_partial_lot_competes_with_itself(logic):
    # Buying 20 of a 30-unit lot leaves 10 at the same price: no resale profit.
    it = item(logic, [(30, 100), (100, 900)], market=1000, perDay=10)
    assert rows(logic, it, opts(logic, maxDays=2)) == []


def test_min_profit_threshold(logic):
    it = item(logic, [(1, 900)], market=1000, perDay=5, commodity=False)
    assert rows(logic, it, opts(logic, minProfit=100)) == []
    assert len(rows(logic, it, opts(logic, minProfit=10))) == 1


def test_item_lots_get_one_row_each(logic):
    it = item(logic, [(1, 300), (1, 350), (1, 2000)], commodity=False, market=1000, perDay=5)
    r = rows(logic, it, opts(logic))
    assert [x["maxPrice"] for x in r] == [300, 350]
    assert all(x["value"] == 950 for x in r)  # next after both = 2000, capped by market 1000


def test_disenchant_only_for_items(logic):
    r = rows(logic, item(logic, [(1, 1000)], commodity=False, de=2000), opts(logic))
    assert r[0]["type"] == "disenchant" and r[0]["value"] == 1900 and r[0]["profit"] == 900
    assert rows(logic, item(logic, [(1, 1000)], commodity=True, de=2000), opts(logic)) == []


def test_one_type_per_item_the_most_profitable(logic):
    # Disenchant gives 1900 net, resale gives 950 net: disenchant wins.
    it = item(logic, [(1, 500)], commodity=False, de=2000, market=1000, perDay=5)
    r = rows(logic, it, opts(logic))
    assert [x["type"] for x in r] == ["disenchant"]


def test_types_can_be_switched_off(logic):
    it = item(logic, [(1, 500)], commodity=False, de=2000, market=1000, perDay=5)
    r = rows(logic, it, opts(logic, types={"resale": True}))
    assert [x["type"] for x in r] == ["resale"]


def test_stock_respects_buy_below_and_cap(logic):
    it = item(logic, [(10, 400), (10, 700)], market=1000, perDay=1, stock={"buyBelow": 500})
    r = rows(logic, it, opts(logic, types={"stock": True}))
    assert r[0]["qty"] == 10 and r[0]["maxPrice"] == 400
    it = item(logic, [(10, 400)], market=1000, stock={"cap": 300})
    assert rows(logic, it, opts(logic, types={"stock": True})) == []
    # "auto" (no buyBelow) = market price
    it = item(logic, [(10, 900), (10, 1100)], market=1000, stock={})
    r = rows(logic, it, opts(logic, types={"stock": True}))
    assert r[0]["qty"] == 10


def test_craft_value(logic):
    it = item(logic, [(20, 50), (20, 90)], craft=80)
    r = rows(logic, it, opts(logic, types={"craft": True}))
    assert r[0]["qty"] == 20 and r[0]["profit"] == 20 * 30


def test_arbitrage_needs_gap_over_two_cuts(logic):
    other = {"price": 1000, "cut": 0.15}
    it = item(logic, [(1, 700)], commodity=False, other=other)
    r = rows(logic, it, opts(logic, types={"arbitrage": True}))
    assert r[0]["value"] == 850 and r[0]["profit"] == 150
    it = item(logic, [(1, 820)], commodity=False, other=other)
    assert rows(logic, it, opts(logic, types={"arbitrage": True}, minProfit=1)) == []


def test_sort_summary_and_affordability(logic):
    d = logic.ns.Deals
    all_rows = logic.to_lua([
        {"itemID": 1, "type": "resale", "perDay": 100, "profit": 500, "cost": 5000},
        {"itemID": 2, "type": "easy", "perDay": 50, "profit": 50, "cost": 100},
        {"itemID": 3, "type": "resale", "perDay": 300, "profit": 300, "cost": 90000},
    ])
    d.Sort(all_rows)
    assert [r["itemID"] for r in to_py(all_rows)] == [2, 3, 1]
    s = to_py(d.Summary(all_rows, 10000))
    assert s["counts"]["resale"] == 2 and s["counts"]["easy"] == 1
    assert s["n"] == 2 and s["cost"] == 5100 and s["profit"] == 550


def test_new_item_reference_is_second_third_lot(logic):
    lots = logic.to_lua([{"qty": 1, "price": p} for p in (50, 200, 300, 900)])
    assert logic.ns.Deals.NewItemReference(lots) == 250
    assert logic.ns.Deals.NewItemReference(logic.to_lua([{"qty": 1, "price": 70}])) == 70
