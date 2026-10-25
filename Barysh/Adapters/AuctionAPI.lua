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

function AH.NeutralKey()
    return (GetRealmName() or "?") .. "|Neutral"
end

-- The other house for arbitrage: faction <-> neutral.
function AH.OtherKey(key)
    if AH.IsNeutralKey(key) then return AH.FactionKey() end
    return AH.NeutralKey()
end

-- VERIFY: deposit on Forever. Estimate before the client can tell (CalculateItemDeposit needs the item
-- in bags): a share of the vendor price per unit for an 8-hour lot, as in Classic.
AH.DEPOSIT_RATE = 0.15
function AH.DepositEstimate(vendorPrice, key)
    local rate = AH.DEPOSIT_RATE * (AH.IsNeutralKey(key) and 5 or 1)
    return math.floor((vendorPrice or 0) * rate)
end

-- Buying ------------------------------------------------------------------------------------
-- Commodities: StartCommoditiesPurchase (needs a click) -> COMMODITY_PRICE_UPDATED -> Confirm.
-- Items: PlaceBid(auctionID, buyout) (needs a click) with an auctionID from an item search.

function AH.StartCommodityPurchase(itemID, qty)
    C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)
end

function AH.ConfirmCommodityPurchase(itemID, qty)
    C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, qty)
end

function AH.CancelCommodityPurchase()
    if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
end

function AH.BuyItem(auctionID, buyout)
    C_AuctionHouse.PlaceBid(auctionID, buyout)
end

-- Posting ------------------------------------------------------------------------------------

-- VERIFY: auction durations on Forever. Retail: 1 = 12 h, 2 = 24 h, 3 = 48 h; auxForever saw 2/8/24 h.
-- Barysh posts "short" (8 h per TZ) or "long" (24 h).
AH.DURATION = { short = 2, long = 3 }
AH.DURATION_HOURS = { [1] = 2, [2] = 8, [3] = 24 }

-- VERIFY: retail silently drops commodity posts with copper in the unit price.
-- auxForever reports copper values work on Forever; SupportsCopperValues() tells for sure.
function AH.RoundPostPrice(price)
    if C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues() then return price end
    return math.max(100, math.floor(price / 100) * 100)
end

function AH.Location(bag, slot)
    return ItemLocation:CreateFromBagAndSlot(bag, slot)
end

-- true = commodity (bought by quantity), false = item, nil = unknown.
function AH.IsCommodityLocation(loc)
    if not C_AuctionHouse.GetItemCommodityStatus then return nil end
    local status = C_AuctionHouse.GetItemCommodityStatus(loc)
    if status == 2 then return true elseif status == 1 then return false end
end

function AH.Deposit(loc, itemID, commodity, durationKey, qty)
    local d = AH.DURATION[durationKey]
    local ok, v
    if commodity then
        ok, v = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, d, qty)
    else
        ok, v = pcall(C_AuctionHouse.CalculateItemDeposit, loc, d, qty)
    end
    return ok and v or nil
end

-- Returns needsConfirmation. Both calls need a click.
function AH.Post(loc, commodity, durationKey, qty, unitPrice)
    local d = AH.DURATION[durationKey]
    if commodity then
        return C_AuctionHouse.PostCommodity(loc, d, qty, unitPrice)
    end
    return C_AuctionHouse.PostItem(loc, d, qty, nil, unitPrice * qty)
end

function AH.ConfirmPost(loc, commodity, durationKey, qty, unitPrice)
    local d = AH.DURATION[durationKey]
    if commodity then
        if C_AuctionHouse.ConfirmPostCommodity then return C_AuctionHouse.ConfirmPostCommodity(loc, d, qty, unitPrice) end
    elseif C_AuctionHouse.ConfirmPostItem then
        return C_AuctionHouse.ConfirmPostItem(loc, d, qty, nil, unitPrice * qty)
    end
end

-- Own auctions -------------------------------------------------------------------------------

function AH.QueryOwned()
    if C_AuctionHouse.QueryOwnedAuctions then C_AuctionHouse.QueryOwnedAuctions({}) end
end

-- { {auctionID, itemID, link, qty, price (unit), timeLeft, sold}, ... }
function AH.Owned()
    local out = {}
    if not C_AuctionHouse.GetNumOwnedAuctions then return out end
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if a and a.itemKey then
            local qty = a.quantity or 1
            out[#out + 1] = {
                auctionID = a.auctionID, itemID = a.itemKey.itemID, link = a.itemLink, qty = qty,
                price = a.buyoutAmount and math.floor(a.buyoutAmount / qty) or nil,
                timeLeft = a.timeLeftSeconds, sold = a.status == 1,
            }
        end
    end
    return out
end

function AH.CancelCost(auctionID)
    if C_AuctionHouse.GetCancelCost then return C_AuctionHouse.GetCancelCost(auctionID) end
end

function AH.Cancel(auctionID)
    C_AuctionHouse.CancelAuction(auctionID)
end
