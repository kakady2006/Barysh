local _, ns = ...

local Items, Bags, CostBasis, MerchantAPI = ns.Items, ns.Bags, ns.CostBasis, ns.MerchantAPI
local L = ns.L

-- "Sell to vendor" button: grey junk, "easy money" purchases and items worth more to the vendor
-- than on the auction house or disenchanted. Everything goes to the ledger. TZ: "Торговец".
local M = ns:NewModule("Vendor", { group = "trade" })
ns.Vendor = M

M.STEP_DELAY = 0.2

-- Why an item goes to the vendor: "junk" | "easy" | "better" | nil.
function M.Reason(itemID, info)
    local s = ns.settings.vendor
    if not info or (info.sellPrice or 0) <= 0 then return nil end
    if ns.ItemLists.Has("stock", itemID) or ns.db.sellMarked[itemID] then return nil end
    if s.junk and info.quality == 0 then return "junk" end
    local bought = ns.db.purchases[itemID]
    if s.easy and bought and bought.type == "easy" then return "easy" end
    -- Weapons and armour are never sold as "better to vendor": it may be gear the player keeps.
    local gear = info.classID == 2 or info.classID == 4
    if s.better and not gear and ns.BestUse(itemID) == "vendor" and info.quality and info.quality >= 1 then
        -- Only with a market price known: without one "vendor" is just the only option.
        if ns.Prices.Value(itemID) then return "better" end
    end
end

-- { {bag, slot, itemID, count, price, reason}, ... }
function M.Candidates()
    local out = {}
    Bags.Each(function(bag, slot, info)
        if info.isLocked then return end
        local item = Items.Info(info.hyperlink or info.itemID)
        local reason = M.Reason(info.itemID, item)
        if reason then
            out[#out + 1] = {
                bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1,
                price = item.sellPrice, reason = reason,
            }
        end
    end)
    return out
end

function M.Total(list)
    local sum = 0
    for _, c in ipairs(list or M.Candidates()) do sum = sum + c.price * c.count end
    return sum
end

local function record(c)
    local cost = CostBasis.Remove(ns.db.books, c.itemID, c.count)
    local amount = c.price * c.count
    ns.Record({ kind = "vendor_sell", itemID = c.itemID, qty = c.count, amount = amount, profit = amount - cost,
        note = c.reason })
end

-- One click sells the whole list, one item at a time while the merchant stays open.
function M.SellAll()
    if not M.merchantOpen or M.selling then return false end
    local list = M.Candidates()
    if #list == 0 then return false end
    M.selling = { list = list, i = 0, money = 0 }
    local function step()
        local s = M.selling
        if not s or not M.merchantOpen then
            M.selling = nil
            return
        end
        s.i = s.i + 1
        local c = s.list[s.i]
        if not c then
            M.selling = nil
            ns.Print(L.VENDOR_SOLD:format(s.i - 1, ns.FormatMoney(s.money)))
            M.UpdateButton()
            return
        end
        local info = C_Container.GetContainerItemInfo(c.bag, c.slot)
        if info and info.itemID == c.itemID then
            Bags.Use(c.bag, c.slot)
            record(c)
            s.money = s.money + c.price * c.count
        end
        C_Timer.After(M.STEP_DELAY, step)
    end
    step()
    return true
end

-- Purchases from vendors: ledger and cost basis.
local function onBuy(index, qty)
    if not M.enabled then return end
    local itemID, price, stack = MerchantAPI.ItemInfo(index)
    if not itemID or not price then return end
    -- VERIFY: quantity counts purchases of `stack` units each, price is per purchase.
    local n = qty or 1
    local units = n * (stack or 1)
    local cost = price * n
    CostBasis.Add(ns.db.books, itemID, units, cost)
    ns.Record({ kind = "vendor_buy", itemID = itemID, qty = units, amount = -cost, profit = 0 })
end

function M.UpdateButton()
    local b = M.button
    if not b then return end
    local list = M.Candidates()
    b:SetText(L.VENDOR_BUTTON:format(#list, ns.FormatMoney(M.Total(list))))
    b:SetEnabled(#list > 0 and not M.selling)
end

local function createButton()
    if M.button or not MerchantFrame then return end
    local b = CreateFrame("Button", "BaryshSellToVendor", MerchantFrame, "UIPanelButtonTemplate")
    b:SetSize(200, 22)
    b:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -2)
    b:SetScript("OnClick", function() ns.Safe(M.SellAll) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.VENDOR_TIP, 1, 1, 1, true)
        for i, c in ipairs(M.Candidates()) do
            if i > 15 then break end
            GameTooltip:AddDoubleLine(("%s ×%d"):format(Items.ColoredName(c.itemID), c.count),
                L["VENDOR_" .. c.reason] .. " · " .. ns.FormatMoney(c.price * c.count), 1, 1, 1, 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    M.button = b
end

local hooked = false
function M:OnEnable()
    if not hooked then
        hooked = true
        MerchantAPI.OnBuy(onBuy)
    end
    self:RegisterEvent("MERCHANT_SHOW", function()
        M.merchantOpen = true
        createButton()
        if M.button then M.button:Show() end
        M.UpdateButton()
    end)
    self:RegisterEvent("MERCHANT_CLOSED", function()
        M.merchantOpen = false
        M.selling = nil
    end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() if M.merchantOpen then M.UpdateButton() end end)
end

function M:OnDisable()
    if M.button then M.button:Hide() end
    M.selling = nil
end
