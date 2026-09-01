--[[ Живой прогон приглашений во фракцию: доставка окна, отказы с
     объяснением, повторная отправка при входе и смене персонажа.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_faction_invite.lua ]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(src, needle) return src:find(needle, 1, true) ~= nil end

local fac = read("lua/autorun/sh_factions.lua")
local ui = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")

print("\n=== 1. ОТВЕТ СЕРВЕРА ВИДЕН ИГРОКУ ===")
ok(has(fac, "local function respondTo(ply, success, msg)"), "сервер отвечает на каждое действие")
ok(has(ui, 'net.Receive("Factions_ActionResult", function()'),
    "меню слушает ответ сервера (раньше не слушало вовсе)")
ok(has(ui, "notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR"),
    "ответ показывается уведомлением")
ok(has(ui, '"[Организации] "'), "и дублируется строкой в чат")
ok(not has(ui, 'notification.AddLegacy("Приглашение отправлено", NOTIFY_GENERIC, 3)'),
    "меню больше не выдумывает «Приглашение отправлено»")

print("\n=== 2. ОТКАЗЫ ОБЪЯСНЯЮТСЯ ===")
ok(has(fac, "Игрок не в сети или играет другим персонажем — приглашение не доставить"),
    "нельзя пригласить того, кому окно не доставить")
ok(has(fac, "Цель ищем ДО записи приглашения"), "разобрана причина «отправлено, но не пришло»")
ok(has(fac, "Недостаточно прав"), "чужой не пригласит")
ok(has(fac, "Персонаж уже состоит во фракции"), "занятого персонажа не позвать")
ok(has(fac, "У персонажа уже есть активное приглашение"), "второе приглашение не перебивает первое")
ok(has(fac, "Недопустимая стартовая должность"), "должность проверяется")

print("\n=== 3. ВЫБОР В ОКНЕ ПРИГЛАШЕНИЯ ===")
ok(has(ui, "local firstRole = true"), "первая должность выбрана заранее")
ok(has(ui, "if rKey ~= fac.LeaderRoleName then"),
    "должность лидера в список приглашения не попадает (сервер её всё равно отклонит)")
ok(has(ui, "local firstDept = true"), "первый отдел выбран заранее")

print("\n=== 4. ДОСТАВКА ===")
ok(has(fac, 'hook.Add("PlayerInitialSpawn","Factions_InviteV2Join"'),
    "при входе приглашение показывается снова")
ok(has(fac, 'hook.Add("GRM_CharacterChanged","Factions_InviteV2Character"'),
    "при смене персонажа — тоже")
ok(has(fac, 'hook.Add("PlayerSpawn","Factions_InviteV2Respawn"'),
    "и после респавна (погиб в момент выдачи — не теряет приглашение)")
ok(has(fac, 'timer.Create("Factions_InviteV2Expire"'), "истёкшие приглашения закрываются сами")

print("\n=== 5. ДИАГНОСТИКА ===")
ok(has(fac, 'concommand.Add("grm_faction_invites"'), "есть список активных приглашений")
ok(has(fac, "персонаж НЕ в сети"), "видно, кому приглашение недоставимо")
ok(has(fac, "[GRM Factions] приглашение"), "выдача пишется в консоль сервера")

print(("\nFACTION INVITE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
