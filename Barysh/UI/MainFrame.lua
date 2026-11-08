local _, ns = ...

local UI = ns.UI
local L = ns.L

-- Main window. Two ways to show it:
--   inside the auction house (the "Barysh" tab, UI/AuctionTab.lua): it fills the auction house, no frame of
--   its own, the sections are chips under the header (like other auction house addons);
--   on its own (minimap button, mailbox): a window with the sections as tabs under it (barysh-design).
-- A disabled module removes its section.
local WIDTH, HEIGHT = 780, 540
UI.WIDTH, UI.HEIGHT = WIDTH, HEIGHT

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

-- Section switches: chips (inside the auction house) and tabs under the window (on its own).
local function layoutTabs()
    local prevChip, prevTab
    for _, def in ipairs(UI.tabs) do
        local chip, tab = def.chip, def.button
        if tabAvailable(def) then
            chip:ClearAllPoints()
            if prevChip then chip:SetPoint("LEFT", prevChip, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -94) end
            tab:ClearAllPoints()
            if prevTab then tab:SetPoint("LEFT", prevTab, "RIGHT", 2, 0) else tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, 1) end
            chip:SetShown(frame.embedded)
            tab:SetShown(not frame.embedded)
            prevChip, prevTab = chip, tab
        else
            chip:Hide()
            tab:Hide()
        end
    end
end

local function placeContent()
    for _, def in ipairs(UI.tabs) do
        local c = def.content
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, frame.embedded and -124 or -96)
        c:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    end
    frame.navLine:SetShown(frame.embedded)
end

function UI.SelectTab(id)
    if not frame then return end
    for _, def in ipairs(UI.tabs) do
        local on = def.id == id and tabAvailable(def)
        def.content:SetShown(on)
        def.chip:SetOn(on)
        def.button:SetOn(on)
        if on then UI.current = def end
    end
    UI.Refresh()
end

local function houseName()
    local key = ns.Prices.DefaultKey()
    if ns.AH.IsNeutralKey(key) then return L.HOUSE_NEUTRAL end
    return UnitFactionGroup("player") == "Alliance" and L.HOUSE_ALLIANCE or L.HOUSE_HORDE
end

local function updateHeader()
    local scan = ns.Scan
    local section = UI.current and UI.current.label or ""
    frame:SetTitle("Barysh", section .. "  ·  " .. L.HOUSE:format(houseName()))
    frame.gold:SetText(L.FREE_GOLD:format(ns.FormatMoney(GetMoney())))

    local h = ns.db.ah[ns.Prices.DefaultKey()]
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
        sub = sub .. "  ·  " .. L.SYNCED:format(age and ns.FormatAge(age) or L.NEVER)
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

-- Inside the auction house (true) or on its own (false).
function UI.SetEmbedded(on)
    local f = UI.Frame()
    f.embedded = on and true or nil
    if on then
        f:SetBackdropBorderColor(0, 0, 0, 0)
        f:SetBackdropColor(UI.RGB(UI.COLOR.bg))
    else
        UI.Flat(f, UI.COLOR.bg, UI.COLOR.edge, 2)
        f:SetSize(WIDTH, HEIGHT)
    end
    f.close:SetShown(not on)
    placeContent()
    layoutTabs()
end

local function sectionTab(parent, text, onClick)
    -- Tab under the window: like a chip, flat top edge (barysh-design .tab).
    local b = UI.Chip(parent, text, onClick)
    b:SetHeight(26)
    return b
end

local function build()
    frame = UI.Window("BaryshMainFrame", WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()

    frame.gold = UI.Text(frame, "GameFontHighlightSmall")
    frame.gold:SetPoint("RIGHT", frame.close, "LEFT", -96, 0)
    frame.onUserClose = function() UI.OnMainUserClose() end
    frame.settings = UI.Button(frame, L.BTN_SETTINGS, 84, function() UI.ToggleSettings() end, L.TIP_SETTINGS)
    frame.settings:SetHeight(22)
    frame.settings:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)

    -- scan status and actions
    frame.status = UI.Text(frame, "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 16, -52)
    frame.sub = UI.Hint(frame, "")
    frame.sub:SetPoint("TOPLEFT", 16, -68)
    frame.save = UI.Button(frame, L.BTN_SAVE, 96, function() ReloadUI() end, L.TIP_SAVE)
    frame.save:SetPoint("TOPRIGHT", -14, -54)
    frame.quickScan = UI.Button(frame, L.BTN_QUICK, 86, function()
        local ok, why = ns.Scan.StartQuick()
        if not ok then ns.Print(L["SCAN_FAIL_" .. why] or why) end
    end, L.TIP_QUICK)
    frame.quickScan:SetPoint("RIGHT", frame.save, "LEFT", -6, 0)
    frame.fullScan = UI.Button(frame, L.BTN_FULL_SCAN, 112, function()
        local ok, why, left = ns.Scan.StartFull("button")
        if not ok then
            ns.Print(why == "cooldown" and L.SCAN_FAIL_cooldown:format(ns.FormatCountdown(left)) or (L["SCAN_FAIL_" .. why] or why))
        end
    end, L.TIP_FULL_SCAN, "primary")
    frame.fullScan:SetPoint("RIGHT", frame.quickScan, "LEFT", -6, 0)
    UI.Divider(frame, -86)
    frame.navLine = UI.Divider(frame, -118)

    for _, def in ipairs(UI.tabs) do
        local content = CreateFrame("Frame", nil, frame)
        content:Hide()
        def.content = content
        def.chip = UI.Chip(frame, def.label, function() UI.SelectTab(def.id) end)
        def.button = sectionTab(frame, def.label, function() UI.SelectTab(def.id) end)
    end
    placeContent()
    for _, def in ipairs(UI.tabs) do
        if def.build then ns.Safe(def.build, def.content) end
    end

    frame:SetScript("OnShow", function()
        layoutTabs()
        if not UI.current or not tabAvailable(UI.current) then
            UI.SelectTab(UI.tabs[1] and UI.tabs[1].id)
        else
            UI.SelectTab(UI.current.id)
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
    if f.embedded then return end -- the auction house tab owns it now
    -- At the auction house the minimap button opens the Barysh tab.
    if not f:IsShown() and ns.Scan and ns.Scan.ahOpen and UI.SelectAuctionTab and UI.SelectAuctionTab() then return end
    f.autoOpened = nil
    f:SetShown(not f:IsShown())
end

-- The player closed with × a window that had opened by itself: it no longer opens by itself
-- (setting "Open by itself", the chat line says where).
function UI.OnMainUserClose()
    if not frame.autoOpened then return end
    frame.autoOpened, frame.dockedTo = nil, nil
    if ns.settings.autoOpen then
        ns.settings.autoOpen = false
        ns.Print(L.AUTO_OPEN_OFF)
    end
end

-- Opens the window on a tab ("Needs attention" jumps, alerts).
function UI.Show(tabId)
    local f = UI.Frame()
    f:Show()
    if tabId then UI.SelectTab(tabId) end
end

-- Docks the window next to a game window (mailbox) and opens a tab; HideNear closes it again.
-- Other addons dock their own panels to the right of the same game window (Mastercraft's mail helper):
-- Barysh goes to the right of the rightmost of them instead of on top.
local function dockTarget(f, anchor)
    local target, edge = anchor, anchor.GetRight and anchor:GetRight()
    if not edge or not UIParent or not UIParent.GetChildren then return anchor end
    local start = edge
    -- The game's protected frames are forbidden to addons: skip them, and never let one frame break the loop.
    local function besideAnchor(c)
        if not c:IsShown() then return nil end
        for i = 1, c:GetNumPoints() do
            local _, rel = c:GetPoint(i)
            if rel == anchor then
                local left, right = c:GetLeft(), c:GetRight()
                if left and right and left >= start - 2 then return right end
                return nil
            end
        end
    end
    for _, c in ipairs({ UIParent:GetChildren() }) do
        local forbidden = c.IsForbidden and c:IsForbidden()
        if c ~= f and not forbidden then
            local ok, right = pcall(besideAnchor, c)
            if ok and right and right > edge then target, edge = c, right end
        end
    end
    return target
end

local function dock(f, anchor)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", dockTarget(f, anchor), "TOPRIGHT", 4, 0)
end

-- Their panels may appear a moment after the game window: look again shortly after.
local function redockSoon(f, anchor)
    C_Timer.After(0.3, function()
        if f:IsShown() and f.dockedTo == anchor then
            ns.Safe(dock, f, anchor)
        end
    end)
end

-- A window opened by itself next to a game window closes with it, whatever event the game sends:
-- the game window's OnHide is watched too. A window the player had open already stays open.
local watched = {}
local function watchAnchor(anchor)
    if watched[anchor] or not anchor.HookScript then return end
    watched[anchor] = true
    anchor:HookScript("OnHide", function() ns.Safe(UI.HideNear, anchor) end)
end

function UI.ShowNear(anchor, tabId)
    if not anchor then return end
    local f = UI.Frame()
    if f.embedded then return end -- shown inside the auction house
    if f:IsShown() and not f.dockedTo then
        if tabId then UI.SelectTab(tabId) end
        return
    end
    if not ns.settings.autoOpen then return end
    dock(f, anchor)
    f.dockedTo = anchor
    f.autoOpened = true
    watchAnchor(anchor)
    UI.Show(tabId)
    redockSoon(f, anchor)
end

-- Opening by itself (deal alert): at the auction house on the Barysh page there, so it goes away with it.
function UI.ShowAuto(tabId)
    if not ns.settings.autoOpen then return end
    if ns.Scan and ns.Scan.ahOpen and UI.SelectAuctionTab and UI.SelectAuctionTab() then
        if tabId then UI.SelectTab(tabId) end
        return
    end
    local shown = UI.Frame():IsShown()
    UI.Show(tabId)
    if not shown then frame.autoOpened = true end
end

function UI.HideNear(anchor)
    local f = UI.Frame()
    if f.dockedTo == anchor then
        f.dockedTo, f.autoOpened = nil, nil
        f:Hide()
    end
end

-- The auction house gets a "Barysh" tab; the window lives inside it while that tab is selected.
function UI.OnAuctionHouse(open)
    if open and UI.CreateAuctionTab then UI.CreateAuctionTab() end
    if not open and UI.CloseAuctionTab then UI.CloseAuctionTab() end
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
