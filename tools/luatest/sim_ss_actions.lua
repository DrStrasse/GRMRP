--[[
    sim_ss_actions.lua — маршрутизация операций панели спецслужбы.

    Что было: обработчик NET_ACT в sh_grm_special_service.lua разбирал
    имя операции лестницей из ЧЕТЫРНАДЦАТИ `elseif act == …`. Это плохо
    по двум причинам:
      1. на каждый клик агента выполнялось до четырнадцати сравнений строк;
      2. новая операция дописывалась в середину простыни, и промах веткой
         (или дубль имени) означал молчаливое «Неизвестная операция» —
         на живом сервере это выглядит как «кнопка не работает».

    Стало: таблица SS_ACTIONS, имя операции — ключ.

    Стенд поднимает НАСТОЯЩИЙ модуль в моках, перехватывает зарегистри-
    рованный net-обработчик и дёргает каждую операцию, проверяя, что она
    зовёт ровно ту функцию SS.*, что и раньше, и с теми же аргументами.
    Проверка идёт ЦИКЛОМ по таблице ожиданий (§5.4.15): забытая операция
    краснеет именно своей строкой.

    Откатная проверка (§10.2): переименование ключа в SS_ACTIONS или
    возврат ветки с опечаткой красит соответствующую операцию.
]]

local pass, fail = 0, 0
local function ok(cond, name, extra)
    if cond then
        pass = pass + 1
        print("  ok   " .. name)
    else
        fail = fail + 1
        print("  FAIL " .. name .. (extra and ("  [" .. tostring(extra) .. "]") or ""))
    end
end

-- ── окружение ────────────────────────────────────────────────────────
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function include() end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 1000 end
function SysTime() return 1000 end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function CreateClientConVar() end
function ErrorNoHalt() end
string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.HasValue = function(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end

local RECEIVERS, HOOKS = {}, {}
hook = {
    Add = function(name, id, fn) HOOKS[name] = HOOKS[name] or {} HOOKS[name][id] = fn end,
    Run = function() end,
    Remove = function() end,
}
timer = { Simple = function() end, Create = function() end, Remove = function() end, Exists = function() return false end }
concommand = { Add = function() end }
util = {
    AddNetworkString = function(n) return n end,
    TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end,
    Compress = function(s) return s end,
    Decompress = function(s) return s end,
}
file = {
    Exists = function() return false end, Read = function() return nil end,
    Write = function() end, CreateDir = function() end,
    Find = function() return {}, {} end, Delete = function() end, Size = function() return 0 end,
    IsDir = function() return true end, Time = function() return 0 end, Append = function() end,
    Rename = function() end, AsyncRead = function() end,
}
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end }

-- Читаемые из сети значения задаёт тест перед вызовом обработчика.
local READ = { strings = {}, ints = {}, tables = {} }
net = {
    Start = function() end, Send = function() end, Broadcast = function() end,
    WriteString = function() end, WriteInt = function() end, WriteUInt = function() end,
    WriteBool = function() end, WriteTable = function() end, WriteEntity = function() end,
    ReadString = function() return table.remove(READ.strings, 1) or "" end,
    ReadInt = function() return table.remove(READ.ints, 1) or 0 end,
    ReadUInt = function() return table.remove(READ.ints, 1) or 0 end,
    ReadBool = function() return false end,
    ReadTable = function() return table.remove(READ.tables, 1) or {} end,
    ReadEntity = function() return nil end,
    Receive = function(name, fn) RECEIVERS[name] = fn end,
}

GRM = { Notify = function() end }
dofile("tools/luatest/lib_grm_core.lua")()
GRM.Identity = { CharacterKey = function(p) return p._key or "0:char1" end }
GRM.Access = { Register = function() end, Has = function() return true end }
GRM.Audit = { Write = function() end }
GRM.Save = { Register = function() end, Mark = function() end }
GRM.Boot = { Task = function(_, _, fn) if isfunction(fn) then fn() end end, Lazy = function() end }
GRM.Net = { Guard = function() return true end }
GRM.Perf = { Players = function() return {} end, Entities = function() return {} end }
GRM.Wanted = { Records = {}, Catalog = {}, Levels = {}, Fines = {} }

assert(loadfile("lua/autorun/sh_grm_special_service.lua"))()
local SS = GRM.SpecialService
ok(istable(SS), "модуль спецслужбы загрузился")

local actReceiver
for name, fn in pairs(RECEIVERS) do
    if tostring(name):lower():find("act") then actReceiver = fn end
end
ok(isfunction(actReceiver), "обработчик операций зарегистрирован в сети")

-- Агентом делаем кого угодно: права проверяет другой стенд.
SS.IsAgent = function() return true end
SS.Send = function() SS._sent = (SS._sent or 0) + 1 end

--[[ Ожидания: имя операции → какая функция SS.* обязана быть вызвана и
     с какими аргументами (проверяем то, что реально влияет на данные). ]]
local CASES = {
    { act = "level", fn = "CovertSetLevel", target = "76561:char1", text = "повод", num = 3,
      check = function(a) return a[2] == "76561:char1" and a[3] == 3 and a[4] == "повод" end },
    { act = "wipe", fn = "CovertWipe", target = "76561:char1", text = "зачистка",
      check = function(a) return a[2] == "76561:char1" and a[3] == "зачистка" end },
    { act = "hide", fn = "CovertHide", target = "76561:char1", text = "скрыть", num = 1,
      check = function(a) return a[3] == true end },
    { act = "hide", fn = "CovertHide", target = "76561:char1", text = "показать", num = 0,
      check = function(a) return a[3] == false end, name = "hide(0) снимает скрытие" },
    { act = "charge_remove", fn = "CovertRemoveCharge", target = "76561:char1", text = "снять", num = 7,
      check = function(a) return a[3] == 7 end },
    { act = "fine_wipe", fn = "CovertWipeFine", num = 42, text = "аннулировать",
      check = function(a) return a[2] == 42 and a[3] == "аннулировать" end },
    { act = "release", fn = "CovertRelease", target = "76561:char1",
      check = function(a) return a[2] == "76561:char1" end },
    { act = "cover_issue", fn = "IssueCover", target = "76561:char2", text = "Легенда",
      extra = { label = "Купец", faction = "Торговля" },
      check = function(a) return a[2] == "76561:char2" and istable(a[3]) and a[3].label == "Купец" end },
    { act = "cover_switch", fn = "SetActiveCover", target = "76561:char2", num = 2,
      check = function(a) return a[2] == "76561:char2" and a[3] == 2 end },
    { act = "cover_revoke", fn = "RevokeCover", target = "76561:char2", num = 1,
      check = function(a) return a[3] == 1 end },
    { act = "case_save", fn = "CaseSave", target = "case1", text = "фабула", num = 4,
      extra = { summary = "длинная фабула", status = "active" },
      check = function(a) return a[2] == "case1" and a[3].summary == "длинная фабула" and a[3].status == "active" end },
    { act = "case_save", fn = "CaseSave", target = "case1", text = "короткая", num = 4, extra = {},
      check = function(a) return a[3].summary == "короткая" and a[3].threat == 4 end,
      name = "case_save без extra берёт текст и угрозу из обычных полей" },
    { act = "case_note", fn = "CaseAddNote", target = "case1", text = "заметка",
      check = function(a) return a[3] == "заметка" end },
    { act = "case_note_del", fn = "CaseRemoveNote", target = "case1", num = 2,
      check = function(a) return a[3] == 2 end },
    { act = "case_delete", fn = "CaseDelete", target = "case1",
      check = function(a) return a[2] == "case1" end },
}

local agent = { __valid = true, _key = "1:char1", IsPlayer = function() return true end,
    SteamID64 = function() return "1" end, IsSuperAdmin = function() return true end,
    ChatPrint = function() end, PrintMessage = function() end }

local function fire(case)
    READ.strings = { case.act, case.target or "", case.text or "" }
    READ.ints = { case.num or 0 }
    READ.tables = { case.extra or {} }
    agent.GRM_SSActNext = 0
    actReceiver(0, agent)
end

for _, case in ipairs(CASES) do
    local called
    local original = SS[case.fn]
    SS[case.fn] = function(...) called = { ... } return true, "готово" end
    fire(case)
    SS[case.fn] = original
    local label = case.name or ("операция " .. case.act .. " → SS." .. case.fn)
    if not called then
        ok(false, label, "функция не вызвана")
    else
        ok(case.check(called), label, "аргументы не совпали")
    end
end

-- refresh отвечает не результатом, а свежим снимком панели.
SS._sent = 0
fire({ act = "refresh" })
ok(SS._sent == 1, "операция refresh отправляет снимок панели")

-- Неизвестная операция не должна молча проглатываться.
local answered
local originalStart = net.Start
net.Start = function(name) answered = name return originalStart(name) end
fire({ act = "нет_такой_операции" })
net.Start = originalStart
ok(answered ~= nil, "неизвестная операция получает честный отказ, а не тишину")

-- Лестница не должна вернуться.
local src = io.open("lua/autorun/sh_grm_special_service.lua", "rb"):read("*a")
ok(src:find('elseif act == "', 1, true) == nil, "лестница `elseif act ==` не вернулась")
ok(src:find("SS_ACTIONS", 1, true) ~= nil, "операции описаны таблицей SS_ACTIONS")

print(("SS ACTIONS: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
os.exit(fail > 0 and 1 or 0)
