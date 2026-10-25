"""Deals, selling, vendor, stock, import/export, trade, recipes, mail extras: whole-addon scenarios."""

import pytest

from conftest import Addon, to_py, toc_files

LINEN, GLOVES, DUST, ESSENCE, SHARD, JUNK, BOLT = 2589, 5000, 10940, 10998, 10978, 3300, 2996
VERYLONG = 3
KEY = "TestRealm|Horde"


@pytest.fixture
def game(addon):
    addon.lua.execute(f"""
        WowMock.items[{LINEN}] = {{ name = "Linen Cloth", quality = 1, ilvl = 5, classID = 7, sellPrice = 13, stack = 20 }}
        WowMock.items[{GLOVES}] = {{ name = "Gloves", quality = 2, ilvl = 22, classID = 4, sellPrice = 300 }}
        WowMock.items[{DUST}] = {{ name = "Strange Dust", quality = 1, ilvl = 1, classID = 7, sellPrice = 0, stack = 20 }}
        WowMock.items[{ESSENCE}] = {{ name = "Lesser Astral Essence", quality = 2, ilvl = 1, classID = 7, sellPrice = 0, stack = 20 }}
        WowMock.items[{SHARD}] = {{ name = "Small Glimmering Shard", quality = 3, ilvl = 1, classID = 7, sellPrice = 0, stack = 20 }}
        WowMock.items[{JUNK}] = {{ name = "Broken Tooth", quality = 0, ilvl = 1, classID = 15, sellPrice = 50 }}
        WowMock.items[{BOLT}] = {{ name = "Bolt of Linen Cloth", quality = 1, ilvl = 5, classID = 7, sellPrice = 40, stack = 20 }}
    """)
    addon.login()
    return addon


def run(game, code):
    game.lua.execute(code)


def set_replicate(game, rows):
    body = ", ".join(f"{{ {i}, {c}, {b}, {t} }}" for i, c, b, t in rows)
    run(game, f"WowMock.replicate = {{ {body} }}")


def scan(game, rows):
    if not game.ns.Scan.ahOpen:
        game.fire("AUCTION_HOUSE_SHOW")
    set_replicate(game, rows)
    game.g.BaryshDB.lastReplicate = None
    game.ns.Scan.StartFull("button")
    game.mock.Advance(4)
    assert game.ns.Scan.state == "idle"


def synced(game, prices):
    """Market prices as if BaryshSync had sent them: {itemID: (price, perDay, scans)}."""
    game.ns.market.ah = game.to_lua({KEY: {i: list(v) for i, v in prices.items()}})
    game.ns.market.generated = game.g.time()
    game.ns.Prices.Invalidate()


def compute_deals(game):
    game.ns.DealsModule.Compute()
    game.mock.RunFrames(20)
    return to_py(game.ns.DealsModule.rows)


MATS = [(DUST, 20, 20 * 1400, VERYLONG), (ESSENCE, 5, 5 * 6000, VERYLONG), (SHARD, 2, 2 * 10000, VERYLONG)]


def test_commodity_resale_deal_and_purchase(game):
    synced(game, {LINEN: (100, 200.0, 40)})
    scan(game, [(LINEN, 20, 20 * 40, VERYLONG), (LINEN, 20, 20 * 60, VERYLONG), (LINEN, 50, 50 * 99, VERYLONG)] + MATS)
    rows = [r for r in compute_deals(game) if r["itemID"] == LINEN]
    assert len(rows) == 1
    row = rows[0]
    assert row["type"] == "resale" and row["qty"] == 40 and row["maxPrice"] == 60
    assert row["cost"] == 20 * 40 + 20 * 60

    run(game, f"WowMock.commodityQuote = {row['cost']}")
    lua_row = next(r for r in game.ns.DealsModule.rows.values() if r.itemID == LINEN)
    assert game.ns.DealsModule.Buy(lua_row)
    game.mock.Advance(1)
    kinds = [p["kind"] for p in to_py(game.mock.purchases)]
    assert kinds == ["start", "confirm"]
    assert lua_row.bought
    assert game.g.BaryshDB.purchases[LINEN].type == "resale"
    # The bought lots left the snapshot.
    assert game.g.BaryshDB.ah[KEY].snap[LINEN] == "50:99:3"
    assert game.errors() == []


def test_commodity_purchase_cancelled_when_price_rises(game):
    synced(game, {LINEN: (100, 200.0, 40)})
    scan(game, [(LINEN, 20, 20 * 40, VERYLONG), (LINEN, 50, 50 * 99, VERYLONG)])
    compute_deals(game)
    lua_row = next(r for r in game.ns.DealsModule.rows.values() if r.itemID == LINEN)
    run(game, f"WowMock.commodityQuote = {lua_row.cost + 500}")
    game.ns.DealsModule.Buy(lua_row)
    game.mock.Advance(1)
    assert [p["kind"] for p in to_py(game.mock.purchases)] == ["start", "cancel"]
    assert not lua_row.bought
    assert any("Цена выросла" in line for line in game.mock.printed.values())


def test_item_deal_found_by_search_then_bought(game):
    # Gloves on sale far below their disenchant value.
    scan(game, [(GLOVES, 1, 2000, VERYLONG)] + MATS)
    rows = compute_deals(game)
    gloves = [r for r in rows if r["itemID"] == GLOVES]
    assert gloves and gloves[0]["type"] == "disenchant"
    D = game.ns.DealsModule
    row = next(r for r in D.rows.values() if r.itemID == GLOVES)
    assert D.ButtonState(row) == "search"
    run(game, f"WowMock.searchResults[{GLOVES}] = {{ commodity = false, rows = {{ {{ 1, 2000, 3, 777 }} }} }}")
    assert not D.Buy(row)  # first click finds the lot
    game.mock.Advance(1)
    assert row.auctionID == 777 and D.ButtonState(row) == "buy"
    assert D.Buy(row)
    game.mock.Advance(1)
    assert to_py(game.mock.purchases)[-1] == {"kind": "bid", "auctionID": 777, "amount": 2000}
    assert row.bought
    assert game.errors() == []


def test_no_buy_list_and_alert_sound(game):
    synced(game, {LINEN: (1000, 500.0, 40)})
    game.ns.settings.deals.soundFrom = 1000
    scan(game, [(LINEN, 20, 20 * 400, VERYLONG), (LINEN, 50, 50 * 990, VERYLONG)])
    assert any(r["itemID"] == LINEN for r in to_py(game.ns.DealsModule.rows))
    assert len(game.mock.sounds) == 1
    game.ns.ItemLists.Add("noBuy", LINEN)
    assert not any(r["itemID"] == LINEN for r in compute_deals(game))


def bag(game, slot, item, count=1, bag_=0):
    run(game, f"WowMock.bags[{bag_}][{slot}] = {{ itemID = {item}, count = {count} }}")


def test_selling_queue_posts_one_lot_per_click(game):
    synced(game, {LINEN: (100, 300.0, 40)})
    scan(game, [(LINEN, 20, 20 * 90, VERYLONG)])
    bag(game, 1, LINEN, 20)
    bag(game, 2, LINEN, 5)
    S = game.ns.SellingModule
    q = to_py(S.Build())
    assert len(q) == 1
    e = q[0]
    assert e["qty"] == 25 and e["price"] == 90 and e["sizes"] == [25] and e["duration"] == "short"
    ok = S.PostNext()
    assert ok is True or ok[0]
    post = to_py(game.mock.posts)[-1]
    assert post == {"kind": "commodity", "bag": 0, "slot": 1, "duration": 2, "qty": 25, "price": 90}
    assert len(S.queue) == 0
    assert to_py(game.g.BaryshDB.posted)[-1]["deposit"] == 10 * 25 * 2
    assert game.errors() == []


def test_selling_stacks_and_confirmation(game):
    synced(game, {LINEN: (100, 300.0, 40)})
    scan(game, [(LINEN, 20, 20 * 90, VERYLONG)])
    bag(game, 1, LINEN, 45)
    game.ns.settings.selling.stack = 20
    S = game.ns.SellingModule
    assert to_py(S.Build())[0]["sizes"] == [20, 20, 5]
    run(game, "WowMock.postNeedsConfirm = true")
    S.PostNext()
    assert S.confirm is not None
    S.PostNext()  # second click confirms
    assert to_py(game.mock.posts)[-1]["kind"] == "confirm"
    S.PostNext()
    S.PostNext()
    assert [p["qty"] for p in to_py(game.mock.posts)] == [20, 20, 20, 5]
    assert len(S.queue) == 0


def test_selling_skips_stock_and_takes_returned(game):
    synced(game, {LINEN: (100, 300.0, 40)})
    scan(game, [(LINEN, 20, 20 * 90, VERYLONG)])
    bag(game, 1, LINEN, 20)
    game.ns.ItemLists.Add("stock", LINEN)
    assert len(game.ns.SellingModule.Build()) == 0
    game.g.BaryshDB.returned = game.to_lua({LINEN: 20})
    q = to_py(game.ns.SellingModule.Build())
    assert q[0]["returned"] is True


def test_own_lots_state_and_cancel(game):
    synced(game, {LINEN: (100, 10.0, 40)})
    scan(game, [(LINEN, 50, 50 * 80, VERYLONG), (LINEN, 20, 20 * 120, VERYLONG)])
    run(game, f"WowMock.owned = {{ {{ 91, {LINEN}, 20, 2400 }} }}")
    game.ns.Scan.ahOpen = True
    owned = to_py(game.ns.SellingModule.Owned())
    assert owned[0]["state"] == "undercut" and owned[0]["cheaper"] == 50 and owned[0]["newPrice"] == 80
    lot = game.ns.SellingModule.owned[1]
    assert game.ns.SellingModule.Cancel(lot)
    assert to_py(game.mock.cancels) == [91]
    assert game.g.BaryshDB.sellMarked[LINEN]


def test_vendor_sells_junk_and_records(game):
    bag(game, 1, JUNK, 3)
    bag(game, 2, LINEN, 20)
    run(game, "WowMock.merchantOpen = true; WowMock.money = 0")
    game.fire("MERCHANT_SHOW")
    V = game.ns.Vendor
    cands = to_py(V.Candidates())
    assert [c["itemID"] for c in cands] == [JUNK]
    assert V.SellAll()
    game.mock.Advance(1)
    assert game.mock.money == 150
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "vendor_sell" and op["amount"] == 150
    assert game.errors() == []


def test_vendor_purchase_recorded(game):
    run(game, f"WowMock.merchant = {{ {{ {BOLT}, 160, 1 }} }}")
    game.fire("MERCHANT_SHOW")
    game.g.BuyMerchantItem(1, 4)
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "vendor_buy" and op["amount"] == -640 and op["qty"] == 4
    assert game.ns.CostBasis.Average(game.g.BaryshDB.books, BOLT) == 160


def test_easy_money_purchase_goes_to_vendor(game):
    game.g.BaryshDB.purchases = game.to_lua({BOLT: {"type": "easy", "t": 1}})
    bag(game, 1, BOLT, 2)
    assert to_py(game.ns.Vendor.Candidates())[0]["reason"] == "easy"


def test_stock_positions_and_exit_after_three_days(game):
    synced(game, {BOLT: (1000, 5.0, 40)})
    game.ns.ItemLists.Add("stock", BOLT, game.to_lua({"note": "под рейд"}))
    bag(game, 1, BOLT, 10)
    game.ns.Inventory.SaveBags()
    game.ns.CostBasis.Add(game.g.BaryshDB.books, BOLT, 10, 12000)
    positions, totals = game.ns.StockModule.Positions()
    p = to_py(positions)[0]
    assert p["qty"] == 10 and p["invested"] == 12000 and p["worth"] == 9500 and p["below"] is True
    assert p["note"] == "под рейд" and not p["exit"]
    game.mock.Advance(2 * 86400 + 60)
    p = to_py(game.ns.StockModule.Positions()[0])[0]
    assert p["exit"] is True
    assert game.ns.StockModule.ExitCount() == 1


def test_import_export_list_between_installs(game):
    game.ns.ItemLists.Add("stock", BOLT, game.to_lua({"buyBelow": 900, "note": "ящики"}))
    game.ns.ItemLists.Add("stock", LINEN)
    text = game.ns.ImportExport.ExportList("stock")
    assert text.startswith("!BARYSH:1!list:stock!")

    other = Addon(toc_files())
    other.login()
    preview = other.ns.ImportExport.Preview(text)
    assert to_py(preview.diff) == {"add": [LINEN, BOLT], "remove": [], "change": []}
    other.ns.ImportExport.Apply(preview)
    entry = other.ns.ItemLists.Entry("stock", BOLT)
    assert entry.buyBelow == 900 and entry.note == "ящики" and entry.src == "import"


def test_import_export_settings(game):
    game.ns.settings.deals.minProfit = 2500
    game.ns.ItemLists.Create("Рейд")
    game.ns.ItemLists.Add("Рейд", LINEN)
    game.ns.SetModuleEnabled("Neutral", True)
    text = game.ns.ImportExport.ExportSettings()
    other = Addon(toc_files())
    other.login()
    p = other.ns.ImportExport.Preview(text)
    paths = [c["path"] for c in to_py(p.changes)]
    assert "deals.minProfit" in paths
    other.ns.ImportExport.Apply(p)
    assert other.ns.settings.deals.minProfit == 2500
    assert other.ns.ItemLists.Has("Рейд", LINEN)
    assert other.ns.modules.Neutral.enabled


def test_import_rejects_garbage(game):
    assert game.ns.ImportExport.Preview("hello") == (None, "format")


def trade(game, player=(), target=(), player_money=0, target_money=0, enchant=None, partner="Client"):
    def items(lst):
        return "{" + ", ".join(f"{{ {i}, {c} }}" for i, c in lst) + "}"
    run(game, f"""
        WowMock.tradePartner = "{partner}"
        WowMock.trade = {{ player = {items(player)}, target = {items(target)},
            playerMoney = {player_money}, targetMoney = {target_money}, enchant = {('"' + enchant + '"') if enchant else 'nil'} }}
    """)
    game.fire("TRADE_SHOW")
    game.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    game.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    game.fire("TRADE_CLOSED")


def test_trade_service_is_recorded(game):
    game.ns.settings.trade.services = game.to_lua([{"name": "Enchant Bracer - Stamina", "client": 5000, "reagents": []}])
    trade(game, target_money=5000, enchant="Enchant Bracer - Stamina")
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "service" and op["amount"] == 5000
    assert game.g.BaryshDB.clients.Client.orders == 1
    assert game.errors() == []


def test_trade_craft_order_uses_client_reagents(game):
    run(game, f"""WowMock.recipes = {{ {{ recipeID = 2963, name = "Bolt of Linen Cloth", output = {BOLT}, difficulty = 1,
        reagents = {{ {{ {LINEN}, 2 }} }} }} }}""")
    game.fire("TRADE_SKILL_SHOW")
    game.mock.Advance(1)
    trade(game, target=[(LINEN, 2)])            # client brings reagents
    assert to_py(game.g.BaryshDB.orders)["Client"] == [{"itemID": LINEN, "qty": 2}]
    trade(game, player=[(BOLT, 1)], target_money=3000)
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "craft" and op["amount"] == 3000 and op["profit"] == 3000
    assert game.g.BaryshDB.orders.Client is None


def test_trade_unclear_asks_and_fix_undoes(game):
    trade(game, target_money=700)                # gold for nothing: ask
    assert game.g.BaryshTradeAsk.shown
    assert any("незнакомца" in line for line in game.mock.printed.values())
    game.ns.TradeModule.Answer(game.g.BaryshTradeAsk.trade, "service")
    assert to_py(game.g.BaryshDB.ledger.ops)[-1]["kind"] == "service"
    n = len(game.g.BaryshDB.ledger.ops)
    trade(game, player=[(BOLT, 1)], target_money=900)   # sale, recorded automatically
    assert len(game.g.BaryshDB.ledger.ops) == n + 1
    game.ns.TradeModule.Fix()
    assert len(game.g.BaryshDB.ledger.ops) == n


def test_recipes_panel_plan_and_shopping(game):
    synced(game, {LINEN: (100, 50.0, 40), BOLT: (600, 10.0, 40)})
    run(game, f"""WowMock.recipes = {{ {{ recipeID = 2963, name = "Bolt of Linen Cloth", output = {BOLT}, difficulty = 0,
        reagents = {{ {{ {LINEN}, 2 }} }} }} }}""")
    game.fire("TRADE_SKILL_SHOW")
    game.mock.Advance(1)
    rows, plan = game.ns.RecipesModule.Evaluate()
    r = to_py(rows)[0]
    assert r["cost"] == 200 and r["sale"] == 570 and r["profit"] == 370
    assert to_py(plan)["steps"][0]["points"] == 10  # 60 -> 75, one recipe covers 10
    assert game.g.BaryshRecipes.shown
    game.ns.RecipesModule.ShoppingList()
    assert game.ns.ItemLists.Has("quick", LINEN)
    game.ns.RecipesModule.CraftNext()
    assert to_py(game.mock.crafts) == [2963]
    # Known recipe makes linen a "raw materials" deal when it is cheap enough.
    values = to_py(game.ns.DealsModule.ReagentValues(KEY))
    assert values[LINEN]["value"] == 285
    assert game.errors() == []


def make_mail(game):
    run(game, f"""
        WowMock.money = 10000
        WowMock.inbox = {{
            {{ sender = "Seller", subject = "Bolts", cod = 1000, items = {{ {{ {BOLT}, 5 }} }} }},
            {{ sender = "Stranger", subject = "gift", money = 50000 }},
            {{ sender = "Tester", subject = "from alt", items = {{ {{ {LINEN}, 20 }} }} }},
        }}
    """)
    game.fire("MAIL_SHOW")


def test_mail_cod_verdict_and_pay(game):
    synced(game, {BOLT: (600, 10.0, 40)})
    make_mail(game)
    inbox = to_py(game.ns.Mail.ReadInbox())
    assert [m["kind"] for m in inbox["other"]] == ["cod", "stranger_gold", "own"]
    info = to_py(game.ns.Mail.CodInfo(1))
    assert info["value"] == 5 * 570 and info["verdict"] == "good" and info["profit"] == 5 * 570 - 1000
    assert game.ns.Mail.PayCod(1)
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "cod" and op["amount"] == -1000
    assert game.ns.CostBasis.Average(game.g.BaryshDB.books, BOLT) == 200
    assert game.mock.money == 9000


def test_mail_return_stranger_gold(game):
    make_mail(game)
    game.ns.Mail.Return(2)
    assert to_py(game.mock.returned) == ["gift"]


def test_lost_deposit_recorded_for_expired_lot(game):
    game.g.BaryshDB.posted = game.to_lua([{"itemID": LINEN, "qty": 20, "price": 90, "deposit": 400, "t": 1}])
    run(game, f"""WowMock.inbox = {{ {{ sender = "Auction House", subject = "Auction expired: Linen Cloth",
        items = {{ {{ {LINEN}, 20 }} }} }} }}""")
    game.fire("MAIL_SHOW")
    game.ns.Mail.Collect()
    game.mock.Advance(3)
    op = to_py(game.g.BaryshDB.ledger.ops)[-1]
    assert op["kind"] == "ah_expired" and op["amount"] == -400
    assert len(game.g.BaryshDB.posted) == 0


def test_capital_and_overview(game):
    synced(game, {LINEN: (100, 50.0, 40)})
    run(game, "WowMock.money = 50000")
    bag(game, 1, LINEN, 20)
    game.fire("PLAYER_MONEY")
    game.ns.Inventory.SaveBags()
    cap = to_py(game.ns.Stock.Capital(game.g.BaryshDB.chars, game.ns.UI.CapitalValue))
    assert cap["gold"] == 50000 and cap["bags"] == 20 * 95
    game.ns.UI.Show("overview")
    game.mock.RunFrames(15)
    assert game.errors() == []


def test_market_info(game):
    for i, price in enumerate([100, 120, 90]):
        scan(game, [(LINEN, 20, 20 * price, VERYLONG), (LINEN, 1, 30, VERYLONG), (LINEN, 40, 40 * 150, VERYLONG)])
        game.mock.Advance(3600)
    info = to_py(game.ns.MarketModule.Info(LINEN, KEY, "week"))
    assert info["min"] == 30 and info["onMarket"] == 61
    assert info["verdicts"]["dumper"] == {"price": 30, "units": 1}
    assert len(info["series"]) == 24
    assert game.ns.MarketModule.Find("linen cloth") == LINEN
    game.ns.MarketModule.RequestExport(game.to_lua([LINEN]))
    assert to_py(game.g.BaryshDB.exportRequests)[0]["items"] == [LINEN]


def test_every_tab_and_settings_group_render(game):
    for m in ("Neutral", "Sync"):
        game.ns.SetModuleEnabled(m, True)
    synced(game, {LINEN: (100, 200.0, 40)})
    scan(game, [(LINEN, 20, 20 * 40, VERYLONG), (GLOVES, 1, 2000, VERYLONG)] + MATS)
    bag(game, 1, LINEN, 20)
    ui = game.ns.UI
    ui.Show()
    for tab in ("overview", "deals", "selling", "stock", "market", "ledger", "mail"):
        ui.SelectTab(tab)
        assert ui.current.id == tab
        game.mock.RunFrames(12)
    win = ui.Settings()
    ui.ToggleSettings()
    for g in ("core", "trade", "craft", "money", "service"):
        b = win.groupButtons[["core", "trade", "craft", "money", "service"].index(g) + 1]
        b.Click(b)
        game.mock.RunFrames(2)
    ui.ImportDialog()
    ui.EditPriceList()
    assert game.errors() == []


def test_settings_reset_group(game):
    game.ns.settings.deals.minProfit = 999
    win = game.ns.UI.Settings()
    game.ns.UI.ToggleSettings()
    trade_btn = win.groupButtons[2]
    trade_btn.Click(trade_btn)
    win.reset.Click(win.reset)
    assert game.ns.settings.deals.minProfit == 100
