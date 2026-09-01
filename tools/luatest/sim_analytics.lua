--[[--------------------------------------------------------------------
    sim_analytics — модуль анализа нагрузки GRM:
    сущности, двери, движения и действия игроков, события, net, профили.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_analytics.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local an    = read("lua/autorun/sh_grm_analytics.lua")
local perf  = read("lua/autorun/sh_06_grm_performance.lua")
local panel = read("lua/autorun/client/cl_grm_admin_panel.lua")

print("\n=== 1. СБОР ДАННЫХ ===")
ok(an:find("function AN.EntitySnapshot", 1, true) ~= nil, "срез по сущностям")
ok(an:find('out.simfphys = out.simfphys + 1', 1, true) ~= nil and an:find('lvs_', 1, true) ~= nil,
    "отдельно считаются simfphys и LVS")
ok(an:find("phys:IsMotionEnabled() and not phys:IsAsleep()", 1, true) ~= nil,
    "считается активная физика (главный источник нагрузки от пропов)")
ok(an:find("function AN.DoorSnapshot", 1, true) ~= nil, "срез по дверям")
ok(an:find("out.suspectPhantom = out.suspectPhantom + (#group - 1)", 1, true) ~= nil,
    "фантомные двери определяются по группам дедупликатора")
ok(an:find("function AN.PlayerSnapshot", 1, true) ~= nil, "срез по игрокам")
ok(an:find("mem.moved = mem.moved + delta", 1, true) ~= nil, "считается пройденное расстояние (движение)")
ok(an:find("noclip = ply:GetMoveType() == MOVETYPE_NOCLIP", 1, true) ~= nil, "видно ноклип")
ok(an:find("afk = delta < 1", 1, true) ~= nil, "определяется AFK")
ok(an:find("inVehicle = ply:InVehicle()", 1, true) ~= nil, "видно, кто в транспорте")

print("\n=== 2. СОБЫТИЯ И ДЕЙСТВИЯ ===")
for _, hookName in ipairs({ "PlayerUse", "EntityFireBullets", "PlayerDeath", "PlayerSpawn",
    "PlayerSay", "OnEntityCreated", "EntityRemoved" }) do
    ok(an:find('hook.Add("' .. hookName .. '", "GRM_Analytics', 1, true) ~= nil,
        "учитывается событие " .. hookName)
end
for _, ev in ipairs({ "GRM_FireIncidentOpened", "GRM_ArrestStateChanged", "GRM_FactionDutyChanged",
    "GRM_VehicleDealerSpawned", "GRM_AdminGroupChanged" }) do
    ok(an:find(ev, 1, true) ~= nil, "учитывается игровое событие " .. ev)
end
ok(an:find("function AN.Count", 1, true) ~= nil and an:find("AN.EventTotals", 1, true) ~= nil,
    "счётчики за минуту и за сессию")

print("\n=== 3. ПРОФИЛИРОВАНИЕ ===")
ok(an:find("function AN.ProfileHooks", 1, true) ~= nil, "профиль хуков по требованию")
ok(an:find("local function isGRMHook", 1, true) ~= nil, "оборачиваются только хуки GRM")
ok(an:find("for _, row in ipairs(originals) do hook.Add(row.event, row.name, row.fn) end", 1, true) ~= nil,
    "после профиля хуки возвращаются на место")
ok(an:find("function AN.ProfileNet", 1, true) ~= nil, "профиль сети по требованию")
ok(an:find("net.Start = origStart", 1, true) ~= nil, "net.Start восстанавливается после профиля")
ok(an:find("math.Clamp(math.floor(tonumber(seconds) or 10), 3, 60)", 1, true) ~= nil,
    "профиль ограничен по времени — постоянной нагрузки нет")

print("\n=== 4. ОТЧЁТЫ И ХРАНЕНИЕ ===")
for _, cmd in ipairs({ "grm_analyze", "grm_analyze_ents", "grm_analyze_doors", "grm_analyze_players",
    "grm_analyze_events", "grm_analyze_hooks", "grm_analyze_net", "grm_analyze_dump" }) do
    ok(an:find('concommand.Add("' .. cmd .. '"', 1, true) ~= nil, "команда " .. cmd)
end
ok(an:find("grm_analytics/report_", 1, true) ~= nil, "срез выгружается в файл")
ok(an:find("AN.HistoryMinutes = 30", 1, true) ~= nil, "история ограничена 30 минутами")
ok(an:find("while #AN.History > cap do table.remove(AN.History, 1) end", 1, true) ~= nil,
    "история не растёт бесконечно")
ok(an:find('GRM.Admin.Can(ply, "menu.modules")', 1, true) ~= nil, "доступ к отчётам по праву админ-платформы")
ok(an:find('GRM.Boot.OnMapStart("GRM_Analytics_Start", "late"', 1, true) ~= nil,
    "сбор стартует поздним приоритетом и не мешает загрузке")

print("\n=== 5. ДЕТЕКТОР ФРИЗОВ: ЛОЖНЫЕ СРАБАТЫВАНИЯ ===")
ok(perf:find("local function frameIgnored", 1, true) ~= nil, "есть фильтр «это не фриз»")
ok(perf:find("system.HasFocus", 1, true) ~= nil,
    "свёрнутое окно не считается фризом (GMod в фоне рендерит на 20 Гц — отсюда ровные 50 мс)")
ok(perf:find("gui.IsGameUIVisible()", 1, true) ~= nil, "Esc-меню не считается фризом")
ok(perf:find("прогрев после загрузки", 1, true) ~= nil, "первые 15 секунд не учитываются")
ok(perf:find("last.count = (last.count or 1) + 1", 1, true) ~= nil, "пачка одинаковых всплесков сворачивается")
ok(perf:find("windows = openWindows()", 1, true) ~= nil,
    "в момент рывка фиксируется, какие окна GRM открыты")
ok(perf:find("пропущено кадров (фон, меню, прогрев)", 1, true) ~= nil, "в отчёте видно число отфильтрованных кадров")

print("\n=== 6. ИНТЕРФЕЙС ===")
ok(panel:find('addTab("analytics", "Анализ нагрузки"', 1, true) ~= nil, "вкладка в админ-меню")
ok(panel:find("local function buildAnalytics", 1, true) ~= nil, "раздел собирается")
ok(panel:find('tool("Профиль хуков (10 с)"', 1, true) ~= nil, "кнопка профиля хуков")
ok(panel:find('tool("Двери"', 1, true) ~= nil, "кнопка отчёта по дверям")

print("\n=== 7. МЕТКА ВЗЛОМА ===")
local mm = read("lua/autorun/sh_grm_minimap.lua")
local alarm = read("lua/autorun/sh_grm_alarm_integration.lua")
ok(mm:find("expiresEpoch = os.time()", 1, true) ~= nil,
    "срок жизни метки считается в единой шкале os.time()")
ok(mm:find("local alive = epoch and (epoch > os.time())", 1, true) ~= nil,
    "клиент проверяет срок по своему os.time(), а не по чужому CurTime")
ok(mm:find('timer.Create("GRM_Minimap_TempSweep"', 1, true) ~= nil,
    "сторож раз в 5 секунд убирает просроченные метки")
ok(mm:find("if removed > 0 then send(nil) end", 1, true) ~= nil,
    "обновление рассылается, только когда что-то реально удалено")
ok(alarm:find('GRM.Minimap.AddTempPoint("ВЗЛОМ/ВМЕШАТЕЛЬСТВО", pos, 60)', 1, true) ~= nil,
    "метка взлома живёт 60 секунд")
ok(alarm:find('GRM.Minimap.RemoveTempPoint("ВЗЛОМ/ВМЕШАТЕЛЬСТВО")', 1, true) ~= nil,
    "повторный взлом не копит метки, а переставляет одну")

print(("\nANALYTICS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
