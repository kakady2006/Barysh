local _, ns = ...

local UI = ns.UI

-- "Barysh" tab at the bottom of the auction house. Clicking it hides the game's own page and shows the
-- Barysh window inside the auction house; any other tab (or closing the auction house) takes it out again.
-- With Auctionator installed the tab is made through the shared LibAHTab library, so it lines up with
-- Auctionator's tabs; without it Barysh makes its own tab after the game's tabs.

local TAB_ID = "Barysh"
local WIDTH, HEIGHT = 620, 560 -- the main window, see UI/MainFrame.lua

local host, ownTab

local function embed()
    local f = UI.Frame()
    f.embedded = true
    f:SetParent(host)
    f:SetFrameStrata(AuctionHouseFrame:GetFrameStrata() or "MEDIUM")
    f:SetFrameLevel((host:GetFrameLevel() or 0) + 5)
    local w, h = host:GetWidth(), host:GetHeight()
    local scale = 1
    if w and h and w > 0 and h > 0 then scale = math.min(1, w / WIDTH, h / HEIGHT) end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("TOP", host, "TOP", 0, 0)
    if f.close then f.close:Hide() end
    UI.Show()
end

local function release()
    local f = UI.Frame()
    if not f.embedded then return end
    f.embedded = nil
    f:Hide()
    f:SetParent(UIParent)
    f:SetScale(1)
    f:SetFrameStrata("HIGH")
    if f.close then f.close:Show() end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
end

local function createHost()
    host = CreateFrame("Frame", "BaryshAuctionHost", AuctionHouseFrame)
    host:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -24)
    host:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 4)
    host:Hide()
    host:SetScript("OnShow", function() ns.Safe(embed) end)
    host:SetScript("OnHide", function() ns.Safe(release) end)
end

-- Own tab, when no other addon brings LibAHTab.
local function select(b)
    AuctionHouseFrame:SetDisplayMode({})
    AuctionHouseFrame.displayMode = nil
    if PanelTemplates_DeselectTab then
        for _, t in ipairs(AuctionHouseFrame.Tabs or {}) do PanelTemplates_DeselectTab(t) end
    end
    if PanelTemplates_SelectTab then PanelTemplates_SelectTab(b) end
    if AuctionHouseFrame.SetTitle then AuctionHouseFrame:SetTitle("Barysh") end
    host:Show()
end

local function createOwnTab()
    local ok, b = pcall(CreateFrame, "Button", "BaryshAuctionTab", AuctionHouseFrame,
        "AuctionHouseFrameDisplayModeTabTemplate")
    if not ok or not b then
        b = CreateFrame("Button", "BaryshAuctionTab", AuctionHouseFrame, "UIPanelButtonTemplate")
        b:SetSize(80, 22)
    end
    b:SetText("Barysh")
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 20, nil, 70) end
    local tabs = AuctionHouseFrame.Tabs
    local last = tabs and tabs[#tabs]
    if last then b:SetPoint("TOPLEFT", last, "TOPRIGHT", 3, 0) else b:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 10, 2) end
    if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, b) end
    b:SetScript("OnClick", function(self) ns.Safe(select, self) end)
    -- Any game tab switches the page back.
    hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
        if type(mode) == "table" and #mode > 0 then
            host:Hide()
            if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, b) end
        end
    end)
    ownTab = b
end

function UI.CreateAuctionTab()
    if host or not AuctionHouseFrame then return end
    createHost()
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib and lib.CreateTab then
        local ok = pcall(lib.CreateTab, lib, TAB_ID, host, "Barysh", "Barysh")
        if ok then return end
    end
    createOwnTab()
end

-- Opens the Barysh page of the auction house (minimap button, slash command while it is open).
function UI.SelectAuctionTab()
    if not host then return false end
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not ownTab and lib and lib.DoesIDExist and lib:DoesIDExist(TAB_ID) then
        lib:SetSelected(TAB_ID)
    elseif ownTab then
        select(ownTab)
    end
    return true
end

-- The auction house closed: take the window out (the game hides the page with it, this makes sure).
function UI.CloseAuctionTab()
    if host and host:IsShown() then host:Hide() end
end
