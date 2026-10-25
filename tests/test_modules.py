"""Whole-addon scenarios against the imitation client."""

import pytest

from conftest import to_py

LINEN, GLOVES, DUST, ESSENCE, SHARD = 2589, 5000, 10940, 10998, 10978
VERYLONG, LONG, SHORT = 3, 2, 0


@pytest.fixture
def game(addon):
    addon.lua.execute(f"""
        WowMock.items[{LINEN}] = {{ name = "Linen Cloth", quality = 1, ilvl = 5, classID = 7, sellPrice = 13, stack = 20 }}
        WowMock.items[{GLOVES}] = {{ name = "Gloves", quality = 2, ilvl = 22, classID = 4, sellPrice = 300 }}
        WowMock.items[{DUST}] = {{ name = "Strange Dust", quality = 1, ilvl = 1, classID = 7, sellPrice = 0 }}
        WowMock.items[{ESSENCE}] = {{ name = "Lesser Astral Essence", quality = 2, ilvl = 1, classID = 7, sellPrice = 0 }}
        WowMock.items[{SHARD}] = {{ name = "Small Glimmering Shard", quality = 3, ilvl = 1, classID = 7, sellPrice = 0 }}
    """)
    addon.login()
    addon.ns.SetModuleEnabled("Sync", True)
    return addon


def run(game, code):
    game.lua.execute(code)


def set_replicate(game, rows):
    """rows: (itemID, count, buyout for the whole lot, tl)"""
    body = ", ".join(f"{{ {i}, {c}, {b}, {t} }}" for i, c, b, t in rows)
    run(game, f"WowMock.replicate = {{ {body} }}")


def open_ah(game):
    game.fire("AUCTION_HOUSE_SHOW")


def full_scan(game):
    ok = game.ns.Scan.StartFull("button")
    assert ok is True or ok == (True,) or (isinstance(ok, tuple) and ok[0])
    game.mock.Advance(3)
    assert game.ns.Scan.state == "idle"


def house(game):
    return game.g.BaryshDB.ah["TestRealm|Horde"]


MARKET = [
    (LINEN, 20, 20 * 10, VERYLONG),
    (LINEN, 20, 20 * 10, VERYLONG),
    (LINEN, 5, 5 * 12, LONG),
    (GLOVES, 1, 5000, VERYLONG),
    (DUST, 10, 10 * 1400, VERYLONG),
    (ESSENCE, 2, 2 * 6000, VERYLONG),
    (SHARD, 1, 10000, VERYLONG),
]


def test_full_scan_saves_snapshot_history_and_outbox(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    h = house(game)
    assert h.snap[LINEN] == "20:10:3,20:10:3,5:12:2"
    assert h.hist[LINEN][1].p == 10
    assert h.hist[LINEN][1].q == 45
    assert len(h.scans) == 1
    out = to_py(game.g.BaryshDB.outbox)
    assert len(out) == 1 and out[0]["full"] is True and out[0]["rows"] == len(MARKET)
    assert out[0]["items"][LINEN]["a"] == "20:10:3,20:10:3,5:12:2"
    assert game.g.BaryshDB.lastReplicate is not None
    probe = to_py(game.g.BaryshDB.probe.scans)
    assert probe[-1]["result"] == "ok" and probe[-1]["rows"] == len(MARKET)
    assert game.errors() == []


def test_second_scan_records_sales_and_respects_cooldown(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    ok, why, left = game.ns.Scan.StartFull("button")
    assert not ok and why == "cooldown" and left > 0
    # The 15-minute timer rescans the unchanged market, then the market changes:
    # one linen stack sold, gloves vanished with >12 h left, dust stack shrank by 4.
    game.mock.Advance(15 * 60)
    set_replicate(game, [r for r in MARKET if r[0] not in (GLOVES, DUST)][1:] + [(DUST, 6, 6 * 1400, VERYLONG)])
    game.mock.Advance(16 * 60)
    h = house(game)
    assert len(h.scans) == 3
    sales = to_py(h.sales)
    assert sum(sales[LINEN].values()) == 20
    assert sum(sales[GLOVES].values()) == 1
    assert sum(sales[DUST].values()) == 4
    assert h.snap[GLOVES] is None
    assert h.hist[GLOVES][len(h.hist[GLOVES])].q == 0
    assert game.errors() == []


def test_timer_mode_scans_every_15_minutes(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    calls = game.mock.replicateCalls
    game.mock.Advance(15 * 60 + 10)
    assert game.mock.replicateCalls == calls + 1


def test_auto_scan_without_answer_switches_to_sound(game):
    run(game, "WowMock.replicateBlocked = true")
    game.ns.settings.scan.onOpen = True
    open_ah(game)
    assert game.ns.Scan.state == "waiting"
    assert len(game.mock.sounds) == 0
    game.mock.Advance(40)
    assert game.ns.Scan.state == "idle"
    assert game.g.BaryshDB.autoScanNeedsClick is True
    assert len(game.mock.sounds) == 1
    game.mock.Advance(60)
    assert len(game.mock.sounds) == 1  # reminds once per cooldown
    assert game.mock.replicateCalls == 1  # and does not try again on its own


def test_scan_blocked_event_marks_click_needed(game):
    open_ah(game)
    game.fire("ADDON_ACTION_FORBIDDEN", "Barysh", "C_AuctionHouse.ReplicateItems()")
    assert game.g.BaryshDB.autoScanNeedsClick is True


def test_quick_scan_updates_listed_items(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    run(game, f"""
        WowMock.searchResults[{LINEN}] = {{ commodity = true, rows = {{ {{ 30, 9, 50000, 1 }}, {{ 5, 12, 7000, 2 }} }} }}
        WowMock.searchResults[{GLOVES}] = {{ commodity = false, rows = {{ {{ 1, 4500, 3, 3 }} }} }}
    """)
    game.ns.settings.lists.quick = game.to_lua([LINEN, GLOVES])
    ok = game.ns.Scan.StartQuick()
    assert ok is True or (isinstance(ok, tuple) and ok[0])
    game.mock.Advance(5)
    assert game.ns.Scan.state == "idle"
    h = house(game)
    assert h.snap[LINEN] == "30:9:3,5:12:1"  # 7000 s left = "30 min - 2 h"
    assert h.snap[GLOVES] == "1:4500:3"
    assert to_py(game.mock.searchCalls) == [LINEN, GLOVES]
    assert game.errors() == []


def test_prices_prefer_pc_data_with_more_scans(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    s = game.ns.Prices.Item(LINEN)
    assert s.current == 10 and s.isNew
    game.ns.market.ah = game.to_lua({"TestRealm|Horde": {LINEN: [15, 120.0, 40]}})
    game.ns.Prices.Invalidate()
    s = game.ns.Prices.Item(LINEN)
    assert s.market == 15 and s.perDay == 120.0 and not s.isNew


def test_tooltip_shows_prices_and_disenchant(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    lines = to_py(game.mock.ShowItemTooltip(GLOVES))
    text = "\n".join(lines)
    assert "Barysh" in text
    assert "Аукцион | 5000c" in text
    # 0.75 * 5 * 1400 + 0.2 * 1.5 * 6000 + 0.05 * 10000 = 7550
    assert "Распыл | ≈ 7550c" in text
    run(game, "WowMock.shift = true")
    text = "\n".join(to_py(game.mock.ShowItemTooltip(GLOVES)))
    assert "Strange Dust" in text and "Лучше всего" in text
    assert game.errors() == []


def test_disenchanter_targets_next_item_and_records_loot(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    run(game, f"""
        WowMock.bags[0][1] = {{ itemID = {LINEN}, count = 20 }}
        WowMock.bags[0][2] = {{ itemID = {GLOVES} }}
    """)
    de = game.ns.Disenchanter
    game.ns.settings.disenchant.skipBetterToSell = False
    de.Update()
    b = game.g.BaryshDisenchantButton
    assert b.attributes.macrotext == "/cast Disenchant\n/use 0 2"
    assert de.count == 1
    game.ns.CostBasis.Add(game.g.BaryshDB.books, GLOVES, 1, 3000)
    b.Click(b)
    game.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262)
    run(game, f"WowMock.loot = {{ {{ {DUST}, 5 }}, {{ {ESSENCE}, 1 }} }}")
    game.fire("LOOT_READY")
    ops = to_py(game.g.BaryshDB.ledger.ops)
    assert ops[-1]["kind"] == "disenchant" and ops[-1]["itemID"] == GLOVES
    books = to_py(game.g.BaryshDB.books)
    assert GLOVES not in books and books[DUST]["c"] + books[ESSENCE]["c"] == 3000
    assert game.errors() == []


def test_disenchanter_waits_for_combat_end(game):
    run(game, f"WowMock.bags[0][2] = {{ itemID = {GLOVES} }}; WowMock.inCombat = true")
    de = game.ns.Disenchanter
    de.Update()
    assert de.pending
    run(game, "WowMock.inCombat = false")
    game.fire("PLAYER_REGEN_ENABLED")
    assert not de.pending
    assert game.mock.bindings["F"] == "BaryshDisenchantButton"


def test_disenchanter_skips_items_better_sold(game):
    open_ah(game)
    set_replicate(game, [(GLOVES, 1, 900000, VERYLONG)] + MARKET[4:])
    full_scan(game)
    run(game, f"WowMock.bags[0][2] = {{ itemID = {GLOVES} }}")
    game.ns.Disenchanter.Update()
    assert game.ns.Disenchanter.count == 0


def make_inbox(game):
    run(game, f"""
        WowMock.money = 0
        WowMock.inbox = {{
            {{ sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 950,
               invoice = {{ type = "seller", itemName = "Linen Cloth", bid = 0, buyout = 1000, deposit = 0, cut = 50, count = 20 }} }},
            {{ sender = "Friend", subject = "hi", money = 5000 }},
            {{ sender = "Auction House", subject = "Auction won: Gloves", items = {{ {{ {GLOVES}, 1 }} }},
               invoice = {{ type = "buyer", itemName = "Gloves", bid = 0, buyout = 4000, count = 1 }} }},
            {{ sender = "Auction House", subject = "Auction expired: Linen Cloth", items = {{ {{ {LINEN}, 20 }} }} }},
        }}
    """)


def test_mail_collects_only_auction_mail(game):
    make_inbox(game)
    game.ns.CostBasis.Add(game.g.BaryshDB.books, LINEN, 20, 600)
    game.fire("MAIL_SHOW")
    assert game.ns.Mail.Collect()
    game.mock.Advance(5)
    assert game.ns.Mail.collecting is None
    inbox = to_py(game.mock.inbox)
    assert len(inbox) == 1 and inbox[0]["sender"] == "Friend"
    assert game.mock.money == 950
    ops = {op["kind"]: op for op in to_py(game.g.BaryshDB.ledger.ops)}
    assert ops["ah_sell"]["amount"] == 950 and ops["ah_sell"]["profit"] == 950 - 600
    assert ops["ah_buy"]["amount"] == -4000
    assert ops["ah_expired"]["qty"] == 20
    assert game.ns.CostBasis.Average(game.g.BaryshDB.books, GLOVES) == 4000
    assert to_py(game.g.BaryshDB.returned) == {LINEN: 20}
    assert game.errors() == []


def test_mail_stops_when_bags_full(game):
    make_inbox(game)
    run(game, "WowMock.bagsFull = true")
    game.fire("MAIL_SHOW")
    game.ns.Mail.Collect()
    game.mock.Advance(5)
    assert game.ns.Mail.collecting is None
    assert any("сумки полны" in line for line in game.mock.printed.values())


def test_mail_collect_needs_open_mailbox(game):
    make_inbox(game)
    assert not game.ns.Mail.Collect()


def test_sync_ack_prunes_outbox_ledger_errors(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    game.ns.Record(game.to_lua({"kind": "ah_sell", "amount": 1, "t": 1}))
    game.ns.Safe(game.lua.eval("function() error('x') end"))
    t = game.g.BaryshDB.outbox[1].t
    game.ns.market.ack = game.to_lua({"scans": t, "ledger": 1, "errors": game.g.time() + 10})
    game.ns.Sync.ApplyAck()
    assert len(game.g.BaryshDB.outbox) == 0
    assert len(game.g.BaryshDB.ledger.ops) == 0
    assert len(game.g.BaryshDB.errors) == 0


def test_sync_off_keeps_no_outbox(game):
    game.ns.SetModuleEnabled("Sync", False)
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    assert game.g.BaryshDB.outbox is None


def test_main_window_and_tabs(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    ui = game.ns.UI
    frame = ui.Frame()
    assert frame.shown  # opened next to the auction house
    for tab in ("overview", "deals", "selling", "ledger", "mail"):
        ui.SelectTab(tab)
        assert ui.current.id == tab
    game.ns.SetModuleEnabled("Ledger", False)
    ledger_tab = next(t for t in to_py_tabs(game) if t.id == "ledger")
    assert not ledger_tab.button.shown
    game.fire("AUCTION_HOUSE_CLOSED")
    assert not frame.shown
    game.g.SlashCmdList.BARYSH("")
    assert frame.shown
    game.mock.RunFrames(70)
    assert game.errors() == []


def to_py_tabs(game):
    return [game.ns.UI.tabs[i] for i in range(1, len(game.ns.UI.tabs) + 1)]


def test_probe_records_environment(game):
    open_ah(game)
    set_replicate(game, MARKET)
    full_scan(game)
    game.g.SlashCmdList.BARYSH("probe")
    p = to_py(game.g.BaryshDB.probe)
    assert p["env"]["interface"] == 16001
    assert "C_AuctionHouse.PlaceBid" in p["env"]["missing"]
    assert len(p["replicateSample"]) == 5
    assert game.errors() == []


def test_slash_commands_do_not_error(game):
    for cmd in ("modules", "module Deals off", "module Deals on", "errors", "scan", "quick", "de", "de show", "nonsense"):
        game.g.SlashCmdList.BARYSH(cmd)
    assert game.errors() == []
