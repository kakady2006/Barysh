local _, ns = ...

-- Auction lots of one item: { {qty =, price = unit price in copper, tl = time-left band}, ... }
-- Stored in SavedVariables as one compact string per item: "qty:price:tl,qty:price:tl".
local Lots = {}
ns.Lots = Lots

-- Time-left bands, same numbers as Enum.AuctionHouseTimeLeftBand.
Lots.TL_SHORT = 0     -- < 30 min
Lots.TL_MEDIUM = 1    -- 30 min - 2 h
Lots.TL_LONG = 2      -- 2 h - 12 h
Lots.TL_VERYLONG = 3  -- > 12 h

local function less(a, b)
    if a.price ~= b.price then return a.price < b.price end
    if a.qty ~= b.qty then return a.qty < b.qty end
    return a.tl < b.tl
end

function Lots.Sort(lots)
    table.sort(lots, less)
    return lots
end

-- Canonical string: equal lot sets always give equal strings.
function Lots.Encode(lots)
    Lots.Sort(lots)
    local parts = {}
    for i, l in ipairs(lots) do
        parts[i] = l.qty .. ":" .. l.price .. ":" .. l.tl
    end
    return table.concat(parts, ",")
end

function Lots.Decode(s)
    local lots = {}
    if not s or s == "" then return lots end
    for q, p, t in s:gmatch("(%d+):(%d+):(%d+)") do
        lots[#lots + 1] = { qty = tonumber(q), price = tonumber(p), tl = tonumber(t) }
    end
    return lots
end

-- Total units, cheapest unit price.
function Lots.Totals(lots)
    local qty, min = 0, nil
    for _, l in ipairs(lots) do
        qty = qty + l.qty
        if not min or l.price < min then min = l.price end
    end
    return qty, min
end

-- Seconds left (search results) -> band.
function Lots.BandFromSeconds(sec)
    if sec < 30 * 60 then return Lots.TL_SHORT end
    if sec < 2 * 3600 then return Lots.TL_MEDIUM end
    if sec <= 12 * 3600 then return Lots.TL_LONG end
    return Lots.TL_VERYLONG
end
