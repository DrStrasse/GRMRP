--[[--------------------------------------------------------------------
    GRM Estate & Business v1.0.0 — ядро зон (фаза 2).

    ЗАЧЕМ. Автоматы, колонки и помещения жили тремя несвязанными
    системами. Игрок не мог ответить «чем я владею и сколько это
    приносит», а на карте не было видно ни свободных объектов, ни
    чужого бизнеса.

    ЧТО ЭТО. Надстройка над готовым GRM.Property — оно уже умеет зоны,
    владельцев, аренду и коммуналку, второй раз это не пишем. Объект
    получает ВИД:

        estate   — жильё:   зелёный значок, уменьшен в 2 раза
        business — бизнес:  жёлтый значок,  уменьшен в 1.5 раза

    Значок — вращающийся models/props_phx/facepunch_logo.mdl над центром
    зоны. Видно издалека, ходить и проверять не нужно.

    СКАНИРОВАНИЕ. Зона сама знает, что внутри: автоматы с едой и
    бензоколонки ищутся по координатам, вручную ничего не привязывается.
    Убрали автомат — точка пересчиталась сама. Это снимает главную боль:
    не нужно помнить, что к чему прикручено.

    РЕШЕНИЯ ВЛАДЕЛЬЦА (27.08), заложенные здесь:
      • одиночный автомат или колонка живут без зоны, как раньше;
        две и более точек в одном месте — только через бизнес-зону;
      • лимит бизнесов на игрока: 3 (конвар grm_estate_limit);
      • просрочка коммуналки даёт ПЕНЮ, а не отключение и не изъятие;
      • цену назначает админ вручную.

    Фаза 2 даёт вид объекта, значки и сканирование. Деньги, рынок и
    личный кабинет — следующие фазы.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Estate = GRM.Estate or {}
local ES = GRM.Estate

ES.Version = "1.0.0"

--- Модель значка и его размеры (заказ владельца).
ES.MarkerModel  = "models/props_phx/facepunch_logo.mdl"

--[[ МАТЕРИАЛ ЗНАЧКА (заказ владельца 27.08).

     У facepunch_logo своя текстура, и render.SetColorModulation только
     подкрашивал её — жёлтый выходил грязным, зелёный почти не читался.
     debugwhite это чистый белый без деталей: умножение на цвет даёт
     ровно тот цвет, который задали. ]]
ES.MarkerMaterial = "models/debug/debugwhite"

--[[ РАЗМЕР. Было 1/1.5 и 1/2 — на карте значок перекрывал полдороги.
     Уменьшен ещё примерно втрое; бизнес чуть крупнее жилья, чтобы их
     можно было различить издалека. ]]
ES.MarkerScale  = { business = 0.22, estate = 0.18 }

ES.MarkerColor  = {
    business = Color(245, 200, 60),    -- жёлтый — бизнес
    estate   = Color(80, 205, 110),    -- зелёный — жильё
    sale     = Color(90, 170, 255),    -- синий — продаётся
}

--[[ ВЫСОТА значка над центром зоны.

     История правок по замечаниям владельца: 78 — висел «крышей» выше
     головы; 36 — всё ещё высоко; 22 — ближе, но просил ещё ниже
     («опусти на 10, может даже на 20 юнитов», 28.08).

     Теперь 2: значок почти на уровне центра зоны. Ноль не берём —
     небольшой подъём нужен, чтобы модель не резалась о геометрию пола,
     когда зона обведена вплотную к земле. ]]
ES.MarkerHeight = 2

--[[ ПРИВЯЗКА ЗНАЧКА К ДВЕРИ (заказ владельца 28.08).

     «Красивее будет смотреться, если значок жилья будет крепиться
      к дверям после создания зоны» + «информация, допустим, Квартира №2
      стоимость 85.000 GRM, тоже к двери чтобы крепилось».

     Раньше и значок, и подпись висели в геометрическом ЦЕНТРЕ зоны.
     Зону обводят вокруг всего дома, поэтому центр — это середина
     комнаты или вообще стена: значок торчал в воздухе посреди
     помещения, а подпись читалась только изнутри.

     Теперь якорь — входная дверь объекта.

     ПЕРЕСМОТР ДИЗАЙНА (28.08, по скриншотам владельца: «ну как-то такое
     себе, мб как-то по-другому дизайн сделать?»).

     Первый заход просто перенёс к двери СТАРУЮ вращающуюся эмблему
     facepunch_logo. На скриншотах видно, почему это не сработало:

       • модель объёмная и крупная — в подъезде она врезалась в потолок
         и в стену, «полумесяц» торчал сквозь перекрытие;
       • она вращалась, то есть половину времени была видна с ребра;
       • подпись рисовалась через HUDPaint, то есть СКВОЗЬ стены: над
         дверью висел текст соседней квартиры;
       • вывеской это не выглядело — просто предмет в воздухе.

     Второй заход сделал плоскую ТАБЛИЧКУ в 3D2D, но повесил её на стену
     НАД дверным проёмом.

     ФИНАЛЬНЫЙ ДИЗАЙН (28.08): «лучше чтобы таблички были не над
     дверями, а НА дверях, как это сделано с автоматами с едой».

     Над дверью почти всегда балка, косяк или начало потолка — вывеска
     налезала на них. Теперь плашка лежит прямо НА ПОЛОТНЕ, в
     собственных углах двери, ровно как надпись на торговом автомате
     (VENDING:Draw в cl_grm_vending_gui). Побочные плюсы: табличка едет
     вместе с открывающейся дверью и видна с обеих сторон полотна.

     Объекты без дверей продолжают показывать прежнюю эмблему в центре
     зоны: это запасной вариант, чтобы старые зоны не потерялись. ]]

--[[ Размер плашки в мире.

     Ширину пришлось уменьшить против настенного варианта: дверное
     полотно около 48 юнитов, а прежние 62 торчали бы за его края. 42
     оставляет по краям поля, как у настоящей таблички с номером. ]]
ES.PlaqueWidth  = 42
ES.PlaqueHeight = 18

--[[ Насколько далеко читается табличка. Мелкий текст дальше 900 юнитов
     всё равно не разобрать, а рисовать 3D2D для каждой двери на карте
     дорого. За этим порогом остаётся только цветная точка-огонёк. ]]
ES.PlaqueDistance = 900

--[[ ПОВОРОТ.

     Логотип у facepunch_logo лежит в плоскости модели, поэтому без
     разворота на 90° по Roll он смотрит в небо («словно крыша»).
     Roll держим постоянным — значок стоит вертикально.

     А вот Yaw крутим САМИ, по времени. Промежуточная попытка «поворачивать
     значок лицом к игроку» оказалась хуже исходной: значок замирал и
     дёргался в зависимости от того, с какой стороны подходит человек
     (владелец 28.08: «вращение испоганено, он вращается туда куда
     смотрит игрок»). Возвращаем ровное вращение вокруг своей оси —
     оно одинаково для всех и не зависит от камеры. ]]
ES.MarkerRoll = 90

--- Скорость вращения значка, градусов в секунду.
ES.MarkerSpin = 42

ES.DrawDistance = 2200        -- дальше значок не рисуем: бережём кадр

--- Оборудование, которое считается доходной точкой бизнеса.
ES.EquipmentClasses = {
    grm_vending_machine = { label = "автомат", kind = "vending" },
    grm_fuel_pump       = { label = "колонка", kind = "fuel" },
}

--[[ Какие типы недвижимости к какому виду относятся. Тип уже есть в
     GRM.Property, поэтому вид выводим из него — существующие объекты
     получают вид сами, без ручной правки. ]]
ES.TypeKind = {
    apartment  = "estate",
    shop       = "business",
    office     = "business",
    warehouse  = "business",
    government = "none",
    restricted = "none",
}

if SERVER and not ConVarExists("grm_estate_limit") then
    CreateConVar("grm_estate_limit", "3", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "Сколько бизнесов может держать один игрок (жильё не считается)")
end

-----------------------------------------------------------------------
-- ОБЩАЯ ЧАСТЬ
-----------------------------------------------------------------------

--- Вид объекта: estate, business или none.
function ES.KindOf(rec)
    if not istable(rec) then return "none" end
    -- Явно заданный вид сильнее типа: админ может сделать бизнесом что угодно.
    local explicit = tostring(rec.estateKind or "")
    if explicit == "business" or explicit == "estate" then return explicit end
    return ES.TypeKind[tostring(rec.type or "")] or "none"
end

function ES.IsBusiness(rec) return ES.KindOf(rec) == "business" end
function ES.IsEstate(rec)   return ES.KindOf(rec) == "estate" end

--- Центр зоны объекта. nil, если зона не задана.
function ES.ZoneCenter(rec)
    if not (istable(rec) and istable(rec.zone)) then return nil end
    local a, b = rec.zone.mins, rec.zone.maxs
    if not (istable(a) and istable(b)) then return nil end
    return Vector((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
end

--[[ ГЛАВНАЯ ДВЕРЬ ОБЪЕКТА.

     Из всех дверей записи берём ту, что ближе всего к центру зоны по
     горизонтали — это почти всегда вход, а не смежная внутренняя дверь.
     Детерминированность важна: при равном расстоянии выбираем по
     идентификатору, иначе значок прыгал бы между дверями от пересчёта
     к пересчёту (порядок ents.GetAll() не гарантирован). ]]
--[[ Справочник «идентификатор двери → энтити». Строится ОДИН раз на
     пересборку снимка: без него каждый объект гонял бы полный список
     дверей карты заново, а объектов десятки. ]]
function ES.DoorIndex()
    local out = {}
    if not (GRM.Doors and GRM.Doors.AllDoors and GRM.Doors.GetDoorID) then return out end
    for _, ent in ipairs(GRM.Doors.AllDoors() or {}) do
        if IsValid(ent) then
            local id = tostring(GRM.Doors.GetDoorID(ent) or "")
            if id ~= "" and not out[id] then out[id] = ent end
        end
    end
    return out
end

--[[ Насколько точка близка к ВНЕШНЕЙ стене зоны и в какую сторону эта
     стена смотрит.

     Возвращает: запас до ближайшей грани по горизонтали (меньше — ближе
     к улице, отрицательное значение = дверь стоит чуть за границей) и
     единичный вектор нормали этой грани наружу.

     Зачем именно так. Первая версия выбирала «дверь, ближайшую к центру
     зоны» — и стенд сразу поймал ошибку: ближе всего к центру стоит
     ВНУТРЕННЯЯ дверь комнаты, а вход как раз врезан в наружную стену,
     то есть максимально далеко от центра. ]]
function ES.ZoneEdge(rec, pos)
    if not (istable(rec) and istable(rec.zone) and pos) then return nil end
    local a, b = rec.zone.mins, rec.zone.maxs
    if not (istable(a) and istable(b)) then return nil end

    local sides = {
        { d = pos.x - a.x, nx = -1, ny = 0 },   -- западная стена
        { d = b.x - pos.x, nx =  1, ny = 0 },   -- восточная
        { d = pos.y - a.y, nx = 0, ny = -1 },   -- южная
        { d = b.y - pos.y, nx = 0, ny =  1 },   -- северная
    }
    local best = sides[1]
    for i = 2, #sides do
        if sides[i].d < best.d then best = sides[i] end
    end
    return best.d, best.nx, best.ny
end

--- Главная (входная) дверь объекта.
function ES.MainDoor(rec, index)
    if not istable(rec) or not istable(rec.doors) or #rec.doors == 0 then return nil end
    index = istable(index) and index or ES.DoorIndex()

    local best, bestMargin, bestID
    for _, rawID in ipairs(rec.doors) do
        local id = tostring(rawID)
        local ent = index[id]
        if IsValid(ent) then
            -- Чем меньше запас до стены, тем вероятнее это вход с улицы.
            local margin = ES.ZoneEdge(rec, ent:GetPos()) or 0
            --[[ Строгое сравнение с допуском плюс разрыв ничьей по
                 идентификатору: порядок дверей в записи и в мире не
                 гарантирован, а значок не должен прыгать между
                 одинаково расположенными дверями при каждом пересчёте. ]]
            if not best or margin < bestMargin - 0.5
                or (math.abs(margin - bestMargin) <= 0.5 and id < bestID) then
                best, bestMargin, bestID = ent, margin, id
            end
        end
    end
    return best
end

--[[ УДАЛЕНО: ES.OutwardDir.

     Считала, в какую сторону от зоны развернуть табличку, когда та
     висела на стене над проёмом. После переноса плашки НА полотно
     разворот берётся у самой двери (её OBB и углы), поэтому функция
     стала мёртвым кодом и убрана — чтобы не выглядела действующей.

     ES.ZoneEdge осталась: по ней всё ещё выбирается входная дверь. ]]

--[[ ТОЧКА, ГДЕ ВИСИТ ТАБЛИЧКА.

     ПЕРЕСМОТР 28.08: «лучше чтобы таблички были не НАД дверями, а НА
     дверях, как это сделано с автоматами с едой».

     Было: табличка висела над дверным проёмом, в плоскости стены. Над
     дверью почти всегда лежит балка, косяк или начинается потолок —
     вывеска налезала на них и выглядела приклеенной к стене случайно.

     Стало: делаем ровно как у торгового автомата (VENDING:Draw в
     cl_grm_vending_gui) — плашка лежит НА САМОМ ПОЛОТНЕ, в собственных
     углах двери. Отсюда два важных следствия:

       • сервер больше не считает yaw по нормали зоны. Угол таблички —
         это угол ДВЕРИ, и знает его только клиент, у которого есть
         энтити. Поэтому сюда возвращается сама дверь, а разворот и
         точное место клиент берёт из её OBB;
       • табличка едет вместе с дверью, когда та открывается. Раньше
         она оставалась висеть в воздухе.

     Возвращает: точку (запасная, для зон без дверей), признак «на
     двери» и саму дверь. ]]
function ES.MarkerAnchor(rec, index)
    local door = ES.MainDoor(rec, index)
    if IsValid(door) then
        --[[ Позицию отдаём как позицию двери: она нужна только для
             отсечения по дальности и как запасной вариант, если у
             клиента дверь почему-то не найдётся. Точное место плашки
             считает клиент в углах полотна. ]]
        local pos = (door.WorldSpaceCenter and door:WorldSpaceCenter()) or door:GetPos()
        return Vector(pos.x, pos.y, pos.z), true, door
    end

    local center = ES.ZoneCenter(rec)
    if not center then return nil, false, nil end
    return Vector(center.x, center.y, center.z + ES.MarkerHeight), false, nil
end

--[[ Сумма с разделителями разрядов: «85 000 GRM» вместо «85000 GRM».
     Владелец сам пишет цены как «85.000 GRM» — на табличке у двери
     слитное число читается плохо. Берём общий GRM.Format, если модуль
     валюты загружен, иначе форматируем сами: значок не должен зависеть
     от порядка загрузки файлов. ]]
function ES.Money(amount)
    local n = math.floor(tonumber(amount) or 0)
    if isfunction(GRM.Format) then return GRM.Format(n) end
    local s, out, cnt = tostring(math.abs(n)), "", 0
    for i = #s, 1, -1 do
        out = s:sub(i, i) .. out
        cnt = cnt + 1
        if cnt % 3 == 0 and i > 1 then out = " " .. out end
    end
    return (n < 0 and "-" or "") .. out .. " GRM"
end

--- Цвет объекта на значке: синий «продаётся», иначе цвет своего вида.
function ES.ZoneColor(zone)
    if not istable(zone) then return ES.MarkerColor.estate end
    if zone.vacant then return ES.MarkerColor.sale end
    return ES.MarkerColor[zone.kind] or ES.MarkerColor.estate
end

--[[ Три строки таблички у двери: название, статус, подсказка.

     Держим в ОБЩЕЙ части, а не в клиентской: так содержимое вывески
     проверяется стендом без запуска рендера. Раньше текст собирался
     прямо в HUDPaint, и убедиться, что на табличке написано именно
     «Квартира №2 · 85 000 GRM», можно было только глазами на сервере. ]]
function ES.PlaqueLines(zone)
    if not istable(zone) then return "", "", nil end
    local title = tostring(zone.name or "") ~= "" and zone.name
        or (zone.kind == "business" and "Бизнес" or "Жильё")

    local status, hint
    if zone.vacant then
        status = (tonumber(zone.price) or 0) > 0
            and ("СВОБОДНО · " .. ES.Money(zone.price))
            or "СВОБОДНО"
        -- Прямо на табличке написано, что набрать: покупка живёт не в админке.
        hint = zone.kind == "business" and "/buybusiness" or "/buyhome"
    else
        status = tostring(zone.owner or "") ~= "" and zone.owner or "занято"
        -- Для бизнеса сразу видно, сколько внутри оборудования.
        if zone.kind == "business" and (tonumber(zone.equipment) or 0) > 0 then
            status = status .. "  ·  точек: " .. zone.equipment
        end
    end
    return title, status, hint
end

--- Площадь зоны в метрах (1 м ≈ 39.37 units) — для подсказки цены.
function ES.ZoneArea(rec)
    if not (istable(rec) and istable(rec.zone)) then return 0 end
    local a, b = rec.zone.mins, rec.zone.maxs
    if not (istable(a) and istable(b)) then return 0 end
    local w = math.abs((b.x or 0) - (a.x or 0)) / 39.37
    local d = math.abs((b.y or 0) - (a.y or 0)) / 39.37
    return math.floor(w * d)
end

function ES.PointInZone(rec, pos)
    if not (istable(rec) and istable(rec.zone) and pos) then return false end
    local a, b = rec.zone.mins, rec.zone.maxs
    if not (istable(a) and istable(b)) then return false end
    return pos.x >= a.x and pos.y >= a.y and pos.z >= a.z
        and pos.x <= b.x and pos.y <= b.y and pos.z <= b.z
end

--- Свободен ли объект (можно купить или арендовать).
function ES.IsVacant(rec)
    if not istable(rec) then return false end
    return tostring(rec.ownerType or "none") == "none"
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    --[[ СКАНИРОВАНИЕ ЗОНЫ. Оборудование не привязывается вручную: стоит
         внутри границ — значит принадлежит объекту. Убрали автомат —
         следующий пересчёт это увидит. ]]
    function ES.ScanZone(rec)
        local out = { total = 0, byKind = {}, entities = {} }
        if not (istable(rec) and istable(rec.zone)) then return out end
        for class, info in pairs(ES.EquipmentClasses) do
            local list = (GRM.Perf and GRM.Perf.Entities)
                and GRM.Perf.Entities(class) or ents.FindByClass(class)
            for _, ent in ipairs(list or {}) do
                if IsValid(ent) and ES.PointInZone(rec, ent:GetPos()) then
                    out.total = out.total + 1
                    out.byKind[info.kind] = (out.byKind[info.kind] or 0) + 1
                    out.entities[#out.entities + 1] = ent
                end
            end
        end
        return out
    end

    --- Кэш сканирования: обходить все сущности на каждый чих не нужно.
    ES._scanCache = ES._scanCache or {}
    function ES.ScanCached(rec, maxAge)
        if not istable(rec) then return { total = 0, byKind = {}, entities = {} } end
        local id = tostring(rec.id or "")
        local now = CurTime()
        local hit = ES._scanCache[id]
        if hit and (now - hit.at) < (tonumber(maxAge) or 5) then return hit.data end
        local data = ES.ScanZone(rec)
        ES._scanCache[id] = { at = now, data = data }
        return data
    end

    function ES.InvalidateScan(rec)
        if istable(rec) then ES._scanCache[tostring(rec.id or "")] = nil
        else ES._scanCache = {} end
    end

    --- Текстовая сводка по содержимому зоны для интерфейса.
    function ES.EquipmentSummary(rec)
        local scan = ES.ScanCached(rec)
        if scan.total == 0 then return "оборудования нет" end
        local parts = {}
        if (scan.byKind.vending or 0) > 0 then
            parts[#parts + 1] = scan.byKind.vending .. " автом."
        end
        if (scan.byKind.fuel or 0) > 0 then
            parts[#parts + 1] = scan.byKind.fuel .. " колонк."
        end
        return table.concat(parts, " · ")
    end

    -----------------------------------------------------------------
    -- ПРАВИЛО ОДИНОЧНОЙ ТОЧКИ (решение владельца)
    -----------------------------------------------------------------
    --[[ Одиночный автомат или колонка — личное дело игрока, зона не нужна.
         Две и более точек рядом — это уже сеть, её оформляют бизнес-зоной.
         Считаем соседей в радиусе: если точка не одна, требуем зону. ]]
    ES.ClusterRadius = 700

    function ES.NeighbourCount(pos, exceptEnt)
        local n = 0
        for class in pairs(ES.EquipmentClasses) do
            local list = (GRM.Perf and GRM.Perf.Entities)
                and GRM.Perf.Entities(class) or ents.FindByClass(class)
            for _, ent in ipairs(list or {}) do
                if IsValid(ent) and ent ~= exceptEnt
                    and ent:GetPos():DistToSqr(pos) <= ES.ClusterRadius ^ 2 then
                    n = n + 1
                end
            end
        end
        return n
    end

    --- Объект недвижимости, внутри которого стоит точка (или nil).
    function ES.ZoneAt(pos)
        local P = GRM.Property
        if not (P and istable(P.Records)) then return nil end
        for _, rec in pairs(P.Records) do
            if ES.PointInZone(rec, pos) then return rec end
        end
        return nil
    end

    --[[ Можно ли владеть этой точкой лично, без бизнес-зоны.
         Возвращает: можно ли, причина отказа. ]]
    function ES.CanOwnStandalone(ent)
        if not IsValid(ent) then return false, "Нет объекта" end
        local pos = ent:GetPos()
        -- Внутри оформленной бизнес-зоны точка принадлежит бизнесу.
        local zone = ES.ZoneAt(pos)
        if zone and ES.IsBusiness(zone) then
            return false, "Точка входит в бизнес «" .. tostring(zone.name or "") .. "»"
        end
        -- Одна точка — личное владение разрешено.
        if ES.NeighbourCount(pos, ent) == 0 then return true end
        return false, "Рядом несколько точек — оформите бизнес-зону"
    end

    -----------------------------------------------------------------
    -- ЛИМИТ БИЗНЕСОВ НА ИГРОКА
    -----------------------------------------------------------------
    function ES.Limit()
        local cv = GetConVar and GetConVar("grm_estate_limit")
        return math.max(1, math.floor(cv and cv:GetInt() or 3))
    end

    function ES.CountOwned(ownerKey)
        ownerKey = tostring(ownerKey or "")
        if ownerKey == "" then return 0 end
        local P = GRM.Property
        if not (P and istable(P.Records)) then return 0 end
        local n = 0
        for _, rec in pairs(P.Records) do
            -- Жильё в лимит бизнесов не входит.
            if ES.IsBusiness(rec) and tostring(rec.ownerType or "") == "character"
                and tostring(rec.ownerKey or "") == ownerKey then
                n = n + 1
            end
        end
        return n
    end

    function ES.CanAcquire(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not ES.IsBusiness(rec) then return true end     -- жильё без лимита
        if ply:IsSuperAdmin() then return true end
        local key = (GRM.Identity and GRM.Identity.CharacterKey
            and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        local have, limit = ES.CountOwned(key), ES.Limit()
        if have >= limit then
            return false, ("Лимит бизнесов: %d из %d. Продайте один, чтобы купить новый."):format(have, limit)
        end
        return true
    end

    -----------------------------------------------------------------
    -- ПЕНЯ ЗА ПРОСРОЧКУ (решение владельца: не отключать и не изымать)
    -----------------------------------------------------------------
    ES.PenaltyRate = 0.05        -- 5% от долга за расчётный период
    ES.PenaltyGrace = 3          -- сколько периодов долга терпим без пени

    --[[ Начисление пени поверх штатной коммуналки GRM.Property.
         Долг растёт сам, объект не отбирается — как и просил владелец. ]]
    function ES.ApplyPenalty(rec)
        if not istable(rec) then return 0 end
        local debt = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0))
        local rate = math.max(0, math.floor(tonumber(rec.utilityRate) or 0))
        if debt <= 0 or rate <= 0 then
            rec.estatePenalty = 0
            return 0
        end
        -- Пеня начинается, только когда долг перерос несколько периодов.
        if debt < rate * ES.PenaltyGrace then return 0 end
        local add = math.floor(debt * ES.PenaltyRate)
        if add <= 0 then return 0 end
        rec.utilityDebt = math.min(100000000, debt + add)
        rec.estatePenalty = math.max(0, math.floor(tonumber(rec.estatePenalty) or 0)) + add
        return add
    end

    hook.Add("Think", "GRM_Estate_Penalty", function()
        if not (GRM.Perf and GRM.Perf.Throttle) then return end
        -- Раз в 5 минут, тем же ритмом, что и штатная коммуналка.
        if not GRM.Perf.Throttle("estate.penalty", 300) then return end
        local P = GRM.Property
        if not (P and istable(P.Records)) then return end
        local touched = false
        for _, rec in pairs(P.Records) do
            if tostring(rec.ownerType or "none") ~= "none" then
                if ES.ApplyPenalty(rec) > 0 then touched = true end
            end
        end
        if touched and P.Save then pcall(P.Save, "estate-penalty") end
    end)

    -----------------------------------------------------------------
    -- СНИМОК ДЛЯ КЛИЕНТА (значки и сводка)
    -----------------------------------------------------------------
    local NET_SYNC = "GRM_Estate_Sync"
    util.AddNetworkString(NET_SYNC)

    function ES.BuildSnapshot()
        local out = {}
        local P = GRM.Property
        if not (P and istable(P.Records)) then return out end
        -- Справочник дверей один на весь снимок, а не на каждый объект.
        local doorIndex = ES.DoorIndex()
        for _, rec in pairs(P.Records) do
            local kind = ES.KindOf(rec)
            --[[ Какой двери принадлежит табличка, решает сервер: только у
                 него есть привязка объекта к дверям. А вот КУДА именно
                 лечь на полотне, считает клиент по углам самой двери —
                 как это делает торговый автомат. ]]
            local anchor, onDoor, door = ES.MarkerAnchor(rec, doorIndex)
            if kind ~= "none" and anchor then
                local scan = ES.ScanCached(rec, 30)
                out[#out + 1] = {
                    id = tostring(rec.id or ""),
                    kind = kind,
                    name = tostring(rec.name or ""),
                    pos = { x = anchor.x, y = anchor.y, z = anchor.z },
                    --[[ Значок на двери: клиент нарисует плашку прямо на
                         полотне. Без двери — прежняя эмблема в центре
                         зоны. ]]
                    onDoor = onDoor and true or false,
                    --[[ Индекс двери-носителя. Передаём именно его, а не
                         угол: дверь открывается, и табличка обязана
                         ехать вместе с ней. ]]
                    door = (onDoor and IsValid(door)) and door:EntIndex() or 0,
                    -- Выставленный на продажу объект выглядит как свободный:
                    -- синий значок означает «можно купить».
                    vacant = ES.IsVacant(rec) or istable(rec.estateSale),
                    forSale = istable(rec.estateSale) and math.max(0,
                        math.floor(tonumber(rec.estateSale.price) or 0)) or 0,
                    owner = tostring(rec.ownerName or ""),
                    equipment = kind == "business" and scan.total or 0,
                    price = istable(rec.estateSale)
                        and math.max(0, math.floor(tonumber(rec.estateSale.price) or 0))
                        or math.max(0, math.floor(tonumber(rec.purchasePrice) or 0)),
                    area = ES.ZoneArea(rec),
                }
            end
        end
        return out
    end

    function ES.Sync(ply)
        local ok, txt = pcall(util.TableToJSON, ES.BuildSnapshot())
        if not ok or not txt then return end
        local data = util.Compress(txt) or ""
        if #data == 0 then return end
        net.Start(NET_SYNC)
            net.WriteUInt(#txt, 32)
            net.WriteUInt(#data, 32)
            net.WriteData(data, #data)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    hook.Add("PlayerInitialSpawn", "GRM_Estate_Sync", function(ply)
        timer.Simple(6, function() if IsValid(ply) then ES.Sync(ply) end end)
    end)

    -- Смена владельца сразу меняет цвет значка у всех.
    hook.Add("GRM_PropertyOwnerChanged", "GRM_Estate_Resync", function()
        timer.Simple(0.2, function() ES.Sync() end)
    end)

    --- Периодическая пересинхронизация: оборудование могли передвинуть.
    timer.Create("GRM_Estate_Resync", 120, 0, function()
        ES.InvalidateScan()
        ES.Sync()
    end)

    -----------------------------------------------------------------
    -- ОБЩАЯ КАССА БИЗНЕСА (фаза 4)
    -----------------------------------------------------------------
    --[[ Раньше касса была у каждого автомата и каждой колонки своя: чтобы
         собрать выручку сети, владелец обходил все точки. Теперь бизнес —
         одна касса: деньги точек внутри зоны снимаются разом.

         Сами точки продолжают копить выручку как раньше (их модули не
         переписываем), а бизнес просто собирает её из них. ]]

    --- Сколько лежит в точках бизнеса прямо сейчас.
    function ES.CashInZone(rec)
        local scan = ES.ScanCached(rec, 2)
        local total = 0
        for _, ent in ipairs(scan.entities) do
            if IsValid(ent) then
                local cls = ent:GetClass()
                if cls == "grm_vending_machine" and GRM.VendingBiz and GRM.VendingBiz.GetCash then
                    total = total + (GRM.VendingBiz.GetCash(ent) or 0)
                elseif cls == "grm_fuel_pump" and ent.GetCash then
                    total = total + (tonumber(ent:GetCash()) or 0)
                end
            end
        end
        return math.max(0, math.floor(total))
    end

    --- Итоги бизнеса за всё время: продано штук и заработано.
    function ES.StatsInZone(rec)
        local scan = ES.ScanCached(rec, 5)
        local sold, earned = 0, 0
        for _, ent in ipairs(scan.entities) do
            if IsValid(ent) and GRM.VendingBiz and GRM.VendingBiz.GetStats then
                local s, e = GRM.VendingBiz.GetStats(ent)
                sold = sold + (s or 0)
                earned = earned + (e or 0)
            end
        end
        return sold, earned
    end

    --- Владелец ли игрок этого объекта.
    function ES.IsOwner(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false end
        if tostring(rec.ownerType or "none") ~= "character" then return false end
        local key = (GRM.Identity and GRM.Identity.CharacterKey
            and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        return tostring(rec.ownerKey or "") == tostring(key or "")
    end

    --[[ Снять кассу бизнеса. Долг по коммуналке гасится ПЕРВЫМ: иначе
         владелец копил бы пеню и снимал выручку мимо неё. ]]
    function ES.Collect(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not (ES.IsOwner(ply, rec) or ply:IsSuperAdmin()) then
            return false, "Это не ваш объект"
        end
        if not ES.IsBusiness(rec) then return false, "Жильё выручки не приносит" end

        ES.InvalidateScan(rec)
        local scan = ES.ScanZone(rec)
        local total = 0
        for _, ent in ipairs(scan.entities) do
            if IsValid(ent) then
                local cls = ent:GetClass()
                if cls == "grm_vending_machine" and GRM.VendingBiz then
                    local cash = GRM.VendingBiz.GetCash and GRM.VendingBiz.GetCash(ent) or 0
                    if cash > 0 then
                        total = total + cash
                        GRM.VendingBiz.SetCash(ent, 0)
                    end
                elseif cls == "grm_fuel_pump" and ent.GetCash and ent.SetCash then
                    local cash = tonumber(ent:GetCash()) or 0
                    if cash > 0 then
                        total = total + math.floor(cash)
                        ent:SetCash(0)
                    end
                end
            end
        end
        if total <= 0 then return false, "Касса пуста" end

        -- Сначала долг, остаток — владельцу.
        local debt = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0))
        local paid = 0
        if debt > 0 then
            paid = math.min(debt, total)
            rec.utilityDebt = debt - paid
            total = total - paid
            if rec.utilityDebt == 0 then rec.estatePenalty = 0 end
        end

        if total > 0 and GRM.GiveMoney then
            GRM.GiveMoney(ply, total, "касса бизнеса «" .. tostring(rec.name or "") .. "»")
        end
        local P = GRM.Property
        if P and P.Save then pcall(P.Save, "estate-collect") end
        if GRM.VendingBiz and GRM.VendingBiz.Persist then pcall(GRM.VendingBiz.Persist, true) end
        if GRM.Fuel and GRM.Fuel.SavePumps then pcall(GRM.Fuel.SavePumps) end
        hook.Run("GRM_EstateCollected", ply, rec, total, paid)

        if paid > 0 and total > 0 then
            return true, ("Снято %d GRM · погашен долг %d GRM"):format(total, paid)
        elseif paid > 0 then
            return true, ("Вся выручка (%d GRM) ушла на погашение долга"):format(paid)
        end
        return true, "Снято " .. total .. " GRM"
    end

    --[[ Доход за сутки. Считаем по накопленной выручке точек и возрасту
         объекта: точной статистики по времени пока не ведём, но владельцу
         нужен порядок цифры, а не бухгалтерия. ]]
    function ES.DailyEstimate(rec)
        local _, earned = ES.StatsInZone(rec)
        if earned <= 0 then return 0 end
        local since = math.max(1, os.time() - (tonumber(rec.estateSince) or os.time()))
        local days = math.max(1, since / 86400)
        return math.floor(earned / days)
    end

    --- Сводка по объекту для интерфейсов.
    function ES.Summary(rec)
        local kind = ES.KindOf(rec)
        local sold, earned = 0, 0
        local cash = 0
        if kind == "business" then
            sold, earned = ES.StatsInZone(rec)
            cash = ES.CashInZone(rec)
        end
        return {
            id = tostring(rec.id or ""),
            name = tostring(rec.name or ""),
            kind = kind,
            vacant = ES.IsVacant(rec),
            owner = tostring(rec.ownerName or ""),
            cash = cash,
            sold = sold,
            earned = earned,
            daily = kind == "business" and ES.DailyEstimate(rec) or 0,
            debt = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0)),
            penalty = math.max(0, math.floor(tonumber(rec.estatePenalty) or 0)),
            equipment = kind == "business" and ES.ScanCached(rec, 10).total or 0,
            summary = kind == "business" and ES.EquipmentSummary(rec) or "",
            area = ES.ZoneArea(rec),
            price = math.max(0, math.floor(tonumber(rec.purchasePrice) or 0)),
        }
    end

    --[[ Отметка начала владения: от неё считается средний доход в сутки.
         Ставится при смене владельца, чтобы прошлые продажи не искажали
         статистику нового хозяина. ]]
    hook.Add("GRM_PropertyOwnerChanged", "GRM_Estate_OwnStamp", function(rec, act)
        if not istable(rec) then return end
        if act == "buy" or act == "rent" or act == "admin_update" then
            rec.estateSince = os.time()
        elseif act == "release" or act == "evict" or act == "rent_expired" then
            rec.estateSince = nil
        end
    end)

    -----------------------------------------------------------------
    -- ТУЛ «GRM: БИЗНЕС-ЗОНА» (фаза 3)
    -----------------------------------------------------------------
    --[[ Тул выделяет зону прямо на месте и сразу показывает, что внутри.
         Заходить в админку и привязывать оборудование руками не нужно —
         сканирование само найдёт автоматы и колонки в границах. ]]
    local NET_TOOL_REQ  = "GRM_Estate_ToolReq"
    local NET_TOOL_DATA = "GRM_Estate_ToolData"
    util.AddNetworkString(NET_TOOL_REQ)
    util.AddNetworkString(NET_TOOL_DATA)

    --- Что лежит в произвольном прямоугольнике: нужно для предпросмотра.
    function ES.ScanBox(mins, maxs)
        local fake = { id = "__preview", zone = {
            mins = { x = mins.x, y = mins.y, z = mins.z },
            maxs = { x = maxs.x, y = maxs.y, z = maxs.z } } }
        return ES.ScanZone(fake)
    end

    --[[ Снимок для тула: существующие зоны с их содержимым плюс
         оборудование, которое пока ничьё — админ сразу видит, что
         осталось неоформленным. ]]
    local function toolSnapshot()
        local zones, loose = {}, {}
        local P = GRM.Property
        local claimed = {}

        for _, rec in pairs((P and P.Records) or {}) do
            local kind = ES.KindOf(rec)
            if kind ~= "none" and istable(rec.zone) then
                local scan = ES.ScanCached(rec, 3)
                for _, ent in ipairs(scan.entities) do claimed[ent] = true end
                zones[#zones + 1] = {
                    id = tostring(rec.id or ""),
                    name = tostring(rec.name or ""),
                    kind = kind,
                    mins = rec.zone.mins,
                    maxs = rec.zone.maxs,
                    vacant = ES.IsVacant(rec),
                    owner = tostring(rec.ownerName or ""),
                    equipment = scan.total,
                    summary = kind == "business" and ES.EquipmentSummary(rec) or "",
                    area = ES.ZoneArea(rec),
                    price = math.max(0, math.floor(tonumber(rec.purchasePrice) or 0)),
                }
            end
        end

        for class, info in pairs(ES.EquipmentClasses) do
            local list = (GRM.Perf and GRM.Perf.Entities)
                and GRM.Perf.Entities(class) or ents.FindByClass(class)
            for _, ent in ipairs(list or {}) do
                if IsValid(ent) and not claimed[ent] then
                    local pos = ent:GetPos()
                    loose[#loose + 1] = { x = pos.x, y = pos.y, z = pos.z, label = info.label }
                end
            end
        end
        return zones, loose
    end

    net.Receive(NET_TOOL_REQ, function(_, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        if GRM.Perf and GRM.Perf.Throttle
            and not GRM.Perf.Throttle("estate.tool." .. ply:EntIndex(), 0.9) then return end
        local zones, loose = toolSnapshot()
        net.Start(NET_TOOL_DATA)
            net.WriteTable({ zones = zones, loose = loose })
        net.Send(ply)
    end)

    --[[ Создание зоны туллом. Объект недвижимости заводится сразу с
         границами: двери можно привязать потом штатным тулом. ]]
    function ES.CreateZone(ply, a, b, name, kind, price)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "Только суперадмин" end
        local P = GRM.Property
        if not (P and istable(P.Records)) then return false, "Модуль недвижимости не загружен" end

        local mins = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
        local maxs = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z) + 190)
        -- Совсем плоскую зону оформлять нельзя: в неё ничего не попадёт.
        if (maxs.x - mins.x) < 32 or (maxs.y - mins.y) < 32 then
            return false, "Зона слишком мала — разведите углы шире"
        end

        kind = (kind == "estate") and "estate" or "business"
        local id = "zone_" .. tostring(math.floor(CurTime() * 100)) .. "_" .. tostring(math.random(100, 999))
        local rec = P.Normalize({
            id = id,
            name = tostring(name or ""),
            -- Тип задаём под вид: жильё квартирой, бизнес магазином.
            type = kind == "estate" and "apartment" or "shop",
            estateKind = kind,
            doors = {},
            purchasePrice = math.max(0, math.floor(tonumber(price) or 0)),
            zone = {
                mins = { x = mins.x, y = mins.y, z = mins.z },
                maxs = { x = maxs.x, y = maxs.y, z = maxs.z },
            },
        })
        if rec.name == "" then
            rec.name = kind == "estate" and "Жилой объект" or "Бизнес-объект"
        end
        P.Records[rec.id] = rec
        if P.Reindex then P.Reindex() end

        --[[ ДВЕРИ ПРИВЯЗЫВАЕМ СРАЗУ ПРИ СОЗДАНИИ ЗОНЫ (заказ владельца 28.08:
             «значок жилья должен крепиться к дверям после создания зоны»).

             Раньше двери подтягивались только в момент покупки — значит у
             свежесозданной свободной зоны дверей не было, значку не к чему
             крепиться, и он висел в центре комнаты. Теперь запись получает
             свои двери сразу: значок и подпись встают над входом ещё до
             того, как объект кто-то купит.

             Владельца дверей это НЕ меняет: AttachDoors только пополняет
             rec.doors и пропускает двери, уже занятые другим объектом. ]]
        local attached = 0
        if GRM.EstateDeal and GRM.EstateDeal.AttachDoors then
            local okAttach, n = pcall(GRM.EstateDeal.AttachDoors, rec)
            if okAttach then attached = tonumber(n) or 0 end
        end

        if P.Save then pcall(P.Save, "estate-tool") end
        ES.InvalidateScan()
        ES.Sync()

        local scan = ES.ScanZone(rec)
        return true, ("Зона «%s» создана · %d м² · внутри точек: %d · дверей: %d"):format(
            rec.name, ES.ZoneArea(rec), scan.total, attached), rec
    end

    --- Удалить зону под прицелом.
    function ES.DeleteZoneAt(ply, pos)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "Только суперадмин" end
        local P = GRM.Property
        if not (P and istable(P.Records)) then return false, "Модуль недвижимости не загружен" end
        for id, rec in pairs(P.Records) do
            if ES.KindOf(rec) ~= "none" and ES.PointInZone(rec, pos) then
                -- Занятый объект не сносим молча: сначала пусть освободят.
                if not ES.IsVacant(rec) then
                    return false, "Объект занят: " .. tostring(rec.ownerName or "владелец")
                        .. ". Сначала освободите его."
                end
                local name = tostring(rec.name or "")
                P.Records[id] = nil
                if P.Reindex then P.Reindex() end
                if P.Save then pcall(P.Save, "estate-tool-delete") end
                ES.InvalidateScan()
                ES.Sync()
                return true, "Зона «" .. name .. "» удалена"
            end
        end
        return false, "Здесь нет зоны"
    end

    -----------------------------------------------------------------
    -- РЫНОК: покупка и продажа объектов (фаза 5)
    -----------------------------------------------------------------
    --[[ Продать объект можно тремя способами:
           государству — мгновенно, но за долю цены;
           игроку      — по договорённости, второй подтверждает;
           на рынок    — объект висит с ценником и значок синеет.
         Долг по коммуналке при продаже удерживается: иначе продажа
         стала бы способом сбросить накопленную пеню. ]]
    ES.StateBuyback = 0.6        -- доля цены при продаже государству
    ES.OfferLifetime = 120       -- сколько живёт предложение игроку, секунд

    ES.Offers = ES.Offers or {}  -- [ключПокупателя] = { id, price, from, at }

    local function ownerKeyOf(ply)
        return (GRM.Identity and GRM.Identity.CharacterKey
            and GRM.Identity.CharacterKey(ply)) or (IsValid(ply) and ply:SteamID64()) or ""
    end
    ES.OwnerKeyOf = ownerKeyOf

    --[[ Освободить объект. Пишем через GRM.Property, чтобы двери,
         сотрудники и ключи очистились штатно. ]]
    local function releaseRecord(rec)
        rec.ownerType = "none"
        rec.ownerKey = ""
        rec.ownerName = ""
        rec.tenure = "none"
        rec.rentUntil = 0
        rec.employees = {}
        rec.guests = {}
        rec.tempKeys = {}
        rec.estateSince = nil
        rec.estateSale = nil
    end

    --- Сколько реально получит владелец с учётом долга.
    function ES.SalePayout(rec, price)
        price = math.max(0, math.floor(tonumber(price) or 0))
        local debt = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0))
        local paid = math.min(debt, price)
        return price - paid, paid
    end

    --- Продажа государству: мгновенно, за долю цены.
    function ES.SellToState(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not ES.IsOwner(ply, rec) then return false, "Это не ваш объект" end
        local base = math.max(0, math.floor(tonumber(rec.purchasePrice) or 0))
        local price = math.floor(base * ES.StateBuyback)
        local payout, paid = ES.SalePayout(rec, price)

        -- Касса не должна пропасть вместе с объектом.
        if ES.IsBusiness(rec) and ES.CashInZone(rec) > 0 then
            return false, "Сначала снимите кассу бизнеса"
        end

        releaseRecord(rec)
        rec.utilityDebt = math.max(0, (tonumber(rec.utilityDebt) or 0) - paid)
        rec.estatePenalty = rec.utilityDebt > 0 and rec.estatePenalty or 0
        if payout > 0 and GRM.GiveMoney then
            GRM.GiveMoney(ply, payout, "продажа объекта государству")
        end
        local P = GRM.Property
        if P and P.Save then pcall(P.Save, "estate-sell-state") end
        ES.InvalidateScan(rec)
        ES.Sync()
        hook.Run("GRM_PropertyOwnerChanged", rec, "release", ply)

        if paid > 0 then
            return true, ("Продано государству за %d GRM · удержан долг %d GRM"):format(payout, paid)
        end
        return true, "Продано государству за " .. payout .. " GRM"
    end

    --- Выставить объект на рынок с ценником (или снять с продажи).
    function ES.SetForSale(ply, rec, price)
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not ES.IsOwner(ply, rec) then return false, "Это не ваш объект" end
        price = math.max(0, math.floor(tonumber(price) or 0))
        if price <= 0 then
            rec.estateSale = nil
            if GRM.Property and GRM.Property.Save then pcall(GRM.Property.Save, "estate-unsale") end
            ES.Sync()
            return true, "Объект снят с продажи"
        end
        rec.estateSale = { price = price, at = os.time(), by = ownerKeyOf(ply) }
        if GRM.Property and GRM.Property.Save then pcall(GRM.Property.Save, "estate-sale") end
        ES.Sync()
        return true, "Объект выставлен на продажу за " .. price .. " GRM"
    end

    --[[ Купить объект, выставленный на рынок. Деньги идут прежнему
         владельцу, долг удерживается из его выручки. ]]
    function ES.BuyFromMarket(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        local sale = istable(rec.estateSale) and rec.estateSale or nil
        if not sale then return false, "Объект не продаётся" end
        if ES.IsOwner(ply, rec) then return false, "Это уже ваш объект" end

        local can, why = ES.CanAcquire(ply, rec)
        if not can then return false, why end

        local price = math.max(0, math.floor(tonumber(sale.price) or 0))
        if price > 0 and GRM.HasMoney and not GRM.HasMoney(ply, price) then
            return false, "Недостаточно наличных: нужно " .. price .. " GRM"
        end

        -- Продавец получает за вычетом долга: продажа не списывает пеню.
        local payout, paid = ES.SalePayout(rec, price)
        local sellerKey = tostring(rec.ownerKey or "")
        if price > 0 and GRM.TakeMoney then
            GRM.TakeMoney(ply, price, "покупка объекта «" .. tostring(rec.name or "") .. "»")
        end
        if payout > 0 and GRM.Identity and GRM.Identity.ResolveCharacter then
            local seller = GRM.Identity.ResolveCharacter(sellerKey)
            if IsValid(seller) and GRM.GiveMoney then
                GRM.GiveMoney(seller, payout, "продажа объекта")
                if GRM.Notify then
                    GRM.Notify(seller, ("Ваш объект «%s» куплен за %d GRM"):format(
                        tostring(rec.name or ""), payout), 100, 215, 125)
                end
            end
        end

        rec.utilityDebt = math.max(0, (tonumber(rec.utilityDebt) or 0) - paid)
        rec.ownerType = "character"
        rec.ownerKey = ownerKeyOf(ply)
        rec.ownerName = ply:GetNWString("GRM_RPName", ply:Nick())
        rec.tenure = "owned"
        rec.rentUntil = 0
        rec.employees, rec.guests, rec.tempKeys = {}, {}, {}
        rec.estateSince = os.time()
        rec.estateSale = nil
        rec.lastUtilityAt = os.time()

        local P = GRM.Property
        if P and P.Save then pcall(P.Save, "estate-market-buy") end
        ES.InvalidateScan(rec)
        ES.Sync()
        hook.Run("GRM_PropertyOwnerChanged", rec, "buy", ply)
        return true, "Объект куплен за " .. price .. " GRM"
    end

    --- Предложить объект конкретному игроку.
    function ES.OfferTo(ply, rec, target, price)
        if not (IsValid(ply) and IsValid(target) and istable(rec)) then return false, "Нет игрока" end
        if not ES.IsOwner(ply, rec) then return false, "Это не ваш объект" end
        if target == ply then return false, "Нельзя предложить самому себе" end
        price = math.max(0, math.floor(tonumber(price) or 0))
        ES.Offers[ownerKeyOf(target)] = {
            id = tostring(rec.id or ""), price = price,
            from = ownerKeyOf(ply), at = os.time(),
        }
        if GRM.Notify then
            GRM.Notify(target, ("Вам предлагают «%s» за %d GRM. Примите: /business_accept"):format(
                tostring(rec.name or ""), price), 120, 200, 255)
        end
        return true, "Предложение отправлено"
    end

    --- Принять предложение.
    function ES.AcceptOffer(ply)
        if not IsValid(ply) then return false, "Нет игрока" end
        local key = ownerKeyOf(ply)
        local offer = ES.Offers[key]
        if not istable(offer) then return false, "Вам ничего не предлагали" end
        if (os.time() - (tonumber(offer.at) or 0)) > ES.OfferLifetime then
            ES.Offers[key] = nil
            return false, "Предложение истекло"
        end
        local P = GRM.Property
        local rec = P and istable(P.Records) and P.Records[offer.id]
        if not istable(rec) then
            ES.Offers[key] = nil
            return false, "Объект больше не существует"
        end
        -- Владелец мог смениться, пока покупатель думал.
        if tostring(rec.ownerKey or "") ~= tostring(offer.from or "") then
            ES.Offers[key] = nil
            return false, "Объект уже сменил владельца"
        end
        -- Пропускаем сделку через ту же проверку, что и рынок.
        local saved = rec.estateSale
        rec.estateSale = { price = offer.price, at = offer.at, by = offer.from }
        local ok, msg = ES.BuyFromMarket(ply, rec)
        if not ok then rec.estateSale = saved end
        ES.Offers[key] = nil
        return ok, msg
    end

    --- Список объектов, выставленных на продажу.
    function ES.MarketList()
        local out = {}
        local P = GRM.Property
        for _, rec in pairs((P and P.Records) or {}) do
            if istable(rec.estateSale) and ES.KindOf(rec) ~= "none" then
                out[#out + 1] = {
                    id = tostring(rec.id or ""),
                    name = tostring(rec.name or ""),
                    kind = ES.KindOf(rec),
                    price = math.max(0, math.floor(tonumber(rec.estateSale.price) or 0)),
                    owner = tostring(rec.ownerName or ""),
                    area = ES.ZoneArea(rec),
                    equipment = ES.IsBusiness(rec) and ES.ScanCached(rec, 30).total or 0,
                }
            end
        end
        table.sort(out, function(a, b) return a.price < b.price end)
        return out
    end

    -----------------------------------------------------------------
    -- ОКНО БИЗНЕСА: подход к зоне и снятие кассы
    -----------------------------------------------------------------
    local NET_PANEL = "GRM_Estate_Panel"
    local NET_ACT   = "GRM_Estate_Act"
    util.AddNetworkString(NET_PANEL)
    util.AddNetworkString(NET_ACT)

    --- Объект, в зоне которого стоит игрок.
    function ES.ZoneOfPlayer(ply)
        if not IsValid(ply) then return nil end
        return ES.ZoneAt(ply:GetPos())
    end

    function ES.OpenPanel(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false end
        local data = ES.Summary(rec)
        data.isOwner = ES.IsOwner(ply, rec) or ply:IsSuperAdmin()
        -- Состояние рынка: выставлен ли объект и по какой цене.
        data.forSale = istable(rec.estateSale) and math.max(0,
            math.floor(tonumber(rec.estateSale.price) or 0)) or 0
        data.stateOffer = math.floor((tonumber(rec.purchasePrice) or 0) * ES.StateBuyback)
        data.limit = ES.Limit()
        data.owned = ES.CountOwned((GRM.Identity and GRM.Identity.CharacterKey
            and GRM.Identity.CharacterKey(ply)) or ply:SteamID64())
        net.Start(NET_PANEL)
            net.WriteTable(data)
        net.Send(ply)
        return true
    end

    --[[ ДЕЙСТВИЯ С ОБЪЕКТОМ — таблица вместо лестницы `elseif action ==`.
         Право (владелец/дистанция) проверяется ВЫШЕ, до диспетчеризации,
         один раз на все действия. Контракт: (ply, rec) → ok, msg;
         пустой msg — «молча обновить окно». ]]
    local ESTATE_ACTIONS = {
        collect = function(ply, rec) return ES.Collect(ply, rec) end,
        buy = function(ply, rec) return ES.BuyFromMarket(ply, rec) end,
        sell_state = function(ply, rec) return ES.SellToState(ply, rec) end,
        -- Цена лежит в том же пакете, поэтому читается внутри действия:
        -- порядок чтения net-полей менять нельзя.
        sale_on = function(ply, rec) return ES.SetForSale(ply, rec, net.ReadUInt(32)) end,
        sale_off = function(ply, rec) return ES.SetForSale(ply, rec, 0) end,
        refresh = function(_ply, rec)
            ES.InvalidateScan(rec)
            return true, nil
        end,
    }

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "estate.act", { rate = 0.4, burst = 3 }, {}) then return end
        local action = net.ReadString()
        local id = net.ReadString()
        local P = GRM.Property
        local rec = P and istable(P.Records) and P.Records[id]
        if not istable(rec) then return end
        -- Все действия только вблизи объекта: управлять бизнесом издалека нельзя.
        if not ply:IsSuperAdmin() and not ES.PointInZone(rec, ply:GetPos()) then
            if GRM.Notify then GRM.Notify(ply, "Подойдите к объекту", 255, 160, 90) end
            return
        end

        local handler = ESTATE_ACTIONS[action]
        local ok, msg = false, "Неизвестное действие"
        if handler then ok, msg = handler(ply, rec) end
        if msg and GRM.Notify then
            GRM.Notify(ply, tostring(msg), ok and 100 or 255, ok and 215 or 150, ok and 125 or 110)
        end
        ES.OpenPanel(ply, rec)
    end)

    --- Открыть окно объекта, в зоне которого стоит игрок.
    concommand.Add("grm_business", function(ply)
        if not IsValid(ply) then return end
        local rec = ES.ZoneOfPlayer(ply)
        if not rec or ES.KindOf(rec) == "none" then
            if GRM.Notify then GRM.Notify(ply, "Вы не внутри бизнес-зоны или жилья", 255, 170, 90) end
            return
        end
        ES.OpenPanel(ply, rec)
    end)

    concommand.Add("grm_business_accept", function(ply)
        local ok, msg = ES.AcceptOffer(ply)
        if GRM.Notify then
            GRM.Notify(ply, tostring(msg), ok and 100 or 255, ok and 215 or 150, ok and 125 or 110)
        end
    end)

    --- Витрина рынка: что вообще продаётся на карте.
    concommand.Add("grm_market", function(ply)
        if not IsValid(ply) then return end
        local rows = ES.MarketList()
        ply:PrintMessage(HUD_PRINTTALK, "[Рынок] объектов в продаже: " .. #rows)
        for _, row in ipairs(rows) do
            ply:PrintMessage(HUD_PRINTTALK, ("  %s «%s» — %d GRM · %d м²%s"):format(
                row.kind == "business" and "БИЗНЕС" or "ЖИЛЬЁ",
                row.name, row.price, row.area,
                row.equipment > 0 and (" · точек: " .. row.equipment) or ""))
        end
        if #rows == 0 then
            ply:PrintMessage(HUD_PRINTTALK, "  Никто ничего не продаёт.")
        end
    end)

    hook.Add("PlayerSay", "GRM_Estate_Chat", function(ply, text)
        local low = string.lower(string.Trim(tostring(text or "")))
        if low == "/market" or low == "/рынок" then
            ply:ConCommand("grm_market")
            return ""
        end
        if low == "/business_accept" then
            ply:ConCommand("grm_business_accept")
            return ""
        end
        if low == "/business" or low == "/бизнес" then
            --[[ Одна команда на три случая (уточнено 28.08):
                   свободный объект → окно СДЕЛКИ с ценой и кнопкой
                                      «купить» (раньше игрока отправляли
                                      в админское /property_admin);
                   свой объект      → панель управления, касса и доход;
                   вне зоны         → личный кабинет со всеми объектами. ]]
            local rec = ES.ZoneOfPlayer(ply)
            if rec and ES.KindOf(rec) ~= "none" then
                local free = tostring(rec.ownerType or "none") == "none"
                if free and GRM.EstateDeal and GRM.EstateDeal.Open then
                    GRM.EstateDeal.Open(ply, ES.KindOf(rec))
                else
                    ES.OpenPanel(ply, rec)
                end
            else
                ES.OpenCabinet(ply)
            end
            return ""
        end
        if low == "/cabinet" or low == "/кабинет" then
            ES.OpenCabinet(ply)
            return ""
        end
    end)

    -----------------------------------------------------------------
    -- КАБИНЕТ ВЛАДЕЛЬЦА (фаза 6)
    -----------------------------------------------------------------
    --[[ Один список всех объектов игрока с общим доходом. Раньше, чтобы
         понять «чем я владею и сколько это приносит», приходилось обходить
         карту и открывать каждый объект отдельно. ]]
    local NET_CABINET = "GRM_Estate_Cabinet"
    util.AddNetworkString(NET_CABINET)

    function ES.CabinetData(ply)
        local key = ownerKeyOf(ply)
        local rows, totals = {}, {
            cash = 0, daily = 0, debt = 0, earned = 0,
            business = 0, estate = 0,
        }
        local P = GRM.Property
        for _, rec in pairs((P and P.Records) or {}) do
            local kind = ES.KindOf(rec)
            if kind ~= "none" and tostring(rec.ownerType or "") == "character"
                and tostring(rec.ownerKey or "") == key then
                local row = ES.Summary(rec)
                row.forSale = istable(rec.estateSale) and math.max(0,
                    math.floor(tonumber(rec.estateSale.price) or 0)) or 0
                --[[ Аренда с датой окончания: владелец должен видеть, что
                     договор скоро истечёт, а не узнавать об этом постфактум. ]]
                row.tenure = tostring(rec.tenure or "none")
                row.rentLeft = 0
                if row.tenure == "rent" and (tonumber(rec.rentUntil) or 0) > 0 then
                    row.rentLeft = math.max(0, math.floor((rec.rentUntil - os.time()) / 3600))
                end
                rows[#rows + 1] = row
                totals.cash = totals.cash + (row.cash or 0)
                totals.daily = totals.daily + (row.daily or 0)
                totals.debt = totals.debt + (row.debt or 0)
                totals.earned = totals.earned + (row.earned or 0)
                if kind == "business" then totals.business = totals.business + 1
                else totals.estate = totals.estate + 1 end
            end
        end
        -- Бизнес выше жилья, внутри — по убыванию кассы: где деньги, то и сверху.
        table.sort(rows, function(a, b)
            if a.kind ~= b.kind then return a.kind == "business" end
            if (a.cash or 0) ~= (b.cash or 0) then return (a.cash or 0) > (b.cash or 0) end
            return tostring(a.name) < tostring(b.name)
        end)
        return { rows = rows, totals = totals, limit = ES.Limit(),
            owned = totals.business }
    end

    function ES.OpenCabinet(ply)
        if not IsValid(ply) then return false end
        net.Start(NET_CABINET)
            net.WriteTable(ES.CabinetData(ply))
        net.Send(ply)
        return true
    end

    --[[ Снять кассу со ВСЕХ своих объектов разом: главный смысл кабинета.
         Долги гасятся по каждому объекту отдельно, как и при обычном сборе. ]]
    function ES.CollectAll(ply)
        if not IsValid(ply) then return false, "Нет игрока" end
        local key = ownerKeyOf(ply)
        local P = GRM.Property
        local total, paid, count = 0, 0, 0
        for _, rec in pairs((P and P.Records) or {}) do
            if ES.IsBusiness(rec) and tostring(rec.ownerType or "") == "character"
                and tostring(rec.ownerKey or "") == key then
                local before = ES.CashInZone(rec)
                if before > 0 then
                    local debtBefore = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0))
                    local ok = ES.Collect(ply, rec)
                    if ok then
                        count = count + 1
                        local debtAfter = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0))
                        local covered = debtBefore - debtAfter
                        paid = paid + covered
                        total = total + (before - covered)
                    end
                end
            end
        end
        if count == 0 then return false, "Во всех объектах касса пуста" end
        if paid > 0 then
            return true, ("Собрано %d GRM с %d объектов · погашено долгов %d GRM"):format(total, count, paid)
        end
        return true, ("Собрано %d GRM с %d объектов"):format(total, count)
    end

    net.Receive(NET_CABINET, function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "estate.cabinet", { rate = 0.5, burst = 3 }, {}) then return end
        local action = net.ReadString()
        if action == "collect_all" then
            local ok, msg = ES.CollectAll(ply)
            if GRM.Notify then
                GRM.Notify(ply, tostring(msg), ok and 100 or 255, ok and 215 or 150, ok and 125 or 110)
            end
        end
        ES.OpenCabinet(ply)
    end)

    concommand.Add("grm_cabinet", function(ply) ES.OpenCabinet(ply) end)

    --- Диагностика: grm_estate
    concommand.Add("grm_estate", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function say(t)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, t) else print(t) end
        end
        local P = GRM.Property
        say("[Недвижимость] версия " .. ES.Version .. ", лимит бизнесов: " .. ES.Limit())
        if not (P and istable(P.Records)) then say("  Модуль недвижимости не загружен.") return end
        local n = 0
        for _, rec in pairs(P.Records) do
            local kind = ES.KindOf(rec)
            if kind ~= "none" then
                n = n + 1
                say(("  [%s] %s — %s · %d м² · %s"):format(
                    kind == "business" and "БИЗНЕС" or "ЖИЛЬЁ",
                    tostring(rec.name or ""),
                    ES.IsVacant(rec) and "свободно" or ("владелец: " .. tostring(rec.ownerName or "")),
                    ES.ZoneArea(rec),
                    kind == "business" and ES.EquipmentSummary(rec) or "—"))
            end
        end
        if n == 0 then say("  Объектов с зонами нет.") end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("estate", {
            label = "Бизнес и жильё",
            version = ES.Version,
            Refresh = function(ply) ES.Sync(ply) end,
            Status = function()
                local n = 0
                for _, rec in pairs((GRM.Property and GRM.Property.Records) or {}) do
                    if ES.KindOf(rec) ~= "none" then n = n + 1 end
                end
                return "объектов: " .. n
            end,
            Depends = { "property" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ: вращающиеся значки над зонами
-----------------------------------------------------------------------
if CLIENT then
    ES.Zones = ES.Zones or {}

    surface.CreateFont("GRMEstate_Label", { font = "Roboto", size = 22, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMEstate_Sub",   { font = "Roboto", size = 16, weight = 500, extended = true, antialias = true })

    net.Receive("GRM_Estate_Sync", function()
        local rawLen = net.ReadUInt(32)
        local len = net.ReadUInt(32)
        local data = net.ReadData(len)
        local txt = util.Decompress(data, rawLen + 64) or ""
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        ES.Zones = (ok and istable(t)) and t or {}
        -- Модели значков пересоздаём под новый список.
        ES._markers = nil
        hook.Run("GRM_EstateSynced")
    end)

    --[[ ЗАПАСНАЯ ЭМБЛЕМА для зон без дверей.

         Клиентские модели создаём ТОЛЬКО для таких объектов. У зон с
         дверью вместо модели рисуется плоская табличка (см. ниже), и
         держать для неё ClientsideModel незачем — именно эта модель на
         скриншотах владельца врезалась в потолок подъезда. ]]
    local function ensureMarkers()
        if ES._markers then return ES._markers end
        local out = {}
        --[[ Чистый белый материал: только с ним умножение на цвет даёт
             ровно заданный оттенок, а не подкрашенную текстуру логотипа. ]]
        local mat = Material(ES.MarkerMaterial)
        for _, zone in ipairs(ES.Zones or {}) do
            if not zone.onDoor then
                local mdl = ClientsideModel(ES.MarkerModel, RENDERGROUP_TRANSLUCENT)
                if IsValid(mdl) then
                    mdl:SetNoDraw(true)
                    mdl:SetPos(Vector(zone.pos.x, zone.pos.y, zone.pos.z))
                    local scale = ES.MarkerScale[zone.kind] or 0.2
                    mdl:SetModelScale(scale, 0)
                    if mat and not mat:IsError() then mdl:SetMaterial(ES.MarkerMaterial) end
                    out[#out + 1] = { ent = mdl, zone = zone }
                end
            end
        end
        ES._markers = out
        return out
    end

    surface.CreateFont("GRMEstate_Plaque",    { font = "Roboto", size = 46, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMEstate_PlaqueSub", { font = "Roboto", size = 30, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMEstate_PlaqueHint",{ font = "Roboto", size = 24, weight = 500, extended = true, antialias = true })

    --[[ ТАБЛИЧКА НАД ДВЕРЬЮ (переделка дизайна 28.08 по скриншотам).

         Рисуем в 3D2D прямо в плоскости стены. Что это чинит:

           • вывеска ПЛОСКАЯ — ей нечем врезаться в потолок, в отличие
             от объёмного логотипа;
           • она в мире, а не в HUD, значит стена её честно перекрывает:
             больше не видно надписей от соседних квартир сквозь бетон;
           • не вращается — текст читается всегда;
           • название, статус и цена в одном блоке, как настоящая
             табличка у входа.

         Рисуем в PostDrawTranslucentRenderables: там уже есть тест
         глубины по миру, поэтому перекрытие стенами достаётся даром. ]]
    --[[ ГДЕ ИМЕННО ЛЕЖИТ ПЛАШКА НА ПОЛОТНЕ.

         Считаем в СОБСТВЕННЫХ углах двери, как торговый автомат считает
         свою переднюю грань. Возвращает точку, угол и сторону, с которой
         эта плашка видна.

         Дверь — вытянутая тонкая коробка. Какая ось у неё «толщина»,
         зависит от того, как её поставил маппер, поэтому не гадаем:
         берём OBB и объявляем лицевой ту горизонтальную ось, по которой
         размер МЕНЬШЕ. Промахнуться тут — значит положить табличку на
         торец полотна, шириной в пару сантиметров. ]]
    local function doorPlaqueFrame(door, sideHint)
        if not IsValid(door) then return nil end
        local mins, maxs = door:OBBMins(), door:OBBMaxs()
        local sx, sy = maxs.x - mins.x, maxs.y - mins.y

        local ang = door:GetAngles()
        local localPos, normal

        --[[ Высота: чуть выше середины полотна, как табличка с номером
             квартиры. Берём долю, а не константу: двери бывают разной
             высоты, от подъездной до гаражных ворот. ]]
        local hz = mins.z + (maxs.z - mins.z) * 0.62

        if sx < sy then
            -- Толщина по X: лицевые грани смотрят вдоль ±X.
            local face = (sideHint >= 0) and (maxs.x + 0.5) or (mins.x - 0.5)
            localPos = Vector(face, (mins.y + maxs.y) * 0.5, hz)
            normal = door:GetForward() * (sideHint >= 0 and 1 or -1)
            ang:RotateAroundAxis(ang:Up(), sideHint >= 0 and 90 or -90)
            ang:RotateAroundAxis(ang:Forward(), 90)
        else
            -- Толщина по Y: лицевые грани смотрят вдоль ±Y.
            local face = (sideHint >= 0) and (maxs.y + 0.5) or (mins.y - 0.5)
            localPos = Vector((mins.x + maxs.x) * 0.5, face, hz)
            normal = door:GetRight() * (sideHint >= 0 and 1 or -1)
            ang:RotateAroundAxis(ang:Up(), sideHint >= 0 and 180 or 0)
            ang:RotateAroundAxis(ang:Forward(), 90)
        end

        return door:LocalToWorld(localPos), ang, normal
    end

    --[[ ТАБЛИЧКА НА ДВЕРИ (переделка 28.08 по просьбе владельца:
         «лучше чтобы таблички были не над дверями, а НА дверях, как это
         сделано с автоматами с едой»).

         Что это меняет против прошлой версии:

           • плашка лежит на самом полотне, а не в стене над проёмом —
             над дверью почти всегда балка или косяк, и вывеска налезала
             на них;
           • она едет вместе с дверью, когда та открывается. Раньше
             оставалась висеть в воздухе;
           • ориентация берётся у самой двери, а не считается от границы
             зоны, поэтому косые и нестандартно поставленные двери тоже
             получают ровную табличку;
           • видна с обеих сторон полотна: снаружи и из подъезда. Сторону
             выбираем по тому, где стоит игрок.

         Рисуем в PostDrawTranslucentRenderables: там есть тест глубины
         по миру, поэтому перекрытие стенами достаётся даром. ]]
    -- Кадровые краски и скретч-объекты плашек/подписей: создаются один раз
    -- при загрузке, поля скретча пишутся строго перед употреблением
    -- (GMod-Color это таблица, Vector/Angle — мутируемые struct'ы; §6.1.8)
    local COL_PLAQUE_BG = Color(16, 20, 28, 235)
    local COL_PLAQUE_STATUS = Color(214, 224, 236)
    local COL_GOLD_HINT = Color(255, 226, 130)
    local COL_LABEL_STATUS = Color(210, 220, 232)
    local COL_LABEL_OUT_TITLE = Color(0, 0, 0, 220)
    local COL_LABEL_OUT_STATUS = Color(0, 0, 0, 200)
    local COL_LABEL_OUT_HINT = Color(0, 0, 0, 210)
    local PLAQUE_TINT = Color(255, 255, 255)
    local PLAQUE_POS = Vector(0, 0, 0)
    local PLAQUE_ANG = Angle(0, 0, 90)
    local LABEL_POS = Vector(0, 0, 0)
    local MARKER_ANG = Angle(0, 0, 0)
    local BTN_DISABLED = Color(70, 78, 92)
    local BTN_HOVER = Color(0, 0, 0)

    local function drawPlaque(zone, eyePos)
        local door = zone.door and zone.door > 0 and Entity(zone.door) or nil
        local pos, ang

        if IsValid(door) then
            --[[ С какой стороны полотна стоит игрок — ту грань и
                 показываем. Пробуем лицевую, и если игрок сзади, берём
                 обратную: табличка нужна и снаружи, и изнутри. ]]
            local center = door:LocalToWorld(door:OBBCenter())
            local mins, maxs = door:OBBMins(), door:OBBMaxs()
            local axis = ((maxs.x - mins.x) < (maxs.y - mins.y))
                and door:GetForward() or door:GetRight()
            local side = (eyePos - center):Dot(axis) >= 0 and 1 or -1
            pos, ang = doorPlaqueFrame(door, side)
        end

        --[[ Двери нет (не доехала до клиента или её снесли) — не бросаем
             объект без подписи: рисуем по присланной точке. ]]
        if not pos then
            PLAQUE_POS.x = zone.pos.x
            PLAQUE_POS.y = zone.pos.y
            PLAQUE_POS.z = zone.pos.z
            pos = PLAQUE_POS
            ang = PLAQUE_ANG
        end

        local dist = eyePos:DistToSqr(pos)
        if dist > ES.DrawDistance ^ 2 then return end

        local col = ES.ZoneColor(zone)

        --[[ Далёкие таблички не рисуем текстом: мелкие буквы всё равно
             не читаются, а 3D2D дорогой. Вместо этого — цветной огонёк,
             чтобы объект было видно издалека. ]]
        if dist > ES.PlaqueDistance ^ 2 then
            PLAQUE_TINT.r = col.r
            PLAQUE_TINT.g = col.g
            PLAQUE_TINT.b = col.b
            PLAQUE_TINT.a = 190
            cam.Start3D2D(pos, ang, 0.25)
                draw.RoundedBox(16, -60, -30, 120, 60, PLAQUE_TINT)
            cam.End3D2D()
            return
        end

        local title, status, hint = ES.PlaqueLines(zone)

        --[[ Масштаб подобран так, чтобы плашка занимала ES.PlaqueWidth
             юнитов по ширине: рисуем в «экранных» координатах 0..W и
             сжимаем. Так шрифты остаются чёткими.

             Ширину держим меньше дверного полотна (оно около 48 юнитов),
             иначе табличка торчала бы за края двери. ]]
        local W, H = 420, 176
        local scale = ES.PlaqueWidth / W

        cam.Start3D2D(pos, ang, scale)
            -- Подложка: тёмная, чтобы текст читался на любой двери.
            draw.RoundedBox(10, -W / 2, -H / 2, W, H, COL_PLAQUE_BG)
            -- Цветная полоса сверху — вид объекта видно мгновенно.
            PLAQUE_TINT.r = col.r
            PLAQUE_TINT.g = col.g
            PLAQUE_TINT.b = col.b
            PLAQUE_TINT.a = 255
            draw.RoundedBox(10, -W / 2, -H / 2, W, 8, PLAQUE_TINT)
            surface.SetDrawColor(col.r, col.g, col.b, 90)
            surface.DrawOutlinedRect(-W / 2, -H / 2, W, H, 3)

            draw.SimpleText(title, "GRMEstate_Plaque", 0, -H / 2 + 42,
                col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(status, "GRMEstate_PlaqueSub", 0, -H / 2 + 88,
                COL_PLAQUE_STATUS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if hint then
                draw.SimpleText("Чтобы купить — напишите " .. hint,
                    "GRMEstate_PlaqueHint", 0, -H / 2 + 130,
                    COL_GOLD_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    hook.Add("PostDrawTranslucentRenderables", "GRM_Estate_Markers", function(depth, sky)
        if depth or sky then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end

        local eyePos = EyePos()

        --[[ Сначала таблички на дверях: их большинство. Проверку «с
             лицевой ли стороны игрок» больше не делаем здесь — плашка
             сама поворачивается к той грани полотна, с которой на неё
             смотрят. ]]
        for _, zone in ipairs(ES.Zones or {}) do
            if zone.onDoor and zone.pos then
                drawPlaque(zone, eyePos)
            end
        end

        -- Затем прежние эмблемы — только для зон без дверей.
        local markers = ensureMarkers()
        for _, row in ipairs(markers) do
            local ent, zone = row.ent, row.zone
            if IsValid(ent) then
                local pos = ent:GetPos()
                if eyePos:DistToSqr(pos) <= ES.DrawDistance ^ 2 then
                    local col = ES.ZoneColor(zone)
                    --[[ Ровное вращение вокруг своей оси, одинаковое для
                         всех и независимое от камеры. Roll держит логотип
                         вертикально, чтобы он не лежал «крышей». ]]
                    MARKER_ANG.y = (CurTime() * ES.MarkerSpin) % 360
                    MARKER_ANG.r = ES.MarkerRoll
                    ent:SetAngles(MARKER_ANG)
                    render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
                    ent:DrawModel()
                    render.SetColorModulation(1, 1, 1)
                end
            end
        end
    end)

    --[[ Подпись через HUD осталась ТОЛЬКО для зон без дверей.

         Для дверей она убрана намеренно: HUDPaint рисует поверх всего,
         игнорируя стены, и на скриншотах владельца было видно текст
         соседних квартир прямо сквозь бетон. У таблички этой болезни
         нет — она честная геометрия в мире. ]]
    hook.Add("HUDPaint", "GRM_Estate_Labels", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        if GRM.AugHUD and GRM.AugHUD.IsActive and GRM.AugHUD.IsActive() then return end
        local eyePos = EyePos()

        for _, zone in ipairs(ES.Zones or {}) do
            if not zone.onDoor then
                local pos = LABEL_POS
                pos.x = zone.pos.x
                pos.y = zone.pos.y
                pos.z = zone.pos.z
                local dist = eyePos:DistToSqr(pos)
                if dist <= (ES.DrawDistance * 0.55) ^ 2 then
                    --[[ Подпись ставим НАД значком, а не под ним: после
                         опускания эмблемы почти к центру зоны сдвиг вниз
                         увёл бы текст под пол. ]]
                    pos.z = pos.z + 18
                    local screen = pos:ToScreen()
                    if screen.visible then
                        local col = ES.ZoneColor(zone)
                        local title, status, hint = ES.PlaqueLines(zone)
                        draw.SimpleTextOutlined(title, "GRMEstate_Label", screen.x, screen.y,
                            col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, COL_LABEL_OUT_TITLE)
                        draw.SimpleTextOutlined(status, "GRMEstate_Sub", screen.x, screen.y + 20,
                            COL_LABEL_STATUS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, COL_LABEL_OUT_STATUS)
                        if hint then
                            draw.SimpleTextOutlined("Чтобы купить — напишите " .. hint,
                                "GRMEstate_Sub", screen.x, screen.y + 38,
                                COL_GOLD_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                                1, COL_LABEL_OUT_HINT)
                        end
                    end
                end
            end
        end
    end)

    -----------------------------------------------------------------
    -- ОКНО ОБЪЕКТА: касса, доход, долг
    -----------------------------------------------------------------
    surface.CreateFont("GRMEstate_Head",  { font = "Roboto", size = 21, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMEstate_Val",   { font = "Roboto", size = 26, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMEstate_Row",   { font = "Roboto", size = 14, weight = 500, extended = true, antialias = true })

    local UI = {
        bg     = Color(18, 23, 32, 250),
        panel  = Color(30, 38, 51, 245),
        gold   = Color(245, 200, 60),
        green  = Color(70, 200, 120),
        red    = Color(215, 85, 75),
        text   = Color(238, 243, 250),
        dim    = Color(155, 168, 186),
    }

    local panelFrame

    local function estateButton(parent, text, col, w, h)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        if w and h then b:SetSize(w, h) end
        b.Paint = function(self, pw, ph)
            local c = col
            if not self:IsEnabled() then c = BTN_DISABLED
            elseif self:IsHovered() then
                BTN_HOVER.r = math.min(255, col.r + 26)
                BTN_HOVER.g = math.min(255, col.g + 26)
                BTN_HOVER.b = math.min(255, col.b + 26)
                BTN_HOVER.a = 255
                c = BTN_HOVER
            end
            draw.RoundedBox(6, 0, 0, pw, ph, c)
            draw.SimpleText(text, "GRMEstate_Row", pw / 2, ph / 2, color_white,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return b
    end

    net.Receive("GRM_Estate_Panel", function()
        local d = net.ReadTable() or {}
        if IsValid(panelFrame) then panelFrame:Remove() end

        local isBiz = d.kind == "business"
        local h = isBiz and 440 or 300
        local f = vgui.Create("DFrame")
        panelFrame = f
        f:SetSize(460, h) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("estate.panel", f) end
        f.Paint = function(_, w, hh)
            draw.RoundedBox(10, 0, 0, w, hh, UI.bg)
            draw.RoundedBoxEx(10, 0, 0, w, 56, UI.panel, true, true, false, false)
            local col = isBiz and UI.gold or UI.green
            draw.SimpleText(tostring(d.name or ""), "GRMEstate_Head", 20, 16, col)
            local sub = (isBiz and "Бизнес" or "Жильё") .. "  ·  " .. tostring(d.area or 0) .. " м²"
            if d.vacant then
                sub = sub .. "  ·  СВОБОДНО"
            elseif tostring(d.owner or "") ~= "" then
                sub = sub .. "  ·  " .. d.owner
            end
            draw.SimpleText(sub, "GRMEstate_Row", 20, 38, UI.dim)
        end

        local close = estateButton(f, "ЗАКРЫТЬ", UI.red, 96, 26)
        close:SetPos(348, 15)
        close.DoClick = function() f:Remove() end

        local y = 72
        local function row(label, value, col)
            local p = vgui.Create("DPanel", f)
            p:SetPos(16, y) p:SetSize(428, 34)
            p.Paint = function(_, w, hh)
                draw.RoundedBox(6, 0, 0, w, hh, UI.panel)
                draw.SimpleText(label, "GRMEstate_Row", 12, hh / 2, UI.dim,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(value, "GRMEstate_Row", w - 12, hh / 2, col or UI.text,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            y = y + 40
        end

        if isBiz then
            -- Касса крупно: это главное, зачем сюда заходят.
            local cashPnl = vgui.Create("DPanel", f)
            cashPnl:SetPos(16, y) cashPnl:SetSize(428, 62)
            cashPnl.Paint = function(_, w, hh)
                draw.RoundedBox(6, 0, 0, w, hh, UI.panel)
                draw.SimpleText("В КАССЕ", "GRMEstate_Row", 14, 12, UI.dim)
                draw.SimpleText(tostring(d.cash or 0) .. " GRM", "GRMEstate_Val", 14, 30,
                    (d.cash or 0) > 0 and UI.green or UI.dim)
            end
            y = y + 70

            row("Оборудование", (d.equipment or 0) > 0 and tostring(d.summary) or "нет", UI.text)
            row("Продано за всё время", tostring(d.sold or 0) .. " шт.", UI.text)
            row("Заработано всего", tostring(d.earned or 0) .. " GRM", UI.text)
            row("Примерно в сутки", tostring(d.daily or 0) .. " GRM", UI.text)
            if (d.debt or 0) > 0 then
                --[[ Долг показываем отдельно: при снятии он гасится первым,
                     и владелец должен понимать, почему получил меньше. ]]
                local extra = (d.penalty or 0) > 0 and ("  (пеня " .. d.penalty .. ")") or ""
                row("Долг по коммунальным", tostring(d.debt) .. " GRM" .. extra, UI.red)
            end
        else
            row("Площадь", tostring(d.area or 0) .. " м²", UI.text)
            row("Точка входа", "доступна при заходе в игру", UI.green)
            if (d.debt or 0) > 0 then
                row("Долг по коммунальным", tostring(d.debt) .. " GRM", UI.red)
            end
        end

        local function act(name, extra)
            net.Start("GRM_Estate_Act")
                net.WriteString(name)
                net.WriteString(tostring(d.id or ""))
                if extra then extra() end
            net.SendToServer()
        end

        if d.isOwner then
            -- Владелец: касса, продажа государству и выставление на рынок.
            local bx = 16
            if isBiz then
                local collect = estateButton(f, "СНЯТЬ КАССУ", UI.green, 210, 36)
                collect:SetPos(16, h - 92)
                collect:SetEnabled((d.cash or 0) > 0)
                collect.DoClick = function() act("collect") end
                bx = 234
            end

            local state = estateButton(f, "ПРОДАТЬ ГОСУДАРСТВУ", UI.panel, isBiz and 210 or 428, 36)
            state:SetPos(bx, h - 92)
            state.DoClick = function()
                Derma_Query(("Продать «%s» государству за %d GRM?\nЭто примерно %d%% от цены объекта."):format(
                        tostring(d.name or ""), d.stateOffer or 0, 60),
                    "Продажа объекта", "Продать", function() act("sell_state") end,
                    "Отмена", function() end)
            end

            if (d.forSale or 0) > 0 then
                --[[ Объект уже на рынке: показываем цену и даём снять
                     с продажи одним нажатием. ]]
                local off = estateButton(f, "СНЯТЬ С ПРОДАЖИ (" .. d.forSale .. " GRM)", UI.red, 428, 36)
                off:SetPos(16, h - 50)
                off.DoClick = function() act("sale_off") end
            else
                local sell = estateButton(f, "ВЫСТАВИТЬ НА ПРОДАЖУ", UI.gold, 428, 36)
                sell:SetPos(16, h - 50)
                sell.DoClick = function()
                    Derma_StringRequest("Продажа объекта",
                        "Цена в GRM. Покупатель найдёт объект по синему значку и в /market.",
                        tostring(d.price or 0),
                        function(txt)
                            local price = math.max(0, math.floor(tonumber(txt) or 0))
                            act("sale_on", function() net.WriteUInt(price, 32) end)
                        end)
                end
            end
        elseif (d.forSale or 0) > 0 then
            -- Объект продаётся другим игроком: можно выкупить прямо тут.
            local buy = estateButton(f, "КУПИТЬ ЗА " .. d.forSale .. " GRM", UI.green, 428, 38)
            buy:SetPos(16, h - 52)
            buy.DoClick = function() act("buy") end
        elseif d.vacant then
            local hint = vgui.Create("DLabel", f)
            hint:SetPos(16, h - 46) hint:SetSize(428, 32)
            hint:SetFont("GRMEstate_Row") hint:SetTextColor(UI.dim) hint:SetWrap(true)
            hint:SetText("Объект свободен. Цена: " .. tostring(d.price or 0)
                .. " GRM. Купить можно у одной из дверей объекта или внутри зоны.")
        end
    end)

    -----------------------------------------------------------------
    -- КАБИНЕТ: все объекты игрока в одном окне
    -----------------------------------------------------------------
    local cabinetFrame

    net.Receive("GRM_Estate_Cabinet", function()
        local d = net.ReadTable() or {}
        local rows = istable(d.rows) and d.rows or {}
        local totals = istable(d.totals) and d.totals or {}
        if IsValid(cabinetFrame) then cabinetFrame:Remove() end

        local f = vgui.Create("DFrame")
        cabinetFrame = f
        f:SetSize(620, 520) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("estate.cabinet", f) end
        f.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, UI.bg)
            draw.RoundedBoxEx(10, 0, 0, w, 76, UI.panel, true, true, false, false)
            draw.SimpleText("МОИ ОБЪЕКТЫ", "GRMEstate_Head", 20, 14, UI.gold)
            -- Общий доход крупно: главная цифра, ради которой сюда заходят.
            draw.SimpleText("Доход в сутки: " .. tostring(totals.daily or 0) .. " GRM",
                "GRMEstate_Row", 20, 42, UI.green)
            draw.SimpleText(("бизнесов %d из %d  ·  жильё %d"):format(
                totals.business or 0, d.limit or 3, totals.estate or 0),
                "GRMEstate_Row", 20, 58, UI.dim)
            draw.SimpleText("В КАССАХ", "GRMEstate_Row", w - 20, 20, UI.dim, TEXT_ALIGN_RIGHT)
            draw.SimpleText(tostring(totals.cash or 0) .. " GRM", "GRMEstate_Val", w - 20, 38,
                (totals.cash or 0) > 0 and UI.green or UI.dim, TEXT_ALIGN_RIGHT)
        end

        local close = estateButton(f, "ЗАКРЫТЬ", UI.red, 96, 26)
        close:SetPos(510, 44)
        close.DoClick = function() f:Remove() end

        local scroll = vgui.Create("DScrollPanel", f)
        scroll:SetPos(16, 88) scroll:SetSize(588, 380)

        if #rows == 0 then
            local empty = vgui.Create("DLabel", scroll)
            empty:Dock(TOP) empty:SetTall(60) empty:SetWrap(true)
            empty:SetFont("GRMEstate_Row") empty:SetTextColor(UI.dim)
            empty:SetText("У вас пока нет объектов.\n\nСвободные помечены синим значком на карте: "
                .. "подойдите и нажмите /business, чтобы купить. Что продают игроки — в /market.")
        end

        for _, row in ipairs(rows) do
            local isBiz = row.kind == "business"
            local card = vgui.Create("DPanel", scroll)
            card:Dock(TOP) card:SetTall(isBiz and 78 or 58) card:DockMargin(0, 0, 6, 8)
            card.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, UI.panel)
                -- Полоса слева цветом вида: бизнес жёлтый, жильё зелёное.
                draw.RoundedBox(2, 0, 0, 4, h, isBiz and UI.gold or UI.green)
                draw.SimpleText(tostring(row.name or ""), "GRMEstate_Row", 14, 12,
                    UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local meta = (isBiz and "Бизнес" or "Жильё") .. "  ·  " .. tostring(row.area or 0) .. " м²"
                if isBiz and (row.equipment or 0) > 0 then
                    meta = meta .. "  ·  " .. tostring(row.summary)
                end
                if row.tenure == "rent" then
                    meta = meta .. "  ·  аренда: " .. tostring(row.rentLeft or 0) .. " ч"
                end
                draw.SimpleText(meta, "GRMEstate_Row", 14, 32, UI.dim,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                if isBiz then
                    draw.SimpleText("касса " .. tostring(row.cash or 0) .. " GRM",
                        "GRMEstate_Row", 14, 56,
                        (row.cash or 0) > 0 and UI.green or UI.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("в сутки ~" .. tostring(row.daily or 0) .. " GRM",
                        "GRMEstate_Row", 190, 56, UI.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                -- Долг и продажа — справа, чтобы бросались в глаза.
                if (row.debt or 0) > 0 then
                    draw.SimpleText("долг " .. tostring(row.debt) .. " GRM", "GRMEstate_Row",
                        w - 14, 12, UI.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
                if (row.forSale or 0) > 0 then
                    draw.SimpleText("продаётся: " .. tostring(row.forSale) .. " GRM",
                        "GRMEstate_Row", w - 14, 32, Color(90, 170, 255),
                        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end

        --[[ Сбор со всех объектов разом — то, ради чего кабинет и нужен:
             больше не надо обходить карту и снимать кассы по одной. ]]
        local collectAll = estateButton(f, "СОБРАТЬ КАССЫ СО ВСЕХ ОБЪЕКТОВ", UI.green, 588, 38)
        collectAll:SetPos(16, 474)
        collectAll:SetEnabled((totals.cash or 0) > 0)
        collectAll.DoClick = function()
            net.Start("GRM_Estate_Cabinet")
                net.WriteString("collect_all")
            net.SendToServer()
        end
    end)

    --- Уборка моделей при выгрузке.
    hook.Add("ShutDown", "GRM_Estate_Cleanup", function()
        for _, row in ipairs(ES._markers or {}) do
            if IsValid(row.ent) then row.ent:Remove() end
        end
        ES._markers = nil
    end)
end
