local _, ns = ...

-- Profession window on the modern client: C_TradeSkillUI.
local Prof = {}
ns.ProfessionAPI = Prof

function Prof.Available()
    return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetAllRecipeIDs ~= nil
end

-- name, skill, maxSkill (maxSkill = the current trainer cap)
function Prof.Info()
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if not info then return nil end
    return info.professionName, info.skillLevel or 0, info.maxSkillLevel or 0
end

-- Learned recipes in the shape Logic/Recipes.lua expects.
function Prof.Recipes()
    local out = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned then
            local s = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
            if s then
                local reagents = {}
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    local r = slot.reagents and slot.reagents[1]
                    if r and r.itemID and (slot.quantityRequired or 0) > 0 then
                        reagents[#reagents + 1] = { itemID = r.itemID, qty = slot.quantityRequired }
                    end
                end
                out[#out + 1] = {
                    recipeID = recipeID, name = info.name, icon = info.icon,
                    output = s.outputItemID, qtyMin = s.quantityMin or 1, qtyMax = s.quantityMax or 1,
                    reagents = reagents, difficulty = info.relativeDifficulty or 3,
                    skillUps = info.numSkillUps or 1, craftable = info.craftable,
                }
            end
        end
    end
    return out
end

-- One craft per click.
function Prof.Craft(recipeID)
    C_TradeSkillUI.CraftRecipe(recipeID, 1)
end

function Prof.Frame()
    return ProfessionsFrame or TradeSkillFrame
end
