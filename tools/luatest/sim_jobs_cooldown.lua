--[[--------------------------------------------------------------------
    sim_jobs_cooldown — пауза между работами и потолок за час.

    БАГ (разбор 29.08). Ограничителей не было вообще: ни кулдауна между
    задачами, ни лимита за час. Единственным регулятором служила казна —
    если денег нет, работу не выдадут. Это очень грубо: город либо
    финансирует бесконечный фарм одной и той же короткой задачи, либо
    внезапно перестаёт выдавать работу вообще всем.

    ЧТО ПРОВЕРЯЕМ:
      1. сразу после сдачи задачи новую взять нельзя — короткая пауза;
      2. пауза проходит — работа снова доступна;
      3. упёрся в часовой потолок — отказ с понятной причиной;
      4. час прошёл — счётчик обнулился;
      5. ПРОВАЛ не наказывает потолком (иначе провалы копили бы лимит),
         но паузу даёт — чтобы отказом от задачи нельзя было
         перебирать предложения без конца;
      6. настройки читаются из конфига и переживают сохранение.

    Запуск: luajit tools/luatest/sim_jobs_cooldown.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local wall = 1700000000
local function nowT() return wall end

-- Минимальная модель ограничителя поверх настоящего кода конфигурации:
-- проверяем не текст, а поведение JB.CanTakeJob / JB.NoteJobTaken.
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function CurTime() return 100 end
function Vector(x, y, z) local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end return v end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
math.Clamp = function(v, lo, hi) v = tonumber(v) or lo if v < lo then return lo end if v > hi then return hi end return v end
string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
os = setmetatable({ time = nowT }, { __index = _G.os })

hook = { Add = function() end, Remove = function() end, Run = function() end }
timer = { Create = function() end, Simple = function() end, Remove = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end }
net = { Receive = function() end, Start = function() end, Send = function() end,
        WriteTable = function() end, WriteUInt = function() end, WriteString = function() end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end,
         IsDir = function() return false end, CreateDir = function() end, Find = function() return {}, {} end }
ents = { FindByClass = function() return {} end, FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return {} end }
game = { GetMap = function() return "rp_test" end }

GRM = { Jobs = {}, Notify = function() end, Format = tostring }
local JB = GRM.Jobs

assert(loadfile("lua/autorun/sh_grm_jobs_limits.lua"))()

local function mkPlayer(k)
    local p = { _valid = true, _key = k }
    function p:Nick() return k end
    function p:SteamID64() return k end
    function p:GetNWString(_, d) return d end
    function p:ChatPrint() end
    return p
end
JB.CharacterKey = function(p) return type(p) == "table" and p._key or "" end

local ply = mkPlayer("777:char1")

print("\n=== 1. НАСТРОЙКИ ЕСТЬ И ОСМЫСЛЕННЫ ===")
ok(istable(JB.Limits), "блок настроек ограничителя объявлен")
ok(tonumber(JB.Limits.cooldownSec) and JB.Limits.cooldownSec > 0,
    "пауза между работами задана", JB.Limits and JB.Limits.cooldownSec)
ok(tonumber(JB.Limits.perHour) and JB.Limits.perHour > 0,
    "часовой потолок задан", JB.Limits and JB.Limits.perHour)

print("\n=== 2. ПЕРВАЯ РАБОТА БЕРЁТСЯ СВОБОДНО ===")
ok(isfunction(JB.CanTakeJob), "есть проверка «можно ли взять работу»")
local can, why = JB.CanTakeJob(ply)
ok(can == true, "новичку ничего не мешает", why)

print("\n=== 3. СРАЗУ ПОСЛЕ СДАЧИ — ПАУЗА ===")
JB.NoteJobFinished(ply, "courier")
local can2, why2 = JB.CanTakeJob(ply)
ok(can2 == false, "подряд вторую задачу взять нельзя")
ok(isstring(why2) and why2:find("екунд") ~= nil, "причина называет, сколько ждать", why2)

print("\n=== 4. ПАУЗА ПРОШЛА — СНОВА МОЖНО ===")
wall = wall + JB.Limits.cooldownSec + 1
local can3 = JB.CanTakeJob(ply)
ok(can3 == true, "после паузы работа доступна")

print("\n=== 5. ЧАСОВОЙ ПОТОЛОК ===")
--[[ Крутим задачи, разнося их по времени так, чтобы пауза не мешала:
     проверяем именно потолок за час, а не кулдаун. ]]
for _ = 1, JB.Limits.perHour do
    JB.NoteJobFinished(ply, "courier")
    wall = wall + JB.Limits.cooldownSec + 1
end
local can4, why4 = JB.CanTakeJob(ply)
ok(can4 == false, "потолок за час останавливает конвейер")
ok(isstring(why4) and (why4:find("час") ~= nil or why4:find("лимит") ~= nil),
    "причина говорит про часовой лимит", why4)

print("\n=== 6. ЧАС ПРОШЁЛ — СЧЁТЧИК ОБНУЛИЛСЯ ===")
wall = wall + 3601
local can5, why5 = JB.CanTakeJob(ply)
ok(can5 == true, "через час работа снова доступна", why5)

print("\n=== 7. ПРОВАЛ НЕ СЪЕДАЕТ ЧАСОВОЙ ЛИМИТ ===")
--[[ Иначе провалы копили бы потолок: отказался пару раз — и до конца
     часа свободен. Но паузу провал даёт, чтобы нельзя было бесконечно
     перебирать предложения, беря и бросая задачи. ]]
local fresh = mkPlayer("888:char1")
-- Шагаем по failCooldownSec: после провала пауза длиннее обычной, и если
-- крутить по cooldownSec, упрёшься в неё, а не проверишь часовой лимит.
for _ = 1, JB.Limits.perHour + 3 do
    JB.NoteJobFailed(fresh, "courier")
    wall = wall + JB.Limits.failCooldownSec + 1
end
local can6, why6 = JB.CanTakeJob(fresh)
ok(can6 == true, "после множества провалов лимит не исчерпан", why6)

JB.NoteJobFailed(fresh, "courier")
local can7, why7 = JB.CanTakeJob(fresh)
ok(can7 == false, "но сразу после провала действует пауза", why7)

print("\n=== 8. ЯДРО ДЕЙСТВИТЕЛЬНО СПРАШИВАЕТ ОГРАНИЧИТЕЛЬ ===")
--[[ Сам по себе модуль бесполезен, если приём заказа его не зовёт.
     Проверяем тело обработчика NET_ACCEPT, а не файл целиком: совпадение
     где-то в другом месте создало бы ложное спокойствие. ]]
local core = read("lua/autorun/sh_grm_jobs.lua")
local body = core:match("net%.Receive%(NET_ACCEPT.-\n    end%)") or ""
ok(body ~= "", "обработчик приёма заказа найден")
ok(body:find("CanTakeJob", 1, true) ~= nil, "перед выдачей работы спрашивается CanTakeJob")
ok(core:find("NoteJobFinished", 1, true) ~= nil, "успешная сдача отмечается")
ok(core:find("NoteJobFailed", 1, true) ~= nil, "провал отмечается")

print(("\nJOBS COOLDOWN: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
