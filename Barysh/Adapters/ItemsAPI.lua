local _, ns = ...

-- Item info from the client. Names come from the client language; we store only item IDs.
local Items = {}
ns.Items = Items

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Returns a table or nil if the client has not loaded the item yet.
function Items.Info(item)
    local name, link, quality, ilvl, minLevel, _, _, stack, equipLoc, texture, sellPrice, classID, subclassID, bindType =
        GetInfo(item)
    if not name then return nil end
    return {
        name = name, link = link, quality = quality, ilvl = ilvl, minLevel = minLevel,
        stack = stack, equipLoc = equipLoc, texture = texture, sellPrice = sellPrice or 0,
        classID = classID, subclassID = subclassID, bindType = bindType,
    }
end

function Items.ID(item)
    if type(item) == "number" then return item end
    if type(item) == "string" then
        local id = item:match("item:(%d+)")
        if id then return tonumber(id) end
        return (GetInstant(item))
    end
end

-- Item level of a concrete link (random suffixes and upgrades), falling back to the base level.
function Items.Level(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local lvl = C_Item.GetDetailedItemLevelInfo(link)
        if lvl then return lvl end
    end
    local info = Items.Info(link)
    return info and info.ilvl
end

function Items.Name(itemID)
    local info = Items.Info(itemID)
    return info and info.name
end

-- VERIFY: whether an item is a commodity (bought by quantity). The auction house decides this per
-- item; until the client tells (search event type), stackable items are treated as commodities.
function Items.IsCommodity(itemID)
    local known = ns.db and ns.db.commodity and ns.db.commodity[itemID]
    if known ~= nil then return known end
    local info = Items.Info(itemID)
    return info ~= nil and (info.stack or 1) > 1
end

-- Remembers what the client said about an item (search results come as commodity or item events).
function Items.SetCommodity(itemID, isCommodity)
    if not ns.db then return end
    ns.db.commodity = ns.db.commodity or {}
    ns.db.commodity[itemID] = isCommodity and true or false
end

function Items.Texture(itemID)
    local info = Items.Info(itemID)
    if info then return info.texture end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
end

-- Name colored by quality, falling back to "#id" while the client loads the item.
function Items.ColoredName(itemID)
    local info = Items.Info(itemID)
    if not info then return "#" .. tostring(itemID) end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
    if c and c.hex then return c.hex .. info.name .. "|r" end
    return info.name
end
