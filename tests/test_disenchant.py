import pytest

from conftest import to_py

ARMOR, WEAPON = 4, 2
GREEN, BLUE, PURPLE = 2, 3, 4
STRANGE_DUST, LESSER_ASTRAL, SMALL_GLIMMERING = 10940, 10998, 10978


def outcomes(logic, cls, q, ilvl):
    return to_py(logic.ns.Disenchant.Outcomes(cls, q, ilvl))


def test_green_armor_ilvl_22(logic):
    o = outcomes(logic, ARMOR, GREEN, 22)
    assert o == [
        {"chance": 0.75, "itemID": STRANGE_DUST, "min": 4, "max": 6},
        {"chance": 0.20, "itemID": LESSER_ASTRAL, "min": 1, "max": 2},
        {"chance": 0.05, "itemID": SMALL_GLIMMERING, "min": 1, "max": 1},
    ]


def test_weapon_swaps_dust_and_essence(logic):
    o = outcomes(logic, WEAPON, GREEN, 22)
    assert [x["chance"] for x in o] == [0.20, 0.75, 0.05]


def test_blue_always_shard(logic):
    assert outcomes(logic, ARMOR, BLUE, 22) == [{"chance": 1, "itemID": SMALL_GLIMMERING, "min": 1, "max": 1}]


@pytest.mark.parametrize("cls, q, ilvl", [(15, GREEN, 20), (ARMOR, 1, 20), (ARMOR, 5, 60), (ARMOR, PURPLE, 30), (ARMOR, GREEN, 99)])
def test_not_disenchantable(logic, cls, q, ilvl):
    assert logic.ns.Disenchant.Outcomes(cls, q, ilvl) is None


def test_chances_sum_to_one(logic):
    for cls in (ARMOR, WEAPON):
        for q, top in ((GREEN, 65), (BLUE, 65), (PURPLE, 80)):
            for ilvl in range(1, top + 1):
                o = outcomes(logic, cls, q, ilvl)
                if o:
                    assert sum(x["chance"] for x in o) == pytest.approx(1), (cls, q, ilvl)


def test_value_formula(logic):
    prices = {STRANGE_DUST: 14_00, LESSER_ASTRAL: 60_00, SMALL_GLIMMERING: 1_00_00}
    o = logic.ns.Disenchant.Outcomes(ARMOR, GREEN, 22)
    value, breakdown, complete = logic.ns.Disenchant.Value(o, lambda item: prices.get(item))
    # 0.75 * 5 * 1400 + 0.20 * 1.5 * 6000 + 0.05 * 1 * 10000
    assert value == 5250 + 1800 + 500
    assert complete
    assert len(to_py(breakdown)) == 3


def test_value_with_missing_price(logic):
    o = logic.ns.Disenchant.Outcomes(ARMOR, GREEN, 22)
    value, _, complete = logic.ns.Disenchant.Value(o, lambda item: 1400 if item == STRANGE_DUST else None)
    assert value == 5250
    assert not complete


def item(logic, **kw):
    base = {"bag": 0, "slot": 1, "itemID": 1, "quality": GREEN, "classID": ARMOR, "ilvl": 20,
            "inSet": False, "locked": False, "bound": False}
    base.update(kw)
    return base


def test_pick_skips_ineligible(logic):
    items = logic.to_lua([
        item(logic, slot=1, quality=1),                 # grey/white
        item(logic, slot=2, quality=BLUE),              # blue, rules allow green only
        item(logic, slot=3, inSet=True),
        item(logic, slot=4, itemID=99),                 # excluded
        item(logic, slot=5, classID=0),                 # consumable
        item(logic, slot=6),                            # ok
        item(logic, slot=7, locked=True),
        item(logic, slot=8),                            # ok
    ])
    rules = logic.to_lua({"quality": "green", "exclude": {99: True}})
    nxt, count = logic.ns.DisenchantPick.Next(items, rules)
    assert nxt["slot"] == 6
    assert count == 2


def test_pick_blue_and_better_to_sell(logic):
    items = logic.to_lua([item(logic, slot=1, quality=BLUE, itemID=5), item(logic, slot=2, itemID=6)])
    rules = logic.to_lua({"quality": "greenblue", "skipBetterToSell": True})
    rules.deValue = lambda it: 100
    rules.sellValue = lambda it: 500 if it.itemID == 5 else 50
    nxt, count = logic.ns.DisenchantPick.Next(items, rules)
    assert nxt["slot"] == 2 and count == 1


def test_bound_items_disenchant_even_if_ah_price_higher(logic):
    items = logic.to_lua([item(logic, bound=True)])
    rules = logic.to_lua({"quality": "green", "skipBetterToSell": True})
    rules.deValue = lambda it: 100
    rules.sellValue = lambda it: 500
    _, count = logic.ns.DisenchantPick.Next(items, rules)
    assert count == 1
