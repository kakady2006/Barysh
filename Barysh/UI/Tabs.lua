local _, ns = ...

local UI = ns.UI
local L = ns.L

-- Overview tab (barysh-design/Overview): capital with its parts, gold per character, today,
-- income per hour by activity for the week, "Needs attention" with a button to the right section.

local money = ns.FormatMoney

-- Value of a stack for capital: market price after the cut, else the vendor price.
function UI.CapitalValue(itemID)
    local key = ns.Prices.DefaultKey()
    local v = ns.Prices.Value(itemID, key)
    if v then return ns.Money.AfterCut(v, ns.AH.Cut(key)) end
    local info = ns.Items.Info(itemID)
    return info and info.sellPrice or nil
end

-- "Needs attention": { {text, tab, button label} }; tab "scan" means the full scan button.
function UI.Attention()
    local out = {}
    local h = ns.db.ah[ns.Prices.DefaultKey()]
    local age = h and h.lastFull and ns.Now() - h.lastFull
    if not age or age > ns.settings.staleHours * 3600 then
        out[#out + 1] = { UI.Colorize(L.OV_DATA_OLD:format(age and ns.FormatAge(age) or L.NEVER), "risk"), "scan", L.BTN_SCAN_SHORT }
    end
    if ns.db.autoScanNeedsClick then out[#out + 1] = { L.SCAN_NEEDS_CLICK } end
    if ns.Sync.enabled and ns.Sync.IsStale() then out[#out + 1] = { UI.Colorize(L.OV_SYNC_OLD, "risk") } end
    if ns.IsModuleEnabled("Selling") then
        local n = ns.SellingModule.UndercutCount()
        if n > 0 then out[#out + 1] = { L.OV_UNDERCUT:format(n), "selling", L.TAB_SELLING } end
    end
    if ns.IsModuleEnabled("Mail") and (ns.db.auctionMail or 0) > 0 then
        out[#out + 1] = { L.OV_AUCTION_MAIL:format(ns.db.auctionMail), "mail", L.TAB_MAIL }
    end
    if ns.IsModuleEnabled("Stock") then
        local n = ns.StockModule.ExitCount()
        if n > 0 then out[#out + 1] = { UI.Colorize(L.OV_STOCK_BELOW:format(n), "loss"), "stock", L.TAB_STOCK } end
    end
    local returned = 0
    for _, n in pairs(ns.db.returned or {}) do returned = returned + n end
    if returned > 0 then out[#out + 1] = { L.OV_RETURNED:format(returned), "selling", L.TAB_SELLING } end
    if #ns.db.errors > 0 then out[#out + 1] = { L.OV_ERRORS:format(#ns.db.errors) } end
    return out
end

-- capital parts: key, label, colour of the bar segment
local PARTS = {
    { "gold", L.OV_PART_GOLD, { 0.94, 0.76, 0.19 } },
    { "goods", L.OV_PART_GOODS, { 0.3, 0.6, 1 } },
    { "auctions", L.OV_PART_AUCTIONS, { 0.62, 0.36, 0.86 } },
    { "mail", L.OV_PART_MAIL, { 0.48, 0.55, 0.42 } },
}

local function swatch(parent, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(9, 9)
    t:SetColorTexture(color[1], color[2], color[3], 1)
    return t
end

UI.RegisterTab({
    id = "overview", label = L.TAB_OVERVIEW,
    build = function(c)
        local left = CreateFrame("Frame", nil, c)
        left:SetPoint("TOPLEFT")
        left:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -6, 0)
        local right = CreateFrame("Frame", nil, c)
        right:SetPoint("TOPLEFT", c, "TOP", 6, 0)
        right:SetPoint("BOTTOMRIGHT")

        -- Capital
        local cap = UI.Card(left, L.OV_CAPITAL)
        cap:SetPoint("TOPLEFT")
        cap:SetPoint("TOPRIGHT")
        cap:SetHeight(186)
        c.total = UI.Text(cap.body, "GameFontHighlightHuge")
        c.total:SetPoint("TOPLEFT", 0, 0)
        c.bar = CreateFrame("Frame", nil, cap.body)
        c.bar:SetPoint("TOPLEFT", 0, -30)
        c.bar:SetPoint("TOPRIGHT", 0, -30)
        c.bar:SetHeight(10)
        c.segments = {}
        c.parts = {}
        for i, p in ipairs(PARTS) do
            local seg = c.bar:CreateTexture(nil, "ARTWORK")
            seg:SetColorTexture(p[3][1], p[3][2], p[3][3], 1)
            c.segments[i] = seg
            local pair = UI.Pair(cap.body, -48 - (i - 1) * 19)
            pair.l:SetPoint("TOPLEFT", 14, -48 - (i - 1) * 19)
            local sw = swatch(cap.body, p[3])
            sw:SetPoint("RIGHT", pair.l, "LEFT", -5, 0)
            c.parts[i] = pair
        end
        local note = UI.Hint(cap.body, L.OV_CAPITAL_NOTE)
        note:SetPoint("TOPLEFT", 0, -128)

        -- Gold per character
        local chars = UI.Card(left, L.OV_CHARS)
        chars:SetPoint("TOPLEFT", cap, "BOTTOMLEFT", 0, -10)
        chars:SetPoint("TOPRIGHT", cap, "BOTTOMRIGHT", 0, -10)
        chars:SetPoint("BOTTOM", left, "BOTTOM")
        c.chars = {}
        for i = 1, 8 do c.chars[i] = UI.Pair(chars.body, -(i - 1) * 19) end

        -- Today
        local today = UI.Card(right, L.OV_TODAY)
        today:SetPoint("TOPLEFT")
        today:SetPoint("TOPRIGHT")
        today:SetHeight(100)
        c.today = { UI.Pair(today.body, 0), UI.Pair(today.body, -19), UI.Pair(today.body, -38) }

        -- Income per hour by activity, week
        local act = UI.Card(right, L.OV_ACTIVITY_WEEK)
        act:SetPoint("TOPLEFT", today, "BOTTOMLEFT", 0, -10)
        act:SetPoint("TOPRIGHT", today, "BOTTOMRIGHT", 0, -10)
        act:SetHeight(32 + 19 * #ns.LedgerModule.ACTIVITIES + 6)
        c.acts = {}
        for i = 1, #ns.LedgerModule.ACTIVITIES do
            local y = -(i - 1) * 19
            local row = { label = UI.Text(act.body, "GameFontHighlightSmall"), value = UI.Text(act.body, "GameFontHighlightSmall") }
            row.label:SetPoint("TOPLEFT", 0, y)
            row.value:SetPoint("TOPRIGHT", 0, y)
            row.value:SetJustifyH("RIGHT")
            row.bar = UI.Bar(act.body, 120, 8)
            row.bar:SetPoint("TOPLEFT", 112, y - 3)
            c.acts[i] = row
        end

        -- Needs attention
        local attn = UI.Card(right, L.OV_ATTENTION)
        attn:SetPoint("TOPLEFT", act, "BOTTOMLEFT", 0, -10)
        attn:SetPoint("TOPRIGHT", act, "BOTTOMRIGHT", 0, -10)
        attn:SetPoint("BOTTOM", right, "BOTTOM")
        c.attention = {}
        for i = 1, 5 do
            local y = -(i - 1) * 28
            local text = UI.Text(attn.body, "GameFontHighlightSmall")
            text:SetPoint("TOPLEFT", 0, y - 5)
            text:SetPoint("RIGHT", attn.body, "RIGHT", -96, 0)
            text:SetWordWrap(false)
            local b = UI.Button(attn.body, "", 88, function(self)
                if self.tab == "scan" then
                    local ok, why, wait = ns.Scan.StartFull("button")
                    if not ok then
                        ns.Print(why == "cooldown" and L.SCAN_FAIL_cooldown:format(ns.FormatCountdown(wait)) or (L["SCAN_FAIL_" .. why] or why))
                    end
                elseif self.tab then
                    UI.SelectTab(self.tab)
                end
            end)
            b:SetHeight(22)
            b:SetPoint("TOPRIGHT", 0, y)
            c.attention[i] = { text = text, button = b }
        end
    end,
    refresh = function(c)
        local cap = ns.Stock.Capital(ns.db.chars, UI.CapitalValue)
        c.total:SetText(money(cap.total))
        local values = { gold = cap.gold, goods = cap.bags + cap.bank, auctions = cap.auctions, mail = cap.mail }
        local width = c.bar:GetWidth() or 0
        local x = 0
        for i, p in ipairs(PARTS) do
            local v = values[p[1]] or 0
            local seg = c.segments[i]
            local w = cap.total > 0 and width * v / cap.total or 0
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT", c.bar, "TOPLEFT", x, 0)
            seg:SetSize(math.max(0.001, w), 10)
            seg:SetShown(w >= 1)
            x = x + w
            c.parts[i]:Set(p[2], money(v))
        end

        local chars = {}
        for name, data in pairs(ns.db.chars) do
            chars[#chars + 1] = { name = name:match("^[^-]+") or name, money = data.money or 0 }
        end
        table.sort(chars, function(a, b) return a.money > b.money end)
        for i, pair in ipairs(c.chars) do
            local ch = chars[i]
            pair:Set(ch and ch.name or "", ch and money(ch.money) or "")
        end

        local acts = ns.LedgerModule.ACTIVITIES
        if ns.LedgerModule.enabled then
            local t = ns.LedgerModule.Totals("today")
            local perHour = ns.LedgerModule.PerHour("today")
            local played = ns.Inventory.PlaySeconds(ns.LedgerModule.PeriodStart("today"), math.huge)
            c.today[1]:Set(L.OV_PROFIT_LABEL, UI.Colorize(money(t.profit), t.profit >= 0 and "profit" or "loss"))
            c.today[2]:Set(L.OV_DEALS_LABEL, tostring(t.count))
            c.today[3]:Set(L.OV_PLAYED_LABEL, L.OV_PLAYED_VALUE:format(math.floor(played / 3600), math.floor(played % 3600 / 60),
                perHour and money(perHour) or "—"))
            local week = ns.LedgerModule.ByActivity(ns.LedgerModule.PeriodStart("week"))
            local hours = ns.Inventory.PlaySeconds(ns.LedgerModule.PeriodStart("week"), math.huge) / 3600
            local top = 0
            for _, a in ipairs(acts) do top = math.max(top, week[a] or 0) end
            for i, a in ipairs(acts) do
                local row = c.acts[i]
                local v = week[a] or 0
                row.label:SetText(L["ACT_" .. a])
                row.value:SetText(hours >= 0.17 and money(v / hours) or money(v))
                row.bar:SetValue(top > 0 and math.max(0, v) / top or 0)
            end
        else
            c.today[1]:Set(L.OV_LEDGER_OFF, "")
            c.today[2]:Set("", "")
            c.today[3]:Set("", "")
            for _, row in ipairs(c.acts) do
                row.label:SetText("")
                row.value:SetText("")
                row.bar:SetValue(0)
            end
        end

        local attn = UI.Attention()
        if #attn == 0 then attn[1] = { UI.Colorize(L.OV_ALL_GOOD, "muted") } end
        for i, slot in ipairs(c.attention) do
            local a = attn[i]
            slot.text:SetText(a and a[1] or "")
            slot.button.tab = a and a[2]
            slot.button:SetText(a and a[3] or "")
            slot.button:SetShown(a ~= nil and a[2] ~= nil)
            if a and a[2] == "scan" then
                slot.button:SetEnabled(ns.Scan.ahOpen and ns.Scan.state == "idle" and ns.Scan.CooldownLeft() == 0)
            elseif a then
                slot.button:SetEnabled(true)
            end
        end
    end,
})
