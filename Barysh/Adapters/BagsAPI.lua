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

-- VERIFY: bank containers on Forever. Classic: -1 (main bank) and bags NUM_BAG_SLOTS+1 .. +NUM_BANKBAGSLOTS.
function Bags.BankContainers()
    local list = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = b end
    return list
end

-- { [itemID] = count } over the given containers.
function Bags.Counts(containers)
    local out = {}
    for _, bag in ipairs(containers) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1) end
        end
    end
    return out
end

function Bags.BagContainers()
    local list = {}
    for b = Bags.FIRST, Bags.LAST do list[#list + 1] = b end
    return list
end

-- First bag slot holding the item, or nil.
function Bags.Find(itemID)
    for bag = Bags.FIRST, Bags.LAST do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then return bag, slot, info end
        end
    end
end

-- Sells (merchant open) or uses the item in a slot.
function Bags.Use(bag, slot)
    C_Container.UseContainerItem(bag, slot)
end
