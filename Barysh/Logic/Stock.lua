local _, ns = ...

local Money = ns.Money

-- Goods bought for future demand and the capital of all characters. TZ: "Склад", "Учёт и капитал".
local Stock = {}
ns.Stock = Stock

Stock.EXIT_DAYS = 3 -- below cost this many days in a row -> highlight and "Exit" button

-- One stock position. p = { qty, avgCost (or nil), price (market unit price or nil), perDay, cut }
function Stock.Position(p)
    local r = { qty = p.qty }
    r.invested = p.avgCost and math.floor(p.avgCost * p.qty + 0.5) or 0
    r.worth = p.price and Money.AfterCut(p.price * p.qty, p.cut) or nil
    if r.worth and p.avgCost then r.profit = r.worth - r.invested end
    if p.perDay and p.perDay > 0 then r.days = p.qty / p.perDay end
    r.below = p.avgCost ~= nil and p.price ~= nil and Money.AfterCut(p.price, p.cut) < p.avgCost
    return r
end

-- Tracks how many days in a row a position stays below cost.
-- state[itemID] = first day (day number) it was seen below; returns the streak in days (1 = today).
function Stock.TrackBelow(state, itemID, below, day)
    if not below then
        state[itemID] = nil
        return 0
    end
    state[itemID] = state[itemID] or day
    return day - state[itemID] + 1
end

function Stock.Totals(positions)
    local t = { invested = 0, worth = 0, profit = 0 }
    for _, r in ipairs(positions) do
        t.invested = t.invested + r.invested
        t.worth = t.worth + (r.worth or 0)
        t.profit = t.profit + (r.profit or 0)
    end
    return t
end

-- Capital over all characters. chars[name] = { money, bags = {[id]=n}, bank, mail, auctions, mailMoney }
-- valueOf(itemID) -> unit value after cut, or nil (then the item counts as 0).
Stock.PLACES = { "bags", "bank", "mail", "auctions" }

function Stock.Capital(chars, valueOf)
    local c = { gold = 0, total = 0, perChar = {} }
    for _, place in ipairs(Stock.PLACES) do c[place] = 0 end
    local cache = {}
    local function value(id)
        local v = cache[id]
        if v == nil then
            v = valueOf(id) or 0
            cache[id] = v
        end
        return v
    end
    for name, ch in pairs(chars) do
        local own = (ch.money or 0) + (ch.mailMoney or 0)
        c.gold = c.gold + own
        for _, place in ipairs(Stock.PLACES) do
            for id, n in pairs(ch[place] or {}) do
                local v = value(id) * n
                c[place] = c[place] + v
                own = own + v
            end
        end
        c.perChar[name] = own
        c.total = c.total + own
    end
    return c
end

-- Units of one item over all characters and places.
function Stock.Held(chars, itemID)
    local n = 0
    for _, ch in pairs(chars) do
        for _, place in ipairs(Stock.PLACES) do
            local p = ch[place]
            if p and p[itemID] then n = n + p[itemID] end
        end
    end
    return n
end
