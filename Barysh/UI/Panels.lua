local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Panels next to game windows: profession (recipe profit) and trade; trade toast and question.
-- TZ: "Панели у окон игры: почты, профессии, обмена".

local DIFFICULTY_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40bf40", [3] = "808080" }

-- Recipes -----------------------------------------------------------------------------------------

local recipes

local function buildRecipes()
    local f = UI.Window("BaryshRecipes", 440, 500)
    f:SetFrameStrata("MEDIUM")
    f.title = UI.Text(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.header = UI.Text(f, "GameFontDisableSmall")
    f.header:SetPoint("TOPLEFT", 40, -36)
    f.header:SetText(L.RECIPES_HEADER)
    f.list = UI.ScrollList(f, {
        { width = 150 }, { width = 56, justify = "RIGHT" }, { width = 56, justify = "RIGHT" },
        { width = 56, justify = "RIGHT" }, { width = 50, justify = "RIGHT" },
    }, 12, {
        onEnter = function(row, d)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            local r = d.eval.recipe
            GameTooltip:AddLine(r.name or "?")
            for _, rg in ipairs(r.reagents) do
                GameTooltip:AddDoubleLine(("%s ×%d"):format(Items.ColoredName(rg.itemID), rg.qty),
                    money((ns.Prices.Value(rg.itemID) or 0) * rg.qty), 1, 1, 1, 1, 1, 1)
            end
            if d.eval.pointCost then
                GameTooltip:AddDoubleLine(L.RECIPE_POINT, money(d.eval.pointCost), 1, 0.82, 0, 1, 1, 1)
            end
            GameTooltip:Show()
        end,
    })
    f.list:SetPoint("TOPLEFT", 14, -50)
    f.list:SetPoint("RIGHT", -14, 0)
    f.list:SetHeight(12 * 22)
    f.planTitle = UI.Text(f, "GameFontNormal")
    f.planTitle:SetPoint("TOPLEFT", 16, -322)
    local planBox = CreateFrame("Frame", nil, f)
    planBox:SetPoint("TOPLEFT", 16, -340)
    planBox:SetSize(400, 100)
    f.plan = UI.Lines(planBox, 6, 400)
    f.shopping = UI.Button(f, L.BTN_SHOPPING, 150, function() ns.RecipesModule.ShoppingList() end, L.TIP_SHOPPING)
    f.shopping:SetPoint("BOTTOMLEFT", 16, 14)
    f.craft = UI.Button(f, L.BTN_CRAFT_NEXT, 160, function() ns.RecipesModule.CraftNext() end, L.TIP_CRAFT_NEXT)
    f.craft:SetPoint("BOTTOMRIGHT", -16, 14)
    f:Hide()
    return f
end

local function refreshRecipes()
    local cur = ns.RecipesModule.current
    if not cur then return end
    local rows, plan = ns.RecipesModule.Evaluate()
    recipes.title:SetText(L.RECIPES_TITLE:format(cur.name or "?", cur.skill, cur.maxSkill))
    local data = {}
    for _, e in ipairs(rows) do
        local r = e.recipe
        local color = DIFFICULTY_COLOR[r.difficulty] or "ffffff"
        data[#data + 1] = {
            eval = e, icon = r.icon or (r.output and Items.Texture(r.output)),
            cols = {
                "|cff" .. color .. (r.name or "?") .. "|r", money(e.cost), e.sale > 0 and money(e.sale) or "—",
                UI.Colorize(money(e.profit), e.profit >= 0 and "profit" or "loss"),
                e.pointCost and money(e.pointCost) or "—",
            },
        }
    end
    recipes.list:SetData(data)
    if plan and #plan.steps > 0 then
        recipes.planTitle:SetText(L.PLAN_TITLE:format(cur.maxSkill))
        local lines = {}
        for i, step in ipairs(plan.steps) do
            if i > 4 then break end
            lines[#lines + 1] = L.PLAN_STEP:format(step.crafts, step.eval.recipe.name or "?", step.points)
        end
        lines[#lines + 1] = L.PLAN_TOTAL:format(money(plan.cost), money(plan.sale), money(plan.cost - plan.sale))
        if plan.short > 0 then lines[#lines + 1] = UI.Colorize(L.PLAN_SHORT:format(plan.short), "risk") end
        UI.SetLines(recipes.plan, lines)
    else
        recipes.planTitle:SetText(cur.skill >= cur.maxSkill and L.PLAN_CAP or L.PLAN_NONE)
        UI.SetLines(recipes.plan, {})
    end
    recipes.craft:SetEnabled(plan ~= nil and #plan.steps > 0)
end

function UI.RecipesPanel(show)
    if not show then
        if recipes then recipes:Hide() end
        return
    end
    if not ns.settings.recipes.shown then return end
    recipes = recipes or buildRecipes()
    local anchor = ns.ProfessionAPI.Frame()
    recipes:ClearAllPoints()
    if anchor then recipes:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0) else recipes:SetPoint("CENTER") end
    recipes:Show()
    ns.Safe(refreshRecipes)
end

-- Trade -------------------------------------------------------------------------------------------

local trade

local function buildTrade()
    local f = UI.Window("BaryshTrade", 260, 150)
    f:SetFrameStrata("MEDIUM")
    f.title = UI.Text(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -14)
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 14, -34)
    box:SetSize(232, 100)
    f.lines = UI.Lines(box, 6, 232)
    f:Hide()
    return f
end

-- Live panel while the trade window is open. t = described trade or nil to hide.
function UI.TradePanel(t)
    if not t then
        if trade then trade:Hide() end
        return
    end
    trade = trade or buildTrade()
    trade:ClearAllPoints()
    if TradeFrame then trade:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 4, 0) else trade:SetPoint("CENTER") end
    local name = t.partner or "?"
    local mark = ns.TradeModule.IsRegular(name) and (" · " .. UI.Colorize(L.TRADE_REGULAR, "profit")) or ""
    trade.title:SetText(name .. mark)
    local lines = {}
    local expected = ns.TradeModule.Expected(t)
    if t.enchant then lines[#lines + 1] = L.TRADE_ENCHANT:format(t.enchant) end
    if expected then
        local st, diff = ns.TradeLogic.CheckPayment(expected, t.got.money)
        local color = st == "ok" and "profit" or (st == "less" and "loss" or "risk")
        lines[#lines + 1] = L.TRADE_EXPECTED:format(money(expected))
        lines[#lines + 1] = UI.Colorize(L["TRADE_PAY_" .. st]:format(money(math.abs(diff))), color)
    end
    if t.order then lines[#lines + 1] = L.TRADE_HAS_ORDER end
    if t.got.money > 0 then lines[#lines + 1] = L.TRADE_GOT:format(money(t.got.money)) end
    if t.gave.money > 0 then lines[#lines + 1] = L.TRADE_GAVE:format(money(t.gave.money)) end
    if t.got.money > 0 and not t.guild and not t.own and not t.order and not t.enchant and #t.gave.items == 0 then
        lines[#lines + 1] = UI.Colorize(L.TRADE_STRANGER_GOLD, "loss")
    end
    UI.SetLines(trade.lines, lines)
    trade:Show()
end

-- Toast after an automatically recorded trade, with "Fix".
local toast

function UI.TradeToast(t, kind)
    if not toast then
        toast = UI.Window("BaryshTradeToast", 300, 64)
        toast:SetPoint("TOP", 0, -140)
        toast.text = UI.Text(toast, "GameFontHighlightSmall")
        toast.text:SetPoint("TOPLEFT", 14, -14)
        toast.text:SetWidth(270)
        toast.fix = UI.Button(toast, L.BTN_FIX, 90, function()
            toast:Hide()
            ns.TradeModule.Fix()
        end)
        toast.fix:SetPoint("BOTTOMRIGHT", -12, 10)
    end
    local amount = t.got.money > 0 and t.got.money or t.gave.money
    toast.text:SetText(L.TRADE_RECORDED:format(L["KIND_" .. kind] or L["TRADEKIND_" .. kind] or kind, money(amount)))
    toast:Show()
    local shown = toast
    C_Timer.After(15, function() if shown:IsShown() then shown:Hide() end end)
end

-- "What was it?" with the options that fit the direction of the trade.
local ask

function UI.TradeAsk(t, options)
    if not ask then
        ask = UI.Window("BaryshTradeAsk", 320, 130)
        ask:SetPoint("TOP", 0, -140)
        ask:SetFrameStrata("DIALOG")
        ask.title = UI.Text(ask, "GameFontNormal")
        ask.title:SetPoint("TOPLEFT", 14, -14)
        ask.title:SetText(L.TRADE_ASK_TITLE)
        ask.text = UI.Text(ask, "GameFontHighlightSmall")
        ask.text:SetPoint("TOPLEFT", 14, -34)
        ask.text:SetWidth(290)
        ask.buttons = {}
    end
    for _, b in ipairs(ask.buttons) do b:Hide() end
    local parts = {}
    if #t.gave.items > 0 then parts[#parts + 1] = L.TRADE_GAVE_ITEMS:format(#t.gave.items) end
    if t.gave.money > 0 then parts[#parts + 1] = L.TRADE_GAVE:format(money(t.gave.money)) end
    if #t.got.items > 0 then parts[#parts + 1] = L.TRADE_GOT_ITEMS:format(#t.got.items) end
    if t.got.money > 0 then parts[#parts + 1] = L.TRADE_GOT:format(money(t.got.money)) end
    ask.text:SetText((t.partner or "?") .. ": " .. table.concat(parts, ", "))
    for i, opt in ipairs(options) do
        local b = ask.buttons[i]
        if not b then
            b = UI.Button(ask, "", 96, function(self)
                ask:Hide()
                ns.TradeModule.Answer(ask.trade, self.kind)
            end)
            ask.buttons[i] = b
        end
        b.kind = opt
        b:SetText(L["TRADEKIND_" .. opt])
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", 12 + (i - 1) % 3 * 100, 12 + math.floor((i - 1) / 3) * 26)
        b:Show()
    end
    ask.trade = t
    ask:Show()
end
