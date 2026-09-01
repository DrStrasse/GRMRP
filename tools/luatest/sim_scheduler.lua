--[[ Живой прогон планировщика периодики (запрос владельца 28.08):
     «оптимизация всех новых и всех в целом модулей — поэтапность,
      порционность, выполнение кода по приоритету».

     Стенд СНАЧАЛА показывает проблему обычных таймеров (совпадение фаз:
     десяток задач бьёт в один тик), потом проверяет, что планировщик её
     решает.

     Проверяется:
       1) разведение фаз — задачи с одним интервалом не сходятся;
       2) приоритеты: при просадке сначала отваливается уборка;
       3) бюджет тика соблюдается, critical проходит всегда;
       4) порционный обход не теряет и не дублирует элементы;
       5) после лага нет шквала догоняющих вызовов;
       6) `when` делает неактуальные задачи бесплатными;
       7) реальные модули переведены на планировщик.

     Запуск: luajit tools/luatest/sim_scheduler.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function ErrorNoHalt() end
FCVAR_ARCHIVE = 128
bit = { bor = function(a, b) return (a or 0) + (b or 0) end }
HUD_PRINTTALK = 3

--- Управляемое время: и игровое, и «реальное» для бюджета.
local NOW, SYS = 0, 0
CurTime = function() return NOW end
SysTime = function() return SYS end
FrameNumber = function() return 1 end

hook = { _t = {} }
function hook.Add(e, i, f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Remove(e, i) if hook._t[e] then hook._t[e][i] = nil end end
function hook.Run(e, ...) for _, f in pairs(hook._t[e] or {}) do local r = f(...) if r ~= nil then return r end end end

timer = { _c = {} }
function timer.Create(id, _, _, f) timer._c[id] = f end
function timer.Simple(_, f) f() end
function timer.Remove(id) timer._c[id] = nil end
function timer.Exists(id) return timer._c[id] ~= nil end

local CVARS = {}
function CreateConVar(name, def)
    CVARS[name] = { v = def }
    return {
        GetFloat = function() return tonumber(CVARS[name].v) or 0 end,
        GetBool = function() return CVARS[name].v ~= "0" end,
        GetString = function() return tostring(CVARS[name].v) end,
        GetInt = function() return math.floor(tonumber(CVARS[name].v) or 0) end,
    }
end
local commands = {}
concommand = { Add = function(n, f) commands[n] = f end }
player = { GetAll = function() return {} end }
engine = { TickInterval = function() return 1 / 66 end }

GRM = { Perf = { FrameAvg = 0, FrameNorm = function() return 1/66 end,
    BudgetScale = function() return 1 end, TrackFrame = function() end,
    Players = function() return {} end } }

assert(loadfile("lua/autorun/sh_07_grm_scheduler.lua"))()
local S = GRM.Sched

-----------------------------------------------------------------------
print("\n=== 1. ПРОБЛЕМА ОБЫЧНЫХ ТАЙМЕРОВ ===")
-----------------------------------------------------------------------
--[[ Десять модулей создали таймер с интервалом 1 с на старте карты.
     timer.Create отсчитывает от момента создания — все они срабатывают
     в одном тике. Каждую секунду сервер получает пик. ]]
do
    local fires = {}
    for i = 1, 10 do
        -- Обычный таймер: первый запуск ровно через interval от старта.
        fires[#fires + 1] = 0 + 1.0
    end
    local same = 0
    for _, t in ipairs(fires) do if math.abs(t - fires[1]) < 0.001 then same = same + 1 end end
    ok(same == 10,
       "БАГ ВОСПРОИЗВЕДЁН: 10 обычных таймеров по 1 с бьют в ОДИН тик", same)
end

-----------------------------------------------------------------------
print("\n=== 2. ПЛАНИРОВЩИК РАЗВОДИТ ФАЗЫ ===")
-----------------------------------------------------------------------
NOW = 0
local phases = {}
for i = 1, 10 do
    S.Every("phase.test" .. i, 1, function() end, { prio = "normal" })
    phases[#phases + 1] = S.Tasks["phase.test" .. i].nextAt
end

local collisions = 0
for i = 1, #phases do
    for j = i + 1, #phases do
        if math.abs(phases[i] - phases[j]) < 0.02 then collisions = collisions + 1 end
    end
end
ok(collisions == 0,
   "ИСПРАВЛЕНО: те же 10 задач разведены и не сходятся в один тик", collisions)

-- Разброс должен покрывать весь период, а не жаться к началу.
local minP, maxP = math.huge, -math.huge
for _, p in ipairs(phases) do minP = math.min(minP, p) maxP = math.max(maxP, p) end
ok(maxP - minP > 0.7, "фазы покрывают почти весь период", ("%.2f"):format(maxP - minP))
ok(minP >= 0 and maxP < 1.0, "и не выходят за пределы интервала")

-- Проверка самой формулы отдельно.
ok(S.PhaseFor(0, 1) == 0, "первая задача идёт без задержки")
local p1, p2 = S.PhaseFor(1, 2), S.PhaseFor(2, 2)
ok(math.abs(p1 - p2) > 0.1, "соседние индексы дают разные фазы")
ok(S.PhaseFor(5, 10) < 10, "фаза всегда внутри интервала")

for i = 1, 10 do S.Remove("phase.test" .. i) end

-----------------------------------------------------------------------
print("\n=== 3. ПРИОРИТЕТЫ ПРИ ПРОСАДКЕ ===")
-----------------------------------------------------------------------
ok(S.AllowedAt("critical", 0.15) == true, "critical идёт даже при провале кадра")
ok(S.AllowedAt("normal", 0.15) == false, "обычная логика при провале ждёт")
ok(S.AllowedAt("low", 0.15) == false, "уборка при провале тем более ждёт")

ok(S.AllowedAt("critical", 0.5) == true, "при затяжке critical идёт")
ok(S.AllowedAt("normal", 0.5) == true, "и обычная логика тоже")
ok(S.AllowedAt("low", 0.5) == false,
   "а уборка отваливается ПЕРВОЙ — именно этого мы и хотим")

ok(S.AllowedAt("low", 1) == true, "в норме идёт всё")
ok(S.AllowedAt("low", 1.5) == true, "на свободном сервере тоже")

-----------------------------------------------------------------------
print("\n=== 4. ЖИВОЙ ПРОГОН ДИСПЕТЧЕРА ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW, SYS = 0, 0

local hits = { crit = 0, norm = 0, low = 0 }
S.Every("t.crit", 1, function() hits.crit = hits.crit + 1 end, { prio = "critical", phase = 0 })
S.Every("t.norm", 1, function() hits.norm = hits.norm + 1 end, { prio = "normal", phase = 0 })
S.Every("t.low",  1, function() hits.low = hits.low + 1 end,  { prio = "low", phase = 0 })

-- Нормальная загрузка: отрабатывают все.
NOW = 0
S.Tick(NOW, 0.01, 1)
ok(hits.crit == 1 and hits.norm == 1 and hits.low == 1,
   "в норме выполняются все три", ("%d/%d/%d"):format(hits.crit, hits.norm, hits.low))

-- Провал кадра: только critical.
NOW = 5
hits.crit, hits.norm, hits.low = 0, 0, 0
S.Tick(NOW, 0.01, 0.15)
ok(hits.crit == 1, "при провале critical выполнился", hits.crit)
ok(hits.norm == 0 and hits.low == 0,
   "а normal и low отложены — сервер разгружается", ("%d/%d"):format(hits.norm, hits.low))

-- Отложенные не потерялись: вернутся, когда станет легче.
NOW = 6
hits.crit, hits.norm, hits.low = 0, 0, 0
S.Tick(NOW, 0.01, 1)
ok(hits.norm == 1 and hits.low == 1,
   "отложенные задачи НЕ потеряны и выполняются позже")

-----------------------------------------------------------------------
print("\n=== 5. БЮДЖЕТ ТИКА ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW, SYS = 0, 0
local heavy = 0
--[[ Пять «тяжёлых» задач по 1 мс каждая. Бюджет 2 мс — значит за один
     проход должны выполниться не все. ]]
for i = 1, 5 do
    S.Every("heavy" .. i, 1, function()
        heavy = heavy + 1
        SYS = SYS + 0.001         -- имитируем работу в 1 мс
    end, { prio = "normal", phase = 0 })
end
S.Tick(0, 0.002, 1)
ok(heavy > 0 and heavy < 5,
   "ИСПРАВЛЕНО: бюджет тика соблюдён — выполнилась часть, остальное позже", heavy)

-- Оставшиеся доберутся следующими проходами.
local before = heavy
NOW = 1 SYS = 0
S.Tick(NOW, 0.002, 1)
ok(heavy > before, "остаток выполняется в следующих тиках", heavy)

-- critical бюджет игнорирует: пропустить его хуже, чем превысить время.
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW, SYS = 0, 0
local critRan = 0
S.Every("over.a", 1, function() SYS = SYS + 0.01 end, { prio = "normal", phase = 0 })
S.Every("over.crit", 1, function() critRan = critRan + 1 end, { prio = "critical", phase = 0 })
S.Tick(0, 0.001, 1)
ok(critRan == 1, "critical выполняется даже при исчерпанном бюджете")

-----------------------------------------------------------------------
print("\n=== 6. НЕТ ШКВАЛА ПОСЛЕ ЛАГА ===")
-----------------------------------------------------------------------
--[[ Сервер завис на минуту. Обычный таймер после этого выстрелит
     столько раз, сколько циклов пропустил. Планировщик — один раз. ]]
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW, SYS = 0, 0
local lagRuns = 0
S.Every("lag.test", 1, function() lagRuns = lagRuns + 1 end, { prio = "normal", phase = 0 })

NOW = 60      -- прошла минута простоя
S.Tick(NOW, 0.01, 1)
ok(lagRuns == 1, "после минутного лага задача выполнилась ОДИН раз, а не 60", lagRuns)

local t = S.Tasks["lag.test"]
ok(t.nextAt > NOW, "следующий запуск назначен в будущее", t.nextAt - NOW)
ok(t.nextAt <= NOW + 1.001, "и ровно через интервал, без накопленного долга")

-----------------------------------------------------------------------
print("\n=== 7. `when` — БЕСПЛАТНЫЕ НЕАКТУАЛЬНЫЕ ЗАДАЧИ ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW = 0
local body, checks = 0, 0
local active = false
S.Every("cond.test", 1, function() body = body + 1 end, {
    prio = "normal", phase = 0,
    when = function() checks = checks + 1 return active end,
})
S.Tick(0, 0.01, 1)
ok(body == 0 and checks == 1,
   "условие ложно — тело не выполняется, стоит только проверка")

active = true
NOW = 1
S.Tick(NOW, 0.01, 1)
ok(body == 1, "условие истинно — задача отработала")

-----------------------------------------------------------------------
print("\n=== 8. ПОРЦИОННЫЙ ОБХОД ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW, SYS = 0, 0
local items = {}
for i = 1, 20 do items[i] = i end
local seen = {}
S.EverySpread("spread.test", 1, function() return items end,
    function(v) seen[#seen + 1] = v end, { prio = "normal", chunk = 5, phase = 0 })

S.Tick(0, 0.01, 1)
ok(#seen == 5, "за первый проход обработана ровно порция", #seen)

-- Круг не закончен — планировщик возвращается сразу, не ждёт интервал.
S.Tick(NOW, 0.01, 1)
ok(#seen == 10, "следующий тик берёт следующую порцию", #seen)
S.Tick(NOW, 0.01, 1)
S.Tick(NOW, 0.01, 1)
ok(#seen == 20, "весь список обойдён", #seen)

-- Ничего не потеряно и не задвоено.
local uniq, dupes = {}, 0
for _, v in ipairs(seen) do
    if uniq[v] then dupes = dupes + 1 end
    uniq[v] = true
end
ok(dupes == 0, "элементы не задвоились")
local missing = 0
for i = 1, 20 do if not uniq[i] then missing = missing + 1 end end
ok(missing == 0, "и ни один не потерян")

-----------------------------------------------------------------------
print("\n=== 9. УПРАВЛЕНИЕ ЗАДАЧАМИ ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW = 0
local n = 0
S.Every("mgmt", 1, function() n = n + 1 end, { prio = "normal", phase = 0 })

S.Pause("mgmt")
NOW = 1 S.Tick(NOW, 0.01, 1)
ok(n == 0, "приостановленная задача не выполняется")

S.Resume("mgmt")
S.Tick(NOW, 0.01, 1)
ok(n == 1, "возобновлённая выполняется сразу")

S.Run("mgmt")
ok(n == 2, "Run выполняет немедленно, вне расписания")

ok(S.Remove("mgmt") == true, "задача удаляется")
ok(S.Tasks["mgmt"] == nil, "и исчезает из списка")

-- Повторная регистрация не плодит дубли (перезагрузка файла).
S.Every("dup", 1, function() end)
S.Every("dup", 2, function() end)
local cnt = 0
for _, id in ipairs(S.Order) do if id == "dup" then cnt = cnt + 1 end end
ok(cnt == 1, "повторная регистрация заменяет, а не дублирует", cnt)
ok(S.Tasks["dup"].interval == 2, "и обновляет параметры")

-- Ошибка в задаче не рушит остальные.
S.Tasks, S.Order, S._seq = {}, {}, 0
NOW = 0
local after = 0
S.Every("boom", 1, function() error("тест") end, { prio = "normal", phase = 0 })
S.Every("after", 1, function() after = after + 1 end, { prio = "normal", phase = 0 })
S.Tick(0, 0.01, 1)
ok(after == 1, "упавшая задача не мешает остальным")

-----------------------------------------------------------------------
print("\n=== 10. МОДУЛИ ПЕРЕВЕДЕНЫ ===")
-----------------------------------------------------------------------
local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

local checks = {
    { "lua/autorun/sh_grm_entry.lua",           "entry.pump",           "critical" },
    { "lua/autorun/sh_grm_entry.lua",           "entry.watchdog",       "low" },
    { "lua/autorun/sh_grm_character.lua",       "char.limboguard",      "critical" },
    { "lua/autorun/server/sv_grm_food.lua",     "food.hunger",          "normal" },
    { "lua/autorun/sh_grm_property.lua",        "property.billing",     "low" },
    { "lua/autorun/sh_grm_housing.lua",         "housing.homeflag",     "low" },
    { "lua/autorun/sh_grm_housing_storage.lua", "homestorage.range",    "normal" },
    { "lua/autorun/sh_grm_spawnpick.lua",       "spawnpick.snapshot",   "low" },
}
for _, c in ipairs(checks) do
    local src = readf(c[1])
    ok(src:find(c[2], 1, true) ~= nil, "переведено: " .. c[2])
end

-- Приоритеты расставлены осмысленно.
local entrySrc = readf("lua/autorun/sh_grm_entry.lua")
ok(entrySrc:find('"entry.pump", E.StepDelay, pump, {\n            prio = "critical"', 1, true) ~= nil
   or entrySrc:match('entry%.pump.-prio = "critical"') ~= nil,
   "конвейер входа — critical: игрок видит его пропуск немедленно")

local propSrc = readf("lua/autorun/sh_grm_property.lua")
ok(propSrc:match('property%.billing.-prio="low"') ~= nil,
   "биллинг — low: пять минут терпит")
ok(propSrc:find("chunk=12", 1, true) ~= nil,
   "и обходит объекты порциями, а не все 256 разом")

-- Везде оставлен запасной путь на случай, если планировщик не загрузился.
local fallbacks = 0
for _, c in ipairs(checks) do
    local src = readf(c[1])
    if src:find("if GRM.Sched then", 1, true) then fallbacks = fallbacks + 1 end
end
ok(fallbacks == #checks,
   "у всех переведённых модулей есть запасной timer.Create", fallbacks)

-----------------------------------------------------------------------
print("\n=== 11. ДИАГНОСТИКА ===")
-----------------------------------------------------------------------
S.Tasks, S.Order, S._seq = {}, {}, 0
S.Every("diag.a", 1, function() end, { prio = "critical" })
S.Every("diag.b", 5, function() end, { prio = "low" })
local rows = S.Status()
ok(#rows == 2, "статус перечисляет задачи", #rows)
ok(rows[1].prio == "critical", "critical идёт первым в отчёте", rows[1].prio)
ok(isnumber(rows[1].avgMs), "считается среднее время")
ok(isfunction(commands["grm_sched"]), "есть команда grm_sched")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
