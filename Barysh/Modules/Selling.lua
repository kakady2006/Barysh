local _, ns = ...

local Selling, Lots, Items, AH, Bags, CostBasis = ns.Selling, ns.Lots, ns.Items, ns.AH, ns.Bags, ns.CostBasis
local L = ns.L

-- Posting queue and own auctions. TZ: "Продажи", docs/decisions.md items 5-6.
-- The addon picks price, lot size and duration; the player clicks once per lot.
local M = ns:NewModule("Selling", { group = "trade" })
ns.SellingModule = M

M.queue = {}
M.owned = {}

local function marketLots(key, itemID)
    local h = ns.db.ah[key]
    return Lots.Decode(h and h.snap[itemID])
end

-- Should this bag item go to the auction house?
local function wanted(itemID, returned)
    if ns.db.sellMarked[itemID] then return true end
    if returned and ns.settings.selling.returned then return true end
    if ns.ItemLists.Has("stock", itemID) then return false end -- held for future demand
    local use = ns.BestUse(itemID)
    return use == "ah"
end

-- Builds the queue from the bags: one entry per item, with its lots.
function M.Build()
    local key = ns.Prices.DefaultKey()
    local cut = AH.Cut(key)
    local s = ns.settings.selling
    local byItem, order = {}, {}
    Bags.Each(function(bag, slot, info)
        if info.isBound then return end
        local item = Items.Info(info.itemID)
        if not item or (item.quality or 0) < 1 then return end
        local e = byItem[info.itemID]
        if not e then
            e = { itemID = info.itemID, qty = 0, bag = bag, slot = slot }
            byItem[info.itemID] = e
            order[#order + 1] = e
        end
        e.qty = e.qty + (info.stackCount or 1)
    end)
    local queue = {}
    for _, e in ipairs(order) do
        local returned = ns.db.returned and ns.db.returned[e.itemID]
        if wanted(e.itemID, returned) then
            local summary = ns.Prices.Item(e.itemID, key)
            local lots = marketLots(key, e.itemID)
            local cost = CostBasis.Average(ns.db.books, e.itemID)
            local price, warn = Selling.PostPrice(lots, cost, summary.market)
            if price then
                price = AH.RoundPostPrice(price)
                local cheaper, same = Selling.Ahead(lots, price)
                e.commodity = Items.IsCommodity(e.itemID)
                e.price, e.warn, e.cost = price, warn, cost
                e.returned = returned and true or nil
                e.duration = Selling.Duration(price, e.qty, cheaper + same, summary.perDay, s.expensive)
                e.sizes = Selling.Split(e.qty, e.commodity, s.stack)
                local info = Items.Info(e.itemID)
                local depositEach = AH.DepositEstimate(info and info.sellPrice, key) * (e.duration == "long" and 3 or 1)
                e.deposit = depositEach * e.qty
                e.revenue = ns.Money.AfterCut(price * e.qty, cut)
                queue[#queue + 1] = e
            else
                e.warn = "no_price"
            end
        end
    end
    M.queue = queue
    return queue
end

function M.Totals()
    local t = { deposit = 0, revenue = 0, lots = 0, n = #M.queue }
    for _, e in ipairs(M.queue) do
        t.deposit = t.deposit + e.deposit
        t.revenue = t.revenue + e.revenue
        t.lots = t.lots + #e.sizes
    end
    return t
end

-- Posting -----------------------------------------------------------------------------------

M.confirm = nil -- a post that the client asked to confirm (price far below market)

local function afterPost(e, size, deposit)
    table.insert(ns.db.posted, { itemID = e.itemID, qty = size, price = e.price, deposit = deposit or 0, t = ns.Now() })
    while #ns.db.posted > 500 do table.remove(ns.db.posted, 1) end
    if ns.db.returned and ns.db.returned[e.itemID] then
        ns.db.returned[e.itemID] = ns.db.returned[e.itemID] - size
        if ns.db.returned[e.itemID] <= 0 then ns.db.returned[e.itemID] = nil end
    end
    table.remove(e.sizes, 1)
    if #e.sizes == 0 then
        ns.db.sellMarked[e.itemID] = nil
        for i, q in ipairs(M.queue) do
            if q == e then table.remove(M.queue, i) break end
        end
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- Posts the next lot of the queue. Must be called from a click.
function M.PostNext()
    if not ns.Scan.ahOpen then return false, "closed" end
    local c = M.confirm
    if c then
        M.confirm = nil
        AH.ConfirmPost(c.loc, c.e.commodity, c.e.duration, c.size, c.e.price)
        afterPost(c.e, c.size, c.deposit)
        return true
    end
    local e = M.queue[1]
    if not e then return false, "empty" end
    local bag, slot = Bags.Find(e.itemID)
    if not bag then
        table.remove(M.queue, 1)
        return false, "missing"
    end
    local size = e.sizes[1]
    local loc = AH.Location(bag, slot)
    local known = AH.IsCommodityLocation(loc)
    if known ~= nil and known ~= e.commodity then
        Items.SetCommodity(e.itemID, known)
        e.commodity = known
    end
    local deposit = AH.Deposit(loc, e.itemID, e.commodity, e.duration, size)
    local needsConfirm = AH.Post(loc, e.commodity, e.duration, size, e.price)
    if needsConfirm then
        M.confirm = { e = e, loc = loc, size = size, deposit = deposit }
        ns.Print(L.POST_CONFIRM)
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        return true, "confirm"
    end
    afterPost(e, size, deposit)
    return true
end

-- Own auctions ------------------------------------------------------------------------------

-- Own active lots with their state: ok (sells first) or undercut (cancel and repost).
function M.Owned()
    local key = ns.Prices.DefaultKey()
    local out = {}
    for _, a in ipairs(AH.Owned()) do
        if not a.sold and a.price then
            local s = ns.Prices.Item(a.itemID, key)
            local lots = Selling.WithoutOwn(marketLots(key, a.itemID), a.qty, a.price)
            local st = Selling.LotState(a.price, lots, s.perDay)
            a.cheaper, a.state = st.cheaper, st.state
            if a.state == "undercut" then
                a.newPrice = Selling.PostPrice(lots, CostBasis.Average(ns.db.books, a.itemID), s.market)
                a.lostDeposit = AH.CancelCost(a.auctionID)
                if not a.lostDeposit then
                    for _, p in ipairs(ns.db.posted) do
                        if p.itemID == a.itemID and p.price == a.price and p.qty == a.qty then a.lostDeposit = p.deposit end
                    end
                end
            end
            out[#out + 1] = a
        end
    end
    table.sort(out, function(x, y)
        if x.state ~= y.state then return x.state == "undercut" end
        return x.itemID < y.itemID
    end)
    M.owned = out
    return out
end

function M.UndercutCount()
    local n = 0
    for _, a in ipairs(M.owned) do if a.state == "undercut" then n = n + 1 end end
    return n
end

-- Must be called from a click. The lot comes back by mail and joins the queue after "Collect".
function M.Cancel(a)
    if not a or not ns.Scan.ahOpen then return false end
    ns.db.sellMarked[a.itemID] = true
    AH.Cancel(a.auctionID)
    return true
end

-- Refreshes market lots of the queue items with a quick search (no click needed).
function M.RefreshPrices()
    local ids = {}
    for _, e in ipairs(M.Build()) do ids[#ids + 1] = e.itemID end
    for _, a in ipairs(M.owned) do ids[#ids + 1] = a.itemID end
    if #ids == 0 then return false, "empty" end
    return ns.Scan.StartQuick(ids)
end

ns.Scan.OnApplied(function()
    if M.enabled and ns.UI and ns.UI.current and ns.UI.current.id == "selling" then
        M.Build()
        M.Owned()
    end
end)

function M:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        AH.QueryOwned()
        M.refreshed = false
    end)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() M.confirm = nil end)
    self:RegisterEvent("OWNED_AUCTIONS_UPDATED", function()
        M.Owned()
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end)
    self:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", function() AH.QueryOwned() end)
    self:RegisterEvent("AUCTION_CANCELED", function() AH.QueryOwned() end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if ns.UI and ns.UI.current and ns.UI.current.id == "selling" and ns.UI.Frame():IsShown() then
            M.Build()
            ns.UI.Refresh()
        end
    end)
end

function M:OnDisable()
    M.queue, M.owned, M.confirm = {}, {}, nil
end
