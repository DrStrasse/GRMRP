--[[ Живой прогон очереди записи на диск GRM.Save: коалесцирование правок,
     одна запись за тик, задержки, авто-удлинение для дорогих реестров,
     сброс при выключении карты и статистика.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_save_queue.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
local SYS = 0
function SysTime() SYS = SYS + 0.0001 return SYS end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function ErrorNoHalt() end
bit = { bor = function() return 0 end }
FCVAR_ARCHIVE = 1

local CVARS = { grm_save_budget_ms = "2", grm_save_verbose = "0" }
function CreateConVar(name, default)
    CVARS[name] = CVARS[name] or tostring(default)
    return { GetFloat = function() return tonumber(CVARS[name]) or 0 end,
             GetBool = function() return CVARS[name] ~= "0" end,
             GetString = function() return CVARS[name] end }
end

local FS, WRITES = {}, {}
file = {
    IsDir = function() return true end, CreateDir = function() end,
    Write = function(p, s) FS[p] = s WRITES[#WRITES + 1] = p end,
    Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end,
}
util = { TableToJSON = function(t) return "json:" .. tostring(t.tag or "?") end }

local timers = {}
timer = { Create = function(id, delay, reps, fn) timers[id] = fn end }
local hooks = {}
hook = { Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
         Run = function(name, ...) for _, fn in pairs(hooks[name] or {}) do fn(...) end end }
concommand = { Add = function() end }
GRM = {}

assert(loadfile("lua/autorun/sh_05_grm_save.lua"))()
local S = GRM.Save

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local builds = { a = 0, b = 0 }
S.Register("mod.a", { file = "grm_test/a.json", delay = 5, label = "Реестр А",
    build = function() builds.a = builds.a + 1 return { tag = "a", n = builds.a } end })
S.Register("mod.b", { file = "grm_test/b.json", delay = 2, priority = 1, label = "Реестр Б",
    build = function() builds.b = builds.b + 1 return { tag = "b" } end })

print("\n=== 1. КОАЛЕСЦИРОВАНИЕ ===")
ok(S.Mark("mod.a", "правка 1") == true, "правка помечает реестр грязным")
for i = 1, 20 do S.Mark("mod.a", "правка " .. i) end
ok(#WRITES == 0, "20 правок подряд НЕ дали ни одной записи на диск", #WRITES)
ok(S.Stats.coalesced >= 20, "сэкономленные записи посчитаны", S.Stats.coalesced)
ok(S.Mark("нет такого") == false, "незарегистрированный реестр не помечается")

print("\n=== 2. ЗАДЕРЖКА И ОДНА ЗАПИСЬ ЗА ТИК ===")
ok(S.Tick(NOW) == false, "до истечения задержки писатель молчит")
S.Mark("mod.b", "правка")
NOW = NOW + 3
ok(S.Tick(NOW) == true and #WRITES == 1, "первым пошёл реестр с более коротким сроком/приоритетом", #WRITES)
ok(WRITES[1] == "grm_test/b.json", "записан именно он", WRITES[1])
ok(S.Tick(NOW) == false, "второй файл в тот же тик НЕ пишется")
NOW = NOW + 3
ok(S.Tick(NOW) == true and WRITES[2] == "grm_test/a.json", "следующий тик — следующий файл")
ok(builds.a == 1, "сборка данных выполнена ОДИН раз на 21 правку", builds.a)
ok(S.Tick(NOW) == false, "чистые реестры не пишутся")

print("\n=== 3. НЕМЕДЛЕННЫЙ СБРОС ===")
S.Mark("mod.a", "правка")
S.Mark("mod.b", "правка")
local flushed = S.FlushAll("тест")
ok(flushed == 2, "FlushAll пишет всё грязное сразу", flushed)
ok(S.Tick(NOW + 100) == false, "после сброса очередь пуста")
ok(S.Flush("mod.a", "вручную") == true, "точечный сброс работает")

print("\n=== 4. ДОРОГОЙ РЕЕСТР ПИШЕТСЯ РЕЖЕ ===")
S.Register("mod.slow", { file = "grm_test/slow.json", delay = 5, build = function()
    for _ = 1, 60 do SysTime() end  -- имитация тяжёлой сериализации
    return { tag = "slow" }
end })
local before = S.Entries["mod.slow"].delay
S.Mark("mod.slow", "правка")
S.Flush("mod.slow")
ok(S.Entries["mod.slow"].delay >= before, "задержка дорогого реестра не уменьшилась",
    S.Entries["mod.slow"].delay)

print("\n=== 5. УСТОЙЧИВОСТЬ ===")
S.Register("mod.bad", { file = "grm_test/bad.json", delay = 0, build = function() error("сломался") end })
S.Mark("mod.bad", "правка")
ok(S.Flush("mod.bad") == false, "падение сборщика не роняет очередь")
ok(S.Entries["mod.bad"].dirty == false, "сломанный реестр не крутится в очереди вечно")
ok(S.Stats.failures >= 1, "провал посчитан")

print("\n=== 6. ВЫКЛЮЧЕНИЕ КАРТЫ ===")
S.Mark("mod.a", "правка перед выключением")
hook.Run("ShutDown")
ok(S.Entries["mod.a"].dirty == false, "при выключении всё сброшено на диск")
ok(isfunction(timers["GRM_Save_Tick"]), "писатель зарегистрирован таймером раз в секунду")

print("\n=== 7. СТАТИСТИКА ===")
local rows, stats = S.Status()
ok(#rows >= 4, "статус перечисляет реестры", #rows)
ok(stats.writes >= 5 and stats.marks >= 25, "счётчики записей и правок ведутся",
    stats.writes .. "/" .. stats.marks)
ok(stats.coalesced > stats.writes, "сэкономлено записей больше, чем сделано — слой окупается",
    stats.coalesced .. " > " .. stats.writes)

print(("\nSAVE QUEUE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
