from conftest import to_py

SHORT, MEDIUM, LONG, VERYLONG = 0, 1, 2, 3


def diff(logic, old, new):
    return to_py(logic.ns.ScanDiff.Diff(logic.lots(*old), logic.lots(*new)))


def test_unchanged_market(logic):
    d = diff(logic, [(1, 100, VERYLONG), (5, 20, LONG)], [(5, 20, LONG), (1, 100, VERYLONG)])
    assert not d["changed"]
    assert d["soldUnits"] == 0


def test_time_left_band_drop_is_same_lot(logic):
    # A lot moving from ">12 h" to "2-12 h" is not a sale plus a new lot.
    d = diff(logic, [(1, 100, VERYLONG)], [(1, 100, LONG)])
    assert not d["changed"]


def test_time_left_cannot_grow(logic):
    # Same qty and price but more time left: the old one vanished and a new one was posted.
    d = diff(logic, [(1, 100, MEDIUM)], [(1, 100, VERYLONG)])
    assert d["changed"]
    assert [r["verdict"] for r in d["removed"]] == ["unknown"]
    assert len(d["added"]) == 1


def test_verdicts_by_time_left(logic):
    old = [(1, 10, VERYLONG), (2, 20, LONG), (3, 30, MEDIUM), (4, 40, SHORT)]
    d = diff(logic, old, [])
    verdicts = {r["price"]: r["verdict"] for r in d["removed"]}
    assert verdicts == {10: "sold", 20: "sold", 30: "unknown", 40: "expired"}
    assert d["soldUnits"] == 3
    assert d["soldValue"] == 1 * 10 + 2 * 20
    assert d["unknownUnits"] == 3
    assert d["expiredUnits"] == 4


def test_long_gap_between_scans_makes_sales_unknown(logic):
    old = [(1, 10, VERYLONG), (2, 20, LONG)]
    # 15 minutes later: both counted as sold.
    d = to_py(logic.ns.ScanDiff.Diff(logic.lots(*old), logic.lots(), 15 * 60))
    assert d["soldUnits"] == 3
    # 3 hours later: the "2-12 h" lot may have expired on its own.
    d = to_py(logic.ns.ScanDiff.Diff(logic.lots(*old), logic.lots(), 3 * 3600))
    assert {r["price"]: r["verdict"] for r in d["removed"]} == {10: "sold", 20: "unknown"}
    # Two days later: nothing can be called a sale.
    d = to_py(logic.ns.ScanDiff.Diff(logic.lots(*old), logic.lots(), 2 * 86400))
    assert d["soldUnits"] == 0 and d["unknownUnits"] == 3


def test_identical_lots_one_sold(logic):
    old = [(1, 50, VERYLONG), (1, 50, VERYLONG), (1, 50, LONG)]
    new = [(1, 50, VERYLONG), (1, 50, LONG)]
    d = diff(logic, old, new)
    assert d["soldUnits"] == 1
    assert d["added"] == []


def test_matching_prefers_lots_that_can_still_match(logic):
    # Old: one SHORT, one VERYLONG. New: one LONG. The VERYLONG became LONG; the SHORT expired.
    d = diff(logic, [(1, 50, SHORT), (1, 50, VERYLONG)], [(1, 50, LONG)])
    assert [r["verdict"] for r in d["removed"]] == ["expired"]
    assert d["added"] == []


def test_stack_reduced_counts_as_partial_sale(logic):
    d = diff(logic, [(100, 7, VERYLONG)], [(60, 7, VERYLONG)])
    assert d["removed"] == [] and d["added"] == []
    assert d["reduced"] == [{"price": 7, "from": 100, "to": 60, "tl": VERYLONG}]
    assert d["soldUnits"] == 40
    assert d["soldValue"] == 280


def test_stack_growth_is_not_reduction(logic):
    d = diff(logic, [(10, 7, VERYLONG)], [(60, 7, VERYLONG)])
    assert d["reduced"] == []
    assert len(d["removed"]) == 1 and len(d["added"]) == 1


def test_new_lots_only(logic):
    d = diff(logic, [], [(3, 9, VERYLONG)])
    assert d["changed"]
    assert d["added"] == [{"qty": 3, "price": 9, "tl": VERYLONG}]


def test_encode_is_canonical_and_round_trips(logic):
    lots = logic.ns.Lots
    a = lots.Encode(logic.lots((5, 20, 2), (1, 100, 3), (1, 20, 1)))
    b = lots.Encode(logic.lots((1, 20, 1), (1, 100, 3), (5, 20, 2)))
    assert a == b == "1:20:1,5:20:2,1:100:3"
    assert to_py(lots.Decode(a)) == [
        {"qty": 1, "price": 20, "tl": 1},
        {"qty": 5, "price": 20, "tl": 2},
        {"qty": 1, "price": 100, "tl": 3},
    ]
    assert to_py(lots.Decode("")) == []


def test_band_from_seconds(logic):
    band = logic.ns.Lots.BandFromSeconds
    assert band(60) == SHORT
    assert band(3600) == MEDIUM
    assert band(8 * 3600) == LONG
    assert band(13 * 3600) == VERYLONG
