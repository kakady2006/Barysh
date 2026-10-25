local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Ledger and Mail tabs. TZ: "Учёт и капитал", "Почта".

local KIND_COLOR = { ah_sell = "profit", ah_buy = "text", ah_expired = "risk", disenchant = "gold",
    vendor_sell = "profit", service = "profit", craft = "profit", trade_sell = "profit" }

local PERIODS = { "today", "week", "month", "all" }

UI.RegisterTab({
    id = "ledger", label = L.TAB_LEDGER, module = "Ledger",
    build = function(c)
        c.period = "today"
        c.activity = nil
        local prev
        for _, p in ipairs(PERIODS) do
            local b = UI.Button(c, L["PERIOD_" .. p], 74, function()
                c.period = p
                UI.Refresh()
            end)
            b.period = p
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT") end
            prev = b
            c[p] = b
        end
        local acts = { { false, L.ACT_all } }
        for _, a in ipairs(ns.LedgerModule.ACTIVITIES) do acts[#acts + 1] = { a, L["ACT_" .. a] } end
        c.filter = UI.Cycle(c, 110, acts, function() return c.activity or false end,
            function(v) c.activity = v or nil; UI.Refresh() end, L.TIP_LEDGER_FILTER)
        c.filter:SetPoint("LEFT", prev, "RIGHT", 10, 0)
        c.export = UI.Button(c, L.BTN_EXPORT, 90, function()
            local from = ns.LedgerModule.PeriodStart(c.period)
            UI.ShowText(L.LEDGER_EXPORT_TITLE, ns.LedgerModule.CSV(from, ns.LedgerModule.KindsOf(c.activity)))
        end, L.TIP_LEDGER_EXPORT)
        c.export:SetPoint("TOPRIGHT", 0, 0)
        c.totals = UI.Text(c, "GameFontHighlight")
        c.totals:SetPoint("TOPLEFT", 0, -30)
        c.list = UI.ScrollList(c, {
            { width = 70 }, { width = 100 }, { width = 186 }, { width = 40, justify = "RIGHT" },
            { width = 76, justify = "RIGHT" }, { width = 70, justify = "RIGHT" },
        }, 16)
        c.list:SetPoint("TOPLEFT", 0, -54)
        c.list:SetPoint("RIGHT")
        c.list:SetHeight(16 * 22)
    end,
    refresh = function(c)
        for _, p in ipairs(PERIODS) do c[p]:SetEnabled(c.period ~= p) end
        c.filter:Update()
        local from = ns.LedgerModule.PeriodStart(c.period)
        local kinds = ns.LedgerModule.KindsOf(c.activity)
        local t = ns.Ledger.Sum(ns.db.ledger, from, math.huge, kinds)
        c.totals:SetText(L.LEDGER_TOTALS:format(money(t.income), money(t.expense), money(t.profit), t.count))
        local data = {}
        local ops = ns.db.ledger.ops
        for i = #ops, 1, -1 do
            local op = ops[i]
            if op.t < from then break end
            if not kinds or kinds[op.kind] then
                local name = op.name or (op.itemID and Items.Name(op.itemID)) or op.note or ""
                data[#data + 1] = {
                    itemID = op.itemID,
                    icon = op.itemID and Items.Texture(op.itemID) or nil,
                    cols = {
                        date("%d.%m %H:%M", op.t),
                        UI.Colorize(L["KIND_" .. op.kind] or op.kind, KIND_COLOR[op.kind] or "text"),
                        name, op.qty and tostring(op.qty) or "",
                        money(op.amount or 0), op.profit and money(op.profit) or "",
                    },
                }
            end
        end
        c.list:SetData(data)
    end,
})

-- Mail -------------------------------------------------------------------------------------------

local OTHER_COLOR = { cod = "risk", own = "profit", stranger_gold = "loss", plain = "text" }

UI.RegisterTab({
    id = "mail", label = L.TAB_MAIL, module = "Mail",
    build = function(c)
        c.title = UI.Text(c, "GameFontNormal")
        c.title:SetPoint("TOPLEFT")
        c.summary = UI.Lines((function()
            local f = CreateFrame("Frame", nil, c)
            f:SetPoint("TOPLEFT", 0, -20)
            f:SetSize(580, 100)
            return f
        end)(), 6, 580)
        c.collect = UI.Button(c, L.MAIL_COLLECT:format(0), 200, function() ns.Mail.Collect() end)
        c.collect:SetPoint("TOPLEFT", 0, -122)
        c.otherTitle = UI.Text(c, "GameFontNormal")
        c.otherTitle:SetPoint("TOPLEFT", 0, -156)
        c.other = UI.ScrollList(c, {
            { width = 120 }, { width = 210 }, { width = 140, justify = "RIGHT" },
        }, 9, {
            button = {
                width = 90,
                text = function(d)
                    if d.kind == "cod" then return L.BTN_PAY_COD end
                    if d.kind == "own" then return L.BTN_TAKE end
                    return L.BTN_RETURN
                end,
                shown = function(d) return d.kind ~= "plain" end,
                onClick = function(d)
                    if d.kind == "cod" then ns.Mail.PayCod(d.index)
                    elseif d.kind == "own" then ns.Mail.TakeOwn(d.index)
                    else ns.Mail.Return(d.index) end
                end,
            },
            onSelect = function(d) c.selected = d; UI.Refresh() end,
            onEnter = function(row, d)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(d.subject, 1, 1, 1, true)
                if d.kind == "stranger_gold" then GameTooltip:AddLine(L.MAIL_STRANGER_WARN, 1, 0.35, 0.29, true) end
                if d.kind == "cod" then
                    local info = ns.Mail.CodInfo(d.index)
                    if info then
                        GameTooltip:AddDoubleLine(L.COD_PRICE, money(info.cod), 1, 0.82, 0, 1, 1, 1)
                        GameTooltip:AddDoubleLine(L.COD_VALUE, money(info.value), 1, 0.82, 0, 1, 1, 1)
                        GameTooltip:AddDoubleLine(L["COD_" .. info.verdict], money(info.profit), 1, 0.82, 0, 1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end,
        })
        c.other:SetPoint("TOPLEFT", 0, -176)
        c.other:SetPoint("RIGHT")
        c.other:SetHeight(9 * 22)
        c.returnCod = UI.Button(c, L.BTN_RETURN, 90, function()
            if c.selected and c.selected.kind == "cod" then ns.Mail.Return(c.selected.index) end
        end, L.TIP_RETURN_COD)
        c.returnCod:SetPoint("BOTTOMRIGHT", 0, 0)
        c.codLine = UI.Text(c, "GameFontHighlightSmall")
        c.codLine:SetPoint("BOTTOMLEFT", 0, 6)
        c.codLine:SetWidth(480)
    end,
    refresh = function(c)
        if not ns.Mail.mailOpen then
            c.title:SetText(L.MAIL_OPEN_BOX)
            UI.SetLines(c.summary, {})
            c.collect:Hide()
            c.otherTitle:SetText("")
            c.other:SetData({})
            c.returnCod:Hide()
            c.codLine:SetText("")
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
        c.title:SetText(L.MAIL_AUCTION_TITLE:format(#inbox.auction, money(inbox.money)))
        local texts = {}
        for _, kind in ipairs(order) do
            local g = groups[kind]
            texts[#texts + 1] = ("%s ×%d — %s%s"):format(L["MAILKIND_" .. kind] or kind, g.n,
                table.concat(g.names, ", "), g.money > 0 and (" · " .. money(g.money)) or "")
        end
        UI.SetLines(c.summary, texts)
        c.collect:Show()
        c.collect:SetText(L.MAIL_COLLECT:format(#inbox.auction))
        c.collect:SetEnabled(#inbox.auction > 0 and not ns.Mail.collecting)
        c.otherTitle:SetText(L.MAIL_OTHER_TITLE:format(#inbox.other))
        local data = {}
        for _, h in ipairs(inbox.other) do
            local amount = h.cod > 0 and (L.MAIL_COD .. " " .. money(h.cod)) or (h.money > 0 and money(h.money) or "")
            h.cols = { UI.Colorize(h.sender or "?", OTHER_COLOR[h.kind] or "text"), h.subject, amount }
            data[#data + 1] = h
        end
        c.other:SetData(data)
        local sel = c.selected
        if sel and sel.kind == "cod" then
            local info = ns.Mail.CodInfo(sel.index)
            c.returnCod:Show()
            c.codLine:SetText(info and L.COD_LINE:format(money(info.cod), money(info.value),
                UI.Colorize(L["COD_" .. info.verdict], info.verdict == "good" and "profit" or "loss"), money(info.profit)) or "")
        else
            c.returnCod:Hide()
            c.codLine:SetText("")
        end
    end,
})
