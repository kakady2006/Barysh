local _, ns = ...

local Deals, Lots, Items, AH, Jobs, MarketStats, Disenchant =
    ns.Deals, ns.Lots, ns.Items, ns.AH, ns.Jobs, ns.MarketStats, ns.Disenchant
local L = ns.L

-- Profitable purchases list and buying. TZ: "Сделки", docs/decisions.md items 1-2.
-- Commodities: the first click asks the price (StartCommoditiesPurchase), the second click confirms
-- if the quote is not above the row's cost; a higher quote is cancelled.
-- VERIFY: if ConfirmCommoditiesPurchase works without a click on Forever, confirm right away.
-- Items: the lot is found by an item search beforehand (no click needed), the click places the buyout.
local M = ns:NewModule("Deals", { group = "trade" })
ns.DealsModule = M

M.ITEMS_PER_STEP = 150
M.PRICE_TOLERANCE = 0     -- confirm a commodity purchase only up to the expected total
M.SEARCH_TIMEOUT = 5

M.rows = {}

-- Data for Logic/Deals.lua ----------------------------------------------------------------

-- Values of reagents in known recipes (all characters), for "raw materials" deals.
function M.ReagentValues(key)
    local recipes = {}
    for _, byID in pairs(ns.db.recipes) do
        for _, r in pairs(byID) do recipes[#recipes + 1] = r end
    end
    if #recipes == 0 then return {} end
    local cut = AH.Cut(key)
    return ns.Recipes.ReagentValues(recipes,
        function(id) return ns.Prices.Value(id, key) end,
        function(id)
            local _, v = ns.BestUse(id, key)
            return v or (ns.Prices.Value(id, key) and ns.Money.AfterCut(ns.Prices.Value(id, key), cut))
        end)
end

function M.Options(key)
    local s = ns.settings.deals
    local types = {}
    for k, v in pairs(s.types) do types[k] = v end
    if not ns.IsModuleEnabled("Neutral") then types.arbitrage = false end
    if not ns.IsModuleEnabled("Stock") then types.stock = false end
    return { cut = AH.Cut(key), minProfit = s.minProfit, maxDays = s.maxDaysToSell, types = types }
end

function M.ItemData(key, itemID, lots, ctx)
    local s = ns.Prices.Item(itemID, key)
    local info = Items.Info(itemID)
    local market = s.market or s.current
    if s.isNew then market = Deals.NewItemReference(lots) or market end
    local it = {
        itemID = itemID, lots = lots, market = market, perDay = s.perDay,
        commodity = Items.IsCommodity(itemID, lots),
        vendor = info and info.sellPrice or 0,
        deposit = AH.DepositEstimate(info and info.sellPrice, key),
    }
    if info and Disenchant.IsDisenchantable(info.classID, info.quality) then
        it.de = ns.DisenchantValue(itemID, key)
    end
    local entry = ns.ItemLists.Entry("stock", itemID)
    if entry then it.stock = { buyBelow = entry.buyBelow, cap = entry.cap } end
    local rv = ctx.reagents[itemID]
    if rv then it.craft = rv.value end
    if ctx.other then
        local o = ns.Prices.Item(itemID, ctx.other)
        local p = o.market or o.current
        if p then it.other = { price = p, cut = AH.Cut(ctx.other) } end
    end
    return it
end

-- Recomputes the list in frame-sized steps. onDone(rows).
function M.Compute(key, onDone)
    key = key or ns.Prices.DefaultKey()
    local h = ns.db.ah[key]
    if M.job then Jobs.Cancel(M.job) end
    if not h then
        M.rows, M.key = {}, key
        if onDone then onDone(M.rows) end
        return
    end
    local opts = M.Options(key)
    local ctx = { reagents = M.ReagentValues(key) }
    if opts.types.arbitrage then ctx.other = AH.OtherKey(key) end
    local noBuy = ns.settings.lists.noBuy.items
    local ids = {}
    for id in pairs(h.snap) do
        if not noBuy[id] then ids[#ids + 1] = id end
    end
    local rows, i = {}, 0
    M.computing = true
    M.job = Jobs.Run("deals", function()
        local stop = math.min(#ids, i + M.ITEMS_PER_STEP)
        for k = i + 1, stop do
            local id = ids[k]
            local lots = Lots.Decode(h.snap[id])
            for _, r in ipairs(Deals.Evaluate(M.ItemData(key, id, lots, ctx), opts)) do rows[#rows + 1] = r end
        end
        i = stop
        return i >= #ids
    end, function(ok)
        M.job, M.computing = nil, false
        if not ok then return end
        Deals.Sort(rows)
        M.rows, M.key, M.computed = rows, key, ns.Now()
        M.Alert(rows)
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        if onDone then onDone(rows) end
    end)
end

-- Rows for the window: filter = deal type or nil; affordable = only what the gold covers.
function M.Rows(filter, affordable)
    local out = {}
    local money = affordable and GetMoney() or nil
    for _, r in ipairs(M.rows) do
        if not r.bought and (not filter or r.type == filter) and (not money or r.cost <= money) then
            out[#out + 1] = r
        end
    end
    return out
end

function M.Summary(affordable)
    local open = {}
    for _, r in ipairs(M.rows) do
        if not r.bought then open[#open + 1] = r end
    end
    return Deals.Summary(open, affordable and GetMoney() or nil)
end

-- Alerts ------------------------------------------------------------------------------------

M.alerted = {}

function M.Alert(rows)
    local s = ns.settings.deals
    local best
    for _, r in ipairs(rows) do
        local id = r.itemID .. ":" .. r.maxPrice .. ":" .. r.qty
        if r.profit >= s.soundFrom and not M.alerted[id] then
            M.alerted[id] = true
            if not best or r.profit > best.profit then best = r end
        end
    end
    if not best then return end
    PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)
    ns.Print(L.DEAL_ALERT:format(Items.ColoredName(best.itemID), ns.FormatMoney(best.profit)))
    if s.popup and ns.UI and ns.UI.Show then ns.UI.Show("deals") end
end

-- Price drop of 30%+ in 24 h on a big volume: one message per item per day.
M.crashSeen = {}
function M.CheckCrashes(stats)
    if not ns.settings.deals.crashAlert then return end
    local h = ns.db.ah[stats.key]
    if not h then return end
    local now, day = ns.Now(), math.floor(ns.Now() / 86400)
    for _, id in ipairs(stats.ids) do
        local hist = h.hist[id]
        if hist and M.crashSeen[id] ~= day and MarketStats.IsCrash(hist, now) then
            M.crashSeen[id] = day
            local ch = MarketStats.Change(hist, now, 86400)
            ns.Print(L.CRASH_ALERT:format(Items.ColoredName(id), math.floor(-ch * 100 + 0.5)))
        end
    end
end

-- Buying ------------------------------------------------------------------------------------

M.buying = nil   -- { row, stage = "quote" | "confirm" | "confirming" | "bidding" }
M.CONFIRM_WAIT = 20 -- seconds the quoted price waits for the confirming click

local function finishPurchase(row)
    row.bought = true
    ns.db.purchases[row.itemID] = { type = row.type, t = ns.Now() }
    -- Take the bought lots out of the snapshot so the list does not offer them again.
    local h = ns.db.ah[M.key]
    if h and h.snap[row.itemID] then
        local lots = Lots.Decode(h.snap[row.itemID])
        local left = row.qty
        table.sort(lots, function(a, b) return a.price < b.price end)
        for _, l in ipairs(lots) do
            if left <= 0 or l.price > row.maxPrice then break end
            local take = math.min(l.qty, left)
            l.qty = l.qty - take
            left = left - take
        end
        local kept = {}
        for _, l in ipairs(lots) do if l.qty > 0 then kept[#kept + 1] = l end end
        h.snap[row.itemID] = #kept > 0 and Lots.Encode(kept) or nil
    end
    ns.Print(L.BOUGHT:format(row.qty, Items.ColoredName(row.itemID), ns.FormatMoney(row.cost)))
    M.buying = nil
    M.PrepareNext()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function failPurchase(reason)
    local b = M.buying
    M.buying = nil
    if b and b.row then b.row.auctionID = nil end
    ns.Print(L["BUY_FAIL_" .. reason] or reason)
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- Finds the auction ID of an item row with a search (no click needed).
function M.Prepare(row)
    if not row or row.commodity or row.auctionID or not ns.Scan.ahOpen then return end
    if M.searching == row then return end
    if not AH.CanSearch() then
        C_Timer.After(0.3, function() if M.enabled then M.Prepare(row) end end)
        return
    end
    M.searching = row
    row.searched = nil
    AH.Search(row.itemID)
    C_Timer.After(M.SEARCH_TIMEOUT, function()
        if M.searching == row then
            M.searching = nil
            row.searched = true
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        end
    end)
end

function M.PrepareNext()
    local rows = M.Rows(nil, ns.settings.deals.affordable)
    M.Prepare(rows[1])
end

local function onItemResults(_, _, itemKey)
    local row = M.searching
    if not row or not itemKey or itemKey.itemID ~= row.itemID then return end
    M.searching = nil
    row.searched = true
    local lots = AH.ItemResults(itemKey)
    for _, l in ipairs(lots) do
        if l.price <= row.maxPrice and l.qty == row.qty and not l.taken then
            row.auctionID = l.auctionID
            row.cost = l.price * l.qty
            break
        end
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- What the buy button would do for a row: "buy" | "search" | "busy" | "gone".
function M.ButtonState(row)
    if not row or not ns.Scan.ahOpen then return "closed" end
    if M.buying then
        if M.buying.row == row and M.buying.stage == "confirm" then return "confirm" end
        return "busy"
    end
    if row.commodity or row.auctionID then return "buy" end
    if row.searched then return "gone" end
    return "search"
end

-- Must be called from a click.
function M.Buy(row)
    if not row or row.bought or not ns.Scan.ahOpen then return false end
    local b = M.buying
    if b and b.row == row and b.stage == "confirm" then
        b.stage = "confirming"
        AH.ConfirmCommodityPurchase(row.itemID, row.qty)
        return true
    end
    if b then return false end
    if row.commodity then
        M.buying = { row = row, stage = "quote", t = GetTime() }
        AH.StartCommodityPurchase(row.itemID, row.qty)
        C_Timer.After(10, function()
            if M.buying and M.buying.row == row and M.buying.stage == "quote" then
                AH.CancelCommodityPurchase()
                failPurchase("timeout")
            end
        end)
        return true
    end
    if not row.auctionID then
        M.Prepare(row)
        return false
    end
    M.buying = { row = row, stage = "bidding", t = GetTime() }
    AH.BuyItem(row.auctionID, row.cost)
    C_Timer.After(10, function()
        if M.buying and M.buying.row == row then failPurchase("timeout") end
    end)
    return true
end

function M.BuyNext()
    if M.buying and M.buying.stage == "confirm" then return M.Buy(M.buying.row) end
    local rows = M.Rows(nil, ns.settings.deals.affordable)
    return M.Buy(rows[1])
end

local function onPriceUpdated(_, _, unitPrice, totalPrice)
    local b = M.buying
    if not b or b.stage ~= "quote" then return end
    local row = b.row
    if totalPrice > row.cost * (1 + M.PRICE_TOLERANCE) then
        AH.CancelCommodityPurchase()
        failPurchase("price")
        return
    end
    b.stage = "confirm"
    row.cost = totalPrice
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    C_Timer.After(M.CONFIRM_WAIT, function()
        if M.buying == b and b.stage == "confirm" then
            AH.CancelCommodityPurchase()
            M.buying = nil
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        end
    end)
end

ns.Scan.OnApplied(function(stats)
    if not M.enabled then return end
    M.CheckCrashes(stats)
    if stats.full or (ns.UI and ns.UI.current and ns.UI.current.id == "deals") then M.Compute(stats.key) end
end)

function M:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        C_Timer.After(0.5, function() if M.enabled then M.Compute() end end)
    end)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
        if M.buying then failPurchase("closed") end
        M.searching = nil
    end)
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", onItemResults)
    self:RegisterEvent("COMMODITY_PRICE_UPDATED", onPriceUpdated)
    self:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function()
        if M.buying then failPurchase("unavailable") end
    end)
    self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
        if M.buying and M.buying.row.commodity then finishPurchase(M.buying.row) end
    end)
    self:RegisterEvent("COMMODITY_PURCHASE_FAILED", function()
        if M.buying then failPurchase("failed") end
    end)
    self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID)
        local b = M.buying
        if b and not b.row.commodity and (not auctionID or auctionID == b.row.auctionID) then finishPurchase(b.row) end
    end)
end

function M:OnDisable()
    if M.job then Jobs.Cancel(M.job) end
    M.rows, M.buying, M.searching, M.job = {}, nil, nil, nil
end
