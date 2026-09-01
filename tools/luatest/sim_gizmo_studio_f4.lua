--[[--------------------------------------------------------------------
    sim_gizmo_studio_f4 — три жалобы владельца от 31.08:

      1) «Гизмо ни в социальных анимациях ни в аксессуарных настройках —
         нету выделения линий гизмо, непонятно какая линия взята + криво
         определяет где хватать какой гизмо. Беру один, он вращает
         другой, подсветки никакой. Шары какие-то».

      2) «В квест-студии всё ещё наблюдаются проблемы с размещением
         блока наград и ачивок и их соединением с другими блоками,
         выносом полос и блоков за пределы видимости».

      3) «F4 меню должно открываться плавно, оно не должно быть
         маленьким, желательно побольше в размере».

    ПРИЧИНЫ, НАЙДЕННЫЕ В КОДЕ.

    Гизмо. Один и тот же алгоритм был скопирован в два файла, и в обоих:
      * перебор осей шёл через pairs() по таблице со строковыми ключами.
        Порядок обхода в Lua НЕ ОПРЕДЕЛЁН — при равном расстоянии до
        курсора выигрывала случайная ось. Это и есть «беру один, вращает
        другой»: один и тот же клик давал разный результат;
      * кольца вращения проверялись ЦЕЛИКОМ, вместе с дальней от камеры
        половиной. Кольцо, повёрнутое ребром, вырождается в отрезок, и
        его обратная сторона перехватывала клики у соседней оси;
      * подсветки не было вовсе, наконечники — проволочные шарики.

    Квест-студия. Холст 3000x2000 лежал в панели Dock(FILL) БЕЗ
    ПРОКРУТКИ: видно только левый верхний угол. Блок, уехавший правее
    или ниже, пропадал навсегда. Плюс новые блоки ставились по жёсткой
    координате x=320 с шагом по остатку от деления на 5 — шестой блок
    ложился ровно на первый. Награда и ачивка добавляются последними,
    поэтому именно они оказывались под чужой карточкой.

    F4. Жёсткий размер 880x640 и мгновенное появление.

    Запуск: luajit tools/luatest/sim_gizmo_studio_f4.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a")
    fh:close()
    return t
end

-----------------------------------------------------------------------
-- Мок ровно под модуль гизмо.
-----------------------------------------------------------------------
CLIENT, SERVER = true, false
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[ Вектор с нужной арифметикой. Считаем по-настоящему: подделывать
     геометрию в стенде бессмысленно, проверяем именно её. ]]
local VecMeta = {}
VecMeta.__index = VecMeta
function VecMeta:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VecMeta:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VecMeta:Distance(o) return (self - o):Length() end
VecMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VecMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VecMeta.__mul = function(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function Vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMeta)
end

-- Углы: единичный базис, повёрнутый вокруг Z на yaw (этого хватает).
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    local rad = math.rad(a.y)
    local c, s = math.cos(rad), math.sin(rad)
    function a:Forward() return Vector(c, s, 0) end
    function a:Right() return Vector(s, -c, 0) end
    function a:Up() return Vector(0, 0, 1) end
    return a
end

function EyePos() return Vector(0, -300, 0) end
render = setmetatable({}, { __index = function() return function() end end })
cam = { IgnoreZ = function() end }
surface = { SetFont = function() end, GetTextSize = function() return 40, 12 end }
draw = { RoundedBox = function() end, SimpleText = function() end }
GRM = {}

assert(loadfile("lua/autorun/client/cl_grm_gizmo.lua"))()
local G = GRM.Gizmo
assert(G, "модуль гизмо не загрузился")

--[[ Проекция мира на экран. Камера в (0,-300,0) смотрит на +Y, поэтому
     экранный X это мировой X, экранный Y это мировой Z (вниз). ]]
local function project(v)
    local depth = v.y + 300
    if depth < 1 then return { x = 0, y = 0, visible = false } end
    local scale = 600 / depth
    return { x = 960 + v.x * scale, y = 540 - v.z * scale, visible = true }
end

local ORIGIN = Vector(0, 0, 0)
local ANG = Angle(0, 0, 0)
local EYE = EyePos()
local LEN = 20

-----------------------------------------------------------------------
print("\n=== 1. ОСИ ПЕРЕБИРАЮТСЯ В ОПРЕДЕЛЁННОМ ПОРЯДКЕ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ БАГА. Раньше оси лежали в таблице с ключами
         x/y/z и обходились через pairs(). Порядок такого обхода в Lua
         не определён — проверим, что теперь это массив с фиксированным
         порядком. ]]
    ok(#G.Axes == 3, "оси заданы МАССИВОМ, порядок фиксирован", #G.Axes)
    ok(G.Axes[1].id == "x" and G.Axes[2].id == "y" and G.Axes[3].id == "z",
        "порядок именно x, y, z")

    local src = readf("lua/autorun/client/cl_grm_gizmo.lua")
    local collect = src:match("function G%.CollectMove.-\nend")
    ok(collect and collect:find("for i = 1, #G.Axes do", 1, true) ~= nil,
        "перебор идёт по индексу, а не через pairs()")
    ok(collect and collect:find("pairs(", 1, true) == nil,
        "pairs() в выборе оси не осталось — иначе порядок снова поплывёт")
end

do
    -- Один и тот же клик обязан давать один и тот же ответ. Всегда.
    local first = G.Pick("move", ORIGIN, ANG, LEN, 1000, 540, project, EYE)
    local stable = true
    for _ = 1, 50 do
        if G.Pick("move", ORIGIN, ANG, LEN, 1000, 540, project, EYE) ~= first then
            stable = false break
        end
    end
    ok(stable, "ИСПРАВЛЕНО: повторный клик в ту же точку даёт ту же ось", first)
end

-----------------------------------------------------------------------
print("\n=== 2. ХВАТАЕТСЯ ИМЕННО ТА ОСЬ, НА КОТОРУЮ НАВЕЛИСЬ ===")
-----------------------------------------------------------------------
do
    --[[ Ведём курсор вдоль каждой оси и проверяем, что берётся она.
         Мировая ось X даёт горизонталь на экране, Z — вертикаль. ]]
    local o = project(ORIGIN)

    -- Ось X (красная): вправо по экрану.
    local tipX = project(ORIGIN + ANG:Forward() * LEN)
    local mxX = (o.x + tipX.x) * 0.5
    local myX = (o.y + tipX.y) * 0.5
    ok(G.Pick("move", ORIGIN, ANG, LEN, mxX, myX, project, EYE) == "x",
        "середина луча X даёт ось X",
        G.Pick("move", ORIGIN, ANG, LEN, mxX, myX, project, EYE))

    -- Ось Z (синяя): вверх по экрану.
    local tipZ = project(ORIGIN + ANG:Up() * LEN)
    local mxZ = (o.x + tipZ.x) * 0.5
    local myZ = (o.y + tipZ.y) * 0.5
    ok(G.Pick("move", ORIGIN, ANG, LEN, mxZ, myZ, project, EYE) == "z",
        "середина луча Z даёт ось Z",
        G.Pick("move", ORIGIN, ANG, LEN, mxZ, myZ, project, EYE))

    -- Далеко от всех осей — ничего не берётся.
    ok(G.Pick("move", ORIGIN, ANG, LEN, 300, 100, project, EYE) == nil,
        "клик мимо гизмо ничего не хватает")
end

do
    -- Сплошная проверка по всей длине каждого луча.
    local bad = {}
    for _, spec in ipairs({
        { id = "x", dir = ANG:Forward() },
        { id = "z", dir = ANG:Up() },
    }) do
        for k = 3, 9 do
            local t = k / 10
            local p = project(ORIGIN + spec.dir * (LEN * t))
            local got = G.Pick("move", ORIGIN, ANG, LEN, p.x, p.y, project, EYE)
            if got ~= spec.id then
                bad[#bad + 1] = spec.id .. "@" .. t .. "→" .. tostring(got)
            end
        end
    end
    ok(#bad == 0, "вдоль всей длины луча берётся его собственная ось",
        bad[1])
end

-----------------------------------------------------------------------
print("\n=== 3. КОЛЬЦА: ТОЛЬКО ВИДИМАЯ ПОЛОВИНА ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/client/cl_grm_gizmo.lua")
    local rot = src:match("function G%.CollectRotate.-\nend\n\n%-%-%[%[ Общий вход")
        or src:match("function G%.CollectRotate.-\n    return out\nend")
    ok(rot ~= nil, "функция выбора кольца найдена")
    ok(rot and rot:find("Dot(eyePos - origin)", 1, true) ~= nil,
        "ИСПРАВЛЕНО: точка кольца проверяется на видимость (ближняя половина)")
end

do
    --[[ Кольцо вокруг Z лежит в плоскости XY — к нашей камере оно
         повёрнуто РЕБРОМ и вырождается в горизонтальный отрезок.
         Раньше его дальняя половина рисовалась поверх той же линии и
         перехватывала клики. Проверяем, что точка на видимой (ближней)
         дуге отдаёт своё кольцо. ]]
    --[[ Базис кольца Z — это Forward и Right. При 90° точка уходит в
         -Y, то есть В СТОРОНУ камеры (она в y = -300): это ближняя
         дуга. Сначала я взял 270° и получил ровно наоборот — стенд
         честно об этом сообщил. ]]
    local near = G.RingPoint(ORIGIN, ANG, "z", math.rad(90), LEN)
    ok((near - ORIGIN):Dot(EYE - ORIGIN) > 0, "контрольная точка на ближней дуге")
    local p = project(near)
    local got = G.Pick("rotate", ORIGIN, ANG, LEN, p.x, p.y, project, EYE)
    ok(got ~= nil, "на ближней дуге кольцо вообще хватается", got)
end

do
    -- Точка строго на дальней дуге не должна перебивать выбор.
    local far = G.RingPoint(ORIGIN, ANG, "z", math.rad(270), LEN)
    ok((far - ORIGIN):Dot(EYE - ORIGIN) < 0, "контрольная точка на дальней дуге")
end

-----------------------------------------------------------------------
print("\n=== 4. ТАЙ-БРЕЙК ПО ГЛУБИНЕ ===")
-----------------------------------------------------------------------
do
    --[[ Когда две оси одинаково близко к курсору, выигрывать должна
         ближняя к камере: именно она нарисована сверху. ]]
    local best = G.Best({
        { axis = "x", dist = 5, depth = 100, order = 1 },
        { axis = "y", dist = 5, depth = 40,  order = 2 },
    })
    ok(best and best.axis == "y", "при равном расстоянии берётся ближняя к камере",
        best and best.axis)

    -- Явно более близкий к курсору кандидат важнее глубины.
    local best2 = G.Best({
        { axis = "x", dist = 1,  depth = 900, order = 1 },
        { axis = "y", dist = 12, depth = 10,  order = 2 },
    })
    ok(best2 and best2.axis == "x", "заметно более близкий к курсору выигрывает",
        best2 and best2.axis)

    ok(G.Best({}) == nil, "пустой список кандидатов не роняет выбор")
end

-----------------------------------------------------------------------
print("\n=== 5. ПОДСВЕТКА И СТРЕЛКИ ВМЕСТО ШАРОВ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/client/cl_grm_gizmo.lua")
    --[[ Ищем ВЫЗОВ, а не упоминание. Первая версия проверки искала
         подстроку по всему файлу и краснела на слове
         «render.DrawWireframeSphere» в комментарии, который объясняет,
         как было раньше. Классическая ловушка «слово есть в файле». ]]
    ok(src:find("render%.DrawWireframeSphere%s*%(") == nil,
        "ИСПРАВЛЕНО: проволочные шары больше не рисуются")
    ok(src:find("local function drawArrow", 1, true) ~= nil,
        "у осей перемещения появились стрелки")
    ok(src:find("render.DrawBeam", 1, true) ~= nil,
        "оси рисуются толстой лентой — в них можно попасть курсором")

    local draw_ = src:match("function G%.Draw%(.-\nend")
    ok(draw_ and draw_:find("hoverAxis", 1, true) ~= nil,
        "отрисовка знает, что под курсором")
    ok(draw_ and draw_:find("brighten", 1, true) ~= nil,
        "выбранная ось подсвечивается ярче")
    ok(draw_ and draw_:find("dim(", 1, true) ~= nil,
        "остальные приглушаются — видно, какая линия взята")
    ok(draw_ and draw_:find("cam.IgnoreZ(true)", 1, true) ~= nil,
        "гизмо рисуется поверх модели, а не прячется внутри неё")
    ok(src:find("function G.DrawLabel", 1, true) ~= nil,
        "есть подпись оси у курсора")
end

-----------------------------------------------------------------------
print("\n=== 6. ОБА РЕДАКТОРА ЗОВУТ ОДИН МОДУЛЬ ===")
-----------------------------------------------------------------------
do
    local studio = readf("lua/autorun/sh_grm_social_studio.lua")
    local custom = readf("lua/autorun/client/cl_grm_customization.lua")

    ok(studio:find("GRM.Gizmo.Pick", 1, true) ~= nil,
        "студия анимаций использует общий модуль")
    ok(studio:find("GRM.Gizmo.Draw", 1, true) ~= nil, "и общую отрисовку")
    ok(custom:find("GRM.Gizmo.Pick", 1, true) ~= nil,
        "редактор аксессуаров использует общий модуль")
    ok(custom:find("GRM.Gizmo.Draw", 1, true) ~= nil, "и общую отрисовку")

    --[[ Копии алгоритма быть не должно: пока их две, однажды починят
         одну и забудут вторую — так и вышло в прошлый раз. ]]
    -- Опять же: ищем вызов, а не слово в поясняющем комментарии.
    ok(studio:find("render%.DrawWireframeSphere%s*%(") == nil,
        "в студии не осталось своей отрисовки шаров")
    ok(custom:find("render%.DrawWireframeSphere%s*%(") == nil,
        "в редакторе аксессуаров тоже")
    ok(studio:find("local AX = {", 1, true) == nil,
        "дубль таблицы осей в студии убран")
    ok(custom:find("local GIZMO_AXES = {", 1, true) == nil,
        "дубль таблицы осей в редакторе аксессуаров убран")
end

-----------------------------------------------------------------------
print("\n=== 7. КВЕСТ-СТУДИЯ: ХОЛСТ МОЖНО ДВИГАТЬ ===")
-----------------------------------------------------------------------
do
    local qs = readf("lua/autorun/client/zz_grm_quest_studio.lua")

    ok(qs:find("local panX, panY", 1, true) ~= nil,
        "ИСПРАВЛЕНО: у холста появилось смещение")
    ok(qs:find("local function applyPan", 1, true) ~= nil,
        "смещение применяется одной функцией")
    ok(qs:find("canvas.OnMouseWheeled", 1, true) ~= nil,
        "колесо прокручивает холст — раньше уехавшее было не достать")

    local pan = qs:match("local function applyPan%(%).-\n    end")
    ok(pan and pan:find("math.Clamp", 1, true) ~= nil,
        "смещение ограничено — за край холста не улететь")

    -- Панорамирование не должно конфликтовать с построением связей.
    local press = qs:match("canvas%.OnMousePressed = function.-\n    end")
    ok(press and press:find("MOUSE_RIGHT", 1, true) ~= nil,
        "холст тянется правой/средней кнопкой, левая занята связями")
    ok(press and press:find("MOUSE_LEFT", 1, true) == nil,
        "левая кнопка холст не двигает — иначе ломалось бы соединение блоков")
end

-----------------------------------------------------------------------
print("\n=== 8. КВЕСТ-СТУДИЯ: БЛОКИ НЕ УЕЗЖАЮТ И НЕ НАКЛАДЫВАЮТСЯ ===")
-----------------------------------------------------------------------
do
    local qs = readf("lua/autorun/client/zz_grm_quest_studio.lua")

    --[[ ВОСПРОИЗВЕДЕНИЕ БАГА: жёсткая координата нового блока. ]]
    ok(qs:find("x = 320, y = 120 + (#blocks % 5) * 40", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткая координата нового блока убрана")
    ok(qs:find("findFreeSpot", 1, true) ~= nil,
        "место под новый блок ищется свободное")
    ok(qs:find("scrollToBlock", 1, true) ~= nil,
        "к добавленному блоку холст подъезжает — иначе он появится за краем")

    -- Перетаскивание ограничено со ВСЕХ сторон.
    ok(qs:find("b.x = math.max(0, px", 1, true) == nil,
        "ИСПРАВЛЕНО: ограничение только слева убрано")
    local think = qs:match("grip%.Think = function%(self%).-\n            end")
    ok(think and think:find("CANVAS_W - CARD_W", 1, true) ~= nil,
        "блок нельзя утащить за правый край")
    ok(think and think:find("CANVAS_H - CARD_H", 1, true) ~= nil,
        "и за нижний")

    -- Уже сохранённые «улетевшие» блоки чинятся при загрузке.
    local load = qs:match("local function loadWork%(def%).-\n    end")
    ok(load and load:find("math.Clamp", 1, true) ~= nil,
        "уехавшие ранее блоки возвращаются в холст при открытии квеста")
end

do
    --[[ Логика поиска свободного места: проверяем сам принцип на той же
         формуле пересечения, что в студии. Блок не должен ложиться на
         уже стоящий — именно из-за этого терялись награда и ачивка. ]]
    local CARD_W, CARD_H = 236, 104
    local blocks = { { x = 40, y = 40 }, { x = 40, y = 168 } }
    local function occupied(x, y)
        for _, ob in ipairs(blocks) do
            if x < ob.x + CARD_W + 12 and x + CARD_W + 12 > ob.x
                and y < ob.y + CARD_H + 12 and y + CARD_H + 12 > ob.y then
                return true
            end
        end
        return false
    end
    ok(occupied(40, 40), "клетка поверх существующего блока считается занятой")
    ok(not occupied(40 + CARD_W + 28, 40), "соседняя колонка свободна")
    ok(occupied(50, 50), "частичное перекрытие тоже считается занятым")
end

-----------------------------------------------------------------------
print("\n=== 9. F4: БОЛЬШЕ И ПЛАВНЕЕ ===")
-----------------------------------------------------------------------
do
    local f4 = readf("lua/autorun/sh_grm_f4menu.lua")

    ok(f4:find("f:SetSize(880, 640)", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткий маленький размер убран")
    ok(f4:find("math.Clamp(math.floor(ScrW() * 0.78)", 1, true) ~= nil,
        "ширина считается от экрана")
    ok(f4:find("math.Clamp(math.floor(ScrH() * 0.82)", 1, true) ~= nil,
        "высота тоже")

    -- Проверяем сами границы на разных экранах.
    local function fw(sw) return math.Clamp(math.floor(sw * 0.78), 880, 1600) end
    local function fh(sh) return math.Clamp(math.floor(sh * 0.82), 640, 1000) end
    ok(fw(1920) > 880, "на 1920 окно шире прежнего", fw(1920))
    ok(fw(1280) >= 880, "на 1280 не меньше прежнего", fw(1280))
    ok(fw(3840) <= 1600, "на 4K не растягивается через весь экран", fw(3840))
    ok(fh(1080) > 640, "и выше прежнего", fh(1080))
    ok(fw(1024) == 880 and fh(768) == 640,
        "на маленьком мониторе размер прежний, окно не вылезет")

    ok(f4:find("f:AlphaTo(255", 1, true) ~= nil, "окно проявляется плавно")
    ok(f4:find("f:SetAlpha(0)", 1, true) ~= nil,
        "и стартует прозрачным — иначе первый кадр даст вспышку")

    --[[ Кнопка закрытия стояла по жёсткому X=836 от старой ширины 880.
         С новым размером она уехала бы за пределы окна. ]]
    ok(f4:find("x:SetPos(836, 8)", 1, true) == nil,
        "ИСПРАВЛЕНО: крестик больше не привязан к старой ширине")
    local layout = f4:match("f%.PerformLayout = function%(self, pw%).-\n    end")
    ok(layout and layout:find("pw - 44", 1, true) ~= nil,
        "крестик держится правого края при любом размере")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
