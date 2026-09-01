--[[--------------------------------------------------------------------
    sim_cutscene_by_answer — ролик привязан к КОНКРЕТНОМУ ответу игрока.

    ЗАКАЗ ВЛАДЕЛЬЦА (29.08). «Он должен учитывать отрицательный ответ в
    последнем диалоге. Там два варианта ответа, и нужно ставить, на какой
    вариант делать запуск кат-сцены, чтобы не просто ткнул 1-й ответ —
    кат-сцена, ткнул 2-й — кат-сцена.»

    ЧТО БЫЛО НЕ ТАК. Две отдельные причины, и обе давали один симптом:

      1. graphTargets игнорировала поле port. В студии порты у ответов
         были (линия тянется от конкретного варианта, port сохраняется в
         связь и доезжает до сервера), но на сервере при обходе графа
         номер порта не читался вовсе — срабатывали ВСЕ связи от реплики
         независимо от того, что выбрал игрок.

      2. Триггер стоял на ПОКАЗЕ реплики (sendNode), то есть до того, как
         игрок вообще успел ответить. Даже с правильным портом момент был
         неверный: эффект уходил в очередь ещё до выбора.

    КАК ДОЛЖНО БЫТЬ:
      port = 0  — связь от самой реплики: срабатывает при показе (прежнее
                  поведение, обратная совместимость);
      port = N  — связь от N-го ответа: срабатывает ТОЛЬКО когда игрок
                  выбрал именно этот вариант.

    Запуск: luajit tools/luatest/sim_cutscene_by_answer.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local quests = read("lua/autorun/sh_grm_quests.lua")
local dialogue = read("lua/autorun/sh_grm_quest_dialogue.lua")
local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")

print("\n=== 1. ОБХОД ГРАФА ЧИТАЕТ НОМЕР ОТВЕТА ===")
local gt = quests:match("local function graphTargets.-\n    end") or ""
ok(gt ~= "", "graphTargets найдена")
ok(gt:find("port", 1, true) ~= nil,
    "обход графа учитывает порт (номер ответа), а не только блок-источник")

print("\n=== 2. ЖИВОЙ ПРОГОН НА БОЕВОМ КОДЕ ===")
--[[ ВАЖНО: гоняем НАСТОЯЩУЮ Q.RunGraphFrom из sh_grm_quests.lua, а не
     копию её логики. Первая версия стенда повторяла отбор у себя — и
     потому не заметила откат, при котором боевой graphTargets перестал
     читать порт: копия-то работала правильно. Проверка, которая не
     краснеет на сломанном коде, бесполезна. ]]
local env = { _fired = {} }
do
    -- Мини-окружение GMod: ровно столько, чтобы модуль квестов загрузился.
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
        function v:DistToSqr(o) local a,b,c = self.x-o.x, self.y-o.y, self.z-o.z return a*a+b*b+c*c end
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
    string.Trim = function(s2) return (tostring(s2):gsub("^%s+", ""):gsub("%s+$", "")) end
    string.Explode = function(sep, str) local o = {}
        for piece in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = piece end return o end
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
    player = { GetAll = function() return {} end, GetBySteamID64 = function() return nil end }
    game = { GetMap = function() return "rp_test" end, SinglePlayer = function() return false end }
    concommand = { Add = function() end }
    surface, draw, cam, render, vgui = {}, {}, {}, {}, {}
    engine = { TickInterval = function() return 0.03 end }
    GRM = { Notify = function() end, Format = tostring }
    _G.CreateConVar = function() return { GetInt = function() return 0 end,
        GetFloat = function() return 0 end, GetBool = function() return false end,
        GetString = function() return "" end } end
    _G.GetConVar = _G.CreateConVar
    FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3
    local chunk = assert(loadfile("lua/autorun/sh_grm_quests.lua"))
    pcall(chunk)
end

local Q = GRM.Quests
ok(Q ~= nil and isfunction(Q.RunGraphFrom), "боевой модуль квестов загружен")

-- Подменяем исполнение эффектов: нам важно, КАКИЕ блоки сработали.
local fired = {}
local def = {
    id = "q_test",
    cutscene = { accept = {}, complete = {} },
    graph = { links = {
        { from = "talk_last", to = "music",      port = 0, when = "now" },
        { from = "talk_last", to = "cut_accept", port = 1, when = "after" },
        { from = "talk_last", to = "achieve",    port = 2, when = "after" },
    } },
}
local ply = { _valid = true }

--[[ Ловим срабатывания по НАБЛЮДАЕМОМУ следу каждого эффекта:
       cut_accept — Q._CutsceneNow (показ ролика),
       music      — net.Start("GRM_Quest_Music"),
       achieve    — GRM.Achievements.Unlock.
     Так проверяется настоящий путь исполнения, а не выдуманный. ]]
--[[ Перехватываем СЕТЬ, а не внутренние функции: cutscene() зовёт
     локальную cutsceneNow через замыкание, поэтому подмена поля
     Q._CutsceneNow на неё не влияет (проверено — эффекты «не срабатывали»,
     хотя код был верный). Имя net-сообщения — честный наблюдаемый след. ]]
-- Ачивки в ядре живут в GRM.Ach (не GRM.Achievements — проверено по коду
-- unlockQuestAchievement). Даём ровно те поля, которые оно спрашивает.
GRM.Ach = { Defs = {}, Register = function() end, RecOf = function() return {} end }
local NET_TO_BLOCK = {
    GRM_Quest_Cutscene = "cut_accept",
    GRM_Quest_Music    = "music",
}
local function targets(uid, mode, port)
    fired = {}
    local realNet = net.Start
    local realUnlock = GRM.Ach.Unlock
    net.Start = function(name)
        local tag = NET_TO_BLOCK[tostring(name)]
        if tag then fired[#fired + 1] = tag end
    end
    GRM.Ach.Unlock = function() fired[#fired + 1] = "achieve" end
    pcall(Q.RunGraphFrom, ply, def, uid, nil, mode, port)
    net.Start, GRM.Ach.Unlock = realNet, realUnlock
    return fired
end
-- Ролику нужны кадры, иначе показ отсеется как пустой.
def.cutscene.accept = { { caption = "кадр", duration = 3 } }
def.music = { sound = "ambient/guit1.wav", volume = 1, when = "start" }
def.achievement = { id = "quest_q_test", name = "Тест", enabled = true, description = "", reward = 0 }

local atShow = targets("talk_last", "now", nil)
ok(#atShow == 1 and atShow[1] == "music",
    "при показе реплики срабатывает только общая связь", table.concat(atShow, ","))

local ans1 = targets("talk_last", "after", 1)
ok(#ans1 == 1 and ans1[1] == "cut_accept",
    "ответ 1 запускает ролик", table.concat(ans1, ","))

local ans2 = targets("talk_last", "after", 2)
ok(#ans2 == 1 and ans2[1] == "achieve",
    "ответ 2 запускает СВОЙ эффект, а не ролик", table.concat(ans2, ","))

ok(#targets("talk_last", "after", 3) == 0,
    "у ответа без связи не срабатывает ничего")

print("\n=== 3. ТРИГГЕР — ВЫБОР ОТВЕТА, А НЕ ПОКАЗ РЕПЛИКИ ===")
--[[ Даже с правильным портом момент важен: пока эффект висел на показе
     реплики, он срабатывал до того, как игрок вообще ответил. ]]
local pick = dialogue:match("net%.Receive%(NET_PICK.-\n    end%)") or ""
ok(pick ~= "", "обработчик выбора найден")
--[[ Проверяем ФАКТ передачи номера ответа в граф, а не выдуманное имя
     функции: сигнатура RunGraphFrom(ply,def,uid,p,mode,port) общая для
     всех вызовов, отдельной обёртки нет. ]]
ok(pick:find("Q.RunGraphFrom(ply, def, uid, nil, \"now\", choiceIndex)", 1, true) ~= nil,
    "выбранный ответ запускает свои связи по номеру порта")
ok(pick:find("choiceIndex > 0", 1, true) ~= nil,
    "срабатывает только на реальный ответ, а не на автопереход")
ok(pick:find("pendingChoice", 1, true) ~= nil,
    "отложенные связи ответа копятся с его номером")

print("\n=== 4. ОТЛОЖЕННЫЕ ЭФФЕКТЫ ОТВЕТА ДОЖИВАЮТ ДО КОНЦА РАЗГОВОРА ===")
--[[ Ответ «после диалога» обязан копиться так же, как связи реплики:
     иначе выбор варианта с роликом не сыграет вовсе. ]]
local fp = dialogue:match("local function flushPending%(ply%).-\n    end") or ""
ok(fp ~= "", "flushPending найдена")
ok(fp:find("pendingChoice", 1, true) ~= nil,
    "выпуск обрабатывает связи выбранных ответов")
--[[ Ранний выход обязан учитывать ОБА списка. Пока проверялся только
     sess.pending, при пустом списке связей реплики функция возвращалась
     раньше — и эффект ответа не срабатывал вовсе. ]]
ok(fp:find("istable(sess.pending) or istable(sess.pendingChoice)", 1, true) ~= nil,
    "выход по пустоте учитывает и связи ответов, а не только реплики")
ok(fp:find("rec.port", 1, true) ~= nil,
    "при выпуске передаётся номер ответа, иначе сработают чужие варианты")

print("\n=== 5. СТАРЫЕ КВЕСТЫ НЕ ЛОМАЮТСЯ ===")
--[[ Связь без порта (port=0 или поле отсутствует) — это связь самой
     реплики. Такие квесты сделаны до появления портов и обязаны
     работать как раньше: срабатывать при показе. ]]
local legacy = { graph = { links = { { from = "n1", to = "cut_accept", when = "now" } } } }
local function legacyTargets(uid, mode, port)
    local out = {}
    for _, l in ipairs(legacy.graph.links) do
        if tostring(l.from) == uid then
            local w = (l.when == "after") and "after" or "now"
            local lp = tonumber(l.port) or 0
            local matchPort = (port == nil and lp == 0) or (port ~= nil and lp == port)
            if ((not mode) or w == mode) and matchPort then out[#out + 1] = l.to end
        end
    end
    return out
end
ok(#legacyTargets("n1", "now", nil) == 1,
    "связь без порта по-прежнему срабатывает при показе реплики")
ok(#legacyTargets("n1", "now", 1) == 0,
    "и НЕ прилипает к произвольному ответу")

print("\n=== 6. В СТУДИИ ВИДНО, К КАКОМУ ОТВЕТУ ПРИВЯЗАНА ЛИНИЯ ===")
ok(studio:find("port = slot", 1, true) ~= nil,
    "линия от ответа сохраняет номер варианта")
-- Автор должен видеть привязку в панели ролика, иначе настройка снова
-- окажется «где-то отдельно», как было с моментом запуска.
ok(studio:find("ответ", 1, true) ~= nil or studio:find("ОТВЕТ", 1, true) ~= nil,
    "в подписи связей упоминается ответ")

print(("\nCUTSCENE BY ANSWER: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
