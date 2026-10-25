local _, ns = ...

local Disenchant, Items, AH, Money = ns.Disenchant, ns.Items, ns.AH, ns.Money
local L = ns.L

-- Market price, disenchant value and sales per day in item tooltips.
local M = ns:NewModule("Tooltip", { group = "core" })

local GOLD_TEXT = "|cffffd100"
local GREY = "|cffa9a191"
local GREEN = "|cff1eff00"

local money = function(c) return ns.FormatMoney(c) end

-- Disenchant value of an item from material prices. Returns value, breakdown or nil.
function ns.DisenchantValue(item, key)
    local info = Items.Info(item)
    if not info then return nil end
    local ilvl = type(item) == "string" and Items.Level(item) or info.ilvl
    local outcomes = Disenchant.Outcomes(info.classID, info.quality, ilvl)
    if not outcomes then return nil end
    local value, breakdown, complete = Disenchant.Value(outcomes, function(id) return ns.Prices.Value(id, key) end)
    return value, breakdown, complete
end

-- Best way to turn the item into gold: "ah" | "disenchant" | "vendor", and its value per unit.
function ns.BestUse(item, key)
    key = key or ns.Prices.DefaultKey()
    local itemID = Items.ID(item)
    local info = Items.Info(item)
    local cut = AH.Cut(key)
    local options = {}
    local v = ns.Prices.Value(itemID, key)
    if v then options[#options + 1] = { "ah", Money.AfterCut(v, cut) } end
    local de = ns.DisenchantValue(item, key)
    if de and de > 0 then options[#options + 1] = { "disenchant", Money.AfterCut(de, cut) } end
    if info and info.sellPrice > 0 then options[#options + 1] = { "vendor", info.sellPrice } end
    local best
    for _, o in ipairs(options) do
        if not best or o[2] > best[2] then best = o end
    end
    if best then return best[1], best[2] end
end

local function perDayText(s)
    if not s.perDay then return "—" end
    if s.perDay >= 10 then return ("~%d"):format(math.floor(s.perDay + 0.5)) end
    return ("~%.1f"):format(s.perDay)
end

function M.AddLines(tooltip, itemID, link)
    local key = ns.Prices.DefaultKey()
    local s = ns.Prices.Item(itemID, key)
    local de, breakdown = ns.DisenchantValue(link or itemID, key)
    local avgCost = ns.CostBasis.Average(ns.db.books, itemID)
    if not s.current and not s.market and not de and not avgCost then return end

    tooltip:AddLine(GOLD_TEXT .. "Barysh|r")
    local houseName = AH.IsNeutralKey(key) and L.TT_AH_NEUTRAL or L.TT_AH
    if s.current then tooltip:AddDoubleLine(houseName, money(s.current), 1, 0.82, 0, 1, 1, 1) end
    if s.market then
        local label = s.isNew and L.TT_NEW or L.TT_USUAL
        tooltip:AddDoubleLine(GREY .. label .. "|r", GREY .. money(s.market) .. "|r")
    end
    if de then tooltip:AddDoubleLine(L.TT_DISENCHANT, "≈ " .. money(de), 1, 0.82, 0, 1, 1, 1) end
    if s.perDay and s.perDay > 0 then
        tooltip:AddDoubleLine(L.TT_PER_DAY, perDayText(s), 1, 0.82, 0, 1, 1, 1)
    end
    if avgCost then tooltip:AddDoubleLine(L.TT_COST, money(avgCost), 1, 0.82, 0, 1, 1, 1) end

    if not IsShiftKeyDown() then
        tooltip:AddLine(GREY .. L.TT_SHIFT .. "|r")
        return
    end
    if s.min7 then
        tooltip:AddDoubleLine(L.TT_MIN_MEDIAN, money(s.min7) .. " · " .. money(s.median7), 1, 0.82, 0, 1, 1, 1)
    end
    if ns.IsModuleEnabled("Neutral") and not AH.IsNeutralKey(key) then
        local neutralKey = AH.NeutralKey()
        local n = ns.db.ah[neutralKey] and ns.Prices.Item(itemID, neutralKey)
        if n and (n.market or n.current) then
            tooltip:AddDoubleLine(L.TT_AH_NEUTRAL, money(n.market or n.current), 1, 0.82, 0, 1, 1, 1)
        end
    end
    tooltip:AddDoubleLine(L.TT_PER_DAY, perDayText(s) .. " " .. L.TT_ESTIMATE, 1, 0.82, 0, 1, 1, 1)
    if breakdown then
        for _, b in ipairs(breakdown) do
            local name = Items.Name(b.itemID) or ("#" .. b.itemID)
            local count = b.min == b.max and tostring(b.min) or (b.min .. "–" .. b.max)
            tooltip:AddDoubleLine(("%d%% · %s %s"):format(math.floor(b.chance * 100 + 0.5), count, name),
                GREY .. (b.price and money(b.price) or "?") .. "|r", 1, 1, 1)
        end
    end
    local use, value = ns.BestUse(link or itemID, key)
    if use then
        tooltip:AddDoubleLine(L.TT_BEST, L["USE_" .. use] .. " " .. money(value), 1, 0.82, 0, 1, 1, 1)
        local buyBelow = value - ns.settings.deals.minProfit
        if buyBelow > 0 then
            tooltip:AddDoubleLine(L.TT_BUY_BELOW, GREEN .. money(buyBelow) .. "|r", 1, 0.82, 0)
        end
    end
end

local function onItemTooltip(tooltip, data)
    if not M.enabled or not ns.settings.tooltip.enabled then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if not itemID or (issecretvalue and issecretvalue(itemID)) then return end
    local _, link = tooltip:GetItem()
    ns.Safe(M.AddLines, tooltip, itemID, link)
end

local hooked = false
function M:OnEnable()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local _, link, id = tooltip:GetItem()
            onItemTooltip(tooltip, { id = id or Items.ID(link) })
        end)
    end
end
