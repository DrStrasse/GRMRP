--[[--------------------------------------------------------------------
    GRM Industry — регистрация предметов производства в инвентаре.

    ПОЧЕМУ ЭТОТ ФАЙЛ ОТДЕЛЬНЫЙ И ПОЧЕМУ С ИМЕНЕМ zz_.

    lua/autorun/sh_grm_inventory.lua создаёт справочник предметов
    ПЕРЕЗАПИСЬЮ:

        GRM.Inventory.ItemDefs = { ... }

    Файлы индустрии называются sh_grm_industry_* и по алфавиту идут
    РАНЬШЕ, чем sh_grm_inventory. Зарегистрируй мы предметы из них —
    инвентарь просто выбросил бы таблицу вместе с нашими записями.
    Поэтому регистрация стоит здесь: файлы zz_ грузятся последними.
    Так же устроен zz_grm_food_inventory_patch.lua.

    Отсюда же следует, что проверять регистрацию нужно именно
    в порядке загрузки GMod — это делает sim_industry_loadorder.

    ЧТО ЛОМАЛОСЬ БЕЗ ЭТОГО ФАЙЛА.

    GRM.Inventory.AddItem первым делом спрашивает GetItemDef и, если
    предмета в справочнике нет, возвращает ВСЁ количество как «не
    влезло» (sh_grm_inventory.lua:549). Адаптер контейнера честно
    понимал это как «нет места» — и источник сырья отвечал «Нет места
    в инвентаре» при совершенно пустом инвентаре.

    Сбор ресурсов не работал вовсе: ни лом из источника, ни готовая
    продукция со станка, ни оружие из верстака не попадали в руки.
    Производство крутилось вхолостую: станок делал вещь, положить её
    было некуда.
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.Inventory = GRM.Inventory or {}
GRM.Inventory.ItemDefs = GRM.Inventory.ItemDefs or {}

local I = GRM.Industry
local registered = 0

--[[ Не перетираем то, что уже зарегистрировал другой модуль: если
     металлолом кто-то завёл раньше, его описание и стак важнее. ]]
local function register(id, def)
    if not id or id == "" then return end
    if GRM.Inventory.ItemDefs[id] then return end
    GRM.Inventory.ItemDefs[id] = def
    registered = registered + 1
end

local ICON = {
    scrap_metal            = "icon16/wrench.png",
    components_box         = "icon16/box.png",
    gpu_basic              = "icon16/computer.png",
    gpu_mid                = "icon16/computer.png",
    gpu_premium            = "icon16/computer.png",
    defective_components   = "icon16/exclamation.png",
    defective_gpu          = "icon16/exclamation.png",
    defective_weapon_parts = "icon16/exclamation.png",
    item_repair_kit        = "icon16/wrench.png",
}

local DESC = {
    scrap_metal            = "Металлолом. Сырьё для производства.",
    components_box         = "Комплектующие. Материал для сборки.",
    gpu_basic              = "Видеокарта начального уровня.",
    gpu_mid                = "Видеокарта среднего уровня.",
    gpu_premium            = "Видеокарта верхнего уровня.",
    item_repair_kit        = "Снимает износ со станка.",
}

-- Обычные предметы — из справочника производства.
if I and I.Items then
    for id, def in pairs(I.Items) do
        register(id, {
            type     = "item",
            name     = def.name or id,
            desc     = def.defect and "Брак производства. Можно переплавить."
                       or (DESC[id] or ""),
            icon     = ICON[id],
            maxStack = 64,
            weight   = tonumber(def.weight) or 1.0,
            price    = tonumber(def.price) or 0,
            sellable = true,
            industry = true,      -- пометка: предмет production-контура
        })
    end
end

--[[ Оружие в справочнике предметов не описано — оно живёт в рецептах.
     Без регистрации его тоже нельзя было выдать в руки: AddItem
     возвращал бы всё количество обратно. ]]
if I and I.Recipes then
    for _, recipe in pairs(I.Recipes) do
        local out = recipe.output
        if isstring(out) and out ~= "" and not (I.Items and I.Items[out]) then
            register(out, {
                type     = "weapon",
                name     = recipe.name or out,
                desc     = "Изделие оружейного верстака.",
                maxStack = 1,
                weight   = 4.0,
                price    = tonumber(recipe.price) or 0,
                sellable = true,
                industry = true,
            })
        end
    end
end

if registered > 0 then
    print("[GRM Industry] предметов зарегистрировано в инвентаре: " .. registered)
end
