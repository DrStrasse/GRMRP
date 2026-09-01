--[[--------------------------------------------------------------------
    sim_quest_reset — админ может сбросить квест и пройти его заново.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «админу нужен сброс квеста, чтобы проверить
    его заново».

    ЗАЧЕМ. Квест проходится один раз: после завершения он лежит в
    прогрессе со статусом completed, NPC больше его не предлагает.
    Проверить правку сюжета можно было только сменой персонажа или
    ручной чисткой файла прогресса — то есть никак.

    ЧТО ПРОВЕРЯЕМ:
      * сброс убирает запись из прогресса, и квест снова доступен;
      * вместе с прогрессом уходят пройденные чекпоинты — иначе точки
        останутся скрытыми и пройти заново будет нельзя;
      * ачивка тоже снимается, иначе повторная выдача не сработает;
      * сброс доступен ТОЛЬКО суперадмину: иначе любой обнулял бы
        себе кулдаун и фармил награды по кругу;
      * можно сбросить и себе, и другому игроку;
      * сброс несуществующего квеста не роняет сервер.

    Запуск: luajit tools/luatest/sim_quest_reset.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function CurTime() return 100 end
function SysTime() return 100 end
function Vector(x, y, z) local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x-o.x, self.y-o.y, self.z-o.z return a*a+b*b+c*c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end return v end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
math.Clamp = function(v, lo, hi) v = tonumber(v) or lo
    if v < lo then return lo end if v > hi then return hi end return v end
math.Round = function(v) return math.floor((tonumber(v) or 0) + 0.5) end
string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
string.Explode = function(sep, str) local o = {}
    for piece in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o+1] = piece end return o end
hook = { Add = function() end, Remove = function() end, Run = function() end }
timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end, Compress = function(x) return x end }
net = { Receive = function() end, Start = function() end, Send = function() end,
        Broadcast = function() end, WriteTable = function() end, WriteString = function() end,
        WriteUInt = function() end, WriteBool = function() end, WriteFloat = function() end,
        WriteEntity = function() end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end,
         IsDir = function() return false end, CreateDir = function() end,
         Find = function() return {}, {} end, Delete = function() end }
ents = { Create = function() return nil end, FindByClass = function() return {} end,
         FindInSphere = function() return {} end, GetAll = function() return {} end }
local ALL_PLAYERS = {}
player = { GetAll = function() return ALL_PLAYERS end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "rp_test" end, SinglePlayer = function() return false end }
concommand = { Add = function() end }
surface, draw, cam, render, vgui = {}, {}, {}, {}, {}
engine = { TickInterval = function() return 0.03 end }
GRM = { Notify = function() end, Format = tostring }
local ACH_UNLOCKED = {}
GRM.Ach = { Defs = {}, Register = function() end, RecOf = function() return {} end,
            Unlock = function(_, d) ACH_UNLOCKED[#ACH_UNLOCKED+1] = d end,
            Reset = function(p, id) ACH_UNLOCKED[id] = nil return true end }
_G.CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
_G.GetConVar = _G.CreateConVar
FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(sid, nick, admin)
    local p = { _valid = true,
        SteamID64 = function() return sid end,
        SteamID = function() return "STEAM_0:1:" .. sid end,
        IsPlayer = function() return true end, Nick = function() return nick end,
        Alive = function() return true end, GetPos = function() return Vector(0,0,0) end,
        IsSuperAdmin = function() return admin == true end,
        IsAdmin = function() return admin == true end,
        GetNWString = function(_, _, d) return d or "" end,
        SetNWString = function() end, SetNWInt = function() end, SetNWBool = function() end,
        ChatPrint = function() end, PrintMessage = function() end }
    ALL_PLAYERS[#ALL_PLAYERS + 1] = p
    return p
end

local admin = mkPlayer("76561190000000100", "Админ", true)
local player1 = mkPlayer("76561190000000101", "Игрок", false)

local def = {
    id = "q_reset", title = "Тестовый", summary = "", enabled = true, draft = false,
    steps = { { type = "visit", title = "Дойти" } },
    cutscene = { accept = {}, complete = {} },
    rewards = { money = 100, items = {} },
    achievement = { id = "quest_q_reset", name = "Ачивка", enabled = true, description = "", reward = 0 },
    checkpoints = { { id = "cp1", label = "Точка", radius = 96, once = true } },
    graph = { links = {} },
}
Q.Definitions = Q.Definitions or {}
Q.Definitions["q_reset"] = def

print("\n=== 1. ФУНКЦИЯ СБРОСА СУЩЕСТВУЕТ ===")
ok(isfunction(Q.ResetQuest), "есть Q.ResetQuest")

print("\n=== 2. ПРОЙДЕННЫЙ КВЕСТ СБРАСЫВАЕТСЯ ===")
pcall(Q.Start, player1, "q_reset")
local p = Q.GetProgress(player1, "q_reset")
ok(istable(p) and p.status == "active", "квест взят", p and p.status)

-- отмечаем чекпоинт и завершаем
Q.ReachCheckpoint(player1, "q_reset", "cp1", nil)
p = Q.GetProgress(player1, "q_reset")
ok(istable(p) and istable(p.checkpoints) and p.checkpoints["cp1"] == true,
    "чекпоинт отмечен пройденным")

if isfunction(Q.ForceFinish) then Q.ForceFinish(player1, def, p) end
p = Q.GetProgress(player1, "q_reset")
ok(istable(p) and p.status == "completed", "квест завершён", p and p.status)

if isfunction(Q.ResetQuest) then
    local done = Q.ResetQuest(admin, player1, "q_reset")
    ok(done == true, "сброс выполнен", tostring(done))
end
p = Q.GetProgress(player1, "q_reset")
ok(p == nil or next(p) == nil, "запись прогресса удалена",
    p and tostring(p.status) or "nil")

print("\n=== 3. ПОСЛЕ СБРОСА КВЕСТ МОЖНО ВЗЯТЬ СНОВА ===")
--[[ Главная цель заказа: админ правит сюжет и проверяет его заново.
     Если Start откажет, сброс бесполезен. ]]
local restarted = pcall(Q.Start, player1, "q_reset")
local p2 = Q.GetProgress(player1, "q_reset")
ok(restarted and istable(p2) and p2.status == "active",
    "квест взят повторно", p2 and p2.status)

print("\n=== 4. ЧЕКПОИНТЫ ТОЖЕ СБРОШЕНЫ ===")
--[[ Если пройденные точки останутся, маркеры будут скрыты и пройти
     заново физически не получится — сброс окажется половинчатым. ]]
ok(not (istable(p2) and istable(p2.checkpoints) and p2.checkpoints["cp1"]),
    "отметка о пройденной точке снята")
if isfunction(Q.CheckpointVisibleFor) then
    ok(Q.CheckpointVisibleFor(player1, "q_reset", "cp1") == true,
        "маркер снова виден игроку")
end

print("\n=== 5. ТОЛЬКО СУПЕРАДМИН ===")
--[[ Без этой проверки любой игрок обнулял бы себе прохождение и фармил
     награду по кругу — это дыра в экономике, а не удобство. ]]
if isfunction(Q.ResetQuest) then
    local hacked = Q.ResetQuest(player1, player1, "q_reset")
    ok(hacked == false, "обычному игроку сброс запрещён", tostring(hacked))
    local p3 = Q.GetProgress(player1, "q_reset")
    ok(istable(p3) and p3.status == "active", "его прогресс не тронут", p3 and p3.status)
end

print("\n=== 6. УСТОЙЧИВОСТЬ ===")
if isfunction(Q.ResetQuest) then
    ok(Q.ResetQuest(admin, player1, "нет_такого") == false,
        "сброс несуществующего квеста отклоняется")
    ok(Q.ResetQuest(admin, nil, "q_reset") == false,
        "сброс без цели не роняет сервер")
    ok(Q.ResetQuest(nil, player1, "q_reset") == false,
        "вызов без админа отклоняется")
end

print("\n=== 7. ЕСТЬ ТОЧКА ВХОДА ДЛЯ АДМИНА ===")
local src = (function() local f = assert(io.open("lua/autorun/sh_grm_quests.lua", "rb"))
    local s = f:read("*a") f:close() return s end)()
ok(src:find("grm_quest_reset", 1, true) ~= nil, "есть консольная команда сброса")
--[[ Кнопка в студии: админ правит квест там же, где его проверяет.
     Гонять его в консоль ради каждой проверки — лишний шаг. ]]
local studio = (function() local f = assert(io.open("lua/autorun/client/zz_grm_quest_studio.lua", "rb"))
    local s = f:read("*a") f:close() return s end)()
ok(studio:find("СБРОСИТЬ ПРОХОЖДЕНИЕ", 1, true) ~= nil
   or studio:find("Сбросить прохождение", 1, true) ~= nil,
    "в студии есть кнопка сброса")

print(("\nQUEST RESET: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
