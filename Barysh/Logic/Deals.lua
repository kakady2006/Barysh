local _, ns = ...

local Money = ns.Money

-- Profitable purchases. TZ: "Сделки", docs/decisions.md items 1-2.
-- Pure: the module gathers lots and prices, this file decides what is worth buying.
local Deals = {}
ns.Deals = Deals

-- Order matters only for ties: the first type wins.
Deals.TYPES = { "easy", "disenchant", "resale", "stock", "craft", "arbitrage" }

-- Types whose goods turn into gold right away (vendor, disenchant materials):
-- profit per day is the whole profit, days to sell is 0.
Deals.IMMEDIATE = { easy = true, disenchant = true }

-- item = {
--   itemID, commodity = bool,
--   lots = { {qty, price (unit)}, ... } any order,
--   market = expected unit price on this house (already caution-adjusted; for new items the 2nd-3rd lot),
--   perDay = units sold per day or nil,
--   vendor = vendor sell price per unit,
--   de = disenchant value per unit (gross, materials at market) or nil,
--   stock = { buyBelow = copper or nil (nil = market), cap = copper or nil } or nil,
--   craft = value per unit as a reagent (already net) or nil,
--   other = { price = unit price on the other house, cut = its cut } or nil,
--   deposit = deposit per unit when reselling (0 if unknown),
-- }
-- opts = { cut, minProfit, maxDays (0 or nil = no limit), types = { [type] = true } or nil (all) }

local function sortedLots(lots)
    local t = {}
    for _, l in ipairs(lots) do
        if l.qty > 0 and l.price > 0 then t[#t + 1] = l end
    end
    table.sort(t, function(a, b) return a.price < b.price end)
    return t
end

-- Net value per unit for a type, or nil when the type does not apply.
-- nextPrice: unit price of the cheapest lot left after buying (resale only).
local function unitValue(kind, item, opts, nextPrice)
    if kind == "easy" then
        return item.vendor and item.vendor > 0 and item.vendor or nil
    elseif kind == "disenchant" then
        if item.commodity or not item.de or item.de <= 0 then return nil end
        return Money.AfterCut(item.de, opts.cut)
    elseif kind == "resale" then
        if not item.market or not item.perDay or item.perDay <= 0 then return nil end
        local sale = item.market
        if nextPrice and nextPrice < sale then sale = nextPrice end
        return Money.AfterCut(sale, opts.cut) - (item.deposit or 0)
    elseif kind == "stock" then
        if not item.stock or not item.market then return nil end
        return Money.AfterCut(item.market, opts.cut) - (item.deposit or 0)
    elseif kind == "craft" then
        return item.craft
    elseif kind == "arbitrage" then
        local o = item.other
        if not o or not o.price then return nil end
        return Money.AfterCut(o.price, o.cut) - (item.deposit or 0)
    end
end

-- Extra entry conditions besides "profit > 0".
local function allowedPrice(kind, item, opts, price)
    if kind == "stock" then
        local limit = item.stock.buyBelow or item.market
        if price > limit then return false end
        if item.stock.cap and price > item.stock.cap then return false end
    elseif kind == "arbitrage" then
        -- The gap must cover both houses' cuts.
        local o = item.other
        if o.price - price <= o.price * (opts.cut + o.cut) then return false end
    end
    return true
end

local function unitsLimit(kind, item, opts)
    if Deals.IMMEDIATE[kind] then return math.huge end
    if opts.maxDays and opts.maxDays > 0 then
        if not item.perDay or item.perDay <= 0 then return 0 end
        return math.floor(item.perDay * opts.maxDays)
    end
    return math.huge
end

local function finishRow(row, kind, item)
    row.type = kind
    row.itemID = item.itemID
    row.commodity = item.commodity
    if Deals.IMMEDIATE[kind] then
        row.days = 0
        row.perDay = row.profit
    elseif item.perDay and item.perDay > 0 then
        row.days = row.qty / item.perDay
        row.perDay = math.floor(row.profit / row.qty * math.min(row.qty, item.perDay) + 0.5)
    else
        row.perDay = 0
    end
    return row
end

-- Best amount to buy from the cheapest lots up: the prefix with the biggest total profit.
-- Resale value depends on the lot left after buying, so buying a cheap lot that "holds the price down"
-- can pay off even at a small loss on that lot: the walk goes on while the lot is below the upper value.
-- wholeLots: items cannot be bought partially.
local function bestPrefix(kind, item, opts, lots, wholeLots)
    local top = unitValue(kind, item, opts, nil)
    if not top then return nil end
    local limit = unitsLimit(kind, item, opts)
    local best
    local qty, cost = 0, 0
    for k, lot in ipairs(lots) do
        if qty >= limit or lot.price >= top or not allowedPrice(kind, item, opts, lot.price) then break end
        local take = math.min(lot.qty, limit - qty)
        if wholeLots and take < lot.qty then break end
        local nextPrice
        if take < lot.qty then nextPrice = lot.price else nextPrice = lots[k + 1] and lots[k + 1].price end
        local v = unitValue(kind, item, opts, nextPrice)
        qty = qty + take
        cost = cost + take * lot.price
        local profit = qty * v - cost
        if not best or profit > best.profit then
            best = { k = k, qty = qty, cost = cost, maxPrice = lot.price, value = v, profit = profit }
        end
    end
    if best and best.profit > 0 and best.profit >= opts.minProfit then return best end
end

-- Commodity: one row "buy N up to price X".
local function commodityRows(kind, item, opts, lots)
    local best = bestPrefix(kind, item, opts, lots, false)
    if not best then return {} end
    best.k = nil
    return { finishRow(best, kind, item) }
end

-- Items: one row per lot (each lot has its own auction), all sharing the prefix's value.
local function itemRows(kind, item, opts, lots)
    local best = bestPrefix(kind, item, opts, lots, true)
    if not best then return {} end
    local rows = {}
    for k = 1, best.k do
        local lot = lots[k]
        rows[k] = finishRow({
            qty = lot.qty, cost = lot.qty * lot.price, maxPrice = lot.price, value = best.value,
            profit = lot.qty * (best.value - lot.price), lot = lot,
        }, kind, item)
    end
    return rows
end

-- All rows of one type for one item.
function Deals.ForType(kind, item, opts)
    local lots = sortedLots(item.lots)
    if #lots == 0 then return {} end
    if item.commodity then return commodityRows(kind, item, opts, lots) end
    return itemRows(kind, item, opts, lots)
end

local function total(rows, field)
    local s = 0
    for _, r in ipairs(rows) do s = s + r[field] end
    return s
end

-- Rows for one item: only the type with the biggest total profit (one item = one type).
function Deals.Evaluate(item, opts)
    local bestRows, bestProfit = nil, 0
    for _, kind in ipairs(Deals.TYPES) do
        if not opts.types or opts.types[kind] then
            local rows = Deals.ForType(kind, item, opts)
            local p = total(rows, "profit")
            if #rows > 0 and p > bestProfit then
                bestRows, bestProfit = rows, p
            end
        end
    end
    return bestRows or {}
end

-- Sorting: "easy" money first (instant), then by profit per day, then by profit.
function Deals.Sort(rows)
    table.sort(rows, function(a, b)
        local ea, eb = a.type == "easy", b.type == "easy"
        if ea ~= eb then return ea end
        if a.perDay ~= b.perDay then return a.perDay > b.perDay end
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    return rows
end

-- Filter counters and the "buy everything" total. money: only rows that fit (nil = all).
function Deals.Summary(rows, money)
    local s = { counts = {}, cost = 0, profit = 0, n = 0 }
    for _, kind in ipairs(Deals.TYPES) do s.counts[kind] = 0 end
    for _, r in ipairs(rows) do
        s.counts[r.type] = s.counts[r.type] + 1
        if not money or r.cost <= money then
            s.n = s.n + 1
            s.cost = s.cost + r.cost
            s.profit = s.profit + r.profit
        end
    end
    return s
end

-- Reference price for a new item (fewer than ~10 scans): the 2nd-3rd cheapest lot. TZ: "Новый товар".
function Deals.NewItemReference(lots)
    local sorted = sortedLots(lots)
    if #sorted == 0 then return nil end
    local a = sorted[math.min(2, #sorted)].price
    local b = sorted[math.min(3, #sorted)].price
    return math.floor((a + b) / 2)
end
