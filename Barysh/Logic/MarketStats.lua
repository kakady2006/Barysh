local _, ns = ...

local History = ns.History

-- Numbers for the "Market" tab and market alerts. TZ: "Вкладка «Рынок»", "Оповещения".
local MarketStats = {}
ns.MarketStats = MarketStats

local DAY = 24 * 60 * 60

MarketStats.DUMPER_GAP = 0.8      -- cheapest lot below 80% of the next price level
MarketStats.DUMPER_SHARE = 0.1    -- and holding at most 10% of the units
MarketStats.FLOOD_RATIO = 2       -- units on the market doubled in 24 h
MarketStats.FLOOD_MIN_UNITS = 20
MarketStats.DROP_SHARE = 0.3      -- price fell 30% or more in 24 h
MarketStats.DROP_MIN_UNITS = 50   -- "on a big volume"

-- Market depth by price level: { {price, units, cum, hours}, ... }; hours = time to sell out
-- everything up to and including this level at the current sales speed (nil if unknown).
function MarketStats.Depth(lots, perDay, maxLevels)
    local byPrice = {}
    for _, l in ipairs(lots) do byPrice[l.price] = (byPrice[l.price] or 0) + l.qty end
    local prices = {}
    for p in pairs(byPrice) do prices[#prices + 1] = p end
    table.sort(prices)
    local out, cum = {}, 0
    for i, p in ipairs(prices) do
        if maxLevels and i > maxLevels then break end
        cum = cum + byPrice[p]
        out[i] = { price = p, units = byPrice[p], cum = cum, hours = perDay and perDay > 0 and cum / perDay * 24 or nil }
    end
    return out
end

-- How long until everything cheaper than `price` is bought. Hours or nil.
function MarketStats.HoursBelow(lots, price, perDay)
    if not perDay or perDay <= 0 then return nil end
    local units = 0
    for _, l in ipairs(lots) do
        if l.price < price then units = units + l.qty end
    end
    return units / perDay * 24
end

-- "dumper": one cheap small lot under the market; "flood": units on the market jumped.
-- hist: price history of the item (Logic/History.lua).
function MarketStats.Verdicts(lots, hist, now)
    local out = {}
    local depth = MarketStats.Depth(lots)
    local total = depth[#depth] and depth[#depth].cum or 0
    if #depth >= 2 then
        local first, second = depth[1], depth[2]
        if first.price < second.price * MarketStats.DUMPER_GAP and first.units <= total * MarketStats.DUMPER_SHARE then
            out.dumper = { price = first.price, units = first.units }
        end
    end
    if hist and #hist > 0 then
        local before = History.At(hist, now - DAY)
        if before and before.q > 0 and total >= before.q * MarketStats.FLOOD_RATIO
            and total - before.q >= MarketStats.FLOOD_MIN_UNITS then
            out.flood = { before = before.q, now = total }
        end
    end
    return out
end

-- Change of the scan price over `seconds`: fraction (-0.25 = fell by a quarter) or nil.
function MarketStats.Change(hist, now, seconds)
    local last = hist[#hist]
    local before = History.At(hist, now - seconds)
    if not last or not before or not last.p or not before.p or before.p == 0 or last.q == 0 then return nil end
    return (last.p - before.p) / before.p
end

-- A sharp drop on a big volume (alert).
function MarketStats.IsCrash(hist, now)
    local last = hist[#hist]
    if not last or (last.q or 0) < MarketStats.DROP_MIN_UNITS then return false end
    local ch = MarketStats.Change(hist, now, DAY)
    return ch ~= nil and ch <= -MarketStats.DROP_SHARE
end

-- Biggest movers over 24 h. hists = { [itemID] = hist }. Returns up, down: { {itemID, change, price}, ... }
function MarketStats.Movers(hists, now, n, minUnits)
    local all = {}
    for id, hist in pairs(hists) do
        local last = hist[#hist]
        if last and (last.q or 0) >= (minUnits or 1) then
            local ch = MarketStats.Change(hist, now, DAY)
            if ch and ch ~= 0 then all[#all + 1] = { itemID = id, change = ch, price = last.p } end
        end
    end
    table.sort(all, function(a, b)
        if a.change ~= b.change then return a.change > b.change end
        return a.itemID < b.itemID
    end)
    local up, down = {}, {}
    for i = 1, math.min(n, #all) do
        if all[i].change > 0 then up[#up + 1] = all[i] end
    end
    for i = #all, math.max(1, #all - n + 1), -1 do
        if all[i].change < 0 then down[#down + 1] = all[i] end
    end
    return up, down
end

-- Points for the chart: `buckets` equal slices of [from, to]; each takes the last known
-- scan price and cheapest price. { {t, p, m, q}, ... } (nil fields when unknown).
function MarketStats.Series(hist, from, to, buckets)
    local out = {}
    local step = (to - from) / buckets
    for i = 1, buckets do
        local t = from + step * i
        local e = History.At(hist, t)
        if e and e.q > 0 then
            out[i] = { t = t, p = e.p, m = e.m, q = e.q }
        else
            out[i] = { t = t }
        end
    end
    return out
end

-- Units sold per day slices from velocity buckets { [day] = units }: last `days` days, oldest first.
function MarketStats.SalesSeries(days, now, n)
    local today = math.floor(now / DAY)
    local out = {}
    for i = n - 1, 0, -1 do out[#out + 1] = days[today - i] or 0 end
    return out
end
