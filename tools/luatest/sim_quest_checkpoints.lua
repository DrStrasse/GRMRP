--[[--------------------------------------------------------------------
    sim_quest_checkpoints — блок ЧЕКПОИНТ и рабочий блок ФИНИШ.

    ДВА ЗАКАЗА ВЛАДЕЛЬЦА (30.08):

    1. «Нужен модуль для графа, отвечающий за размещение маркеров,
       чекпоинтов, который можно будет связать с выплатами/ачивками.
       Проп круга из plastic, материал debugwhite, красный,
       прозрачность 50%, как в логистике. Чекпоинты крутящиеся.»

    2. «Не срабатывает блок финиша, не выставляется в граф.»

    ПОЧЕМУ ФИНИШ НЕ РАБОТАЛ. Блок в палитре был и даже создавался в
    QuestToBlocks, но для ядра `finish` — только ИМЯ ТРИГГЕРА, от
    которого расходятся линии (Q.RunGraphFrom(ply,def,"finish",p) в
    конце квеста). Целью связи он быть не мог: в runEffect его нет, в
    EFFECT_UIDS тоже. Линия «этап → ФИНИШ» рисовалась, сохранялась и не
    делала ничего — квест не завершался.

    ЧТО ПРОВЕРЯЕМ:
      * чекпоинт есть в палитре, переживает сохранение и переоткрытие;
      * визуал ровно как в логистике: debugwhite, красный, альфа 127;
      * чекпоинт вращается;
      * достижение чекпоинта двигает квест и запускает связанные блоки
        (награда, ачивка) — ради этого он и нужен;
      * ФИНИШ как ЦЕЛЬ связи реально завершает квест;
      * старые квесты без чекпоинтов работают как раньше.

    Запуск: luajit tools/luatest/sim_quest_checkpoints.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
--[[ Мягкое чтение: на коде ДО правки файлов энтити ещё нет. Жёсткий
     assert уронил бы стенд на первом же обращении и скрыл все
     остальные провалы — тогда непонятно, что именно делать. ]]
local function readSoft(p)
    local f = io.open(p, "rb")
    if not f then return "" end
    local s = f:read("*a") f:close() return s
end

local quests = read("lua/autorun/sh_grm_quests.lua")
local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")

print("\n=== 1. ЧЕКПОИНТ ЕСТЬ В ПАЛИТРЕ БЛОКОВ ===")
local palette = studio:match("Q%.BlockTypes = %{.-\n%}") or ""
ok(palette ~= "", "таблица типов блоков найдена")
ok(palette:find('id = "checkpoint"', 1, true) ~= nil,
    "чекпоинт объявлен как тип блока")
ok(palette:find("ЧЕКПОИНТ", 1, true) ~= nil, "у него человеко-понятное имя")

print("\n=== 2. ВИЗУАЛ КАК В ЛОГИСТИКЕ ===")
--[[ Владелец указал конкретный эталон — точка погрузки логистики:
     RENDERMODE_TRANSCOLOR + debugwhite + красный с альфой 127.
     Сверяем ровно с ним, чтобы чекпоинты не выбивались из вида сервера. ]]
local entInit = readSoft("lua/entities/grm_quest_checkpoint/init.lua")
ok(entInit:find("models/debug/debugwhite", 1, true) ~= nil, "материал debugwhite")
ok(entInit:find("RENDERMODE_TRANSCOLOR", 1, true) ~= nil, "режим прозрачности как у точки погрузки")
ok(entInit:find("127", 1, true) ~= nil, "альфа 127 — те же 50% прозрачности")
ok(entInit:find("Color(255, 0, 0", 1, true) ~= nil, "цвет красный")

local shared = readSoft("lua/entities/grm_quest_checkpoint/shared.lua")
local model = entInit:match('SetModel%("([^"]+)"') or shared:match('Model%s*=%s*"([^"]+)"') or ""
--[[ Модель обязана совпадать с эталоном логистики: владелец указал её
     прямо, и одинаковый вид маркеров важнее «красивой» альтернативы.
     Сверяем с конфигом логистики, а не с зашитой строкой — если там
     поменяют модель, стенд заметит расхождение. ]]
local logi = read("lua/autorun/sh_grm_industry_core.lua")
local logiModel = logi:match('depot%s*=%s*%{[^}]-model%s*=%s*"([^"]+)"') or ""
ok(model ~= "" and model == logiModel,
    "модель та же, что у точки погрузки логистики",
    ("чекпоинт=%s логистика=%s"):format(model, logiModel))
ok(model:find("tube", 1, true) ~= nil or model:find("plate", 1, true) ~= nil
   or model:find("cylinder", 1, true) ~= nil or model:find("circle", 1, true) ~= nil,
    "это круглый проп из стандартного набора", model)

print("\n=== 3. ЧЕКПОИНТ ВРАЩАЕТСЯ ===")
--[[ Вращение крутим на КЛИЕНТЕ: гонять угол по сети каждый кадр ради
     украшения — пустая нагрузка на сервер и на канал. ]]
local entCl = readSoft("lua/entities/grm_quest_checkpoint/cl_init.lua")
ok(entCl:find("SetAngles", 1, true) ~= nil or entCl:find("RenderAngles", 1, true) ~= nil,
    "клиент крутит модель")
ok(entCl:find("RealTime", 1, true) ~= nil or entCl:find("CurTime", 1, true) ~= nil,
    "угол считается от времени — вращение плавное и одинаковое у всех")

print("\n=== 4. ЧЕКПОИНТ ПЕРЕЖИВАЕТ СОХРАНЕНИЕ КВЕСТА ===")
--[[ Классическая ловушка этой студии: BlocksToQuest пересобирает квест
     с нуля, и всё, что не перенесли явно, стирается при первом же
     сохранении. Так уже терялись graph.links, music, map и флаг
     момента кат-сцены. ]]
local b2q = studio:match("function Q%.BlocksToQuest.-\n    return out\nend") or ""
ok(b2q ~= "", "BlocksToQuest найдена")
ok(b2q:find('b.kind == "checkpoint"', 1, true) ~= nil,
    "чекпоинты собираются из блоков при сохранении")
ok(b2q:find("out.checkpoints", 1, true) ~= nil, "и складываются в поле квеста")

local q2b = studio:match("function Q%.QuestToBlocks.-\n    return blocks") or
            studio:match("function Q%.QuestToBlocks.-\nend") or ""
ok(q2b:find("checkpoint", 1, true) ~= nil,
    "и восстанавливаются обратно в блоки при открытии")

print("\n=== 5. НОРМАЛИЗАЦИЯ НА СЕРВЕРЕ НЕ ТЕРЯЕТ ЧЕКПОИНТЫ ===")
ok(quests:find("normalizeCheckpoints", 1, true) ~= nil, "есть нормализация чекпоинтов")
local norm = quests:match("checkpoints=normalizeCheckpoints[^,]*") or ""
ok(norm ~= "", "нормализованный список попадает в определение квеста")

print("\n=== 6. ФИНИШ КАК ЦЕЛЬ СВЯЗИ ЗАВЕРШАЕТ КВЕСТ ===")
--[[ Главная жалоба: «не срабатывает блок финиша». Для ядра finish был
     только ИМЕНЕМ ТРИГГЕРА (от него расходятся линии в конце квеста), а
     целью связи быть не мог — в runEffect его не было. Линия рисовалась,
     сохранялась и не делала ничего. ]]
local runEffect = quests:match("local function runEffect.-\n    end") or ""
ok(runEffect ~= "", "runEffect найден")
ok(runEffect:find('uid=="finish"', 1, true) ~= nil,
    "finish обрабатывается как цель связи")

local effectUids = quests:match("local EFFECT_UIDS = %{[^}]*%}") or ""
ok(effectUids:find("finish", 1, true) ~= nil,
    "finish числится эффектом — иначе GraphDrives его не увидит")

print("\n=== 7. ЧЕКПОИНТ ДВИГАЕТ КВЕСТ ===")
ok(quests:find("Q.ReachCheckpoint", 1, true) ~= nil,
    "есть серверная точка входа «игрок дошёл до чекпоинта»")
--[[ Смысл блока в том, чтобы связать точку на карте с выплатой. Значит
     достижение чекпоинта обязано запускать связанные с ним блоки. ]]
local reach = quests:match("function Q%.ReachCheckpoint.-\n    end") or ""
ok(reach:find("RunGraphFrom", 1, true) ~= nil,
    "достижение чекпоинта запускает связанные блоки (награда, ачивка)")

print("\n=== 8. ТОЧКА СТАВИТСЯ ТУЛОМ, А НЕ РУКАМИ ===")
--[[ Координаты, вписанные руками в поля студии, — гарантированная
     опечатка: маркер окажется под картой или в стене. Ставим кликом. ]]
local tool = read("lua/weapons/gmod_tool/stools/grm_quest_tool.lua")
ok(tool:find('mode=="checkpoint"', 1, true) ~= nil, "у тула есть режим чекпоинта")
ok(tool:find("SetCheckpointPos", 1, true) ~= nil, "клик ставит точку через ядро")
ok(tool:find("checkpoint_id", 1, true) ~= nil, "тул знает, какой именно точке ставит позицию")
ok(quests:find("function Q.SetCheckpointPos", 1, true) ~= nil, "серверная постановка есть")

local setPos = quests:match("function Q%.SetCheckpointPos.-\n    end") or ""
ok(setPos:find("RefreshCheckpointMarkers", 1, true) ~= nil,
    "после постановки маркер появляется сразу, без перезапуска карты")

print("\n=== 9. ПАНЕЛЬ БЛОКА В СТУДИИ ===")
ok(studio:find('b.kind == "checkpoint"', 1, true) ~= nil, "у блока есть своя панель")
ok(studio:find("grm_quest_tool_checkpoint_id", 1, true) ~= nil,
    "кнопка подставляет ID точки в тул")
ok(studio:find("Считать этап пройденным", 1, true) ~= nil,
    "есть переключатель «двигает этап»")
ok(studio:find("НЕ поставлена", 1, true) ~= nil,
    "видно, поставлена точка или нет — иначе автор не поймёт, почему маркера нет")

print("\n=== 10. МАРКЕРЫ НЕ ПЛОДЯТСЯ И НЕ ВИСЯТ ЛИШНИЕ ===")
local refresh = quests:match("function Q%.RefreshCheckpointMarkers.-\n    end") or ""
ok(refresh ~= "", "пересборка маркеров найдена")
ok(refresh:find("ent:Remove()", 1, true) ~= nil,
    "старые маркеры снимаются перед расстановкой — иначе они копятся")
ok(refresh:find("def.draft", 1, true) ~= nil and refresh:find("FitsMap", 1, true) ~= nil,
    "черновики и чужие карты маркеров не получают")

print("\n=== 11. ЖИВОЙ ПРОГОН ГРАФА С ФИНИШЕМ ===")
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
net = { Receive = function() end,
        Start = function(n) FIRED[#FIRED+1] = tostring(n) end,
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
_G.CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
_G.GetConVar = _G.CreateConVar
FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
ok(isfunction(Q.RunGraphFrom), "модуль квестов загружен")

--[[ Связь «этап → ФИНИШ»: ровно то, что владелец собрал в студии.
     Проверяем, что обход графа доходит до finish и тот срабатывает. ]]
local finished = {}
Q.Complete = Q.Complete or function() end
local def = {
    id = "q_fin", enabled = true, steps = { { type = "visit" } },
    cutscene = { accept = {}, complete = {} },
    graph = { links = { { from = "step_1", to = "finish", port = 0, when = "now" } } },
}
--[[ Игрок должен уметь всё, что ядро зовёт по дороге к завершению:
     ключ персонажа, ник, оповещения. Без этого стенд падает в моке, а
     не на проверке — и мы не узнаем, сработала связь или нет. ]]
local ply = {
    _valid = true,
    SteamID64 = function() return "76561190000000001" end,
    SteamID = function() return "STEAM_0:1:1" end,
    IsPlayer = function() return true end,
    Nick = function() return "Тестер" end,
    Alive = function() return true end,
    GetPos = function() return Vector(0, 0, 0) end,
    GetNWString = function(_, _, d) return d or "" end,
    SetNWString = function() end, SetNWInt = function() end, SetNWBool = function() end,
    ChatPrint = function() end, PrintMessage = function() end,
}
FIRED = {}
local fired = Q.RunGraphFrom(ply, def, "step_1", { step = 1 })
ok((tonumber(fired) or 0) > 0, "связь «этап → ФИНИШ» действительно сработала", tostring(fired))

print(("\nQUEST CHECKPOINTS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
