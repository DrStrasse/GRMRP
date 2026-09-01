--[[--------------------------------------------------------------------
    GRM Permissions Test (Код 125)
    Тестовые команды для проверки системы доступов
----------------------------------------------------------------------]]

if SERVER then
    concommand.Add("grm_perms_test", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end

        print("=== Тест системы доступов ===")

        -- Загружаем данные
        if GRM.FactionPerms then
            GRM.FactionPerms.Load()
            print("FactionPerms загружены")
        end

        -- Тест законов
        if GRM.Laws then
            local laws = GRM.Laws.GetAll()
            print("Законов: " .. #laws)
        end

        -- Тест экономики
        if GRM.Economy then
            print("Economy модуль загружен")
        end

        -- Тест фракций
        if Factions then
            print("Factions загружены: " .. table.Count(Factions))
        end

        print("=== Тест завершён ===")
    end)

    print("[GRM] Permissions Test loaded")
end
