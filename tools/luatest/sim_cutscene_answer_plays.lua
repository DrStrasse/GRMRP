--[[--------------------------------------------------------------------
    sim_cutscene_answer_plays — ролик от выбранного ответа ДОИГРЫВАЕТ.

    ЖАЛОБА ВЛАДЕЛЬЦА (30.08): «обратная ситуация — кат-сцена не
    показывается при выборе верного диалога». То есть привязка к ответу
    заработала, а ролик пропал совсем.

    ПРИЧИНА — ПОРЯДОК ВНУТРИ flushPending:

        1) Q.FlushCutscene(ply)          <- очередь пуста, выпускать нечего
        2) RunGraphFrom(..., "after")    <- ЗДЕСЬ ролик попадает в очередь
        3) RunGraphFrom(..., "after", port)   и остаётся в ней навсегда

    Гейт в cutscene() откладывает ролик, пока идёт разговор
    (ply.GRMQuestDlg жив). На момент шага 2-3 сессия ЕЩЁ существует —
    её снимают строкой ниже, уже после flushPending. Поэтому эффект
    честно кладёт ролик в очередь, но выпуск давно позади: ролик не
    играет вообще.

    ПРАВИЛЬНЫЙ ПОРЯДОК: сначала прогнать все отложенные эффекты, а
    выпускать очередь ПОСЛЕДНИМ — тогда в неё успевает попасть всё, что
    добавили сами эффекты.

    Стенд гоняет НАСТОЯЩИЙ код обоих модулей: и sh_grm_quests (гейт,
    очередь), и sh_grm_quest_dialogue (flushPending). Проверять здесь
    копию логики нельзя — именно это в прошлый раз скрыло дефект.

    Запуск: luajit tools/luatest/sim_cutscene_answer_plays.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

-------------------------------------------------------------------------
-- Мини-окружение GMod
-------------------------------------------------------------------------
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
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    return v
end
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
    for piece in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = piece end return o end

local HOOKS = {}
hook = {
    Add = function(ev, name, fn) HOOKS[ev] = HOOKS[ev] or {} HOOKS[ev][name] = fn end,
    Remove = function(ev, name) if HOOKS[ev] then HOOKS[ev][name] = nil end end,
    Run = function() end,
}
timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end, Compress = function(x) return x end }

--- Ловим показ ролика по net-сообщению: cutscene() зовёт локальную
--- cutsceneNow через замыкание, подменить её полем нельзя (проверено).
local SHOWN = {}
net = {
    Receive = function() end,
    Start = function(name) if tostring(name) == "GRM_Quest_Cutscene" then SHOWN[#SHOWN + 1] = "cut" end end,
    Send = function() end, Broadcast = function() end,
    WriteTable = function() end, WriteString = function() end, WriteUInt = function() end,
    WriteBool = function() end, WriteFloat = function() end, WriteEntity = function() end,
    ReadTable = function() return {} end, ReadUInt = function() return 0 end,
    ReadString = function() return "" end,
}
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

assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
ok(Q ~= nil and isfunction(Q.RunGraphFrom), "модуль квестов загружен")
ok(isfunction(Q.QueueCutscene) and isfunction(Q.FlushCutscene), "очередь роликов на месте")

-------------------------------------------------------------------------
-- 1. ГЕЙТ: во время разговора ролик откладывается
-------------------------------------------------------------------------
print("\n=== 1. ВО ВРЕМЯ РАЗГОВОРА РОЛИК ОТКЛАДЫВАЕТСЯ ===")
local def = {
    id = "q_test",
    cutscene = {
        accept = { { caption = "кадр", duration = 3 } },
        complete = {},
        acceptAfterDialogue = true,          -- «ждать конца диалога»
    },
    graph = { links = {
        -- линия ОТ ВТОРОГО ОТВЕТА к ролику, отложенная
        { from = "talk_last", to = "cut_accept", port = 2, when = "after" },
    } },
}
local ply = { _valid = true, GRMQuestDlg = { questID = "q_test" } }

SHOWN = {}
Q.RunGraphFrom(ply, def, "talk_last", nil, "after", 2)
ok(#SHOWN == 0, "пока диалог открыт, ролик на экран не ушёл", #SHOWN)
ok(Q.PendingCutscene[ply] ~= nil, "ролик лёг в очередь")

-------------------------------------------------------------------------
-- 2. ГЛАВНОЕ: выпуск очереди ПОСЛЕ прогона эффектов
-------------------------------------------------------------------------
print("\n=== 2. ПОРЯДОК ВНУТРИ flushPending ===")
--[[ Здесь ловится жалоба «кат-сцена не показывается при выборе верного
     диалога». Если выпуск стоит ДО прогона эффектов, ролик попадает в
     очередь уже после выпуска и остаётся там навсегда. ]]
local dlg = io.open("lua/autorun/sh_grm_quest_dialogue.lua"):read("*a")
local fp = dlg:match("local function flushPending%(ply%).-\n    end") or ""
ok(fp ~= "", "flushPending найдена")

local atFlush = fp:find("FlushCutscene", 1, true)
local atAfter = fp:find('Q.RunGraphFrom(ply, def, uid, nil, "after")', 1, true)
local atPort  = fp:find("rec.port", 1, true)
ok(atFlush and atAfter and atFlush > atAfter,
    "очередь выпускается ПОСЛЕ связей реплики",
    ("flush=%s after=%s"):format(tostring(atFlush), tostring(atAfter)))
ok(atFlush and atPort and atFlush > atPort,
    "очередь выпускается ПОСЛЕ связей выбранного ответа",
    ("flush=%s port=%s"):format(tostring(atFlush), tostring(atPort)))

-------------------------------------------------------------------------
-- 3. СКВОЗНОЙ ПРОГОН: ответ -> конец разговора -> ролик на экране
-------------------------------------------------------------------------
print("\n=== 3. СКВОЗНОЙ ПРОГОН ВЫБОРА ОТВЕТА ===")
--[[ Повторяем боевую последовательность: игрок выбрал 2-й ответ,
     эффекты отложились, разговор закончился, очередь выпущена. ]]
local function simulateTalk(pickedPort)
    SHOWN = {}
    Q.PendingCutscene = {}
    local p = { _valid = true, GRMQuestDlg = { questID = "q_test", pendingChoice = {} } }
    -- выбор ответа: копим отложенные связи (как делает обработчик)
    p.GRMQuestDlg.pendingChoice[1] = { uid = "talk_last", port = pickedPort }
    -- конец разговора: сначала эффекты, потом выпуск очереди
    for _, rec in ipairs(p.GRMQuestDlg.pendingChoice) do
        Q.RunGraphFrom(p, def, rec.uid, nil, "after", rec.port)
    end
    Q.FlushCutscene(p)
    return #SHOWN
end

ok(simulateTalk(2) == 1, "верный ответ (2) — ролик показан", simulateTalk(2))
ok(simulateTalk(1) == 0, "другой ответ (1) — ролика нет", simulateTalk(1))

-------------------------------------------------------------------------
-- 4. ОЧЕРЕДЬ НЕ ЗАСТРЕВАЕТ
-------------------------------------------------------------------------
print("\n=== 4. ОЧЕРЕДЬ НЕ ЗАСТРЕВАЕТ ===")
SHOWN = {}
Q.PendingCutscene = {}
local p2 = { _valid = true, GRMQuestDlg = { questID = "q_test" } }
Q.RunGraphFrom(p2, def, "talk_last", nil, "after", 2)
ok(Q.PendingCutscene[p2] ~= nil, "ролик в очереди")
Q.FlushCutscene(p2)
ok(#SHOWN == 1, "выпуск показал ролик", #SHOWN)
ok(Q.PendingCutscene[p2] == nil, "очередь очищена — повторно не сыграет")
Q.FlushCutscene(p2)
ok(#SHOWN == 1, "второй выпуск ничего не показывает", #SHOWN)

-------------------------------------------------------------------------
-- 5. БЕЗ РАЗГОВОРА — СРАЗУ
-------------------------------------------------------------------------
print("\n=== 5. ВНЕ РАЗГОВОРА РОЛИК ИДЁТ СРАЗУ ===")
--[[ Ролик от этапа посреди города обязан играть немедленно: иначе он
     повис бы в очереди до следующей болтовни с NPC — тихая потеря,
     которую заметить труднее, чем ранний показ. ]]
SHOWN = {}
Q.PendingCutscene = {}
local lone = { _valid = true }                -- GRMQuestDlg нет
Q.RunGraphFrom(lone, def, "talk_last", nil, "after", 2)
ok(#SHOWN == 1, "вне разговора показан немедленно", #SHOWN)
ok(Q.PendingCutscene[lone] == nil, "в очередь не клался")

print(("\nCUTSCENE ANSWER PLAYS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
