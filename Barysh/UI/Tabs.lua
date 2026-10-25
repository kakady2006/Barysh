local _, ns = ...

local UI = ns.UI
local L = ns.L

-- Overview tab. TZ: "Вкладка «Обзор»": capital and its parts, gold per character, today,
-- income per hour and by activity, "Needs attention" with jumps to other tabs.

function UI.Lines(parent, n, width, template)
    local out = {}
    for i = 1, n do
        local fs = UI.Text(parent, template or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        fs:SetWidth(width or 270)
        fs:SetWordWrap(false)
        out[i] = fs
    end
    return out
end

function UI.SetLines(fsList, texts)
    for i, fs in ipairs(fsList) do fs:SetText(texts[i] or "") end
end

local function box(parent, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(w, h)
    return f
end

local function title(parent, x, y, text)
    local fs = UI.Text(parent, "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local money = ns.FormatMoney

-- Value of a stack for capital: market price after the cut, else the vendor price.
function UI.CapitalValue(itemID)
    local key = ns.Prices.DefaultKey()
    local v = ns.Prices.Value(itemID, key)
    if v then return ns.Money.AfterCut(v, ns.AH.Cut(key)) end
    local info = ns.Items.Info(itemID)
    return info and info.sellPrice or nil
end

-- "Needs attention": { {text, tab} }
function UI.Attention()
    local out = {}
    local h = ns.db.ah[ns.Prices.DefaultKey()]
    local age = h and h.lastFull and ns.Now() - h.lastFull
    if not age or age > ns.settings.staleHours * 3600 then
        out[#out + 1] = { UI.Colorize(L.OV_DATA_OLD:format(age and ns.FormatAge(age) or L.NEVER), "risk") }
    end
    if ns.db.autoScanNeedsClick then out[#out + 1] = { L.SCAN_NEEDS_CLICK } end
    if ns.Sync.enabled and ns.Sync.IsStale() then out[#out + 1] = { UI.Colorize(L.OV_SYNC_OLD, "risk") } end
    if ns.IsModuleEnabled("Selling") then
        local n = ns.SellingModule.UndercutCount()
        if n > 0 then out[#out + 1] = { UI.Colorize(L.OV_UNDERCUT:format(n), "risk"), "selling" } end
    end
    if ns.IsModuleEnabled("Mail") and (ns.db.auctionMail or 0) > 0 then
        out[#out + 1] = { L.OV_AUCTION_MAIL:format(ns.db.auctionMail), "mail" }
    end
    if ns.IsModuleEnabled("Stock") then
        local n = ns.StockModule.ExitCount()
        if n > 0 then out[#out + 1] = { UI.Colorize(L.OV_STOCK_BELOW:format(n), "loss"), "stock" } end
    end
    local returned = 0
    for _, n in pairs(ns.db.returned or {}) do returned = returned + n end
    if returned > 0 then out[#out + 1] = { L.OV_RETURNED:format(returned), "selling" } end
    if #ns.db.errors > 0 then out[#out + 1] = { L.OV_ERRORS:format(#ns.db.errors) } end
    return out
end

UI.RegisterTab({
    id = "overview", label = L.TAB_OVERVIEW,
    build = function(c)
        title(c, 0, 0, L.OV_CAPITAL)
        c.capital = UI.Lines(box(c, 0, -20, 280, 100), 6)
        title(c, 0, -124, L.OV_CHARS)
        c.chars = UI.Lines(box(c, 0, -144, 280, 140), 8)
        title(c, 300, 0, L.OV_TODAY)
        c.today = UI.Lines(box(c, 300, -20, 280, 60), 3)
        title(c, 300, -76, L.OV_WEEK)
        c.week = UI.Lines(box(c, 300, -96, 280, 110), 7)
        title(c, 300, -214, L.OV_ATTENTION)
        c.attention = {}
        for i = 1, 6 do
            local b = CreateFrame("Button", nil, c)
            b:SetPoint("TOPLEFT", 300, -234 - (i - 1) * 18)
            b:SetSize(280, 18)
            b.text = UI.Text(b, "GameFontHighlightSmall")
            b.text:SetPoint("LEFT")
            b.text:SetWidth(280)
            b.text:SetWordWrap(false)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.08)
            b:SetScript("OnClick", function(self) if self.tab then UI.SelectTab(self.tab) end end)
            c.attention[i] = b
        end
    end,
    refresh = function(c)
        local cap = ns.Stock.Capital(ns.db.chars, UI.CapitalValue)
        UI.SetLines(c.capital, {
            L.OV_TOTAL:format(money(cap.total)),
            L.OV_PART_GOLD:format(money(cap.gold)),
            L.OV_PART_BAGS:format(money(cap.bags)),
            L.OV_PART_BANK:format(money(cap.bank)),
            L.OV_PART_MAIL:format(money(cap.mail)),
            L.OV_PART_AUCTIONS:format(money(cap.auctions)),
        })
        local chars = {}
        for name, data in pairs(ns.db.chars) do
            chars[#chars + 1] = { name = name:match("^[^-]+") or name, money = data.money or 0, total = cap.perChar[name] or 0 }
        end
        table.sort(chars, function(a, b) return a.total > b.total end)
        local texts = {}
        for i = 1, math.min(#chars, 8) do
            texts[i] = ("%s: %s · %s"):format(chars[i].name, money(chars[i].money), UI.Colorize(money(chars[i].total), "muted"))
        end
        UI.SetLines(c.chars, texts)

        if ns.LedgerModule.enabled then
            local t = ns.LedgerModule.Totals("today")
            local perHour = ns.LedgerModule.PerHour("today")
            UI.SetLines(c.today, {
                L.OV_PROFIT:format(UI.Colorize(money(t.profit), t.profit >= 0 and "profit" or "loss")),
                L.OV_DEALS:format(t.count),
                L.OV_PER_HOUR:format(perHour and money(perHour) or "—"),
            })
            local week = ns.LedgerModule.ByActivity(ns.LedgerModule.PeriodStart("week"))
            local wt = {}
            local weekHour = ns.LedgerModule.PerHour("week")
            wt[1] = L.OV_PER_HOUR:format(weekHour and money(weekHour) or "—")
            for _, a in ipairs(ns.LedgerModule.ACTIVITIES) do
                if week[a] ~= 0 then wt[#wt + 1] = ("%s: %s"):format(L["ACT_" .. a], money(week[a])) end
            end
            UI.SetLines(c.week, wt)
        else
            UI.SetLines(c.today, { L.OV_LEDGER_OFF })
            UI.SetLines(c.week, {})
        end

        local attn = UI.Attention()
        if #attn == 0 then attn[1] = { UI.Colorize(L.OV_ALL_GOOD, "muted") } end
        for i, b in ipairs(c.attention) do
            local a = attn[i]
            b.text:SetText(a and (a[1] .. (a[2] and " ›" or "")) or "")
            b.tab = a and a[2]
            b:SetShown(a ~= nil)
        end
    end,
})
