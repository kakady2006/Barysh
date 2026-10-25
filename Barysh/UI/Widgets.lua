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

-- Tooltip on hover for any frame.
function UI.Tip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Checkbox with a label. get() -> bool, set(bool).
function UI.Check(parent, label, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = UI.Text(cb, "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self) ns.Safe(set, self:GetChecked() and true or false) end)
    function cb:Update()
        self:SetChecked(get() and true or false)
    end
    -- Dependent options are shown inactive with an explanation.
    function cb:SetActive(on, why)
        self:SetEnabled(on)
        local v = on and 1 or 0.5
        self.label:SetTextColor(v, v, v)
        self.label:SetText(label .. ((not on and why) and (" — " .. why) or ""))
    end
    if tooltip then UI.Tip(cb, tooltip) end
    cb:Update()
    return cb
end

-- One-line edit box. onEnter(text) on Enter.
function UI.Edit(parent, width, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetScript("OnEnterPressed", function(self)
        if onEnter then ns.Safe(onEnter, self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

-- "12з 50с", "12g50s", "12.5" (gold) -> copper; nil if not a price.
function UI.ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return nil end
    local n = tonumber((text:gsub(",", ".")))
    if n then return math.floor(n * 10000 + 0.5) end
    local total, found = 0, false
    for num, unit in text:gmatch("(%d+)([^%d]+)") do
        local v = tonumber(num)
        if unit == "g" or unit == "з" then
            total, found = total + v * 10000, true
        elseif unit == "s" or unit == "с" then
            total, found = total + v * 100, true
        elseif unit == "c" or unit == "м" then
            total, found = total + v, true
        end
    end
    return found and total or nil
end

-- Money edit box, in gold. get() -> copper or nil, set(copper or nil).
function UI.MoneyEdit(parent, width, get, set)
    local e = UI.Edit(parent, width, function(text) set(UI.ParseMoney(text)) end)
    function e:Update()
        local v = get()
        self:SetText(v and ("%g"):format(v / 10000) or "")
    end
    e:SetScript("OnEditFocusLost", function(self)
        local v = UI.ParseMoney(self:GetText())
        if v ~= get() then ns.Safe(set, v) end
        self:Update()
    end)
    e:Update()
    return e
end

-- Button that cycles through values (instead of a dropdown). values = { {value, label}, ... }
function UI.Cycle(parent, width, values, get, set, tooltip)
    local b = UI.Button(parent, "", width, function(self)
        local cur = get()
        local idx = 1
        for i, v in ipairs(values) do
            if v[1] == cur then idx = i end
        end
        set(values[idx % #values + 1][1])
        self:Update()
    end, tooltip)
    function b:Update()
        local cur = get()
        for _, v in ipairs(values) do
            if v[1] == cur then return self:SetText(v[2]) end
        end
        self:SetText(values[1][2])
    end
    b:Update()
    return b
end

-- A list with mouse-wheel scrolling, row selection and an optional button per row.
-- opts = { rowHeight, onSelect = fn(d), onEnter = fn(row, d),
--          button = { width, text = fn(d), enabled = fn(d), shown = fn(d), onClick = fn(d) } }
function UI.ScrollList(parent, columns, rows, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or 22
    local list = UI.List(parent, columns, rows, rowHeight)
    list.offset = 0
    list.all = {}
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #self.all - #self.rows)
        self.offset = math.max(0, math.min(maxOff, self.offset - delta * 3))
        self:Render()
    end)
    for _, row in ipairs(list.rows) do
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(1, 0.82, 0, 0.15)
        sel:Hide()
        row.sel = sel
        if opts.button then
            local b = UI.Button(row, "", opts.button.width or 70, function(self)
                local d = self:GetParent().data
                if d then opts.button.onClick(d) end
            end)
            b:SetHeight(rowHeight - 2)
            b:SetPoint("RIGHT", -2, 0)
            row.button = b
        end
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            list.selected = self.data
            if opts.onSelect then ns.Safe(opts.onSelect, self.data) end
            list:Render()
        end)
        row:SetScript("OnEnter", function(self)
            local d = self.data
            if not d then return end
            if opts.onEnter then
                ns.Safe(opts.onEnter, self, d)
            elseif d.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.itemID) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local setData = list.SetData
    function list:Render()
        local view = {}
        for i = 1, #self.rows do view[i] = self.all[i + self.offset] end
        setData(self, view)
        for _, row in ipairs(self.rows) do
            local d = row.data
            row.sel:SetShown(d ~= nil and d == self.selected)
            if row.button then
                row.button:SetShown(d ~= nil and (not opts.button.shown or opts.button.shown(d)))
                if d then
                    row.button:SetText(opts.button.text(d))
                    row.button:SetEnabled(not opts.button.enabled or opts.button.enabled(d))
                end
            end
        end
    end
    function list:SetData(data)
        self.all = data
        self.offset = math.min(self.offset, math.max(0, #data - #self.rows))
        self:Render()
    end
    return list
end

-- Bar chart: values = { number or nil, ... }; marks = optional second series drawn as thin lines.
function UI.Chart(parent, width, height, color)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    c.bars, c.marks = {}, {}
    color = color or UI.COLOR.gold
    local function texture(list, i, layer, r, g, b)
        local t = list[i]
        if not t then
            t = c:CreateTexture(nil, layer)
            t:SetColorTexture(r, g, b, 0.85)
            list[i] = t
        end
        return t
    end
    function c:SetValues(values, marks)
        local n = math.max(#values, 1)
        local top = 0
        for i = 1, n do
            if values[i] and values[i] > top then top = values[i] end
            if marks and marks[i] and marks[i] > top then top = marks[i] end
        end
        local w = width / n
        for i = 1, math.max(n, #self.bars) do
            local bar = texture(self.bars, i, "ARTWORK", color[1], color[2], color[3])
            local mark = texture(self.marks, i, "OVERLAY", 0.8, 0.8, 0.8)
            local v = i <= n and values[i]
            bar:ClearAllPoints()
            if v and top > 0 then
                bar:SetPoint("BOTTOMLEFT", (i - 1) * w + 1, 0)
                bar:SetSize(math.max(1, w - 2), math.max(1, v / top * height))
                bar:Show()
            else
                bar:Hide()
            end
            local m = marks and i <= n and marks[i]
            mark:ClearAllPoints()
            if m and top > 0 then
                mark:SetPoint("BOTTOMLEFT", (i - 1) * w + 1, m / top * height)
                mark:SetSize(math.max(1, w - 2), 2)
                mark:Show()
            else
                mark:Hide()
            end
        end
        self.top = top
    end
    return c
end

-- Window with a multi-line text box: export (text selected for Ctrl+C) and import (paste).
function UI.TextWindow()
    if UI.textWindow then return UI.textWindow end
    local f = UI.Window("BaryshTextWindow", 520, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f.title = UI.Text(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.hint = UI.Text(f, "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", 16, -32)
    f.hint:SetWidth(480)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -52)
    scroll:SetPoint("BOTTOMRIGHT", -34, 48)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(460)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    f.result = UI.Text(f, "GameFontHighlightSmall")
    f.result:SetPoint("BOTTOMLEFT", 16, 18)
    f.result:SetWidth(330)
    f.action = UI.Button(f, "", 150, function()
        if f.onAction then f.onAction(edit:GetText()) end
    end)
    f.action:SetPoint("BOTTOMRIGHT", -16, 14)
    f:Hide()
    UI.textWindow = f
    return f
end

-- Shows text to copy with Ctrl+C.
function UI.ShowText(title, text, hint)
    local f = UI.TextWindow()
    f.title:SetText(title)
    f.hint:SetText(hint or ns.L.COPY_HINT)
    f.edit:SetText(text or "")
    f.result:SetText("")
    f.action:Hide()
    f.onAction = nil
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Asks for text; onAction(text, window) when the button is pressed.
function UI.AskText(title, hint, buttonText, onAction)
    local f = UI.TextWindow()
    f.title:SetText(title)
    f.hint:SetText(hint or "")
    f.edit:SetText("")
    f.result:SetText("")
    f.action:SetText(buttonText)
    f.action:Show()
    f.onAction = function(text) ns.Safe(onAction, text, f) end
    f:Show()
    f.edit:SetFocus()
end

function UI.PerDay(v)
    if not v then return "—" end
    if v >= 10 then return ("%d"):format(math.floor(v + 0.5)) end
    return ("%.1f"):format(v)
end

function UI.Days(d)
    if not d then return "—" end
    if d < 1 then return ns.L.HOURS_SHORT:format(math.max(1, math.floor(d * 24 + 0.5))) end
    return ns.L.DAYS_SHORT:format(d)
end

function UI.Percent(x)
    if not x then return "—" end
    return ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5)))
end
