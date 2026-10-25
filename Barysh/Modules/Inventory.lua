local _, ns = ...

local Bags, MailAPI = ns.Bags, ns.MailAPI

-- What every character holds, for capital and stock: gold, bags, bank, mail, own auctions.
-- Updated when the character logs in and when the bank, mailbox or auction house is open.
-- TZ: "Капитал считается по всем персонажам аккаунта".
local M = ns:NewModule("Inventory", { group = "core", canDisable = false })
ns.Inventory = M

M.BAG_DELAY = 2
M.PLAYTIME_TICK = 60

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function M.Char()
    local key = ns.CharKey()
    local c = ns.db.chars[key]
    if not c then
        c = {}
        ns.db.chars[key] = c
    end
    c.faction = UnitFactionGroup("player")
    return c
end

function M.SaveMoney()
    local c = M.Char()
    c.money = GetMoney()
    c.t = ns.Now()
end

function M.SaveBags()
    M.bagQueued = false
    M.Char().bags = Bags.Counts(Bags.BagContainers())
end

function M.SaveBank()
    M.Char().bank = Bags.Counts(Bags.BankContainers())
end

-- Mail contents (COD mail is not ours until paid).
function M.SaveMail()
    local items, money = {}, 0
    for i = 1, MailAPI.Count() do
        local h = MailAPI.Header(i)
        if h and h.cod == 0 then
            money = money + h.money
            for _, it in ipairs(MailAPI.Items(i)) do
                if it.itemID then items[it.itemID] = (items[it.itemID] or 0) + it.count end
            end
        end
    end
    local c = M.Char()
    c.mail, c.mailMoney = items, money
end

function M.SaveAuctions(owned)
    local out = {}
    for _, a in ipairs(owned) do
        if not a.sold then out[a.itemID] = (out[a.itemID] or 0) + a.qty end
    end
    M.Char().auctions = out
end

-- Time online, for "income per hour".
function M.TickPlaytime()
    local now = ns.Now()
    local last = M.lastTick or now
    M.lastTick = now
    local d = math.floor(now / 86400)
    ns.db.playtime[d] = (ns.db.playtime[d] or 0) + math.max(0, math.min(now - last, 2 * M.PLAYTIME_TICK))
    for day in pairs(ns.db.playtime) do
        if day < d - 60 then ns.db.playtime[day] = nil end
    end
end

-- Seconds online in [from, to), by whole days.
function M.PlaySeconds(from, to)
    local sum = 0
    for day, sec in pairs(ns.db.playtime) do
        local t = day * 86400
        if t + 86400 > from and t < to then sum = sum + sec end
    end
    return sum
end

function M:OnEnable()
    M.SaveMoney()
    M.SaveBags()
    M.lastTick = ns.Now()
    M.ticker = C_Timer.NewTicker(M.PLAYTIME_TICK, function() ns.Safe(M.TickPlaytime) end)
    self:RegisterEvent("PLAYER_MONEY", M.SaveMoney)
    self:RegisterEvent("PLAYER_LOGOUT", function()
        M.SaveMoney()
        M.TickPlaytime()
    end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if not M.bagQueued then
            M.bagQueued = true
            C_Timer.After(M.BAG_DELAY, function() ns.Safe(M.SaveBags) end)
        end
    end)
    self:RegisterEvent("BANKFRAME_OPENED", function()
        M.bankOpen = true
        M.SaveBank()
    end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() if M.bankOpen then M.SaveBank() end end)
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        if M.bankOpen then M.SaveBank() end
        M.bankOpen = false
    end)
    self:RegisterEvent("MAIL_INBOX_UPDATE", M.SaveMail)
    self:RegisterEvent("OWNED_AUCTIONS_UPDATED", function() M.SaveAuctions(ns.AH.Owned()) end)
end
