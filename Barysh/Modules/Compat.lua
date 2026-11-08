local _, ns = ...

local L = ns.L

-- Other addons that put the same lines into item tooltips. Each line is kept by one addon only:
--   Barysh       auction price, usual price, disenchant value and outcomes, cost, best use;
--   Mastercraft  crafted by, recipe it teaches, used in, guides, owned on the account;
--   the game     vendor sell price (Barysh adds it when the game does not, see Modules/Tooltip.lua).
-- Their settings are switched off while this module is on and Barysh has its own prices, and put back
-- as they were when the module is turned off. Originals live in BaryshDB.compat.
local M = ns:NewModule("Compat", { group = "core" })

-- Each rule: addon (loaded check), key (unique), get() -> value or nil when not available, set(v), off value.
local function mastercraft(key)
    return {
        addon = "Mastercraft",
        key = "Mastercraft." .. key,
        get = function()
            local s = type(MastercraftDB) == "table" and MastercraftDB.settings
            if type(s) ~= "table" then return nil end
            -- Mastercraft treats a missing value as on
            return s[key] ~= false
        end,
        set = function(v) MastercraftDB.settings[key] = v end,
        off = false,
    }
end

local function auctionator(option)
    return {
        addon = "Auctionator",
        key = "Auctionator." .. option,
        get = function()
            local cfg = Auctionator and Auctionator.Config
            local name = cfg and cfg.Options and cfg.Options[option]
            if not (name and cfg.Get and cfg.Set) or AUCTIONATOR_CONFIG == nil then return nil end
            return cfg.Get(name) and true or false
        end,
        set = function(v) Auctionator.Config.Set(Auctionator.Config.Options[option], v) end,
        off = false,
    }
end

M.RULES = {
    mastercraft("lootTooltip"),   -- vendor / disenchant / auction verdict: Barysh "Best use"
    mastercraft("tipPrice"),      -- auction price, worth, cost, break-even: Barysh price and cost lines
    mastercraft("tipDisenchant"), -- what gear disenchants into: Barysh Shift details
    auctionator("AUCTION_TOOLTIPS"), -- auction price
    auctionator("VENDOR_TOOLTIPS"),  -- vendor price: the game or Barysh shows it
    {
        -- Item counts per character: Mastercraft shows them with mail, so Bagnon's go when both are on.
        addon = "Bagnon",
        also = "Mastercraft",
        key = "Bagnon.countItems",
        get = function()
            if type(Bagnon_Sets) ~= "table" then return nil end
            if type(MastercraftDB) == "table" and type(MastercraftDB.settings) == "table"
                and MastercraftDB.settings.ownedTooltip == false then
                return nil
            end
            return Bagnon_Sets.countItems ~= false
        end,
        set = function(v) Bagnon_Sets.countItems = v end,
        off = false,
    },
}

local function loaded(name)
    if not name then return true end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded ~= nil and isLoaded(name) and true or false
end

-- Barysh has prices of its own: a full scan here, or data from the PC.
function M.HasOwnPrices()
    for _, h in pairs(ns.db.ah) do
        if type(h) == "table" and h.lastFull then return true end
    end
    local m = ns.market and ns.market.ah
    return type(m) == "table" and next(m) ~= nil
end

local function saved()
    ns.db.compat = ns.db.compat or {}
    return ns.db.compat
end

-- Switches the duplicate lines off. Returns the names of addons that were changed now.
function M.Apply()
    if not M.enabled or not M.HasOwnPrices() then return {} end
    local store, changed, seen = saved(), {}, {}
    for _, r in ipairs(M.RULES) do
        if loaded(r.addon) and loaded(r.also) then
            local ok, cur = pcall(r.get)
            if ok and cur ~= nil and cur ~= r.off then
                if store[r.key] == nil then store[r.key] = cur end
                if pcall(r.set, r.off) and not seen[r.addon] then
                    seen[r.addon] = true
                    changed[#changed + 1] = r.addon
                end
            end
        end
    end
    return changed
end

-- Puts back what Barysh switched off.
function M.Restore()
    local store = ns.db.compat
    if not store then return end
    for _, r in ipairs(M.RULES) do
        local v = store[r.key]
        if v ~= nil and loaded(r.addon) then
            if pcall(r.set, v) then store[r.key] = nil end
        end
    end
end

local function applyAndTell()
    local changed = M.Apply()
    if #changed > 0 then ns.Print(L.COMPAT_APPLIED:format(table.concat(changed, ", "))) end
end

function M:OnEnable()
    -- Other addons finish their own setup at login: wait a little, then again after each auction visit
    -- (the first full scan gives Barysh its prices).
    C_Timer.After(5, function() ns.Safe(applyAndTell) end)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() ns.Safe(applyAndTell) end)
end

function M:OnDisable()
    M.Restore()
end
