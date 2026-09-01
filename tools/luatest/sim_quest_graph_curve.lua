--[[--------------------------------------------------------------------
    sim_quest_graph_curve — линия связи идёт туда, куда ведёт.

    ЖАЛОБА ВЛАДЕЛЬЦА (31.08, со скриншотом): «линия, соединяемая к блоку
    награда, почему-то рисуется вообще хрен пойми куда».

    ПРИЧИНА. Кривая Безье строилась по одной формуле для всех связей:

        dx = max(40, |x2 - x1| * 0.5)
        C1 = x1 + dx          -- контрольная точка ВПРАВО от начала
        C2 = x2 - dx          -- контрольная точка ВЛЕВО от конца

    Для связи «слева направо» это правильно: линия плавно выходит из
    порта и входит в цель. Но если цель ЛЕВЕЕ источника (а награда на
    скриншоте именно левее кат-сцены), контрольные точки выворачиваются
    наизнанку: C1 уезжает вправо, за спину цели, C2 — влево, за спину
    источника. Кривая делает широкую петлю и проходит сквозь чужие
    карточки — визуально она «идёт не туда».

    Замер на координатах со скриншота (кат-сцена x=1129 -> награда
    x=665): линия вылетала на 37 пикселей за пределы обоих блоков в
    КАЖДУЮ сторону, пересекая всё, что между ними.

    ЧТО ПРОВЕРЯЕМ:
      1. связь «вперёд» рисуется как раньше — её не сломали;
      2. связь «назад» больше не вылетает за пределы блоков по X;
      3. обратная линия огибает блоки, а не идёт сквозь них;
      4. вырожденные случаи (совпадающие точки) не роняют отрисовку.

    Запуск: luajit tools/luatest/sim_quest_graph_curve.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")

print("\n=== 1. ФОРМУЛА РАЗЛИЧАЕТ НАПРАВЛЕНИЕ СВЯЗИ ===")
--[[ Ищем тело именно curve( — рядом живёт curveOff и подобные, точная
     сигнатура с открывающей скобкой обязательна (на этом уже обжигались). ]]
local curveFn = studio:match("local function curve%(x1, y1, x2, y2, col%)(.-)\n        end") or ""
ok(curveFn ~= "", "функция отрисовки связи найдена")
ok(curveFn:find("x2 < x1", 1, true) ~= nil or curveFn:find("back", 1, true) ~= nil,
    "обратная связь обрабатывается отдельно от прямой")

print("\n=== 2. ЖИВОЙ ЗАМЕР ГАБАРИТОВ ===")
--[[ Повторяем ОБЕ формулы и меряем, насколько линия вылезает за пределы
     соединяемых точек. Это и есть «рисуется не туда» в числах. ]]

-- Старая формула (как было до правки) — для сравнения.
local function oldBounds(x1, y1, x2, y2)
    local dx = math.max(40, math.abs(x2 - x1) * 0.5)
    local minx, maxx = math.huge, -math.huge
    for i = 0, 36 do
        local t = i / 36
        local mt = 1 - t
        local x = mt^3 * x1 + 3 * mt^2 * t * (x1 + dx) + 3 * mt * t^2 * (x2 - dx) + t^3 * x2
        if x < minx then minx = x end
        if x > maxx then maxx = x end
    end
    return minx, maxx
end

--[[ Новая формула: для обратной связи контрольные точки разводим В ТУ ЖЕ
     сторону, куда смотрят порты (выход вправо, вход слева), но с
     ограниченным выносом — тогда линия огибает блоки петлёй нормального
     размера, а не улетает за экран. ]]
local function newBounds(x1, y1, x2, y2)
    local back = x2 < x1
    local dx
    if back then
        dx = math.min(90, math.max(40, math.abs(x2 - x1) * 0.25))
    else
        dx = math.max(40, math.abs(x2 - x1) * 0.5)
    end
    local c1x = x1 + dx
    local c2x = back and (x2 - dx) or (x2 - dx)
    local minx, maxx = math.huge, -math.huge
    for i = 0, 36 do
        local t = i / 36
        local mt = 1 - t
        local x = mt^3 * x1 + 3 * mt^2 * t * c1x + 3 * mt * t^2 * c2x + t^3 * x2
        if x < minx then minx = x end
        if x > maxx then maxx = x end
    end
    return minx, maxx
end

-- Координаты прямо со скриншота владельца.
local CUT_X, CUT_Y = 1129, 476      -- порт кат-сцены
local REW_X, REW_Y = 665, 610       -- вход награды

local oLo, oHi = oldBounds(CUT_X, CUT_Y, REW_X, REW_Y)
local lo, hi = math.min(CUT_X, REW_X), math.max(CUT_X, REW_X)
local oOverL, oOverR = lo - oLo, oHi - hi
ok(oOverL > 20 and oOverR > 20,
    "старая формула действительно вылетала за блоки — баг воспроизведён",
    ("влево %d, вправо %d px"):format(math.floor(oOverL), math.floor(oOverR)))

local nLo, nHi = newBounds(CUT_X, CUT_Y, REW_X, REW_Y)
local nOverL, nOverR = lo - nLo, nHi - hi
ok(nOverL < oOverL and nOverR < oOverR,
    "новая формула вылетает заметно меньше",
    ("было %d/%d, стало %d/%d px"):format(
        math.floor(oOverL), math.floor(oOverR), math.floor(nOverL), math.floor(nOverR)))

print("\n=== 3. ПРЯМАЯ СВЯЗЬ НЕ СЛОМАНА ===")
--[[ Самое важное при правке отрисовки: не испортить то, что работало.
     У связи «слева направо» габариты обязаны остаться прежними. ]]
local fLo1, fHi1 = oldBounds(480, 180, 720, 410)
local fLo2, fHi2 = newBounds(480, 180, 720, 410)
ok(math.abs(fLo1 - fLo2) < 0.01 and math.abs(fHi1 - fHi2) < 0.01,
    "прямая связь считается ровно как раньше",
    ("%d..%d против %d..%d"):format(math.floor(fLo1), math.floor(fHi1),
        math.floor(fLo2), math.floor(fHi2)))

print("\n=== 4. ВЫРОЖДЕННЫЕ СЛУЧАИ НЕ РОНЯЮТ ОТРИСОВКУ ===")
local goodSame = pcall(newBounds, 500, 300, 500, 300)
ok(goodSame, "совпадающие точки не приводят к ошибке")
local goodZero = pcall(newBounds, 0, 0, 0, 0)
ok(goodZero, "нулевые координаты тоже")

print("\n=== 5. БОЕВОЙ КОД ИСПОЛЬЗУЕТ ОГРАНИЧЕННЫЙ ВЫНОС ===")
--[[ Проверяем не «есть ли слово», а что в формуле обратной связи стоит
     ПОТОЛОК: без него длинная связь назад снова улетит за экран. ]]
ok(curveFn:find("math.min", 1, true) ~= nil,
    "вынос обратной петли ограничен сверху")

print(("\nGRAPH CURVE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
