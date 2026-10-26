local _, ns = ...

-- Vendor window. Selling = using a bag item while the merchant is open.
local Merchant = {}
ns.MerchantAPI = Merchant

-- VERIFY: the buyback tab keeps the last 12 sold stacks (one per bag slot), as in Classic.
Merchant.BUYBACK_SLOTS = 12

-- Item bought from the vendor: itemID, unit price, stack size of one purchase.
function Merchant.ItemInfo(index)
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return itemID, info.price, info.stackCount or 1, info.name end
    end
    if GetMerchantItemInfo then
        local name, _, price, quantity = GetMerchantItemInfo(index)
        return itemID, price, quantity or 1, name
    end
end

-- Calls fn(index, qty) after every purchase from a vendor.
function Merchant.OnBuy(fn)
    if BuyMerchantItem then
        hooksecurefunc("BuyMerchantItem", function(index, qty) ns.Safe(fn, index, qty) end)
    end
end
