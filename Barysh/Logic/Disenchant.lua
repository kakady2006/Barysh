local _, ns = ...

local Data = ns.DisenchantData

local Disenchant = {}
ns.Disenchant = Disenchant

Disenchant.CLASS_WEAPON = 2
Disenchant.CLASS_ARMOR = 4
Disenchant.QUALITY_UNCOMMON = 2
Disenchant.QUALITY_RARE = 3
Disenchant.QUALITY_EPIC = 4

-- itemID is optional: with it, the items that never disenchant (DisenchantData.never) are excluded.
function Disenchant.IsDisenchantable(classID, quality, itemID)
    if itemID and Data.never[itemID] then return false end
    return (classID == Disenchant.CLASS_WEAPON or classID == Disenchant.CLASS_ARMOR)
        and quality ~= nil and quality >= Disenchant.QUALITY_UNCOMMON and quality <= Disenchant.QUALITY_EPIC
end

-- Weapon or armour by class alone (a cheap first filter before the full item data).
function Disenchant.IsGearClass(classID)
    return classID == Disenchant.CLASS_WEAPON or classID == Disenchant.CLASS_ARMOR
end

local function findRow(rows, ilvl)
    if rows[1].minIlvl and ilvl < rows[1].minIlvl then return nil end
    for _, row in ipairs(rows) do
        if ilvl <= row.maxIlvl then return row end
    end
end

-- Possible results: { {chance =, itemID =, min =, max =}, ... } or nil.
function Disenchant.Outcomes(classID, quality, ilvl)
    if not Disenchant.IsDisenchantable(classID, quality) or not ilvl or ilvl < 1 then return nil end
    local out = {}
    if quality == Disenchant.QUALITY_UNCOMMON then
        local row = findRow(Data.uncommon, ilvl)
        if not row then return nil end
        local weapon = classID == Disenchant.CLASS_WEAPON
        local dustChance, essChance = 0.75, 0.20
        if row.first then dustChance, essChance = 0.80, 0.20 end
        if weapon then dustChance, essChance = essChance, dustChance end
        out[#out + 1] = { chance = dustChance, itemID = row.dust[1], min = row.dust[2], max = row.dust[3] }
        out[#out + 1] = { chance = essChance, itemID = row.essence[1], min = row.essence[2], max = row.essence[3] }
        if row.shard then
            out[#out + 1] = { chance = 0.05, itemID = row.shard[1], min = row.shard[2], max = row.shard[3] }
        end
        return out
    end
    local rows = quality == Disenchant.QUALITY_RARE and Data.rare or Data.epic
    local row = findRow(rows, ilvl)
    if not row then return nil end
    for _, o in ipairs(row.outcomes) do
        out[#out + 1] = { chance = o[1], itemID = o[2], min = o[3], max = o[4] }
    end
    return out
end

-- Expected value V = sum(chance * average count * material price).
-- priceOf(itemID) -> copper or nil. Returns value, breakdown, complete (all prices known).
function Disenchant.Value(outcomes, priceOf)
    if not outcomes then return nil end
    local value, complete, breakdown = 0, true, {}
    for i, o in ipairs(outcomes) do
        local price = priceOf(o.itemID)
        local avg = (o.min + o.max) / 2
        local v = price and o.chance * avg * price or 0
        if not price then complete = false end
        value = value + v
        breakdown[i] = { chance = o.chance, itemID = o.itemID, min = o.min, max = o.max, price = price, value = v }
    end
    return math.floor(value + 0.5), breakdown, complete
end

-- Expected count of one material from one disenchant (0 when it never drops).
function Disenchant.Yield(outcomes, materialID)
    local n = 0
    for _, o in ipairs(outcomes or {}) do
        if o.itemID == materialID then n = n + o.chance * (o.min + o.max) / 2 end
    end
    return n
end

-- Items on the auction that disenchant into one material, cheapest material first. One row per item,
-- at the price of its cheapest lot (unit price).
-- candidates = { { itemID, outcomes, lots = { {qty, price (unit)} }, other = value of the other
--                  materials per disenchant, already after the cut } }
-- matPrice = what one unit of the material costs on the auction now (nil = unknown).
-- Each row: itemID, price (cheapest unit price), count (units listed), yield (material per item),
--   perUnit = cost of one material after selling the rest, profit = against buying the material
--   (nil when matPrice is unknown).
function Disenchant.ForMaterial(candidates, materialID, matPrice)
    local rows = {}
    for _, c in ipairs(candidates) do
        local y = Disenchant.Yield(c.outcomes, materialID)
        local price, count = nil, 0
        for _, l in ipairs(c.lots or {}) do
            if l.qty > 0 and l.price > 0 then
                count = count + l.qty
                if not price or l.price < price then price = l.price end
            end
        end
        if y > 0 and price then
            local other = c.other or 0
            local row = {
                itemID = c.itemID, price = price, count = count, yield = y,
                perUnit = math.floor((price - other) / y + 0.5),
            }
            if matPrice then row.profit = math.floor(y * matPrice + other - price + 0.5) end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if a.perUnit ~= b.perUnit then return a.perUnit < b.perUnit end
        return a.itemID < b.itemID
    end)
    return rows
end
