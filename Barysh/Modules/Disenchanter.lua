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
        if itemID then
            outputs[#outputs + 1] = { itemID = itemID, qty = qty or 1, value = (ns.Prices.Value(itemID) or 0) * (qty or 1) }
        end
    end
    if #outputs == 0 then return end
    local cost = CostBasis.Transfer(ns.db.books, cast.itemID, 1, outputs)
    local value = 0
    for _, o in ipairs(outputs) do value = value + o.value end
    ns.Record({ kind = "disenchant", itemID = cast.itemID, qty = 1, amount = 0, profit = value - cost,
        note = (#outputs) .. " outputs" })
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

local function createButton()
    if M.button then return M.button end
    local b = CreateFrame("Button", "BaryshDisenchantButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(48, 48)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.cdb.dePos = { point, rel, x, y }
    end)
    local pos = ns.cdb.dePos
    if pos then
        b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        b:SetPoint("CENTER", UIParent, "CENTER", 300, -150)
    end
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
end

function M:OnDisable()
    if M.button and not InCombatLockdown() then
        ClearOverrideBindings(M.button)
        M.button:Hide()
    end
    M.next, M.casting = nil, nil
end
