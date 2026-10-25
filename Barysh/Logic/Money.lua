local _, ns = ...

-- All money is integer copper.
local Money = {}
ns.Money = Money

Money.SILVER = 100
Money.GOLD = 10000

function Money.Split(copper)
    local sign = copper < 0 and -1 or 1
    copper = math.abs(copper)
    local g = math.floor(copper / Money.GOLD)
    local s = math.floor((copper % Money.GOLD) / Money.SILVER)
    local c = copper % Money.SILVER
    return sign * g, sign * s, sign * c
end

-- What the seller receives after the auction house cut, rounded down.
function Money.AfterCut(amount, cut)
    return math.floor(amount * (1 - cut))
end

function Money.Round(x)
    return math.floor(x + 0.5)
end
