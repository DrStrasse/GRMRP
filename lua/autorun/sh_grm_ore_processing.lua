--[[--------------------------------------------------------------------
    GRM Ore Processing v1.0 (Код 118) — переработка руды в химикаты

    СВЯЗЬ С DOБЫЧЕЙ:
    - ore_aluminum → растворитель (narc_solvent)
    - ore_copper → прекурсор (narc_precursor)
    - Металлолом → оборудование (narc_equipment)

    КОМАНДЫ:
    - /process <тип> — переработать руду в ингредиент
    - /processlist — список доступных рецептов
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.OreProcessing = GRM.OreProcessing or {}
local PROC = GRM.OreProcessing

-- ============================================================
-- РЕЦЕПТЫ ПЕРЕРАБОТКИ
-- ============================================================
PROC.Recipes = {
    -- Алюминиевая руда → растворитель
    solvent = {
        input = "ore_aluminum",
        input_count = 1,
        output = "narc_solvent",
        output_count = 5,
        time = 5, -- секунд на переработку
    },

    -- Медная руда → прекурсор
    precursor = {
        input = "ore_copper",
        input_count = 1,
        output = "narc_precursor",
        output_count = 3,
        time = 8,
    },

    -- Металлолом → оборудование
    equipment = {
        input = "scrap_metal", -- из завода
        input_count = 10,
        output = "narc_equipment",
        output_count = 1,
        time = 15,
    },
}

-- ============================================================
-- СЕРВЕРНАЯ ЧАСТЬ
-- ============================================================
if SERVER then
    util.AddNetworkString("GRM_OreProcess")
    util.AddNetworkString("GRM_OreProcess_Result")

    -- Команда /process
    hook.Add("PlayerSay", "GRM_OreProcessing_Command", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))

        if cmd == "/processlist" or cmd == "!processlist" then
            local msg = "Доступные рецепты переработки:\n"
            for id, recipe in pairs(PROC.Recipes) do
                msg = msg .. string.format("  /process %s — %d %s → %d %s (%d сек)\n",
                    id,
                    recipe.input_count,
                    recipe.input,
                    recipe.output_count,
                    recipe.output,
                    recipe.time
                )
            end
            ply:ChatPrint(msg)
            return ""
        end

        if string.StartWith(cmd, "/process ") or string.StartWith(cmd, "!process ") then
            local args = string.Explode(" ", cmd)
            local recipeID = args[2]

            if not recipeID then
                ply:ChatPrint("Использование: /process <тип>")
                return ""
            end

            local recipe = PROC.Recipes[recipeID]
            if not recipe then
                ply:ChatPrint("Неизвестный рецепт: " .. recipeID)
                return ""
            end

            -- Проверяем наличие руды
            local haveInput = GRM.Inventory and GRM.Inventory.CountItem and GRM.Inventory.CountItem(ply, recipe.input) or 0
            if haveInput < recipe.input_count then
                ply:ChatPrint(string.format("Нужно %d %s (у вас: %d)", recipe.input_count, recipe.input, haveInput))
                return ""
            end

            -- Начинаем переработку
            ply:ChatPrint(string.format("Переработка %d %s → %d %s (%d сек)...",
                recipe.input_count, recipe.input, recipe.output_count, recipe.output, recipe.time))

            timer.Simple(recipe.time, function()
                if not IsValid(ply) then return end

                -- Списываем руду
                local removed = GRM.Inventory.RemoveItem(ply, recipe.input, recipe.input_count)
                if not removed then
                    ply:ChatPrint("Ошибка: не удалось списать руду")
                    return
                end

                -- Добавляем продукт
                local left = GRM.Inventory.AddItem(ply, recipe.output, recipe.output_count)
                if left > 0 then
                    ply:ChatPrint(string.format("Инвентарь полон! Получено: %d %s", recipe.output_count - left, recipe.output))
                else
                    ply:ChatPrint(string.format("Готово! Получено: %d %s", recipe.output_count, recipe.output))
                end
            end)

            return ""
        end
    end)

    print("[GRM] Ore Processing loaded (Код 118)")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/processlist" })
end
