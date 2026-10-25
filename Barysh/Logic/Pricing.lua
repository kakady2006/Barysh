local _, ns = ...

local Stats, Money = ns.Stats, ns.Money

local Pricing = {}
ns.Pricing = Pricing

Pricing.SCAN_SHARE = 0.15       -- cheapest share of units used for the scan price
Pricing.WINDOW_DAYS = 7         -- market price window
Pricing.RECENT_DAYS = 3         -- scans this fresh count twice
Pricing.RECENT_WEIGHT = 2
Pricing.NEW_ITEM_SCANS = 10     -- fewer scans than this -> "new, price forming"

Pricing.CAUTION_PERCENTILE = { normal = 0.5, careful = 0.35, bold = 0.65 }

local DAY = 24 * 60 * 60

-- Unit price at 1-based unit position pos in lots sorted by price.
local function unitPriceAt(sorted, pos)
    local acc = 0
    for _, lot in ipairs(sorted) do
        acc = acc + lot.qty
        if acc >= pos then return lot.price end
    end
end

-- Scan price: median unit price among the cheapest `share` of all units on the market.
-- lots = { {price = unit price in copper, qty = units}, ... }
function Pricing.ScanPrice(lots, share)
    share = share or Pricing.SCAN_SHARE
    local sorted, total = {}, 0
    for _, lot in ipairs(lots) do
        if lot.qty > 0 and lot.price > 0 then
            sorted[#sorted + 1] = lot
            total = total + lot.qty
        end
    end
    if total == 0 then return nil end
    table.sort(sorted, function(a, b) return a.price < b.price end)
    local n = math.max(1, math.ceil(total * share))
    if n % 2 == 1 then
        return unitPriceAt(sorted, (n + 1) / 2)
    end
    return math.floor((unitPriceAt(sorted, n / 2) + unitPriceAt(sorted, n / 2 + 1)) / 2)
end

-- Market price: weighted percentile of scan prices over the last WINDOW_DAYS,
-- scans from the last RECENT_DAYS weigh RECENT_WEIGHT. caution: normal | careful | bold.
-- scans = { {time = unix seconds, price = copper}, ... }
function Pricing.MarketPrice(scans, now, caution)
    local p = Pricing.CAUTION_PERCENTILE[caution or "normal"]
    assert(p, "unknown caution level")
    local items = {}
    for _, s in ipairs(scans) do
        local age = now - s.time
        if age >= 0 and age <= Pricing.WINDOW_DAYS * DAY and s.price then
            local w = age <= Pricing.RECENT_DAYS * DAY and Pricing.RECENT_WEIGHT or 1
            items[#items + 1] = { value = s.price, weight = w }
        end
    end
    local v = Stats.WeightedPercentile(items, p)
    return v and Money.Round(v)
end

function Pricing.IsNewItem(scanCount)
    return scanCount < Pricing.NEW_ITEM_SCANS
end
