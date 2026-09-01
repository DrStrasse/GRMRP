--[[--------------------------------------------------------------------
    sim_boot — GRM Boot: приоритеты, бюджет на тик, зависимости,
    ленивые задачи и ожидание условий. Живой прогон в моке GMod.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_boot.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

-- Мок конваров с реальными значениями
local convars = {}
_G.CreateConVar = function(name, def)
    convars[name] = tostring(def)
    return {
        GetFloat = function() return tonumber(convars[name]) or 0 end,
        GetInt = function() return math.floor(tonumber(convars[name]) or 0) end,
        GetBool = function() return (tonumber(convars[name]) or 0) ~= 0 end,
        GetString = function() return convars[name] end,
    }
end
_G.GetConVar = function(name) return _G.CreateConVar(name, convars[name] or "0") end
_G.bit = { bor = function(a) return a end }
_G.FCVAR_ARCHIVE = 1
_G.SysTime = function() return stub.time or 0 end
_G.HUD_PRINTCONSOLE = 2

print("\n=== 1. ЗАГРУЗКА МОДУЛЯ ===")
stub.reset()
local loaded, err = stub.loadModule("lua/autorun/sh_00_grm_boot.lua")
ok(loaded, "модуль планировщика поднялся", err)
local B = _G.GRM and _G.GRM.Boot
ok(B and B.Version == "1.1.0", "версия 1.1.0")
ok(B.TIERS.critical == 0 and B.TIERS.idle == 4, "пять приоритетов от critical до idle")

print("\n=== 2. ПРИОРИТЕТЫ И ПОРЯДОК ===")
local order = {}
B.Task("t.late",     "late",     function() order[#order + 1] = "late" end)
B.Task("t.critical", "critical", function() order[#order + 1] = "critical" end)
B.Task("t.normal",   "normal",   function() order[#order + 1] = "normal" end)
B.Task("t.early",    "early",    function() order[#order + 1] = "early" end)
B.Task("t.idle",     "idle",     function() order[#order + 1] = "idle" end)

B.Start()
ok(order[1] == "critical", "critical выполняется сразу при старте", tostring(order[1]))

-- Прогоняем очередь тиками
for _ = 1, 20 do
    stub.time = (stub.time or 0) + 0.1
    _G.hook.Run("Think")
end
ok(table.concat(order, ",") == "critical,early,normal,late",
    "порядок строго по приоритету, idle не выполнялась", table.concat(order, ","))
ok(B.Done("t.late") and not B.Done("t.idle"), "idle-задача ждёт требования")

print("\n=== 3. ЛЕНИВАЯ ЗАДАЧА ПО ТРЕБОВАНИЮ ===")
B.Ensure("t.idle", "тест")
ok(B.Done("t.idle"), "Ensure выполняет ленивую задачу")
local before = #order
B.Ensure("t.idle", "повтор")
ok(#order == before, "повторный Ensure ничего не выполняет второй раз")

print("\n=== 4. ЗАВИСИМОСТИ ===")
local seq = {}
B.Task("dep.child", "early", function() seq[#seq + 1] = "child" end, { needs = { "dep.parent" } })
B.Task("dep.parent", "late", function() seq[#seq + 1] = "parent" end)
for _ = 1, 20 do
    stub.time = stub.time + 0.1
    _G.hook.Run("Think")
end
ok(seq[1] == "parent" and seq[2] == "child",
    "задача с зависимостью ждёт родителя, даже если её приоритет выше", table.concat(seq, ","))

print("\n=== 5. БЮДЖЕТ НА ТИК ===")
-- Пять задач по 1 мс при бюджете 2 мс должны растянуться минимум на 3 тика.
convars["grm_boot_budget_ms"] = "2"
local ran = 0
for i = 1, 5 do
    B.Task("heavy." .. i, "normal", function()
        ran = ran + 1
        stub.time = stub.time + 0.001   -- «работа» 1 мс
    end)
end
local ticks = 0
while ran < 5 and ticks < 50 do
    ticks = ticks + 1
    _G.hook.Run("Think")
end
ok(ran == 5, "все тяжёлые задачи в итоге выполнены")
ok(ticks >= 3, ("работа размазана минимум на 3 тика (получилось %d) — нет пика в один кадр"):format(ticks))

print("\n=== 6. ОЖИДАНИЕ УСЛОВИЯ: «если А — делаем Б, иначе ждём» ===")
local flag, done = false, false
B.When("wait.demo", function() return flag end, function() done = true end, { interval = 0.1 })
for _ = 1, 5 do
    stub.time = stub.time + 0.2
    _G.hook.Run("Think")
end
ok(not done, "пока условие не выполнено — действие ждёт")
flag = true
stub.time = stub.time + 0.2
_G.hook.Run("Think")
ok(done, "как только условие выполнилось — действие сработало")

local immediate = false
B.When("wait.instant", function() return true end, function() immediate = true end)
ok(immediate, "уже выполненное условие срабатывает сразу, без таймера")

print("\n=== 7. ТРИГГЕР ПО ЧАТ-КОМАНДЕ ===")
local shopLoaded = false
B.Lazy("demo.shop", function() shopLoaded = true end)
B.OnChat({ "/shop", "!shop" }, "demo.shop")
_G.hook.Run("PlayerSay", stub.makeEntity({ class = "player", isPlayer = true }), "/другое")
ok(not shopLoaded, "посторонняя команда ничего не поднимает")
_G.hook.Run("PlayerSay", stub.makeEntity({ class = "player", isPlayer = true }), "/shop")
ok(shopLoaded, "команда игрока поднимает ленивую подсистему")

print("\n=== 8. ТРИГГЕР ПО ПЕРВОМУ ИГРОКУ И ПО ENTITY ===")
local firstPlayerRan, usedRan = false, false
B.Lazy("demo.firstplayer", function() firstPlayerRan = true end)
B.OnFirstPlayer("demo.firstplayer")
ok(not firstPlayerRan, "на пустом сервере задача не выполняется вообще")
_G.hook.Run("PlayerInitialSpawn", stub.makeEntity({ class = "player", isPlayer = true }))
ok(firstPlayerRan, "первый вошедший игрок поднимает подсистему")

B.Lazy("demo.use", function() usedRan = true end)
B.OnUseClass("grm_atm", "demo.use")
_G.hook.Run("PlayerUse", stub.makeEntity({ class = "player", isPlayer = true }), stub.makeEntity({ class = "grm_atm" }))
ok(usedRan, "использование entity поднимает подсистему")

print("\n=== 9. УСТОЙЧИВОСТЬ И ДИАГНОСТИКА ===")
B.Task("bad.task", "late", function() error("умышленная ошибка") end)
for _ = 1, 10 do _G.hook.Run("Think") end
ok(B.Tasks["bad.task"].state == "failed", "падение одной задачи не ломает очередь")
ok(B.Done("t.normal"), "остальные задачи остались выполненными")
local rows, stats = B.Status()
ok(#rows > 0 and stats.ran > 0, "Status() отдаёт отчёт по задачам")
ok(stub.commands and stub.commands["grm_boot_status"] ~= nil, "есть команда grm_boot_status")

print("\n=== 10. ПРИМЕНЕНИЕ В МОДУЛЯХ ===")
local files = {
    { "lua/autorun/sh_grm_doors.lua", "doors.db", "early" },
    { "lua/autorun/sh_grm_perm_entities.lua", "perm.entities", "early" },
    { "lua/autorun/sh_grm_incassation.lua", "incass.atms", "normal" },
    { "lua/autorun/sh_grm_fire.lua", "fire.state", "normal" },
    { "lua/autorun/server/sv_grm_phone.lua", "phone.map", "normal" },
    { "lua/autorun/server/sv_grm_alarm.lua", "alarm.map", "normal" },
    { "lua/autorun/server/sv_grm_cctv.lua", "cctv.map", "normal" },
    { "lua/autorun/server/sv_grm_industry.lua", "industry.map", "late" },
    { "lua/autorun/server/sv_grm_industry_logistics.lua", "industry.logistics", "late" },
    { "lua/autorun/server/sv_grm_mining_saver.lua", "mining.saver", "late" },
    { "lua/autorun/sh_grm_quests.lua", "quests.npc", "late" },
    { "lua/autorun/sh_grm_jobs_v5.lua", "jobs.garbage", "late" },
}
local converted = 0
for _, row in ipairs(files) do
    local src = read(row[1])
    if src:find('GRM.Boot.Task("' .. row[2] .. '", "' .. row[3] .. '"', 1, true) then converted = converted + 1 end
end
ok(converted == #files, ("стартовые загрузки переведены на приоритеты: %d/%d"):format(converted, #files))

local shop = read("lua/autorun/sh_grm_phone_shop.lua")
ok(shop:find('GRM.Boot.Lazy("phoneshop.owned"', 1, true) ~= nil, "реестр телефонов — ленивая задача")
ok(shop:find('GRM.Boot.OnChat({ "/phoneshop"', 1, true) ~= nil, "поднимается по команде игрока")
ok(shop:find('GRM.Boot.OnUseClass("grm_phone_terminal"', 1, true) ~= nil, "и по использованию терминала")
ok(shop:find('GRM.Boot.OnFirstPlayer("phoneshop.owned")', 1, true) ~= nil, "и при первом игроке (на пустом сервере — никогда)")

local waiters = 0
for _, f in ipairs({ "sh_grm_fire_access", "sh_grm_alarm_access", "sh_grm_doors_access",
                     "sh_grm_wanted_access", "sh_grm_cctv_access", "sh_grm_phone_access" }) do
    if read("lua/autorun/" .. f .. ".lua"):find("GRM.Boot.When", 1, true) then waiters = waiters + 1 end
end
ok(waiters == 6, ("шесть опрашивающих таймеров доступов заменены ожиданием условия: %d/6"):format(waiters))

print(("\nBOOT: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
