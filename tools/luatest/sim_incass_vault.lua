--[[--------------------------------------------------------------------
    sim_incass_vault — заказ владельца 19.08: дистанция сдачи инкассации
    в хранилище была слишком большой (сдавали через соседние помещения),
    а подсказку у хранилища видели все подряд.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_incass_vault.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local s = read("lua/autorun/sh_grm_incassation.lua")

print("\n=== 1. ДИСТАНЦИЯ ===")
ok(s:find("VaultRadius             = 140", 1, true) ~= nil, "радиус хранилища уменьшен с 320 до 140")
ok(s:find("* 1.5) ^ 2)", 1, true) == nil,
    "убран множитель 1.5 — раньше фактическая дистанция была 480 юнитов")
ok(s:find("VaultRequireLineOfSight = true", 1, true) ~= nil, "включена проверка прямой видимости")
ok(s:find("local function vaultReachable", 1, true) ~= nil, "единая проверка досягаемости хранилища")
ok(s:find('return false, "Хранилище за стеной — подойдите к нему"', 1, true) ~= nil,
    "через стену сдать нельзя, и игрок понимает почему")
ok(s:find("MASK_SOLID_BRUSHONLY", 1, true) ~= nil,
    "луч проверяет именно геометрию карты, а не случайные предметы")
ok(select(2, s:gsub("vaultReachable%(ply, ", "")) >= 4,
    "проверка применяется во всех точках сдачи, а не в одной")

print("\n=== 2. КТО ВИДИТ ПОДСКАЗКУ ===")
ok(s:find("function I.RefreshAccessFlag", 1, true) ~= nil, "сервер считает право на инкассацию")
ok(s:find('ply:SetNWBool("GRMIncass_Allowed", ok)', 1, true) ~= nil, "право зеркалится клиенту")
ok(s:find('local allowedHint = ply:GetNWBool("GRMIncass_Allowed", false) or ply:IsSuperAdmin()', 1, true) ~= nil,
    "подсказки показываются только допущенным и суперадмину")
ok(s:find("if IsValid(targetEnt) and allowedHint then", 1, true) ~= nil,
    "прохожий больше не видит подсказку у хранилища и банкомата")
ok(s:find('hook.Add("PlayerSpawn", "GRM_Incass_AccessFlag"', 1, true) ~= nil, "флаг обновляется при спавне")
ok(s:find('hook.Add("GRM_FactionDutyChanged", "GRM_Incass_AccessFlag"', 1, true) ~= nil,
    "и при выходе на службу / со службы")
ok(s:find('timer.Create("GRM_Incass_AccessSweep", 15, 0', 1, true) ~= nil,
    "изменения ролей администрацией подхватываются раз в 15 секунд")

print("\n=== 3. КЛИЕНТСКИЙ ПОИСК ХРАНИЛИЩА ===")
ok(s:find("local reach = ((I.Config and I.Config.VaultRadius) or 140) ^ 2", 1, true) ~= nil,
    "клиент ищет хранилище тем же радиусом, что и сервер")
ok(s:find("(350 * 350)", 1, true) == nil, "старый радиус 350 больше нигде не используется")

print(("\nINCASS VAULT: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
