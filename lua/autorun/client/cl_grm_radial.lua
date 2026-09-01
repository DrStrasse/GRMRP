--[[--------------------------------------------------------------------
    GRM Radial — общая отрисовка радиальных меню.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Дизайн во всех модулях и во всех радиальных
    меню поправь, сами рисованные кольца и круги исправь в плане
    дизайна».

    ЧТО БЫЛО НЕ ТАК. Три радиальных меню (биндер, соц.анимации,
    взаимодействие) рисовались независимо и выглядели по-разному:

      * соц.анимации и взаимодействие заливали СПЛОШНОЙ круг и поверх
        него писали текст. Секторы визуально не разделялись — куда
        ведёт мышь, понятно только по подсветке;
      * подсветка была плоской заливкой без границ: сектор «растекался»
        и не читался как кнопка;
      * биндер рисовал аккуратные секторы с зазорами — то есть один
        модуль выглядел заметно лучше двух других;
      * круги собирались из 12–20 отрезков и на большом радиусе были
        видимо гранёными.

    ЧТО ЗДЕСЬ. Один набор примитивов на все меню: кольцевой сектор с
    зазором, ровная окружность, центральная площадка. Дизайн правится в
    одном месте и меняется сразу везде.

    ЧИТАЕМОСТЬ. Владелец отдельно просил не давать тёмный текст на
    тёмном фоне. Поэтому здесь только светлые цвета текста, а надписи
    поверх мира идут с обводкой.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Radial = GRM.Radial or {}
local RD = GRM.Radial
RD.Version = "1.0.0"

--[[ ОБЩАЯ ПАЛИТРА радиальных меню. Совпадает с остальными окнами GRM:
     тёмная подложка, светлый текст, синий акцент, золотой заголовок. ]]
RD.Col = {
    dim     = Color(9, 12, 18, 208),    -- затемнение под кольцом
    sector  = Color(34, 42, 56, 236),   -- обычный сектор
    hover   = Color(56, 122, 208, 242), -- сектор под курсором
    active  = Color(46, 132, 92, 242),  -- уже включённый пункт
    off     = Color(38, 40, 48, 214),   -- недоступный пункт
    edge    = Color(120, 178, 255, 190),-- кромка выбранного
    hub     = Color(14, 18, 26, 246),   -- центральная площадка
    hubEdge = Color(52, 64, 84, 220),
    text    = Color(236, 242, 250),
    dimText = Color(156, 170, 188),
    gold    = Color(245, 195, 65),
    good    = Color(104, 214, 138),
    bad     = Color(226, 96, 92),
    shadow  = Color(0, 0, 0, 228),
}

--[[ Сегментов на круг. 96 вместо прежних 12–20: на радиусе 230 грани
     были видны невооружённым глазом, круг выглядел многоугольником. ]]
RD.Segments = 96

--[[ Ровный круг. Отдельной функцией, чтобы все меню рисовали окружности
     одинаково гладкими. ]]
function RD.Circle(cx, cy, radius, col, segments)
    segments = segments or RD.Segments
    local poly = {}
    for i = 0, segments do
        local a = math.rad(i / segments * 360)
        poly[#poly + 1] = { x = cx + math.cos(a) * radius, y = cy + math.sin(a) * radius }
    end
    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
    surface.DrawPoly(poly)
end

--[[ КОЛЬЦЕВОЙ СЕКТОР — основа нового вида.

     fromDeg/spanDeg — угол начала и ширина в градусах, r0/r1 —
     внутренний и внешний радиус. gapDeg — зазор между соседями.

     Зазор принципиален: без него секторы сливаются в сплошное кольцо и
     не читаются как отдельные кнопки. Именно этого не хватало меню
     анимаций и взаимодействия.

     Центр (r0) не закрашиваем: там живёт модель персонажа или название
     объекта, и заливка от центра их перекрывала — на это владелец
     жаловался отдельно. ]]
function RD.Sector(cx, cy, fromDeg, spanDeg, r0, r1, col, gapDeg)
    gapDeg = gapDeg or 1.6
    -- У узких секторов зазор не должен съесть сам сектор.
    if spanDeg <= gapDeg * 2 + 1 then gapDeg = math.max(0, spanDeg * 0.12) end

    local a0 = math.rad(fromDeg + gapDeg)
    local a1 = math.rad(fromDeg + spanDeg - gapDeg)
    -- Плотность точек по длине дуги: короткой хватит меньше.
    local steps = math.max(6, math.ceil((spanDeg / 360) * RD.Segments))

    local poly = {}
    for i = 0, steps do
        local a = a0 + (a1 - a0) * (i / steps)
        poly[#poly + 1] = { x = cx + math.cos(a) * r1, y = cy + math.sin(a) * r1 }
    end
    for i = steps, 0, -1 do
        local a = a0 + (a1 - a0) * (i / steps)
        poly[#poly + 1] = { x = cx + math.cos(a) * r0, y = cy + math.sin(a) * r0 }
    end

    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
    surface.DrawPoly(poly)
    return a0, a1, steps
end

--[[ Светящаяся кромка по внешнему краю сектора: показывает, что именно
     схватится. Тонкая полоса, а не заливка — иначе перебивает подпись. ]]
function RD.SectorEdge(cx, cy, fromDeg, spanDeg, r1, col, gapDeg, thickness)
    gapDeg = gapDeg or 1.6
    thickness = thickness or 3
    if spanDeg <= gapDeg * 2 + 1 then gapDeg = math.max(0, spanDeg * 0.12) end

    local a0 = math.rad(fromDeg + gapDeg)
    local a1 = math.rad(fromDeg + spanDeg - gapDeg)
    local steps = math.max(6, math.ceil((spanDeg / 360) * RD.Segments))

    local poly = {}
    for i = 0, steps do
        local a = a0 + (a1 - a0) * (i / steps)
        poly[#poly + 1] = { x = cx + math.cos(a) * (r1 + thickness), y = cy + math.sin(a) * (r1 + thickness) }
    end
    for i = steps, 0, -1 do
        local a = a0 + (a1 - a0) * (i / steps)
        poly[#poly + 1] = { x = cx + math.cos(a) * r1, y = cy + math.sin(a) * r1 }
    end

    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
    surface.DrawPoly(poly)
end

--[[ Затемнение под меню — КОЛЬЦОМ, а не сплошным кругом.

     Сплошная заливка гасила центр, где стоит модель персонажа. Теперь
     тень лежит только под секторами. ]]
function RD.Backdrop(cx, cy, r0, r1, col)
    RD.Sector(cx, cy, 0, 360, r0, r1, col or RD.Col.dim, 0)
end

--[[ Центральная площадка: подложка под название и состояние. Круг с
     тонкой окантовкой — так центр читается как отдельный элемент, а не
     как дыра в кольце. ]]
function RD.Hub(cx, cy, radius)
    RD.Circle(cx, cy, radius + 2, RD.Col.hubEdge)
    RD.Circle(cx, cy, radius, RD.Col.hub)
end

--[[ Геометрия пункта: где начинается его сектор и где лежит подпись.

     Отсчёт от ВЕРХНЕЙ точки и по часовой стрелке — так же, как считает
     выбор мышью во всех меню. Держим здесь, чтобы раскладка и выбор не
     разошлись: именно на этом рассогласовании ловились гизмо и кольцо
     анимаций. ]]
function RD.SlotAngles(i, count)
    local span = 360 / count
    -- -90: ноль градусов смотрит вверх. -span/2: пункт центрируется
    -- на своём направлении, а не начинается с него.
    return (i - 1) * span - 90 - span * 0.5, span
end

function RD.SlotLabelPos(i, count, cx, cy, radius)
    local from, span = RD.SlotAngles(i, count)
    local a = math.rad(from + span * 0.5)
    return cx + math.cos(a) * radius, cy + math.sin(a) * radius
end

--[[ Выбор пункта по направлению мыши. Единая реализация: раньше каждое
     меню считало угол само, и любая правка одного оставляла остальные
     с прежним поведением. ]]
function RD.Pick(mx, my, cx, cy, count, innerR)
    if count <= 0 then return nil end
    local dx, dy = mx - cx, my - cy
    if math.sqrt(dx * dx + dy * dy) < (innerR or 0) then return nil end
    -- Экранный Y растёт вниз, поэтому -dy: иначе кольцо зеркальное.
    local ang = math.deg(math.atan2(dx, -dy))
    if ang < 0 then ang = ang + 360 end
    local span = 360 / count
    local idx = math.floor((ang + span * 0.5) / span) + 1
    if idx > count then idx = idx - count end
    return idx
end

--[[ Нарисовать кольцо целиком.

     items — список { name, sub, enabled, active, accent }.
     Возвращать ничего не нужно: подсветку вызывающий передаёт в sel. ]]
function RD.Draw(cx, cy, items, sel, innerR, outerR, opts)
    opts = opts or {}
    local count = #items
    if count == 0 then return end
    local labelR = opts.labelR or ((innerR + outerR) * 0.5)

    RD.Backdrop(cx, cy, innerR, outerR)

    for i, it in ipairs(items) do
        local from, span = RD.SlotAngles(i, count)
        local on = (sel == i)

        local col = RD.Col.sector
        if it.enabled == false then col = RD.Col.off
        elseif on then col = RD.Col.hover
        elseif it.active then col = RD.Col.active end

        RD.Sector(cx, cy, from, span, innerR, outerR, col)
        if on then
            RD.SectorEdge(cx, cy, from, span, outerR, RD.Col.edge)
        end

        local lx, ly = RD.SlotLabelPos(i, count, cx, cy, labelR)

        --[[ Текст только светлый. Недоступный пункт приглушаем, но не
             делаем тёмным: на тёмной подложке он стал бы нечитаемым —
             ровно то, на что жаловался владелец. ]]
        local tcol = RD.Col.text
        if it.enabled == false then tcol = Color(150, 144, 148)
        elseif on then tcol = Color(255, 255, 255)
        elseif it.accent == "good" then tcol = RD.Col.good
        elseif it.accent == "bad" then tcol = RD.Col.bad end

        local hasSub = it.sub and it.sub ~= ""
        draw.SimpleTextOutlined(tostring(it.name or ""),
            opts.font or "GRMRadial_Item", lx, hasSub and (ly - 8) or ly, tcol,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, RD.Col.shadow)
        if hasSub then
            draw.SimpleTextOutlined(tostring(it.sub),
                opts.subFont or "GRMRadial_Sub", lx, ly + 10,
                on and RD.Col.text or RD.Col.dimText,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, RD.Col.shadow)
        end
    end

    if opts.hub ~= false then RD.Hub(cx, cy, innerR - 6) end
end

surface.CreateFont("GRMRadial_Item", { font = "Roboto", size = 17, weight = 600, extended = true })
surface.CreateFont("GRMRadial_Sub", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMRadial_Title", { font = "Roboto", size = 20, weight = 700, extended = true })

print("[GRM Radial] loaded v" .. RD.Version)
