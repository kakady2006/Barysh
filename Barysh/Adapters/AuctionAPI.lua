local _, ns = ...

-- Thin layer over C_AuctionHouse. Everything that may differ on the Forever client lives here.
local AH = {}
ns.AH = AH

function AH.Available()
    return C_AuctionHouse ~= nil and C_AuctionHouse.ReplicateItems ~= nil
end

-- Full scan --------------------------------------------------------------------------

function AH.RequestReplicate()
    return pcall(C_AuctionHouse.ReplicateItems)
end

function AH.NumReplicate()
    return C_AuctionHouse.GetNumReplicateItems() or 0
end

-- Row i (0-based, VERIFY). Returns itemID, count, buyout (whole lot), time-left band, hasAllInfo.
-- VERIFY: buyoutPrice is assumed to be for the whole lot, as on retail.
function AH.ReadReplicate(i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(i)
    if not itemID then return nil end
    local tl = C_AuctionHouse.GetReplicateItemTimeLeft and C_AuctionHouse.GetReplicateItemTimeLeft(i)
    return itemID, count or 1, buyout or 0, tl or 3, hasAllInfo
end

-- All return values of a row, as text, for /barysh probe.
function AH.RawReplicate(i)
    local values = { C_AuctionHouse.GetReplicateItemInfo(i) }
    local parts = {}
    for k = 1, 18 do parts[k] = tostring(values[k]) end
    local tl = C_AuctionHouse.GetReplicateItemTimeLeft and C_AuctionHouse.GetReplicateItemTimeLeft(i)
    return table.concat(parts, " | ") .. " || tl=" .. tostring(tl)
end

-- Item search (quick scan, buying) -------------------------------------------------------

function AH.CanSearch()
    if C_AuctionHouse.IsThrottledMessageSystemReady then
        return C_AuctionHouse.IsThrottledMessageSystemReady()
    end
    return true
end

function AH.Search(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    C_AuctionHouse.SendSearchQuery(key, sorts, true)
    return key
end

-- Lots from the last commodity search: { {qty, price, tl, auctionID}, ... }, complete
function AH.CommodityResults(itemID)
    local lots = {}
    local n = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) or 0
    for i = 1, n do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 then
            lots[#lots + 1] = {
                qty = r.quantity, price = r.unitPrice, auctionID = r.auctionID,
                tl = ns.Lots.BandFromSeconds(r.timeLeftSeconds or 0),
            }
        end
    end
    return lots, C_AuctionHouse.HasFullCommoditySearchResults(itemID)
end

function AH.ItemResults(itemKey)
    local lots = {}
    local n = C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) or 0
    for i = 1, n do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local qty = r.quantity or 1
            lots[#lots + 1] = {
                qty = qty, price = math.floor(r.buyoutAmount / qty), auctionID = r.auctionID,
                tl = r.timeLeft or 3,
            }
        end
    end
    return lots, C_AuctionHouse.HasFullItemSearchResults(itemKey)
end

-- Which auction house the player stands at -----------------------------------------------

-- VERIFY: map IDs of the neutral auction house zones on Forever.
-- Classic uiMapIDs and their modern equivalents: Tanaris (Gadgetzan), Stranglethorn / Cape (Booty Bay),
-- Winterspring (Everlook).
AH.NEUTRAL_MAPS = {
    [1446] = true, [1434] = true, [1452] = true,
    [71] = true, [210] = true, [224] = true, [83] = true,
}

function AH.IsNeutralZone()
    if not C_Map or not C_Map.GetBestMapForUnit then return false end
    local mapID = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not mapID or mapID == 0 then return false end
        if AH.NEUTRAL_MAPS[mapID] then return true end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return false
end

function AH.FactionKey()
    return (GetRealmName() or "?") .. "|" .. (UnitFactionGroup("player") or "Neutral")
end

function AH.CurrentKey()
    if AH.IsNeutralZone() then
        return (GetRealmName() or "?") .. "|Neutral"
    end
    return AH.FactionKey()
end

function AH.IsNeutralKey(key)
    return key and key:sub(-8) == "|Neutral"
end

function AH.Cut(key)
    return AH.IsNeutralKey(key) and ns.const.cutNeutral or ns.const.cutFaction
end
