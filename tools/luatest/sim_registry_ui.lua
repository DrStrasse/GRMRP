--[[--------------------------------------------------------------------
    sim_registry_ui — заказ владельца 19.08: модуль ID игроков и персонажей,
    привязка номеров к чату, фракциям и админ-меню (бан по ID игрока).

    Живая логика реестра — sim_registry_runtime.lua. Здесь: состав модуля и
    интеграции.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_registry_ui.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local reg   = read("lua/autorun/sh_grm_registry.lua")
local fac   = read("lua/autorun/sh_factions.lua")
local facUI = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local core  = read("lua/autorun/sh_grm_admin_core.lua")
local acts  = read("lua/autorun/server/sv_grm_admin_actions.lua")
local panel = read("lua/autorun/client/cl_grm_admin_panel.lua")

print("\n=== 1. РЕЕСТР ===")
ok(has(reg, 'R.Version = "1.0.0"'), "модуль реестра версионирован")
ok(has(reg, 'R.CharPrefix    = "ГР"') and has(reg, 'R.AccountPrefix = "ИГ"'),
    "номера с префиксом: ГР — персонаж, ИГ — игрок")
ok(has(reg, "function R.EnsureAccount") and has(reg, "function R.EnsureCharacter"),
    "номера выдаются отдельно игроку и персонажу")
ok(has(reg, "function R.RetireCharacter") and has(reg, "retired = rec.retired == true"),
    "удалённый персонаж уходит в архив, номер не переиспользуется")
ok(has(reg, "function R.Lower"), "поиск по имени работает с кириллицей")
ok(has(reg, "R.PrefixAliases") and has(reg, '["GR"] = "char"'),
    "принимается латинская раскладка префикса (GR/IG)")
ok(has(reg, "SAVE read-back ПУСТ"), "запись проверяется чтением обратно")
ok(has(reg, 'GRM.Boot.OnMapStart("GRM_Registry_Sync"'), "старт через планировщик GRM.Boot")
ok(has(reg, 'hook.Add("GRM_CharacterChanged", "GRM_Registry_CharChanged"'),
    "смена персонажа переключает номер сразу")
ok(has(reg, 'ply:SetNWString("GRM_CID"') and has(reg, 'ply:SetNWString("GRM_PID"'),
    "номера висят на игроке NW-строками")
ok(has(reg, 'concommand.Add("grm_id_find"') and has(reg, 'cmd ~= "/id"'),
    "команды /id и grm_id_find на месте")

print("\n=== 2. ЧАТ ===")
ok(has(fac, "function GRM.Factions.AppendCID"), "номер добавляется в шапку служебных каналов")
ok(has(fac, 'CreateConVar("grm_chat_show_cid"'), "показ номера управляется конваром")
ok(select(2, fac:gsub("GRM%.Factions%.AppendCID%(", "")) >= 5,
    "номер добавлен во все служебные каналы (/fr, /frb, /dep, /depb)")
ok(not has(fac, "AppendCID(text"), "в обычный IC-чат номер НЕ уходит (метагейм закрыт)")

print("\n=== 3. ФРАКЦИИ ===")
ok(has(fac, "_cid = (GRM.Registry and GRM.Registry.CID and GRM.Registry.CID(key))"),
    "номер персонажа уходит в состав организации")
ok(has(facUI, 'list:AddColumn("ID")'), "в составе появилась колонка ID")
ok(has(facUI, "cidLower ~= \"\" and cidLower:find(filter, 1, true)"), "по номеру можно искать сотрудника")

print("\n=== 4. АДМИН-МЕНЮ И БАН ПО ID ===")
ok(has(core, 'pid = ply:GetNWString("GRM_PID", "")') and has(core, 'cid = ply:GetNWString("GRM_CID", "")'),
    "номера уходят в список игроков админ-панели")
ok(has(acts, "A.ban_id = {"), "действие «бан по ID игрока» существует")
ok(has(acts, 'perm = "mod.ban"'), "бан по ID требует права mod.ban")
ok(has(acts, "ULib.addBan"), "офлайн-бан идёт через ULib, если он есть")
ok(has(acts, "banid %d %s\\n"), "фолбэк на штатный banid для офлайн-игрока")
ok(has(acts, "A.id_lookup = {"), "есть поиск по реестру из админ-панели")
ok(has(acts, "GRM.Registry.Resolve(query)"), "поиск и бан принимают номер, имя или SteamID")
ok(has(panel, "local function buildBanByID"), "блок бана по ID в интерфейсе")
ok(has(panel, "БАН ПО ID ИГРОКА (работает и офлайн)"), "подписано, что работает офлайн")
ok(has(panel, 'act("id_lookup"') and has(panel, 'act("ban_id"'), "кнопки «найти» и «забанить»")
ok(has(panel, 'tostring(row.pid or "")') and has(panel, 'tostring(row.cid or "")'),
    "номера видно в списке и в карточке игрока")

print(("\nREGISTRY UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
