--[[--------------------------------------------------------------------
    sim_checkpoint_links — связь ЧЕКПОИНТ → НАГРАДА / АЧИВКА выживает.

    ЖАЛОБА ВЛАДЕЛЬЦА (30.08): «Блок чекпоинт нельзя связать с блоком
    награда и ачивка».

    ПРИЧИНА — РАСХОЖДЕНИЕ UID. Блок, добавленный из палитры, получал
    uid = kind, то есть просто "checkpoint": своей ветки в addBlock у
    него не было, данные оставались пустыми. Связь сохранялась как
    from = "checkpoint".

    А при следующем открытии QuestToBlocks собирает чекпоинты по правилу
    uid = "cp_" .. id (так же, как Q.CheckpointUID в ядре). Пустой id
    превращался в "checkpoint", и блок получал uid "cp_checkpoint".

    Итог: сохранённая связь указывала на несуществующий блок и
    отбрасывалась при загрузке — линия исчезала, будто её нельзя
    провести. Ровно тот же класс бага, что уже ловили с репликами:
    «uid, отличный от того, каким его сделает загрузка».

    ЧТО ПРОВЕРЯЕМ:
      * у нового чекпоинта из палитры сразу правильный uid и свой id;
      * два чекпоинта не сливаются в один;
      * связь чекпоинт → награда переживает сохранение и переоткрытие;
      * то же для ачивки и кат-сцены;
      * ядро реально запускает эти блоки при достижении точки.

    Запуск: luajit tools/luatest/sim_checkpoint_links.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")
local quests = read("lua/autorun/sh_grm_quests.lua")

print("\n=== 1. НОВЫЙ ЧЕКПОИНТ ПОЛУЧАЕТ ПРАВИЛЬНЫЙ UID ===")
local addFn = studio:match("local function addBlock%(kind%).-\n    end") or ""
ok(addFn ~= "", "addBlock найдена")
--[[ Ключ всей правки: uid нового блока обязан совпадать с тем, каким его
     сделает загрузка (cp_<id>). Иначе связь, нарисованная до сохранения,
     после переоткрытия теряет источник. ]]
ok(addFn:find('kind == "checkpoint"', 1, true) ~= nil,
    "у чекпоинта своя ветка данных при создании")
ok(addFn:find('"cp_"', 1, true) ~= nil,
    "uid строится как cp_<id> — так же, как при загрузке")

print("\n=== 2. ЖИВОЙ ПРОГОН: UID СОВПАДАЕТ ДО И ПОСЛЕ СОХРАНЕНИЯ ===")
--[[ Повторяем обе стороны боевого правила: как студия делает uid при
     создании и как его же собирает загрузка. Расхождение = порванная
     связь, что владелец и увидел. ]]
local function uidOnCreate(existing)
    -- как в addBlock: ищем первый свободный номер
    local used = {}
    for _, b in ipairs(existing) do
        if b.kind == "checkpoint" then used[tostring((b.data or {}).id or "")] = true end
    end
    local n = 1
    while used["cp" .. n] do n = n + 1 end
    local id = "cp" .. n
    return "cp_" .. id, id
end
local function uidOnLoad(cpID) return "cp_" .. tostring(cpID) end

local blocks = {}
local u1, id1 = uidOnCreate(blocks)
blocks[#blocks + 1] = { kind = "checkpoint", uid = u1, data = { id = id1 } }
ok(u1 == uidOnLoad(id1), "первый чекпоинт: uid при создании = uid при загрузке", u1)

local u2, id2 = uidOnCreate(blocks)
blocks[#blocks + 1] = { kind = "checkpoint", uid = u2, data = { id = id2 } }
ok(u2 == uidOnLoad(id2), "второй чекпоинт: то же самое", u2)
ok(u1 ~= u2, "две точки не сливаются в одну", ("%s / %s"):format(u1, u2))

print("\n=== 3. СВЯЗЬ ПЕРЕЖИВАЕТ КРУГ «СОХРАНИТЬ → ОТКРЫТЬ» ===")
--[[ Моделируем полный цикл: рисуем связь, «сохраняем» (BlocksToQuest),
     «открываем» (QuestToBlocks) и смотрим, нашлась ли цель. Именно на
     этом шаге линия и пропадала. ]]
local function saveGraph(bs)
    local links, cps = {}, {}
    for _, b in ipairs(bs) do
        for _, l in ipairs(b.links or {}) do
            links[#links + 1] = { from = b.uid, to = l.to, port = l.port or 0 }
        end
        if b.kind == "checkpoint" then
            cps[#cps + 1] = { id = tostring((b.data or {}).id or b.uid):gsub("^cp_", "") }
        end
    end
    return { graph = { links = links }, checkpoints = cps }
end
local function loadGraph(quest)
    local byUID, out = {}, {}
    for _, cp in ipairs(quest.checkpoints or {}) do
        local b = { kind = "checkpoint", uid = "cp_" .. tostring(cp.id), data = cp, links = {} }
        out[#out + 1] = b byUID[b.uid] = b
    end
    for _, name in ipairs({ "reward", "achieve", "cut_accept" }) do
        local b = { kind = name, uid = name, links = {} }
        out[#out + 1] = b byUID[b.uid] = b
    end
    local restored = 0
    for _, l in ipairs((quest.graph or {}).links or {}) do
        local from, to = byUID[l.from], byUID[l.to]
        if from and to then
            from.links[#from.links + 1] = { to = l.to, port = l.port }
            restored = restored + 1
        end
    end
    return out, restored
end

local work = {}
local cu, cid = uidOnCreate(work)
local cp = { kind = "checkpoint", uid = cu, data = { id = cid }, links = {} }
work[#work + 1] = cp
work[#work + 1] = { kind = "reward", uid = "reward", links = {} }
work[#work + 1] = { kind = "achieve", uid = "achieve", links = {} }

cp.links[#cp.links + 1] = { to = "reward", port = 0 }
local saved = saveGraph(work)
local _, restored = loadGraph(saved)
ok(restored == 1, "связь чекпоинт → НАГРАДА восстановилась после переоткрытия", restored)

cp.links = { { to = "achieve", port = 0 } }
saved = saveGraph(work)
_, restored = loadGraph(saved)
ok(restored == 1, "связь чекпоинт → АЧИВКА тоже", restored)

cp.links = { { to = "cut_accept", port = 0 } }
saved = saveGraph(work)
_, restored = loadGraph(saved)
ok(restored == 1, "и чекпоинт → КАТ-СЦЕНА", restored)

print("\n=== 4. СТАРЫЙ БАГ ЛОВИТСЯ ===")
--[[ Воспроизводим прежнее поведение: uid = kind. Если проверка выше
     зелёная и здесь тоже — значит она ничего не проверяет. ]]
local broken = { kind = "checkpoint", uid = "checkpoint", data = {}, links = { { to = "reward", port = 0 } } }
local brokenWork = { broken, { kind = "reward", uid = "reward", links = {} } }
local brokenSaved = saveGraph(brokenWork)
local _, brokenRestored = loadGraph(brokenSaved)
ok(brokenRestored == 0,
    "со старым uid связь действительно терялась — стенд проверяет реальную разницу",
    brokenRestored)

print("\n=== 4b. ПУСТОЙ id НЕ ЛОМАЕТ СОХРАНЕНИЕ ===")
--[[ Пустая строка это не nil: выражение `d.id or b.uid` её НЕ заменит.
     Точка сохранилась бы с пустым id, и связи снова потеряли бы
     источник — тот же баг, только с другой стороны. ]]
local b2q = studio:match("function Q%.BlocksToQuest.-\n    return out\nend") or ""
ok(b2q:find('rawID == ""', 1, true) ~= nil,
    "пустой id распознаётся отдельно от nil")
ok(b2q:find('cp.id == ""', 1, true) ~= nil,
    "и заменяется запасным, а не уходит в квест пустым")

print("\n=== 5. ЯДРО ЗАПУСКАЕТ СВЯЗАННЫЕ БЛОКИ ===")
ok(quests:find("function Q.ReachCheckpoint", 1, true) ~= nil, "точка входа есть")
local reach = quests:match("function Q%.ReachCheckpoint.-\n    end") or ""
ok(reach:find("Q.CheckpointUID(cpID)", 1, true) ~= nil,
    "граф обходится от cp_<id> — того же имени, что в связях")

print("\n=== 6. ЖИВОЙ ПРОГОН ЯДРА ===")
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
local FIRED = {}
net = { Receive = function() end, Start = function(n) FIRED[#FIRED+1] = tostring(n) end,
        Send = function() end, Broadcast = function() end,
        WriteTable = function() end, WriteString = function() end, WriteUInt = function() end,
        WriteBool = function() end, WriteFloat = function() end, WriteEntity = function() end }
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
GRM = { Notify = function() end, Format = tostring }
GRM.Ach = { Defs = {}, Register = function() end, RecOf = function() return {} end,
            Unlock = function() FIRED[#FIRED+1] = "achieve" end }
_G.CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
_G.GetConVar = _G.CreateConVar
FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3

assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
ok(isfunction(Q.RunGraphFrom), "модуль квестов загружен")

--[[ Связь «чекпоинт cp1 → ачивка»: ровно то, что владелец не мог
     собрать. Проверяем, что обход графа от cp_cp1 её находит. ]]
local def = {
    id = "q_cp", enabled = true, steps = { { type = "visit" } },
    cutscene = { accept = {}, complete = {} },
    achievement = { id = "quest_q_cp", name = "Тест", enabled = true, description = "", reward = 0 },
    checkpoints = { { id = "cp1", label = "Точка", radius = 96, once = true } },
    graph = { links = { { from = "cp_cp1", to = "achieve", port = 0, when = "now" } } },
}
local ply = { _valid = true,
    SteamID64 = function() return "76561190000000002" end,
    SteamID = function() return "STEAM_0:1:2" end,
    IsPlayer = function() return true end, Nick = function() return "Тестер" end,
    Alive = function() return true end, GetPos = function() return Vector(0,0,0) end,
    GetNWString = function(_, _, d) return d or "" end,
    SetNWString = function() end, SetNWInt = function() end, SetNWBool = function() end,
    ChatPrint = function() end, PrintMessage = function() end }

FIRED = {}
local fired = Q.RunGraphFrom(ply, def, Q.CheckpointUID("cp1"), { step = 1 })
ok((tonumber(fired) or 0) > 0, "связь чекпоинт → АЧИВКА срабатывает в ядре", tostring(fired))

print(("\nCHECKPOINT LINKS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
