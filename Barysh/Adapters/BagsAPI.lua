local _, ns = ...

local Bags = {}
ns.Bags = Bags

-- VERIFY: bag numbering on Forever (backpack 0, bags 1-4; no reagent bag expected).
Bags.FIRST, Bags.LAST = 0, NUM_BAG_SLOTS or 4

-- Calls fn(bag, slot, info) for every filled slot. info = C_Container item info table.
function Bags.Each(fn)
    for bag = Bags.FIRST, Bags.LAST do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then fn(bag, slot, info) end
        end
    end
end

function Bags.InEquipmentSet(bag, slot)
    if C_Container.GetContainerItemEquipmentSetInfo then
        return C_Container.GetContainerItemEquipmentSetInfo(bag, slot) and true or false
    end
    return false
end

-- Count of an item across the bags.
function Bags.Count(itemID)
    local n = 0
    Bags.Each(function(_, _, info)
        if info.itemID == itemID then n = n + (info.stackCount or 1) end
    end)
    return n
end
