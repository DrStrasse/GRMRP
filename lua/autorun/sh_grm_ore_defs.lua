-- grm_ore_defs.lua
if not GRM then GRM = {} end
if not GRM.Inventory then GRM.Inventory = {} end
if not GRM.Inventory.ItemDefs then GRM.Inventory.ItemDefs = {} end

local function RegisterOre(id, name, color)
    GRM.Inventory.ItemDefs[id] = {
        type = "item",
        name = name,
        desc = "Кусок " .. name:lower() .. " руды.",
        icon = "icon16/brick.png",
        maxStack = 99,
        weight = 0.5,
        oreType = id:match("ore_(.+)"),
        color = color,
        sellable = true,
    }
end

RegisterOre("ore_copper", "Медная руда", Color(184, 115, 51))
RegisterOre("ore_gold", "Золотая руда", Color(255, 215, 0))
RegisterOre("ore_aluminum", "Алюминиевая руда", Color(200, 200, 210))
RegisterOre("ore_platinum", "Платиновая руда", Color(180, 180, 200))

print("[GRM Ore Defs] Предметы руды зарегистрированы")
