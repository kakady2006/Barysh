-- Imitation of the WoW client API the addon uses.
-- Add only functions that really exist in the Forever (modern) API.

local Mock = {
    frames = {}, printed = {}, sounds = {}, timers = {},
    clock = 0,              -- ms since start
    base = 1793000000,      -- unix time at clock 0
    inCombat = false,
    bindings = {},
}
WowMock = Mock

-- Frames -------------------------------------------------------------------------------

local Frame = {}
local function noop() end
Frame.__index = function(_, key)
    local v = rawget(Frame, key)
    if v ~= nil then return v end
    -- Every other widget method (CamelCase) is accepted and ignored; data fields stay nil.
    if type(key) == "string" and key:match("^%u") then return noop end
end

function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Frame:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
function Frame:SetAttribute(k, v) self.attributes[k] = v end
function Frame:GetAttribute(k) return self.attributes[k] end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:GetWidth() return self.width or 100 end
function Frame:GetHeight() return self.height or 20 end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetWidth(w) self.width = w end
function Frame:SetHeight(h) self.height = h end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetChecked(v) self.checked = v end
function Frame:Click(button)
    if self.scripts.PreClick then self.scripts.PreClick(self, button or "LeftButton", false) end
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", false) end
    if self.scripts.PostClick then self.scripts.PostClick(self, button or "LeftButton", false) end
end
function Frame:GetObjectType() return self.frameType end
function Frame:NumLines() return #self.lines end
function Frame:AddLine(text) self.lines[#self.lines + 1] = text end
function Frame:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " | " .. r end
function Frame:ClearLines() self.lines = {} end

local function newObject(frameType, name, parent)
    local f = setmetatable({
        frameType = frameType, name = name, parent = parent,
        events = {}, scripts = {}, attributes = {}, lines = {}, shown = true,
    }, Frame)
    if name then _G[name] = f end
    return f
end

function Frame:CreateFontString(name) return newObject("FontString", name, self) end
function Frame:CreateTexture(name) return newObject("Texture", name, self) end

function CreateFrame(frameType, name, parent, template)
    local f = newObject(frameType, name, parent)
    f.template = template
    Mock.frames[#Mock.frames + 1] = f
    return f
end

UIParent = newObject("Frame", "UIParent")
Minimap = newObject("Frame", "Minimap")
GameTooltip = newObject("GameTooltip", "GameTooltip")
UISpecialFrames = {}

-- Fire an event on every frame registered for it, like the client does.
function Mock.FireEvent(event, ...)
    for _, f in ipairs(Mock.frames) do
        local handler = f.scripts.OnEvent
        if f.events[event] and handler then handler(f, event, ...) end
    end
end

-- Timers -------------------------------------------------------------------------------

local function schedule(sec, fn, ticker)
    local t = { at = Mock.clock + sec * 1000, fn = fn, interval = ticker and sec, cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    Mock.timers[#Mock.timers + 1] = t
    return t
end

C_Timer = {
    After = function(sec, fn) schedule(sec, fn) end,
    NewTimer = function(sec, fn) return schedule(sec, fn) end,
    NewTicker = function(sec, fn) return schedule(sec, fn, true) end,
}

local function runTimers()
    local due = {}
    for i = #Mock.timers, 1, -1 do
        local t = Mock.timers[i]
        if t.cancelled then
            table.remove(Mock.timers, i)
        elseif t.at <= Mock.clock then
            due[#due + 1] = t
            if t.interval then t.at = t.at + t.interval * 1000 else table.remove(Mock.timers, i) end
        end
    end
    for i = #due, 1, -1 do
        if not due[i].cancelled then due[i].fn(due[i]) end
    end
end

-- Run n frames of `ms` milliseconds: timers first, then OnUpdate scripts.
function Mock.RunFrames(n, ms)
    ms = ms or 16
    for _ = 1, n do
        Mock.clock = Mock.clock + ms
        runTimers()
        for _, f in ipairs(Mock.frames) do
            local handler = f.scripts.OnUpdate
            if handler then handler(f, ms / 1000) end
        end
    end
end

function Mock.Advance(seconds)
    local frames = math.ceil(seconds * 1000 / 100)
    Mock.RunFrames(frames, 100)
end

-- Basics -------------------------------------------------------------------------------

function debugprofilestop() return Mock.clock end
function GetTime() return Mock.clock / 1000 end
function time(t)
    if t then return os.time(t) end
    return Mock.base + math.floor(Mock.clock / 1000)
end
date = os.date
function GetServerTime() return time() end
function GetLocale() return "ruRU" end
function debugstack(level) return debug.traceback("", (level or 1) + 1) end
function InCombatLockdown() return Mock.inCombat end
function IsShiftKeyDown() return Mock.shift == true end
function UnitName() return "Tester" end
function GetRealmName() return "TestRealm" end
function UnitFactionGroup() return Mock.faction or "Horde" end
function GetMoney() return Mock.money or 0 end
function GetBuildInfo() return "1.60.1", "70450", "Oct 20 2026", 16001 end
function PlaySound(id) Mock.sounds[#Mock.sounds + 1] = id end
function ReloadUI() Mock.reloaded = true end
function SetOverrideBindingClick(owner, prio, key, button) Mock.bindings[key] = button end
function ClearOverrideBindings() Mock.bindings = {} end
function GetCoinTextureString(copper) return tostring(copper) .. "c" end
function hooksecurefunc() end
tinsert = table.insert
function GetCursorPosition() return 0, 0 end
function issecretvalue() return false end

SOUNDKIT = { RAID_WARNING = 8959, AUCTION_WINDOW_OPEN = 5274, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
Enum = {
    AuctionHouseTimeLeftBand = { Short = 0, Medium = 1, Long = 2, VeryLong = 3 },
    AuctionHouseSortOrder = { Price = 0, Name = 1 },
    TooltipDataType = { Item = 0 },
}

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
ERR_INV_FULL = "Inventory is full."
ATTACHMENTS_MAX_RECEIVE = 16
NUM_BAG_SLOTS = 4

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
end

SlashCmdList = {}

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        if field == "Version" then return "test" end
    end,
}

C_Map = {
    GetBestMapForUnit = function() return Mock.mapID or 1454 end,
    GetMapInfo = function(id) return { mapID = id, name = "Map" .. id, parentMapID = 0 } end,
}
function GetZoneText() return "Zone" end
function GetSubZoneText() return "" end

C_Spell = {
    GetSpellName = function(id) if id == 13262 then return "Disenchant" end end,
    GetSpellTexture = function() return 132871 end,
}

-- Items --------------------------------------------------------------------------------
-- Mock.items[itemID] = { name, quality, ilvl, classID, sellPrice, stack }
Mock.items = {}

local function itemInfo(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    local it = id and Mock.items[id]
    if not it then return nil end
    return it.name, "|Hitem:" .. id .. "|h[" .. it.name .. "]|h", it.quality, it.ilvl, 1, "Type", "Sub",
        it.stack or 1, "", 134400, it.sellPrice or 0, it.classID or 0, 0, it.bind or 0
end
GetItemInfo = itemInfo
C_Item = {
    GetItemInfo = itemInfo,
    GetItemInfoInstant = function(item)
        if type(item) == "string" and not item:find("item:") then
            for id, it in pairs(Mock.items) do
                if it.name == item then return id end
            end
            return nil
        end
        local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        local it = id and Mock.items[id]
        if it then return id, "Type", "Sub", "", 134400, it.classID or 0, 0 end
    end,
    GetDetailedItemLevelInfo = function(item)
        local _, _, _, ilvl = itemInfo(item)
        return ilvl
    end,
}

-- Bags: Mock.bags[bag][slot] = { itemID, count, locked, bound, inSet }
Mock.bags = { [0] = {} }
C_Container = {
    GetContainerNumSlots = function(bag) return Mock.bags[bag] and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local b = Mock.bags[bag]
        local s = b and b[slot]
        if not s then return nil end
        local it = Mock.items[s.itemID] or {}
        return {
            itemID = s.itemID, stackCount = s.count or 1, isLocked = s.locked or false,
            quality = it.quality, isBound = s.bound or false,
            hyperlink = "|Hitem:" .. s.itemID .. "|h[" .. (it.name or "?") .. "]|h",
        }
    end,
    GetContainerItemEquipmentSetInfo = function(bag, slot)
        local s = Mock.bags[bag] and Mock.bags[bag][slot]
        return s and s.inSet or false, ""
    end,
}

-- Auction house ------------------------------------------------------------------------
-- Mock.replicate = { {itemID, count, buyout, tl, hasAllInfo}, ... }  (read with 0-based index)
-- Mock.searchResults[itemID] = { commodity = bool, rows = { {quantity, unitPrice|buyoutAmount, timeLeftSeconds|timeLeft, auctionID} } }
Mock.replicate = {}
Mock.searchResults = {}
Mock.replicateCalls = 0
Mock.searchCalls = {}

C_AuctionHouse = {
    ReplicateItems = function()
        Mock.replicateCalls = Mock.replicateCalls + 1
        if Mock.replicateBlocked then return end
        C_Timer.After(Mock.replicateDelay or 2, function() Mock.FireEvent("REPLICATE_ITEM_LIST_UPDATE") end)
    end,
    GetNumReplicateItems = function() return #Mock.replicate end,
    GetReplicateItemInfo = function(i)
        local r = Mock.replicate[i + 1]
        if not r then return nil end
        local it = Mock.items[r[1]] or {}
        return it.name, 134400, r[2], it.quality or 1, true, 1, 0, 0, 0, r[3], 0, false, nil, nil, nil, 0, r[1], r[5] ~= false
    end,
    GetReplicateItemTimeLeft = function(i)
        local r = Mock.replicate[i + 1]
        return r and r[4]
    end,
    MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
    SendSearchQuery = function(itemKey)
        Mock.searchCalls[#Mock.searchCalls + 1] = itemKey.itemID
        local res = Mock.searchResults[itemKey.itemID]
        C_Timer.After(0.3, function()
            if res and res.commodity then
                Mock.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", itemKey.itemID)
            else
                Mock.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", itemKey)
            end
        end)
    end,
    IsThrottledMessageSystemReady = function() return true end,
    GetCommoditySearchResultsQuantity = function(itemID)
        local res = Mock.searchResults[itemID]
        return res and #res.rows or 0
    end,
    GetCommoditySearchResultInfo = function(itemID, index)
        local r = Mock.searchResults[itemID].rows[index]
        return { itemID = itemID, quantity = r[1], unitPrice = r[2], timeLeftSeconds = r[3], auctionID = r[4] }
    end,
    HasFullCommoditySearchResults = function() return true end,
    GetItemSearchResultsQuantity = function(itemKey)
        local res = Mock.searchResults[itemKey.itemID]
        return res and #res.rows or 0
    end,
    GetItemSearchResultInfo = function(itemKey, index)
        local r = Mock.searchResults[itemKey.itemID].rows[index]
        return { itemKey = itemKey, quantity = r[1], buyoutAmount = r[2], timeLeft = r[3], auctionID = r[4] }
    end,
    HasFullItemSearchResults = function() return true end,
}

-- Mail ---------------------------------------------------------------------------------
-- Mock.inbox = { { sender, subject, money, cod, items = { {itemID, count} }, invoice = {type, itemName, player, bid, buyout, deposit, cut} } }
Mock.inbox = {}

function GetInboxNumItems() return #Mock.inbox, #Mock.inbox end
function GetInboxHeaderInfo(i)
    local m = Mock.inbox[i]
    if not m then return nil end
    return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 30, m.items and #m.items or 0,
        false, false, false, false, false
end
function GetInboxInvoiceInfo(i)
    local inv = Mock.inbox[i] and Mock.inbox[i].invoice
    if not inv then return nil end
    return inv.type, inv.itemName, inv.player, inv.bid or 0, inv.buyout or 0, inv.deposit or 0, inv.cut or 0, 0, 0, 0, inv.count or 1
end
function GetInboxItem(i, a)
    local m = Mock.inbox[i]
    local it = m and m.items and m.items[a]
    if not it then return nil end
    local info = Mock.items[it[1]] or {}
    return info.name, it[1], 134400, it[2], info.quality or 1, true
end
function GetInboxItemLink(i, a)
    local m = Mock.inbox[i]
    local it = m and m.items and m.items[a]
    return it and ("|Hitem:" .. it[1] .. "|h[x]|h")
end
local function afterMailChange(i)
    local m = Mock.inbox[i]
    if m and (m.money or 0) == 0 and (not m.items or #m.items == 0) then
        table.remove(Mock.inbox, i)
    end
    C_Timer.After(0.1, function() Mock.FireEvent("MAIL_INBOX_UPDATE") end)
end
function TakeInboxMoney(i)
    local m = Mock.inbox[i]
    if not m then return end
    Mock.money = (Mock.money or 0) + (m.money or 0)
    m.money = 0
    afterMailChange(i)
end
function TakeInboxItem(i, a)
    local m = Mock.inbox[i]
    if not m or not m.items or not m.items[a] then return end
    if Mock.bagsFull then
        C_Timer.After(0.1, function() Mock.FireEvent("UI_ERROR_MESSAGE", 0, ERR_INV_FULL) end)
        return
    end
    table.remove(m.items, a)
    afterMailChange(i)
end

-- Loot ---------------------------------------------------------------------------------
Mock.loot = {}
function GetNumLootItems() return #Mock.loot end
function GetLootSlotLink(i) return Mock.loot[i] and ("|Hitem:" .. Mock.loot[i][1] .. "|h[x]|h") end
function GetLootSlotInfo(i)
    local l = Mock.loot[i]
    if l then return 134400, "x", l[2], nil, 1 end
end

-- Tooltips -----------------------------------------------------------------------------
Mock.tooltipCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, fn) Mock.tooltipCalls[dataType] = fn end,
}

function Mock.ShowItemTooltip(itemID)
    GameTooltip:ClearLines()
    local fn = Mock.tooltipCalls[Enum.TooltipDataType.Item]
    function GameTooltip:GetItem() return "x", "|Hitem:" .. itemID .. "|h[x]|h", itemID end
    fn(GameTooltip, { id = itemID })
    return GameTooltip.lines
end
