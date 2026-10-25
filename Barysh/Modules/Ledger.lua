local _, ns = ...

local Ledger = ns.Ledger

-- Ledger of all money and item movements, capital per character. TZ: "Учёт и капитал".
local M = ns:NewModule("Ledger", { group = "money" })
ns.LedgerModule = M

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Records an operation; a disabled ledger records nothing.
-- op = { kind, itemID, name, qty, amount, profit, note }
function ns.Record(op)
    if not M.enabled then return nil end
    op.t = op.t or ns.Now()
    op.char = op.char or ns.CharKey()
    return Ledger.Add(ns.db.ledger, op)
end

local function saveMoney()
    local c = ns.db.chars[ns.CharKey()] or {}
    c.money = GetMoney()
    c.t = ns.Now()
    c.faction = UnitFactionGroup("player")
    ns.db.chars[ns.CharKey()] = c
end

-- Start of today / week / month in local time; "all" = 0.
function M.PeriodStart(period, now)
    now = now or ns.Now()
    if period == "all" then return 0 end
    local d = date("*t", now)
    d.hour, d.min, d.sec = 0, 0, 0
    if period == "week" then
        -- weeks start on Monday
        local wday = (d.wday + 5) % 7
        return time(d) - wday * 86400
    elseif period == "month" then
        d.day = 1
    end
    return time(d)
end

function M.Totals(period)
    return Ledger.Sum(ns.db.ledger, M.PeriodStart(period), math.huge)
end

function M.TotalGold()
    local sum = 0
    for _, c in pairs(ns.db.chars) do sum = sum + (c.money or 0) end
    return sum
end

function M:OnEnable()
    saveMoney()
    self:RegisterEvent("PLAYER_MONEY", saveMoney)
    self:RegisterEvent("PLAYER_LOGOUT", saveMoney)
end
