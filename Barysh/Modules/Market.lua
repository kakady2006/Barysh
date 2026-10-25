local _, ns = ...

local MarketStats, Lots, AH, Items = ns.MarketStats, ns.Lots, ns.AH, ns.Items

-- Numbers for the "Market" tab: one item over 24 h / 7 / 30 days, depth, verdicts, movers.
-- 30 days come from the PC (Data/Market.lua); the addon itself keeps summaryDays of history.
-- TZ: "Вкладка «Рынок»".
local M = ns:NewModule("Market", { group = "trade" })
ns.MarketModule = M

M.PERIODS = { day = 86400, week = 7 * 86400, month = 30 * 86400 }
M.POINTS = 24

-- House keys for the house choice: current | faction | neutral | both.
function M.Keys(choice)
    local faction, neutral = AH.FactionKey(), AH.NeutralKey()
    local neutralOn = ns.IsModuleEnabled("Neutral")
    if choice == "neutral" and neutralOn then return { neutral } end
    if choice == "faction" then return { faction } end
    if choice == "both" and neutralOn then return { faction, neutral } end
    return { ns.Prices.DefaultKey() }
end

-- Daily series from the PC: "p1,p2,...", oldest first, empty = no data that day.
local function syncedSeries(key, itemID)
    local m = ns.market and ns.market.series and ns.market.series[key]
    local e = m and m[itemID]
    if not e then return nil end
    local prices, sales = {}, {}
    local i = 0
    for v in (e[1] .. ","):gmatch("([^,]*),") do
        i = i + 1
        prices[i] = tonumber(v)
    end
    i = 0
    for v in ((e[2] or "") .. ","):gmatch("([^,]*),") do
        i = i + 1
        sales[i] = tonumber(v) or 0
    end
    return prices, sales
end

-- Everything about one item on one house for a period ("day" | "week" | "month").
function M.Info(itemID, key, period)
    local now = ns.Now()
    local h = ns.db.ah[key]
    local s = ns.Prices.Item(itemID, key)
    local lots = Lots.Decode(h and h.snap[itemID])
    local hist = h and h.hist[itemID] or {}
    local seconds = M.PERIODS[period] or M.PERIODS.week
    local info = {
        key = key, itemID = itemID, summary = s, lots = lots,
        min = s.currentMin, market = s.market or s.current, onMarket = s.onMarket, perDay = s.perDay,
        change = MarketStats.Change(hist, now, seconds),
        verdicts = MarketStats.Verdicts(lots, hist, now),
        depth = MarketStats.Depth(lots, s.perDay, 8),
    }
    if period == "month" then
        local prices, sales = syncedSeries(key, itemID)
        if prices then
            info.series = {}
            for i, p in ipairs(prices) do info.series[i] = { p = p } end
            info.sales = sales
        end
    end
    if not info.series then
        info.series = MarketStats.Series(hist, now - seconds, now, M.POINTS)
        local days = period == "day" and 1 or (period == "month" and 30 or 7)
        info.sales = MarketStats.SalesSeries(h and h.sales[itemID] or {}, now, days)
    end
    return info
end

-- Biggest movers over 24 h on a house.
function M.Movers(key, n)
    local h = ns.db.ah[key]
    if not h then return {}, {} end
    return MarketStats.Movers(h.hist, ns.Now(), n or 8, 5)
end

-- Item search by name among items the scans have seen.
function M.Find(text)
    local id = ns.ItemLists.ParseItem(text)
    if id then return id end
    text = (text or ""):lower()
    if text == "" then return nil end
    local h = ns.db.ah[ns.Prices.DefaultKey()]
    for itemID in pairs(h and h.hist or {}) do
        local name = Items.Name(itemID)
        if name and name:lower():find(text, 1, true) then return itemID end
    end
end

-- "Export for analysis": BaryshSync builds the file from its database after the next save.
function M.RequestExport(itemIDs, key)
    local req = { t = ns.Now(), ah = key or ns.Prices.DefaultKey(), items = itemIDs }
    table.insert(ns.db.exportRequests, req)
    ns.Print(ns.L.EXPORT_REQUESTED)
    return req
end

function M:OnEnable() end
