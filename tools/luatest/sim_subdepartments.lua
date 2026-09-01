--[[--------------------------------------------------------------------
    sim_subdepartments.lua
    Тест-стенд для иерархии «Отделы ➔ Подотделы» (Structure v5.0).
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

print("=== ТЕСТ: Иерархия отделов и подотделов (Structure v5.0) ===")
local facCode = assert(io.open("lua/autorun/sh_factions.lua", "rb")):read("*a")
local coreCode = assert(io.open("lua/autorun/sh_grm_factions_core_v4.lua", "rb")):read("*a")
local uiCode = assert(io.open("lua/autorun/client/cl_grm_factions_unified_ui.lua", "rb")):read("*a")

ok(facCode:find("function GRM.Factions.SubdepartmentDisplayName", 1, true) ~= nil, "GRM.Factions.SubdepartmentDisplayName существует")
ok(facCode:find("function GRM.Factions.ResolveSubdepartmentKey", 1, true) ~= nil, "GRM.Factions.ResolveSubdepartmentKey существует")
ok(facCode:find("function GRM.Factions.GetSubdepartments", 1, true) ~= nil, "GRM.Factions.GetSubdepartments существует")
ok(facCode:find("f.Subdepartments = istable(f.Subdepartments)", 1, true) ~= nil, "ensureDefaults инициализирует f.Subdepartments")
ok(facCode:find("f.SubdepartmentDisplayNames", 1, true) ~= nil, "ensureDefaults инициализирует f.SubdepartmentDisplayNames")
ok(facCode:find("Subdepartments   = f.Subdepartments", 1, true) ~= nil, "Subdepartments синхронизируются клиенту")
ok(facCode:find("Subdepartment=tostring(rec.Subdepartment", 1, true) ~= nil, "Члены фракции несут поле Subdepartment")

ok(facCode:find("local function addSubdepartment", 1, true) ~= nil, "Серверная функция addSubdepartment существует")
ok(facCode:find("local function removeSubdepartment", 1, true) ~= nil, "Серверная функция removeSubdepartment существует")
ok(facCode:find("local function renameSubdepartment", 1, true) ~= nil, "Серверная функция renameSubdepartment существует")
ok(facCode:find("local function setMemberSubdepartment", 1, true) ~= nil, "Серверная функция setMemberSubdepartment существует")

ok(facCode:find('action == "addSubdepartment"', 1, true) ~= nil, "Сетевое действие addSubdepartment зарегистрировано")
ok(facCode:find('action == "removeSubdepartment"', 1, true) ~= nil, "Сетевое действие removeSubdepartment зарегистрировано")
ok(facCode:find('action == "renameSubdepartment"', 1, true) ~= nil, "Сетевое действие renameSubdepartment зарегистрировано")
ok(facCode:find('action == "setSubdepartment"', 1, true) ~= nil, "Сетевое действие setSubdepartment зарегистрировано")

ok(facCode:find("_G.FactionsAPI.AddSubdepartment", 1, true) ~= nil, "FactionsAPI экспортирует AddSubdepartment")
ok(facCode:find("_G.FactionsAPI.RemoveSubdepartment", 1, true) ~= nil, "FactionsAPI экспортирует RemoveSubdepartment")
ok(facCode:find("_G.FactionsAPI.RenameSubdepartment", 1, true) ~= nil, "FactionsAPI экспортирует RenameSubdepartment")
ok(facCode:find("_G.FactionsAPI.SetMemberSubdepartment", 1, true) ~= nil, "FactionsAPI экспортирует SetMemberSubdepartment")

ok(coreCode:find('C.Version="5.0.0"', 1, true) ~= nil, "Faction Core v5.0.0")
ok(coreCode:find("GRM_FactionMemberSubdepartmentChanged", 1, true) ~= nil, "Core v5.0 слушает событие смены подотдела")
ok(coreCode:find("subdepartment_changed", 1, true) ~= nil, "Смена подотдела пишется в кадровое дело сотрудника")

ok(uiCode:find("GRM.Factions.GetSubdepartments", 1, true) ~= nil, "Unified UI отображает дерево подотделов")
ok(uiCode:find("SubdepartmentDisplayName", 1, true) ~= nil, "Unified UI показывает подотдел в таблице состава")

print(string.format("\nРЕЗУЛЬТАТ: Пройдено проверок: %d/%d (провалов: %d)", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
print("ALL SUBDEPARTMENT ASSERTIONS PASSED!")
