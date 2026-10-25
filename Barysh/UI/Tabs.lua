local _, ns = ...

local UI = ns.UI
local L = ns.L

local function lines(parent, n, template)
    local out = {}
    for i = 1, n do
        local fs = UI.Text(parent, template or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        fs:SetWidth(270)
        out[i] = fs
    end
    return out
end

local function setLines(fsList, texts)
    for i, fs in ipairs(fsList) do fs:SetText(texts[i] or "") end
end

-- Overview ------------------------------------------------------------------------------

UI.RegisterTab({
    id = "overview", label = L.TAB_OVERVIEW,
    build = function(c)
        local left = CreateFrame("Frame", nil, c)
        left:SetPoint("TOPLEFT")
        left:SetSize(280, 420)
        local right = CreateFrame("Frame", nil, c)
        right:SetPoint("TOPLEFT", 300, 0)
        right:SetSize(280, 420)
        c.capitalTitle = UI.Text(left, "GameFontNormal")
        c.capitalTitle:SetPoint("TOPLEFT")
        c.capitalTitle:SetText(L.OV_CAPITAL)
        local box = CreateFrame("Frame", nil, left)
        box:SetPoint("TOPLEFT", 0, -20)
        box:SetSize(280, 200)
        c.capital = lines(box, 10)
        c.todayTitle = UI.Text(right, "GameFontNormal")
        c.todayTitle:SetPoint("TOPLEFT")
        c.todayTitle:SetText(L.OV_TODAY)
        local tbox = CreateFrame("Frame", nil, right)
        tbox:SetPoint("TOPLEFT", 0, -20)
        tbox:SetSize(280, 60)
        c.today = lines(tbox, 3)
        c.attnTitle = UI.Text(right, "GameFontNormal")
        c.attnTitle:SetPoint("TOPLEFT", 0, -90)
        c.attnTitle:SetText(L.OV_ATTENTION)
        local abox = CreateFrame("Frame", nil, right)
        abox:SetPoint("TOPLEFT", 0, -110)
        abox:SetSize(280, 120)
        c.attention = lines(abox, 6)
    end,
    refresh = function(c)
        local texts = { L.OV_GOLD_TOTAL:format(ns.FormatMoney(ns.LedgerModule.TotalGold())) }
        local chars = {}
        for name, data in pairs(ns.db.chars) do chars[#chars + 1] = { name = name, money = data.money or 0 } end
        table.sort(chars, function(a, b) return a.money > b.money end)
        for i = 1, math.min(#chars, 8) do
            texts[#texts + 1] = ("  %s: %s"):format(chars[i].name:match("^[^-]+"), ns.FormatMoney(chars[i].money))
        end
        setLines(c.capital, texts)

        if ns.LedgerModule.enabled then
            local t = ns.LedgerModule.Totals("today")
            setLines(c.today, {
                L.OV_PROFIT:format(UI.Colorize(ns.FormatMoney(t.profit), t.profit >= 0 and "profit" or "loss")),
                L.OV_DEALS:format(t.count),
            })
        else
            setLines(c.today, { L.OV_LEDGER_OFF })
        end

        local attn = {}
        local h = ns.db.ah[ns.Prices.DefaultKey()]
        local age = h and h.lastFull and ns.Now() - h.lastFull
        if not age or age > ns.settings.staleHours * 3600 then
            attn[#attn + 1] = UI.Colorize(L.OV_DATA_OLD:format(age and ns.FormatAge(age) or L.NEVER), "risk")
        end
        if ns.db.autoScanNeedsClick then attn[#attn + 1] = L.SCAN_NEEDS_CLICK end
        if ns.Sync.enabled and ns.Sync.IsStale() then attn[#attn + 1] = UI.Colorize(L.OV_SYNC_OLD, "risk") end
        if #ns.db.errors > 0 then attn[#attn + 1] = L.OV_ERRORS:format(#ns.db.errors) end
        local returned = 0
        for _, n in pairs(ns.db.returned or {}) do returned = returned + n end
        if returned > 0 then attn[#attn + 1] = L.OV_RETURNED:format(returned) end
        if #attn == 0 then attn[1] = UI.Colorize(L.OV_ALL_GOOD, "muted") end
        setLines(c.attention, attn)
    end,
})

-- Deals and Selling: filled in during the first days in game (needs real scans) ---------------

local function placeholder(text)
    return function(c)
        local fs = UI.Text(c, "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 0, -10)
        fs:SetWidth(560)
        fs:SetText(text)
    end
end

UI.RegisterTab({ id = "deals", label = L.TAB_DEALS, module = "Deals", build = placeholder(L.SOON_DEALS) })
UI.RegisterTab({ id = "selling", label = L.TAB_SELLING, module = "Selling", build = placeholder(L.SOON_SELLING) })

-- Ledger --------------------------------------------------------------------------------

local KIND_COLOR = { ah_sell = "profit", ah_buy = "text", ah_expired = "risk", disenchant = "gold" }

UI.RegisterTab({
    id = "ledger", label = L.TAB_LEDGER, module = "Ledger",
    build = function(c)
        c.period = "today"
        local prev
        for _, p in ipairs({ "today", "week", "month", "all" }) do
            local b = UI.Button(c, L["PERIOD_" .. p], 80, function()
                c.period = p
                UI.Refresh()
            end)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT") end
            prev = b
        end
        c.totals = UI.Text(c, "GameFontHighlight")
        c.totals:SetPoint("TOPLEFT", 0, -30)
        c.list = UI.List(c, {
            { width = 70 }, { width = 110 }, { width = 190 }, { width = 40, justify = "RIGHT" },
            { width = 70, justify = "RIGHT" }, { width = 60, justify = "RIGHT" },
        }, 15)
        c.list:SetPoint("TOPLEFT", 0, -54)
        c.list:SetPoint("RIGHT")
        c.list:SetHeight(15 * 22)
    end,
    refresh = function(c)
        local from = ns.LedgerModule.PeriodStart(c.period)
        local t = ns.Ledger.Sum(ns.db.ledger, from, math.huge)
        c.totals:SetText(L.LEDGER_TOTALS:format(ns.FormatMoney(t.income), ns.FormatMoney(t.expense),
            ns.FormatMoney(t.profit), t.count))
        local data = {}
        local ops = ns.db.ledger.ops
        for i = #ops, 1, -1 do
            local op = ops[i]
            if op.t < from or #data >= 15 then break end
            local name = op.name or (op.itemID and ns.Items.Name(op.itemID)) or ""
            data[#data + 1] = {
                icon = op.itemID and select(10, GetItemInfo(op.itemID)) or nil,
                cols = {
                    date("%d.%m %H:%M", op.t),
                    UI.Colorize(L["KIND_" .. op.kind] or op.kind, KIND_COLOR[op.kind] or "text"),
                    name, op.qty and tostring(op.qty) or "",
                    ns.FormatMoney(op.amount or 0), op.profit and ns.FormatMoney(op.profit) or "",
                },
            }
        end
        c.list:SetData(data)
    end,
})

-- Mail ----------------------------------------------------------------------------------

UI.RegisterTab({
    id = "mail", label = L.TAB_MAIL, module = "Mail",
    build = function(c)
        c.title = UI.Text(c, "GameFontNormal")
        c.title:SetPoint("TOPLEFT")
        c.summary = lines(c, 6)
        for i, fs in ipairs(c.summary) do fs:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 16) fs:SetWidth(560) end
        c.collect = UI.Button(c, L.MAIL_COLLECT:format(0), 200, function() ns.Mail.Collect() end)
        c.collect:SetPoint("TOPLEFT", 0, -124)
        c.otherTitle = UI.Text(c, "GameFontNormal")
        c.otherTitle:SetPoint("TOPLEFT", 0, -160)
        c.other = UI.List(c, { { width = 160 }, { width = 250 }, { width = 100, justify = "RIGHT" } }, 8)
        c.other:SetPoint("TOPLEFT", 0, -180)
        c.other:SetPoint("RIGHT")
        c.other:SetHeight(8 * 22)
    end,
    refresh = function(c)
        if not ns.Mail.mailOpen then
            c.title:SetText(L.MAIL_OPEN_BOX)
            setLines(c.summary, {})
            c.collect:Hide()
            c.otherTitle:SetText("")
            c.other:SetData({})
            return
        end
        local inbox = ns.Mail.ReadInbox()
        local groups, order = {}, {}
        for _, m in ipairs(inbox.auction) do
            local g = groups[m.kind]
            if not g then
                g = { n = 0, money = 0, names = {} }
                groups[m.kind] = g
                order[#order + 1] = m.kind
            end
            g.n = g.n + 1
            g.money = g.money + m.header.money
            if #g.names < 3 and m.name then g.names[#g.names + 1] = m.name end
        end
        c.title:SetText(L.MAIL_AUCTION_TITLE:format(#inbox.auction, ns.FormatMoney(inbox.money)))
        local texts = {}
        for _, kind in ipairs(order) do
            local g = groups[kind]
            texts[#texts + 1] = ("%s ×%d — %s%s"):format(L["MAILKIND_" .. kind] or kind, g.n,
                table.concat(g.names, ", "), g.money > 0 and (" · " .. ns.FormatMoney(g.money)) or "")
        end
        setLines(c.summary, texts)
        c.collect:Show()
        c.collect:SetText(L.MAIL_COLLECT:format(#inbox.auction))
        c.collect:SetEnabled(#inbox.auction > 0 and not ns.Mail.collecting)
        c.otherTitle:SetText(L.MAIL_OTHER_TITLE:format(#inbox.other))
        local data = {}
        for i, h in ipairs(inbox.other) do
            if i > 8 then break end
            local amount = h.cod > 0 and (L.MAIL_COD .. " " .. ns.FormatMoney(h.cod)) or (h.money > 0 and ns.FormatMoney(h.money) or "")
            data[#data + 1] = { cols = { h.sender or "?", h.subject, amount } }
        end
        c.other:SetData(data)
    end,
})
