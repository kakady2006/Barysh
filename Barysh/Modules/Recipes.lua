local _, ns = ...

local Recipes, Prof = ns.Recipes, ns.ProfessionAPI
local L = ns.L

-- Recipe profit next to the profession window, levelling plan, shopping list.
-- Known recipes are saved per character for "raw materials" deals. TZ: "Выгода рецептов".
local M = ns:NewModule("Recipes", { group = "craft" })
ns.RecipesModule = M

M.crafted = {} -- output itemID -> time it was last crafted (for trade recognition)
M.CRAFTED_TTL = 24 * 3600

local function buyPrice(id) return ns.Prices.Value(id) end

local function saleValue(id)
    local _, v = ns.BestUse(id)
    return v
end

-- Reads the open profession window and saves the recipes of this character.
function M.Read()
    if not Prof.Available() then return nil end
    local name, skill, maxSkill = Prof.Info()
    local recipes = Prof.Recipes()
    local saved = {}
    for _, r in ipairs(recipes) do
        saved[r.recipeID] = {
            recipeID = r.recipeID, output = r.output, qtyMin = r.qtyMin, qtyMax = r.qtyMax,
            reagents = r.reagents, name = r.name, difficulty = r.difficulty,
        }
    end
    local char = ns.CharKey()
    ns.db.recipes[char] = ns.db.recipes[char] or {}
    for id, r in pairs(saved) do ns.db.recipes[char][id] = r end
    M.current = { name = name, skill = skill or 0, maxSkill = maxSkill or 0, recipes = recipes }
    return M.current
end

-- Rows for the panel, best profit first; plan to the next trainer threshold.
function M.Evaluate()
    local cur = M.current
    if not cur then return {}, nil end
    local rows = {}
    for _, r in ipairs(cur.recipes) do rows[#rows + 1] = Recipes.Evaluate(r, buyPrice, saleValue) end
    table.sort(rows, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.recipe.recipeID < b.recipe.recipeID
    end)
    local plan = Recipes.Plan(cur.recipes, cur.skill, cur.maxSkill, buyPrice, saleValue)
    return rows, plan
end

-- "Shopping list": reagents of the plan go to the quick scan list (and so get fresh prices
-- and show up as "raw materials" deals).
function M.ShoppingList()
    local _, plan = M.Evaluate()
    if not plan then return 0 end
    local n = 0
    for itemID in pairs(Recipes.Shopping(plan)) do
        if ns.ItemLists.Add("quick", itemID) then n = n + 1 end
    end
    ns.Print(L.SHOPPING_ADDED:format(n))
    return n
end

-- Must be called from a click: one craft of the first plan step.
function M.CraftNext()
    local _, plan = M.Evaluate()
    local step = plan and plan.steps[1]
    if not step then return false end
    Prof.Craft(step.eval.recipe.recipeID)
    return true
end

function M.RecentlyCrafted()
    local out, now = {}, ns.Now()
    for id, t in pairs(M.crafted) do
        if now - t < M.CRAFTED_TTL then out[id] = true end
    end
    return out
end

local function refresh()
    M.queued = false
    if not M.open then return end
    M.Read()
    if ns.UI and ns.UI.RecipesPanel then ns.UI.RecipesPanel(true) end
end

function M:OnEnable()
    self:RegisterEvent("TRADE_SKILL_SHOW", function()
        M.open = true
        refresh()
    end)
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
        if M.open and not M.queued then
            M.queued = true
            C_Timer.After(0.5, refresh)
        end
    end)
    self:RegisterEvent("TRADE_SKILL_CLOSE", function()
        M.open = false
        if ns.UI and ns.UI.RecipesPanel then ns.UI.RecipesPanel(false) end
    end)
    -- On the modern client a recipe's ID is the spell that crafts it.
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        if unit ~= "player" or not M.current then return end
        for _, r in ipairs(M.current.recipes) do
            if r.recipeID == spellID and r.output then M.crafted[r.output] = ns.Now() end
        end
    end)
end

function M:OnDisable()
    M.current, M.open = nil, false
    if ns.UI and ns.UI.RecipesPanel then ns.UI.RecipesPanel(false) end
end
