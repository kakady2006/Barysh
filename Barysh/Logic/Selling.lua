local _, ns = ...

local Money = ns.Money

-- Posting price, lot sizes and duration; state of own lots. TZ: "Продажи", docs/decisions.md items 5-6.
local Selling = {}
ns.Selling = Selling

Selling.SHORT = "short"   -- 8 hours (VERIFY: durations live in Adapters/AuctionAPI.lua)
Selling.LONG = "long"     -- 24 hours
Selling.SHORT_HOURS = 8

-- Unit price to post at: the cheapest price on the market, no undercutting by a copper,
-- but not below cost. Without lots on the market: the market price.
-- marketLots: lots of other sellers. Returns price, warning ("below_cost" | nil) or nil, "no_price".
function Selling.PostPrice(marketLots, cost, market)
    local min
    for _, l in ipairs(marketLots) do
        if l.qty > 0 and l.price > 0 and (not min or l.price < min) then min = l.price end
    end
    local price = min or market
    if not price then return nil, "no_price" end
    if cost and price < cost then
        return math.ceil(cost), "below_cost"
    end
    return price
end

-- Units cheaper than price (they sell before ours) and units at the same price.
function Selling.Ahead(marketLots, price)
    local cheaper, same = 0, 0
    for _, l in ipairs(marketLots) do
        if l.price < price then cheaper = cheaper + l.qty elseif l.price == price then same = same + l.qty end
    end
    return cheaper, same
end

-- 8 hours, or 24 for slow and expensive goods: when the market will not take
-- everything ahead of us plus our lot within 8 hours, or the lot is worth more than `expensive`.
function Selling.Duration(price, qty, ahead, perDay, expensive)
    if expensive and expensive > 0 and price * qty >= expensive then return Selling.LONG end
    if not perDay or perDay <= 0 then return Selling.LONG end
    local hours = (ahead + qty) / perDay * 24
    return hours > Selling.SHORT_HOURS and Selling.LONG or Selling.SHORT
end

-- Lot sizes. Commodities: one lot of everything (buyers take any amount), or stacks of `stack`
-- when the option is on. Items: one per lot.
function Selling.Split(qty, commodity, stack)
    local out = {}
    if not commodity then
        for i = 1, qty do out[i] = 1 end
        return out
    end
    if not stack or stack <= 0 or stack >= qty then return { qty } end
    local left = qty
    while left > 0 do
        out[#out + 1] = math.min(stack, left)
        left = left - stack
    end
    return out
end

-- State of an own lot. Units ahead of it vs daily sales:
-- fewer than a day of sales -> "ok" (bought first), more -> "undercut" (cancel and repost).
-- marketLots must not contain the lot itself.
function Selling.LotState(myPrice, marketLots, perDay)
    local cheaper = Selling.Ahead(marketLots, myPrice)
    local state
    if cheaper == 0 then
        state = "ok"
    elseif perDay and perDay > 0 and cheaper < perDay then
        state = "ok"
    else
        state = "undercut"
    end
    return { cheaper = cheaper, state = state }
end

-- Removes one lot equal to mine (qty and unit price) from the market lots: the scan does not
-- know owners, so our own lot is in there too.
function Selling.WithoutOwn(marketLots, qty, price)
    local out, removed = {}, false
    for _, l in ipairs(marketLots) do
        if not removed and l.qty == qty and l.price == price then
            removed = true
        else
            out[#out + 1] = l
        end
    end
    return out
end

-- Totals for the queue: deposit for everything and revenue after the cut.
-- queue = { {price (unit), qty, deposit}, ... }
function Selling.Totals(queue, cut)
    local t = { deposit = 0, revenue = 0, n = #queue }
    for _, e in ipairs(queue) do
        t.deposit = t.deposit + (e.deposit or 0)
        t.revenue = t.revenue + Money.AfterCut(e.price * e.qty, cut)
    end
    return t
end
