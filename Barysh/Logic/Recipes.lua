local _, ns = ...

-- Recipe profit, cost of a skill point, levelling plan, reagent values for "raw materials" deals.
-- TZ: "Выгода рецептов", deals type "Сырьё для крафта".
local Recipes = {}
ns.Recipes = Recipes

-- recipe = { recipeID, name, output = itemID or nil (enchants have none), qtyMin, qtyMax,
--   reagents = { {itemID, qty}, ... }, difficulty = 0 orange | 1 yellow | 2 green | 3 grey, skillUps }
-- buyPrice(itemID) -> unit cost to buy (market) or nil; saleValue(itemID) -> unit value after cut (best use) or nil.

-- Chance of a skill point by colour. Classic: orange always; yellow and green fall with skill.
-- Averages over the colour's range — an estimate, shown as such.
Recipes.CHANCE = { [0] = 1, [1] = 0.75, [2] = 0.25, [3] = 0 }
Recipes.PLAN_SPAN = 10 -- skill points one recipe is assumed to cover before it turns green/grey

function Recipes.ReagentCost(recipe, buyPrice, skipItemID)
    local cost, complete = 0, true
    for _, r in ipairs(recipe.reagents) do
        if r.itemID ~= skipItemID then
            local p = buyPrice(r.itemID)
            if p then cost = cost + p * r.qty else complete = false end
        end
    end
    return math.floor(cost + 0.5), complete
end

function Recipes.AvgQty(recipe)
    return ((recipe.qtyMin or 1) + (recipe.qtyMax or recipe.qtyMin or 1)) / 2
end

function Recipes.Evaluate(recipe, buyPrice, saleValue)
    local cost, complete = Recipes.ReagentCost(recipe, buyPrice)
    local sale = 0
    if recipe.output then
        local v = saleValue(recipe.output)
        if v then sale = math.floor(v * Recipes.AvgQty(recipe) + 0.5) end
    end
    local chance = Recipes.CHANCE[recipe.difficulty or 3] or 0
    local points = chance * math.max(1, recipe.skillUps or 1)
    local r = { recipe = recipe, cost = cost, sale = sale, profit = sale - cost, chance = chance, complete = complete }
    if points > 0 then r.pointCost = math.floor((cost - sale) / points + 0.5) end
    return r
end

-- Plan to the next trainer threshold: cheapest recipes per skill point first.
-- Returns { steps = { {eval, crafts, points}, ... }, cost, sale, points, short = points not covered }.
function Recipes.Plan(recipes, skill, target, buyPrice, saleValue)
    local evals = {}
    for _, rec in ipairs(recipes) do
        local e = Recipes.Evaluate(rec, buyPrice, saleValue)
        if e.pointCost and e.complete then evals[#evals + 1] = e end
    end
    table.sort(evals, function(a, b) return a.pointCost < b.pointCost end)
    local need = math.max(0, target - skill)
    local plan = { steps = {}, cost = 0, sale = 0, points = 0 }
    for _, e in ipairs(evals) do
        if need <= 0 then break end
        local pts = math.min(need, Recipes.PLAN_SPAN)
        local perCraft = e.chance * math.max(1, e.recipe.skillUps or 1)
        local crafts = math.ceil(pts / perCraft)
        plan.steps[#plan.steps + 1] = { eval = e, crafts = crafts, points = pts }
        plan.cost = plan.cost + e.cost * crafts
        plan.sale = plan.sale + e.sale * crafts
        plan.points = plan.points + pts
        need = need - pts
    end
    plan.short = need
    return plan
end

-- Value of one unit of each reagent: what the finished item brings minus the other reagents,
-- per unit of this reagent; the best recipe wins. { [itemID] = { value, recipeID } }
function Recipes.ReagentValues(recipes, buyPrice, saleValue)
    local out = {}
    for _, rec in ipairs(recipes) do
        local sale = rec.output and saleValue(rec.output)
        if sale then
            local gross = sale * Recipes.AvgQty(rec)
            for _, r in ipairs(rec.reagents) do
                local others, complete = Recipes.ReagentCost(rec, buyPrice, r.itemID)
                if complete and r.qty > 0 then
                    local v = math.floor((gross - others) / r.qty)
                    if v > 0 and (not out[r.itemID] or v > out[r.itemID].value) then
                        out[r.itemID] = { value = v, recipeID = rec.recipeID }
                    end
                end
            end
        end
    end
    return out
end

-- Shopping list for a plan: { [itemID] = units }.
function Recipes.Shopping(plan)
    local need = {}
    for _, step in ipairs(plan.steps) do
        for _, r in ipairs(step.eval.recipe.reagents) do
            need[r.itemID] = (need[r.itemID] or 0) + r.qty * step.crafts
        end
    end
    return need
end
