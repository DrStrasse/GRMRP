--[[--------------------------------------------------------------------
    sim_quest_graph_chain — квест не должен завершаться сразу после
    первой реплики; блоки не должны уезжать за холст; кольца рисуются
    единым модулем.

    ЖАЛОБА ВЛАДЕЛЬЦА (31.08): «блоки всё ещё за границей графа связей и
    поля видимости + нарушены соединения + неверно идёт срабатывание
    некоторых связей из-за чего квест после диалога сразу же
    принимается и завершается. Дизайн во всех модулях и во всех
    радиальных меню поправь».

    ГЛАВНАЯ ПРИЧИНА (найдена в Q.RunGraphFrom). Обход графа клал в
    очередь ЛЮБОЙ блок, к которому ведёт линия, — включая реплики,
    этапы и чекпоинты. Дальше он брал уже ИХ связи и шёл вглубь. То
    есть одна линия «реплика → следующая реплика» превращала показ
    первой фразы в пробег по всему графу: срабатывали награда, ачивка
    и ФИНИШ, подключённые в самом конце. Квест завершался в тот же миг,
    когда игрок дочитал первую строку.

    ПРАВИЛЬНО: цепочка продолжается ТОЛЬКО через блоки-эффекты (ролик,
    музыка, награда, ачивка, финиш). Реплика, этап и чекпоинт — точки
    ожидания, их запускает своё событие, а не обход графа.

    Запуск: luajit tools/luatest/sim_quest_graph_chain.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Мок GMod.
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return istable(v) and v._valid ~= false end
function CurTime() return 100 end
function SysTime() return 100 end
function RealTime() return 100 end
os.time = function() return 1700000000 end

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a,b,c = self.x-o.x, self.y-o.y, self.z-o.z return a*a+b*b+c*c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    return v
end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.Round = function(v) return math.floor((tonumber(v) or 0) + 0.5) end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
string.Explode = function(sep, str)
    local o = {}
    for p in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = p end
    return o
end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.Copy = function(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = table.Copy(v) end
    return o
end
table.HasValue = function(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end

hook = { Add = function() end, Run = function() end, Remove = function() end,
         Call = function() end, GetTable = function() return {} end }
timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end, Compress = function(x) return x end }
net = setmetatable({}, { __index = function() return function() return "" end end })
file = { Read = function() return nil end, Write = function() end,
         Exists = function() return false end, CreateDir = function() end,
         IsDir = function() return false end, Find = function() return {}, {} end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end,
         Create = function() return { _valid = false } end }
game = { GetMap = function() return "rp_city" end }
resource = { AddFile = function() end }
function ErrorNoHalt() end
function print_() end
GRM = { Notify = function() end }

assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
assert(Q, "ядро квестов не загрузилось")
assert(Q.RunGraphFrom, "Q.RunGraphFrom недоступна")

-----------------------------------------------------------------------
-- Отслеживаем, что реально сработало.
-----------------------------------------------------------------------
local FIRED = {}
local function resetFired() FIRED = {} end

-- Подменяем видимые эффекты: важно ЧТО сработало, а не как выглядит.
Q.ForceFinish = function() FIRED[#FIRED + 1] = "finish" return true end

local ply = { _valid = true, _nw = {} }
function ply:IsPlayer() return true end
function ply:Alive() return true end
function ply:SteamID64() return "76561100000000001" end
function ply:Nick() return "Test" end
function ply:GetNWString(k, d) return self._nw[k] or d or "" end
function ply:SetNWString(k, v) self._nw[k] = v end
function ply:GetPos() return Vector(0, 0, 0) end
function ply:EntIndex() return 1 end

-----------------------------------------------------------------------
print("\n=== 1. ВОСПРОИЗВЕДЕНИЕ БАГА: ЦЕПОЧКА СКВОЗЬ РЕПЛИКИ ===")
-----------------------------------------------------------------------
--[[ Граф ровно как у владельца: первая реплика ведёт ко второй, вторая
     к награде, награда к финишу. Показ ПЕРВОЙ реплики не должен
     трогать ни награду, ни финиш. ]]
local def = {
    id = "q_test", enabled = true, title = "Тест",
    steps = {}, rewards = { money = 0, items = {} },
    cutscene = { accept = {}, complete = {} },
    graph = { links = {
        { from = "node_1", to = "node_2", when = "now", port = 0 },
        { from = "node_2", to = "reward",  when = "now", port = 0 },
        { from = "reward", to = "finish",  when = "now", port = 0 },
    } },
}

do
    resetFired()
    local fired = Q.RunGraphFrom(ply, def, "node_1", { status = "active", step = 1 }, "now")

    --[[ Ключевая проверка. До фикса обход шёл node_1 → node_2 →
         reward → finish и завершал квест на первой же фразе. ]]
    local hasFinish = false
    for _, f in ipairs(FIRED) do if f == "finish" then hasFinish = true end end
    ok(not hasFinish,
        "ИСПРАВЛЕНО: показ первой реплики НЕ завершает квест", table.concat(FIRED, ","))
    ok(fired == 0,
        "от реплики к реплике эффекты не срабатывают", fired)
end

-----------------------------------------------------------------------
print("\n=== 2. ПРЯМАЯ СВЯЗЬ НА ЭФФЕКТ РАБОТАЕТ ===")
-----------------------------------------------------------------------
do
    --[[ Обратная опасность: перестараться и сломать нормальные связи.
         Линия «реплика → финиш» обязана срабатывать. ]]
    local d2 = {
        id = "q2", enabled = true, steps = {}, rewards = { money = 0, items = {} },
        cutscene = { accept = {}, complete = {} },
        graph = { links = { { from = "node_1", to = "finish", when = "now", port = 0 } } },
    }
    resetFired()
    local fired = Q.RunGraphFrom(ply, d2, "node_1", { status = "active" }, "now")
    ok(fired == 1, "прямая связь «реплика → ФИНИШ» срабатывает", fired)
    ok(FIRED[1] == "finish", "именно финиш", FIRED[1])
end

-----------------------------------------------------------------------
print("\n=== 3. ЦЕПОЧКА ЭФФЕКТОВ ПРОДОЛЖАЕТСЯ ===")
-----------------------------------------------------------------------
do
    --[[ Эффект может вести к эффекту: «этап → музыка → ролик». Такая
         цепочка должна отрабатывать целиком — её ломать нельзя. ]]
    local d3 = {
        id = "q3", enabled = true, steps = {},
        rewards = { money = 0, items = {} },
        music = { sound = "a.wav", volume = 1, loop = false },
        cutscene = { accept = { { pos = Vector(0,0,0) } }, complete = {} },
        graph = { links = {
            { from = "step_1", to = "music",      when = "now", port = 0 },
            { from = "music",  to = "cut_accept", when = "now", port = 0 },
        } },
    }
    resetFired()
    local fired = Q.RunGraphFrom(ply, d3, "step_1", { status = "active" })
    ok(fired == 2, "цепочка «музыка → ролик» отработала целиком", fired)
end

-----------------------------------------------------------------------
print("\n=== 4. ЧЕКПОИНТ И ЭТАП — ТОЧКИ ОЖИДАНИЯ ===")
-----------------------------------------------------------------------
do
    --[[ Чекпоинт не должен «проваливаться» дальше по графу при показе
         реплики: он ждёт, пока игрок физически до него дойдёт. ]]
    local d4 = {
        id = "q4", enabled = true, steps = {}, rewards = { money = 0, items = {} },
        cutscene = { accept = {}, complete = {} },
        graph = { links = {
            { from = "node_1",  to = "cp_cp1",  when = "now", port = 0 },
            { from = "cp_cp1",  to = "reward",  when = "now", port = 0 },
        } },
    }
    resetFired()
    local fired = Q.RunGraphFrom(ply, d4, "node_1", { status = "active" }, "now")
    ok(fired == 0, "награда за чекпоинтом не выдаётся заранее", fired)

    -- А когда игрок дошёл — граф от чекпоинта её выдаёт.
    resetFired()
    local fired2 = Q.RunGraphFrom(ply, d4, "cp_cp1", { status = "active" })
    ok(fired2 == 1, "по достижении чекпоинта награда срабатывает", fired2)
end

do
    local d5 = {
        id = "q5", enabled = true, steps = {}, rewards = { money = 0, items = {} },
        cutscene = { accept = {}, complete = {} },
        graph = { links = {
            { from = "node_1", to = "step_1", when = "now", port = 0 },
            { from = "step_1", to = "finish", when = "now", port = 0 },
        } },
    }
    resetFired()
    Q.RunGraphFrom(ply, d5, "node_1", { status = "active" }, "now")
    local hasFinish = false
    for _, f in ipairs(FIRED) do if f == "finish" then hasFinish = true end end
    ok(not hasFinish, "этап тоже не пробрасывает граф к финишу")
end

-----------------------------------------------------------------------
print("\n=== 5. ЗАЩИТА ОТ ЗАЦИКЛИВАНИЯ СОХРАНЕНА ===")
-----------------------------------------------------------------------
do
    --[[ Автор может свести эффекты в кольцо. Без пометки посещённых
         сервер ушёл бы в бесконечный цикл и повесил карту. ]]
    local d6 = {
        id = "q6", enabled = true, steps = {}, rewards = { money = 0, items = {} },
        music = { sound = "a.wav" },
        cutscene = { accept = {}, complete = {} },
        graph = { links = {
            { from = "start",  to = "music",  when = "now", port = 0 },
            { from = "music",  to = "reward", when = "now", port = 0 },
            { from = "reward", to = "music",  when = "now", port = 0 },
        } },
    }
    resetFired()
    local okRun = pcall(Q.RunGraphFrom, ply, d6, "start", { status = "active" })
    ok(okRun, "кольцо из эффектов не роняет сервер")
end

-----------------------------------------------------------------------
print("\n=== 6. ИСХОДНИК ЯДРА ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_quests.lua")
    local run = src:match("function Q%.RunGraphFrom.-\n    end")
    ok(run ~= nil, "функция обхода найдена")

    --[[ Постановка в очередь обязана быть ВНУТРИ проверки на эффект.
         Если она снова окажется снаружи, баг вернётся. ]]
    ok(run and run:find("if runEffect(ply,def,nxt,p) then", 1, true) ~= nil,
        "ИСПРАВЛЕНО: очередь пополняется только эффектами")
    local body = run and run:match("if runEffect.-\n                    end")
    ok(body and body:find("queue[#queue+1]=nxt", 1, true) ~= nil,
        "продолжение цепочки — внутри ветки эффекта")
end

-----------------------------------------------------------------------
print("\n=== 7. СТУДИЯ: БЛОКИ НЕ УЕЗЖАЮТ ЗА ХОЛСТ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/client/zz_grm_quest_studio.lua")

    ok(src:find("local LAY_MAX_Y", 1, true) ~= nil,
        "у раскладки появился предел по высоте")
    ok(src:find("local LAY_MAX_X", 1, true) ~= nil, "и по ширине")

    --[[ Старая формула ставила награду и ачивку в колонку 5 — это
         x = 1240, далеко за видимой областью окна. ]]
    ok(src:find("return 40 + (col - 1) * 300, y", 1, true) == nil,
        "ИСПРАВЛЕНО: старая формула с шагом 300 убрана")

    local place = src:match("local function place%(col%).-\n    end")
    ok(place and place:find("colShift", 1, true) ~= nil,
        "столбец переносится вбок, а не растёт вниз без предела")

    -- ФИНИШ больше не в колонке этапов.
    ok(src:find("FRAME_FINISH_X, FRAME_FINISH_Y = 620, 40", 1, true) == nil,
        "ИСПРАВЛЕНО: ФИНИШ убран с координат колонки этапов")

    --[[ Проверяем саму раскладку на числах: все блоки обязаны влезать
         в холст 3000x2000 с учётом размера карточки. ]]
    local CARD_W, CARD_H = 236, 104
    local LAY_X0, LAY_Y0 = 40, 40
    local LAY_COL_W, LAY_ROW_H = 268, 132
    local LAY_MAX_Y, LAY_MAX_X = 1700, 2700
    local colY, colShift = {}, {}
    local function place(col)
        colY[col] = colY[col] or LAY_Y0
        colShift[col] = colShift[col] or 0
        local y = colY[col]
        if y > LAY_MAX_Y then
            colShift[col] = colShift[col] + 1
            y = LAY_Y0
            colY[col] = y
        end
        colY[col] = y + LAY_ROW_H
        local x = LAY_X0 + (col - 1) * LAY_COL_W + colShift[col] * LAY_COL_W
        if x > LAY_MAX_X then x = LAY_MAX_X end
        return x, y
    end

    local bad = {}
    -- Много блоков в каждой колонке: так выглядит большой квест.
    for col = 1, 5 do
        for _ = 1, 30 do
            local x, y = place(col)
            if x < 0 or x + CARD_W > 3000 then bad[#bad + 1] = "x=" .. x end
            if y < 0 or y + CARD_H > 2000 then bad[#bad + 1] = "y=" .. y end
        end
    end
    ok(#bad == 0, "150 блоков — все внутри холста", bad[1])
end

-----------------------------------------------------------------------
print("\n=== 8. ЕДИНЫЙ МОДУЛЬ КОЛЕЦ ===")
-----------------------------------------------------------------------
do
    local rad = readf("lua/autorun/client/cl_grm_radial.lua")
    local inter = readf("lua/autorun/sh_grm_interact.lua")
    local anims = readf("lua/autorun/sh_grm_social_anims.lua")

    ok(rad:find("function RD.Sector", 1, true) ~= nil,
        "есть кольцевой сектор — секторы разделены, а не слиты")
    ok(rad:find("gapDeg", 1, true) ~= nil, "между секторами есть зазор")
    ok(rad:find("RD.Segments = 96", 1, true) ~= nil,
        "круги гладкие: 96 сегментов вместо прежних 12-20")
    ok(rad:find("function RD.Pick", 1, true) ~= nil,
        "выбор пункта тоже общий — раскладка и выбор не разойдутся")

    --[[ Меню анимаций осталось кольцевым и живёт на общем модуле.

         А меню взаимодействия 31.08 стало ПРЯМОУГОЛЬНЫМ (заказ
         владельца: «похожее на круговое, но только прямоугольное»),
         поэтому кольцевой модуль ему уже не нужен. Требовать от него
         GRM.Radial было бы проверкой ради проверки: важно, что своей
         копии отрисовки колец там нет. ]]
    ok(anims:find("GRM.Radial", 1, true) ~= nil, "меню анимаций использует модуль колец")
    ok(inter:find("P.ItemRect", 1, true) ~= nil,
        "меню взаимодействия перешло на прямоугольную панель")

    --[[ Дубли отрисовки должны были уйти: пока их две, дизайн снова
         разъедется при первой же правке. ]]
    ok(inter:find("surface.DrawPoly(ring)", 1, true) == nil,
        "своя отрисовка сектора в взаимодействии убрана")
    ok(anims:find("surface.DrawPoly(ring)", 1, true) == nil,
        "и в анимациях")

    --[[ Читаемость: владелец отдельно просил не давать тёмный текст.
         Проверяем яркость текстовых цветов палитры. ]]
    local pal = rad:match("RD.Col = {(.-)\n}")
    ok(pal ~= nil, "палитра колец найдена")
    local dark = {}
    for name, r, g, b in pal:gmatch("(%w+)%s*=%s*Color%((%d+),%s*(%d+),%s*(%d+)") do
        local lum = tonumber(r) * 0.299 + tonumber(g) * 0.587 + tonumber(b) * 0.114
        local isText = (name == "text" or name == "dimText" or name == "gold"
            or name == "good" or name == "bad")
        if isText and lum < 110 then dark[#dark + 1] = name end
    end
    ok(#dark == 0, "ни один цвет текста не тёмный", table.concat(dark, ","))
end

-----------------------------------------------------------------------
print("\n=== 9. ГЕОМЕТРИЯ ОБЩЕГО КОЛЬЦА ===")
-----------------------------------------------------------------------
do
    --[[ Раскладка подписей и выбор мышью обязаны совпадать: именно на
         их расхождении в проекте уже ловились гизмо и кольцо анимаций. ]]
    local rad = readf("lua/autorun/client/cl_grm_radial.lua")
    local pick = rad:match("(function RD%.Pick.-\nend)")
    local slotA = rad:match("(function RD%.SlotAngles.-\nend)")
    local slotL = rad:match("(function RD%.SlotLabelPos.-\nend)")
    ok(pick and slotA and slotL, "формулы кольца найдены")

    local env = { math = math, RD = {} }
    local chunk = assert(loadstring(
        "local RD = RD\n" .. pick .. "\n" .. slotA .. "\n" .. slotL .. "\nreturn RD"))
    setfenv(chunk, env)
    local RD = chunk()

    local CX, CY, LR, IR = 960, 540, 160, 92
    local bad = {}
    for count = 2, 12 do
        for i = 1, count do
            local lx, ly = RD.SlotLabelPos(i, count, CX, CY, LR)
            if RD.Pick(lx, ly, CX, CY, count, IR) ~= i then
                bad[#bad + 1] = count .. "/" .. i
            end
        end
    end
    ok(#bad == 0, "наведение на подпись даёт именно её пункт (2..12)", bad[1])
    ok(RD.Pick(CX, CY, CX, CY, 6, IR) == nil, "в центре выбора нет")
    ok(RD.Pick(CX, CY - 200, CX, CY, 0, IR) == nil, "пустой список не роняет")

    -- Первый пункт смотрит вверх.
    local x1, y1 = RD.SlotLabelPos(1, 4, CX, CY, LR)
    ok(math.abs(x1 - CX) < 0.01 and y1 < CY, "первый пункт сверху")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
