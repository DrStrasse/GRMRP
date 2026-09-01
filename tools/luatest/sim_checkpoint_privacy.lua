--[[--------------------------------------------------------------------
    sim_checkpoint_privacy — чекпоинт виден и работает ТОЛЬКО у того,
    кто взял квест.

    ЗАКАЗ ВЛАДЕЛЬЦА (30.08): «Их надо чтобы было видно только тем, кто
    взял квест, чтобы не получилось так, что чекпоинт рисуется для всех
    и любой рандом, вставший на чекпоинт случайно или намеренно, забрал
    награду чужого человека.»

    ЗДЕСЬ ДВЕ РАЗНЫЕ ЗАДАЧИ, И ПУТАТЬ ИХ НЕЛЬЗЯ:

      1. ВИДИМОСТЬ — вопрос удобства. Решается на клиенте: не рисуем
         круг тем, у кого квеста нет.

      2. КРАЖА НАГРАДЫ — вопрос БЕЗОПАСНОСТИ. Клиентская проверка тут
         бесполезна: клиент можно подменить, а срабатывание считает
         сервер. Значит сервер обязан сам отказывать чужому.

    Клиентская проверка уже стоит (прошлая правка), серверная тоже —
    ReachCheckpoint требует p.status == "active" у КОНКРЕТНОГО игрока.
    Этот стенд закрепляет обе и ловит третью проблему:

      3. ФЛАГ Reached БЫЛ ОБЩИМ. SetReached — сетевая переменная одна на
         всех: первый прошедший ставил её, и маркер прятался у ВСЕХ
         остальных, включая тех, кто точку ещё не проходил. Прогресс при
         этом у каждого свой — то есть картинка врала.

    Запуск: luajit tools/luatest/sim_checkpoint_privacy.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local quests = read("lua/autorun/sh_grm_quests.lua")
local cl = read("lua/entities/grm_quest_checkpoint/cl_init.lua")
local shared = read("lua/entities/grm_quest_checkpoint/shared.lua")

print("\n=== 1. ОБЩЕГО ФЛАГА «ПРОЙДЕНО» БОЛЬШЕ НЕТ ===")
--[[ Сетевая переменная одна на всех игроков. Прогресс личный, поэтому
     хранить в ней «пройдено» нельзя: первый прошедший прятал маркер
     остальным. Правда живёт только в прогрессе игрока. ]]
ok(shared:find('NetworkVar("Bool", 0, "Reached")', 1, true) == nil,
    "Reached убран из сетевых переменных — он был общим на всех")
ok(quests:find("ent:SetReached(true)", 1, true) == nil,
    "сервер не ставит общий флаг при проходе")

print("\n=== 2. ВИДИМОСТЬ РЕШАЕТ КЛИЕНТ ПО СВОЕМУ ПРОГРЕССУ ===")
ok(cl:find("shouldShow", 1, true) ~= nil, "проверка видимости есть")
ok(cl:find('p.status == "active"', 1, true) ~= nil,
    "рисуем только при активном квесте У СЕБЯ")
ok(cl:find("p.checkpoints", 1, true) ~= nil,
    "пройденность берётся из ЛИЧНОГО прогресса, а не с энтити")

--[[ Выход обязан стоять до отрисовки модели: иначе у чужого останется
     висеть красный круг без подписи. ]]
local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", " ")
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line:gsub("%-%-.*$", "") end
    return table.concat(out, "\n")
end
local drawBody = cl:match("function ENT:Draw%(%)\n(.-)\nend\n") or ""
local drawCode = stripComments(drawBody)
local atReturn = drawCode:find("return", 1, true) or math.huge
local atModel = drawCode:find("DrawModel", 1, true) or math.huge
ok(atReturn < atModel, "выход стоит ДО DrawModel",
    ("return=%s model=%s"):format(tostring(atReturn), tostring(atModel)))

print("\n=== 3. СЕРВЕР ОТКАЗЫВАЕТ ЧУЖОМУ (ГЛАВНОЕ) ===")
--[[ Клиентскую проверку можно обойти подменой клиента. Срабатывание
     считает сервер, значит защита от кражи награды обязана быть там. ]]
local reach = quests:match("function Q%.ReachCheckpoint.-\n    end") or ""
ok(reach ~= "", "ReachCheckpoint найдена")
ok(reach:find('p.status=="active"', 1, true) ~= nil,
    "сервер требует активный квест У ЭТОГО игрока")
ok(reach:find("progressFor(ply)", 1, true) ~= nil,
    "прогресс берётся персонально, а не общий")

print("\n=== 4. ЖИВОЙ ПРОГОН: ЧУЖОЙ НЕ ЗАБИРАЕТ НАГРАДУ ===")
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

--[[ Деньги считаем поимённо: так видно, КОМУ ушла награда. ]]
local PAID = {}
net = { Receive = function() end, Start = function() end, Send = function() end,
        Broadcast = function() end, WriteTable = function() end, WriteString = function() end,
        WriteUInt = function() end, WriteBool = function() end, WriteFloat = function() end,
        WriteEntity = function() end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end,
         IsDir = function() return false end, CreateDir = function() end,
         Find = function() return {}, {} end, Delete = function() end }
ents = { Create = function() return nil end, FindByClass = function() return {} end,
         FindInSphere = function() return {} end, GetAll = function() return {} end }
player = { GetAll = function() return {} end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "rp_test" end, SinglePlayer = function() return false end }
concommand = { Add = function() end }
surface, draw, cam, render, vgui = {}, {}, {}, {}, {}
engine = { TickInterval = function() return 0.03 end }
GRM = {
    Notify = function() end, Format = tostring,
    GiveMoney = function(p, amount) PAID[p] = (PAID[p] or 0) + amount end,
}
_G.CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
_G.GetConVar = _G.CreateConVar
FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
ok(isfunction(Q.ReachCheckpoint), "модуль квестов загружен")

local function mkPlayer(sid, nick)
    return { _valid = true,
        SteamID64 = function() return sid end,
        SteamID = function() return "STEAM_0:1:" .. sid end,
        IsPlayer = function() return true end, Nick = function() return nick end,
        Alive = function() return true end, GetPos = function() return Vector(0,0,0) end,
        GetNWString = function(_, _, d) return d or "" end,
        SetNWString = function() end, SetNWInt = function() end, SetNWBool = function() end,
        ChatPrint = function() end, PrintMessage = function() end }
end

local owner = mkPlayer("76561190000000010", "Владелец квеста")
local rando = mkPlayer("76561190000000011", "Случайный прохожий")

local def = {
    id = "q_priv", title = "Приватный квест", summary = "",
    enabled = true, draft = false,
    steps = { { type = "visit" } },
    cutscene = { accept = {}, complete = {} },
    rewards = { money = 500, items = {} },
    checkpoints = { { id = "cp1", label = "Точка", radius = 96, once = true } },
    graph = { links = { { from = "cp_cp1", to = "reward", port = 0, when = "now" } } },
}
Q.Definitions = Q.Definitions or {}
Q.Definitions["q_priv"] = def

--[[ Квест взял ТОЛЬКО owner. Прохожий просто идёт мимо. ]]
Q.Progress = Q.Progress or {}
local okStart = pcall(Q.Start, owner, "q_priv")

PAID = {}
local grabbed = Q.ReachCheckpoint(rando, "q_priv", "cp1", nil)
ok(grabbed == false, "прохожий БЕЗ квеста не срабатывает на чекпоинте", tostring(grabbed))
ok((PAID[rando] or 0) == 0, "и не получает ни копейки", PAID[rando] or 0)

PAID = {}
local mine = Q.ReachCheckpoint(owner, "q_priv", "cp1", nil)
ok(mine == true, "владелец квеста проходит точку", tostring(mine))

print("\n=== 5. ПОВТОРНЫЙ ПРОХОД НЕ ДОИТ НАГРАДУ ===")
PAID = {}
local again = Q.ReachCheckpoint(owner, "q_priv", "cp1", nil)
ok(again == false, "одноразовая точка второй раз не срабатывает", tostring(again))
ok((PAID[owner] or 0) == 0, "повторная награда не выдаётся", PAID[owner] or 0)

print("\n=== 6. ЧУЖОЙ КВЕСТ / НЕСУЩЕСТВУЮЩАЯ ТОЧКА ===")
ok(Q.ReachCheckpoint(rando, "q_priv", "cp_нет_такой", nil) == false,
    "выдуманный ID точки отклоняется")
ok(Q.ReachCheckpoint(rando, "нет_такого_квеста", "cp1", nil) == false,
    "выдуманный ID квеста отклоняется")
ok(Q.ReachCheckpoint(nil, "q_priv", "cp1", nil) == false,
    "вызов без игрока не падает и отклоняется")

print("\n=== 7. ВИДИМОСТЬ: ЖИВОЙ ПРОГОН ПРАВИЛА ===")
--[[ Повторяем клиентское правило: у чужого маркера быть не должно, а
     пройденная своя точка скрывается. Прогресс у каждого свой, поэтому
     флаг с ЭНТИТИ тут не участвует вовсе. ]]
local function shouldShow(rows, questID, cpID)
    for _, row in ipairs(rows) do
        local d = row.definition
        if d and d.id == questID then
            local p = row.progress
            if not (istable(p) and p.status == "active") then return false end
            if istable(p.checkpoints) and p.checkpoints[cpID] then return false end
            return true
        end
    end
    return false
end

local ownerRows = { { definition = def, progress = { status = "active", checkpoints = {} } } }
local randoRows = {}
ok(shouldShow(ownerRows, "q_priv", "cp1") == true, "владельцу квеста маркер виден")
ok(shouldShow(randoRows, "q_priv", "cp1") == false, "прохожему маркера НЕТ")

ownerRows[1].progress.checkpoints["cp1"] = true
ok(shouldShow(ownerRows, "q_priv", "cp1") == false, "своя пройденная точка скрывается")

--[[ И главное про общий флаг: проход ОДНОГО игрока не должен влиять на
     картинку другого. Раньше SetReached был общим и прятал маркер всем. ]]
local secondRows = { { definition = def, progress = { status = "active", checkpoints = {} } } }
ok(shouldShow(secondRows, "q_priv", "cp1") == true,
    "второй игрок с тем же квестом всё ещё видит точку, хотя первый её прошёл")

print("\n=== 8. МАРКЕР НЕ ПРИХОДИТ ЧУЖОМУ ПО СЕТИ ===")
--[[ Клиентская проверка не рисует чужой маркер, но сама энтити всё
     равно передавалась бы всем: её видно чит-клиентом и инструментами
     «показать все entity». Для квестовой точки это подсказка «здесь
     дают деньги». Прячем на уровне сети. ]]
local init = read("lua/entities/grm_quest_checkpoint/init.lua")
--[[ Проверяем не наличие слова, а ВЫЗОВ внутри UpdateTransmit: откат,
     при котором строку заменили заглушкой, объявление функции не трогает
     — и проверка «есть SetPreventTransmit» осталась бы зелёной на
     сломанном коде (поймано откатом). ]]
local upd = init:match("function ENT:UpdateTransmit%(%).-\nend") or ""
ok(upd ~= "", "UpdateTransmit найдена")
ok(upd:find("SetPreventTransmit", 1, true) ~= nil,
    "энтити скрывается от чужого клиента на уровне сети")
ok(upd:find("MaySee", 1, true) ~= nil,
    "получатели считаются по праву видеть, а не наугад")
ok(init:find("UpdateTransmit", 1, true) ~= nil, "есть пересчёт получателей")
ok(quests:find("function Q.CheckpointVisibleFor", 1, true) ~= nil,
    "правило видимости вынесено в ядро")

--[[ Одна функция на два вопроса — «показывать» и «пускать». Если развести
     их по разным местам, они разойдутся: игрок видит точку, а она не
     срабатывает. Проверяем, что энтити спрашивает именно ядро. ]]
ok(init:find("Q.CheckpointVisibleFor", 1, true) ~= nil,
    "энтити спрашивает ядро, а не решает сама")

--[[ Маркер обязан появиться сразу при взятии квеста: иначе игрок стоит
     перед пустым местом до следующего тика. ]]
ok(quests:find("Q.RefreshCheckpointVisibility", 1, true) ~= nil,
    "есть пересчёт видимости по событию")
local startFn = quests:match("function Q%.Start%(ply,questID%).-\n    end") or ""
ok(startFn:find("RefreshCheckpointVisibility", 1, true) ~= nil,
    "взятие квеста сразу показывает его точки владельцу")

print("\n=== 9. ЖИВОЙ ПРОГОН ПРАВИЛА ИЗ ЯДРА ===")
--[[ Гоняем НАСТОЯЩУЮ Q.CheckpointVisibleFor, а не копию: копия может
     быть верной, а боевая функция нет. ]]
ok(isfunction(Q.CheckpointVisibleFor), "функция доступна")
if isfunction(Q.CheckpointVisibleFor) then
    local owner2 = mkPlayer("76561190000000012", "Второй владелец")
    Q.Definitions["q_priv2"] = {
        id = "q_priv2", title = "Второй", summary = "", enabled = true, draft = false,
        steps = { { type = "visit" } }, cutscene = { accept = {}, complete = {} },
        rewards = { money = 0, items = {} },
        checkpoints = { { id = "cpA", label = "A", radius = 96, once = true } },
        graph = { links = {} },
    }
    ok(Q.CheckpointVisibleFor(owner2, "q_priv2", "cpA") == false,
        "до взятия квеста точка не видна")
    pcall(Q.Start, owner2, "q_priv2")
    ok(Q.CheckpointVisibleFor(owner2, "q_priv2", "cpA") == true,
        "после взятия — видна владельцу")
    ok(Q.CheckpointVisibleFor(rando, "q_priv2", "cpA") == false,
        "постороннему по-прежнему не видна")

    Q.ReachCheckpoint(owner2, "q_priv2", "cpA", nil)
    ok(Q.CheckpointVisibleFor(owner2, "q_priv2", "cpA") == false,
        "после прохода одноразовая точка скрывается")
end

print(("\nCHECKPOINT PRIVACY: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
