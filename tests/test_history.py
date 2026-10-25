from conftest import to_py

DAY = 86400
NOW = 1_793_000_000


def test_record_only_changes(logic):
    h = logic.ns.History
    lst = logic.table()
    assert h.Record(lst, 1, 100, 10, 90)
    assert not h.Record(lst, 2, 100, 10, 90)
    assert h.Record(lst, 3, 100, 9, 90)
    assert len(lst) == 2


def test_absent_item_not_recorded_until_seen(logic):
    h = logic.ns.History
    lst = logic.table()
    assert not h.Record(lst, 1, None, 0, None)
    assert h.Record(lst, 2, 50, 1, 50)
    assert h.Record(lst, 3, None, 0, None)


def test_prune_keeps_baseline(logic):
    h = logic.ns.History
    lst = logic.to_lua([{"t": t, "p": t, "q": 1, "m": t} for t in (1, 2, 3, 10, 11)])
    h.Prune(lst, 5)
    assert [e["t"] for e in to_py(lst)] == [3, 10, 11]


def test_summary_uses_price_at_each_scan(logic):
    h = logic.ns.History
    # Price 100 from 6 days ago, changed to 300 two days ago. Six scans: four old, two recent.
    lst = logic.to_lua([
        {"t": NOW - 6 * DAY, "p": 100, "q": 5, "m": 90},
        {"t": NOW - 2 * DAY, "p": 300, "q": 4, "m": 250},
    ])
    scans = logic.to_lua([NOW - 6 * DAY, NOW - 5 * DAY, NOW - 4 * DAY, NOW - 3.5 * DAY, NOW - 2 * DAY, NOW - DAY])
    s = to_py(h.Summary(lst, scans, NOW))
    assert s["scans"] == 6
    # weights: 100 x4 (w1) = 4, 300 x2 (w2) = 4 -> half reached at 100
    assert s["market"] == 100
    assert s["current"] == 300
    assert s["min7"] == 90
    assert s["median7"] == 100
    assert s["isNew"] is True


def test_summary_item_gone(logic):
    h = logic.ns.History
    lst = logic.to_lua([
        {"t": NOW - 2 * DAY, "p": 100, "q": 5, "m": 90},
        {"t": NOW - DAY, "p": None, "q": 0, "m": None},
    ])
    scans = logic.to_lua([NOW - 2 * DAY, NOW - DAY])
    s = to_py(h.Summary(lst, scans, NOW))
    assert s["scans"] == 1
    assert s["onMarket"] == 0
    assert "current" not in s


def test_velocity_per_day(logic):
    v = logic.ns.Velocity
    days = logic.table()
    v.Add(days, NOW - 3 * DAY, 10)
    v.Add(days, NOW - DAY, 4)
    v.Add(days, NOW, 6)
    v.Add(days, NOW - 30 * DAY, 100)  # outside the window
    assert v.PerDay(days, NOW, 7, None) == 20 / 7
    # Watching for only two days: 20 units over 2 days.
    assert v.PerDay(days, NOW, 7, NOW - 2 * DAY) == 10
    # Less than a day of watching counts as one day.
    assert v.PerDay(days, NOW, 7, NOW - 3600) == 20
    v.Prune(days, NOW, 7)
    assert sum(to_py(days).values()) == 20
