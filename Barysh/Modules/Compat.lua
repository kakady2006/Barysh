local _, ns = ...

-- Earlier versions switched off price lines of Mastercraft, Auctionator and Bagnon in item tooltips and
-- kept the originals in BaryshDB.compat. Now Barysh shows its lines only with Shift and leaves other
-- addons alone: this puts back whatever is still stored, then forgets it.
local Compat = {}
ns.Compat = Compat

local SETTERS = {
    ["Mastercraft.lootTooltip"] = function(v) MastercraftDB.settings.lootTooltip = v end,
    ["Mastercraft.tipPrice"] = function(v) MastercraftDB.settings.tipPrice = v end,
    ["Mastercraft.tipDisenchant"] = function(v) MastercraftDB.settings.tipDisenchant = v end,
    ["Auctionator.AUCTION_TOOLTIPS"] = function(v) Auctionator.Config.Set(Auctionator.Config.Options.AUCTION_TOOLTIPS, v) end,
    ["Auctionator.VENDOR_TOOLTIPS"] = function(v) Auctionator.Config.Set(Auctionator.Config.Options.VENDOR_TOOLTIPS, v) end,
    ["Bagnon.countItems"] = function(v) Bagnon_Sets.countItems = v end,
}

function Compat.Restore()
    local store = ns.db and ns.db.compat
    if type(store) ~= "table" then return end
    for key, v in pairs(store) do
        local set = SETTERS[key]
        -- an addon that is not loaded yet keeps its entry until it is
        if not set or pcall(set, v) then store[key] = nil end
    end
    if next(store) == nil then ns.db.compat = nil end
end

ns.RegisterEvent(Compat, "PLAYER_LOGIN", function()
    -- other addons finish their own setup at login
    C_Timer.After(5, function() ns.Safe(Compat.Restore) end)
end)
