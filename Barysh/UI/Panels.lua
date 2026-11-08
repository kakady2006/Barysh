local _, ns = ...

local UI = ns.UI
local L = ns.L
local Items = ns.Items
local money = ns.FormatMoney

-- Panels next to game windows: profession (recipe profit) and mailbox settings.

local DIFFICULTY_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40bf40", [3] = "808080" }

-- Recipes -----------------------------------------------------------------------------------------

local recipes

local function buildRecipes()
    local f = UI.Window("BaryshRecipes", 480, 540)
    f:SetFrameStrata("MEDIUM")
    f.list = UI.Table(f, {
        { title = L.COL_RECIPE, flex = true },
        { title = L.COL_REAGENTS, width = 62, justify = "RIGHT" },
        { title = L.COL_SALE, width = 62, justify = "RIGHT" },
        { title = L.COL_PROFIT, width = 62, justify = "RIGHT" },
        { title = L.COL_POINT, width = 62, justify = "RIGHT" },
    }, {
        rowHeight = 26,
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
    f.list:SetPoint("TOPLEFT", 4, -46)
    f.list:SetPoint("RIGHT", -4, 0)
    f.list:SetHeight(300)
    UI.Divider(f, -352)
    f.planTitle = UI.Heading(f, "")
    f.planTitle:SetPoint("TOPLEFT", 16, -362)
    local planBox = CreateFrame("Frame", nil, f)
    planBox:SetPoint("TOPLEFT", 16, -384)
    planBox:SetSize(448, 110)
    f.plan = UI.Lines(planBox, 6, 448)
    f.craft = UI.Button(f, L.BTN_CRAFT_NEXT, 170, function() ns.RecipesModule.CraftNext() end, L.TIP_CRAFT_NEXT, "primary")
    f.craft:SetPoint("BOTTOMRIGHT", -16, 14)
    f.shopping = UI.Button(f, L.BTN_SHOPPING, 130, function() ns.RecipesModule.ShoppingList() end, L.TIP_SHOPPING)
    f.shopping:SetPoint("RIGHT", f.craft, "LEFT", -6, 0)
    f:Hide()
    return f
end

local function refreshRecipes()
    local cur = ns.RecipesModule.current
    if not cur then return end
    local rows, plan = ns.RecipesModule.Evaluate()
    recipes:SetTitle("Barysh", L.RECIPES_TITLE:format(cur.name or "?", cur.skill, cur.maxSkill))
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

-- The panel goes with the profession window: it closes when that window hides, even without
-- the game's close event.
local watchedProfession
function UI.RecipesPanel(show)
    if not show then
        if recipes then recipes:Hide() end
        return
    end
    if not ns.settings.recipes.shown then return end
    local anchor = ns.ProfessionAPI.Frame()
    if anchor and anchor.IsShown and not anchor:IsShown() then return end
    recipes = recipes or buildRecipes()
    if anchor and anchor ~= watchedProfession and anchor.HookScript then
        watchedProfession = anchor
        anchor:HookScript("OnHide", function() if recipes then recipes:Hide() end end)
    end
    recipes:ClearAllPoints()
    if anchor then recipes:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0) else recipes:SetPoint("CENTER") end
    recipes:Show()
    ns.Safe(refreshRecipes)
end

-- New data for an open panel; a closed one stays closed.
function UI.RefreshRecipesPanel()
    if recipes and recipes:IsShown() then ns.Safe(refreshRecipes) end
end

-- Mail settings ----------------------------------------------------------------------------------
-- The mail options live on the open mailbox, under the game's window, not in the settings window.
-- Shown even with the Mail module off, so it can be switched on right there.

local mailBar

function UI.MailSettingsBar()
    if mailBar or not MailFrame then return mailBar end
    local f = CreateFrame("Frame", "BaryshMailSettings", MailFrame, "BackdropTemplate")
    f:SetSize(math.max(MailFrame:GetWidth() or 0, 340), 70)
    f:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 0, -2)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\Tooltips\UI-Tooltip-Background",
            edgeFile = "Interface\Tooltips\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.8)
    end
    f.title = UI.Text(f, "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 10, -7)
    f.title:SetText("Barysh")
    f.module = UI.Check(f, L.MAIL_SET_MODULE, function() return ns.IsModuleEnabled("Mail") end,
        function(v) ns.SetModuleEnabled("Mail", v); UI.MailSettingsUpdate() end, L.MODTIP_Mail)
    f.module:SetPoint("TOPLEFT", 6, -20)
    f.stranger = UI.Check(f, L.SET_STRANGER, function() return ns.settings.mail.strangerWarn end,
        function(v)
            ns.settings.mail.strangerWarn = v
            if UI.Refresh then UI.Refresh() end
        end, L.SET_STRANGER_TIP)
    f.stranger:SetPoint("TOPLEFT", 6, -42)
    mailBar = f
    return f
end

function UI.MailSettingsUpdate()
    local f = mailBar
    if not f then return end
    f.module:Update()
    f.stranger:Update()
    local on = ns.IsModuleEnabled("Mail")
    f.stranger:SetActive(on, not on and L.NEEDS_MODULE:format(L.MODULE_Mail) or nil)
end

local mailOwner = {}
ns.RegisterEvent(mailOwner, "MAIL_SHOW", function()
    if not ns.settings then return end
    local f = UI.MailSettingsBar()
    if f then
        f:Show()
        UI.MailSettingsUpdate()
    end
end)
