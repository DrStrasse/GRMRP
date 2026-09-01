--[[--------------------------------------------------------------------
    sim_structure_v41_and_persistence.lua
    Тест-стенд для Structure v4.1 (RoleDisplayNames + Unified Factions UI)
    и комплексного исправления персистентности и подгрузки карты.
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, msg)
    if v then
        pass = pass + 1
        print("  ok  " .. msg)
    else
        fail = fail + 1
        print("  FAIL " .. msg)
    end
end

print("=== ТЕСТ 1: Structure v4.1 — Стабильные ключи должностей ===")
local facCode = assert(io.open("lua/autorun/sh_factions.lua", "rb")):read("*a")
local coreCode = assert(io.open("lua/autorun/sh_grm_factions_core_v4.lua", "rb")):read("*a")

ok(facCode:find("function GRM.Factions.RoleDisplayName", 1, true) ~= nil, "GRM.Factions.RoleDisplayName resolver существует")
ok(facCode:find("function GRM.Factions.ResolveRoleKey", 1, true) ~= nil, "GRM.Factions.ResolveRoleKey resolver существует")
ok(facCode:find("RoleDisplayNames = f.RoleDisplayNames", 1, true) ~= nil, "RoleDisplayNames синхронизируются клиенту")
ok(facCode:find("f.RoleDisplayNames[roleKey] = newDisplayName", 1, true) ~= nil, "renameRole обновляет только display metadata")
ok((coreCode:match('C%.Version="(%d+)') or "0") + 0 >= 4, "Faction Core не ниже v4.1.0")
ok(coreCode:find("f.RoleDisplayNames", 1, true) ~= nil, "Faction Core мигрирует и проверяет RoleDisplayNames")
ok(facCode:find("FactionsAPI.GetRoleDisplayName", 1, true) ~= nil, "FactionsAPI экспортирует GetRoleDisplayName")

print("=== ТЕСТ 2: Единый UI фракций (Unified UI) ===")
local uiCode = assert(io.open("lua/autorun/client/cl_grm_factions_unified_ui.lua", "rb")):read("*a")
ok(uiCode:find("GRM.Factions.UnifiedUI", 1, true) ~= nil, "Unified UI модуль зарегистрирован")
ok(uiCode:find("addTabBtn(\"overview\"", 1, true) ~= nil, "Вкладка «Обзор» присутствует")
ok(uiCode:find("addTabBtn(\"members\"", 1, true) ~= nil, "Вкладка «Сотрудники» присутствует")
ok(uiCode:find("addTabBtn(\"structure\"", 1, true) ~= nil, "Вкладка «Структура» присутствует")
ok(uiCode:find("addTabBtn(\"personnel\"", 1, true) ~= nil, "Вкладка «Кадровые дела» присутствует")
ok(uiCode:find("GRM.UI.Track", 1, true) ~= nil, "Singleton lifecycle управляется через GRM.UI.Track")

print("=== ТЕСТ 3: Защита памяти FFD и персистентность дверей ===")
local ffdLinkCode = assert(io.open("lua/autorun/sh_grm_ffdlink.lua", "rb")):read("*a")
ok(ffdLinkCode:find('GRM._ffdLinkVer = "1.2.0"', 1, true) ~= nil, "FFD Link v1.2.0")
ok(ffdLinkCode:find("ent.Sliding_BasePos or ent:GetPos()", 1, true) ~= nil, "resolveEntry учитывает Sliding_BasePos")
ok(ffdLinkCode:find("Resolve(ctrl, false)", 1, true) ~= nil, "Fade зовёт Resolve с prune=false (память не затирается)")
ok(ffdLinkCode:find("RefreshAllControllers", 1, true) ~= nil, "RefreshAllControllers присутствует для синка после загрузки карты")
ok(ffdLinkCode:find('GRM.PermData.Extract["prop_physics"]', 1, true) ~= nil, "PermData Extract для prop_physics зарегистрирован в autorun")
ok(ffdLinkCode:find('GRM.PermData.Apply["prop_physics"]', 1, true) ~= nil, "PermData Apply для prop_physics зарегистрирован в autorun")
ok(ffdLinkCode:find('duplicator.RegisterEntityModifier("FFD_FadingDoor"', 1, true) ~= nil, "Duplicator modifier FFD_FadingDoor в autorun")

print("=== ТЕСТ 4: Защита памяти сканнеров и кейпадов ===")
local scStoolCode = assert(io.open("lua/weapons/gmod_tool/stools/ffd_scanner.lua", "rb")):read("*a")
local kpStoolCode = assert(io.open("lua/weapons/gmod_tool/stools/ffd_keypad.lua", "rb")):read("*a")
local scEntCode = assert(io.open("lua/entities/grm_scanner/init.lua", "rb")):read("*a")
local kpEntCode = assert(io.open("lua/entities/grm_keypad/init.lua", "rb")):read("*a")

ok(scStoolCode:find('GRM_ScannerData', 1, true) ~= nil, "ffd_scanner сохраняет Duplicator modifier")
ok(kpStoolCode:find('GRM_KeypadData', 1, true) ~= nil, "ffd_keypad сохраняет Duplicator modifier")
ok(scEntCode:find('duplicator.RegisterEntityModifier("GRM_ScannerData"', 1, true) ~= nil, "grm_scanner регистрирует Duplicator modifier")
ok(kpEntCode:find('duplicator.RegisterEntityModifier("GRM_KeypadData"', 1, true) ~= nil, "grm_keypad регистрирует Duplicator modifier")
ok(scStoolCode:find("string.format('ffd_scanner_faction %q'", 1, true) ~= nil, "ffd_scanner экранирует русские/многословные фракции при ПКМ")
ok(kpStoolCode:find("string.format('ffd_keypad_password %q'", 1, true) ~= nil, "ffd_keypad экранирует PIN при ПКМ")

print("=== ТЕСТ 5: Восстановление объектов при PostCleanupMap ===")
local phoneCode = assert(io.open("lua/autorun/server/sv_grm_phone.lua", "rb")):read("*a")
local roomtapCode = assert(io.open("lua/autorun/server/sv_grm_roomtap.lua", "rb")):read("*a")
local oreCode = assert(io.open("lua/autorun/server/sv_grm_ore_spawner.lua", "rb")):read("*a")
local miningCode = assert(io.open("lua/autorun/server/sv_grm_mining_saver.lua", "rb")):read("*a")
local bcCode = assert(io.open("lua/autorun/sh_grm_broadcast.lua", "rb")):read("*a")
local rnCode = assert(io.open("lua/autorun/sh_grm_radionet.lua", "rb")):read("*a")
local arrestCode = assert(io.open("lua/autorun/sh_grm_arrest.lua", "rb")):read("*a")
local spawnCode = assert(io.open("lua/autorun/sh_spawn_points.lua", "rb")):read("*a")
local foodCode = assert(io.open("lua/autorun/server/sv_grm_food.lua", "rb")):read("*a")
local jobsCode = assert(io.open("lua/autorun/sh_grm_jobs.lua", "rb")):read("*a")
local permCode = assert(io.open("lua/autorun/sh_grm_perm_entities.lua", "rb")):read("*a")

ok(phoneCode:find('hook.Add("PostCleanupMap", "GRM_Phone_Cleanup"', 1, true) ~= nil, "sv_grm_phone восстанавливается на PostCleanupMap")
ok(roomtapCode:find('hook.Add("PostCleanupMap", "GRM_RoomTap_Cleanup"', 1, true) ~= nil, "sv_grm_roomtap восстанавливается на PostCleanupMap")
ok(oreCode:find('hook.Add("PostCleanupMap", "GRM_OreSpawner_Cleanup"', 1, true) ~= nil, "sv_grm_ore_spawner восстанавливается на PostCleanupMap")
ok(miningCode:find('hook.Add("PostCleanupMap", "GRM_Saver_Cleanup"', 1, true) ~= nil, "sv_grm_mining_saver восстанавливается на PostCleanupMap")
ok(bcCode:find('hook.Add("PostCleanupMap", "GRM_BC_Cleanup"', 1, true) ~= nil, "sh_grm_broadcast восстанавливается на PostCleanupMap")
ok(rnCode:find('hook.Add("PostCleanupMap", "GRM_RN_Cleanup"', 1, true) ~= nil, "sh_grm_radionet восстанавливается на PostCleanupMap")
ok(arrestCode:find('hook.Add("PostCleanupMap", "GRM_Arrest_Cleanup"', 1, true) ~= nil, "sh_grm_arrest восстанавливается на PostCleanupMap")
ok(spawnCode:find('hook.Add("PostCleanupMap", "SpawnPoints_ReloadCleanup"', 1, true) ~= nil, "sh_spawn_points восстанавливается на PostCleanupMap")
ok(foodCode:find('hook.Add("PostCleanupMap", "GRM_Food_Cleanup"', 1, true) ~= nil, "sv_grm_food восстанавливается на PostCleanupMap")
ok(jobsCode:find('hook.Add("PostCleanupMap", "GRM_Jobs_Cleanup"', 1, true) ~= nil, "sh_grm_jobs восстанавливается на PostCleanupMap")
ok(permCode:find('RefreshAllControllers', 1, true) ~= nil, "sh_grm_perm_entities синхронизирует контроллеры после спавна")

print(string.format("\nРЕЗУЛЬТАТ: Пройдено проверок: %d/%d (провалов: %d)", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
print("ALL TESTS PASSED SUCCESSFULLY!")
