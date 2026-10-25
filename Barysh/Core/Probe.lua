local _, ns = ...

local L = ns.L

-- Records how the Forever client really behaves, for docs/ingame-checklist.md.
-- Everything goes to BaryshDB.probe and reaches the PC on /reload.
local Probe = {}
ns.Probe = Probe

local AH_FUNCS = {
    "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo", "GetReplicateItemTimeLeft",
    "GetReplicateItemLink", "SendSearchQuery", "SendSellSearchQuery", "StartCommoditiesPurchase",
    "ConfirmCommoditiesPurchase", "PlaceBid", "PostItem", "PostCommodity", "CancelAuction",
    "CalculateItemDeposit", "CalculateCommodityDeposit", "QueryOwnedAuctions", "GetOwnedAuctions",
    "IsThrottledMessageSystemReady", "SupportsCopperValues", "GetCommoditySearchResultInfo",
    "GetItemSearchResultInfo", "MakeItemKey",
}

local GLOBAL_FUNCS = {
    "GetInboxInvoiceInfo", "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem", "ReturnInboxItem",
    "GetItemInfo", "GetCoinTextureString", "issecretvalue", "GetTradePlayerItemInfo", "GetTradeTargetItemInfo",
}

local NAMESPACES = {
    C_EncodingUtil = { "CompressString", "DecompressString", "EncodeBase64", "DecodeBase64", "SerializeCBOR" },
    C_TradeSkillUI = { "GetRecipeSchematic", "GetAllRecipeIDs", "GetRecipeInfo" },
    C_Container = { "GetContainerItemInfo", "GetContainerItemEquipmentSetInfo" },
    C_Item = { "GetItemInfo", "GetDetailedItemLevelInfo" },
    C_Spell = { "GetSpellName" },
    C_CurrencyInfo = { "GetCoinTextureString" },
    TooltipDataProcessor = { "AddTooltipPostCall" },
}

local function has(t, name) return t ~= nil and type(t[name]) == "function" end

function Probe.Environment()
    local version, build, buildDate, interface = GetBuildInfo()
    local env = {
        t = ns.Now(), version = version, build = build, buildDate = buildDate, interface = interface,
        locale = GetLocale(), realm = GetRealmName(), faction = UnitFactionGroup("player"),
        zone = GetZoneText and GetZoneText(), subzone = GetSubZoneText and GetSubZoneText(),
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"),
        houseKey = ns.AH.CurrentKey(), ahOpen = ns.Scan.ahOpen or false,
        missing = {},
    }
    local missing = env.missing
    for _, f in ipairs(AH_FUNCS) do
        if not has(C_AuctionHouse, f) then missing[#missing + 1] = "C_AuctionHouse." .. f end
    end
    for _, f in ipairs(GLOBAL_FUNCS) do
        if type(_G[f]) ~= "function" then missing[#missing + 1] = f end
    end
    for ns_, funcs in pairs(NAMESPACES) do
        for _, f in ipairs(funcs) do
            if not has(_G[ns_], f) then missing[#missing + 1] = ns_ .. "." .. f end
        end
    end
    table.sort(missing)
    if C_AuctionHouse and C_AuctionHouse.SupportsCopperValues then
        env.copperValues = C_AuctionHouse.SupportsCopperValues()
    end
    return env
end

-- Raw shape of the first rows of the last full scan.
function Probe.ReplicateSample(n)
    local out = {}
    if not ns.AH.Available() then return out end
    local total = ns.AH.NumReplicate()
    for i = 0, math.min(total, n or 5) - 1 do
        out[#out + 1] = ns.AH.RawReplicate(i)
    end
    return out
end

-- Called when the mailbox opens: raw invoices and subjects of the first few mails.
function Probe.RecordMail()
    local p = ns.db.probe
    local mails = {}
    for i = 1, math.min(ns.MailAPI.Count(), 5) do
        local h = ns.MailAPI.Header(i)
        if h then
            mails[#mails + 1] = {
                subject = h.subject, money = h.money, cod = h.cod, items = h.itemCount,
                invoice = ns.MailAPI.RawInvoice(i),
                kind = (ns.MailClassify.Classify(h.subject, (ns.MailAPI.Invoice(i) or {}).type, ns.Mail.Patterns())),
            }
        end
    end
    p.mail = mails
end

function Probe.Run()
    local p = ns.db.probe
    p.env = Probe.Environment()
    p.replicateSample = Probe.ReplicateSample(5)
    local env = p.env
    ns.Print(L.PROBE_DONE:format(tostring(env.interface), tostring(env.build), #env.missing))
    if #env.missing > 0 then
        ns.Print(L.PROBE_MISSING .. " " .. table.concat(env.missing, ", "))
    end
    local last = p.scans and p.scans[#p.scans]
    if last then
        ns.Print(L.PROBE_LAST_SCAN:format(tostring(last.trigger), tostring(last.result), tostring(last.rows),
            last.waited or 0, last.readMs or 0, tostring(last.frames)))
    end
    ns.Print(L.PROBE_RELOAD)
end
