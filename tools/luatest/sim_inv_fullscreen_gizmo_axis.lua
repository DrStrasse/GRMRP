--[[--------------------------------------------------------------------
    sim_inv_fullscreen_gizmo_axis — три жалобы владельца от 31.08:

      1) «Инвентарь побольше — на весь экран давай всё и модель поправь,
         а то за границы выходит»;
         «где в инвентаре кнопка использовать? И ПКМ не вижу чтобы
         срабатывало, чтобы показывало мини-контекстные клавиши».

      2) «Колесо анимаций тоже поправь показ модели».

      3) «Я выбираю гизмо Z — вращение Z, но он почему-то вращает по X,
         а X вращает по Y».

    ПРИЧИНЫ, НАЙДЕННЫЕ В КОДЕ.

    ГИЗМО (самое серьёзное). В GMod угол это Angle(pitch, yaw, roll), и
    каждое поле вращает вокруг своей оси:
        roll  — вокруг Forward (X)
        pitch — вокруг Right   (Y)
        yaw   — вокруг Up      (Z)
    А оба редактора связывали их «по алфавиту»: x→pitch, y→yaw, z→roll.
    Соответствие сдвинуто на позицию — берёшь кольцо Z, крутится roll,
    то есть вокруг X. Ровно то, что описал владелец.

    ИНВЕНТАРЬ. Размер был жёстким (330+690 на 620), камера модели — по
    жёстким числам под одну модель. Панель деталей имела высоту 90
    точек, а кнопки «Использовать»/«Выбросить» стоят на y=132 — ниже её
    дна, поэтому их не было видно. ПКМ по слоту молча использовал
    предмет, ничего не показывая.

    КОЛЕСО. Камера тоже по жёстким числам (фигура обрезана), свет
    задавался только рассеянный — силуэт чёрный, а подсветка сектора
    заливалась ОТ ЦЕНТРА поверх модели и при одном пункте занимала все
    360°.

    Запуск: luajit tools/luatest/sim_inv_fullscreen_gizmo_axis.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function near(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 0.001)
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a")
    fh:close()
    return t
end

CLIENT, SERVER = true, false
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
local VM = {}
VM.__index = VM
function VM:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VM:Distance(o) return (self - o):Length() end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    function a:Forward() return Vector(1, 0, 0) end
    function a:Right() return Vector(0, -1, 0) end
    function a:Up() return Vector(0, 0, 1) end
    return a
end
function EyePos() return Vector(0, -300, 0) end
function ScrW() return 1920 end
function ScrH() return 1080 end
render = setmetatable({}, { __index = function() return function() end end })
cam = { IgnoreZ = function() end }
surface = { SetFont = function() end, GetTextSize = function() return 40, 12 end }
draw = { RoundedBox = function() end, SimpleText = function() end }
GRM = {}

assert(loadfile("lua/autorun/client/cl_grm_gizmo.lua"))()
local G = GRM.Gizmo

local invSrc = readf("lua/autorun/client/cl_grm_inventory_ui.lua")
local animSrc = readf("lua/autorun/sh_grm_social_anims.lua")
local studioSrc = readf("lua/autorun/sh_grm_social_studio.lua")
local customSrc = readf("lua/autorun/client/cl_grm_customization.lua")

-----------------------------------------------------------------------
print("\n=== 1. ГИЗМО: ОСЬ КРУТИТ СВОЁ ПОЛЕ УГЛА ===")
-----------------------------------------------------------------------
do
    --[[ Главная проверка. В GMod вращение вокруг Forward это roll,
         вокруг Right это pitch, вокруг Up это yaw. ]]
    ok(G.AngleKeyOf ~= nil, "соответствие «ось → поле угла» вынесено в модуль")
    ok(G.AngleKeyOf.x == "r",
        "ИСПРАВЛЕНО: ось X крутит roll (вокруг Forward)", G.AngleKeyOf.x)
    ok(G.AngleKeyOf.y == "p",
        "ИСПРАВЛЕНО: ось Y крутит pitch (вокруг Right)", G.AngleKeyOf.y)
    ok(G.AngleKeyOf.z == "yaw",
        "ИСПРАВЛЕНО: ось Z крутит yaw (вокруг Up)", G.AngleKeyOf.z)

    -- Старое (сломанное) соответствие быть не должно.
    ok(not (G.AngleKeyOf.x == "p" and G.AngleKeyOf.z == "r"),
        "БАГ НЕ ВЕРНУЛСЯ: соответствие больше не сдвинуто по алфавиту")

    -- Каждая ось крутит СВОЁ поле, пересечений нет.
    local seen = {}
    local dup = false
    for _, ax in ipairs({ "x", "y", "z" }) do
        local k = G.AngleKeyOf[ax]
        if seen[k] then dup = true end
        seen[k] = true
    end
    ok(not dup, "три оси — три разных поля угла")
end

do
    -- Имя поля yaw отличается в двух хранилищах: студия зовёт его yaw,
    -- аксессуары — y. Функция обязана учитывать оба.
    ok(G.AngleKey("z", "yaw") == "yaw", "студия анимаций получает поле yaw")
    ok(G.AngleKey("z", "y") == "y", "редактор аксессуаров получает поле y")
    ok(G.AngleKey("x", "y") == "r", "roll называется одинаково в обоих")
    ok(G.AngleKey("y", "yaw") == "p", "pitch тоже")
end

-----------------------------------------------------------------------
print("\n=== 2. ОБА РЕДАКТОРА ИСПОЛЬЗУЮТ ОБЩЕЕ СООТВЕТСТВИЕ ===")
-----------------------------------------------------------------------
do
    ok(studioSrc:find("GRM.Gizmo.AngleKey", 1, true) ~= nil,
        "студия анимаций берёт поле из модуля")
    ok(customSrc:find("GRM.Gizmo.AngleKey", 1, true) ~= nil,
        "редактор аксессуаров тоже")

    -- Локальных копий сломанного правила остаться не должно.
    ok(studioSrc:find('ST.gzAxis == "x" then rec.p = v', 1, true) == nil,
        "в студии убрано локальное x→pitch")
    ok(customSrc:find('axis == "x" and "p" or axis == "y" and "y" or "r"', 1, true) == nil,
        "в аксессуарах убрано локальное x→p, y→y, z→r")

    --[[ Слайдеры углов были подписаны по имени поля и завязаны на
         старое соответствие: после починки гизмо тянешь кольцо Z, а
         обновляется строка Pitch. ]]
    ok(customSrc:find("Вокруг Z (Yaw)", 1, true) ~= nil,
        "слайдер аксессуаров подписан осью, а не полем")
    ok(customSrc:find("angleSliders.z=add(\"Вокруг Z (Yaw)\",-180,180,equipped.angles.y", 1, true) ~= nil,
        "и слайдер оси Z действительно правит yaw")
    ok(customSrc:find("angleSliders.x=add(\"Вокруг X (Roll)\",-180,180,equipped.angles.r", 1, true) ~= nil,
        "слайдер оси X правит roll")
    ok(studioSrc:find('addSl("Вокруг Z (Yaw)", "yaw"', 1, true) ~= nil,
        "в студии слайдер оси Z правит yaw")
    ok(studioSrc:find('addSl("Вокруг X (Roll)", "r"', 1, true) ~= nil,
        "в студии слайдер оси X правит roll")
end

-----------------------------------------------------------------------
print("\n=== 3. ИНВЕНТАРЬ: РАЗМЕР ОТ ЭКРАНА ===")
-----------------------------------------------------------------------
--[[ Раскладку считаем БОЕВОЙ функцией, выдернутой из модуля. ]]
local A
do
    --[[ Берём и блок раскладки, и функцию камеры: они объявлены в
         разных местах файла (камера — уже после local charPanel), а
         проверять надо обе боевыми, а не переписанными в стенде. ]]
    local block = invSrc:match("(INV%.Anim = INV%.Anim or {}.-\nend)\n\nlocal charPanel")
    ok(block ~= nil, "блок раскладки найден в модуле")
    local camBlock = invSrc:match("(function A%.CameraFor.-\nend)")
    ok(camBlock ~= nil, "функция камеры найдена в модуле")
    local env = { INV = {}, math = math, ScrW = ScrW, ScrH = ScrH, Vector = Vector }
    local chunk = assert(loadstring(block .. "\nlocal A = INV.Anim\n" .. camBlock .. "\nreturn INV.Anim"))
    setfenv(chunk, env)
    A = chunk()
end
ok(A and A.Layout, "функция раскладки доступна")

do
    ok(invSrc:find("A.LeftW = 330", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткая ширина 330 убрана")
    ok(invSrc:find("A.Height = 620", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткая высота 620 убрана")

    local bad = {}
    for _, res in ipairs({ { 1280, 720 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 } }) do
        local sw, sh = res[1], res[2]
        local lw, rw, h, x0, y = A.Layout(sw, sh)
        -- Окно должно занимать почти весь экран и не вылезать за него.
        if x0 < 0 or y < 0 then bad[#bad + 1] = sw .. ": за экран" end
        if x0 + lw + A.Gap + rw > sw then bad[#bad + 1] = sw .. ": шире экрана" end
        if y + h > sh then bad[#bad + 1] = sw .. ": выше экрана" end
        -- Не меньше прежнего размера.
        if lw + A.Gap + rw <= 1036 then bad[#bad + 1] = sw .. ": не больше старого" end
        if h <= 620 then bad[#bad + 1] = sw .. ": высота не выросла" end
        -- Симметричные поля.
        if math.abs((sw - (x0 + lw + A.Gap + rw)) - x0) > 1 then
            bad[#bad + 1] = sw .. ": поля не симметричны"
        end
    end
    ok(#bad == 0, "на 1280…3840 окно занимает экран и не вылезает", bad[1])
end

do
    local lw, rw = A.Layout(1920, 1080)
    ok(rw > lw * 2, "предметам отдано больше места, чем карточке персонажа",
        lw .. " / " .. rw)
    local lw2 = A.Layout(3840, 2160)
    ok(lw2 <= A.MaxLeft, "на 4K колонка персонажа не разрастается", lw2)
    local lw3 = A.Layout(1280, 720)
    ok(lw3 >= A.MinLeft, "на малом экране колонка не схлопывается", lw3)
end

-----------------------------------------------------------------------
print("\n=== 4. ИНВЕНТАРЬ: МОДЕЛЬ ВЛЕЗАЕТ В ПАНЕЛЬ ===")
-----------------------------------------------------------------------
do
    ok(A.CameraFor ~= nil, "камера считается функцией, а не жёсткими числами")
    ok(invSrc:find("mdl:SetCamPos(Vector(58, 0, 40))", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткая позиция камеры убрана")
    ok(invSrc:find("ent:GetRenderBounds()", 1, true) ~= nil,
        "габариты берутся у самой модели")

    --[[ Проверяем кадрирование геометрией: половина роста должна
         укладываться в вертикальный угол обзора на найденной
         дистанции. Если не укладывается — фигуру обрежет. ]]
    local FOV = 36
    local bad = {}
    for _, hgt in ipairs({ 60, 72, 84, 96 }) do
        local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, hgt)
        local camPos, lookAt = A.CameraFor(mins, maxs, 330, 400, FOV)
        local dist = camPos.x
        local visibleHalf = math.tan(math.rad(FOV) * 0.5) * dist
        if visibleHalf < hgt * 0.5 then
            bad[#bad + 1] = "рост " .. hgt .. " не влезает"
        end
        -- Взгляд ровно в середину роста.
        if not near(lookAt.z, hgt * 0.5, 0.01) then
            bad[#bad + 1] = "рост " .. hgt .. ": смотрим не в центр"
        end
        -- Чем выше модель, тем дальше камера.
        if dist <= 0 then bad[#bad + 1] = "рост " .. hgt .. ": дистанция <= 0" end
    end
    ok(#bad == 0, "модель любого роста помещается в кадр целиком", bad[1])

    local c1 = A.CameraFor(Vector(-16, -16, 0), Vector(16, 16, 60), 330, 400, 36)
    local c2 = A.CameraFor(Vector(-16, -16, 0), Vector(16, 16, 96), 330, 400, 36)
    ok(c2.x > c1.x, "для высокой модели камера отходит дальше",
        c1.x .. " → " .. c2.x)

    -- Широкая модель (плечи) не должна упираться в бока узкой панели.
    local wide = A.CameraFor(Vector(-40, -40, 0), Vector(40, 40, 72), 300, 500, 36)
    local narrow = A.CameraFor(Vector(-10, -10, 0), Vector(10, 10, 72), 300, 500, 36)
    ok(wide.x >= narrow.x, "для широкой модели камера не ближе", wide.x .. "/" .. narrow.x)

    ok(A.CameraFor(nil, nil, 330, 400, 36) ~= nil, "нет габаритов — не падаем")
end

-----------------------------------------------------------------------
print("\n=== 5. ИНВЕНТАРЬ: КНОПКИ И ПКМ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ БАГА: кнопки стояли на y=132 в панели
         высотой 90 — то есть ниже её дна. ]]
    ok(invSrc:find("use:SetPos(14, 132)", 1, true) == nil,
        "ИСПРАВЛЕНО: кнопка «Использовать» больше не на жёстком y=132")
    ok(invSrc:find("detailPanel:SetSize(330, 90)", 1, true) == nil,
        "ИСПРАВЛЕНО: панель деталей больше не высотой 90")
    ok(invSrc:find("local firstY = ph - 14 - rows * bh", 1, true) ~= nil,
        "кнопки прижаты к низу панели и не могут уехать за её край")
    ok(invSrc:find("local DETAIL_H = 214", 1, true) ~= nil,
        "у панели деталей есть высота под кнопки")

    -- Высоты хватает на две строки кнопок.
    local ph, bh = 214, 32
    local firstY2 = ph - 14 - 2 * bh - 8
    ok(firstY2 > 120, "две строки кнопок помещаются ниже описания", firstY2)
    ok(firstY2 + 2 * bh + 8 <= ph, "и не вылезают за дно панели")

    -- ПКМ теперь показывает меню.
    local rc = invSrc:match("slotBtn%.DoRightClick = function%(%).-\n    end")
    ok(rc ~= nil, "обработчик ПКМ найден")
    ok(rc and rc:find("DermaMenu()", 1, true) ~= nil,
        "ИСПРАВЛЕНО: ПКМ открывает меню, а не молча использует предмет")
    ok(rc and rc:find("Использовать", 1, true) ~= nil, "в меню есть «Использовать»")
    ok(rc and rc:find("Выбросить 1", 1, true) ~= nil, "и «Выбросить»")
    ok(rc and rc:find("Разделить стак", 1, true) ~= nil, "и разделение стака")
    ok(rc and rc:find("Надеть", 1, true) ~= nil, "аксессуар можно надеть из меню")

    -- Подсказки должны описывать новое поведение.
    ok(invSrc:find("ПКМ — меню действий", 1, true) ~= nil,
        "подсказка в шапке обновлена")
end

-----------------------------------------------------------------------
print("\n=== 6. ИНВЕНТАРЬ: СЕТКА ТЯНЕТСЯ ПО ПАНЕЛИ ===")
-----------------------------------------------------------------------
do
    --[[ Ищем именно ПРИСВАИВАНИЕ, а не упоминание. Первая версия
         проверки краснела на этой же строке в поясняющем комментарии
         («Было жёстко: 6 колонок по 74 точки») — то есть ловила текст,
         а не код. ]]
    local grid = invSrc:match("local function rebuildSlots%(%).-\nend")
    ok(grid ~= nil, "функция построения сетки найдена")
    ok(grid and grid:find("local columns, size, gap = 6, 74, 8", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткие 6 колонок по 74 убраны")
    ok(invSrc:find("slotsPanel:GetWide()", 1, true) ~= nil,
        "число колонок считается от ширины панели")

    -- Тот же расчёт, что в модуле: ячейки должны заполнять ширину.
    local gap = 8
    local bad = {}
    for _, avail in ipairs({ 400, 600, 900, 1400, 2000 }) do
        local columns = math.max(4, math.floor((avail + gap) / (84 + gap)))
        columns = math.min(columns, 24)
        local size = math.Clamp(math.floor((avail - gap * (columns - 1)) / columns), 68, 108)
        local used = columns * size + (columns - 1) * gap
        if used > avail then bad[#bad + 1] = avail .. ": вылезает" end
        if columns < 4 then bad[#bad + 1] = avail .. ": мало колонок" end
    end
    ok(#bad == 0, "сетка не вылезает за панель на любой ширине", bad[1])
end

-----------------------------------------------------------------------
print("\n=== 7. КОЛЕСО АНИМАЦИЙ: МОДЕЛЬ ===")
-----------------------------------------------------------------------
do
    ok(animSrc:find("cam.Start3D(Vector(62, 0, 34), Angle(4, 180, 0)", 1, true) == nil,
        "ИСПРАВЛЕНО: жёсткая камера колеса убрана")
    ok(animSrc:find("function R.CameraFor", 1, true) ~= nil,
        "камера считается от габаритов модели")
    ok(animSrc:find("ent:GetRenderBounds()", 1, true) ~= nil,
        "габариты берутся у модели")

    --[[ Чёрный силуэт: ResetModelLighting задаёт только рассеянный
         свет, направленные источники надо ставить отдельно. ]]
    ok(animSrc:find("render.SetModelLighting(BOX_TOP", 1, true) ~= nil,
        "ИСПРАВЛЕНО: выставлен направленный свет — модель не чёрная")
    ok(animSrc:find("render.SetModelLighting(BOX_FRONT", 1, true) ~= nil,
        "свет спереди тоже есть")

    -- Квадрат вывода центрирован.
    ok(animSrc:find("cy - size * 0.62", 1, true) == nil,
        "ИСПРАВЛЕНО: кадр больше не смещён вверх")
    ok(animSrc:find("local px, py = math.floor(cx - size * 0.5), math.floor(cy - size * 0.5)", 1, true) ~= nil,
        "кадр по центру круга")
end

do
    -- Кадрирование колеса той же геометрической проверкой.
    local block = animSrc:match("(function R%.CameraFor.-\nend)")
    ok(block ~= nil, "функция камеры колеса найдена")
    local env = { math = math, Vector = Vector }
    local chunk = assert(loadstring("local R = {}\n" .. block .. "\nreturn R.CameraFor"))
    setfenv(chunk, env)
    local CameraFor = chunk()

    local FOV = 40
    local bad = {}
    for _, hgt in ipairs({ 60, 72, 84, 96 }) do
        local camPos, lookAt = CameraFor(Vector(-16, -16, 0), Vector(16, 16, hgt), FOV)
        local visibleHalf = math.tan(math.rad(FOV) * 0.5) * camPos.x
        if visibleHalf < hgt * 0.5 then bad[#bad + 1] = "рост " .. hgt end
        if not near(lookAt.z, hgt * 0.5, 0.01) then bad[#bad + 1] = "центр " .. hgt end
    end
    ok(#bad == 0, "в колесе модель любого роста влезает целиком", bad[1])
end

-----------------------------------------------------------------------
print("\n=== 8. КОЛЕСО: ПОДСВЕТКА НЕ НАКРЫВАЕТ МОДЕЛЬ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ БАГА: сектор заливался от центра, а при одном
         пункте занимал все 360° — круг становился синим пятном. ]]
    local sec = animSrc:match("if R%.sel and count > 0 then.-\n        end")
    ok(sec ~= nil, "блок подсветки сектора найден")
    --[[ Ищем добавление ТОЧКИ ЦЕНТРА в многоугольник, не привязываясь
         к имени переменной: при откате фикса имя может быть любым, а
         баг — тот же (заливка от центра поверх модели). ]]
    ok(sec and sec:match("%[#%w+ %+ 1%] = { x = cx, y = cy }") == nil,
        "ИСПРАВЛЕНО: заливка от центра убрана — модель не перекрыта")
    ok(sec and sec:find("R.InnerR", 1, true) ~= nil,
        "сектор стал кольцевым: от внутреннего радиуса к внешнему")
    ok(sec and sec:find("math.min(360 / count, 120)", 1, true) ~= nil,
        "угол ограничен — один пункт не красит весь круг")

    -- Проверяем ограничение угла на разном числе пунктов.
    local bad = {}
    for _, n in ipairs({ 1, 2, 3, 6, 12 }) do
        local step = math.min(360 / n, 120)
        if step > 120.001 then bad[#bad + 1] = n end
        if n == 1 and step >= 360 then bad[#bad + 1] = "один пункт красит круг" end
    end
    ok(#bad == 0, "сектор никогда не занимает весь круг", bad[1])
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
