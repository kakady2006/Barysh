local _, ns = ...

-- Building blocks in the Barysh look (the design in barysh-design): dark flat panels with a bronze edge,
-- gold headings, red main buttons, dark secondary buttons, filter chips, coloured tags, item tables.
local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.COLOR = {
    gold = { 1, 0.82, 0 },
    text = { 0.93, 0.9, 0.84 },
    muted = { 0.66, 0.63, 0.57 },
    profit = { 0.12, 1, 0 },
    risk = { 1, 0.69, 0 },
    loss = { 1, 0.35, 0.29 },
    blue = { 0.3, 0.6, 1 },
    -- surfaces
    bg = { 0.055, 0.047, 0.039 },
    card = { 0.075, 0.063, 0.05 },
    edge = { 0.49, 0.42, 0.28 },
    line = { 0.23, 0.19, 0.13 },
    rowLine = { 0.12, 0.1, 0.075 },
    chip = { 0.094, 0.078, 0.059 },
    chipOn = { 0.165, 0.13, 0.078 },
    chipEdgeOn = { 0.54, 0.44, 0.25 },
    input = { 0.03, 0.025, 0.02 },
}

-- Tag colours { edge, text } by kind: deal types, ledger operations, states.
UI.TAG = {
    disenchant = { { 0.42, 0.31, 0.63 }, { 0.78, 0.7, 1 } },
    resale = { { 0.25, 0.43, 0.56 }, { 0.62, 0.82, 1 } },
    stock = { { 0.48, 0.38, 0.19 }, { 1, 0.82, 0.48 } },
    craft = { { 0.25, 0.48, 0.27 }, { 0.62, 0.91, 0.65 } },
    arbitrage = { { 0.54, 0.29, 0.18 }, { 1, 0.7, 0.54 } },
    easy = { { 0.64, 0.51, 0.25 }, { 1, 0.82, 0 } },
    profit = { { 0.25, 0.48, 0.27 }, { 0.62, 0.91, 0.65 } },
    loss = { { 0.6, 0.25, 0.2 }, { 1, 0.6, 0.5 } },
    risk = { { 0.6, 0.45, 0.15 }, { 1, 0.75, 0.3 } },
    blue = { { 0.25, 0.43, 0.56 }, { 0.62, 0.82, 1 } },
    plain = { { 0.29, 0.24, 0.17 }, { 0.85, 0.81, 0.73 } },
}

local QUALITY_EDGE = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.42, 0.38, 0.32 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

local function rgb(c, a) return c[1], c[2], c[3], a or c[4] or 1 end
UI.RGB = rgb

-- Flat panel: solid background and a thin edge.
function UI.Flat(f, bg, edge, edgeSize)
    if not f.SetBackdrop then
        if not (Mixin and BackdropTemplateMixin) then return end
        Mixin(f, BackdropTemplateMixin)
    end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edgeSize or 1 })
    f:SetBackdropColor(rgb(bg or UI.COLOR.bg))
    f:SetBackdropBorderColor(rgb(edge or UI.COLOR.line))
end

function UI.Text(parent, template, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if r then fs:SetTextColor(r, g, b) end
    fs:SetJustifyH("LEFT")
    return fs
end

-- Gold heading ("Капитал", "Очередь выставления").
function UI.Heading(parent, text)
    local fs = UI.Text(parent, "GameFontNormal")
    fs:SetTextColor(rgb(UI.COLOR.gold))
    fs:SetText(text or "")
    return fs
end

-- Muted small text for hints and footers.
function UI.Hint(parent, text)
    local fs = UI.Text(parent, "GameFontHighlightSmall")
    fs:SetTextColor(rgb(UI.COLOR.muted))
    fs:SetText(text or "")
    return fs
end

-- Horizontal line across a frame at y (from the top).
function UI.Divider(parent, y, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(rgb(color or UI.COLOR.line))
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 0, y)
    t:SetPoint("TOPRIGHT", 0, y)
    return t
end

local function tipScripts(f, tooltip)
    if not tooltip then return end
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(type(tooltip) == "function" and tooltip() or tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Tooltip on hover for any frame.
function UI.Tip(frame, text)
    tipScripts(frame, text)
end

-- Button. style: "primary" (red with gold text: the main action of a screen or row) or nil (dark).
function UI.Button(parent, text, width, onClick, tooltip, style)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 100, 24)
    local primary = style == "primary"
    UI.Flat(b, primary and { 0.48, 0.09, 0.05 } or { 0.18, 0.157, 0.118 }, primary and { 0.17, 0.02, 0.01 } or { 0, 0, 0 })
    local shine = b:CreateTexture(nil, "ARTWORK")
    shine:SetPoint("TOPLEFT", 1, -1)
    shine:SetPoint("TOPRIGHT", -1, -1)
    shine:SetHeight(11)
    shine:SetColorTexture(1, 1, 1, primary and 0.09 or 0.05)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.82, 0, 0.1)
    local fs = b:CreateFontString(nil, "OVERLAY", primary and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetPoint("CENTER", 0, 0)
    b:SetFontString(fs)
    b.style = style
    local function look(self, on)
        fs:SetAlpha(on and 1 or 0.45)
        self:SetAlpha(on and 1 or 0.75)
    end
    hooksecurefunc(b, "SetEnabled", function(self, on) look(self, on and true or false) end)
    hooksecurefunc(b, "Enable", function(self) look(self, true) end)
    hooksecurefunc(b, "Disable", function(self) look(self, false) end)
    b:SetText(text or "")
    b:SetScript("OnClick", function(self, button) ns.Safe(onClick, self, button) end)
    tipScripts(b, tooltip)
    return b
end

-- Filter chip: a small toggle ("Все 42", "Распыл 14"). chip:SetOn(bool).
function UI.Chip(parent, text, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(20)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    function b:SetOn(on)
        self.on = on
        UI.Flat(self, on and UI.COLOR.chipOn or UI.COLOR.chip, on and UI.COLOR.chipEdgeOn or UI.COLOR.line)
        if on then fs:SetTextColor(rgb(UI.COLOR.gold)) else fs:SetTextColor(0.79, 0.76, 0.69) end
    end
    local setText = b.SetText
    function b:SetText(t)
        setText(self, t)
        self:SetWidth(math.max(36, (fs:GetStringWidth() or 30) + 18))
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.06)
    b:SetText(text or "")
    b:SetOn(false)
    b:SetScript("OnClick", function(self) ns.Safe(onClick, self) end)
    tipScripts(b, tooltip)
    return b
end

-- Row of chips. items = { {value, label, tooltip}, ... }; onPick(value).
-- group:Set(value) marks one, group:Label(value, text) renames one, group:SetPoint(...) places the row.
function UI.ChipRow(parent, items, onPick)
    local g = { chips = {}, order = {} }
    local prev
    for _, it in ipairs(items) do
        local value = it[1]
        local chip = UI.Chip(parent, it[2], function() onPick(value) end, it[3])
        chip.value = value
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        g.chips[value] = chip
        g.order[#g.order + 1] = chip
        prev = chip
    end
    function g:SetPoint(...) self.order[1]:SetPoint(...) end
    function g:Set(value)
        for v, chip in pairs(self.chips) do chip:SetOn(v == value) end
    end
    function g:Label(value, text) if self.chips[value] then self.chips[value]:SetText(text) end end
    function g:Last() return self.order[#self.order] end
    return g
end

-- Coloured tag ("Перепродажа", "Распыл"). tag:Set(text, kind) with kind from UI.TAG.
function UI.Tag(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetHeight(16)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")
    function f:Set(text, kind)
        if not text or text == "" then return self:Hide() end
        local c = UI.TAG[kind] or UI.TAG.plain
        UI.Flat(self, kind == "easy" and UI.COLOR.chipOn or { 0, 0, 0, 0 }, c[1])
        self.text:SetTextColor(rgb(c[2]))
        self.text:SetText(text)
        self:SetWidth((self.text:GetStringWidth() or 40) + 12)
        self:Show()
    end
    f:Hide()
    return f
end

-- Card: bordered block with a gold heading; card.body holds the content below the heading.
function UI.Card(parent, title)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Flat(f, UI.COLOR.card, UI.COLOR.line)
    f.title = UI.Heading(f, title)
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 12, title and -32 or -10)
    f.body:SetPoint("BOTTOMRIGHT", -12, 8)
    return f
end

-- Stat card: small caption and a big number ("Вложено 184").
function UI.StatCard(parent, caption)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Flat(f, UI.COLOR.card, UI.COLOR.line)
    f:SetHeight(56)
    f.caption = UI.Hint(f, caption)
    f.caption:SetPoint("TOPLEFT", 10, -8)
    f.value = UI.Text(f, "GameFontHighlightLarge")
    f.value:SetPoint("TOPLEFT", 10, -24)
    f.note = UI.Hint(f, "")
    f.note:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -1)
    function f:Set(value, note)
        self.value:SetText(value or "")
        self.note:SetText(note or "")
    end
    return f
end

-- Label on the left and value on the right at y inside parent. pair:Set(label, value).
function UI.Pair(parent, y)
    local l = UI.Text(parent, "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 0, y)
    local r = UI.Text(parent, "GameFontHighlightSmall")
    r:SetPoint("TOPRIGHT", 0, y)
    r:SetJustifyH("RIGHT")
    local p = { l = l, r = r }
    function p:Set(label, value)
        l:SetText(label or "")
        r:SetText(value or "")
    end
    function p:SetShown(on) l:SetShown(on); r:SetShown(on) end
    return p
end

-- Horizontal bar 0..1 ("доход по занятиям", market depth). bar:SetValue(x).
function UI.Bar(parent, width, height, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height or 8)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.17, 0.13, 0.09, 1)
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(rgb(color or { 0.62, 0.36, 0.86 }))
    function f:SetValue(x)
        x = math.max(0, math.min(1, x or 0))
        fill:SetWidth(math.max(0.001, width * x))
        fill:SetShown(x > 0)
    end
    f:SetValue(0)
    return f
end

-- Window (flat, bronze edge) with "Barysh  sub" title, a close button and a line under the header.
function UI.Window(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    UI.Flat(f, UI.COLOR.bg, UI.COLOR.edge, 2)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    -- Not while it sits inside another window (the auction house tab).
    f:SetScript("OnDragStart", function(self) if not self.embedded then self:StartMoving() end end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- f.onUserClose: called only for the player's click on ×, not for other hides.
    local close = UI.Button(f, "×", 26, function()
        f:Hide()
        if f.onUserClose then ns.Safe(f.onUserClose) end
    end)
    close:SetHeight(22)
    close:SetPoint("TOPRIGHT", -10, -10)
    f.close = close
    f.titleText = UI.Text(f, "GameFontNormalLarge")
    f.titleText:SetTextColor(rgb(UI.COLOR.gold))
    f.titleText:SetPoint("TOPLEFT", 16, -14)
    f.subText = UI.Hint(f, "")
    f.subText:SetPoint("BOTTOMLEFT", f.titleText, "BOTTOMRIGHT", 10, 1)
    function f:SetTitle(main, sub)
        self.titleText:SetText(main or "")
        self.subText:SetText(sub or "")
    end
    f.headerLine = UI.Divider(f, -42)
    tinsert(UISpecialFrames, name)
    return f
end

-- Item table: gold header row, item icon with a quality edge, name with a muted second line,
-- coloured tags and a button per row. Rows are made to fill the height; the mouse wheel scrolls.
-- columns = { { title, width, justify = "LEFT"|"RIGHT", flex = true (takes the free width), tag = true } }
-- opts = { rowHeight, header = false, icons = false, minRows, onSelect = fn(d), onEnter = fn(row, d),
--          button = { width, text = fn(d), enabled = fn(d), shown = fn(d), onClick = fn(d), style = "primary"|"plain" } }
-- Row data: { itemID, icon, quality, cols = { ... }, sub, tagKind = { [col] = kind }, buttonStyle }.
function UI.Table(parent, columns, opts)
    opts = opts or {}
    local rowH = opts.rowHeight or 30
    local headerH = opts.header == false and 0 or 22
    local showIcons = opts.icons ~= false
    local t = CreateFrame("Frame", nil, parent)
    t.rows, t.all, t.offset = {}, {}, 0

    if headerH > 0 then
        t.head = CreateFrame("Frame", nil, t)
        t.head:SetPoint("TOPLEFT")
        t.head:SetPoint("TOPRIGHT")
        t.head:SetHeight(headerH)
        local line = t.head:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(rgb(UI.COLOR.line))
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        t.head.cols = {}
        for c, col in ipairs(columns) do
            local holder = CreateFrame("Frame", nil, t.head)
            holder:SetHeight(headerH)
            local fs = UI.Text(holder, "GameFontNormalSmall")
            fs:SetTextColor(rgb(UI.COLOR.gold))
            fs:SetText(col.title or "")
            fs:SetJustifyH(col.justify or "LEFT")
            fs:SetAllPoints(holder)
            t.head.cols[c] = holder
        end
    end

    -- Fixed columns are placed from the right; the flex column takes what is left.
    local function layoutCells(cells, width, withIcon)
        local right = width - 8 - (opts.button and ((opts.button.width or 70) + 8) or 0)
        local flexIndex
        for c = #columns, 1, -1 do
            local col = columns[c]
            if col.flex then
                flexIndex = c
            else
                local cell = cells[c]
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", cell:GetParent(), "TOPLEFT", right - col.width, 0)
                cell:SetPoint("BOTTOMLEFT", cell:GetParent(), "BOTTOMLEFT", right - col.width, 0)
                cell:SetWidth(col.width)
                right = right - col.width - 8
            end
        end
        if flexIndex then
            local cell = cells[flexIndex]
            local x = 8 + (withIcon and (rowH - 4 + 8) or 0)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", cell:GetParent(), "TOPLEFT", x, 0)
            cell:SetPoint("BOTTOMLEFT", cell:GetParent(), "BOTTOMLEFT", x, 0)
            cell:SetWidth(math.max(40, right - x))
        end
    end

    local function newRow(i)
        local row = CreateFrame("Button", nil, t)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 0, -headerH - (i - 1) * rowH)
        row:SetPoint("RIGHT", t, "RIGHT")
        local line = row:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(rgb(UI.COLOR.rowLine))
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.07)
        row.sel:Hide()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.05)
        row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.iconFrame:SetSize(rowH - 6, rowH - 6)
        row.iconFrame:SetPoint("LEFT", 8, 0)
        UI.Flat(row.iconFrame, { 0.13, 0.11, 0.09 }, QUALITY_EDGE[1])
        row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 1, -1)
        row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.cols, row.tags = {}, {}
        for c, col in ipairs(columns) do
            local holder = CreateFrame("Frame", nil, row)
            local fs = UI.Text(holder, "GameFontHighlightSmall")
            fs:SetJustifyH(col.justify or "LEFT")
            fs:SetWordWrap(false)
            fs:SetPoint("LEFT", holder, "LEFT")
            fs:SetPoint("RIGHT", holder, "RIGHT")
            if col.flex then
                holder.sub = UI.Hint(holder, "")
                holder.sub:SetWordWrap(false)
                holder.sub:SetPoint("TOPLEFT", holder, "LEFT", 0, -1)
                holder.sub:SetPoint("RIGHT", holder, "RIGHT")
            end
            holder.fs = fs
            if col.tag then
                local tag = UI.Tag(holder)
                local side = col.justify == "RIGHT" and "RIGHT" or "LEFT"
                tag:SetPoint(side, holder, side)
                row.tags[c] = tag
            end
            row.cols[c] = holder
        end
        if opts.button then
            local b = UI.Button(row, "", opts.button.width or 70, function(self)
                local d = self:GetParent().data
                if d then opts.button.onClick(d) end
            end, nil, opts.button.style == "plain" and nil or "primary")
            b:SetHeight(math.min(24, rowH - 6))
            b:SetPoint("RIGHT", -6, 0)
            row.button = b
        end
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            t.selected = self.data
            if opts.onSelect then ns.Safe(opts.onSelect, self.data) end
            t:Render()
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
        t.rows[i] = row
        return row
    end

    local function visibleRows()
        local h = t:GetHeight() or 0
        return math.max(opts.minRows or 1, math.floor((h - headerH) / rowH))
    end
    t.VisibleRows = visibleRows

    function t:Layout()
        local w = self:GetWidth() or 0
        if w <= 0 then return end
        if self.head then layoutCells(self.head.cols, w, showIcons) end
        for _, row in ipairs(self.rows) do layoutCells(row.cols, w, showIcons) end
    end

    local function fillRow(row, d)
        local withIcon = showIcons and (d.icon ~= nil or d.itemID ~= nil)
        row.iconFrame:SetShown(withIcon)
        if withIcon then
            row.icon:SetTexture(d.icon or (ns.Items and ns.Items.Texture(d.itemID)) or 134400)
            local q = d.quality
            if q == nil and d.itemID and ns.Items then
                local info = ns.Items.Info(d.itemID)
                q = info and info.quality
            end
            row.iconFrame:SetBackdropBorderColor(rgb(QUALITY_EDGE[q or 1] or QUALITY_EDGE[1]))
        end
        for c, holder in ipairs(row.cols) do
            local text = d.cols and d.cols[c] or ""
            if row.tags[c] then
                holder.fs:SetText("")
                row.tags[c]:Set(text, d.tagKind and d.tagKind[c])
            else
                holder.fs:SetText(text)
            end
            if holder.sub then
                local sub = d.sub or ""
                holder.sub:SetText(sub)
                holder.fs:ClearAllPoints()
                holder.fs:SetPoint(sub ~= "" and "BOTTOMLEFT" or "LEFT", holder, "LEFT", 0, sub ~= "" and 1 or 0)
                holder.fs:SetPoint("RIGHT", holder, "RIGHT")
            end
        end
        row.sel:SetShown(d == t.selected)
        if row.button then
            local b = opts.button
            row.button:SetShown(not b.shown or b.shown(d))
            row.button:SetText(b.text(d))
            row.button:SetEnabled(not b.enabled or b.enabled(d))
        end
    end

    function t:Render()
        local n = visibleRows()
        for i = #self.rows + 1, n do newRow(i) end
        self:Layout()
        self.offset = math.max(0, math.min(self.offset, #self.all - n))
        for i, row in ipairs(self.rows) do
            local d = i <= n and self.all[i + self.offset] or nil
            row.data = d
            if d then
                fillRow(row, d)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    function t:SetData(data)
        self.all = data or {}
        self:Render()
    end

    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #self.all - visibleRows())
        self.offset = math.max(0, math.min(maxOff, self.offset - delta * 3))
        self:Render()
    end)
    t:SetScript("OnSizeChanged", function(self) self:Render() end)
    return t
end

-- Older entry point: a table without a header row and with at least `rows` rows.
function UI.ScrollList(parent, columns, rows, opts)
    opts = opts or {}
    if opts.header == nil then opts.header = false end
    opts.minRows = opts.minRows or rows
    return UI.Table(parent, columns, opts)
end

function UI.Colorize(text, color)
    local c = UI.COLOR[color]
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

-- Checkbox with a label. get() -> bool, set(bool).
function UI.Check(parent, label, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
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
        self.label:SetTextColor(v * 0.93, v * 0.9, v * 0.84)
        self.label:SetText(label .. ((not on and why) and (" — " .. why) or ""))
    end
    if tooltip then UI.Tip(cb, tooltip) end
    cb:Update()
    return cb
end

-- One-line edit box (dark field). onEnter(text) on Enter.
function UI.Edit(parent, width, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 22)
    UI.Flat(e, UI.COLOR.input, UI.COLOR.line)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetScript("OnEnterPressed", function(self)
        if onEnter then ns.Safe(onEnter, self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(rgb(UI.COLOR.chipEdgeOn)) end)
    e:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(rgb(UI.COLOR.line)) end)
    -- Placeholder text while empty.
    e.placeholder = UI.Hint(e, "")
    e.placeholder:SetPoint("LEFT", 6, 0)
    e:HookScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    function e:SetPlaceholder(text) self.placeholder:SetText(text or "") end
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
        self:SetBackdropBorderColor(rgb(UI.COLOR.line))
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
            if v[1] == cur then return self:SetText(v[2] .. "  ▾") end
        end
        self:SetText(values[1][2] .. "  ▾")
    end
    b:Update()
    return b
end

-- Price chart as in the design: gold line (market price), grey line (minimum), blue bars (sold per day).
-- chart:SetValues(prices, minimums, sales); each a list per day/point, nil for gaps.
function UI.Chart(parent, width, height)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetSize(width, height)
    UI.Flat(c, { 0.04, 0.035, 0.03 }, UI.COLOR.line)
    c.grid = {}
    for i = 1, 3 do
        local g = c:CreateTexture(nil, "BACKGROUND")
        g:SetColorTexture(1, 1, 1, 0.05)
        g:SetHeight(1)
        g:SetPoint("LEFT", 34, 0)
        g:SetPoint("RIGHT", -6, 0)
        g:SetPoint("TOP", c, "TOP", 0, -8 - (i - 1) * (height - 30) / 3)
        c.grid[i] = g
        local label = UI.Hint(c, "")
        label:SetPoint("RIGHT", g, "LEFT", -4, 0)
        g.label = label
    end
    c.bars, c.lines = {}, { {}, {} }
    local plotL, plotR, plotT, plotB = 34, 6, 8, 18

    local function segment(set, i, layer, color, thick)
        local seg = set[i]
        if not seg then
            if c.CreateLine then
                seg = c:CreateLine(nil, layer)
                seg:SetThickness(thick)
            else
                seg = c:CreateTexture(nil, layer)
                seg:SetSize(thick, thick)
            end
            seg:SetColorTexture(rgb(color))
            set[i] = seg
        end
        return seg
    end

    function c:SetValues(prices, minimums, sales)
        prices, minimums, sales = prices or {}, minimums or {}, sales or {}
        local n = math.max(#prices, #minimums, #sales, 1)
        local top, low = 0, math.huge
        for i = 1, n do
            for _, v in ipairs({ prices[i], minimums[i] }) do
                if v then top = math.max(top, v); low = math.min(low, v) end
            end
        end
        if low == math.huge then low = 0 end
        if top <= low then top = low + 1 end
        local pad = (top - low) * 0.15
        top, low = top + pad, math.max(0, low - pad)
        local w = (self:GetWidth() or width) - plotL - plotR
        local h = (self:GetHeight() or height) - plotT - plotB
        local function x(i) return plotL + (n == 1 and w / 2 or (i - 1) / (n - 1) * w) end
        local function y(v) return plotB + (v - low) / (top - low) * h end
        for i, g in ipairs(self.grid) do
            local v = top - (i - 1) * (top - low) / 3
            g.label:SetText(ns.FormatMoney(v))
        end
        -- sales bars, scaled to the lower third
        local smax = 0
        for i = 1, n do if sales[i] and sales[i] > smax then smax = sales[i] end end
        local bw = math.max(2, w / n * 0.6)
        for i = 1, math.max(n, #self.bars) do
            local bar = self.bars[i]
            if not bar then
                bar = self:CreateTexture(nil, "BORDER")
                bar:SetColorTexture(0.2, 0.3, 0.45, 0.8)
                self.bars[i] = bar
            end
            local v = i <= n and sales[i]
            bar:ClearAllPoints()
            if v and smax > 0 then
                bar:SetPoint("BOTTOMLEFT", x(i) - bw / 2, plotB)
                bar:SetSize(bw, math.max(1, v / smax * h * 0.35))
                bar:Show()
            else
                bar:Hide()
            end
        end
        for s, series in ipairs({ prices, minimums }) do
            local set = self.lines[s]
            local color = s == 1 and UI.COLOR.gold or { 0.75, 0.75, 0.75, 0.8 }
            local k = 0
            for i = 1, n - 1 do
                local a, b = series[i], series[i + 1]
                if a and b then
                    k = k + 1
                    local seg = segment(set, k, s == 1 and "OVERLAY" or "ARTWORK", color, s == 1 and 2 or 1)
                    if seg.SetStartPoint then
                        seg:SetStartPoint("BOTTOMLEFT", self, x(i), y(a))
                        seg:SetEndPoint("BOTTOMLEFT", self, x(i + 1), y(b))
                    else
                        seg:ClearAllPoints()
                        seg:SetPoint("CENTER", self, "BOTTOMLEFT", x(i), y(a))
                    end
                    seg:Show()
                end
            end
            for i = k + 1, #set do set[i]:Hide() end
        end
        self.top = top
    end
    return c
end

-- Window with a multi-line text box: export (text selected for Ctrl+C) and import (paste).
function UI.TextWindow()
    if UI.textWindow then return UI.textWindow end
    local f = UI.Window("BaryshTextWindow", 540, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f.title = f.titleText
    f.hint = UI.Hint(f, "")
    f.hint:SetPoint("TOPLEFT", 16, -52)
    f.hint:SetWidth(500)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.Flat(box, UI.COLOR.input, UI.COLOR.line)
    box:SetPoint("TOPLEFT", 16, -72)
    box:SetPoint("BOTTOMRIGHT", -16, 48)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(470)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    f.result = UI.Text(f, "GameFontHighlightSmall")
    f.result:SetPoint("BOTTOMLEFT", 16, 18)
    f.result:SetWidth(330)
    f.action = UI.Button(f, "", 150, function()
        if f.onAction then f.onAction(edit:GetText()) end
    end, nil, "primary")
    f.action:SetPoint("BOTTOMRIGHT", -16, 14)
    f:Hide()
    UI.textWindow = f
    return f
end

-- Shows text to copy with Ctrl+C.
function UI.ShowText(title, text, hint)
    local f = UI.TextWindow()
    f:SetTitle("Barysh", title)
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
    f:SetTitle("Barysh", title)
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

-- Lines of text under each other (simple lists inside cards).
function UI.Lines(parent, n, width, template)
    local out = {}
    for i = 1, n do
        local fs = UI.Text(parent, template or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
        fs:SetWidth(width or 270)
        fs:SetWordWrap(false)
        out[i] = fs
    end
    return out
end

function UI.SetLines(fsList, texts)
    for i, fs in ipairs(fsList) do fs:SetText(texts[i] or "") end
end
