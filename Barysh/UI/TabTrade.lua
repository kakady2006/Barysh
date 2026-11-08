local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Deals, Selling, Stock and Market tabs (barysh-design: Main, Sales, Stock, Market).

local function itemName(itemID, extra)
    return Items.ColoredName(itemID) .. (extra or "")
end

local function profitText(v)
    if not v then return "—" end
    return UI.Colorize((v > 0 and "+" or "") .. money(v), v >= 0 and "profit" or "loss")
end

-- Footer: line on top, text on the left, buttons on the right (added by the caller).
local function footer(c, height)
    local f = CreateFrame("Frame", nil, c)
    f:SetPoint("BOTTOMLEFT")
    f:SetPoint("BOTTOMRIGHT")
    f:SetHeight(height or 40)
    UI.Divider(f, 0)
    f.text = UI.Text(f, "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 0, -10)
    f.hint = UI.Hint(f, "")
    f.hint:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -3)
    return f
end

-- Deals ---------------------------------------------------------------------------------------

local DEAL_TYPES = ns.Deals.TYPES

UI.RegisterTab({
    id = "deals", label = L.TAB_DEALS, module = "Deals",
    build = function(c)
        c.filter = "all"
        local items = { { "all", L.DEAL_all, L.DEALTIP_all } }
        for _, kind in ipairs(DEAL_TYPES) do items[#items + 1] = { kind, L["DEAL_" .. kind], L["DEALTIP_" .. kind] } end
        c.chips = UI.ChipRow(c, items, function(kind)
            c.filter = kind
            UI.Refresh()
        end)
        c.chips:SetPoint("TOPLEFT", 0, 0)
        c.affordable = UI.Check(c, L.DEALS_AFFORDABLE,
            function() return ns.settings.deals.affordable end,
            function(v) ns.settings.deals.affordable = v; UI.Refresh() end, L.DEALS_AFFORDABLE_TIP)
        c.affordable:SetPoint("TOPRIGHT", -c.affordable.label:GetStringWidth() - 6, 1)

        c.foot = footer(c, 46)
        c.buyNext = UI.Button(c.foot, L.BTN_BUY_NEXT, 160, function() ns.DealsModule.BuyNext() end, L.TIP_BUY_NEXT, "primary")
        c.buyNext:SetHeight(28)
        c.buyNext:SetPoint("TOPRIGHT", 0, -10)
        c.recalc = UI.Button(c.foot, L.BTN_RECALC, 100, function() ns.DealsModule.Compute() end)
        c.recalc:SetPoint("RIGHT", c.buyNext, "LEFT", -6, 0)

        c.list = UI.Table(c, {
            { title = L.COL_ITEM, flex = true },
            { title = L.COL_TYPE, width = 96, tag = true },
            { title = L.COL_PRICE, width = 70, justify = "RIGHT" },
            { title = L.COL_VALUE, width = 70, justify = "RIGHT" },
            { title = L.COL_PROFIT, width = 66, justify = "RIGHT" },
            { title = L.COL_PER_DAY, width = 66, justify = "RIGHT" },
        }, {
            rowHeight = 34,
            button = {
                width = 74,
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
        c.list:SetPoint("TOPLEFT", 0, -28)
        c.list:SetPoint("BOTTOMRIGHT", c.foot, "TOPRIGHT", 0, 4)
    end,
    refresh = function(c)
        local D = ns.DealsModule
        local affordable = ns.settings.deals.affordable
        c.affordable:Update()
        local sum = D.Summary(affordable)
        local all = 0
        for _, n in pairs(sum.counts) do all = all + n end
        c.chips:Label("all", ("%s %d"):format(L.DEAL_all, all))
        for _, kind in ipairs(DEAL_TYPES) do
            c.chips:Label(kind, ("%s %d"):format(L["DEAL_" .. kind], sum.counts[kind] or 0))
        end
        c.chips:Set(c.filter)
        local data = {}
        for _, r in ipairs(D.Rows(c.filter ~= "all" and c.filter or nil, affordable)) do
            local qty = r.commodity and (" ×" .. r.qty) or ""
            r.cols = {
                itemName(r.itemID, qty), L["DEALTAG_" .. r.type] or L["DEAL_" .. r.type], money(r.maxPrice), money(r.value),
                profitText(r.profit), r.type == "easy" and UI.Colorize(L.DEAL_NOW, "muted") or money(r.perDay),
            }
            r.tagKind = { [2] = r.type }
            local below = r.value and r.value > 0 and r.maxPrice and (1 - r.maxPrice / r.value) or nil
            r.sub = below and below > 0.01 and L.DEAL_SUB_BELOW:format(math.floor(below * 100 + 0.5)) or ""
            data[#data + 1] = r
        end
        c.list:SetData(data)
        if D.computing then
            c.foot.text:SetText(L.DEALS_COMPUTING)
            c.foot.hint:SetText("")
        elseif #data == 0 then
            c.foot.text:SetText(D.computed and L.DEALS_NONE or L.DEALS_NEED_SCAN)
            c.foot.hint:SetText("")
        else
            c.foot.text:SetText(L.DEALS_TOTAL:format(sum.n, money(sum.cost), profitText(sum.profit)))
            c.foot.hint:SetText(L.DEALS_SORTED)
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
        local top = CreateFrame("Frame", nil, c)
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetPoint("BOTTOM", c, "CENTER", 0, -6)
        local bottom = CreateFrame("Frame", nil, c)
        bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
        bottom:SetPoint("BOTTOMRIGHT")

        c.queueTitle = UI.Heading(top, "")
        c.queueTitle:SetPoint("TOPLEFT")
        local note = UI.Hint(top, L.QUEUE_NOTE)
        note:SetPoint("TOPRIGHT", 0, -2)
        c.post = UI.Button(top, L.BTN_POST_NEXT, 170, function()
            local ok, why = ns.SellingModule.PostNext()
            if not ok and why then ns.Print(L["POST_FAIL_" .. why] or why) end
        end, L.TIP_POST_NEXT, "primary")
        c.post:SetHeight(26)
        c.post:SetPoint("BOTTOMRIGHT", 0, 0)
        c.refresh = UI.Button(top, L.BTN_REFRESH_PRICES, 130, function()
            local ok, why = ns.SellingModule.RefreshPrices()
            if not ok and why then ns.Print(L["SCAN_FAIL_" .. why] or why) end
        end, L.TIP_REFRESH_PRICES)
        c.refresh:SetPoint("RIGHT", c.post, "LEFT", -6, 0)
        c.totals = UI.Hint(top, "")
        c.totals:SetPoint("BOTTOMLEFT", 0, 6)
        c.queue = UI.Table(top, {
            { title = L.COL_ITEM, flex = true },
            { title = L.COL_PACK, width = 66, justify = "RIGHT" },
            { title = L.COL_PRICE_EACH, width = 84, justify = "RIGHT" },
            { title = L.COL_COST, width = 70, justify = "RIGHT" },
            { title = L.COL_DURATION, width = 44, justify = "RIGHT" },
            { title = L.COL_AHEAD, width = 84, justify = "RIGHT" },
        }, { rowHeight = 28 })
        c.queue:SetPoint("TOPLEFT", 0, -20)
        c.queue:SetPoint("BOTTOMRIGHT", 0, 32)

        c.ownTitle = UI.Heading(bottom, "")
        c.ownTitle:SetPoint("TOPLEFT")
        local ownNote = UI.Hint(bottom, L.OWN_NOTE)
        ownNote:SetPoint("TOPRIGHT", 0, -2)
        c.own = UI.Table(bottom, {
            { title = L.COL_ITEM, flex = true },
            { title = L.COL_YOUR_PRICE, width = 80, justify = "RIGHT" },
            { title = L.COL_AHEAD, width = 84, justify = "RIGHT" },
            { title = L.COL_STATE, width = 170 },
        }, {
            rowHeight = 28,
            button = {
                width = 74,
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
        c.own:SetPoint("TOPLEFT", 0, -20)
        c.own:SetPoint("BOTTOMRIGHT")
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
            local notes = {}
            if e.warn == "below_cost" then notes[#notes + 1] = UI.Colorize(L.Q_BELOW_COST, "loss") end
            if #e.sizes > 1 then notes[#notes + 1] = L.Q_LOTS:format(#e.sizes) end
            local pack = #e.sizes > 1 and ("%d × %d"):format(#e.sizes, e.sizes[1]) or ("1 × " .. e.qty)
            e.cols = {
                itemName(e.itemID, e.returned and ("  " .. UI.Colorize(L.Q_RETURNED, "blue")) or ""),
                pack, money(e.price), e.cost and UI.Colorize(money(e.cost), "muted") or "—", L["DUR_" .. e.duration],
                e.ahead and L.PCS:format(e.ahead) or "—",
            }
            e.sub = table.concat(notes, " · ")
            data[#data + 1] = e
        end
        c.queue:SetData(data)
        c.totals:SetText(L.QUEUE_TOTALS:format(money(t.deposit), money(t.revenue)))
        c.post:SetText(S.confirm and L.BTN_POST_CONFIRM or L.BTN_POST_NEXT)
        c.post:SetEnabled(ns.Scan.ahOpen and (#S.queue > 0 or S.confirm ~= nil))
        c.refresh:SetEnabled(ns.Scan.ahOpen and ns.Scan.state == "idle")

        local own = {}
        for _, a in ipairs(S.owned) do
            local state = a.state == "ok" and UI.Colorize(L.OWN_OK, "profit") or UI.Colorize(L.OWN_UNDERCUT, "risk")
            a.cols = { itemName(a.itemID, a.qty > 1 and (" ×" .. a.qty) or ""), money(a.price), L.PCS:format(a.cheaper or 0), state }
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
        c.invested = UI.StatCard(c, L.STAT_INVESTED)
        c.worth = UI.StatCard(c, L.STAT_WORTH)
        c.ifSold = UI.StatCard(c, L.STAT_IF_SOLD)
        c.invested:SetPoint("TOPLEFT")
        c.invested:SetPoint("RIGHT", c, "LEFT", 240, 0)
        c.worth:SetPoint("TOPLEFT", c.invested, "TOPRIGHT", 10, 0)
        c.worth:SetPoint("RIGHT", c.invested, "RIGHT", 250, 0)
        c.ifSold:SetPoint("TOPLEFT", c.worth, "TOPRIGHT", 10, 0)
        c.ifSold:SetPoint("RIGHT", c, "RIGHT")

        c.foot = footer(c, 40)
        c.foot.text:SetText(UI.Colorize(L.STOCK_FOOT, "muted"))
        c.add = UI.Edit(c.foot, 230, function(text)
            if ns.ItemLists.Add("stock", text) then UI.Refresh() else ns.Print(L.ITEM_NOT_FOUND) end
        end)
        c.add:SetPlaceholder(L.STOCK_ADD_HINT)
        c.add:SetPoint("TOPRIGHT", 0, -9)

        c.list = UI.Table(c, {
            { title = L.COL_GOODS_WHY, flex = true },
            { title = L.COL_QTY, width = 44, justify = "RIGHT" },
            { title = L.COL_COST, width = 70, justify = "RIGHT" },
            { title = L.COL_NOW, width = 70, justify = "RIGHT" },
            { title = L.COL_PROFIT, width = 66, justify = "RIGHT" },
            { title = L.COL_SELL, width = 54, justify = "RIGHT" },
        }, {
            rowHeight = 34,
            button = {
                width = 90,
                text = function(d) return d.exit and L.BTN_EXIT or L.BTN_TO_SELLING end,
                shown = function(d) return d.qty > 0 end,
                onClick = function(d) ns.StockModule.ToSelling(d.itemID); UI.Refresh() end,
                style = "plain",
            },
        })
        c.list:SetPoint("TOPLEFT", c.invested, "BOTTOMLEFT", 0, -10)
        c.list:SetPoint("BOTTOMRIGHT", c.foot, "TOPRIGHT", 0, 4)
    end,
    refresh = function(c)
        local positions, t = ns.StockModule.Positions()
        c.invested:Set(money(t.invested))
        c.worth:Set(money(t.worth))
        c.ifSold:Set(profitText(t.profit), L.STAT_AFTER_CUT)
        local data = {}
        for _, p in ipairs(positions) do
            p.cols = {
                itemName(p.itemID), tostring(p.qty), p.avgCost and money(p.avgCost) or "—", p.price and money(p.price) or "—",
                p.profit and profitText(p.profit) or "—", UI.Days(p.days),
            }
            if p.exit then
                p.sub = UI.Colorize(L.STOCK_BELOW_DAYS:format(p.streak), "loss")
            else
                p.sub = p.note or ""
            end
            data[#data + 1] = p
        end
        c.list:SetData(data)
        -- the exit button is the red one
        for _, row in ipairs(c.list.rows) do
            if row.data and row.button then
                local exit = row.data.exit
                UI.Flat(row.button, exit and { 0.48, 0.09, 0.05 } or { 0.18, 0.157, 0.118 }, exit and { 0.17, 0.02, 0.01 } or { 0, 0, 0 })
            end
        end
    end,
})

-- Market ----------------------------------------------------------------------------------------

local HOUSES = { { "current", L.HOUSE_current }, { "faction", L.HOUSE_faction }, { "neutral", L.HOUSE_neutral }, { "both", L.HOUSE_both } }
local PERIODS = { { "day", L.PERIOD_day }, { "week", L.PERIOD_7d }, { "month", L.PERIOD_30d } }

UI.RegisterTab({
    id = "market", label = L.TAB_MARKET, module = "Market",
    build = function(c)
        c.period = "week"
        local left = CreateFrame("Frame", nil, c)
        left:SetPoint("TOPLEFT")
        left:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -290, 0)
        local right = CreateFrame("Frame", nil, c)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
        right:SetPoint("BOTTOMRIGHT")

        c.search = UI.Edit(right, 200, function(text)
            local id = ns.MarketModule.Find(text)
            if id then c.itemID = id else ns.Print(L.ITEM_NOT_FOUND) end
            UI.Refresh()
        end)
        c.search:SetPlaceholder(L.MARKET_SEARCH)
        c.search:SetPoint("TOPLEFT")
        c.search:SetPoint("TOPRIGHT")

        c.name = UI.Text(left, "GameFontNormalLarge")
        c.name:SetPoint("TOPLEFT", 0, -2)
        c.periods = UI.ChipRow(left, PERIODS, function(v) c.period = v; UI.Refresh() end)
        c.periods.order[1]:SetPoint("TOPRIGHT", left, "TOPRIGHT", -(c.periods.order[2]:GetWidth() + c.periods.order[3]:GetWidth() + 8), 0)
        c.houses = UI.ChipRow(left, HOUSES, function(v) ns.settings.market.house = v; UI.Refresh() end)
        c.houses:SetPoint("TOPLEFT", 0, -26)

        c.chart = UI.Chart(left, 400, 150)
        c.chart:SetPoint("TOPLEFT", 0, -52)
        c.chart:SetPoint("RIGHT", left, "RIGHT")
        local legend = UI.Hint(left, L.MARKET_LEGEND)
        legend:SetPoint("TOPLEFT", c.chart, "BOTTOMLEFT", 0, -5)

        local stats = CreateFrame("Frame", nil, left)
        stats:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -8)
        stats:SetPoint("RIGHT", left, "RIGHT")
        stats:SetHeight(64)
        local colL = CreateFrame("Frame", nil, stats)
        colL:SetPoint("TOPLEFT")
        colL:SetPoint("BOTTOMRIGHT", stats, "BOTTOM", -10, 0)
        local colR = CreateFrame("Frame", nil, stats)
        colR:SetPoint("TOPLEFT", stats, "TOP", 10, 0)
        colR:SetPoint("BOTTOMRIGHT")
        c.stat = {
            UI.Pair(colL, 0), UI.Pair(colL, -19), UI.Pair(colL, -38),
            UI.Pair(colR, 0), UI.Pair(colR, -19), UI.Pair(colR, -38),
        }
        c.verdict = UI.Text(left, "GameFontHighlightSmall")
        c.verdict:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -4)
        c.verdict:SetPoint("RIGHT", left, "RIGHT")

        c.toList = UI.Button(left, L.BTN_TO_QUICK, 100, function()
            if c.itemID then ns.ItemLists.Add("quick", c.itemID); ns.Print(L.ADDED_TO_QUICK) end
        end, L.TIP_TO_QUICK)
        c.toList:SetPoint("BOTTOMLEFT")
        c.export = UI.Button(left, L.BTN_EXPORT_ANALYSIS, 150, function()
            ns.MarketModule.RequestExport(c.itemID and { c.itemID } or {}, ns.MarketModule.Keys(ns.settings.market.house)[1])
        end, L.TIP_EXPORT_ANALYSIS)
        c.export:SetPoint("LEFT", c.toList, "RIGHT", 6, 0)

        local depth = UI.Card(right, L.MARKET_DEPTH)
        depth:SetPoint("TOPLEFT", c.search, "BOTTOMLEFT", 0, -10)
        depth:SetPoint("TOPRIGHT", c.search, "BOTTOMRIGHT", 0, -10)
        depth:SetHeight(170)
        c.depth = {}
        for i = 1, 5 do
            local y = -(i - 1) * 20
            local row = { price = UI.Text(depth.body, "GameFontHighlightSmall"), units = UI.Text(depth.body, "GameFontHighlightSmall") }
            row.price:SetPoint("TOPLEFT", 0, y)
            row.units:SetPoint("TOPRIGHT", 0, y)
            row.units:SetJustifyH("RIGHT")
            row.bar = UI.Bar(depth.body, 110, 8, { 0.25, 0.47, 0.75 })
            row.bar:SetPoint("TOPLEFT", 80, y - 3)
            c.depth[i] = row
        end
        c.depthNote = UI.Hint(depth.body, "")
        c.depthNote:SetPoint("TOPLEFT", 0, -104)
        c.depthNote:SetPoint("RIGHT", depth.body, "RIGHT")

        local movers = UI.Card(right, L.MARKET_MOVERS)
        movers:SetPoint("TOPLEFT", depth, "BOTTOMLEFT", 0, -10)
        movers:SetPoint("TOPRIGHT", depth, "BOTTOMRIGHT", 0, -10)
        movers:SetPoint("BOTTOM", right, "BOTTOM")
        c.movers = {}
        for i = 1, 8 do c.movers[i] = UI.Pair(movers.body, -(i - 1) * 20) end
    end,
    refresh = function(c)
        c.houses:Set(ns.settings.market.house)
        c.periods:Set(c.period)
        local keys = ns.MarketModule.Keys(ns.settings.market.house)
        local up, down = ns.MarketModule.Movers(keys[1], 4)
        local mv = {}
        for _, m in ipairs(up) do mv[#mv + 1] = { Items.ColoredName(m.itemID), UI.Colorize(UI.Percent(m.change), "profit") } end
        for _, m in ipairs(down) do mv[#mv + 1] = { Items.ColoredName(m.itemID), UI.Colorize(UI.Percent(m.change), "loss") } end
        for i, pair in ipairs(c.movers) do
            local m = mv[i]
            if m then pair:Set(m[1], m[2]) elseif i == 1 then pair:Set(UI.Colorize(L.MARKET_NO_MOVES, "muted"), "") else pair:Set("", "") end
        end

        local function clear()
            for _, p in ipairs(c.stat) do p:Set("", "") end
            for _, row in ipairs(c.depth) do
                row.price:SetText("")
                row.units:SetText("")
                row.bar:SetValue(0)
            end
            c.depthNote:SetText("")
            c.verdict:SetText("")
            c.chart:SetValues({}, {}, {})
        end
        if not c.itemID then
            c.name:SetText(UI.Colorize(L.MARKET_PICK_SHORT, "muted"))
            clear()
            return
        end
        c.name:SetText(Items.ColoredName(c.itemID))
        local info = ns.MarketModule.Info(c.itemID, keys[1], c.period)
        c.stat[1]:Set(UI.Colorize(L.MK_MIN_NOW, "muted"), money(info.min))
        c.stat[2]:Set(UI.Colorize(L.MK_ON_MARKET, "muted"), L.PCS:format(info.onMarket or 0))
        c.stat[3]:Set(UI.Colorize(L.MK_CHANGE, "muted"), info.change and UI.Colorize(UI.Percent(info.change), info.change >= 0 and "profit" or "loss") or "—")
        c.stat[4]:Set(UI.Colorize(L.MK_MARKET, "muted"), money(info.market))
        c.stat[5]:Set(UI.Colorize(L.MK_PER_DAY, "muted"), "~" .. UI.PerDay(info.perDay))
        local verdicts = {}
        if info.verdicts.dumper then verdicts[#verdicts + 1] = L.MARKET_DUMPER:format(money(info.verdicts.dumper.price)) end
        if info.verdicts.flood then verdicts[#verdicts + 1] = L.MARKET_FLOOD:format(info.verdicts.flood.before, info.verdicts.flood.now) end
        c.stat[6]:Set(UI.Colorize(L.MK_VERDICT, "muted"), #verdicts > 0 and UI.Colorize(L.MK_SEE_BELOW, "risk") or UI.Colorize(L.MK_CALM, "muted"))
        c.verdict:SetText(UI.Colorize(table.concat(verdicts, " · "), "risk"))

        local p, m = {}, {}
        for k, pt in ipairs(info.series) do
            p[k] = pt.p
            m[k] = pt.m
        end
        c.chart:SetValues(p, m, info.sales or {})

        local maxUnits = 0
        for k = 1, math.min(5, #info.depth) do maxUnits = math.max(maxUnits, info.depth[k].units or 0) end
        for k, row in ipairs(c.depth) do
            local d = info.depth[k]
            row.price:SetText(d and money(d.price) or "")
            row.units:SetText(d and tostring(d.units) or "")
            row.bar:SetValue(d and maxUnits > 0 and d.units / maxUnits or 0)
        end
        local last = info.depth[math.min(5, #info.depth)]
        c.depthNote:SetText(last and L.MARKET_DEPTH_NOTE:format(money(last.price), last.cum, last.hours and UI.Days(last.hours / 24) or "—") or "")
    end,
})
