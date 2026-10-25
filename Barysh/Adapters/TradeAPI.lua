local _, ns = ...

-- Trade window: items and gold on both sides. Slot 7 is "will not be traded" (enchanting).
local TradeAPI = {}
ns.TradeAPI = TradeAPI

TradeAPI.SLOTS = MAX_TRADABLE_ITEMS or 6
TradeAPI.ENCHANT_SLOT = TRADE_ENCHANT_SLOT or 7

local function side(infoFn, linkFn)
    local items = {}
    for i = 1, TradeAPI.SLOTS do
        local name, _, count = infoFn(i)
        local link = linkFn(i)
        local itemID = ns.Items.ID(link)
        if name and itemID then items[#items + 1] = { itemID = itemID, qty = count or 1, name = name } end
    end
    return items
end

-- { partner, gave = { items, money }, got = { items, money }, enchant }
function TradeAPI.Read()
    local t = {
        partner = UnitName("NPC"),
        gave = { items = side(GetTradePlayerItemInfo, GetTradePlayerItemLink), money = GetPlayerTradeMoney() or 0 },
        got = { items = side(GetTradeTargetItemInfo, GetTradeTargetItemLink), money = GetTargetTradeMoney() or 0 },
    }
    -- The partner's item in their "will not be traded" slot shows the enchantment we put on it.
    local _, _, _, _, _, enchant = GetTradeTargetItemInfo(TradeAPI.ENCHANT_SLOT)
    if enchant and enchant ~= "" then t.enchant = enchant end
    return t
end

function TradeAPI.IsGuildMember(name)
    if not name then return false end
    if C_GuildInfo and C_GuildInfo.MemberExistsByName then return C_GuildInfo.MemberExistsByName(name) end
    return false
end
