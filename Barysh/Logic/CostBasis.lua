local _, ns = ...

-- Weighted average cost per item. book[itemID] = { q = units held, c = total cost in copper }.
local CostBasis = {}
ns.CostBasis = CostBasis

function CostBasis.Add(book, itemID, qty, cost)
    if qty <= 0 then return end
    local e = book[itemID]
    if not e then
        e = { q = 0, c = 0 }
        book[itemID] = e
    end
    e.q = e.q + qty
    e.c = e.c + cost
end

-- Average cost per unit, or nil if nothing is on the books.
function CostBasis.Average(book, itemID)
    local e = book[itemID]
    if not e or e.q <= 0 then return nil end
    return e.c / e.q
end

-- Takes units off the books (sold, used, disenchanted). Returns their cost.
-- Units the book never saw cost nothing.
function CostBasis.Remove(book, itemID, qty)
    local e = book[itemID]
    if not e or e.q <= 0 or qty <= 0 then return 0 end
    local n = math.min(qty, e.q)
    local cost = math.floor(e.c * n / e.q + 0.5)
    e.q = e.q - n
    e.c = e.c - cost
    if e.q <= 0 then book[itemID] = nil end
    return cost
end

-- Moves the cost of `qty` source units onto outputs ({ {itemID, qty, value}, ... }),
-- split by each output's market value (equal split if values are unknown).
-- Used for disenchanting: the item's cost goes to the materials.
function CostBasis.Transfer(book, fromItemID, qty, outputs)
    local cost = CostBasis.Remove(book, fromItemID, qty)
    if #outputs == 0 then return cost end
    local totalValue = 0
    for _, o in ipairs(outputs) do totalValue = totalValue + (o.value or 0) end
    local left = cost
    for i, o in ipairs(outputs) do
        local share
        if i == #outputs then
            share = left
        elseif totalValue > 0 then
            share = math.floor(cost * (o.value or 0) / totalValue + 0.5)
        else
            share = math.floor(cost / #outputs + 0.5)
        end
        left = left - share
        CostBasis.Add(book, o.itemID, o.qty, share)
    end
    return cost
end
