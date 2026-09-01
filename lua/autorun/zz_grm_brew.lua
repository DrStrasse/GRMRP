--[[ Варка: рецепты пива/кваса требуют котёл рядом с плитой. ]]
if SERVER then AddCSLuaFile() end
if not SERVER then return end

local function nearKettle(pos)
    for _, e in ipairs(ents.FindInSphere(pos, 180)) do
        if IsValid(e) and e:GetClass() == "grm_brew_kettle" then return true end
    end
    return false
end

local function wrap()
    local stored = scripted_ents.GetStored("grm_food_stove")
    if not (stored and stored.t and stored.t.kitchenOp) then return false end
    if stored.t._grmBrewWrap then return true end
    local old = stored.t.kitchenOp
    stored.t.kitchenOp = function(self, ply, op, data)
        if op == "stove_cook" then
            local rid = tostring((istable(data) and data.recipe) or "")
            local rec = GRM.FoodKitchen and GRM.FoodKitchen.Recipe and GRM.FoodKitchen.Recipe(rid)
            if istable(rec) and rec.needKettle and not nearKettle(self:GetPos()) then
                if GRM.FoodKitchen and GRM.FoodKitchen.Notify then
                    GRM.FoodKitchen.Notify(ply, "[Варка] Рядом нужен котёл (поставьте оборудование).", 255, 180, 80)
                end
                return
            end
        end
        return old(self, ply, op, data)
    end
    stored.t._grmBrewWrap = true
    return true
end

timer.Create("GRM_Brew_Wrap", 1, 30, function()
    if wrap() then timer.Remove("GRM_Brew_Wrap") end
end)
