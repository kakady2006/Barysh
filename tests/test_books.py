"""Cost basis, ledger and auction mail recognition."""

import pytest

from conftest import to_py

SOLD = "Auction successful: %s"
WON = "Auction won: %s"
EXPIRED = "Auction expired: %s"
CANCELLED = "Auction cancelled: %s"
OUTBID = "Outbid on %s"


def test_cost_basis_weighted_average(logic):
    cb = logic.ns.CostBasis
    book = logic.table()
    cb.Add(book, 1, 10, 1000)   # 10 @ 100
    cb.Add(book, 1, 10, 3000)   # 10 @ 300
    assert cb.Average(book, 1) == 200
    assert cb.Remove(book, 1, 5) == 1000
    assert cb.Average(book, 1) == 200
    assert cb.Remove(book, 1, 100) == 3000  # only 15 left on the books
    assert cb.Average(book, 1) is None
    assert cb.Remove(book, 2, 1) == 0


def test_cost_basis_transfer_to_materials(logic):
    cb = logic.ns.CostBasis
    book = logic.table()
    cb.Add(book, 7, 1, 1000)
    moved = cb.Transfer(book, 7, 1, logic.to_lua([
        {"itemID": 100, "qty": 4, "value": 300},
        {"itemID": 200, "qty": 1, "value": 100},
    ]))
    assert moved == 1000
    assert cb.Average(book, 100) == 750 / 4
    assert cb.Average(book, 200) == 250
    assert cb.Average(book, 7) is None


def test_ledger_sum_and_since(logic):
    lg = logic.ns.Ledger
    ledger = lg.New()
    lg.Add(ledger, logic.to_lua({"t": 10, "kind": "ah_sell", "amount": 950, "profit": 450}))
    lg.Add(ledger, logic.to_lua({"t": 20, "kind": "ah_buy", "amount": -500}))
    lg.Add(ledger, logic.to_lua({"t": 30, "kind": "ah_sell", "amount": 100, "profit": 20}))
    s = to_py(lg.Sum(ledger, 0, 25))
    assert s == {"income": 950, "expense": 500, "profit": 450, "count": 2}
    s = to_py(lg.Sum(ledger, 0, 100, logic.to_lua({"ah_sell": True})))
    assert s["count"] == 2 and s["profit"] == 470
    assert [op["id"] for op in to_py(lg.Since(ledger, 1))] == [2, 3]
    lg.Trim(ledger, 2, 25)
    assert [op["id"] for op in to_py(ledger.ops)] == [3]


@pytest.fixture
def patterns(logic):
    mc = logic.ns.MailClassify
    return mc.BuildPatterns(logic.to_lua({
        "sold": SOLD, "won": WON, "expired": EXPIRED, "cancelled": CANCELLED, "outbid": OUTBID,
    }))


@pytest.mark.parametrize("subject, invoice, kind, name", [
    ("Auction successful: Linen Cloth", "seller", "sold", "Linen Cloth"),
    ("Auction won: Linen Cloth (20)", "buyer", "won", "Linen Cloth (20)"),
    ("Auction expired: Gloves", None, "expired", "Gloves"),
    ("Auction cancelled: Gloves", None, "cancelled", "Gloves"),
    ("Outbid on Gloves", None, "outbid", "Gloves"),
    ("Sale Pending: Gloves", "seller_temp_invoice", "pending", None),
    ("Hi from a friend", None, None, None),
    ("Auction expired? no", None, None, None),
])
def test_classify(logic, patterns, subject, invoice, kind, name):
    assert logic.ns.MailClassify.Classify(subject, invoice, patterns) == (kind, name)


def test_pattern_escapes_magic_characters(logic):
    p = logic.ns.MailClassify.PatternFromFormat("Аукцион (успешно) - 100%: %s")
    assert logic.lua.globals().string.match("Аукцион (успешно) - 100%: Ткань", p) == "Ткань"
