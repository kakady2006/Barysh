local _, ns = ...

-- Small building blocks in the style of the standard Blizzard UI.
local UI = {}
ns.UI = UI

UI.COLOR = {
    gold = { 1, 0.82, 0 },
    text = { 0.93, 0.9, 0.84 },
    muted = { 0.66, 0.63, 0.57 },
    profit = { 0.12, 1, 0 },
    risk = { 1, 0.69, 0 },
    loss = { 1, 0.35, 0.29 },
}

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

function UI.Window(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    f.close = close
    tinsert(UISpecialFrames, name)
    return f
end

function UI.Text(parent, template, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if r then fs:SetTextColor(r, g, b) end
    fs:SetJustifyH("LEFT")
    return fs
end

function UI.Button(parent, text, width, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    b:SetScript("OnClick", function(self, button) ns.Safe(onClick, self, button) end)
    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

-- A list of `rows` lines with an optional icon; fill with list:SetData({ {icon=, cols={...}}, ... }).
-- columns = { {width =, justify = "LEFT"|"RIGHT"}, ... }
function UI.List(parent, columns, rows, rowHeight)
    local list = CreateFrame("Frame", nil, parent)
    list.rows = {}
    rowHeight = rowHeight or 22
    for i = 1, rows do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", list, "RIGHT")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 4, rowHeight - 4)
        row.icon:SetPoint("LEFT", 2, 0)
        row.cols = {}
        local x = rowHeight + 2
        for c, col in ipairs(columns) do
            local fs = UI.Text(row, "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(col.width)
            fs:SetJustifyH(col.justify or "LEFT")
            fs:SetWordWrap(false)
            row.cols[c] = fs
            x = x + col.width + 6
        end
        list.rows[i] = row
    end
    function list:SetData(data)
        for i, row in ipairs(self.rows) do
            local d = data[i]
            if d then
                row.icon:SetTexture(d.icon)
                row.icon:SetShown(d.icon ~= nil)
                for c, fs in ipairs(row.cols) do fs:SetText(d.cols[c] or "") end
                row.data = d
                row:Show()
            else
                row.data = nil
                row:Hide()
            end
        end
    end
    return list
end

function UI.Colorize(text, color)
    local c = UI.COLOR[color]
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end
