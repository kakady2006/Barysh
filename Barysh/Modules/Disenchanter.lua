local _, ns = ...

local Bags, Items, DisenchantPick, CostBasis, Money, AH = ns.Bags, ns.Items, ns.DisenchantPick, ns.CostBasis, ns.Money, ns.AH
local L = ns.L

-- One-button disenchanting via a secure action button. TZ: "Распылитель".
-- Each press disenchants one item; the target changes out of combat after every disenchant.
local M = ns:NewModule("Disenchanter", { group = "craft" })
ns.Disenchanter = M

M.SPELL_ID = 13262

local function spellName()
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(M.SPELL_ID) end
    return GetSpellInfo and (GetSpellInfo(M.SPELL_ID))
end

-- Bag items in the shape DisenchantPick expects.
function M.BagItems()
    local items = {}
    Bags.Each(function(bag, slot, info)
        local item = Items.Info(info.hyperlink or info.itemID)
        if item then
            items[#items + 1] = {
                bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                quality = info.quality or item.quality, classID = item.classID,
                ilvl = Items.Level(info.hyperlink) or item.ilvl,
                locked = info.isLocked, bound = info.isBound, inSet = Bags.InEquipmentSet(bag, slot),
            }
        end
    end)
    return items
end

function M.Rules()
    local s = ns.settings.disenchant
    local key = ns.Prices.DefaultKey()
    return {
        quality = s.quality,
        exclude = ns.settings.lists.noDisenchant.items,
        skipBetterToSell = s.skipBetterToSell,
        deValue = function(item) return ns.DisenchantValue(item.link or item.itemID, key) end,
        sellValue = function(item)
            local v = ns.Prices.Value(item.itemID, key)
            return v and Money.AfterCut(v, AH.Cut(key))
        end,
    }
end

-- Points the button at the next item. Only out of combat: secure attributes are locked in combat.
function M.Update()
    local b = M.button
    if not b then return end
    if InCombatLockdown() then
        M.pending = true
        return
    end
    M.pending = false
    local nextItem, count = DisenchantPick.Next(M.BagItems(), M.Rules())
    M.next, M.count = nextItem, count
    local name = spellName()
    if nextItem and name then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", ("/cast %s\n/use %d %d"):format(name, nextItem.bag, nextItem.slot))
    else
        b:SetAttribute("type", nil)
        b:SetAttribute("macrotext", nil)
    end
    b.count:SetText(count > 0 and count or "")
    b:SetAlpha(count > 0 and 1 or 0.5)
end

-- Ledger: what the last disenchant gave ---------------------------------------------------

local function output(itemID, qty)
    return { itemID = itemID, qty = qty or 1, value = (ns.Prices.Value(itemID) or 0) * (qty or 1) }
end

local function record(cast, outputs)
    if #outputs == 0 then return end
    local cost = CostBasis.Transfer(ns.db.books, cast.itemID, 1, outputs)
    local value = 0
    for _, o in ipairs(outputs) do value = value + o.value end
    ns.Record({ kind = "disenchant", itemID = cast.itemID, qty = 1, amount = 0, profit = value - cost,
        note = (#outputs) .. " outputs" })
end

-- Auto-loot addons (SpeedyAutoLoot) may take the slots before Barysh reads them. Then the outputs come
-- from the "You receive loot" chat lines of the next moment.
local CHAT_WAIT = 1.5

local function chatPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%%%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

function M.ParseLootMessage(msg)
    local multi = chatPattern(LOOT_ITEM_SELF_MULTIPLE)
    if multi then
        local link, qty = msg:match(multi)
        if link then return Items.ID(link), tonumber(qty) end
    end
    local single = chatPattern(LOOT_ITEM_SELF)
    if single then
        local link = msg:match(single)
        if link then return Items.ID(link), 1 end
    end
end

local function onChatLoot(msg)
    local p = M.pendingChat
    if not p or GetTime() - p.t > CHAT_WAIT or type(msg) ~= "string" then return end
    local itemID, qty = M.ParseLootMessage(msg)
    if itemID then p.outputs[#p.outputs + 1] = output(itemID, qty) end
end

local function onLoot()
    local cast = M.casting
    -- Only loot right after a disenchant that really went through.
    if not cast or not cast.done or GetTime() - cast.t > 10 then return end
    M.casting = nil
    local outputs = {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local _, _, qty = GetLootSlotInfo(i)
        local itemID = Items.ID(link)
        if itemID then outputs[#outputs + 1] = output(itemID, qty) end
    end
    if #outputs > 0 then return record(cast, outputs) end
    local pending = { cast = cast, t = GetTime(), outputs = {} }
    M.pendingChat = pending
    C_Timer.After(CHAT_WAIT, function()
        if M.pendingChat ~= pending then return end
        M.pendingChat = nil
        ns.Safe(record, pending.cast, pending.outputs)
    end)
end

-- Button --------------------------------------------------------------------------------

local function showTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.DE_TITLE:format(M.count or 0))
    if M.next then
        local info = Items.Info(M.next.link or M.next.itemID)
        GameTooltip:AddDoubleLine(L.DE_NEXT, info and info.name or "?", 1, 1, 1)
    else
        GameTooltip:AddLine(L.DE_NONE, 1, 1, 1)
    end
    GameTooltip:AddLine(L.DE_HINT, 0.66, 0.63, 0.57, true)
    GameTooltip:Show()
end

function M.ApplyBinding()
    if not M.button or InCombatLockdown() then return end
    ClearOverrideBindings(M.button)
    local key = ns.settings.disenchant.key
    if key and key ~= "" then
        SetOverrideBindingClick(M.button, true, key, M.button:GetName(), "LeftButton")
    end
end

function M.PlaceButton(b)
    b = b or M.button
    if not b or InCombatLockdown() then return end
    b:ClearAllPoints()
    local pos = ns.cdb.dePos
    if pos then
        b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        b:SetPoint("CENTER", UIParent, "CENTER", 300, -150)
    end
end

-- Settings: "Put the button back" after it was dragged somewhere awkward.
function M.ResetPosition()
    ns.cdb.dePos = nil
    M.PlaceButton()
end

local function createButton()
    if M.button then return M.button end
    local b = CreateFrame("Button", "BaryshDisenchantButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(48, 48)
    b:RegisterForClicks("AnyUp", "AnyDown")
    -- Shift + drag moves the button. With Shift held a click does nothing (an empty macro), otherwise
    -- the press that starts the drag would already disenchant.
    b:SetAttribute("shift-type*", "macro")
    b:SetAttribute("shift-macrotext*", "")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton", "RightButton")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.cdb.dePos = { point, rel, x, y }
    end)
    M.PlaceButton(b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(M.SPELL_ID) or 132871)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.keyText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.keyText:SetPoint("TOPLEFT", 3, -3)
    b.keyText:SetText(ns.settings.disenchant.key or "")
    b:SetScript("PreClick", function()
        if M.next then M.casting = { itemID = M.next.itemID, t = GetTime() } end
    end)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    M.button = b
    return b
end

function M.SetShown(show)
    if InCombatLockdown() then return end
    ns.settings.disenchant.shown = show
    if M.button then M.button:SetShown(show and M.enabled) end
end

function M:OnEnable()
    createButton()
    M.Update()
    M.ApplyBinding()
    M.button:SetShown(ns.settings.disenchant.shown)
    self:RegisterEvent("BAG_UPDATE_DELAYED", M.Update)
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not M.updateQueued then
            M.updateQueued = true
            C_Timer.After(0.5, function() M.updateQueued = false; if M.enabled then M.Update() end end)
        end
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if M.pending then M.Update() end
        M.ApplyBinding()
    end)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        if unit == "player" and spellID == M.SPELL_ID and M.casting then
            M.casting.done = true
            M.casting.t = GetTime()
        end
    end)
    self:RegisterEvent("UNIT_SPELLCAST_FAILED", function(_, _, unit, _, spellID)
        if unit == "player" and spellID == M.SPELL_ID then M.casting = nil end
    end)
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, _, unit, _, spellID)
        if unit == "player" and spellID == M.SPELL_ID then M.casting = nil end
    end)
    self:RegisterEvent("LOOT_READY", function() ns.Safe(onLoot) end)
    self:RegisterEvent("CHAT_MSG_LOOT", function(_, _, msg) ns.Safe(onChatLoot, msg) end)
end

function M:OnDisable()
    if M.button and not InCombatLockdown() then
        ClearOverrideBindings(M.button)
        M.button:Hide()
    end
    M.next, M.casting = nil, nil
end
