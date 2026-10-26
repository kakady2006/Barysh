local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items

-- Settings window. TZ: "Настройки": groups with a checkbox on the left, the group's functions
-- in blocks on the right, profile in the header, "Reset group" and "Done" at the bottom.
-- Dependent options are shown inactive with an explanation.

local WIDTH, HEIGHT = 660, 540

local GROUP_KEYS = {
    core = { "scan", "tooltip", "summaryDays", "staleHours", "minimap" },
    trade = { "deals", "selling", "vendor", "market" },
    craft = { "disenchant", "recipes", "trade" },
    money = { "mail" },
    service = {},
}

local function set(path, value)
    local t = ns.settings
    for i = 1, #path - 1 do t = t[path[i]] end
    t[path[#path]] = value
    if ns.Prices then ns.Prices.Invalidate() end
    UI.Refresh()
end

local function get(path)
    local t = ns.settings
    for i = 1, #path - 1 do t = t[path[i]] end
    return t[path[#path]]
end

-- Vertical layout on a scroll child --------------------------------------------------------

local Layout = {}
Layout.__index = Layout

local function newLayout(parent)
    return setmetatable({ parent = parent, y = 0, items = {} }, Layout)
end

function Layout:Header(text)
    local fs = UI.Text(self.parent, "GameFontNormal")
    fs:SetPoint("TOPLEFT", 0, -self.y - 4)
    fs:SetText(text)
    self.y = self.y + 24
end

function Layout:Note(text)
    local fs = UI.Text(self.parent, "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 4, -self.y)
    fs:SetWidth(440)
    fs:SetText(text)
    self.y = self.y + 16
end

function Layout:Add(widget, height, x)
    widget:SetPoint("TOPLEFT", x or 0, -self.y)
    self.items[#self.items + 1] = widget
    self.y = self.y + (height or 24)
    return widget
end

-- Checkbox bound to a settings path; active() -> bool, why
function Layout:Check(label, path, tooltip, active)
    local cb = UI.Check(self.parent, label, function() return get(path) end, function(v) set(path, v) end, tooltip)
    cb.active = active
    return self:Add(cb, 24, 8)
end

-- Module on/off checkbox.
function Layout:Module(name, tooltip, requires)
    local m = ns.modules[name]
    local cb = UI.Check(self.parent, L["MODULE_" .. name],
        function() return m.enabled end,
        function(v) ns.SetModuleEnabled(name, v); UI.RefreshSettings() end, tooltip or L["MODTIP_" .. name])
    if not m.canDisable then cb.active = function() return false, L.CANNOT_DISABLE end end
    if requires then
        cb.active = function()
            if ns.IsModuleWanted(requires) or ns.IsModuleEnabled(requires) then return true end
            return false, L.NEEDS_MODULE:format(L["MODULE_" .. requires])
        end
    end
    return self:Add(cb, 26)
end

-- Label + widget on one row.
function Layout:Row(label, widget, tooltip)
    local fs = UI.Text(self.parent, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 12, -self.y - 4)
    fs:SetText(label)
    widget:SetPoint("TOPLEFT", 230, -self.y)
    if tooltip then UI.Tip(widget, tooltip) end
    self.items[#self.items + 1] = widget
    self.y = self.y + 26
    return widget
end

function Layout:Money(label, path, tooltip)
    return self:Row(label, UI.MoneyEdit(self.parent, 80, function() return get(path) end,
        function(v) set(path, v or 0) end), tooltip)
end

function Layout:Cycle(label, path, values, tooltip)
    return self:Row(label, UI.Cycle(self.parent, 150, values, function() return get(path) end,
        function(v) set(path, v) end), tooltip)
end

function Layout:Button(label, onClick, tooltip, width)
    local b = UI.Button(self.parent, label, width or 180, onClick, tooltip)
    return self:Add(b, 26, 8)
end

function Layout:Update()
    for _, w in ipairs(self.items) do
        if w.Update then w:Update() end
        if w.SetActive then
            local on, why = true, nil
            if w.active then on, why = w.active() end
            w:SetActive(on, why)
        end
    end
end

-- Groups --------------------------------------------------------------------------------------

local function moduleOn(name)
    return function()
        if ns.IsModuleEnabled(name) then return true end
        return false, L.NEEDS_MODULE:format(L["MODULE_" .. name])
    end
end

local build = {}

function build.core(l)
    l:Header(L.SET_SCAN)
    l:Check(L.SET_SCAN_BUTTON, { "scan", "onButton" })
    l:Check(L.SET_SCAN_OPEN, { "scan", "onOpen" }, L.SET_SCAN_OPEN_TIP)
    l:Check(L.SET_SCAN_EVERY15, { "scan", "every15" }, L.SET_SCAN_EVERY15_TIP)
    l:Check(L.SET_SCAN_QUICK, { "scan", "quick" })
    l:Cycle(L.SET_SUMMARY_DAYS, { "summaryDays" }, { { 3, "3" }, { 7, "7" }, { 14, "14" } }, L.SET_SUMMARY_DAYS_TIP)
    l:Cycle(L.SET_STALE, { "staleHours" }, { { 12, "12 " .. L.UNIT_H }, { 24, "24 " .. L.UNIT_H }, { 48, "48 " .. L.UNIT_H } })
    l:Header(L.SET_TOOLTIP)
    l:Module("Tooltip")
    l:Header(L.SET_MINIMAP)
    l:Check(L.SET_MINIMAP_HIDE, { "minimap", "hidden" })
end

function build.trade(l)
    l:Header(L.MODULE_Deals)
    l:Module("Deals")
    for _, kind in ipairs(ns.Deals.TYPES) do
        local active = moduleOn("Deals")
        if kind == "arbitrage" then
            active = function()
                if not ns.IsModuleEnabled("Deals") then return false, L.NEEDS_MODULE:format(L.MODULE_Deals) end
                if not ns.IsModuleEnabled("Neutral") then return false, L.NEEDS_MODULE:format(L.MODULE_Neutral) end
                return true
            end
        elseif kind == "stock" then
            active = function()
                if not ns.IsModuleEnabled("Deals") then return false, L.NEEDS_MODULE:format(L.MODULE_Deals) end
                if not ns.IsModuleEnabled("Stock") then return false, L.NEEDS_MODULE:format(L.MODULE_Stock) end
                return true
            end
        end
        l:Check(L["DEAL_" .. kind], { "deals", "types", kind }, L["DEALTIP_" .. kind], active)
    end
    l:Money(L.SET_MIN_PROFIT, { "deals", "minProfit" }, L.SET_MIN_PROFIT_TIP)
    l:Cycle(L.SET_MAX_DAYS, { "deals", "maxDaysToSell" },
        { { 0, L.NO_LIMIT }, { 1, "1" }, { 3, "3" }, { 7, "7" }, { 14, "14" }, { 30, "30" } })
    l:Cycle(L.SET_CAUTION, { "deals", "caution" },
        { { "normal", L.CAUTION_normal }, { "careful", L.CAUTION_careful }, { "bold", L.CAUTION_bold } }, L.SET_CAUTION_TIP)
    l:Money(L.SET_SOUND_FROM, { "deals", "soundFrom" })
    l:Check(L.SET_POPUP, { "deals", "popup" }, nil, moduleOn("Deals"))
    l:Check(L.SET_CRASH, { "deals", "crashAlert" }, nil, moduleOn("Deals"))

    l:Header(L.MODULE_Selling)
    l:Module("Selling")
    l:Cycle(L.SET_STACK, { "selling", "stack" }, { { 0, L.STACK_ONE }, { 20, "20" }, { 40, "40" } }, L.SET_STACK_TIP)
    l:Money(L.SET_EXPENSIVE, { "selling", "expensive" }, L.SET_EXPENSIVE_TIP)
    l:Check(L.SET_RETURNED, { "selling", "returned" }, nil, moduleOn("Selling"))

    l:Header(L.MODULE_Stock)
    l:Module("Stock")
    l:Note(L.SET_STOCK_NOTE)

    l:Header(L.MODULE_Vendor)
    l:Module("Vendor")
    l:Note(L.SET_VENDOR_QUALITY)
    for _, q in ipairs(ns.Vendor.QUALITY_ORDER) do
        l:Check(L["SET_VENDOR_Q_" .. q], { "vendor", "quality", q }, L.SET_VENDOR_Q_TIP, moduleOn("Vendor"))
    end
    l:Check(L.SET_VENDOR_KEEP_VALUABLE, { "vendor", "keepValuable" }, L.SET_VENDOR_KEEP_VALUABLE_TIP, moduleOn("Vendor"))
    l:Check(L.SET_VENDOR_EASY, { "vendor", "easy" }, nil, moduleOn("Vendor"))
    l:Check(L.SET_VENDOR_BETTER, { "vendor", "better" }, nil, moduleOn("Vendor"))
    l:Check(L.SET_VENDOR_AUTO, { "vendor", "auto" }, L.SET_VENDOR_AUTO_TIP, moduleOn("Vendor"))
    l:Note(L.SET_VENDOR_LISTS)
    UI.BuildListsEditor(l, { "vendorSell", "vendorKeep" })

    l:Header(L.MODULE_Market)
    l:Module("Market")
    l:Header(L.MODULE_Neutral)
    l:Module("Neutral")
end

function build.craft(l)
    l:Header(L.MODULE_Disenchanter)
    l:Module("Disenchanter")
    l:Cycle(L.SET_DE_QUALITY, { "disenchant", "quality" }, { { "green", L.Q_GREEN }, { "greenblue", L.Q_GREENBLUE } })
    l:Check(L.SET_DE_SKIP, { "disenchant", "skipBetterToSell" }, nil, moduleOn("Disenchanter"))
    l:Check(L.SET_DE_SHOWN, { "disenchant", "shown" }, nil, moduleOn("Disenchanter"))
    l:Row(L.SET_DE_KEY, UI.Edit(l.parent, 60, function(text)
        ns.settings.disenchant.key = (text or ""):upper()
        if ns.Disenchanter.enabled then ns.Disenchanter.ApplyBinding() end
    end))
    l:Note(L.SET_DE_NOTE)
    l:Header(L.MODULE_Recipes)
    l:Module("Recipes")
    l:Check(L.SET_RECIPES_SHOWN, { "recipes", "shown" }, nil, moduleOn("Recipes"))
    l:Header(L.MODULE_Trade)
    l:Module("Trade")
    l:Check(L.SET_TRADE_ASK, { "trade", "ask" }, nil, moduleOn("Trade"))
    l:Button(L.BTN_PRICE_LIST, function() UI.EditPriceList() end, L.TIP_PRICE_LIST)
    l:Header(L.CLIENTS_TITLE)
    local clients = UI.Lines((function()
        local f = CreateFrame("Frame", nil, l.parent)
        l:Add(f, 10 * 16 + 4, 8)
        f:SetSize(440, 10 * 16)
        return f
    end)(), 10, 440)
    l.items[#l.items + 1] = { Update = function()
        local list = {}
        for name, c in pairs(ns.db.clients) do list[#list + 1] = { name = name, c = c } end
        table.sort(list, function(a, b) return (a.c.last or 0) > (b.c.last or 0) end)
        local texts = {}
        for i, e in ipairs(list) do
            if i > #clients then break end
            local regular = ns.TradeLogic.IsRegular(ns.db.clients, e.name) and (" · " .. L.TRADE_REGULAR) or ""
            texts[i] = L.CLIENT_LINE:format(e.name, e.c.orders, ns.FormatMoney(e.c.sum),
                e.c.last and date("%d.%m", e.c.last) or "—") .. regular
        end
        if #texts == 0 then texts[1] = UI.Colorize(L.CLIENTS_NONE, "muted") end
        UI.SetLines(clients, texts)
    end }
end

function build.money(l)
    l:Header(L.MODULE_Mail)
    l:Module("Mail")
    l:Check(L.SET_STRANGER, { "mail", "strangerWarn" }, nil, moduleOn("Mail"))
    l:Header(L.MODULE_Ledger)
    l:Module("Ledger")
end

function build.service(l)
    l:Header(L.MODULE_Sync)
    l:Module("Sync")
    l:Note(L.SET_SYNC_NOTE)
    l:Header(L.MODULE_ImportExport)
    l:Button(L.BTN_IMPORT, function() UI.ImportDialog() end, L.TIP_IMPORT)
    l:Button(L.BTN_EXPORT_SETTINGS, function()
        UI.ShowText(L.EXPORT_SETTINGS_TITLE, ns.ImportExport.ExportSettings())
    end)
    l:Header(L.MODULE_Lists)
    UI.BuildListsEditor(l)
end

-- Lists editor (settings → Utility). TZ: "Списки товаров". -------------------------------------
-- fixed: only these lists, without creating or deleting (the vendor lists in Trade).

function UI.BuildListsEditor(l, fixed)
    local p = l.parent
    local first = fixed and fixed[1] or "quick"
    local state = { name = first }
    local function listNames() return fixed or ns.ItemLists.Names() end
    local listCycle = UI.Button(p, "", 170, function(self)
        local names = listNames()
        local idx = 1
        for i, n in ipairs(names) do if n == state.name then idx = i end end
        state.name = names[idx % #names + 1]
        state.selected = nil
        UI.RefreshSettings()
    end, L.TIP_LIST_PICK)
    l:Add(listCycle, 0, 8)
    local newList = UI.Button(p, L.BTN_NEW_LIST, 100, function()
        UI.AskText(L.NEW_LIST_TITLE, L.NEW_LIST_HINT, L.BTN_CREATE, function(text, w)
            local name = ns.ItemLists.Create((text or ""):match("^[^\n]*"))
            if name then
                state.name = name
                w:Hide()
                UI.RefreshSettings()
            else
                w.result:SetText(UI.Colorize(L.LIST_EXISTS, "loss"))
            end
        end)
    end)
    l:Add(newList, 0, 184)
    local delList = UI.Button(p, L.BTN_DELETE_LIST, 100, function()
        if ns.ItemLists.Delete(state.name) then
            state.name = first
            UI.RefreshSettings()
        end
    end)
    l:Add(delList, 0, 288)
    local export = UI.Button(p, L.BTN_EXPORT_LIST, 60, function()
        UI.ShowText(L.EXPORT_LIST_TITLE:format(ns.ItemLists.Title(state.name)), ns.ImportExport.ExportList(state.name))
    end)
    l:Add(export, 28, 392)

    local add = UI.Edit(p, 230, function(text)
        if ns.ItemLists.Add(state.name, text) then UI.RefreshSettings() else ns.Print(L.ITEM_NOT_FOUND) end
    end)
    add:SetScript("OnEditFocusGained", function(self) UI.activeEdit = self end)
    add:SetScript("OnEditFocusLost", function(self) if UI.activeEdit == self then UI.activeEdit = nil end end)
    l:Add(add, 0, 14)
    local hint = UI.Text(p, "GameFontDisableSmall")
    hint:SetText(L.LIST_ADD_HINT)
    l:Add(hint, 26, 254)

    local list = UI.ScrollList(p, { { width = 180 }, { width = 60 }, { width = 120 } }, 10, {
        button = { width = 70, text = function() return L.BTN_REMOVE end,
            onClick = function(d) ns.ItemLists.Remove(state.name, d.itemID); UI.RefreshSettings() end },
        onSelect = function(d) state.selected = d.itemID; UI.RefreshSettings() end,
    })
    list:SetWidth(450)
    list:SetHeight(220)
    l:Add(list, 224, 0)
    -- Drag an item from the bags onto the list.
    list:SetScript("OnReceiveDrag", function()
        local kind, itemID = GetCursorInfo()
        if kind == "item" and itemID then
            ns.ItemLists.Add(state.name, itemID)
            ClearCursor()
            UI.RefreshSettings()
        end
    end)
    list:SetScript("OnMouseUp", list:GetScript("OnReceiveDrag"))

    -- Stock parameters of the selected item: buy below (empty = auto), cap, note.
    local function entry() return state.selected and ns.ItemLists.Entry(state.name, state.selected) end
    local function field(name)
        return function() local e = entry(); return e and e[name] end,
            function(v) local e = entry(); if e then e[name] = v; ns.Prices.Invalidate(); UI.RefreshSettings() end end
    end
    local bbGet, bbSet = field("buyBelow")
    local capGet, capSet = field("cap")
    local buyBelow = l:Row(L.STOCK_BUY_BELOW, UI.MoneyEdit(p, 80, bbGet, bbSet), L.STOCK_BUY_BELOW_TIP)
    local cap = l:Row(L.STOCK_CAP, UI.MoneyEdit(p, 80, capGet, capSet))
    local noteGet, noteSet = field("note")
    local note = UI.Edit(p, 200, function(text) noteSet(text ~= "" and text or nil) end)
    function note:Update() self:SetText(noteGet() or "") end
    l:Row(L.STOCK_NOTE, note)

    local editor = { Update = function()
        listCycle:SetText(ns.ItemLists.Title(state.name) .. " ›")
        delList:SetEnabled(not ns.ItemLists.IsBuiltin(state.name))
        newList:SetShown(not fixed)
        delList:SetShown(not fixed)
        local data = {}
        local lst = ns.ItemLists.Get(state.name)
        if not lst then
            state.name = first
            lst = ns.ItemLists.Get(first)
        end
        for _, id in ipairs(ns.ItemLists.Ids(state.name)) do
            local e = lst.items[id]
            local params = {}
            if e.buyBelow then params[#params + 1] = "≤ " .. ns.FormatMoney(e.buyBelow) end
            if e.cap then params[#params + 1] = "max " .. ns.FormatMoney(e.cap) end
            if e.note then params[#params + 1] = e.note end
            data[#data + 1] = {
                itemID = id, icon = Items.Texture(id),
                cols = { Items.ColoredName(id), L["SRC_" .. (e.src or "manual")], table.concat(params, " · ") },
            }
            if id == state.selected then list.selected = data[#data] end
        end
        list:SetData(data)
        local stock = state.name == "stock" and entry() ~= nil
        buyBelow:SetShown(stock)
        cap:SetShown(stock)
        note:SetShown(stock)
    end }
    l.items[#l.items + 1] = editor
end

-- Price list for services: one line per service "Name; price with client's reagents; price with own (or empty = auto)".
function UI.EditPriceList()
    local lines = {}
    for _, e in ipairs(ns.settings.trade.services) do
        lines[#lines + 1] = ("%s; %s; %s"):format(e.name, e.client and ("%g"):format(e.client / 10000) or "",
            e.own and ("%g"):format(e.own / 10000) or "")
    end
    UI.AskText(L.PRICE_LIST_TITLE, L.PRICE_LIST_HINT, L.BTN_SAVE_LIST, function(text, w)
        local list = {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            local name, client, own = line:match("^%s*([^;]+);%s*([^;]*);?%s*([^;]*)")
            if name and name:match("%S") then
                list[#list + 1] = {
                    name = name:gsub("%s+$", ""), client = UI.ParseMoney(client), own = UI.ParseMoney(own), reagents = {},
                }
            end
        end
        -- Keep reagents known for services with the same name.
        for _, e in ipairs(list) do
            for _, old in ipairs(ns.settings.trade.services) do
                if old.name == e.name then e.reagents = old.reagents or {} end
            end
        end
        ns.settings.trade.services = list
        w.result:SetText(L.PRICE_LIST_SAVED:format(#list))
    end)
    UI.TextWindow().edit:SetText(table.concat(lines, "\n"))
end

-- Import dialog: paste → preview of what changes → apply.
function UI.ImportDialog()
    local preview
    UI.AskText(L.IMPORT_TITLE, L.IMPORT_HINT, L.BTN_PREVIEW, function(text, w)
        if preview then
            ns.ImportExport.Apply(preview)
            w.result:SetText(UI.Colorize(L.IMPORT_DONE, "profit"))
            w.action:SetText(L.BTN_PREVIEW)
            preview = nil
            UI.RefreshSettings()
            return
        end
        local p, err = ns.ImportExport.Preview(text)
        if not p then
            w.result:SetText(UI.Colorize(L["IMPORT_ERR_" .. tostring(err)] or tostring(err), "loss"))
            return
        end
        preview = p
        if p.kind == "list" then
            w.result:SetText(L.IMPORT_LIST_DIFF:format(ns.ItemLists.Title(p.list) or p.list,
                #p.diff.add, #p.diff.remove, #p.diff.change) .. (p.isNew and (" · " .. L.IMPORT_NEW_LIST) or ""))
        else
            w.result:SetText(L.IMPORT_SETTINGS_DIFF:format(#p.changes))
        end
        w.action:SetText(L.BTN_APPLY)
    end)
end

-- Window ----------------------------------------------------------------------------------------

local win

local function selectGroup(g)
    win.group = g
    for _, b in ipairs(win.groupButtons) do b:SetEnabled(b.group ~= g) end
    for name, page in pairs(win.pages) do page.scroll:SetShown(name == g) end
    UI.RefreshSettings()
end

local function groupModules(g)
    local out = {}
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        if m.group == g and m.canDisable then out[#out + 1] = name end
    end
    return out
end

local function buildWindow()
    win = UI.Window("BaryshSettings", WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    local title = UI.Text(win, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L.SETTINGS_TITLE)
    win.profile = UI.Cycle(win, 190, { { "account", L.PROFILE_ACCOUNT }, { "char", L.PROFILE_CHAR } },
        function() return ns.cdb.profileMode end,
        function(v)
            ns.SetProfileMode(v)
            ns.ApplyModuleSettings()
            UI.ModulesChanged()
            UI.RefreshSettings()
        end, L.TIP_PROFILE)
    win.profile:SetPoint("TOPRIGHT", -40, -12)

    win.groupButtons, win.groupChecks, win.pages = {}, {}, {}
    for i, g in ipairs(ns.groups) do
        local b = UI.Button(win, L["GROUP_" .. g:upper()], 120, function() selectGroup(g) end)
        b:SetPoint("TOPLEFT", 40, -44 - (i - 1) * 28)
        b.group = g
        win.groupButtons[i] = b
        local mods = groupModules(g)
        if #mods > 0 then
            local cb = UI.Check(win, "", function()
                for _, n in ipairs(mods) do if ns.IsModuleEnabled(n) then return true end end
                return false
            end, function(v)
                for _, n in ipairs(mods) do ns.SetModuleEnabled(n, v) end
                UI.RefreshSettings()
            end, L.TIP_GROUP_CHECK)
            cb:SetPoint("RIGHT", b, "LEFT", -2, 0)
            win.groupChecks[#win.groupChecks + 1] = cb
        end

        local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 176, -44)
        scroll:SetPoint("BOTTOMRIGHT", -34, 48)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(450, 10)
        scroll:SetScrollChild(child)
        scroll:Hide()
        local l = newLayout(child)
        build[g](l)
        child:SetHeight(l.y + 10)
        win.pages[g] = { scroll = scroll, layout = l }
    end

    win.reset = UI.Button(win, L.BTN_RESET_GROUP, 140, function()
        for _, key in ipairs(GROUP_KEYS[win.group] or {}) do ns.ResetSettingsGroup(key) end
        ns.Prices.Invalidate()
        UI.RefreshSettings()
    end, L.TIP_RESET_GROUP)
    win.reset:SetPoint("BOTTOMLEFT", 16, 14)
    win.done = UI.Button(win, L.BTN_DONE, 100, function() win:Hide() end)
    win.done:SetPoint("BOTTOMRIGHT", -16, 14)
    win:Hide()
    selectGroup("core")
end

function UI.RefreshSettings()
    if not win or not win:IsShown() then return end
    win.profile:Update()
    for _, cb in ipairs(win.groupChecks) do cb:Update() end
    local page = win.pages[win.group]
    if page then page.layout:Update() end
    if ns.Disenchanter and ns.Disenchanter.enabled then ns.Disenchanter.SetShown(ns.settings.disenchant.shown) end
    if UI.minimapButton then UI.minimapButton:SetShown(not ns.settings.minimap.hidden) end
    if ns.Vendor and ns.Vendor.merchantOpen then ns.Vendor.UpdateButton() end
    UI.Refresh()
end

function UI.Settings()
    if not win then buildWindow() end
    return win
end

function UI.ToggleSettings()
    local w = UI.Settings()
    w:SetShown(not w:IsShown())
    UI.RefreshSettings()
end

-- Shift+click on an item while a Barysh edit box has focus inserts the link there.
if ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        local e = UI.activeEdit
        if e and e:HasFocus() and link then e:Insert(link) end
    end)
end
