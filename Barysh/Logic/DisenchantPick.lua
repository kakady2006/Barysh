local _, ns = ...

local Disenchant = ns.Disenchant

-- Chooses which bag item the disenchant button works on next.
local DisenchantPick = {}
ns.DisenchantPick = DisenchantPick

-- item = { bag, slot, itemID, quality, classID, ilvl, inSet, locked, bound }
-- rules = {
--   quality = "green" | "greenblue",
--   exclude = { [itemID] = true },
--   skipBetterToSell = bool,
--   deValue = function(item) -> copper or nil,
--   sellValue = function(item) -> copper after cut or nil,
-- }
function DisenchantPick.IsCandidate(item, rules)
    if item.locked or item.inSet then return false end
    if not Disenchant.IsDisenchantable(item.classID, item.quality) then return false end
    local maxQuality = rules.quality == "greenblue" and Disenchant.QUALITY_RARE or Disenchant.QUALITY_UNCOMMON
    if item.quality > maxQuality then return false end
    if rules.exclude and rules.exclude[item.itemID] then return false end
    if rules.skipBetterToSell and rules.deValue and rules.sellValue then
        local de, sell = rules.deValue(item), rules.sellValue(item)
        -- Bound items cannot be sold on the auction house.
        if de and sell and not item.bound and sell > de then return false end
    end
    return true
end

-- items in bag order. Returns the next candidate and how many candidates there are.
function DisenchantPick.Next(items, rules)
    local first, count = nil, 0
    for _, item in ipairs(items) do
        if DisenchantPick.IsCandidate(item, rules) then
            count = count + 1
            first = first or item
        end
    end
    return first, count
end
