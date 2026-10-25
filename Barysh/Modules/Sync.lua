local _, ns = ...

local Ledger = ns.Ledger
local L = ns.L

-- Data exchange with BaryshSync on the PC. TZ: "Программа BaryshSync".
-- Out: BaryshDB.outbox (scan changes), ledger, errors — written to disk on /reload or logout.
-- In: Data\Market.lua (market statistics + what BaryshSync has already stored), read on /reload.
local M = ns:NewModule("Sync", { group = "service", defaultEnabled = false })
ns.Sync = M

local LEDGER_KEEP_DAYS = 35

function M.MarketAge()
    local g = ns.market and ns.market.generated or 0
    if g == 0 then return nil end
    return ns.Now() - g
end

function M.IsStale()
    local age = M.MarketAge()
    return not age or age > ns.settings.staleHours * 3600
end

-- Drops everything BaryshSync confirmed it has stored.
function M.ApplyAck()
    local ack = ns.market and ns.market.ack
    if not ack then return end
    if ack.scans and ns.db.outbox then
        local kept = {}
        for _, e in ipairs(ns.db.outbox) do
            if e.t > ack.scans then kept[#kept + 1] = e end
        end
        ns.db.outbox = kept
    end
    if ack.ledger then
        Ledger.Trim(ns.db.ledger, ack.ledger, ns.Now() - LEDGER_KEEP_DAYS * 86400)
    end
    if ack.errors then
        local kept = {}
        for _, e in ipairs(ns.db.errors) do
            if e.last > ack.errors then kept[#kept + 1] = e end
        end
        ns.db.errors = kept
    end
end

function M.Save()
    ReloadUI()
end

function M:OnEnable()
    ns.db.outbox = ns.db.outbox or {}
    M.ApplyAck()
    M.warned = false
    self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        if not M.warned and M.IsStale() then
            M.warned = true
            local age = M.MarketAge()
            ns.Print(age and L.SYNC_STALE:format(ns.FormatAge(age)) or L.SYNC_NEVER)
        end
    end)
end

function M:OnDisable()
    -- Nothing will collect the outbox while the link is off.
    ns.db.outbox = nil
end
