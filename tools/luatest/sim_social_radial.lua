--[[--------------------------------------------------------------------
    sim_social_radial — радиальное меню соц.анимаций.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08, по скриншоту чужого проекта): «радиальное
    меню анимаций с показом этих самых анимаций, причём рендерит как
    саму анимацию, так и 3д модельку персонажа за которого человек
    играет».

    ЧТО БЫЛО. Только окно со списком: рельс категорий, карточки,
    предпросмотр сбоку. Чтобы включить анимацию, надо попасть курсором
    в конкретную кнопку — медленно, и в бою/отыгрыше неудобно.

    ЧТО ПРОВЕРЯЕМ (боевые функции модуля, не копии логики):
      * ВЫБОР НАПРАВЛЕНИЕМ. R.Pick считает пункт по УГЛУ от центра —
        попадать курсором в мелкую цель не нужно. Проверяем все
        четыре стороны и границы секторов.
      * МЁРТВАЯ ЗОНА в центре: там модель, выбора быть не должно —
        иначе меню применяло бы случайный пункт при чуть дрогнувшей
        мыши у центра.
      * РАСКЛАДКА по кольцу согласована с выбором: подпись пункта
        лежит там же, куда ведёт курсор. Если R.SlotPos и R.Pick
        разойдутся, игрок будет целиться в одну надпись, а получать
        соседнюю — самый неприятный класс багов в таком меню.
      * УСТОЙЧИВОСТЬ: ноль пунктов, один пункт, много пунктов.
      * ИСХОДНИК: модель берётся СВОЯ (модель, скин, bodygroups),
        рисуется без двойника в мире, анимация считается общей
        функцией Sample, затемняется только круг, а не весь экран.

    Запуск: luajit tools/luatest/sim_social_radial.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- Мок GMod. Клиентская часть модуля, поэтому CLIENT = true.
-----------------------------------------------------------------------
SERVER, CLIENT = false, true
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function isangle(v) return istable(v) and v.__angle == true end
function IsValid(v) return istable(v) and v._valid ~= false end

function CurTime() return 100 end
function RealTime() return 100 end
function SysTime() return 100 end
function FrameTime() return 0.016 end

function Angle(p, y, r) return { __angle = true, p = p or 0, y = y or 0, r = r or 0 } end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
    return v
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.NormalizeAngle = function(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
string.Explode = function(sep, str)
    local o = {}
    for p in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = p end
    return o
end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

hook = { Add = function() end, Remove = function() end, Run = function() end }
timer = { Create = function() end, Remove = function() end, Simple = function() end,
          Exists = function() return false end }
util = { AddNetworkString = function() end }
net = { Receive = function() end, Start = function() end, SendToServer = function() end,
        ReadString = function() return "" end, WriteString = function() end }
player = { GetAll = function() return {} end }
concommand = { Add = function() end }
surface = { CreateFont = function() end, PlaySound = function() end,
            SetDrawColor = function() end, DrawPoly = function() end }
draw = { NoTexture = function() end, SimpleText = function() end,
         SimpleTextOutlined = function() end, RoundedBox = function() end }
render = setmetatable({}, { __index = function() return function() end end })
cam = { Start3D = function() end, End3D = function() end }
gui = { MousePos = function() return 0, 0 end, EnableScreenClicker = function() end,
        IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end }
vgui = { Create = function() return { _valid = false } end }
function CreateClientConVar() end
function GetConVarNumber() return 1 end
function ClientsideModel() return { _valid = false } end
function LocalPlayer() return { _valid = false } end
function ScrW() return 1920 end
function ScrH() return 1080 end
RENDERGROUP_OTHER = 0
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 88
TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT = 1, 0, 2
IN_ATTACK, IN_ATTACK2 = 1024, 2048
GRM = { Notify = function() end }

assert(loadfile("lua/autorun/sh_grm_social_anims.lua"))()
local S = GRM.Social
assert(S, "GRM.Social не загрузился")
local R = S.Radial
assert(R, "радиальное меню не объявлено")

-- Центр условного экрана 1920x1080.
local CX, CY = 960, 540

-----------------------------------------------------------------------
print("\n=== 1. ВЫБОР НАПРАВЛЕНИЕМ, А НЕ ПОПАДАНИЕМ В КНОПКУ ===")
-----------------------------------------------------------------------
do
    local far = R.OuterR - 20        -- заведомо вне мёртвой зоны
    -- Четыре пункта: вверх, вправо, вниз, влево.
    ok(R.Pick(CX, CY - far, CX, CY, 4) == 1, "мышь вверх — первый пункт",
        R.Pick(CX, CY - far, CX, CY, 4))
    ok(R.Pick(CX + far, CY, CX, CY, 4) == 2, "мышь вправо — второй",
        R.Pick(CX + far, CY, CX, CY, 4))
    ok(R.Pick(CX, CY + far, CX, CY, 4) == 3, "мышь вниз — третий",
        R.Pick(CX, CY + far, CX, CY, 4))
    ok(R.Pick(CX - far, CY, CX, CY, 4) == 4, "мышь влево — четвёртый",
        R.Pick(CX - far, CY, CX, CY, 4))

    --[[ Кольцо не должно читаться зеркально. Экранный Y растёт ВНИЗ,
         и если это не учесть, «вправо» и «влево» меняются местами —
         игрок ведёт мышь к одной надписи, а подсвечивается другая. ]]
    ok(R.Pick(CX + far, CY, CX, CY, 4) ~= R.Pick(CX - far, CY, CX, CY, 4),
        "право и лево — разные пункты (кольцо не зеркальное)")
end

-----------------------------------------------------------------------
print("\n=== 2. МЁРТВАЯ ЗОНА В ЦЕНТРЕ (там модель) ===")
-----------------------------------------------------------------------
do
    ok(R.Pick(CX, CY, CX, CY, 6) == nil, "ровно в центре выбора нет")
    ok(R.Pick(CX + R.InnerR - 5, CY, CX, CY, 6) == nil,
        "чуть внутри мёртвой зоны — тоже нет")
    ok(R.Pick(CX + R.InnerR + 5, CY, CX, CY, 6) ~= nil,
        "сразу за её границей выбор появляется")
    ok(R.InnerR > 0 and R.OuterR > R.InnerR, "радиусы заданы осмысленно",
        R.InnerR .. "/" .. R.OuterR)
end

-----------------------------------------------------------------------
print("\n=== 3. ПОДПИСЬ ЛЕЖИТ ТАМ, КУДА ВЕДЁТ КУРСОР ===")
-----------------------------------------------------------------------
do
    --[[ Самый неприятный класс багов в радиальном меню: раскладка
         подписей и разбор угла считаются разными формулами и потихоньку
         расходятся. Тогда игрок целится в «Приветствие», а включается
         соседний пункт. Проверяем согласованность сплошь. ]]
    local bad = {}
    for count = 2, 12 do
        for i = 1, count do
            local lx, ly = R.SlotPos(i, count, CX, CY, R.LabelR)
            local got = R.Pick(lx, ly, CX, CY, count)
            if got ~= i then
                bad[#bad + 1] = ("count=%d слот=%d получили=%s"):format(count, i, tostring(got))
            end
        end
    end
    ok(#bad == 0, "наведение на подпись любого пункта даёт именно его",
        #bad > 0 and (bad[1] .. " (всего " .. #bad .. ")") or nil)
end

do
    -- Границы секторов: чуть в сторону от подписи всё ещё её пункт.
    local count = 8
    local bad = 0
    for i = 1, count do
        local step = 360 / count
        for _, off in ipairs({ -step * 0.4, -step * 0.2, 0, step * 0.2, step * 0.4 }) do
            local a = math.rad((i - 1) * step - 90 + off)
            local x = CX + math.cos(a) * R.LabelR
            local y = CY + math.sin(a) * R.LabelR
            if R.Pick(x, y, CX, CY, count) ~= i then bad = bad + 1 end
        end
    end
    ok(bad == 0, "весь сектор пункта отдаёт этот пункт, а не соседний", bad)
end

-----------------------------------------------------------------------
print("\n=== 4. КРАЙНИЕ СЛУЧАИ ===")
-----------------------------------------------------------------------
do
    ok(R.Pick(CX, CY - 200, CX, CY, 0) == nil, "пустая категория не роняет выбор")
    ok(R.Pick(CX, CY - 200, CX, CY, 1) == 1, "единственный пункт выбирается с любой стороны")
    ok(R.Pick(CX + 200, CY, CX, CY, 1) == 1, "и он же — с противоположной")

    local far = R.OuterR + 400
    ok(R.Pick(CX, CY - far, CX, CY, 4) == 1,
        "далеко за кольцом направление всё равно читается (мышь у края экрана)")

    -- Много пунктов: индекс не должен выпрыгивать за границы списка.
    local outside = 0
    for count = 2, 24 do
        for deg = 0, 359, 7 do
            local a = math.rad(deg)
            local x = CX + math.cos(a) * (R.LabelR)
            local y = CY + math.sin(a) * (R.LabelR)
            local idx = R.Pick(x, y, CX, CY, count)
            if idx ~= nil and (idx < 1 or idx > count) then outside = outside + 1 end
        end
    end
    ok(outside == 0, "индекс никогда не выходит за пределы списка", outside)
end

-----------------------------------------------------------------------
print("\n=== 5. РАСКЛАДКА ПО КОЛЬЦУ ===")
-----------------------------------------------------------------------
do
    local x, y = R.SlotPos(1, 4, CX, CY, R.LabelR)
    ok(math.abs(x - CX) < 0.01 and y < CY, "первый пункт сверху", x .. "," .. y)
    local x2, y2 = R.SlotPos(2, 4, CX, CY, R.LabelR)
    ok(x2 > CX and math.abs(y2 - CY) < 0.01, "второй справа — идём по часовой стрелке")
    local x3, y3 = R.SlotPos(3, 4, CX, CY, R.LabelR)
    ok(math.abs(x3 - CX) < 0.01 and y3 > CY, "третий снизу")

    -- Пункты не наезжают друг на друга.
    local minDist = math.huge
    for i = 1, 8 do
        local ax, ay = R.SlotPos(i, 8, CX, CY, R.LabelR)
        for j = i + 1, 8 do
            local bx, by = R.SlotPos(j, 8, CX, CY, R.LabelR)
            local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
            if d < minDist then minDist = d end
        end
    end
    ok(minDist > 40, "при восьми пунктах подписи разнесены", math.floor(minDist))
end

-----------------------------------------------------------------------
print("\n=== 6. ИСХОДНИК: модель своя, рисуется без двойника ===")
-----------------------------------------------------------------------
do
    local src = io.open("lua/autorun/sh_grm_social_anims.lua", "rb"):read("*a")

    --[[ Проверяем ВНУТРИ функции создания модели, а не по всему файлу.

         Первая версия стенда искала "m:SetNoDraw(true)" во всём
         исходнике — и не заметила подмены на false, потому что такая же
         строка есть ниже, в коде пропа-планшета. Классическая ловушка
         «слово есть где-то в файле»: проверка зелёная, баг на месте. ]]
    local mk = src:match("local function radialEnsureModel%(%).-\nend")
    ok(mk ~= nil, "функция создания модели найдена")

    ok(mk and mk:find("lp:GetModel()", 1, true) ~= nil,
        "берётся модель СВОЕГО персонажа, а не заглушка")
    ok(mk and mk:find("m:SetSkin(lp:GetSkin()", 1, true) ~= nil, "скин копируется с игрока")
    ok(mk and mk:find("SetBodygroup", 1, true) ~= nil,
        "bodygroups копируются — иначе форма/костюм пропадут")
    ok(mk and mk:find("m:SetNoDraw(true)", 1, true) ~= nil,
        "модель скрыта от движка: иначе рядом с игроком появился бы двойник")
    ok(src:find("cam.Start3D", 1, true) ~= nil, "рисуется вручную в 3D поверх игры")
    ok(src:find("SuppressEngineLighting", 1, true) ~= nil,
        "своё освещение — в тёмном помещении силуэт не утонет")

    -- Анимация в кольце обязана считаться ТОЙ ЖЕ функцией, что в игре.
    local paint = src:match("f%.Paint = function%(_, w, h%)(.-)\n    end\n\n    %-%- Колесо")
    ok(paint ~= nil, "тело отрисовки кольца найдено")
    ok(paint and paint:find("S.Sample(", 1, true) ~= nil,
        "анимация в меню считается боевой S.Sample, а не копией логики")
    ok(paint and paint:find("FrameAdvance", 1, true) ~= nil,
        "базовая анимация модели тоже проигрывается (модель живая)")

    --[[ 31.08 владелец уже ловил меня на подложке во весь экран в
         студии («чё за потемнение?»). Здесь затемняться должен ТОЛЬКО
         круг под меню. ]]
    --[[ Отрисовка кольца 31.08 переехала в общий модуль GRM.Radial
         (заказ владельца «во всех радиальных меню дизайн поправь»), и
         своей DrawPoly здесь больше нет. Проверяем то же по сути:
         затемнение идёт КОЛЬЦОМ через общий модуль, а не заливкой
         всего экрана. ]]
    ok(paint and paint:find("RD.Draw", 1, true) ~= nil,
        "кольцо рисуется общим модулем")
    ok(src:find("function RD.Backdrop", 1, true) == nil,
        "своей реализации подложки в модуле анимаций нет")
    local rad = io.open("lua/autorun/client/cl_grm_radial.lua", "rb")
    local radSrc = rad and rad:read("*a") or ""
    if rad then rad:close() end
    ok(radSrc:find("function RD.Backdrop", 1, true) ~= nil,
        "затемнение — кольцом под секторами, а не на весь экран")
    ok(radSrc:find("RD.Sector(cx, cy, 0, 360, r0, r1", 1, true) ~= nil,
        "подложка построена как кольцо: центр остаётся чистым")
    local fullFill = paint and paint:match("draw%.RoundedBox%(%s*%d+%s*,%s*0%s*,%s*0%s*,%s*w%s*,%s*h")
    ok(fullFill == nil, "НЕТ заливки во весь экран — игру видно",
        fullFill)
end

-----------------------------------------------------------------------
print("\n=== 7. ИСХОДНИК: поведение клавиши и камеры ===")
-----------------------------------------------------------------------
do
    local src = io.open("lua/autorun/sh_grm_social_anims.lua", "rb"):read("*a")

    ok(src:find('hook.Add("PlayerButtonUp", "GRM_Soc_KeyUp"', 1, true) ~= nil,
        "отпускание клавиши применяет выбор (меню на удержание)")
    ok(src:find("S._radialOpenedAt", 1, true) ~= nil,
        "есть защита от мгновенного закрытия при коротком нажатии")

    local up = src:match('hook%.Add%("PlayerButtonUp".-\nend%)')
    ok(up and up:find("0.25", 1, true) ~= nil,
        "порог удержания задан явно — иначе клик закрыл бы меню в тот же кадр")

    --[[ Курсор в радиальном меню двигается мышью. Без блокировки тот
         же ход мыши разворачивал бы игрока: выбираешь анимацию и
         крутишься на месте. ]]
    local sc = src:match('hook%.Add%("StartCommand", "GRM_Soc_MenuFreeze".-\nend%)')
    ok(sc and sc:find("SetMouseX(0)", 1, true) ~= nil,
        "пока кольцо открыто, мышь не крутит камеру")
    ok(sc and sc:find("SetViewAngles", 1, true) ~= nil, "угол обзора удерживается")

    ok(src:find("function S.ApplyRadialChoice", 1, true) ~= nil,
        "применение вынесено в одну функцию (клик и отпускание не разойдутся)")

    -- Обычное окно списком должно остаться: им пользуется биндер.
    ok(src:find("function S.OpenMenu", 1, true) ~= nil, "полное окно со списком сохранено")
    ok(src:find("grm_cl_social_radial", 1, true) ~= nil,
        "радиальное меню можно отключить конвар'ом")
end

-----------------------------------------------------------------------
print("\n=== 8. ЗАКРЫТИЕ ЧИСТИТ ЗА СОБОЙ ===")
-----------------------------------------------------------------------
do
    local src = io.open("lua/autorun/sh_grm_social_anims.lua", "rb"):read("*a")
    local close = src:match("function S%.CloseRadialMenu%(%).-\nend")
    ok(close and close:find("radialCleanup()", 1, true) ~= nil,
        "клиентская модель удаляется — иначе утечка на каждое открытие")
    ok(close and close:find("EnableScreenClicker(false)", 1, true) ~= nil,
        "курсор отпускается, иначе игрок останется с мышью посреди игры")
    local cleanup = src:match("local function radialCleanup%(%).-\nend")
    ok(cleanup and cleanup:find("R.ent:Remove()", 1, true) ~= nil,
        "модель именно удаляется, а не просто забывается")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
