local _, ns = ...

local Pricing, Stats = ns.Pricing, ns.Stats

-- Per-item price history kept in the addon: a list of change points
-- { t = scan time, p = scan price, q = units on market, m = cheapest unit price }.
-- An item that left the market is recorded as q = 0.
-- Full-scan times are kept separately, so the price at every scan can be rebuilt.
local History = {}
ns.History = History

local DAY = 24 * 60 * 60

-- Appends a change point. Returns true if anything changed.
function History.Record(list, t, price, qty, min)
    local last = list[#list]
    if last and last.p == price and last.q == qty and last.m == min then
        return false
    end
    if not last and qty == 0 then
        return false
    end
    list[#list + 1] = { t = t, p = price, q = qty, m = min }
    return true
end

-- Drops points older than cutoff, keeping the last one before it as the baseline.
function History.Prune(list, cutoff)
    local firstKeep = 1
    for i = 1, #list do
        if list[i].t < cutoff then firstKeep = i else break end
    end
    if firstKeep > 1 then
        local n = #list
        for i = firstKeep, n do list[i - firstKeep + 1] = list[i] end
        for i = n - firstKeep + 2, n do list[i] = nil end
    end
    return list
end

function History.At(list, t)
    local found
    for _, e in ipairs(list) do
        if e.t <= t then found = e else break end
    end
    return found
end

-- Scan prices of this item at each full scan within the window: { {time, price}, ... }
function History.ScanPrices(list, scanTimes, now, windowDays)
    local from = now - (windowDays or Pricing.WINDOW_DAYS) * DAY
    local out = {}
    for _, t in ipairs(scanTimes) do
        if t >= from and t <= now then
            local e = History.At(list, t)
            if e and e.q > 0 and e.p then
                out[#out + 1] = { time = t, price = e.p, min = e.m }
            end
        end
    end
    return out
end

-- Everything the tooltip and deals need about one item.
function History.Summary(list, scanTimes, now, caution)
    local scans = History.ScanPrices(list, scanTimes, now)
    local last = list[#list]
    local s = {
        scans = #scans,
        market = Pricing.MarketPrice(scans, now, caution),
        current = last and last.q > 0 and last.p or nil,
        currentMin = last and last.q > 0 and last.m or nil,
        onMarket = last and last.q or 0,
        updated = last and last.t,
    }
    local mins, prices = {}, {}
    for i, sc in ipairs(scans) do
        mins[i] = sc.min
        prices[i] = sc.price
    end
    if #mins > 0 then
        local m = mins[1]
        for _, v in ipairs(mins) do if v < m then m = v end end
        s.min7 = m
        s.median7 = Stats.Median(prices)
    end
    s.isNew = Pricing.IsNewItem(s.scans)
    return s
end
