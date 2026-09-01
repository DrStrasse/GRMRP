--[[--------------------------------------------------------------------
    GRM Gizmo — общий гизмо перемещения и вращения.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Мне не нравится как сделан отвратительно
    Гизмо ни в социальных анимациях ни в аксессуарных настройках — нету
    выделения линий гизмо, непонятно какая линия взята + криво
    определяет где хватать какой гизмо. Беру один, он вращает другой,
    подсветки никакой. Шары какие-то, надо нормальные гизмо сделать».

    ЧТО БЫЛО НЕ ТАК (два одинаковых куска кода в двух файлах).

    1) НЕТ ПОДСВЕТКИ. Оси рисовались одним и тем же цветом всегда.
       Понять, что схватится под курсором, можно было только методом
       тыка.

    2) «БЕРУ ОДИН — ВРАЩАЕТ ДРУГОЙ». Три причины сразу:

       а) перебор осей шёл через pairs() по таблице со строковыми
          ключами. Порядок обхода в Lua при этом НЕ ОПРЕДЕЛЁН и может
          меняться. При равном расстоянии до курсора выигрывала та ось,
          которая попалась первой, — то есть случайная. Один и тот же
          клик в одном и том же месте мог дать разные оси;

       б) кольца вращения проверялись ЦЕЛИКОМ, вместе с дальней
          половиной. Кольцо, повёрнутое к камере ребром, вырождается в
          отрезок, и его ДАЛЬНЯЯ сторона часто оказывалась к курсору
          ближе, чем ближняя сторона нужного кольца. Курсор на видимой
          дуге — схватилась ось, которая в этом месте проходит с
          обратной стороны;

       в) при близких расстояниях не учитывалась глубина: побеждала
          численно меньшая дистанция в пикселях, хотя визуально сверху
          лежит другая ось.

    3) ШАРЫ ВМЕСТО СТРЕЛОК. Наконечники рисовались
       render.DrawWireframeSphere — проволочные шарики.

    ЧТО СТАЛО. Один модуль на оба редактора: детерминированный порядок
    осей, отбор только видимой половины кольца, тай-брейк по глубине,
    толстые лучи со стрелками и подсветка того, что схватится.

    Проекция передаётся параметром: так стенд гоняет ТУ ЖЕ функцию
    выбора оси без запуска игры.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Gizmo = GRM.Gizmo or {}
local G = GRM.Gizmo
G.Version = "1.0.0"

--[[ ДЕТЕРМИНИРОВАННЫЙ ПОРЯДОК. Массив, а не pairs() по таблице: при
     равном расстоянии до курсора выбор обязан быть одним и тем же
     всегда, иначе клик в одну и ту же точку даёт разные оси. ]]
G.Axes = {
    { id = "x", color = Color(235, 78, 72), name = "X",
      vec = function(a) return a:Forward() end },
    { id = "y", color = Color(86, 214, 116), name = "Y",
      vec = function(a) return a:Right() end },
    { id = "z", color = Color(84, 150, 255), name = "Z",
      vec = function(a) return a:Up() end },
}

G.PickRadiusMove = 16      -- допуск попадания по лучу, пиксели
G.PickRadiusRing = 13      -- по кольцу
G.RingSegments = 56

function G.AxisData(id)
    for i = 1, #G.Axes do
        if G.Axes[i].id == id then return G.Axes[i] end
    end
end

--[[ КАКОЕ ПОЛЕ УГЛА КРУТИТ ЭТА ОСЬ (баг найден 31.08 владельцем:
     «выбираю гизмо Z — вращение Z, но он почему-то вращает по X,
     а X вращает по Y»).

     В GMod угол это Angle(pitch, yaw, roll), и каждое поле вращает
     вокруг СВОЕЙ оси:

         roll  (r)   — вокруг Forward, то есть вокруг X
         pitch (p)   — вокруг Right,   то есть вокруг Y
         yaw   (y)   — вокруг Up,      то есть вокруг Z

     А оба редактора связывали их «по алфавиту»: x→pitch, y→yaw,
     z→roll. Соответствие оказалось сдвинуто на одну позицию, и
     получалось ровно то, что описал владелец: берёшь Z — крутится
     roll, то есть вокруг X; берёшь X — крутится pitch, вокруг Y.

     Держим соответствие ЗДЕСЬ, одной таблицей на оба редактора:
     дважды повторённое правило — это дважды повторённая ошибка. ]]
G.AngleKeyOf = { x = "r", y = "p", z = "yaw" }

--[[ Имя поля для конкретного хранилища. Студия анимаций хранит углы
     как {p=, yaw=, r=}, редактор аксессуаров — как {p=, y=, r=}.
     Отличается только имя yaw, поэтому параметром отдаём его вариант. ]]
function G.AngleKey(axis, yawName)
    local k = G.AngleKeyOf[axis]
    if k == "yaw" then return yawName or "yaw" end
    return k
end

-- Плоскость кольца вращения вокруг оси: два перпендикулярных ей вектора.
function G.RingBasis(axis, ang)
    if axis == "x" then return ang:Right(), ang:Up() end
    if axis == "y" then return ang:Forward(), ang:Up() end
    return ang:Forward(), ang:Right()
end

function G.RingPoint(origin, ang, axis, radians, radius)
    local a, b = G.RingBasis(axis, ang)
    return origin + a * math.cos(radians) * radius + b * math.sin(radians) * radius
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

--[[ Расстояние от точки до отрезка в экранных координатах и параметр
     ближайшей точки. Общая мелочь для лучей и для дуг колец. ]]
local function segDist(mx, my, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    if len2 < 0.0001 then
        return math.sqrt(dist2(mx, my, x1, y1)), 0, 0, 0
    end
    local t = math.Clamp(((mx - x1) * dx + (my - y1) * dy) / len2, 0, 1)
    local px, py = x1 + dx * t, y1 + dy * t
    local len = math.sqrt(len2)
    return math.sqrt(dist2(mx, my, px, py)), t, dx / len, dy / len
end

--[[ ВЫБОР ПОБЕДИТЕЛЯ. Вынесено отдельно и сделано чистым: именно здесь
     раньше побеждала случайная ось.

     Правила по порядку:
       1. кандидат должен попасть в допуск;
       2. если один заметно ближе к курсору (более чем на TIE пикселей)
          — берём его;
       3. при близких расстояниях берём тот, что БЛИЖЕ К КАМЕРЕ: именно
          он нарисован сверху, в него игрок и целится;
       4. при полном равенстве — порядок из G.Axes, всегда одинаковый. ]]
G.TiePixels = 4

function G.Best(candidates)
    local best
    for i = 1, #candidates do
        local c = candidates[i]
        if not best then
            best = c
        else
            local closer = best.dist - c.dist
            if closer > G.TiePixels then
                best = c
            elseif math.abs(closer) <= G.TiePixels and c.depth < best.depth then
                -- Одинаково близко к курсору — выигрывает ближняя к камере.
                best = c
            end
        end
    end
    return best
end

--[[ Кандидаты для режима ПЕРЕМЕЩЕНИЯ: три луча из центра.

     project — функция мира→экран, возвращает {x=, y=, visible=} и
     глубину. Передаётся снаружи, чтобы стенд мог подставить свою. ]]
function G.CollectMove(origin, ang, len, mx, my, project, eyePos)
    local out = {}
    local o = project(origin)
    if not o or o.visible == false then return out end
    for i = 1, #G.Axes do
        local ax = G.Axes[i]
        local tip = origin + ax.vec(ang) * len
        local e = project(tip)
        if e and e.visible ~= false then
            local d, t, dx, dy = segDist(mx, my, o.x, o.y, e.x, e.y)
            if d <= G.PickRadiusMove then
                -- Глубина ближайшей точки луча: середина между концами
                -- по параметру t, этого достаточно для сравнения осей.
                local mid = origin + ax.vec(ang) * (len * t)
                out[#out + 1] = {
                    axis = ax.id, dist = d, dx = dx, dy = dy,
                    depth = eyePos and eyePos:Distance(mid) or 0,
                    order = i,
                }
            end
        end
    end
    return out
end

--[[ Кандидаты для ВРАЩЕНИЯ: три кольца.

     Ключевое отличие от старого кода — берём только ВИДИМУЮ половину
     кольца. Точка считается видимой, если она на ближней к камере
     стороне: (pt - origin) смотрит в сторону камеры. Без этого дальняя
     дуга перехватывала клики у соседней оси. ]]
function G.CollectRotate(origin, ang, radius, mx, my, project, eyePos)
    local out = {}
    local segs = G.RingSegments
    for i = 1, #G.Axes do
        local ax = G.Axes[i]
        local bestD, bestDX, bestDY, bestDepth
        local prev, prevVisible
        for s = 0, segs do
            local rad = math.pi * 2 * s / segs
            local pt = G.RingPoint(origin, ang, ax.id, rad, radius)
            local visible = true
            if eyePos then
                -- Ближняя половина: вектор из центра к точке направлен
                -- в сторону камеры.
                visible = (pt - origin):Dot(eyePos - origin) > 0
            end
            local sp = project(pt)
            if sp and sp.visible == false then sp = nil end
            if prev and sp and prevVisible and visible then
                local d, _, dx, dy = segDist(mx, my, prev.x, prev.y, sp.x, sp.y)
                if d <= G.PickRadiusRing and (not bestD or d < bestD) then
                    bestD, bestDX, bestDY = d, dx, dy
                    bestDepth = eyePos and eyePos:Distance(pt) or 0
                end
            end
            prev, prevVisible = sp, visible
        end
        if bestD then
            out[#out + 1] = {
                axis = ax.id, dist = bestD, dx = bestDX, dy = bestDY,
                depth = bestDepth or 0, order = i,
            }
        end
    end
    return out
end

--[[ Общий вход: что схватится под курсором.
     Возвращает id оси и экранное направление её перетаскивания. ]]
function G.Pick(mode, origin, ang, size, mx, my, project, eyePos)
    project = project or function(v)
        local s = v:ToScreen()
        return s
    end
    if eyePos == nil then eyePos = EyePos() end
    local list
    if mode == "rotate" then
        list = G.CollectRotate(origin, ang, size, mx, my, project, eyePos)
    else
        list = G.CollectMove(origin, ang, size, mx, my, project, eyePos)
    end
    local best = G.Best(list)
    if not best then return nil end
    return best.axis, best.dx, best.dy
end

-----------------------------------------------------------------------
-- ОТРИСОВКА
-----------------------------------------------------------------------
local function brighten(c, k)
    return Color(math.min(255, c.r + k), math.min(255, c.g + k), math.min(255, c.b + k), c.a or 255)
end

local function dim(c, a)
    return Color(c.r, c.g, c.b, a)
end

--[[ Толстый луч со стрелкой вместо линии с шариком.

     render.DrawBeam рисует ленту постоянной ширины, всегда повёрнутую
     к камере, — это и даёт «толстую» ось, в которую удобно целиться.
     Наконечник — второй, широкий и короткий отрезок у самого конца:
     визуально читается как стрелка и стоит дёшево. ]]
local function drawArrow(origin, dir, len, col, width, headScale)
    local tip = origin + dir * len
    local neck = origin + dir * (len - len * 0.24)
    render.DrawBeam(origin, neck, width, 0, 1, col)
    render.DrawBeam(neck, tip, width * (headScale or 3.4), 0, 1, col)
end

--[[ Рисование гизмо. hoverAxis — что под курсором, activeAxis — что
     сейчас тянут. Подсветка: активная ось ярче и толще, остальные
     приглушены, чтобы выбранная читалась однозначно. ]]
function G.Draw(mode, origin, ang, size, hoverAxis, activeAxis)
    render.SetColorMaterial()

    --[[ Гизмо всегда поверх геометрии. Аксессуар или кость часто
         внутри модели: без этого оси прятались в теле персонажа и
         схватить их было нечем. ]]
    cam.IgnoreZ(true)

    local focus = activeAxis or hoverAxis

    for i = 1, #G.Axes do
        local ax = G.Axes[i]
        local on = (ax.id == focus)
        --[[ Когда одна ось активна, прочие глушим прозрачностью: у
             владельца была ровно эта жалоба — «непонятно какая линия
             взята». ]]
        local col = ax.color
        if on then
            col = brighten(ax.color, 45)
        elseif focus then
            col = dim(ax.color, 90)
        end

        if mode == "rotate" then
            local segs = G.RingSegments
            local w = on and 2.6 or 1.5
            local prev = G.RingPoint(origin, ang, ax.id, 0, size)
            for s = 1, segs do
                local cur = G.RingPoint(origin, ang, ax.id, math.pi * 2 * s / segs, size)
                render.DrawBeam(prev, cur, w, 0, 1, col)
                prev = cur
            end
        else
            drawArrow(origin, ax.vec(ang), size, col, on and 2.8 or 1.7)
        end
    end

    -- Центр: маленький белый куб-маркер вместо проволочного шара.
    local c = activeAxis and Color(255, 240, 170) or Color(240, 244, 250)
    render.DrawBeam(origin - Vector(0, 0, 0.9), origin + Vector(0, 0, 0.9), 2.4, 0, 1, c)

    cam.IgnoreZ(false)
end

--[[ Подпись оси у курсора. Рисуется в 2D (HUDPaint/Paint панели), а не
     в мире: текст в мире на таком масштабе нечитаем. ]]
function G.DrawLabel(mode, axis, mx, my)
    if not axis then return end
    local ax = G.AxisData(axis)
    if not ax then return end
    local txt = (mode == "rotate" and "вращение " or "сдвиг ") .. ax.name
    surface.SetFont("DermaDefaultBold")
    local tw, th = surface.GetTextSize(txt)
    draw.RoundedBox(4, mx + 16, my + 14, tw + 12, th + 6, Color(12, 16, 24, 235))
    draw.SimpleText(txt, "DermaDefaultBold", mx + 22, my + 17, ax.color)
end

print("[GRM Gizmo] loaded v" .. G.Version)
