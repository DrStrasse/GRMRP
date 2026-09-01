--[[--------------------------------------------------------------------
    GRM Labs Craft v2.0.0 — лаборатории наркотиков и медицины
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.NarcCraft = GRM.NarcCraft or {}
local CRAFT = GRM.NarcCraft
CRAFT.Version = "2.0.0"
CRAFT.Active = CRAFT.Active or {}

util.AddNetworkString("GRM_NarcCraft_Open")
util.AddNetworkString("GRM_NarcCraft_Start")
util.AddNetworkString("GRM_NarcCraft_Progress")
util.AddNetworkString("GRM_NarcCraft_Done")

local FALLBACK_NARC = {
    marijuana = { name="Марихуана", ingredients={narc_solvent=2,narc_precursor=1}, cook_time=30, yield=3 },
    amphetamine = { name="Амфетамин", ingredients={narc_solvent=3,narc_precursor=3}, cook_time=60, yield=5 },
    cocaine = { name="Кокаин", ingredients={narc_solvent=5,narc_precursor=5,narc_equipment=1}, cook_time=90, yield=7 },
}
local FALLBACK_MED = {
    painkillers = { name="Обезболивающее", ingredients={narc_solvent=2,narc_precursor=1}, time=20, yield=5 },
    antibiotics = { name="Антибиотики", ingredients={narc_solvent=3,narc_precursor=2}, time=30, yield=4 },
    adrenaline = { name="Адреналин", ingredients={narc_solvent=5,narc_precursor=3,narc_equipment=1}, time=45, yield=2 },
    detox = { name="Детокс-комплект", ingredients={narc_solvent=4,narc_precursor=2}, time=40, yield=2 },
}

local LAB_META = {
    narc = { title = "Лаборатория наркотиков", outputPrefix = "narc_" },
    med  = { title = "Медицинская лаборатория", outputPrefix = "med_" },
}

local function notify(ply, msg, r, g, b)
    if GRM.Notify then GRM.Notify(ply, msg, r or 100, g or 220, b or 100)
    elseif IsValid(ply) and ply.ChatPrint then ply:ChatPrint("[Лаборатория] " .. tostring(msg or "")) end
end

local function recipesOf(labType)
    if labType == "narc" then return (GRM.Narcotics and GRM.Narcotics.Recipes) or FALLBACK_NARC end
    return (GRM.MedicalFull and GRM.MedicalFull.Recipes) or FALLBACK_MED
end
local function recipeTime(r) return math.max(1, math.floor(tonumber(r and (r.time or r.cook_time)) or 30)) end
local function invReady() return GRM.Inventory and GRM.Inventory.CountItem and GRM.Inventory.RemoveItem and GRM.Inventory.AddItem end

local function payloadFor(ply, labType)
    local recipes = recipesOf(labType)
    local out = { labType = labType, title = (LAB_META[labType] and LAB_META[labType].title) or "Лаборатория", recipes = {} }
    for id, r in pairs(recipes or {}) do
        local row = { id=id, name=r.name or id, time=recipeTime(r), yield=tonumber(r.yield) or 1, ingredients={}, can=true }
        for itemID, need in pairs(r.ingredients or {}) do
            local have = invReady() and (GRM.Inventory.CountItem(ply, itemID) or 0) or 0
            row.ingredients[#row.ingredients+1] = { id=itemID, need=need, have=have, ok=have>=need }
            if have < need then row.can = false end
        end
        table.sort(row.ingredients, function(a,b) return a.id < b.id end)
        out.recipes[#out.recipes+1] = row
    end
    table.sort(out.recipes, function(a,b) return a.name < b.name end)
    return out
end

function CRAFT.OpenLab(ply, labType, ent)
    if not IsValid(ply) then return end
    labType = (labType == "med") and "med" or "narc"
    net.Start("GRM_NarcCraft_Open")
        net.WriteTable(payloadFor(ply, labType))
    net.Send(ply)
end

function CRAFT.CanCraft(ply, recipeID, labType)
    if not IsValid(ply) then return false, "Игрок недействителен" end
    if not invReady() then return false, "Инвентарь не загружен" end
    local recipes = recipesOf(labType)
    local recipe = recipes and recipes[recipeID]
    if not recipe then return false, "Неизвестный рецепт" end
    if CRAFT.Active[ply] then return false, "Вы уже заняты крафтом" end
    for itemID, need in pairs(recipe.ingredients or {}) do
        local have = GRM.Inventory.CountItem(ply, itemID) or 0
        if have < need then return false, string.format("Нужно %d %s (у вас: %d)", need, itemID, have) end
    end
    return true, recipe
end

function CRAFT.StartCraft(ply, recipeID, labType)
    labType = (labType == "med") and "med" or "narc"
    local ok, recipeOrErr = CRAFT.CanCraft(ply, recipeID, labType)
    if not ok then notify(ply, recipeOrErr, 255, 100, 100) return end
    local recipe = recipeOrErr
    local t = recipeTime(recipe)
    for itemID, need in pairs(recipe.ingredients or {}) do GRM.Inventory.RemoveItem(ply, itemID, need) end

    CRAFT.Active[ply] = { labType=labType, recipeID=recipeID, doneAt=CurTime()+t }
    net.Start("GRM_NarcCraft_Progress")
        net.WriteString(recipe.name or recipeID)
        net.WriteUInt(t, 16)
    net.Send(ply)
    notify(ply, "Процесс начат: " .. tostring(recipe.name or recipeID) .. " (" .. t .. " сек)", 100, 200, 255)

    timer.Simple(t, function()
        if not IsValid(ply) then return end
        CRAFT.Active[ply] = nil
        local output = ((LAB_META[labType] and LAB_META[labType].outputPrefix) or "narc_") .. recipeID
        local left = GRM.Inventory.AddItem(ply, output, tonumber(recipe.yield) or 1)
        if (left or 0) > 0 then notify(ply, "Инвентарь полон! Потеряно: " .. tostring(left), 255, 100, 100)
        else notify(ply, "Готово: " .. tostring(recipe.name or recipeID), 100, 220, 100) end
        net.Start("GRM_NarcCraft_Done")
            net.WriteString(recipe.name or recipeID)
        net.Send(ply)
        CRAFT.OpenLab(ply, labType)
    end)
end

net.Receive("GRM_NarcCraft_Open", function(_, ply)
    if not IsValid(ply) then return end
    local labType = net.ReadString()
    if labType ~= "narc" and labType ~= "med" then return end
    CRAFT.OpenLab(ply, labType)
end)

net.Receive("GRM_NarcCraft_Start", function(_, ply)
    if not IsValid(ply) then return end
    local labType = net.ReadString()
    local recipeID = net.ReadString()
    if labType ~= "narc" and labType ~= "med" then return end
    CRAFT.StartCraft(ply, recipeID, labType)
end)

print("[GRM] Labs Craft loaded v" .. CRAFT.Version)
