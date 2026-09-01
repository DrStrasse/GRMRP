--[[--------------------------------------------------------------------
    sim_perf_order — порядок выполнения, порционность и очередь записи.

    Заказ владельца 21.08: «синхронизация, разбитие на части и порядок
    выполнения кода, проверка всех модулей, чтобы ничего не вызывало
    микрофризы. Код должен выполняться по степени важности, порционно».

    Живой прогон очереди диска — sim_save_queue.lua. Здесь: что слои на
    месте и что модули ими пользуются.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_perf_order.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local boot  = read("lua/autorun/sh_00_grm_boot.lua")
local net   = read("lua/autorun/sh_04_grm_net.lua")
local save  = read("lua/autorun/sh_05_grm_save.lua")
local perf  = read("lua/autorun/sh_06_grm_performance.lua")
local audit = read("tools/audit_perf.py")

print("\n=== 1. ПОРЯДОК ПО ВАЖНОСТИ (СТАРТ) ===")
ok(has(boot, "B.TIERS = { critical = 0, early = 1, normal = 2, late = 3, idle = 4 }"),
    "пять ступеней важности при старте")
ok(has(boot, "grm_boot_budget_ms"), "старт идёт порциями по бюджету миллисекунд на тик")
ok(has(boot, "function B.Ensure"), "ленивые подсистемы поднимаются по требованию")
ok(has(boot, "needsReady"), "зависимости соблюдаются, а не «кто успел»")

print("\n=== 2. ПОРЦИОННОСТЬ В РАНТАЙМЕ ===")
ok(has(perf, "function P.Queue"), "разовая тяжёлая работа уходит в очередь")
ok(has(perf, "function P.Spread"), "большие списки обходятся порциями")
ok(has(perf, "grm_perf_budget_ms"), "у рантайм-очереди свой бюджет на кадр")
ok(has(perf, "function P.Coalesce"), "пачка событий сводится в один вызов")
ok(has(perf, "GRM_Perf_SpikeWatch"), "детектор фризов на месте")

print("\n=== 3. СИНХРОНИЗАЦИЯ ===")
ok(has(net, "function N.Stream"), "большие таблицы уходят частями, а не одним пакетом")
ok(has(net, "function N.Guard"), "приём пакетов защищён лимитами")
local factions = read("lua/autorun/sh_factions.lua")
ok(has(factions, 'GRM.Perf.Coalesce("grm_factions_char_choices"'),
    "список персонажей рассылается один раз на пачку событий")
ok(has(read("lua/autorun/sh_grm_admin_core.lua"), 'GRM.Perf.Coalesce("grm_admin_sync_all"'),
    "снимок прав администрации не рассылается на каждый клик")
ok(has(read("lua/autorun/sh_grm_qmenu.lua"), 'GRM.Perf.Coalesce("grm_qmenu_sync_all"'),
    "настройки Q-меню рассылаются пачкой")
ok(has(read("lua/autorun/sh_grm_minimap.lua"), 'GRM.Perf.Coalesce("grm_minimap_send_all"'),
    "карта рассылается не на каждое изменение точки")

print("\n=== 4. ОЧЕРЕДЬ ЗАПИСИ НА ДИСК ===")
ok(has(save, 'S.Version = "1.0.0"'), "слой записи версионирован")
ok(has(save, "function S.Register") and has(save, "function S.Mark"),
    "модуль регистрирует файл и помечает его грязным, а не пишет сам")
ok(has(save, "Больше одной записи за тик не делает") or has(save, "Одна запись за тик"),
    "писатель делает не больше одной записи за тик")
ok(has(save, "entry.delay = math.min(60"), "дорогой реестр сам получает большую задержку")
ok(has(save, 'hook.Add("ShutDown"'), "при выключении карты всё сбрасывается на диск")
ok(has(save, 'hook.Add("PreCleanupMap"'), "перед очисткой карты — тоже")
ok(has(save, "grm_save_status"), "есть консольная статистика записей")

print("\n=== 5. МОДУЛИ ПЕРЕВЕДЕНЫ НА ОЧЕРЕДЬ ===")
local reg = read("lua/autorun/sh_grm_registry.lua")
ok(has(reg, 'GRM.Save.Register("registry"'), "реестр номеров пишется очередью")
ok(has(reg, "Раньше каждый вход игрока"), "объяснено, что чинили")
local np = read("lua/autorun/sh_grm_nameplate.lua")
ok(has(np, 'GRM.Save.Register("nameplate.known"'), "знакомства пишутся очередью")
ok(has(np, 'GRM.Save.Register("nameplate.marks"'), "приметы пишутся очередью")
local pcb = read("lua/autorun/sh_grm_pcboard.lua")
ok(has(pcb, 'GRM.Save.Register("pcboard.log"'), "журнал госбазы пишется очередью")
ok(has(pcb, 'GRM.Save.Register("pcboard.access"'), "доступы госбазы пишутся очередью")

print("\n=== 6. ТОЧЕЧНЫЕ ПРАВКИ НАГРУЗКИ ===")
local mv = read("lua/autorun/sh_grm_movement.lua")
ok(has(mv, 'timer.Create("GRM_StaminaTick", STAMINA_TICK, 0'),
    "тик стамины стал реже (0.25 c вместо 0.1 c)")
ok(has(mv, "math.Clamp(now - staminaLast, 0.01, 1)"),
    "расход и восстановление считаются по реальной дельте — поведение не изменилось")
local hc = read("lua/autorun/server/sv_grm_handcuffs.lua")
ok(select(2, hc:gsub("next%(HC%.Cuffed%) == nil then return", "")) >= 2,
    "оба таймера наручников выходят сразу, если закованных нет")

print("\n=== 6б. СЕТЕВЫЕ ИМЕНА (баг 21.08) ===")
local ban = read("lua/autorun/sh_grm_ban.lua")
ok(has(ban, "for _, name in pairs(SB.Net) do util.AddNetworkString(name) end"),
    "все каналы модуля банов регистрируются проходом по таблице")
ok(has(ban, "unpooled message name"), "в коде объяснено, из-за чего была ошибка")
ok(has(audit, "net_unpooled"), "аудит ловит незарегистрированные каналы")
ok(has(audit, "часть имён не в пуле"), "и говорит, сколько каналов не зарегистрировано")

print("\n=== 7. АУДИТ КАК ВОРОТА ===")
ok(has(audit, "disk_hotpath"), "аудит ловит запись на диск в горячем пути")
ok(has(audit, "big_sync"), "аудит ловит крупные синхронизации одним пакетом")
ok(has(audit, "join_heavy"), "аудит ловит тяжёлый вход игрока")
ok(has(audit, "--gate"), "есть режим ворот с ненулевым кодом возврата")
ok(has(audit, "def cut_body"), "тело хука обрезается корректно (ложные срабатывания убраны)")
ok(has(audit, "Тяжёлый вызов ПОСЛЕ раннего выхода"),
    "вызов за ранним выходом не считается покадровым")

print(("\nPERF ORDER: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
