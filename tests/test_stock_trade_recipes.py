"""Stock and capital, trade recognition, recipes, market numbers."""

import pytest

from conftest import to_py

DAY = 86400


def test_stock_position(logic):
    p = to_py(logic.ns.Stock.Position(logic.to_lua({"qty": 10, "avgCost": 100, "price": 150, "perDay": 4, "cut": 0.05})))
    assert p == {"qty": 10, "invested": 1000, "worth": 1425, "profit": 425, "days": 2.5, "below": False}
    p = to_py(logic.ns.Stock.Position(logic.to_lua({"qty": 10, "avgCost": 100, "price": 104, "cut": 0.05})))
    assert p["below"] is True and "days" not in p


def test_stock_below_streak(logic):
    s = logic.ns.Stock
    state = logic.table()
    assert s.TrackBelow(state, 1, True, 100) == 1
    assert s.TrackBelow(state, 1, True, 102) == 3
    assert s.TrackBelow(state, 1, False, 103) == 0
    assert s.TrackBelow(state, 1, True, 104) == 1


def test_capital(logic):
    chars = logic.to_lua({
        "A-R": {"money": 1000, "bags": {1: 10}, "bank": {2: 1}, "mailMoney": 50},
        "B-R": {"money": 500, "auctions": {1: 5}, "mail": {3: 2}},
    })
    values = logic.lua.eval("function(id) if id == 1 then return 10 elseif id == 2 then return 300 end end")
    c = to_py(logic.ns.Stock.Capital(chars, values))
    assert c["gold"] == 1550 and c["bags"] == 100 and c["bank"] == 300 and c["auctions"] == 50 and c["mail"] == 0
    assert c["total"] == 2000
    assert c["perChar"] == {"A-R": 1450, "B-R": 550}
    assert logic.ns.Stock.Held(chars, 1) == 15


def trade(logic, **kw):
    t = {"gave": {"items": [], "money": 0}, "got": {"items": [], "money": 0}, "guild": False}
    t.update(kw)
    return logic.to_lua(t)


def items(*ids):
    return [{"itemID": i, "qty": 1} for i in ids]


@pytest.mark.parametrize("kw, kind, auto", [
    ({"enchant": "Enchant Bracer - Stamina", "got": {"items": [], "money": 5000}}, "service", True),
    ({"gave": {"items": items(7), "money": 0}, "got": {"items": [], "money": 900}, "order": True}, "craft", True),
    ({"gave": {"items": items(7), "money": 0}, "got": {"items": [], "money": 900}}, "trade_sell", True),
    ({"gave": {"items": items(7), "money": 0}, "got": {"items": [], "money": 900}, "crafted": {7: True}}, "unclear", False),
    ({"gave": {"items": [], "money": 900}, "got": {"items": items(7), "money": 0}}, "trade_buy", True),
    ({"got": {"items": [], "money": 900}}, "money_in", False),
    ({"got": {"items": items(1, 2), "money": 0}}, "reagents_in", True),
    ({"gave": {"items": items(1), "money": 0}, "got": {"items": items(2), "money": 0}}, "unclear", False),
    ({"own": True, "got": {"items": [], "money": 900}}, "transfer", True),
    ({}, "ignore", True),
])
def test_trade_classify(logic, kw, kind, auto):
    r = to_py(logic.ns.TradeLogic.Classify(trade(logic, **kw)))
    assert r["kind"] == kind and r["auto"] == auto


def test_stranger_gold_warning(logic):
    r = to_py(logic.ns.TradeLogic.Classify(trade(logic, got={"items": [], "money": 900})))
    assert r["warn"] == "stranger_gold" and r["options"] == ["service", "trade_sell", "ignore"]
    r = to_py(logic.ns.TradeLogic.Classify(trade(logic, got={"items": [], "money": 900}, guild=True)))
    assert "warn" not in r


def test_own_reagents_and_prices(logic):
    T = logic.ns.TradeLogic
    need = logic.to_lua([{"itemID": 1, "qty": 4}, {"itemID": 2, "qty": 1}])
    own = to_py(T.OwnReagents(need, logic.to_lua([{"itemID": 1, "qty": 3}])))
    assert own == [{"itemID": 1, "qty": 1}, {"itemID": 2, "qty": 1}]
    value = logic.lua.eval("function(id) return id * 100 end")
    entry = logic.to_lua({"name": "Enchant Boots - Agility", "client": 2000, "reagents": [{"itemID": 1, "qty": 2}]})
    assert T.ServicePrice(entry, False, value) == 2000
    assert T.ServicePrice(entry, True, value) == 2200
    assert T.CheckPayment(2200, 2000) == ("less", -200)
    pl = logic.to_lua([entry])
    assert T.FindService(pl, "Enchant Boots - Agility").client == 2000
    assert T.FindService(pl, "Чары: Enchant Boots - Agility (3)").client == 2000
    clients = logic.table()
    for i in range(3):
        T.AddOrder(clients, "Client", 100, i)
    assert T.IsRegular(clients, "Client") and clients.Client.sum == 300


@pytest.fixture
def prices(logic):
    buy = logic.lua.eval("function(id) local t = { [1] = 10, [2] = 50, [3] = 5 }; return t[id] end")
    sale = logic.lua.eval("function(id) local t = { [100] = 200, [101] = 30 }; return t[id] end")
    return buy, sale


def recipe(rid, output, reagents, difficulty, qmin=1, qmax=1):
    return {"recipeID": rid, "output": output, "qtyMin": qmin, "qtyMax": qmax, "difficulty": difficulty,
            "reagents": [{"itemID": i, "qty": q} for i, q in reagents]}


def test_recipe_evaluate(logic, prices):
    buy, sale = prices
    r = to_py(logic.ns.Recipes.Evaluate(logic.to_lua(recipe(1, 100, [(1, 4), (2, 1)], 1)), buy, sale))
    assert r["cost"] == 90 and r["sale"] == 200 and r["profit"] == 110 and r["chance"] == 0.75
    assert r["pointCost"] == round(-110 / 0.75)
    grey = to_py(logic.ns.Recipes.Evaluate(logic.to_lua(recipe(2, 100, [(1, 1)], 3)), buy, sale))
    assert "pointCost" not in grey


def test_recipe_plan_and_shopping(logic, prices):
    buy, sale = prices
    recs = logic.to_lua([
        recipe(1, 101, [(3, 2)], 0),          # cost 10, sale 30 -> point -20
        recipe(2, None, [(2, 1)], 0),         # enchant: cost 50, point 50
        recipe(3, 101, [(1, 1)], 2),          # cost 10 sale 30, chance 0.25 -> -80
    ])
    plan = to_py(logic.ns.Recipes.Plan(recs, 70, 95, buy, sale))
    assert [s["eval"]["recipe"]["recipeID"] for s in plan["steps"]] == [3, 1, 2]
    assert [s["points"] for s in plan["steps"]] == [10, 10, 5]
    assert plan["steps"][0]["crafts"] == 40 and plan["short"] == 0
    need = to_py(logic.ns.Recipes.Shopping(logic.ns.Recipes.Plan(recs, 70, 95, buy, sale)))
    assert need == [40, 5, 20]  # item 1, 2, 3


def test_reagent_values(logic, prices):
    buy, sale = prices
    recs = logic.to_lua([recipe(1, 100, [(1, 4), (2, 1)], 1, 1, 3)])  # sale 200 x 2 = 400
    v = logic.ns.Recipes.ReagentValues(recs, buy, sale)
    assert v[1].value == (400 - 50) // 4 and v[2].value == 400 - 40


def hist(logic, points):
    return logic.to_lua([{"t": t, "p": p, "q": q, "m": m} for t, p, q, m in points])


def test_market_depth_and_hours(logic):
    ms = logic.ns.MarketStats
    lots = logic.to_lua([{"qty": 10, "price": 100}, {"qty": 5, "price": 100}, {"qty": 30, "price": 120}])
    d = to_py(ms.Depth(lots, 24))
    assert d == [{"price": 100, "units": 15, "cum": 15, "hours": 15}, {"price": 120, "units": 30, "cum": 45, "hours": 45}]
    assert ms.HoursBelow(lots, 120, 24) == 15
    assert ms.HoursBelow(lots, 120, 0) is None


def test_market_verdicts(logic):
    ms = logic.ns.MarketStats
    now = 10 * DAY
    lots = logic.to_lua([{"qty": 1, "price": 50}, {"qty": 40, "price": 100}, {"qty": 40, "price": 110}])
    h = hist(logic, [(now - 2 * DAY, 100, 20, 100), (now, 100, 81, 50)])
    v = to_py(ms.Verdicts(lots, h, now))
    assert v["dumper"] == {"price": 50, "units": 1}
    assert v["flood"] == {"before": 20, "now": 81}


def test_market_change_crash_and_movers(logic):
    ms = logic.ns.MarketStats
    now = 10 * DAY
    falling = hist(logic, [(now - 2 * DAY, 1000, 100, 900), (now - 3600, 600, 100, 500)])
    rising = hist(logic, [(now - 2 * DAY, 100, 100, 90), (now, 150, 100, 140)])
    assert ms.Change(falling, now, DAY) == pytest.approx(-0.4)
    assert ms.IsCrash(falling, now)
    assert not ms.IsCrash(rising, now)
    up, down = ms.Movers(logic.to_lua({1: falling, 2: rising}), now, 5, 1)
    assert [x["itemID"] for x in to_py(up)] == [2] and [x["itemID"] for x in to_py(down)] == [1]


def test_market_series(logic):
    ms = logic.ns.MarketStats
    h = hist(logic, [(100, 10, 5, 9), (300, 20, 0, 0)])
    s = to_py(ms.Series(h, 0, 400, 4))
    assert [x.get("p") for x in s] == [10, 10, None, None]
    assert to_py(ms.SalesSeries(logic.to_lua({9: 4, 10: 7}), 10 * DAY + 5, 3)) == [0, 4, 7]
