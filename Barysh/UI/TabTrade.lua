local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Deals, Selling, Stock and Market tabs. TZ: "Сделки", "Продажи", "Склад", "Вкладка «Рынок»".

local function itemCell(itemID, extra)
    return Items.ColoredName(itemID) .. (extra or "")
end

local function profitText(v)
    return UI.Colorize(money(v), v >= 0 and "profit" or "loss")
end

-- Deals ---------------------------------------------------------------------------------------

local DEAL_TYPES = ns.Deals.TYPES

UI.RegisterTab({
    id = "deals", label = L.TAB_DEALS, module = "Deals",
    build = function(c)
        c.filter = nil
        c.filters = {}
        local prev
        for i, kind in ipairs({ "all", unpack(DEAL_TYPES) }) do
            local b = UI.Button(c, "", 74, function()
                c.filter = kind ~= "all" and kind or nil
                UI.Refresh()
            end, L["DEALTIP_" .. kind])
            b:SetHeight(20)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT") end
            b.kind = kind
            c.filters[i] = b
            prev = b
        end
        c.affordable = UI.Check(c, L.DEALS_AFFORDABLE,
            function() return ns.settings.deals.affordable end,
            function(v) ns.settings.deals.affordable = v; UI.Refresh() end, L.DEALS_AFFORDABLE_TIP)
        c.affordable:SetPoint("TOPLEFT", 0, -24)
        c.header = UI.Text(c, "GameFontDisableSmall")
        c.header:SetPoint("TOPLEFT", 26, -50)
        c.header:SetText(L.DEALS_HEADER)
        c.list = UI.ScrollList(c, {
            { width = 156 }, { width = 58 }, { width = 64, justify = "RIGHT" }, { width = 64, justify = "RIGHT" },
            { width = 64, justify = "RIGHT" }, { width = 50, justify = "RIGHT" },
        }, 14, {
            button = {
                width = 62,
                text = function(d)
                    local st = ns.DealsModule.ButtonState(d)
                    if st == "confirm" then return L.BTN_CONFIRM end
                    return st == "search" and L.BTN_FIND or (st == "gone" and L.BTN_GONE or L.BTN_BUY)
                end,
                enabled = function(d)
                    local st = ns.DealsModule.ButtonState(d)
                    return st == "buy" or st == "search" or st == "confirm"
                end,
                onClick = function(d) ns.DealsModule.Buy(d) end,
            },
            onSelect = function(d) ns.DealsModule.Prepare(d) end,
            onEnter = function(row, d)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.itemID) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L.DEAL_BUY_LINE, (d.commodity and L.DEAL_UP_TO or "%s"):format(money(d.maxPrice)), 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddDoubleLine(L.DEAL_DAYS, UI.Days(d.days), 1, 0.82, 0, 1, 1, 1)
                GameTooltip:Show()
            end,
        })
        c.list:SetPoint("TOPLEFT", 0, -64)
        c.list:SetPoint("RIGHT")
        c.list:SetHeight(14 * 22)
        c.total = UI.Text(c, "GameFontHighlight")
        c.total:SetPoint("BOTTOMLEFT", 0, 6)
        c.total:SetWidth(400)
        c.buyNext = UI.Button(c, L.BTN_BUY_NEXT, 150, function() ns.DealsModule.BuyNext() end, L.TIP_BUY_NEXT)
        c.buyNext:SetPoint("BOTTOMRIGHT", 0, 0)
        c.recalc = UI.Button(c, L.BTN_RECALC, 100, function() ns.DealsModule.Compute() end)
        c.recalc:SetPoint("RIGHT", c.buyNext, "LEFT", -4, 0)
    end,
    refresh = function(c)
        local D = ns.DealsModule
        local affordable = ns.settings.deals.affordable
        c.affordable:Update()
        local sum = D.Summary(affordable)
        local all = 0
        for _, n in pairs(sum.counts) do all = all + n end
        for _, b in ipairs(c.filters) do
            local n = b.kind == "all" and all or sum.counts[b.kind] or 0
            b:SetText(("%s %d"):format(L["DEAL_" .. b.kind], n))
            b:SetEnabled((c.filter or "all") ~= b.kind)
        end
        local data = {}
        for _, r in ipairs(D.Rows(c.filter, affordable)) do
            local qty = r.commodity and ("×" .. r.qty) or ""
            r.icon = Items.Texture(r.itemID)
            r.cols = {
                itemCell(r.itemID, " " .. qty), L["DEAL_" .. r.type], money(r.maxPrice), money(r.value),
                profitText(r.profit), r.type == "easy" and L.DEAL_NOW or UI.Colorize(money(r.perDay), "muted"),
            }
            data[#data + 1] = r
        end
        c.list:SetData(data)
        if D.computing then
            c.total:SetText(L.DEALS_COMPUTING)
        elseif #data == 0 then
            c.total:SetText(D.computed and L.DEALS_NONE or L.DEALS_NEED_SCAN)
        else
            c.total:SetText(L.DEALS_TOTAL:format(sum.n, money(sum.cost), profitText(sum.profit)))
        end
        local confirming = D.buying and D.buying.stage == "confirm"
        c.buyNext:SetText(confirming and L.BTN_CONFIRM_BUY:format(money(D.buying.row.cost)) or L.BTN_BUY_NEXT)
        c.buyNext:SetEnabled(ns.Scan.ahOpen and ((#data > 0 and not D.buying) or confirming))
    end,
})

-- Selling -------------------------------------------------------------------------------------

UI.RegisterTab({
    id = "selling", label = L.TAB_SELLING, module = "Selling",
    build = function(c)
        c.queueTitle = UI.Text(c, "GameFontNormal")
        c.queueTitle:SetPoint("TOPLEFT")
        c.refresh = UI.Button(c, L.BTN_REFRESH_PRICES, 130, function()
            local ok, why = ns.SellingModule.RefreshPrices()
            if not ok and why then ns.Print(L["SCAN_FAIL_" .. why] or why) end
        end, L.TIP_REFRESH_PRICES)
        c.refresh:SetPoint("TOPRIGHT", 0, 2)
        c.queue = UI.ScrollList(c, {
            { width = 190 }, { width = 60, justify = "RIGHT" }, { width = 76, justify = "RIGHT" },
            { width = 44, justify = "RIGHT" }, { width = 150 },
        }, 8)
        c.queue:SetPoint("TOPLEFT", 0, -22)
        c.queue:SetPoint("RIGHT")
        c.queue:SetHeight(8 * 22)
        c.totals = UI.Text(c, "GameFontHighlightSmall")
        c.totals:SetPoint("TOPLEFT", 0, -202)
        c.totals:SetWidth(400)
        c.post = UI.Button(c, L.BTN_POST_NEXT, 160, function()
            local ok, why = ns.SellingModule.PostNext()
            if not ok and why then ns.Print(L["POST_FAIL_" .. why] or why) end
        end, L.TIP_POST_NEXT)
        c.post:SetPoint("TOPRIGHT", 0, -198)
        c.ownTitle = UI.Text(c, "GameFontNormal")
        c.ownTitle:SetPoint("TOPLEFT", 0, -232)
        c.own = UI.ScrollList(c, {
            { width = 180 }, { width = 72, justify = "RIGHT" }, { width = 80, justify = "RIGHT" }, { width = 130 },
        }, 8, {
            button = {
                width = 70,
                text = function() return L.BTN_CANCEL end,
                shown = function(d) return d.state == "undercut" end,
                onClick = function(d) ns.SellingModule.Cancel(d) end,
            },
            onEnter = function(row, d)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(Items.ColoredName(d.itemID))
                GameTooltip:AddDoubleLine(L.OWN_CHEAPER, tostring(d.cheaper), 1, 0.82, 0, 1, 1, 1)
                if d.state == "undercut" then
                    GameTooltip:AddDoubleLine(L.OWN_LOST_DEPOSIT, money(d.lostDeposit or 0), 1, 0.82, 0, 1, 1, 1)
                    GameTooltip:AddDoubleLine(L.OWN_REPOST_AT, money(d.newPrice), 1, 0.82, 0, 1, 1, 1)
                    GameTooltip:AddLine(L.OWN_CANCEL_HINT, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end,
        })
        c.own:SetPoint("TOPLEFT", 0, -252)
        c.own:SetPoint("RIGHT")
        c.own:SetHeight(8 * 22)
    end,
    refresh = function(c)
        local S = ns.SellingModule
        if not c.built or c.built + 2 < GetTime() then
            S.Build()
            c.built = GetTime()
        end
        local t = S.Totals()
        c.queueTitle:SetText(L.QUEUE_TITLE:format(t.lots))
        local data = {}
        for _, e in ipairs(S.queue) do
            local note = {}
            if e.returned then note[#note + 1] = UI.Colorize(L.Q_RETURNED, "risk") end
            if e.warn == "below_cost" then note[#note + 1] = UI.Colorize(L.Q_BELOW_COST, "loss") end
            if #e.sizes > 1 then note[#note + 1] = L.Q_LOTS:format(#e.sizes) end
            e.icon = Items.Texture(e.itemID)
            e.cols = {
                itemCell(e.itemID), "×" .. e.qty, money(e.price), L["DUR_" .. e.duration], table.concat(note, " · "),
            }
            data[#data + 1] = e
        end
        c.queue:SetData(data)
        c.totals:SetText(L.QUEUE_TOTALS:format(money(t.deposit), money(t.revenue)))
        c.post:SetText(S.confirm and L.BTN_POST_CONFIRM or L.BTN_POST_NEXT)
        c.post:SetEnabled(ns.Scan.ahOpen and (#S.queue > 0 or S.confirm ~= nil))
        c.refresh:SetEnabled(ns.Scan.ahOpen and ns.Scan.state == "idle")

        local own = {}
        for _, a in ipairs(S.owned) do
            a.icon = Items.Texture(a.itemID)
            local state = a.state == "ok" and UI.Colorize(L.OWN_OK, "profit") or UI.Colorize(L.OWN_UNDERCUT, "risk")
            a.cols = { itemCell(a.itemID, a.qty > 1 and (" ×" .. a.qty) or ""), money(a.price), tostring(a.cheaper), state }
            own[#own + 1] = a
        end
        c.ownTitle:SetText(L.OWN_TITLE:format(#own, S.UndercutCount()))
        c.own:SetData(own)
    end,
})

-- Stock ----------------------------------------------------------------------------------------

UI.RegisterTab({
    id = "stock", label = L.TAB_STOCK, module = "Stock",
    build = function(c)
        c.totals = UI.Text(c, "GameFontHighlight")
        c.totals:SetPoint("TOPLEFT")
        c.totals:SetWidth(580)
        c.add = UI.Edit(c, 200, function(text)
            if ns.ItemLists.Add("stock", text) then UI.Refresh() else ns.Print(L.ITEM_NOT_FOUND) end
        end)
        c.add:SetPoint("TOPLEFT", 6, -22)
        local hint = UI.Text(c, "GameFontDisableSmall")
        hint:SetPoint("LEFT", c.add, "RIGHT", 8, 0)
        hint:SetText(L.STOCK_ADD_HINT)
        c.header = UI.Text(c, "GameFontDisableSmall")
        c.header:SetPoint("TOPLEFT", 26, -48)
        c.header:SetText(L.STOCK_HEADER)
        c.list = UI.ScrollList(c, {
            { width = 150 }, { width = 40, justify = "RIGHT" }, { width = 64, justify = "RIGHT" },
            { width = 64, justify = "RIGHT" }, { width = 64, justify = "RIGHT" }, { width = 44, justify = "RIGHT" },
            { width = 50 },
        }, 15, {
            button = {
                width = 74,
                text = function(d) return d.exit and L.BTN_EXIT or L.BTN_TO_SELLING end,
                shown = function(d) return d.qty > 0 end,
                onClick = function(d) ns.StockModule.ToSelling(d.itemID); UI.Refresh() end,
            },
        })
        c.list:SetPoint("TOPLEFT", 0, -62)
        c.list:SetPoint("RIGHT")
        c.list:SetHeight(15 * 22)
    end,
    refresh = function(c)
        local positions, t = ns.StockModule.Positions()
        c.totals:SetText(L.STOCK_TOTALS:format(money(t.invested), money(t.worth), profitText(t.profit)))
        local data = {}
        for _, p in ipairs(positions) do
            p.icon = Items.Texture(p.itemID)
            local name = itemCell(p.itemID)
            if p.exit then name = UI.Colorize("! ", "loss") .. name end
            p.cols = {
                name, tostring(p.qty), p.avgCost and money(p.avgCost) or "—", p.price and money(p.price) or "—",
                p.profit and profitText(p.profit) or "—", UI.Days(p.days), p.note or "",
            }
            data[#data + 1] = p
        end
        c.list:SetData(data)
    end,
})

-- Market ----------------------------------------------------------------------------------------

local HOUSES = { { "current", L.HOUSE_current }, { "faction", L.HOUSE_faction }, { "neutral", L.HOUSE_neutral }, { "both", L.HOUSE_both } }
local PERIODS = { { "day", L.PERIOD_day }, { "week", L.PERIOD_7d }, { "month", L.PERIOD_30d } }

UI.RegisterTab({
    id = "market", label = L.TAB_MARKET, module = "Market",
    build = function(c)
        c.period = "week"
        c.search = UI.Edit(c, 200, function(text)
            local id = ns.MarketModule.Find(text)
            if id then c.itemID = id else ns.Print(L.ITEM_NOT_FOUND) end
            UI.Refresh()
        end)
        c.search:SetPoint("TOPLEFT", 6, 0)
        c.house = UI.Cycle(c, 110, HOUSES, function() return ns.settings.market.house end,
            function(v) ns.settings.market.house = v; UI.Refresh() end, L.TIP_MARKET_HOUSE)
        c.house:SetPoint("LEFT", c.search, "RIGHT", 8, 0)
        c.periodBtn = UI.Cycle(c, 80, PERIODS, function() return c.period end, function(v) c.period = v; UI.Refresh() end)
        c.periodBtn:SetPoint("LEFT", c.house, "RIGHT", 4, 0)
        c.toList = UI.Button(c, L.BTN_TO_QUICK, 90, function()
            if c.itemID then ns.ItemLists.Add("quick", c.itemID); ns.Print(L.ADDED_TO_QUICK) end
        end, L.TIP_TO_QUICK)
        c.toList:SetPoint("LEFT", c.periodBtn, "RIGHT", 4, 0)
        c.export = UI.Button(c, L.BTN_EXPORT_ANALYSIS, 90, function()
            ns.MarketModule.RequestExport(c.itemID and { c.itemID } or {}, ns.MarketModule.Keys(ns.settings.market.house)[1])
        end, L.TIP_EXPORT_ANALYSIS)
        c.export:SetPoint("LEFT", c.toList, "RIGHT", 4, 0)

        c.name = UI.Text(c, "GameFontNormalLarge")
        c.name:SetPoint("TOPLEFT", 0, -30)
        c.name:SetWidth(580)
        c.numbers = UI.Lines((function()
            local f = CreateFrame("Frame", nil, c)
            f:SetPoint("TOPLEFT", 0, -54)
            f:SetSize(280, 120)
            return f
        end)(), 7, 280)
        c.priceChart = UI.Chart(c, 290, 80)
        c.priceChart:SetPoint("TOPLEFT", 296, -54)
        c.salesChart = UI.Chart(c, 290, 34, UI.COLOR.profit)
        c.salesChart:SetPoint("TOPLEFT", 296, -140)
        local chartHint = UI.Text(c, "GameFontDisableSmall")
        chartHint:SetPoint("TOPLEFT", 296, -178)
        chartHint:SetText(L.MARKET_CHART_HINT)
        c.depthTitle = UI.Text(c, "GameFontNormal")
        c.depthTitle:SetPoint("TOPLEFT", 0, -196)
        c.depthTitle:SetText(L.MARKET_DEPTH)
        c.depth = UI.Lines((function()
            local f = CreateFrame("Frame", nil, c)
            f:SetPoint("TOPLEFT", 0, -214)
            f:SetSize(280, 130)
            return f
        end)(), 8, 280)
        c.moversTitle = UI.Text(c, "GameFontNormal")
        c.moversTitle:SetPoint("TOPLEFT", 296, -196)
        c.moversTitle:SetText(L.MARKET_MOVERS)
        c.movers = UI.Lines((function()
            local f = CreateFrame("Frame", nil, c)
            f:SetPoint("TOPLEFT", 296, -214)
            f:SetSize(290, 200)
            return f
        end)(), 12, 290)
    end,
    refresh = function(c)
        c.house:Update()
        c.periodBtn:Update()
        local keys = ns.MarketModule.Keys(ns.settings.market.house)
        local up, down = ns.MarketModule.Movers(keys[1], 6)
        local mv = { UI.Colorize(L.MARKET_UP, "profit") }
        for _, m in ipairs(up) do mv[#mv + 1] = ("%s %s"):format(UI.Percent(m.change), Items.ColoredName(m.itemID)) end
        mv[#mv + 1] = UI.Colorize(L.MARKET_DOWN, "loss")
        for _, m in ipairs(down) do mv[#mv + 1] = ("%s %s"):format(UI.Percent(m.change), Items.ColoredName(m.itemID)) end
        UI.SetLines(c.movers, mv)

        if not c.itemID then
            c.name:SetText(L.MARKET_PICK)
            UI.SetLines(c.numbers, {})
            UI.SetLines(c.depth, {})
            c.priceChart:SetValues({})
            c.salesChart:SetValues({})
            return
        end
        c.name:SetText(Items.ColoredName(c.itemID))
        local texts, depth = {}, {}
        for i, key in ipairs(keys) do
            local info = ns.MarketModule.Info(c.itemID, key, c.period)
            local houseName = ns.AH.IsNeutralKey(key) and L.HOUSE_NEUTRAL or L.HOUSE_FACTION_SHORT
            if #keys > 1 then texts[#texts + 1] = UI.Colorize(houseName, "gold") end
            texts[#texts + 1] = L.MARKET_MIN_MARKET:format(money(info.min), money(info.market))
            texts[#texts + 1] = L.MARKET_ON_PER_DAY:format(info.onMarket or 0, UI.PerDay(info.perDay))
            texts[#texts + 1] = L.MARKET_CHANGE:format(UI.Percent(info.change))
            if info.verdicts.dumper then
                texts[#texts + 1] = UI.Colorize(L.MARKET_DUMPER:format(money(info.verdicts.dumper.price)), "risk")
            end
            if info.verdicts.flood then
                texts[#texts + 1] = UI.Colorize(L.MARKET_FLOOD:format(info.verdicts.flood.before, info.verdicts.flood.now), "risk")
            end
            if i == 1 then
                local p, m = {}, {}
                for k, pt in ipairs(info.series) do
                    p[k] = pt.p
                    m[k] = pt.m
                end
                c.priceChart:SetValues(p, m)
                c.salesChart:SetValues(info.sales or {})
                for k, d in ipairs(info.depth) do
                    depth[k] = L.MARKET_DEPTH_LINE:format(money(d.price), d.units, d.cum,
                        d.hours and UI.Days(d.hours / 24) or "—")
                end
            end
        end
        UI.SetLines(c.numbers, texts)
        UI.SetLines(c.depth, depth)
    end,
})
