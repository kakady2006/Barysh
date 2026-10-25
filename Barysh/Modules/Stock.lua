local _, ns = ...

local Stock, Items, AH, CostBasis = ns.Stock, ns.Items, ns.AH, ns.CostBasis

-- Goods bought for future demand: invested, worth now, when to sell. TZ: "Склад".
-- What to hold comes from the "stock" list; holdings come from Modules/Inventory.lua.
local M = ns:NewModule("Stock", { group = "trade" })
ns.StockModule = M

-- Positions of the stock list: { itemID, qty, invested, worth, profit, days, below, streak, exit, note }
function M.Positions()
    local key = ns.Prices.DefaultKey()
    local cut = AH.Cut(key)
    local today = math.floor(ns.Now() / 86400)
    local out = {}
    for _, id in ipairs(ns.ItemLists.Ids("stock")) do
        local qty = Stock.Held(ns.db.chars, id)
        local s = ns.Prices.Item(id, key)
        local p = Stock.Position({
            qty = qty, avgCost = CostBasis.Average(ns.db.books, id), price = s.market or s.current,
            perDay = s.perDay, cut = cut,
        })
        p.itemID = id
        p.price = s.market or s.current
        p.avgCost = CostBasis.Average(ns.db.books, id)
        p.note = (ns.ItemLists.Entry("stock", id) or {}).note
        if qty > 0 then
            p.streak = Stock.TrackBelow(ns.db.stockBelow, id, p.below, today)
            p.exit = p.streak >= Stock.EXIT_DAYS
        else
            ns.db.stockBelow[id] = nil
            p.streak = 0
        end
        out[#out + 1] = p
    end
    table.sort(out, function(a, b)
        if a.exit ~= b.exit then return a.exit end
        return (a.worth or 0) > (b.worth or 0)
    end)
    return out, Stock.Totals(out)
end

-- Positions below cost for 3+ days ("Needs attention" on the overview).
function M.ExitCount()
    local n = 0
    for _, p in ipairs((M.Positions())) do
        if p.exit then n = n + 1 end
    end
    return n
end

-- "Exit" and "To selling": the item goes into the selling queue even though it is on the stock list.
function M.ToSelling(itemID)
    ns.db.sellMarked[itemID] = true
    ns.Print(ns.L.TO_SELLING:format(Items.ColoredName(itemID)))
end

function M:OnEnable() end
