local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Ledger and Mail tabs (barysh-design: Ledger, Mail).

local KIND_TAG = { ah_sell = "profit", ah_buy = "blue", ah_expired = "risk", disenchant = "disenchant",
    vendor_sell = "easy", vendor_buy = "plain", craft = "craft", cod = "blue" }

local PERIODS = { "today", "week", "month", "all" }

local function signed(v)
    if not v or v == 0 then return UI.Colorize("—", "muted") end
    return UI.Colorize((v > 0 and "+" or "") .. money(v), v > 0 and "profit" or "loss")
end

-- Ledger ---------------------------------------------------------------------------------------

UI.RegisterTab({
    id = "ledger", label = L.TAB_LEDGER, module = "Ledger",
    build = function(c)
        c.period = "today"
        c.activity = false
        local periods = {}
        for _, p in ipairs(PERIODS) do periods[#periods + 1] = { p, L["PERIOD_" .. p] } end
        c.periods = UI.ChipRow(c, periods, function(p) c.period = p; UI.Refresh() end)
        local w = 0
        for _, chip in ipairs(c.periods.order) do w = w + chip:GetWidth() + 4 end
        c.periods:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(w - c.periods.order[1]:GetWidth() - 4), 0)

        c.cards = {}
        local captions = { L.STAT_INCOME, L.STAT_EXPENSE, L.STAT_COUNT, L.STAT_PROFIT }
        for i, cap in ipairs(captions) do
            local card = UI.StatCard(c, cap)
            if i == 1 then
                card:SetPoint("TOPLEFT", 0, -28)
            else
                card:SetPoint("TOPLEFT", c.cards[i - 1], "TOPRIGHT", 10, 0)
            end
            c.cards[i] = card
        end
        c:SetScript("OnSizeChanged", function(self, width)
            local cw = ((width or 700) - 30) / 4
            for _, card in ipairs(self.cards) do card:SetWidth(cw) end
        end)
        for _, card in ipairs(c.cards) do card:SetWidth(170) end

        local acts = { { false, L.ACT_all } }
        for _, a in ipairs(ns.LedgerModule.ACTIVITIES) do acts[#acts + 1] = { a, L["ACT_" .. a] } end
        c.acts = UI.ChipRow(c, acts, function(a) c.activity = a; UI.Refresh() end)
        c.acts:SetPoint("TOPLEFT", 0, -96)

        local foot = CreateFrame("Frame", nil, c)
        foot:SetPoint("BOTTOMLEFT")
        foot:SetPoint("BOTTOMRIGHT")
        foot:SetHeight(38)
        UI.Divider(foot, 0)
        c.syncNote = UI.Hint(foot, "")
        c.syncNote:SetPoint("TOPLEFT", 0, -14)
        c.export = UI.Button(foot, L.BTN_EXPORT_PERIOD, 150, function()
            local from = ns.LedgerModule.PeriodStart(c.period)
            UI.ShowText(L.LEDGER_EXPORT_TITLE, ns.LedgerModule.CSV(from, ns.LedgerModule.KindsOf(c.activity or nil)))
        end, L.TIP_LEDGER_EXPORT)
        c.export:SetPoint("TOPRIGHT", 0, -8)

        c.list = UI.Table(c, {
            { title = L.COL_TIME, width = 50 },
            { title = L.COL_OPERATION, width = 120, tag = true },
            { title = L.COL_ITEM, flex = true },
            { title = L.COL_QTY, width = 40, justify = "RIGHT" },
            { title = L.COL_SUM, width = 84, justify = "RIGHT" },
            { title = L.COL_PROFIT, width = 80, justify = "RIGHT" },
        }, { rowHeight = 24, icons = false })
        c.list:SetPoint("TOPLEFT", 0, -124)
        c.list:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 4)
    end,
    refresh = function(c)
        c.periods:Set(c.period)
        c.acts:Set(c.activity)
        local from = ns.LedgerModule.PeriodStart(c.period)
        local kinds = ns.LedgerModule.KindsOf(c.activity or nil)
        local t = ns.Ledger.Sum(ns.db.ledger, from, math.huge, kinds)
        c.cards[1]:Set(money(t.income))
        c.cards[2]:Set(money(t.expense))
        c.cards[3]:Set(tostring(t.count))
        c.cards[4]:Set(signed(t.profit))
        local data = {}
        local ops = ns.db.ledger.ops
        local day = c.period == "today"
        for i = #ops, 1, -1 do
            local op = ops[i]
            if op.t < from then break end
            if not kinds or kinds[op.kind] then
                local name = op.itemID and Items.ColoredName(op.itemID) or op.name or op.note or ""
                data[#data + 1] = {
                    itemID = op.itemID,
                    cols = {
                        UI.Colorize(date(day and "%H:%M" or "%d.%m", op.t), "muted"),
                        L["KIND_" .. op.kind] or op.kind,
                        name, op.qty and tostring(op.qty) or "",
                        signed(op.amount or 0), op.profit and signed(op.profit) or UI.Colorize("—", "muted"),
                    },
                    tagKind = { [2] = KIND_TAG[op.kind] or "plain" },
                }
            end
        end
        c.list:SetData(data)
        if ns.Sync.enabled then
            local age = ns.Sync.MarketAge()
            c.syncNote:SetText(L.SYNCED:format(age and ns.FormatAge(age) or L.NEVER))
        else
            c.syncNote:SetText(L.LEDGER_SYNC_OFF)
        end
    end,
})

-- Mail -------------------------------------------------------------------------------------------

local MAILKIND_COLOR = { sold = "profit", won = "blue", expired = "risk", cancelled = "risk", outbid = "muted" }
local OTHER_EDGE = { stranger_gold = { 0.55, 0.2, 0.15 }, cod = { 0.25, 0.43, 0.56 }, own = { 0.23, 0.19, 0.13 },
    plain = { 0.23, 0.19, 0.13 } }
local OTHER_BG = { stranger_gold = { 0.13, 0.05, 0.04 }, cod = { 0.05, 0.08, 0.11 } }

local function letterCard(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetHeight(74)
    f.from = UI.Text(f, "GameFontHighlightSmall")
    f.from:SetPoint("TOPLEFT", 12, -10)
    f.amount = UI.Text(f, "GameFontHighlightSmall")
    f.amount:SetPoint("TOPRIGHT", -12, -10)
    f.amount:SetJustifyH("RIGHT")
    f.text = UI.Text(f, "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 12, -28)
    f.text:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.main = UI.Button(f, "", 150, function(self)
        local d = f.data
        if not d then return end
        if d.kind == "cod" then ns.Mail.PayCod(d.index)
        elseif d.kind == "own" then ns.Mail.TakeOwn(d.index)
        else ns.Mail.Return(d.index) end
    end, nil, "primary")
    f.main:SetPoint("BOTTOMRIGHT", -10, 8)
    f.second = UI.Button(f, L.BTN_RETURN, 80, function()
        if f.data then ns.Mail.Return(f.data.index) end
    end, L.TIP_RETURN_COD)
    f.second:SetPoint("RIGHT", f.main, "LEFT", -6, 0)
    return f
end

UI.RegisterTab({
    id = "mail", label = L.TAB_MAIL, module = "Mail",
    build = function(c)
        c.title = UI.Heading(c, "")
        c.title:SetPoint("TOPLEFT")
        c.total = UI.Text(c, "GameFontHighlightSmall")
        c.total:SetPoint("TOPRIGHT", 0, -2)
        c.groups = {}
        for i = 1, 5 do
            local y = -24 - (i - 1) * 22
            local row = {
                kind = UI.Text(c, "GameFontHighlightSmall"),
                names = UI.Text(c, "GameFontHighlightSmall"),
                money = UI.Text(c, "GameFontHighlightSmall"),
                line = UI.Divider(c, y - 20, UI.COLOR.rowLine),
            }
            row.kind:SetPoint("TOPLEFT", 0, y)
            row.names:SetPoint("TOPLEFT", 130, y)
            row.names:SetPoint("RIGHT", c, "RIGHT", -120, 0)
            row.names:SetWordWrap(false)
            row.money:SetPoint("TOPRIGHT", 0, y)
            row.money:SetJustifyH("RIGHT")
            c.groups[i] = row
        end
        c.collect = UI.Button(c, L.MAIL_COLLECT:format(0), 220, function() ns.Mail.Collect() end, nil, "primary")
        c.collect:SetHeight(26)
        c.collect:SetPoint("TOPRIGHT", 0, -138)
        c.sep = UI.Divider(c, -174)
        c.otherTitle = UI.Heading(c, "")
        c.otherTitle:SetPoint("TOPLEFT", 0, -186)
        c.cards = {}
        for i = 1, 4 do
            local card = letterCard(c)
            card:SetPoint("TOPLEFT", 0, -210 - (i - 1) * 82)
            card:SetPoint("RIGHT", c, "RIGHT")
            c.cards[i] = card
        end
        c.empty = UI.Hint(c, "")
        c.empty:SetPoint("TOPLEFT", 0, -212)
    end,
    refresh = function(c)
        local open = ns.Mail.mailOpen
        local inbox = open and ns.Mail.ReadInbox() or { auction = {}, other = {}, money = 0 }
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
        c.title:SetText(open and L.MAIL_AUCTION_TITLE:format(#inbox.auction) or L.MAIL_OPEN_BOX)
        c.total:SetText(inbox.money > 0 and UI.Colorize("+" .. money(inbox.money), "profit") or "")
        for i, row in ipairs(c.groups) do
            local kind = order[i]
            local g = kind and groups[kind]
            row.kind:SetText(g and UI.Colorize(("%s ×%d"):format(L["MAILKIND_" .. kind] or kind, g.n), MAILKIND_COLOR[kind] or "text") or "")
            row.names:SetText(g and table.concat(g.names, ", ") or "")
            row.money:SetText(g and (g.money > 0 and money(g.money) or UI.Colorize(L.MAIL_ITEMS, "muted")) or "")
            row.line:SetShown(g ~= nil)
        end
        c.collect:SetShown(open)
        c.collect:SetText(L.MAIL_COLLECT:format(#inbox.auction))
        c.collect:SetEnabled(#inbox.auction > 0 and not ns.Mail.collecting)

        c.otherTitle:SetText(open and L.MAIL_OTHER_TITLE:format(#inbox.other) or "")
        c.sep:SetShown(open)
        c.empty:SetText(open and #inbox.other == 0 and L.MAIL_NO_OTHER or "")
        for i, card in ipairs(c.cards) do
            local h = inbox.other[i]
            card.data = h
            if h then
                UI.Flat(card, OTHER_BG[h.kind] or UI.COLOR.card, OTHER_EDGE[h.kind] or UI.COLOR.line)
                local who = L["MAILFROM_" .. h.kind] or ""
                card.from:SetText(L.MAIL_FROM:format(h.sender or "?") .. (who ~= "" and ("  ·  " .. UI.Colorize(who,
                    h.kind == "stranger_gold" and "loss" or (h.kind == "own" and "profit" or "muted"))) or ""))
                local amount = h.cod > 0 and h.cod or h.money
                card.amount:SetText(amount > 0 and money(amount) or "")
                local text = h.subject or ""
                if h.kind == "stranger_gold" then
                    text = UI.Colorize(L.MAIL_STRANGER_WARN, "loss")
                elseif h.kind == "cod" then
                    local info = ns.Mail.CodInfo(h.index)
                    if info then
                        text = L.COD_LINE:format(money(info.cod), money(info.value),
                            UI.Colorize(L["COD_" .. info.verdict], info.verdict == "good" and "profit" or "loss"), money(info.profit))
                    end
                end
                card.text:SetText(text)
                card.main:SetShown(h.kind ~= "plain")
                card.main:SetText(h.kind == "cod" and L.BTN_PAY_COD or (h.kind == "own" and L.BTN_TAKE or L.BTN_RETURN_SENDER))
                card.second:SetShown(h.kind == "cod")
                card:Show()
            else
                card:Hide()
            end
        end
    end,
})
