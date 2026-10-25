local _, ns = ...

local UI = ns.UI
local L = ns.L

-- Main window: sticks to the right edge of the auction house, opens from the minimap button too.
-- Tabs at the bottom; a disabled module removes its tab.
local WIDTH, HEIGHT = 620, 560

UI.tabs = {}      -- registered tab definitions, in order
UI.current = nil

-- def = { id, label, module (name or nil), build = function(content), refresh = function(content) }
function UI.RegisterTab(def)
    UI.tabs[#UI.tabs + 1] = def
end

local frame

local function tabAvailable(def)
    return not def.module or (ns.modules[def.module] and ns.modules[def.module].enabled)
end

local function layoutTabs()
    local prev
    for _, def in ipairs(UI.tabs) do
        local b = def.button
        if tabAvailable(def) then
            b:ClearAllPoints()
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, 2) end
            b:Show()
            prev = b
        else
            b:Hide()
        end
    end
end

function UI.SelectTab(id)
    if not frame then return end
    for _, def in ipairs(UI.tabs) do
        local on = def.id == id and tabAvailable(def)
        def.content:SetShown(on)
        def.button:SetEnabled(not on)
        if on then UI.current = def end
    end
    UI.Refresh()
end

local function updateHeader()
    local scan = ns.Scan
    local key = ns.Prices.DefaultKey()
    local house = ns.AH.IsNeutralKey(key) and L.HOUSE_NEUTRAL or (UnitFactionGroup("player") == "Alliance" and L.HOUSE_ALLIANCE or L.HOUSE_HORDE)
    frame.house:SetText(L.HOUSE:format(house))
    frame.gold:SetText(L.FREE_GOLD:format(ns.FormatMoney(GetMoney())))

    local h = ns.db.ah[key]
    local last = h and h.lastFull
    local status
    if scan.state == "waiting" then
        status = L.SCAN_WAITING
    elseif scan.state == "reading" or scan.state == "saving" then
        status = L.SCAN_READING
    elseif scan.state == "quick" then
        status = L.SCAN_QUICK_RUNNING
    else
        status = L.LAST_FULL_SCAN:format(last and ns.FormatAge(ns.Now() - last) or L.NEVER)
    end
    frame.status:SetText(status)

    local left = scan.CooldownLeft()
    local sub
    if left > 0 then
        sub = L.NEXT_SCAN_IN:format(ns.FormatCountdown(left))
    elseif ns.db.autoScanNeedsClick then
        sub = L.SCAN_NEEDS_CLICK
    else
        sub = L.SCAN_AVAILABLE
    end
    if ns.Sync.enabled then
        local age = ns.Sync.MarketAge()
        sub = sub .. " · " .. L.SYNCED:format(age and ns.FormatAge(age) or L.NEVER)
    end
    frame.sub:SetText(sub)
    frame.fullScan:SetEnabled(scan.ahOpen and scan.state == "idle" and left == 0)
    frame.quickScan:SetEnabled(scan.ahOpen and scan.state == "idle" and #scan.QuickList() > 0)
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    ns.Safe(updateHeader)
    local def = UI.current
    if def and def.refresh and tabAvailable(def) then ns.Safe(def.refresh, def.content) end
end

local function build()
    frame = UI.Window("BaryshMainFrame", WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()

    local title = UI.Text(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Barysh")
    frame.house = UI.Text(frame, "GameFontHighlightSmall")
    frame.house:SetPoint("LEFT", title, "RIGHT", 12, 0)
    frame.gold = UI.Text(frame, "GameFontHighlightSmall")
    frame.gold:SetPoint("TOPRIGHT", -40, -16)

    frame.status = UI.Text(frame, "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 16, -40)
    frame.sub = UI.Text(frame, "GameFontDisableSmall")
    frame.sub:SetPoint("TOPLEFT", 16, -56)

    frame.settings = UI.Button(frame, L.BTN_SETTINGS, 90, function() UI.ToggleSettings() end, L.TIP_SETTINGS)
    frame.settings:SetPoint("TOPRIGHT", -16, -42)
    frame.save = UI.Button(frame, L.BTN_SAVE, 90, function() ReloadUI() end, L.TIP_SAVE)
    frame.save:SetPoint("RIGHT", frame.settings, "LEFT", -4, 0)
    frame.quickScan = UI.Button(frame, L.BTN_QUICK, 90, function()
        local ok, why = ns.Scan.StartQuick()
        if not ok then ns.Print(L["SCAN_FAIL_" .. why] or why) end
    end, L.TIP_QUICK)
    frame.quickScan:SetPoint("RIGHT", frame.save, "LEFT", -4, 0)
    frame.fullScan = UI.Button(frame, L.BTN_FULL_SCAN, 110, function()
        local ok, why, left = ns.Scan.StartFull("button")
        if not ok then
            ns.Print(why == "cooldown" and L.SCAN_FAIL_cooldown:format(ns.FormatCountdown(left)) or (L["SCAN_FAIL_" .. why] or why))
        end
    end, L.TIP_FULL_SCAN)
    frame.fullScan:SetPoint("RIGHT", frame.quickScan, "LEFT", -4, 0)

    for _, def in ipairs(UI.tabs) do
        local content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", 14, -80)
        content:SetPoint("BOTTOMRIGHT", -14, 14)
        content:Hide()
        def.content = content
        if def.build then ns.Safe(def.build, content) end
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetText(def.label)
        b:SetSize(math.max(64, (b:GetFontString() and b:GetFontString():GetStringWidth() or 40) + 20), 24)
        b:SetScript("OnClick", function() UI.SelectTab(def.id) end)
        def.button = b
    end

    frame:SetScript("OnShow", function()
        layoutTabs()
        if not UI.current or not tabAvailable(UI.current) then
            UI.SelectTab(UI.tabs[1] and UI.tabs[1].id)
        else
            UI.Refresh()
        end
    end)
    -- Countdown and statuses tick once a second while the window is open.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 1 then
            acc = 0
            UI.Refresh()
        end
    end)
end

function UI.Frame()
    if not frame then build() end
    return frame
end

function UI.Toggle()
    local f = UI.Frame()
    f:SetShown(not f:IsShown())
end

-- Opens the window on a tab ("Needs attention" jumps, alerts).
function UI.Show(tabId)
    local f = UI.Frame()
    f:Show()
    if tabId then UI.SelectTab(tabId) end
end

-- Docks the window next to a game window (mailbox) and opens a tab; HideNear closes it again.
function UI.ShowNear(anchor, tabId)
    if not anchor then return end
    local f = UI.Frame()
    if f:IsShown() and not f.dockedTo then
        if tabId then UI.SelectTab(tabId) end
        return
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    f.dockedTo = anchor
    UI.Show(tabId)
end

function UI.HideNear(anchor)
    local f = UI.Frame()
    if f.dockedTo == anchor then
        f.dockedTo = nil
        f:Hide()
    end
end

-- Docking to the auction house window.
function UI.OnAuctionHouse(open)
    local f = UI.Frame()
    if open then
        if AuctionHouseFrame then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
        end
        f:Show()
    elseif not open and f.dockedOpen then
        f:Hide()
    end
    f.dockedOpen = open
end

function UI.ModulesChanged()
    if frame then
        layoutTabs()
        if UI.current and not tabAvailable(UI.current) then UI.SelectTab(UI.tabs[1].id) end
    end
end

-- Minimap button: plain button on the minimap ring, drag to move.
function UI.CreateMinimapButton()
    if UI.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "BaryshMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    local function place()
        local a = math.rad(ns.settings.minimap.angle or 200)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
    end
    place()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() UI.Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Barysh")
        GameTooltip:AddLine(L.MINIMAP_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetShown(not ns.settings.minimap.hidden)
    UI.minimapButton = b
end
