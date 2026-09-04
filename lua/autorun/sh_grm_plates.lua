--[[--------------------------------------------------------------------
    GRM Plates v1.0.0 — регистрационные номерные знаки на транспорт
    (заказ владельца 21.08).

    Логика жизни знака:
      1. РЕГИСТРАЦИЯ. Сотрудник Полиции / Дорожной инспекции / ВАИ через
         терминал (вкладка «Номерные знаки») или командой выдаёт владельцу
         регистрационный номер. Номер попадает в единый реестр: серия, тип,
         владелец, кто выдал, когда, статус.
      2. ПОЛУЧЕНИЕ БЛАНКА. Владелец (или сотрудник) получает ФИЗИЧЕСКИЙ знак
         — энтити grm_plate на модели models/hunter/plates/plate025x075.mdl
         с материалом models/debug/debugwhite и напечатанным номером.
         Знаков можно взять два — передний и задний.
      3. УСТАНОВКА РУКАМИ. Знак ставится физганом куда нужно (бампер спереди,
         багажник сзади) и закрепляется нажатием [E]: он приваривается к
         транспорту с сохранением локальной позиции. Повторное [E] снимает.
      4. ПРОВЕРКА. Сотрудник видит номер над транспортом, пробивает его
         командой или в терминале: чей, какой тип, статус, на чём стоял.
      5. АННУЛИРОВАНИЕ / УТЕРЯ. Номер можно аннулировать (знак становится
         красным «АННУЛИРОВАН») или заявить об утере.

    Хранение: data/grm_plates/registry.json через очередь GRM.Save.
    Позиции закреплённых знаков хранятся в записи гаража, поэтому знаки
    возвращаются на место после выдачи машины из гаража.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Plates = GRM.Plates or {}
local PL = GRM.Plates
PL.Version = "1.0.0"

PL.Model    = "models/hunter/plates/plate025x075.mdl"
PL.Material = "models/debug/debugwhite"

PL.Net = {
    OPEN = "GRM_Plates_Open",
    SYNC = "GRM_Plates_Sync",
    ACT  = "GRM_Plates_Act",
    RENDER = "GRM_Plates_Render",   -- раскладка надписи на знаке
}

-----------------------------------------------------------------------
-- ТИПЫ ЗНАКОВ
-- pattern: A — буква из PL.Letters, 0 — цифра. Разбивка group — как
-- показывать номер человеку (по сколько символов ставить пробел).
-----------------------------------------------------------------------
PL.Letters = "АВЕКМНОРСТУХ"   -- буквы, читаемые и латиницей, и кириллицей

PL.Types = {
    civil = {
        name = "Гражданский", order = 10, pattern = "A000AA", groups = { 1, 3, 2 },
        plate = { 250, 250, 250 }, text = { 20, 20, 24 }, band = { 40, 70, 140 },
    },
    commercial = {
        name = "Коммерческий", order = 20, pattern = "AA0000", groups = { 2, 4 },
        plate = { 250, 225, 120 }, text = { 25, 25, 25 }, band = { 120, 90, 30 },
    },
    gov = {
        name = "Государственный", order = 30, pattern = "0000AA", groups = { 4, 2 },
        plate = { 235, 240, 250 }, text = { 20, 40, 100 }, band = { 30, 60, 120 },
    },
    police = {
        name = "Полицейский", order = 40, pattern = "A0000", groups = { 1, 4 },
        plate = { 60, 90, 160 }, text = { 245, 248, 255 }, band = { 25, 45, 95 },
    },
    military = {
        name = "Военный", order = 50, pattern = "0000AA", groups = { 4, 2 },
        plate = { 60, 80, 55 }, text = { 240, 245, 235 }, band = { 30, 45, 28 },
    },
    transit = {
        name = "Транзитный", order = 60, pattern = "AA000", groups = { 2, 3 },
        plate = { 240, 240, 240 }, text = { 160, 40, 40 }, band = { 150, 60, 40 },
    },
}

PL.Statuses = {
    active  = "действителен",
    revoked = "аннулирован",
    lost    = "заявлен утерянным",
    seized  = "изъят",
}

function PL.TypeList()
    local out = {}
    for key, def in pairs(PL.Types) do
        out[#out + 1] = { key = key, name = def.name, order = def.order or 100, pattern = def.pattern }
    end
    table.sort(out, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    return out
end

function PL.TypeDef(kind)
    return PL.Types[tostring(kind or "")] or PL.Types.civil
end

-----------------------------------------------------------------------
-- НОМЕР: НОРМАЛИЗАЦИЯ, ПРОВЕРКА, ГЕНЕРАЦИЯ (чистые функции)
-----------------------------------------------------------------------

--- Верхний регистр с кириллицей (string.upper знает только латиницу).
local function upperRU(s)
    s = string.upper(tostring(s or ""))
    if not string.find(s, "\208", 1, true) and not string.find(s, "\209", 1, true) then return s end
    s = string.gsub(s, "\208([\176-\191])", function(c) return "\208" .. string.char(string.byte(c) - 32) end)
    s = string.gsub(s, "\209([\128-\143])", function(c) return "\208" .. string.char(string.byte(c) + 32) end)
    s = string.gsub(s, "\209\145", "\208\129")
    return s
end
PL.Upper = upperRU

--- Латиница, похожая на кириллицу, приводится к кириллице: игрок набирает
--  «A123BC» в любой раскладке — база всё равно находит знак.
local LATIN_TO_RU = {
    A = "А", B = "В", E = "Е", K = "К", M = "М", H = "Н",
    O = "О", P = "Р", C = "С", T = "Т", Y = "У", X = "Х",
}

--- Символы номера как массив (UTF-8: кириллица — два байта).
local function chars(s)
    local out, i = {}, 1
    while i <= #s do
        local b = string.byte(s, i)
        local len = 1
        if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
        out[#out + 1] = string.sub(s, i, i + len - 1)
        i = i + len
    end
    return out
end
PL.Chars = chars

--- Номер в каноническом виде: без пробелов, верхний регистр, кириллица.
function PL.NormalizeNumber(raw)
    local s = upperRU(tostring(raw or ""))
    s = string.gsub(s, "[%s%-_·]", "")
    local out = {}
    for _, ch in ipairs(chars(s)) do
        out[#out + 1] = LATIN_TO_RU[ch] or ch
    end
    return table.concat(out)
end

local function letterSet()
    local set = {}
    for _, ch in ipairs(chars(PL.Letters)) do set[ch] = true end
    return set
end

--- Проверка номера по шаблону типа. Возвращает: ок, причина.
function PL.ValidNumber(number, kind)
    number = PL.NormalizeNumber(number)
    if number == "" then return false, "Номер пуст" end
    local def = PL.TypeDef(kind)
    local pat = chars(def.pattern or "A000AA")
    local got = chars(number)
    if #got ~= #pat then
        return false, ("Номер типа «%s» состоит из %d символов"):format(def.name, #pat)
    end
    local letters = letterSet()
    for i, slot in ipairs(pat) do
        local ch = got[i]
        if slot == "0" then
            if not string.match(ch, "^%d$") then return false, ("Позиция %d — цифра"):format(i) end
        else
            if not letters[ch] then
                return false, ("Позиция %d — буква из набора %s"):format(i, PL.Letters)
            end
        end
    end
    return true
end

--- Номер, разбитый пробелами для показа: «А 123 ВС».
function PL.FormatNumber(number, kind)
    number = PL.NormalizeNumber(number)
    local def = PL.TypeDef(kind)
    local groups = def.groups or { #chars(number) }
    local got, out, idx = chars(number), {}, 1
    for _, size in ipairs(groups) do
        local part = {}
        for _ = 1, size do
            if got[idx] then part[#part + 1] = got[idx] end
            idx = idx + 1
        end
        if #part > 0 then out[#out + 1] = table.concat(part) end
    end
    while got[idx] do out[#out + 1] = got[idx] idx = idx + 1 end
    return table.concat(out, " ")
end

--- Сгенерировать свободный номер типа. taken(number) -> true, если занят.
function PL.GenerateNumber(kind, taken, rnd)
    local def = PL.TypeDef(kind)
    local pat = chars(def.pattern or "A000AA")
    local letters = chars(PL.Letters)
    rnd = rnd or math.random
    for _ = 1, 400 do
        local out = {}
        for _, slot in ipairs(pat) do
            if slot == "0" then out[#out + 1] = tostring(rnd(0, 9))
            else out[#out + 1] = letters[rnd(1, #letters)] end
        end
        local number = table.concat(out)
        if not (taken and taken(number)) then return number end
    end
    return nil
end

-----------------------------------------------------------------------
-- ГЕОМЕТРИЯ ЛИЦЕВОЙ СТОРОНЫ ЗНАКА (чистая функция, гоняется в стенде)
--
-- Самая тонкая ось габаритов — толщина знака, её направление и есть
-- нормаль лица. Из двух оставшихся ДЛИННАЯ идёт вдоль строки номера,
-- короткая — вверх. Именно поэтому номер стоит правильно, а не поперёк
-- (первая версия рисовала надпись боком — заказ владельца «повернуть на 90»).
-----------------------------------------------------------------------
--[[ Как лежит надпись на знаке.

     Гадать по габаритам модели оказалось ненадёжно: у plate025x075 «тонкая»
     ось OBB не совпала с видимой плоскостью, и поле знака рисовалось поперёк
     (владелец: «поверни как следует, я не знаю какую координату ты тронул»).

     Поэтому раскладка НАСТРАИВАЕТСЯ и хранится на сервере:
       axis — какая ось модели смотрит «наружу» (auto/x/y/z);
       yaw  — поворот надписи в плоскости знака (0/90/180/270);
       flip — зеркалить (если надпись читается с изнанки);
       scale— размер поля относительно габаритов модели.
     Настраивается прямо в игре командами /номер_поворот, /номер_ось,
     /номер_масштаб — один раз и на все знаки. ]]
PL.Render = PL.Render or {
    axis = "auto",      -- какая ось модели образует плоскость надписи
    yaw = 90,           -- поворот строки в плоскости (0/90/180/270)
    flip = false,       -- зеркало
    scale = 1,          -- размер поля относительно габаритов
    offset = 1.5,       -- вынос НАРУЖУ (перпендикулярно надписи)
    -- тонкая доводка: доворот плоскости и сдвиг вдоль её осей
    tiltP = 0, tiltY = 0, tiltR = 0,   -- наклон / рыскание / крен, градусы
    moveX = 0, moveY = 0,              -- вправо-влево и вверх-вниз по знаку
}

--[[ ПОЧЕМУ РАСПОЗНАВАНИЕ ТРАНСПОРТА СТОИТ ЗДЕСЬ, А НЕ НИЖЕ.
     PL.LayoutFor и PL.ClassFor зовут vehicleBase. Раньше эта функция
     объявлялась на 200 строк ниже, и Lua компилировал обращение к ней
     как ЧТЕНИЕ ГЛОБАЛА: файл грузился без ошибок, а установка знака на
     машину падала с 'attempt to call global vehicleBase (a nil value)'.
     Держим объявление выше всех, кто им пользуется. ]]
-----------------------------------------------------------------------
-- РАСПОЗНАВАНИЕ ТРАНСПОРТА (общее для знака, крепления и проверок)
-----------------------------------------------------------------------
--- Похоже ли это на транспорт (включая simfphys / LVS / Glide).
local function looksLikeVehicle(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("simfphys", 1, true) == 1 or cls:find("lvs_", 1, true) == 1
        or cls:find("prop_vehicle", 1, true) == 1 or cls:find("gmod_sent_vehicle", 1, true) == 1 then
        return true
    end
    return ent.IsSimfphysCar == true or ent.LVS ~= nil or ent.IsGlideVehicle == true
end

--- База машины: у simfphys/LVS сиденье — отдельная энтити.
local function vehicleBase(ent)
    if not IsValid(ent) then return nil end
    local base = ent
    if base.GetBase and IsValid(base:GetBase()) then base = base:GetBase() end
    if base.base and IsValid(base.base) then base = base.base end
    local parent = base:GetParent()
    if IsValid(parent) and looksLikeVehicle(parent) then base = parent end
    -- simfphys прячет реальную машину в списке passengers/spawnlist
    if base.IsVehicle and base:GetClass() == "prop_vehicle_prisoner_pod" then
        for _, key in ipairs({ "vehlist", "vehList", "passengers", "SeatArmor" }) do
            local list = base[key]
            if istable(list) then
                for _, v in ipairs(list) do
                    if IsValid(v) and looksLikeVehicle(v) and not v:IsVehicle() then
                        return v
                    end
                end
            end
        end
    end
    return base
end

--- Истинный класс машины (а не сиденья). Для сохранения раскладки
--  «для всех таких» должен возвращаться, например, simfphys_gta_sa_enforcer,
--  а не gmod_sent_vehicle_fphysics_base.
function PL.ClassFor(ent)
    local base = vehicleBase(ent)
    if not IsValid(base) then return "" end
    local cls = base:GetClass() or ""
    if cls == "prop_vehicle_prisoner_pod" or cls == "gmod_sent_vehicle_fphysics_base"
        or cls == "prop_vehicle_jeep" or cls == "prop_vehicle_airboat" then
        local vehList = isfunction(base.GetNW2String) and base:GetNW2String("veh_list_name", "") or ""
        if vehList ~= "" then return tostring(vehList) end
        -- simfphys/SimfPhys часто хранит SpawnList
        local sl = base.SpawnList
        if isstring(sl) and sl ~= "" then return sl end
        -- последний шанс: имя сущности модели
        local mdl = base:GetModel() or ""
        if mdl ~= "" then local fn = string.GetFileFromFilename and string.GetFileFromFilename(mdl) or mdl return (fn or mdl):lower() end
    end
    return cls
end
PL.VehicleBase = vehicleBase
PL.LooksLikeVehicle = looksLikeVehicle

--- Полный набор ключей раскладки — общий для сервера, клиента и стендов.
PL.RenderKeys = { "axis", "yaw", "flip", "scale", "offset",
    "tiltP", "tiltY", "tiltR", "moveX", "moveY" }

--[[ ПОЛОЖЕНИЕ ЗНАКА НА КОНКРЕТНОЙ МОДЕЛИ (заказ владельца 22.08).
     `PL.Layouts[class]` переопределяет точку крепления для машин этого
     класса: pos — локальная точка, normal — локальная нормаль кормы,
     upHint — локальный «верх». Заполняется командой суперадмина
     `/номер_layout` и сохраняется в render.json вместе с рекладом.
     Пока нет layout — работает автоматика по OBB (надёжная). ]]
PL.Layouts = PL.Layouts or {}

local function normalizeLayout(src)
    src = istable(src) and src or {}
    local function vec(t, def)
        return { x = tonumber(t and t.x) or (def and def.x or 0),
                 y = tonumber(t and t.y) or (def and def.y or 0),
                 z = tonumber(t and t.z) or (def and def.z or 0) }
    end
    return {
        enabled = src.enabled ~= false,
        pos = vec(src.pos, { x = 0, y = 0, z = 0 }),
        normal = vec(src.normal, { x = -1, y = 0, z = 0 }),
        upHint = vec(src.upHint, { x = 0, y = 0, z = 1 }),
    }
end
PL.NormalizeLayout = normalizeLayout

--- Layout по машине: сначала точный класс, потом класс без регистра.
function PL.LayoutFor(veh)
    if not IsValid(veh) then return nil end
    local base = vehicleBase(veh)
    if not IsValid(base) then return nil end
    local class = PL.ClassFor(base)
    local direct = PL.Layouts[class]
    if istable(direct) then return normalizeLayout(direct) end
    local lower = string.lower(class)
    for k, v in pairs(PL.Layouts or {}) do
        if string.lower(tostring(k)) == lower then return normalizeLayout(v) end
    end
    return nil
end

--- Сохранить/сбросить layout класса. Возвращает нормализованный layout.
function PL.SetLayout(class, src)
    class = tostring(class or "")
    if class == "" then return nil end
    if src == nil or src.enabled == false then
        PL.Layouts[class] = nil
        if SERVER and PL.SaveRender then PL.SaveRender() end
        return nil
    end
    local layout = normalizeLayout(src)
    layout.id = class
    PL.Layouts[class] = layout
    if SERVER and PL.SaveRender then PL.SaveRender() end
    return layout
end

--- Нормализация настроек: числа в разумных пределах, ось из списка.
function PL.NormalizeRender(src)
    src = istable(src) and src or {}
    local axis = tostring(src.axis or "auto")
    if axis ~= "x" and axis ~= "y" and axis ~= "z" then axis = "auto" end
    local function num(v, lo, hi, def)
        local n = tonumber(v)
        if n == nil then return def end
        return math.Clamp(n, lo, hi)
    end
    return {
        axis = axis,
        yaw = math.floor(num(src.yaw, 0, 359, 0) / 90 + 0.5) % 4 * 90,
        flip = src.flip == true,
        scale = num(src.scale, 0.2, 3, 1),
        offset = num(src.offset, 0, 12, 1.5),
        tiltP = num(src.tiltP, -180, 180, 0),
        tiltY = num(src.tiltY, -180, 180, 0),
        tiltR = num(src.tiltR, -180, 180, 0),
        moveX = num(src.moveX, -24, 24, 0),
        moveY = num(src.moveY, -24, 24, 0),
    }
end

--- Геометрия лицевой стороны с учётом настроек раскладки.
function PL.FaceGeometry(mins, maxs, render)
    render = istable(render) and render or PL.Render
    local size = maxs - mins
    local center = (mins + maxs) * 0.5
    local dims = { x = math.abs(size.x), y = math.abs(size.y), z = math.abs(size.z) }

    local thin = tostring(render.axis or "auto")
    if thin ~= "x" and thin ~= "y" and thin ~= "z" then
        thin = "x"
        if dims.y < dims[thin] then thin = "y" end
        if dims.z < dims[thin] then thin = "z" end
    end

    local rest = {}
    for _, ax in ipairs({ "x", "y", "z" }) do
        if ax ~= thin then rest[#rest + 1] = ax end
    end
    local long, short = rest[1], rest[2]
    if dims[short] > dims[long] then long, short = short, long end

    -- поворот надписи в плоскости знака: меняем местами оси и знаки
    local yaw = math.floor((tonumber(render.yaw) or 0) / 90 + 0.5) % 4
    local rightAxis, upAxis = long, short
    local rightSign, upSign = 1, 1
    if yaw == 1 then rightAxis, upAxis, rightSign, upSign = short, long, 1, -1
    elseif yaw == 2 then rightSign, upSign = -1, -1
    elseif yaw == 3 then rightAxis, upAxis, rightSign, upSign = short, long, -1, 1 end
    if render.flip then rightSign = -rightSign end

    local unit = { x = Vector(1, 0, 0), y = Vector(0, 1, 0), z = Vector(0, 0, 1) }
    local k = math.Clamp(tonumber(render.scale) or 1, 0.2, 3)
    return {
        center = center,
        normal = unit[thin],
        right = unit[rightAxis] * rightSign,
        up = unit[upAxis] * upSign,
        thin = thin, rightAxis = rightAxis, upAxis = upAxis,
        -- АВТОМАТИКА: две оси плоскости знака как они есть в модели, без
        -- ручных поворотов. Клиент сам решает, какая из них «вдоль строки»,
        -- по тому, как знак стоит в мире (заказ владельца 22.08).
        longAxis = long, shortAxis = short,
        unitLong = unit[long], unitShort = unit[short],
        sizeLong = dims[long], sizeShort = dims[short],
        thickness = dims[thin],
        half = dims[thin] * 0.5,
        -- насколько надпись вынесена НАРУЖУ от поверхности: при нуле она
        -- тонет внутри пропа и её не видно (заказ владельца 21.08)
        offset = math.Clamp(tonumber(render.offset) or 1.5, 0, 12),
        tiltP = tonumber(render.tiltP) or 0,
        tiltY = tonumber(render.tiltY) or 0,
        tiltR = tonumber(render.tiltR) or 0,
        moveX = tonumber(render.moveX) or 0,
        moveY = tonumber(render.moveY) or 0,
        w = dims[rightAxis] * k, h = dims[upAxis] * k,
    }
end

-----------------------------------------------------------------------
-- ПАМЯТЬ КРЕПЛЕНИЯ (чистая часть — гоняется стендом)
--
-- Знак должен вставать ровно туда, куда его поставили: на бампер машины,
-- на щит, на борт пропа. Поэтому крепление хранится не «примерно рядом с
-- машиной», а точными числами: локальная позиция и локальные углы внутри
-- РОДИТЕЛЯ плюс нормаль поверхности, к которой знак прижат. Vector в JSON
-- уходит пустышкой, поэтому всё пишем числами.
-----------------------------------------------------------------------

PL.NudgeLimits = { move = 64, turn = 180 }

--- Пустое крепление с нулями (чтобы не плодить проверок на nil).
function PL.BlankMount()
    return {
        parentType = "", parentKey = "", parentClass = "", parentName = "",
        pos = { x = 0, y = 0, z = 0 },
        ang = { p = 0, y = 0, r = 0 },
        normal = { x = 0, y = 0, z = 0 },
    }
end

--- Привести крепление к нормальному виду (после чтения из файла).
function PL.NormalizeMount(src)
    local m = PL.BlankMount()
    if not istable(src) then return m end
    for _, k in ipairs({ "parentType", "parentKey", "parentClass", "parentName", "vehicle", "vehicleID" }) do
        if src[k] ~= nil then m[k] = tostring(src[k]) end
    end
    -- старые записи: vehicleID был единственным ключом
    if m.parentKey == "" and tostring(src.vehicleID or "") ~= "" then
        m.parentKey, m.parentType = tostring(src.vehicleID), "vehicle"
    end
    if m.parentName == "" and tostring(src.vehicle or "") ~= "" then m.parentName = tostring(src.vehicle) end
    local p, a, n = src.pos, src.ang, src.normal
    if istable(p) then
        m.pos = { x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0 }
    end
    if istable(a) then
        m.ang = { p = tonumber(a.p) or 0, y = tonumber(a.y) or 0, r = tonumber(a.r) or 0 }
    end
    if istable(n) then
        m.normal = { x = tonumber(n.x) or 0, y = tonumber(n.y) or 0, z = tonumber(n.z) or 0 }
    end
    m.at = tonumber(src.at) or 0
    return m
end

--- Подвинуть/повернуть сохранённое крепление. kind: "move" | "turn".
--  Возвращает НОВУЮ таблицу крепления (чистая функция, без побочек).
function PL.NudgeMount(mount, kind, axis, delta, base)
    local m = PL.NormalizeMount(mount)
    delta = tonumber(delta) or 0
    axis = string.lower(tostring(axis or ""))
    if kind == "move" then
        local lim = PL.NudgeLimits.move
        if m.pos[axis] == nil then return m, false end
        --[[ ПРЕДЕЛ СЧИТАЕМ ОТ ТОГО МЕСТА, ГДЕ ЗНАК СТОЯЛ, А НЕ ОТ НУЛЯ
             локальных координат машины (жалоба владельца 31.08:
             «невозможно отодвинуть вперёд или назад сверх лимита»).

             Пока предел ±64 накладывался на саму координату, у любой
             машины длиннее 128 юнитов знак было не вынести на корму:
             pos.x у заднего знака около -110, а первый же шаг
             прибивал его math.Clamp к -64 — ВНУТРЬ кузова. И ровно
             так же по z: знак уезжал на -64, то есть под машину.
             Теперь это предел СМЕЩЕНИЯ от точки, где знак стоял
             перед началом подгонки. ]]
        local lo, hi = -lim, lim
        if istable(base) and istable(base.pos) and tonumber(base.pos[axis]) ~= nil then
            local b = tonumber(base.pos[axis])
            lo, hi = b - lim, b + lim
        end
        m.pos[axis] = math.Clamp(m.pos[axis] + delta, lo, hi)
        return m, true
    elseif kind == "turn" then
        local lim = PL.NudgeLimits.turn
        local map = { p = "p", pitch = "p", y = "y", yaw = "y", r = "r", roll = "r" }
        local key = map[axis]
        if not key then return m, false end
        local v = (m.ang[key] + delta) % 360
        if v > 180 then v = v - 360 end
        m.ang[key] = math.Clamp(v, -lim, lim)
        return m, true
    end
    return m, false
end


-----------------------------------------------------------------------
-- ДОСТУП
-----------------------------------------------------------------------
PL.IssueHints = { "полиц", "police", "ordnung", "инспек", "ваи", "gendarm", "жандарм", "дорожн", "гаи" }

--- Кто вправе выдавать и аннулировать номера.
--[[ РЕГИСТРАЦИЯ ПРАВ В ДВУХ МЕСТАХ, ГДЕ ИХ ИЩЕТ ВЛАДЕЛЕЦ.
     Раньше код спрашивал права `plates.issue` и `plates_issue`, но нигде их
     не объявлял — значит, в списках они не появлялись и выдать их было
     негде (вопрос владельца 22.08). Теперь:
       • `/admin` → Привилегии — capability платформы (группам и игрокам);
       • `/factions` → Доступы — право организации (должностям и отделам),
         оно объявлено в GRM.FactionPerms.Permissions. ]]
if GRM.Access and GRM.Access.Register then
    -- Уровни госбазы объявляются прямо у права: единый слой доступа сам
    -- их проверит, модулю больше не нужно знать про PCBoard.
    GRM.Access.Register("plates.issue", {
        label = "Номерные знаки: регистрация и аннулирование", scope = "character",
        factionPerm = "plates_issue",
        levels = { police = true, military = true, admin = true },
    })
    GRM.Access.Register("plates.check", {
        label = "Номерные знаки: проверка по базе", scope = "character",
        factionPerm = "plates_check",
        levels = { police = true, military = true, justice = true, special = true, admin = true },
    })
end

--[[ Кто вправе регистрировать номера — и ПОЧЕМУ.
     Возвращаем не только да/нет, но и причину: игрок должен видеть в окне,
     сотрудник он или гражданский, а не гадать, куда делся раздел выдачи
     (вопрос владельца 22.08: «а как номера регистрировать?»). ]]
function PL.IssueReason(ply)
    if not IsValid(ply) then return false, "нет игрока" end
    if ply.IsSuperAdmin and ply:IsSuperAdmin() then return true, "суперадминистратор" end
    if GRM.Access and GRM.Access.Can and GRM.Access.Can(ply, "plates.issue") then
        return true, "право plates.issue"
    end
    if GRM.FactionPerms and GRM.FactionPerms.PlayerHasPermission
        and GRM.FactionPerms.PlayerHasPermission(ply, "plates_issue") then
        return true, "право организации plates_issue"
    end

    local fac = string.lower(ply:GetNWString("GRM_Faction", ""))
    if fac ~= "" then
        for _, hint in ipairs(PL.IssueHints) do
            if string.find(fac, hint, 1, true) then
                return true, "организация «" .. ply:GetNWString("GRM_Faction", "") .. "»"
            end
        end
    end
    if GRM.PCBoard and GRM.PCBoard.PlayerLevel then
        local level = GRM.PCBoard.PlayerLevel(ply)
        if level == "police" or level == "military" or level == "admin" then
            return true, "уровень госбазы: " .. level
        end
    end
    return false, fac ~= "" and ("организация «" .. ply:GetNWString("GRM_Faction", "") .. "» не выдаёт номера")
        or "вы не состоите в органах"
end

function PL.CanIssue(ply)
    return (select(1, PL.IssueReason(ply))) == true
end

--- Кто вправе пробивать номер по базе (шире, чем выдача).
function PL.CanCheck(ply)
    if PL.CanIssue(ply) then return true end
    if not IsValid(ply) then return false end
    if GRM.Access and GRM.Access.Can and GRM.Access.Can(ply, "plates.check") then return true end
    if GRM.FactionPerms and GRM.FactionPerms.PlayerHasPermission
        and GRM.FactionPerms.PlayerHasPermission(ply, "plates_check") then return true end
    if GRM.PCBoard and GRM.PCBoard.PlayerLevel then
        local level = GRM.PCBoard.PlayerLevel(ply)
        if level ~= nil and level ~= "none" then return true end
    end
    return false
end

-----------------------------------------------------------------------
-- РЕЕСТР (общая часть данных; запись — на сервере)
-----------------------------------------------------------------------
PL.Data = PL.Data or { plates = {} }

function PL.Get(number)
    number = PL.NormalizeNumber(number)
    if number == "" then return nil end
    return PL.Data.plates and PL.Data.plates[number] or nil
end

function PL.FactionOwnerKey(name)
    name = tostring(name or "")
    if name == "" then return "" end
    if string.sub(name, 1, 8) == "faction:" then return name end
    return "faction:" .. name
end

function PL.IsFactionOwner(key)
    return string.sub(tostring(key or ""), 1, 8) == "faction:"
end

function PL.ListFor(ownerKey)
    ownerKey = tostring(ownerKey or "")
    local out = {}
    for number, rec in pairs(PL.Data.plates or {}) do
        if istable(rec) and tostring(rec.ownerKey or "") == ownerKey then
            rec.number = number
            out[#out + 1] = rec
        end
    end
    table.sort(out, function(a, b) return tostring(a.number) < tostring(b.number) end)
    return out
end

--- Личные знаки персонажа плюс знаки его организации (лимит личный не ест фракционные).
function PL.ListVisibleFor(charKey, factionName)
    local seen, out = {}, {}
    local function add(list)
        for _, rec in ipairs(list or {}) do
            local n = tostring(rec.number or "")
            if n ~= "" and not seen[n] then seen[n] = true out[#out + 1] = rec end
        end
    end
    add(PL.ListFor(charKey))
    local fk = PL.FactionOwnerKey(factionName)
    if fk ~= "" then add(PL.ListFor(fk)) end
    table.sort(out, function(a, b) return tostring(a.number) < tostring(b.number) end)
    return out
end

function PL.CountFor(ownerKey)
    return #PL.ListFor(ownerKey)
end

--- Сколько знаков одному персонажу (0 — без ограничения).
function PL.Limit()
    if SERVER and PL.LimitCvar then return math.max(0, PL.LimitCvar:GetInt()) end
    return 0
end

if SERVER then

    util.AddNetworkString(PL.Net.OPEN)
    util.AddNetworkString(PL.Net.SYNC)
    util.AddNetworkString(PL.Net.ACT)
    util.AddNetworkString(PL.Net.RENDER)

    PL.LimitCvar = PL.LimitCvar or CreateConVar("grm_plates_limit", "6", FCVAR_ARCHIVE,
        "Сколько регистрационных номеров может быть у одного персонажа (0 — без предела)")
    PL.SpawnLimitCvar = PL.SpawnLimitCvar or CreateConVar("grm_plates_blanks", "2", FCVAR_ARCHIVE,
        "Сколько физических знаков одного номера можно держать на руках (перед и зад)")

    local DIR  = "grm_plates"
    local FILE = DIR .. "/registry.json"
    local RENDER_FILE = DIR .. "/render.json"

    local function ensureDir()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end

    -- Форвард-декларация: чат-команды ниже зовут её раньше объявления
    -- (ловушка Lua, которую ловит sim_forward_locals).
    local renderCommand

    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана:
    -- копия канона.
    local charKey = GRM.CharKey
    PL.CharKey = charKey

    local function notify(ply, text, good)
        if not IsValid(ply) then return end
        if GRM.Notify then
            GRM.Notify(ply, text, good and 100 or 255, good and 220 or 140, good and 130 or 100)
        else
            ply:ChatPrint("[Номера] " .. tostring(text))
        end
    end

    -- ── хранение ────────────────────────────────────────────────────
    --[[ ЗАЩИТА БАЗЫ ОТ ЗАТИРАНИЯ.
         Реестр читается при старте карты, а очередь записи живёт с первой
         секунды. Если что-то пометит реестр «грязным» ДО загрузки (сейв на
         выключении, смена карты, любой вызов Save), на диск уйдёт ПУСТАЯ
         таблица и все выданные номера пропадут. Поэтому и сборка, и запись
         молчат, пока файл не прочитан. ]]
    PL._loaded = PL._loaded or false

    local function buildPayload()
        if not PL._loaded then return nil end
        local arr = {}
        for number, rec in pairs(PL.Data.plates or {}) do
            if istable(rec) then
                rec.number = number
                arr[#arr + 1] = rec
            end
        end
        table.sort(arr, function(a, b) return tostring(a.number) < tostring(b.number) end)
        return { version = 1, plates = arr }
    end

    function PL.SaveNow()
        if not PL._loaded then return false end
        ensureDir()
        local ok, txt = pcall(util.TableToJSON, buildPayload(), true)
        if not ok or not isstring(txt) then return false end
        file.Write(FILE, txt)
        return file.Read(FILE, "DATA") == txt
    end

    if GRM.Save and GRM.Save.Register then
        PL._saveRegistered = GRM.Save.Register("grm_plates", {
            file = FILE, delay = 3, priority = 5, label = "номерные знаки",
            build = buildPayload,
        })
    end

    --[[ КТО СЕЙЧАС СМОТРИТ УЧЁТ.
         Терминал жандармерии, комендатуры и полиции порядка — это окно,
         которое человек держит открытым. Раньше снимок уходил только тому,
         кто нажал кнопку: коллега зарегистрировал номер — у остальных на
         экране старые данные (жалоба владельца 22.08). Теперь модуль знает
         своих зрителей и обновляет их сам. ]]
    PL.Viewers = PL.Viewers or {}

    function PL.SetViewer(ply, on)
        if not IsValid(ply) then return end
        if on then PL.Viewers[ply] = true else PL.Viewers[ply] = nil end
    end

    --- Разослать снимок всем, у кого окно открыто (порционно и без спама).
    function PL.PushViewers(reason)
        local function run()
            for ply in pairs(PL.Viewers) do
                if IsValid(ply) then PL.Push(ply) else PL.Viewers[ply] = nil end
            end
        end
        if GRM.Perf and GRM.Perf.Coalesce then
            GRM.Perf.Coalesce("plates.viewers.push", 0.35, run)
        else
            run()
        end
    end

    hook.Add("PlayerDisconnected", "GRM_Plates_Viewers", function(ply)
        if PL.Viewers then PL.Viewers[ply] = nil end
    end)

    --[[ Сердцебиение окна учёта.
         Права могли выдать в обход событий (правка файла назначения,
         рестарт карты) — и тогда страница ждала бы ручного «пробить».
         Раз в 5 секунд открытые окна получают свежий снимок. Таймер живёт
         только пока кто-то смотрит: пустой список — таймера нет. ]]
    local function viewersTick()
        local any = false
        for ply in pairs(PL.Viewers or {}) do
            if IsValid(ply) then any = true PL.Push(ply) else PL.Viewers[ply] = nil end
        end
        if not any then timer.Remove("GRM_Plates_ViewersTick") end
    end

    local baseSetViewer = PL.SetViewer
    function PL.SetViewer(ply, on)
        baseSetViewer(ply, on)
        if on and not timer.Exists("GRM_Plates_ViewersTick") then
            timer.Create("GRM_Plates_ViewersTick", 5, 0, viewersTick)
        end
    end

    function PL.Save(why)
        if not PL._loaded then return false end
        -- Любая правка реестра = обновление у всех, кто смотрит учёт.
        PL.PushViewers(why)
        if PL._saveRegistered and GRM.Save and GRM.Save.Mark then
            return GRM.Save.Mark("grm_plates", why or "plates")
        end
        return PL.SaveNow()
    end

    --[[ Раскладка надписи: хранится файлом и рассылается всем — правишь
         один раз, видят все и после рестарта. ]]
    function PL.SaveRender()
        ensureDir()
        PL.Render = PL.NormalizeRender(PL.Render)
        -- layouts сохраняются вместе с раскладкой (заказ владельца 22.08).
        local layouts = {}
        for class, src in pairs(PL.Layouts or {}) do
            if istable(src) then
                local row = { id = class, enabled = src.enabled ~= false }
                if istable(src.pos) then row.pos = { x = src.pos.x, y = src.pos.y, z = src.pos.z } end
                if istable(src.normal) then row.normal = { x = src.normal.x, y = src.normal.y, z = src.normal.z } end
                if istable(src.upHint) then row.upHint = { x = src.upHint.x, y = src.upHint.y, z = src.upHint.z } end
                layouts[#layouts + 1] = row
            end
        end
        table.sort(layouts, function(a, b) return tostring(a.id) < tostring(b.id) end)
        local ok, txt = pcall(util.TableToJSON, { render = PL.Render, layouts = layouts }, true)
        if not ok or not isstring(txt) then return false end
        file.Write(RENDER_FILE, txt)
        return true
    end

    function PL.LoadRender()
        if not file.Exists(RENDER_FILE, "DATA") then return false end
        local ok, t = pcall(util.JSONToTable, file.Read(RENDER_FILE, "DATA") or "", false, true)
        if not (ok and istable(t)) then return false end
        -- новый формат: { render=..., layouts=... }; старый — просто render.
        local renderSrc = istable(t.render) and t.render or t
        PL.Render = PL.NormalizeRender(renderSrc)
        PL.Layouts = {}
        for _, row in ipairs(istable(t.layouts) and t.layouts or {}) do
            if istable(row) and tostring(row.id or "") ~= "" then
                local layout = normalizeLayout(row)
                layout.id = tostring(row.id)
                PL.Layouts[layout.id] = layout
            end
        end
        return true
    end

    function PL.PushRender(ply)
        local r = PL.NormalizeRender(PL.Render)
        PL.Render = r
        net.Start(PL.Net.RENDER)
            net.WriteString(r.axis)
            net.WriteUInt(r.yaw, 9)
            net.WriteBool(r.flip)
            net.WriteFloat(r.scale)
            net.WriteFloat(r.offset)
            net.WriteFloat(r.tiltP) net.WriteFloat(r.tiltY) net.WriteFloat(r.tiltR)
            net.WriteFloat(r.moveX) net.WriteFloat(r.moveY)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    hook.Add("PlayerInitialSpawn", "GRM_Plates_RenderSync", function(ply)
        timer.Simple(3, function() if IsValid(ply) then PL.PushRender(ply) end end)
    end)

    function PL.Load()
        PL.LoadRender()
        PL.Data.plates = {}
        if not file.Exists(FILE, "DATA") then PL._loaded = true return false end
        local raw = file.Read(FILE, "DATA") or ""
        local ok, t = pcall(util.JSONToTable, raw, false, true)
        if not ok or not istable(t) then return false end
        for _, rec in ipairs(istable(t.plates) and t.plates or {}) do
            if istable(rec) then
                local number = PL.NormalizeNumber(rec.number)
                if number ~= "" then
                    rec.number = number
                    -- крепление приводим к единому виду: старые записи знали
                    -- только vehicleID, новые — полный ключ родителя
                    rec.mount = istable(rec.mount) and PL.NormalizeMount(rec.mount) or nil
                    PL.Data.plates[number] = rec
                end
            end
        end
        PL._loaded = true
        return true
    end

    -- ── выдача и статусы ────────────────────────────────────────────

    --- Зарегистрировать номер за персонажем.
    --  opts: { number (не обязателен), type, ownerKey, ownerName, note, by, byName, vehicle }
    function PL.Issue(opts)
        opts = istable(opts) and opts or {}
        local kind = tostring(opts.type or "civil")
        if not PL.Types[kind] then return nil, "Неизвестный тип знака" end

        local ownerKey = tostring(opts.ownerKey or "")
        if ownerKey == "" then return nil, "Не указан владелец" end

        local limit = PL.Limit()
        -- Фракционный пул не упирается в личный лимит персонажа.
        if limit > 0 and not PL.IsFactionOwner(ownerKey) and PL.CountFor(ownerKey) >= limit then
            return nil, ("У владельца уже %d знаков — это предел"):format(limit)
        end

        local number = PL.NormalizeNumber(opts.number)
        if number ~= "" then
            local okNum, why = PL.ValidNumber(number, kind)
            if not okNum then return nil, why end
            if PL.Get(number) then return nil, "Такой номер уже выдан" end
        else
            number = PL.GenerateNumber(kind, function(n) return PL.Get(n) ~= nil end)
            if not number then return nil, "Свободных номеров этой серии не осталось" end
        end

        local rec = {
            number = number,
            type = kind,
            ownerKey = ownerKey,
            ownerName = tostring(opts.ownerName or ""),
            faction = tostring(opts.faction or ""),
            vehicle = tostring(opts.vehicle or ""),
            note = string.sub(tostring(opts.note or ""), 1, 160),
            status = "active",
            issued = os.time(),
            by = tostring(opts.by or ""),
            byName = tostring(opts.byName or "система"),
            history = { { at = os.time(), what = "выдан", who = tostring(opts.byName or "система") } },
        }
        PL.Data.plates[number] = rec
        PL.Save("выдача номера")
        hook.Run("GRM_PlateIssued", rec)
        return rec
    end

    local function addHistory(rec, what, who)
        rec.history = istable(rec.history) and rec.history or {}
        table.insert(rec.history, { at = os.time(), what = tostring(what), who = tostring(who or "система") })
        while #rec.history > 20 do table.remove(rec.history, 1) end
    end

    function PL.SetStatus(number, status, whoName)
        local rec = PL.Get(number)
        if not rec then return false, "Номер не найден" end
        if not PL.Statuses[tostring(status or "")] then return false, "Неизвестный статус" end
        rec.status = status
        addHistory(rec, PL.Statuses[status], whoName)
        PL.Save("статус номера")
        -- живые знаки перекрашиваются сразу
        for _, ent in ipairs(PL.EntitiesOf(rec.number)) do
            ent:SetNWString("GRM_PlateStatus", status)
        end
        hook.Run("GRM_PlateStatusChanged", rec, status)
        return true
    end

    function PL.Revoke(number, whoName)
        return PL.SetStatus(number, "revoked", whoName)
    end

    --- Полностью удалить номер из реестра (служба). Снимает все живые бланки
    --  и чистит привязку к гаражу/автопарку.
    function PL.Delete(number, whoName)
        local rec = PL.Get(number)
        if not rec then return false, "Номер не найден" end
        number = PL.NormalizeNumber(number)
        -- снимаем физические бланки
        for _, ent in ipairs(PL.EntitiesOf(number)) do
            if IsValid(ent) then
                local veh = ent:GetParent()
                if IsValid(veh) then
                    -- помечаем, что это удаление, а не обычное снятие:
                    -- Detach подчистит UID гаража/автопарка
                    ent:Remove()
                else
                    ent:Remove()
                end
            end
        end
        -- если номер был привязан к машине — запомним UID до удаления записи
        local uid = tostring(rec.vehicleUID or (rec.mount and rec.mount.parentKey) or "")
        PL.Data.plates[number] = nil
        PL.Save("удаление номера")
        hook.Run("GRM_PlateDeleted", number, rec, whoName)
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("plates", "delete", nil, { number = number, by = whoName }, {})
        end
        local VD = GRM.VehicleDealer
        if VD and VD.Garages then
            for ownerKey, rows in pairs(VD.Garages) do
                if istable(rows) then
                    for rid, g in pairs(rows) do
                        if istable(g) and (tostring(g.vehicleUID or "") == uid
                                or tostring(g.plate or "") == number) then
                            g.vehicleUID = nil
                            g.plate = nil
                            g.plates = nil
                        end
                    end
                end
            end
            if VD.SaveGarages then pcall(VD.SaveGarages) end
        end
        local FL = GRM.Fleet
        if FL and FL.Units then
            for id, unit in pairs(FL.Units) do
                if istable(unit) and (tostring(unit.vehicleUID or "") == uid
                        or tostring(unit.plate or "") == number) then
                    unit.vehicleUID = nil
                    unit.plate = nil
                    unit.plates = {}
                end
            end
            if FL.SaveFleet then pcall(FL.SaveFleet, "delete plate " .. number) end
        end
        return true, "Номер удалён из реестра"
    end

    -- ── физические знаки ────────────────────────────────────────────

    --[[ Какой номер закреплён за машиной с этим UID. Нужен окнам дилера,
         гаража и госбазам: они работают с записями, а не с энтити. ]]
    function PL.PlateOfVehicleKey(uid)
        uid = tostring(uid or "")
        if uid == "" then return "" end
        for number, rec in pairs(PL.Data.plates or {}) do
            local mount = istable(rec.mount) and rec.mount or nil
            if mount and tostring(mount.parentKey or mount.vehicleID or "") == uid then
                return number, rec
            end
            -- защита: запись могла потерять mount, но не vehicleUID
            if tostring(rec.vehicleUID or "") == uid then return number, rec end
        end
        return ""
    end

    --- Все живые знаки с этим номером.
    function PL.EntitiesOf(number)
        number = PL.NormalizeNumber(number)
        local out = {}
        local list = (GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_plate") or ents.FindByClass("grm_plate")
        for _, ent in ipairs(list) do
            if IsValid(ent) and PL.NormalizeNumber(ent:GetNWString("GRM_Plate", "")) == number then
                out[#out + 1] = ent
            end
        end
        return out
    end

    --- Создать физический знак.
    function PL.SpawnPlate(number, pos, ang, owner)
        local rec = PL.Get(number)
        if not rec then return nil, "Номер не зарегистрирован" end
        local ent = ents.Create("grm_plate")
        if not IsValid(ent) then return nil, "Не удалось создать знак" end
        ent:SetPos(pos or Vector(0, 0, 0))
        ent:SetAngles(ang or Angle(0, 0, 0))
        ent:Spawn()
        ent:Activate()
        ent:SetupPlate(rec)
        if IsValid(owner) then
            ent.GRMPlateOwner = owner
            if owner.AddCount then owner:AddCount("grm_plates", ent) end
        end
        return ent
    end

    --- Знаки, закреплённые на транспорте.
    function PL.VehiclePlates(veh)
        local out = {}
        if not IsValid(veh) then return out end
        for _, child in ipairs(veh:GetChildren() or {}) do
            if IsValid(child) and child:GetClass() == "grm_plate" then out[#out + 1] = child end
        end
        return out
    end

    --- Запись гаража, к которой относится машина (если это личный транспорт).
    local function garageRecordOf(veh)
        local VD = GRM.VehicleDealer
        if not (VD and VD.FindRecord) then return nil end
        if not IsValid(veh) then return nil end
        local id = veh.GRMGarageID
        if not id then return nil end
        local ply = veh.GRMGarageOwner

        --[[ КЛЮЧ ВЛАДЕЛЬЦА ПОМНИМ НА САМОЙ МАШИНЕ (жалоба 31.08:
             «проблемы с запоминанием номеров»).

             Раньше запись гаража искали ТОЛЬКО по энтити игрока.
             Энтити умирает, как только человек выходит с сервера:
             IsValid(ply) становится ложью, запись не находится, и
             память позиции знака не пишется и не читается — номер
             «забывает», куда его поставили, и встаёт в авто-точку.

             Ключ персонажа — строка, она переживает выход владельца.
             Проставляем его при первом удобном случае, чтобы
             подхватились и машины, выданные до этой правки. ]]
        if not veh.GRMGarageOwnerKey and IsValid(ply) then
            veh.GRMGarageOwnerKey = charKey(ply)
        end

        if IsValid(ply) then
            local rec = VD.FindRecord(ply, id)
            if istable(rec) then return rec, ply, id end
        end
        local ck = veh.GRMGarageOwnerKey
        if ck ~= nil and tostring(ck) ~= "" and istable(VD.Garages) then
            local bucket = VD.Garages[tostring(ck)]
            if istable(bucket) then
                local rec = bucket[tostring(id)]
                if istable(rec) then return rec, nil, id end
            end
        end
        return nil
    end

    --[[ СЛУЖЕБНЫЙ ТРАНСПОРТ: у него нет записи в личном гараже дилера, но
         номер должен привязываться к единице автопарка. Пока это делалось
         только для личного (garageRecordOf), у служебного привязка оставалась
         только на энтити и сразу терялась. ]]
    local function fleetRecordOf(veh)
        local FL = GRM.Fleet
        if not (FL and FL.Unit) then return nil end
        local fid = tostring(veh.GRMFleetID or veh.GRMFleetUnit or "")
        local unit = FL.Unit(fid)
        return unit, fid
    end

    --[[ ПАМЯТЬ ПОЗИЦИИ ПО КОНКРЕТНОЙ МАШИНЕ.

         Отредактированное положение знака должно жить и после снятия:
         когда игрок вешает номер обратно на ТУ ЖЕ машину, он встаёт в
         запомненную точку, а не сбрасывается в авто. Храним локальные
         pos/ang в записи гаража (plateMemory) и в единице автопарка
         (unit.plateMemory), поэтому память переживает рестарт и выдачу
         из гаража. class-layout применяется с бóльшим приоритетом. ]]
    local function vehicleMemoryRecord(veh)
        local g = garageRecordOf(veh)
        if istable(g) then return g end
        local u = fleetRecordOf(veh)
        if istable(u) then return u end
        return nil
    end

    --- Сохранить локальные pos/ang знака в память конкретной машины.
    local function saveVehicleMemory(veh, lp, la)
        local rec = vehicleMemoryRecord(veh)
        if not istable(rec) then return false end
        rec.plateMemory = {
            pos = { x = lp.x, y = lp.y, z = lp.z },
            ang = { p = la.p, y = la.y, r = la.r },
        }
        local g = garageRecordOf(veh)
        if istable(g) and GRM.VehicleDealer and GRM.VehicleDealer.SaveGarages then
            GRM.VehicleDealer.SaveGarages(); return true
        end
        local u, fid = fleetRecordOf(veh)
        if istable(u) and GRM.Fleet and GRM.Fleet.SaveFleet then
            GRM.Fleet.SaveFleet("plate memory " .. fid); return true
        end
        return false
    end
    PL._saveVehicleMemory = saveVehicleMemory

    --- Прочитать память машины как {pos=Vector, ang=Angle} или nil.
    local function readVehicleMemory(veh)
        local rec = vehicleMemoryRecord(veh)
        local m = istable(rec) and rec.plateMemory or nil
        if not (istable(m) and istable(m.pos) and istable(m.ang)) then return nil end
        return {
            pos = Vector(tonumber(m.pos.x) or 0, tonumber(m.pos.y) or 0, tonumber(m.pos.z) or 0),
            ang = Angle(tonumber(m.ang.p) or 0, tonumber(m.ang.y) or 0, tonumber(m.ang.r) or 0),
        }
    end
    PL._readVehicleMemory = readVehicleMemory

    --- Стереть память машины (кнопка «Авто»).
    local function clearVehicleMemory(veh)
        local rec = vehicleMemoryRecord(veh)
        if not istable(rec) or rec.plateMemory == nil then return false end
        rec.plateMemory = nil
        local g = garageRecordOf(veh)
        if istable(g) and GRM.VehicleDealer and GRM.VehicleDealer.SaveGarages then GRM.VehicleDealer.SaveGarages(); return true end
        local u, fid = fleetRecordOf(veh)
        if istable(u) and GRM.Fleet and GRM.Fleet.SaveFleet then GRM.Fleet.SaveFleet("plate memory reset " .. fid); return true end
        return false
    end
    PL._clearVehicleMemory = clearVehicleMemory

    --- Запомнить раскладку знаков машины в записи гаража или единицы парка.
    --  Раньше знаки возвращались «на место» только у личного транспорта:
    --  у служебного запись не писалась, и после уборки в гараж/рестарта
    --  номер визуально висел, но в базе был не привязан.
    local function rememberLayout(veh)
        local layout = {}
        for _, plate in ipairs(PL.VehiclePlates(veh)) do
            local lp = veh:WorldToLocal(plate:GetPos())
            local la = veh:WorldToLocalAngles(plate:GetAngles())
            layout[#layout + 1] = {
                number = plate:GetNWString("GRM_Plate", ""),
                pos = { x = lp.x, y = lp.y, z = lp.z },   -- Vector — userdata, в JSON пишем числами
                ang = { p = la.p, y = la.y, r = la.r },
            }
        end

        local rec = garageRecordOf(veh)
        if istable(rec) then
            rec.plates = layout
            rec.plate = layout[1] and tostring(layout[1].number or "") or ""
            if GRM.VehicleDealer and GRM.VehicleDealer.SaveGarages then GRM.VehicleDealer.SaveGarages() end
        end

        local unit = fleetRecordOf(veh)
        if istable(unit) then
            unit.plates = layout
            unit.plate = layout[1] and tostring(layout[1].number or "") or ""
            if GRM.Fleet and GRM.Fleet.SaveFleet then GRM.Fleet.SaveFleet("закрепление знака") end
        end
    end
    PL.RememberLayout = rememberLayout

    --[[ ЛИЧНОСТЬ МАШИНЫ.
         «Если я удалю машину — номер вернётся именно на неё?» Да: знак
         привязывается не к энтити (она умирает вместе с машиной), а к
         ЗАПИСИ транспорта в гараже — это и есть конкретная машина, которая
         переживает удаление, рестарт и выдачу заново. У служебных и карт-
         машин записи нет, для них знак живёт только пока живёт машина. ]]
    function PL.VehicleIdentity(veh)
        if not IsValid(veh) then return "", "" end
        -- UID единого слоя транспорта: он переживает удаление машины,
        -- уборку в гараж и повторную выдачу (заказ владельца 22.08).
        local uid = (GRM.Vehicles and GRM.Vehicles.EnsureUID) and GRM.Vehicles.EnsureUID(veh) or ""
        --[[ НАДЁЖНЫЙ ФОЛБЭК. Раньше при отсутствии GRM.Vehicles возвращался
             голый GRMGarageID, а GRMFleetID игнорировался — привязка в базе
             получала ключ, по которому окна её не ищут ("veh:<id>"/"fleet:<id>").
             Теперь всегда нормализуем к привычным ключам. ]]
        local id = uid
        if id == "" then
            local gid = tostring(veh.GRMGarageID or "")
            local fid = tostring(veh.GRMFleetID or veh.GRMFleetUnit or "")
            if gid ~= "" then id = "veh:" .. gid
            elseif fid ~= "" then id = "fleet:" .. fid
            end
        end
        local name = tostring(veh.VD_Class or veh:GetClass() or "")
        -- имя ищем по СЫРОМУ id записи гаража: VD.FindRecord ждёт veh_2, а
        -- привязка в базе хранит "veh:veh_2".
        if IsValid(veh.GRMGarageOwner) and GRM.VehicleDealer and GRM.VehicleDealer.FindRecord then
            local rawID = tostring(veh.GRMGarageID or "")
            if rawID ~= "" then
                local rec = GRM.VehicleDealer.FindRecord(veh.GRMGarageOwner, rawID)
                if istable(rec) then name = tostring(rec.name or name) end
            end
        end
        return id, name
    end

    --- Закрепить знак на транспорте.
    function PL.Attach(plate, veh, actor)
        if not (IsValid(plate) and IsValid(veh)) then return false, "Нужен транспорт рядом" end
        if plate:GetParent() == veh then return false, "Знак уже закреплён" end

        plate:SetParent(veh)
        plate:SetMoveType(MOVETYPE_NONE)
        plate:SetSolid(SOLID_NONE)
        plate:SetCollisionGroup(COLLISION_GROUP_WORLD)
        local phys = plate:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        plate.GRMPlateVehicle = veh
        plate:SetNWBool("GRM_PlateMounted", true)
        -- подгонка стрелками начинается заново от нового места
        plate.GRMNudgeBase = nil

        local number = PL.NormalizeNumber(plate:GetNWString("GRM_Plate", ""))
        local rec = PL.Get(number)
        --[[ ЛИЧНОСТЬ МАШИНЫ СЧИТАЕМ ЗАРАНЕЕ, А НЕ ВНУТРИ `if rec`.
             vehID нужен ниже двум блокам — записи гаража и единице
             автопарка, — которые лежат ЗА пределами этого if. Пока
             объявление было внутри, снаружи читался глобал nil, и связь
             «машина ↔ номер» в гараже терялась: после выдачи из гаража
             знак возвращался без привязки. ]]
        local vehID, vehName = PL.VehicleIdentity(veh)
        if rec then
            local lp = veh:WorldToLocal(plate:GetPos())
            local la = veh:WorldToLocalAngles(plate:GetAngles())
            rec.mount = PL.NormalizeMount({
                vehicle = vehName, vehicleID = vehID, at = os.time(),
                parentType = PL.LooksLikeVehicle(veh) and "vehicle" or "prop",
                parentKey = vehID,
                parentClass = tostring(veh:GetClass() or ""),
                parentName = vehName,
                -- координаты числами: Vector — userdata, в JSON он пустой
                pos = { x = lp.x, y = lp.y, z = lp.z },
                ang = { p = la.p, y = la.y, r = la.r },
            })
            -- обратная связь: машина знает свой номер, номер знает машину
            rec.vehicleUID = vehID
            addHistory(rec, "закреплён на транспорте" .. (vehName ~= "" and (" (" .. vehName .. ")") or ""),
                IsValid(actor) and actor:Nick() or "владелец")
            PL.Save("монтаж знака")
        end
        -- номер видно над машиной и в проверках
        veh:SetNWString("GRM_PlateNumber", number)
        veh:SetNWString("GRM_PlateType", plate:GetNWString("GRM_PlateType", "civil"))
        --[[ БАЗА ДАННЫХ, А НЕ ТОЛЬКО ФИЗИКА (заказ владельца 22.08).
             Окна дилера/гаража читают номер из записи, а не с энтити.
             rememberLayout пишет и личную запись гаража, и единицу
             автопарка; здесь дополнительно проставляем vehicleUID на
             запись, чтобы даже при потере mount связь находилась. ]]
        local VD = GRM.VehicleDealer
        if IsValid(veh.GRMGarageOwner) and veh.GRMGarageID and VD and VD.FindRecord then
            local gr = VD.FindRecord(veh.GRMGarageOwner, tostring(veh.GRMGarageID))
            if istable(gr) then
                gr.vehicleUID = tostring(vehID or veh.GRMGarageID)
                if VD.SaveGarages then VD.SaveGarages() end
            end
        end
        local FL = GRM.Fleet
        local fidAttach = tostring(veh.GRMFleetID or veh.GRMFleetUnit or "")
        if FL and FL.Unit and fidAttach ~= "" then
            local unit = FL.Unit(fidAttach)
            if istable(unit) then
                unit.vehicleUID = tostring(vehID or fidAttach)
                if FL.SaveFleet then FL.SaveFleet("закрепление знака") end
            end
        end
        rememberLayout(veh)
        --[[ Запоминаем позицию по конкретной машине: после снятия и
             повторной установки знак встанет ровно сюда, а не в
             авто-точку.

             Но только если точку выбрал человек. Авто-расчёт
             (MountOnRear) помечает знак флагом GRMPlateAutoPlaced —
             его результат в память не пишем, иначе кривой расчёт
             залип бы намертво. ]]
        if not plate.GRMPlateAutoPlaced then
            local _lp = veh:WorldToLocal(plate:GetPos())
            local _la = veh:WorldToLocalAngles(plate:GetAngles())
            saveVehicleMemory(veh, _lp, _la)
        end
        plate.GRMPlateAutoPlaced = nil
        hook.Run("GRM_PlateAttached", plate, veh, actor)
        return true
    end

    --- Снять знак с транспорта.
    function PL.Detach(plate, actor, seize)
        if not IsValid(plate) then return false, "Знак не найден" end
        local veh = plate:GetParent()
        plate:SetParent(nil)
        plate:SetMoveType(MOVETYPE_VPHYSICS)
        plate:SetSolid(SOLID_VPHYSICS)
        plate:SetCollisionGroup(COLLISION_GROUP_NONE)
        plate:PhysicsInit(SOLID_VPHYSICS)
        local phys = plate:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() phys:EnableMotion(true) end
        plate.GRMPlateVehicle = nil
        plate:SetNWBool("GRM_PlateMounted", false)

        local number = PL.NormalizeNumber(plate:GetNWString("GRM_Plate", ""))
        local rec = PL.Get(number)
        -- запомним машину, с которой снимаем, чтобы почистить её UID в
        -- гараже/автопарке (rememberLayout ниже обнулит только список plates)
        local detachVeh = IsValid(veh) and veh or nil
        if rec then
            rec.mount = nil
            --[[ СНИМАЕМ ПРИВЯЗКУ К МАШИНЕ ПОЛНОСТЬЮ.
                 Раньше чистился только rec.mount, а rec.vehicleUID оставался —
                 и окна гаража/автопарка продолжали показывать номер как
                 закреплённый (жалоба владельца: «не вижу чтобы запоминало
                 снятие»). Теперь при снятии номер полностью отвязывается
                 от конкретного транспорта. ]]
            rec.vehicleUID = nil
            addHistory(rec, seize and "изъят сотрудником" or "снят с транспорта",
                IsValid(actor) and actor:Nick() or "владелец")
            if seize then rec.status = "seized" end
            PL.Save("демонтаж знака")
        end
        if IsValid(veh) then
            local rest = PL.VehiclePlates(veh)
            veh:SetNWString("GRM_PlateNumber", #rest > 0 and rest[1]:GetNWString("GRM_Plate", "") or "")
            rememberLayout(veh)
            -- если знаков на машине не осталось — снимаем UID-привязку
            -- и с записи гаража, и с единицы автопарка
            if #rest == 0 and detachVeh then
                local VD = GRM.VehicleDealer
                if IsValid(veh.GRMGarageOwner) and veh.GRMGarageID and VD and VD.FindRecord then
                    local gr = VD.FindRecord(veh.GRMGarageOwner, tostring(veh.GRMGarageID))
                    if istable(gr) then
                        gr.vehicleUID = nil
                        gr.plate = nil
                        if VD.SaveGarages then VD.SaveGarages() end
                    end
                end
                local FL = GRM.Fleet
                local fid = tostring(veh.GRMFleetID or veh.GRMFleetUnit or "")
                if FL and FL.Unit and fid ~= "" then
                    local unit = FL.Unit(fid)
                    if istable(unit) then
                        unit.vehicleUID = nil
                        unit.plate = nil
                        if FL.SaveFleet then FL.SaveFleet("снятие знака") end
                    end
                end
            end
        end
        hook.Run("GRM_PlateDetached", plate, veh, actor)
        return true
    end

    --- Кто может трогать конкретный знак.
    function PL.CanHandle(ply, plate)
        if not (IsValid(ply) and IsValid(plate)) then return false end
        if ply:IsSuperAdmin() then return true, "superadmin" end
        local rec = PL.Get(plate:GetNWString("GRM_Plate", ""))
        if rec then
            if tostring(rec.ownerKey) == charKey(ply) then return true, "owner" end
            local fac = IsValid(ply) and ply:GetNWString("GRM_Faction", "") or ""
            if fac ~= "" and tostring(rec.ownerKey) == PL.FactionOwnerKey(fac) then return true, "faction" end
        end
        if PL.CanIssue(ply) then return true, "police" end
        return false
    end

    --[[ ЕДИНАЯ ОБРАБОТКА «НАЖАЛ E НА ЗНАКЕ».
         Одна функция на все пути: [E] по самому знаку, [E] по машине с
         знаком в руках физгана и команда /номер_прикрепить. Игрок всегда
         получает внятный ответ, а не молчание. ]]
    function PL.HandlePlateUse(ply, plate, veh)
        if not (IsValid(ply) and IsValid(plate)) then return false end

        local can, why = PL.CanHandle(ply, plate)
        if not can then
            notify(ply, "Это чужой знак — трогать его нельзя.")
            return false
        end

        -- уже закреплён → снимаем
        if IsValid(plate:GetParent()) then
            local seize = (why == "police") and tostring(plate.GRMPlateOwnerKey or "") ~= charKey(ply)
            PL.Detach(plate, ply, seize)
            notify(ply, seize and "Знак изъят с транспорта." or "Знак снят с транспорта.", true)
            return true
        end

        if not IsValid(veh) and plate.FindVehicle then
            veh = plate:FindVehicle()
        end
        if not IsValid(veh) then
            notify(ply, "Рядом нет транспорта. Поднесите знак вплотную к бамперу и нажмите [E].")
            return false
        end

        --[[ КУДА ИМЕННО ВЕШАТЬ.
             Раньше знак просто «прилипал» туда, где висел в руках, и его
             приходилось выравнивать вручную. Теперь:
               • смотрите на кузов — знак встаёт РОВНО в эту точку, лицом
                 наружу по нормали поверхности (PlaceOnSurface);
               • не смотрите — уходит на задний борт по габаритам машины
                 (MountOnRear).
             В обоих случаях ориентация считается по замерам модели: тонкая
             ось наружу, длинная вдоль строки, короткая вверх. ]]
        local placed = false
        local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply) or ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) then
            local hitBase = PL.VehicleBase(tr.Entity) or tr.Entity
            if hitBase == veh and tr.HitNormal and tr.HitNormal:Length() > 0.1 then
                PL.PlaceOnSurface(plate, tr.HitPos, tr.HitNormal, veh:GetUp())
                placed = PL.Attach(plate, veh, ply)
            end
        end

        local ok, err = placed, nil
        if not ok then ok, err = PL.MountOnRear(plate, veh, ply) end

        notify(ply, ok and "Знак закреплён на транспорте." or tostring(err or "Не удалось закрепить"), ok)
        if ok then plate:EmitSound("physics/metal/metal_solid_impact_hard2.wav", 60, 110) end
        return ok
    end

    --[[ ЗНАК В РУКАХ ФИЗГАНА.
         Держать знак и нажимать [E] по бамперу — самый естественный жест,
         но [E] по машине сажает в неё. Поэтому: если игрок держит знак
         физганом и жмёт [E] на транспорт — крепим знак и НЕ пускаем в салон. ]]
    hook.Add("PhysgunPickup", "GRM_Plates_Held", function(ply, ent)
        if IsValid(ent) and ent:GetClass() == "grm_plate" then ply.GRMHeldPlate = ent end
    end)
    hook.Add("PhysgunDrop", "GRM_Plates_Dropped", function(ply, ent)
        if IsValid(ent) and ply.GRMHeldPlate == ent then
            -- знак остаётся «в работе» ещё пару секунд после отпускания
            ply.GRMHeldPlateUntil = CurTime() + 3
        end
    end)

    hook.Add("PlayerUse", "GRM_Plates_UseVehicle", function(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return end
        local plate = ply.GRMHeldPlate
        if not IsValid(plate) or IsValid(plate:GetParent()) then return end
        if (ply.GRMHeldPlateUntil or 0) < CurTime() then
            local wep = ply:GetActiveWeapon()
            if not (IsValid(wep) and wep:GetClass() == "weapon_physgun") then return end
        end
        if not (PL.LooksLikeVehicle and PL.LooksLikeVehicle(ent)) then return end
        local base = PL.VehicleBase and PL.VehicleBase(ent) or ent
        if plate:GetPos():Distance(base.NearestPoint and base:NearestPoint(plate:GetPos()) or base:GetPos()) > 90 then
            return
        end
        PL.HandlePlateUse(ply, plate, base)
        return false
    end)

    --- Запасной путь: закрепить/снять ближайший свой знак командой.
    local function nearestOwnPlate(ply, mounted)
        local best, bestD = nil, 300
        local list = (GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_plate") or ents.FindByClass("grm_plate")
        for _, ent in ipairs(list) do
            if IsValid(ent) and PL.CanHandle(ply, ent) then
                local attached = IsValid(ent:GetParent())
                if attached == (mounted == true) then
                    local d = ply:GetPos():Distance(ent:GetPos())
                    if d < bestD then best, bestD = ent, d end
                end
            end
        end
        return best
    end

    concommand.Add("grm_plate_attach", function(ply)
        if not IsValid(ply) then return end
        local plate = nearestOwnPlate(ply, false)
        if not IsValid(plate) then notify(ply, "Рядом нет вашего свободного знака.") return end
        PL.HandlePlateUse(ply, plate)
    end)

    concommand.Add("grm_plate_detach", function(ply)
        if not IsValid(ply) then return end
        local plate = nearestOwnPlate(ply, true)
        if not IsValid(plate) then notify(ply, "Рядом нет закреплённого знака.") return end
        PL.HandlePlateUse(ply, plate)
    end)

    --[[ ВОЗВРАТ ЗНАКОВ НА КОНКРЕТНУЮ МАШИНУ.
         Источников два, и это осознанно:
           1) раскладка в записи гаража (быстро и точно, ставилась при
              закреплении);
           2) сам реестр номеров — если запись гаража потеряла список
              (старое сохранение, ручная правка), знак всё равно найдёт свою
              машину по mount.vehicleID.
         Дубли исключаются по номеру. ]]
    function PL.RestoreForVehicle(ply, ent, record)
        if not (IsValid(ent) and istable(record)) then return 0 end
        local done, restored = {}, 0

        local function place(number, pos, ang)
            number = PL.NormalizeNumber(number)
            if number == "" or done[number] then return end
            local plateRec = PL.Get(number)
            if not plateRec then return end
            done[number] = true
            local lp = Vector(tonumber(pos and pos.x) or 0, tonumber(pos and pos.y) or 0, tonumber(pos and pos.z) or 0)
            local la = Angle(tonumber(ang and ang.p) or 0, tonumber(ang and ang.y) or 0, tonumber(ang and ang.r) or 0)
            local plate = PL.SpawnPlate(number, ent:LocalToWorld(lp), ent:LocalToWorldAngles(la), ply)
            if IsValid(plate) and PL.Attach(plate, ent, ply) then restored = restored + 1 end
        end

        for _, saved in ipairs(istable(record.plates) and record.plates or {}) do
            place(saved.number, saved.pos, saved.ang)
        end

        --[[ Второй источник — сам реестр номеров. Ключ крепления это UID
             машины из единого слоя транспорта: "veh:<id записи гаража>",
             "fleet:<id единицы автопарка>" или выданный UID. Поэтому знак
             находит СВОЮ машину даже если раскладка в записи гаража
             потерялась. ]]
        local keys = {}
        local recID = tostring(record.id or "")
        if recID ~= "" then keys["veh:" .. recID] = true keys[recID] = true end
        local uid = (GRM.Vehicles and GRM.Vehicles.EnsureUID) and GRM.Vehicles.EnsureUID(ent) or ""
        if uid ~= "" then keys[uid] = true end

        for number, plateRec in pairs(PL.Data.plates or {}) do
            local mount = istable(plateRec.mount) and plateRec.mount or nil
            local key = mount and tostring(mount.parentKey or mount.vehicleID or "") or ""
            if key ~= "" and keys[key] then
                place(number, mount.pos, mount.ang)
                mount.offMap = nil
            end
        end
        return restored
    end

    hook.Add("GRM_VehicleIssued", "GRM_Plates_Restore", function(ply, ent, rec)
        PL.RestoreForVehicle(ply, ent, rec)
    end)

    --[[ СЛУЖЕБНЫЕ НОМЕРА БОЛЬШЕ НЕ ВЫДАЮТСЯ САМИ (заказ владельца 22.08).

         Личный транспорт получает номер в отделении: человек идёт,
         регистрирует, вешает. Для техники, закупленной ЦЕЛИКОМ в автопарк,
         автоматическая генерация и крепление номера не нужны — машина
         закупается организацией как единица, а номера ей ставят вручную,
         как и личным машинам. Функция ниже оставлена как ручной инструмент
         (вызывается только явно), но на выдачу из автопарка она больше не
         подписана. Конвар по умолчанию 0. ]]
    local cvAuto = CreateConVar("grm_plates_auto_service", "0", FCVAR_ARCHIVE,
        "Пока только ручной вызов: авто-номера транспорта автопарка отключены")

    --- Какая серия положена организации.
    function PL.ServiceKind(faction)
        local name = string.lower(tostring(faction or ""))
        if name == "" then return "gov" end
        for _, hint in ipairs({ "polizei", "полиц", "ordnung", "порядк", "gendarm", "жандарм", "ваи", "гаи" }) do
            if string.find(name, hint, 1, true) then return "police" end
        end
        for _, hint in ipairs({ "military", "воен", "wehr", "армия", "komendat", "коменд" }) do
            if string.find(name, hint, 1, true) then return "military" end
        end
        return "gov"
    end

    --- Повесить знак на задний борт машины по её габаритам.
    --[[--------------------------------------------------------------
        ГЕОМЕТРИЯ ЗНАКА — ПО ЗАМЕРАМ МОДЕЛИ (владелец прислал 22.08).

        models/hunter/plates/plate025x075.mdl:
            мин  -6.2 -18 -1.7      макс  6.2 18 1.8
            габарит 12.4 × 36.1 × 3.5
            ТОНКАЯ ось z (3.5)  — это НОРМАЛЬ лицевой стороны
            ДЛИННАЯ ось y (36.1) — вдоль строки номера
            КОРОТКАЯ ось x (12.4) — высота таблички

        Отсюда правило крепления, которого раньше не было:
          • локальная +Z знака должна смотреть НАРУЖУ от поверхности;
          • локальная +X — вверх (высота таблички);
          • локальная +Y — вдоль строки, горизонтально.

        В GMod у энтити Forward = локальная +X, Up = локальная +Z.
        Значит нужный угол берётся одной операцией:
            angles = up:AngleEx(normal)
        где up — куда смотрит верх таблички, normal — наружу от кузова.
        Раньше здесь просто разворачивали углы машины на 180° по рысканью:
        наружу оказывалась локальная X, и знак ложился ребром/плашмя.
    ----------------------------------------------------------------]]
    PL.ModelGeometry = {
        model = "models/hunter/plates/plate025x075.mdl",
        thin = "z", long = "y", short = "x",
        size = { x = 12.4, y = 36.1, z = 3.5 },
        halfThickness = 1.225, -- модель знака уменьшена до 70%
    }

    --- Углы знака для поверхности с нормалью normal.
    --  upHint — желаемое «вверх» (по умолчанию мировой верх).
    function PL.SurfaceAngles(normal, upHint)
        local n = Vector(normal.x, normal.y, normal.z)
        if n:Length() < 0.001 then n = Vector(1, 0, 0) end
        n:Normalize()

        local up = upHint and Vector(upHint.x, upHint.y, upHint.z) or Vector(0, 0, 1)
        -- верх таблички не может совпадать с нормалью: знак на полу/потолке
        if math.abs(n:Dot(up)) > 0.95 then up = Vector(1, 0, 0) end
        -- составляющую вдоль нормали убираем, остаётся чистое «вверх по знаку»
        up = up - n * up:Dot(n)
        if up:Length() < 0.001 then up = n:Angle():Up() end
        up:Normalize()

        -- Forward = локальная +X (высота), Up = локальная +Z (нормаль)
        return up:AngleEx(n)
    end

    --- Поставить знак ровно на поверхность: заподлицо, лицом наружу.
    function PL.PlaceOnSurface(plate, hitPos, normal, upHint)
        if not IsValid(plate) then return false end
        local ang = PL.SurfaceAngles(normal, upHint)
        local lift = (PL.ModelGeometry.halfThickness or 1.75) + 0.2
        plate:SetAngles(ang)
        plate:SetPos(Vector(hitPos.x, hitPos.y, hitPos.z) + Vector(normal.x, normal.y, normal.z):GetNormalized() * lift)
        return true
    end

    --[[ ЗАДНИЙ БОРТ МАШИНЫ (заказ владельца 22.08: номер не сидит ровно).
         Раньше точка бралась из OBB, а нормаль — из `veh:GetForward()`. У
         simfphys/LVS origin смещена, а `GetForward` может относиться не к
         корпусу. Поэтому:
           • задняя точка считается в ЛОКАЛЬНЫХ осях модели: -X корпуса;
           • нормаль — локальный -X в мире (не зависит от GetForward);
           • если у энтити есть WorldSpaceAABB — считаем по мировым
             габаритам, чтобы точка была на корме даже со смещённым
             origin. ]]
    --[[ ТОЧКА НА КУЗОВЕ: ВЕРТИКАЛЬНЫЙ ВЕЕР ЛУЧЕЙ (фикс 25.08).

         Прошлая версия стреляла ОДНИМ лучом по центру корпуса на высоте
         30% габарита (≈14–42 юнита). У внедорожников и военной техники
         центр кормы на этой высоте — это запасное колесо, рама или ниша
         под бампером; луч бил в землю/скос и знак вставал вровень с
         землёй под машиной (жалоба владельца: номер лежит на асфальте,
         а система пишет «закреплён»).

         Теперь по каждому борту пускаем НЕСКОЛЬКО лучей на разной высоте
         (от верхней кромки габарита вниз, с лёгким боковым смещением) и
         берём первый, который попал в сам корпус на разумной высоте.
         Точка проходит валидацию: не ниже плоскости колёс и не дальше
         габарита машины, иначе — фолбэк по OBB с высокой точкой. ]]
    local function rearTraceFilter(veh)
        return function(ent)
            if not IsValid(ent) then return true end
            if ent == veh then return false end
            local par = ent.GetParent and ent:GetParent() or nil
            if par == veh then return false end
            -- пропускаем колёса/дочерние части simfphys — они и есть корпус
            if looksLikeVehicle(ent) and vehicleBase(ent) == veh then return false end
            return true
        end
    end

    -- Один луч в точку боковой границы на заданной мировой высоте.
    local function traceAtHeight(veh, dir, c, span, z)
        if not (util and isfunction(util.TraceLine)) then return nil end
        local from = Vector(c.x, c.y, z) + dir * span
        local to   = Vector(c.x, c.y, z) - dir * 8
        local tr = util.TraceLine({ start = from, endpos = to, filter = rearTraceFilter(veh), mask = MASK_SOLID })
        if not (tr.Hit and IsValid(tr.Entity)) then return nil end
        local hitUs = tr.Entity == veh or vehicleBase(tr.Entity) == veh
        if not hitUs then return nil end
        if tr.HitNormal:Length() < 0.2 then return nil end
        --[[ НОРМАЛЬ ДОЛЖНА СМОТРЕТЬ НАРУЖУ — то есть ВДОЛЬ dir.

             Луч идёт из-за пределов машины внутрь: start = центр +
             dir * вынос, endpos = центр - dir * 8. Значит сам луч
             направлен ВДОЛЬ -dir, а наружная нормаль поверхности —
             ВДОЛЬ dir.

             Раньше проверка была перевёрнута: n:Dot(-dir) < 0.35.
             Для правильного попадания скалярное произведение давало
             -1, и трассировка ОТБРАСЫВАЛА ВСЕ попадания — и спереди,
             и сзади. До поверхности кузова дело не доходило никогда:
             знак всегда ставился грубым фолбэком по габариту, отсюда
             и «крепление сзади крепит хрен пойми как». ]]
        local n = Vector(tr.HitNormal.x, tr.HitNormal.y, tr.HitNormal.z)
        n:Normalize()
        if n:Dot(dir) < 0.35 then return nil end
        return { pos = tr.HitPos, normal = n }
    end

    local function hullEndHit(veh, dir)
        if not IsValid(veh) then return nil end
        -- WorldSpaceAABB есть в игре, но моки стендов его не дают —
        -- в этом случае считаем по OBB относительно позиции энтити.
        local wmin, wmax
        if isfunction(veh.WorldSpaceAABB) then
            wmin, wmax = veh:WorldSpaceAABB()
        else
            local obbMin, obbMax = veh:OBBMins(), veh:OBBMaxs()
            local p = veh:GetPos()
            wmin, wmax = p + obbMin, p + obbMax
        end
        if not (wmin and wmax) then return nil end
        local c = (wmin + wmax) * 0.5
        local h = math.max(8, wmax.z - wmin.z)
        -- плоскость «земли»: OBB.min.z + половина диаметра колеса (14) —
        -- всё, что ниже, это дорога/рама, а не борт для таблички
        local floorZ = wmin.z + math.Clamp(h * 0.18, 12, 24)
        dir = Vector(dir.x, dir.y, 0)
        if dir:Length() < 0.05 then return nil end
        dir:Normalize()
        local span = math.max(wmax.x - wmin.x, wmax.y - wmin.y) * 0.75 + 90

        --[[ ВЕЕР ВЫСОТ: ОТ БАМПЕРА ВВЕРХ.

             Номер вешают на бампер, а не на крышку багажника. Раньше
             лучи шли сверху вниз (0.82 → 0.22), а цикл останавливался
             на ПЕРВОМ удачном — то есть на самом верхнем. Знак уезжал
             под крышку багажника, а то и под крышу: «крепит хрен пойми
             как». Теперь первыми идут высоты бампера, вверх уходим
             только если бампер трассировке не достался. Пол кузова
             (floorZ) по-прежнему отсекает колёса и дорогу. ]]
        local fracs = { 0.28, 0.36, 0.22, 0.44, 0.52, 0.18, 0.64, 0.80 }
        -- небольшое боковое смещение луча (левее/правее центра), чтобы
        -- обойти запасное колесо по центру кормы
        local side = Vector(-dir.y, dir.x, 0)
        local offsets = { 0, 12, -12, 22, -22 }
        local best
        for _, frac in ipairs(fracs) do
            local z = wmin.z + math.Clamp(h * frac, floorZ + 2, wmax.z - 4)
            for _, off in ipairs(offsets) do
                local cc = c + side * off
                local hit = traceAtHeight(veh, dir, cc, span, z)
                if hit and hit.pos.z >= floorZ then
                    --[[ Из попаданий на одной высоте берём ближайшее к
                         СЕРЕДИНЕ кормы. Раньше выбирали самое высокое,
                         но внутри одной высоты это всё равно что
                         случайное: знак цеплялся краем за крыло. ]]
                    if not best or math.abs(off) < math.abs(best.off) then
                        best = { pos = hit.pos, normal = hit.normal, up = veh:GetUp(), off = off }
                    end
                end
            end
            if best then break end
        end

        if best then
            return { pos = best.pos, normal = best.normal, up = best.up }
        end

        --[[ ФОЛБЭК: трассировка не достала кузов — у части моделей
             коллизия не совпадает с габаритом. Ставим знак на уровень
             БАМПЕРА у границы габарита: раньше было 55% высоты, и знак
             висел посреди борта.

             Границу считаем проекцией углов габарита на направление, а
             не долей от большей стороны: на длинной машине старая
             формула уносила точку далеко наружу, и валидация её
             отбрасывала — знак вовсе не крепился. ]]
        local extent = 0
        for _, x in ipairs({ wmin.x, wmax.x }) do
            for _, y in ipairs({ wmin.y, wmax.y }) do
                local d = (x - c.x) * dir.x + (y - c.y) * dir.y
                if d > extent then extent = d end
            end
        end
        local face = Vector(c.x, c.y, wmin.z + math.Clamp(h * 0.30, floorZ + 4, wmax.z - 6))
            + dir * (extent + 2)
        return { pos = face, normal = -dir, up = veh:GetUp() }
    end

    --[[ ВАЛИДАЦИЯ БУДУЩЕЙ ТОЧКИ КРЕПЛЕНИЯ.

         Возвращает ok, reason. Не даёт Attach зафиксировать в базе позицию
         «знак на земле под машиной»: если точка висит ниже колёс или дальше
         корпуса на дистанцию таблички — это ошибка автокрепления, а не
         нормальное место. ]]
    local function validateMountPoint(veh, pos)
        local isVec = isvector or function(v) return type(v) == "Vector" or (istable(v) and v.x ~= nil and v.y ~= nil and v.z ~= nil) end
        if not (IsValid(veh) and isVec(pos)) then return false, "нет точки" end
        local wmin, wmax
        if isfunction(veh.WorldSpaceAABB) then wmin, wmax = veh:WorldSpaceAABB()
        else local a,b = veh:OBBMins(), veh:OBBMaxs(); local p=veh:GetPos(); wmin,wmax=p+a,p+b end
        if not (wmin and wmax) then return true end
        local h = math.max(8, wmax.z - wmin.z)
        local floorZ = wmin.z + math.Clamp(h * 0.18, 12, 24)
        if pos.z < floorZ then
            return false, "точка ниже уровня кузова"
        end
        -- расстояние до ближайшей точки корпуса
        local base = vehicleBase(veh) or veh
        local near = base.NearestPoint and base:NearestPoint(pos) or pos
        if pos:Distance(near) > 16 then
            return false, "точка не на кузове"
        end
        return true
    end
    PL.ValidateMountPoint = validateMountPoint

    function PL.MountEnds(veh)
        if not IsValid(veh) then return nil, nil end
        local fwd = veh:GetForward()
        fwd.z = 0
        if fwd:Length() < 0.15 and isfunction(veh.LocalToWorld) then
            local wx = veh:LocalToWorld(Vector(1, 0, 0)) - veh:GetPos()
            wx.z = 0
            local wy = veh:LocalToWorld(Vector(0, 1, 0)) - veh:GetPos()
            wy.z = 0
            fwd = (wx:Length() >= wy:Length()) and wx or wy
        end
        if fwd:Length() < 0.05 then fwd = Vector(1, 0, 0) else fwd:Normalize() end
        return hullEndHit(veh, fwd), hullEndHit(veh, -fwd)
    end

    function PL.MountPointFor(veh, wantFront, nearPos)
        if not IsValid(veh) then return nil, "Транспорт не найден" end

        -- 1) раскладка КЛАССА (сохранённая кнопкой «для всех таких»)
        local layout = PL.LayoutFor and PL.LayoutFor(veh)
        if istable(layout) and layout.enabled ~= false and isfunction(veh.LocalToWorld) then
            local p = Vector(layout.pos.x, layout.pos.y, layout.pos.z)
            local world = veh:LocalToWorld(p)
            local nrm = (veh:LocalToWorld(Vector(layout.normal.x, layout.normal.y, layout.normal.z)) - veh:GetPos()):GetNormalized()
            local up = layout.upHint and Vector(layout.upHint.x, layout.upHint.y, layout.upHint.z) or veh:GetUp()
            return { pos = world, normal = nrm, up = up, layout = layout }
        end

        -- 2) ПАМЯТЬ КОНКРЕТНОЙ МАШИНЫ (после редактирования/снятия)
        local mem = readVehicleMemory(veh)
        if mem and isfunction(veh.LocalToWorld) then
            local world = veh:LocalToWorld(mem.pos)
            --[[ ПАМЯТЬ ПРОВЕРЯЕМ, А НЕ СЛЕПО ВЕРИМ (жалоба 31.08).

                 Пока память применялась без проверки, однажды
                 неудачно посчитанная точка залипала навсегда: знак
                 возвращался в неё и после правки расчёта, и после
                 смены кузова. Теперь если память села мимо корпуса
                 или ниже уровня кузова — её игнорируем и считаем
                 авто-точку заново. Ручная подгонка, сделанная
                 стрелками, всегда лежит на кузове, поэтому её это
                 не заденет. ]]
            if validateMountPoint(veh, world) then
                local nrm = veh:LocalToWorldAngles(mem.ang):Forward()
                return { pos = world, normal = nrm, up = veh:GetUp(),
                    exact = true,
                    setPlate = function(plate) plate:SetPos(world); plate:SetAngles(veh:LocalToWorldAngles(mem.ang)) end }
            end
        end

        -- 3) авто-точка
        local front, rear = PL.MountEnds(veh)
        if wantFront == true then return front or rear end
        if wantFront == false then return rear or front end
        if nearPos and front and rear then
            if nearPos:DistToSqr(front.pos) < nearPos:DistToSqr(rear.pos) then return front end
            return rear
        end
        return rear or front
    end

    --- Повесить знак на задний борт машины по её габаритам.
    function PL.MountOnRear(plate, veh, actor)
        if not (IsValid(plate) and IsValid(veh)) then return false end
        local mount = PL.MountPointFor(veh)
        if not mount then
            -- у нестандартных сущностей габаритов может не быть: тогда просто
            -- крепим как есть, без вычисления борта
            return PL.Attach(plate, veh, actor)
        end
        --[[ ПАМЯТЬ/КЛАСС: если позиция задана вручную (редактор или кнопка
             «для всех таких»), ставим знак ТОЧНО в сохранённые pos/ang —
             без автонормали и валидации, иначе ручная подгонка собьётся. ]]
        if mount.exact and isfunction(mount.setPlate) then
            mount.setPlate(plate)
            return PL.Attach(plate, veh, actor)
        end
        --[[ ВАЛИДАЦИЯ. Если авто-точка села ниже уровня кузова или мимо
             корпуса (редкий баг геометрии модели), не крепим вслепую:
             пробуем второй (передний) борт, и только если и он не валиден —
             крепим по ручной позиции знака (игрок хотя бы видит, куда ставит).
             Так в БД не уезжает «знак на земле под машиной». ]]
        local ok = validateMountPoint(veh, mount.pos)
        if not ok then
            local alt = select(2, PL.MountEnds(veh))
            if alt and validateMountPoint(veh, alt.pos) then
                mount = alt
            elseif plate:GetPos():Distance(plate:GetPos()) == 0 then
                mount = nil
            end
        end
        if mount then
            PL.PlaceOnSurface(plate, mount.pos, mount.normal, mount.up)
            --[[ АВТО-ТОЧКУ НЕ ЗАПОМИНАЕМ КАК «ТАК ХОТЕЛ ИГРОК».

                 Attach по умолчанию пишет позицию в память машины,
                 чтобы знак возвращался ровно на место. Пока авто-точка
                 писалась наравне с ручной, первый же — пусть и
                 неудачный — расчёт залипал: исправление расчёта уже
                 ничего не меняло, знак вставал в запомненную кривую
                 точку. Теперь запоминается только осознанное
                 размещение: взгляд в кузов, стрелки в редакторе,
                 раскладка на класс. ]]
            if not mount.layout and not mount.exact then
                plate.GRMPlateAutoPlaced = true
            end
        end
        return PL.Attach(plate, veh, actor)
    end

    --[[ РЕДАКТОР ПОЛОЖЕНИЯ УЖЕ ЗАКРЕПЛЁННОГО ЗНАКА.

         Игрок/сотрудник открывает меню знака и двигает его стрелками с
         шагом 1/5/20 см либо поворачивает. Правки применяются к локальной
         позиции внутри родителя и сразу пересохраняют раскладку: и в записи
         гаража/автопарка, и в реестре (rec.mount), поэтому позиция
         переживает рестарт и выдачу машины заново.

         Вариант «сохранить для всех таких машин» пишет class-layout в
         render.json (как /номер_layout), но уже из UI, а не командой. ]]
    function PL.NudgeMounted(plate, kind, axis, delta, forClass)
        if not IsValid(plate) then return false, "Знак не найден" end
        local veh = plate:GetParent()
        if not IsValid(veh) then return false, "Знак не закреплён" end
        local lp = veh:WorldToLocal(plate:GetPos())
        local la = veh:WorldToLocalAngles(plate:GetAngles())
        local pos = { x = lp.x, y = lp.y, z = lp.z }
        local ang = { p = la.p, y = la.y, r = la.r }
        -- Точка отсчёта для предела: где знак стоял до начала подгонки.
        if not istable(plate.GRMNudgeBase) then
            plate.GRMNudgeBase = { pos = { x = pos.x, y = pos.y, z = pos.z },
                                   ang = { p = ang.p, y = ang.y, r = ang.r } }
        end

        local cur = PL.BlankMount()
        cur.pos, cur.ang = pos, ang
        local moved, ok2 = PL.NudgeMount(cur, kind, axis, delta, plate.GRMNudgeBase)
        if not ok2 then return false, "Неизвестная ось" end

        --[[ ПОЛ КУЗОВА (жалоба владельца 31.08: «почему-то под машиной
             куда-то вниз уходит»). Стрелкой «вниз» знак можно было
             увести под днище и даже под дорогу: предел ±64 отсчитывался
             от нуля, а не от бампера. Теперь ниже плоскости колёс не
             опускаем — бампер он и есть бампер, ниже некуда. ]]
        if kind == "move" and (axis == "z" or axis == "x" or axis == "y") then
            local wmin, wmax
            if isfunction(veh.WorldSpaceAABB) then
                wmin, wmax = veh:WorldSpaceAABB()
            else
                local a, b = veh:OBBMins(), veh:OBBMaxs()
                local vp = veh:GetPos()
                wmin, wmax = vp + a, vp + b
            end
            if wmin and wmax then
                local h = math.max(8, wmax.z - wmin.z)
                local floorZ = wmin.z + math.Clamp(h * 0.18, 12, 24)
                local wz = veh:LocalToWorld(Vector(moved.pos.x, moved.pos.y, moved.pos.z)).z
                if wz < floorZ then
                    return false, "Ниже уровня кузова знак не опускаем"
                end
            end
        end
        plate:SetLocalPos(Vector(moved.pos.x, moved.pos.y, moved.pos.z))
        plate:SetLocalAngles(Angle(moved.ang.p, moved.ang.y, moved.ang.r))
        rememberLayout(veh)
        -- Каждое движение пишется в память КОНКРЕТНОЙ машины — после
        -- снятия/повторной установки позиция не забудется.
        saveVehicleMemory(veh,
            Vector(moved.pos.x, moved.pos.y, moved.pos.z),
            Angle(moved.ang.p, moved.ang.y, moved.ang.r))
        local number = PL.NormalizeNumber(plate:GetNWString("GRM_Plate", ""))
        local rec = PL.Get(number)
        if rec then
            rec.mount = rec.mount or PL.BlankMount()
            rec.mount.pos = { x = moved.pos.x, y = moved.pos.y, z = moved.pos.z }
            rec.mount.ang = { p = moved.ang.p, y = moved.ang.y, r = moved.ang.r }
            PL.Save("правка положения знака")
        end
        return true
    end

    --[[ Сохранить текущее положение знака как РАСКЛАДКУ КЛАССА машины.
         Тогда любая установка на транспорт этого класса (например
         simfphys_mafia2_jeep) будет использовать ту же позицию. ]]
    function PL.SaveClassLayoutFromPlate(plate)
        if not IsValid(plate) then return false, "Знак не найден" end
        local veh = plate:GetParent()
        if not IsValid(veh) then return false, "Знак не закреплён" end
        local lp = veh:WorldToLocal(plate:GetPos())
        local la = veh:WorldToLocalAngles(plate:GetAngles())
        saveVehicleMemory(veh, lp, la)
        local class = PL.ClassFor(veh)
        PL.SetLayout(class, {
            pos = { x = lp.x, y = lp.y, z = lp.z },
            normal = { x = -1, y = 0, z = 0 },
            upHint = { x = 0, y = 0, z = 1 },
            enabled = true,
        })
        return true, class
    end

    --- Сбросить знак на авто-точку борта (срабатывает и для ручного layout).
    function PL.ReattachAuto(plate, veh, actor)
        if not (IsValid(plate) and IsValid(veh)) then return false end
        local class = tostring(veh:GetClass() or "")
        -- временно убираем class-layout И память машины, чтобы взять чистую авто-точку
        local savedLayout = PL.Layouts and PL.Layouts[class] or nil
        if PL.Layouts then PL.Layouts[class] = nil end
        clearVehicleMemory(veh)
        local mount = PL.MountPointFor(veh)
        if savedLayout and PL.Layouts then PL.Layouts[class] = savedLayout end
        if mount then
            if mount.exact and isfunction(mount.setPlate) then mount.setPlate(plate)
            else PL.PlaceOnSurface(plate, mount.pos, mount.normal, mount.up) end
            rememberLayout(veh)
            local number = PL.NormalizeNumber(plate:GetNWString("GRM_Plate", ""))
            local rec = PL.Get(number)
            if rec then
                local lp = veh:WorldToLocal(plate:GetPos())
                local la = veh:WorldToLocalAngles(plate:GetAngles())
                rec.mount = rec.mount or PL.BlankMount()
                rec.mount.pos = { x = lp.x, y = lp.y, z = lp.z }
                rec.mount.ang = { p = la.p, y = la.y, r = la.r }
                PL.Save("авто-крепление знака")
            end
            -- авто-крепление тоже запоминаем по этой машине
            local _lp = veh:WorldToLocal(plate:GetPos())
            local _la = veh:WorldToLocalAngles(plate:GetAngles())
            saveVehicleMemory(veh, _lp, _la)
            return true
        end
        return false
    end

    --- Выдать и повесить ведомственный номер, если его ещё нет.
    function PL.EnsureServicePlate(ply, ent, faction, uid)
        if not cvAuto:GetBool() then return false end
        if not IsValid(ent) then return false end
        uid = tostring(uid or ((GRM.Vehicles and GRM.Vehicles.EnsureUID) and GRM.Vehicles.EnsureUID(ent) or ""))
        if uid == "" then return false end

        -- номер уже закреплён за этой машиной — просто вернём его на место
        local existing = PL.PlateOfVehicleKey(uid)
        if existing ~= "" then
            if #PL.VehiclePlates(ent) > 0 then return true end
            local rec = PL.Get(existing)
            local mount = rec and istable(rec.mount) and rec.mount or nil
            local plate = PL.SpawnPlate(existing,
                mount and ent:LocalToWorld(Vector(mount.pos.x, mount.pos.y, mount.pos.z)) or ent:GetPos(),
                mount and ent:LocalToWorldAngles(Angle(mount.ang.p, mount.ang.y, mount.ang.r)) or ent:GetAngles(),
                ply)
            if IsValid(plate) then
                if mount then PL.Attach(plate, ent, ply) else PL.MountOnRear(plate, ent, ply) end
            end
            return true
        end

        local kind = PL.ServiceKind(faction)
        local rec = PL.Issue({
            type = kind,
            ownerKey = "faction:" .. tostring(faction or ""),
            ownerName = tostring(faction or "Организация"),
            faction = tostring(faction or ""),
            vehicle = (GRM.Vehicles and GRM.Vehicles.Title) and GRM.Vehicles.Title(ent) or tostring(ent:GetClass()),
            byName = "автоучёт",
            note = "служебный транспорт",
        })
        if not rec then return false end

        local plate = PL.SpawnPlate(rec.number, ent:GetPos(), ent:GetAngles(), ply)
        if not IsValid(plate) then return false end
        return PL.MountOnRear(plate, ent, ply)
    end

    --[[ ВЕРНУТЬ РУЧНОЙ НОМЕР ЗА ЕДИНИЦЕЙ АВТОПАРКА.
         Автоматическая генерация номера у автопарка отключена, но если
         сотрудник зарегистрировал номер вручную (UID "fleet:<id>"), он
         должен вернуться на ту же машину при следующей выдаче — как у
         личного транспорта. Здесь только «вернуть», новый номер НЕ
         создаётся. ]]
    function PL.RestoreFleetPlate(ent, uid, unit)
        if not IsValid(ent) then return 0 end
        uid = tostring(uid or ((GRM.Vehicles and GRM.Vehicles.EnsureUID) and GRM.Vehicles.EnsureUID(ent) or ""))
        if uid == "" then return 0 end
        if #PL.VehiclePlates(ent) > 0 then return 1 end
        if istable(unit) and istable(unit.plates) and #unit.plates > 0 then
            -- Раскладка из записи единицы автопарка (та, что записана в базе).
            local restored = 0
            for _, saved in ipairs(unit.plates) do
                if istable(saved) then
                    local number = PL.NormalizeNumber(saved.number)
                    if number ~= "" and PL.Get(number) then
                        local lp = Vector(tonumber(saved.pos and saved.pos.x) or 0,
                            tonumber(saved.pos and saved.pos.y) or 0, tonumber(saved.pos and saved.pos.z) or 0)
                        local la = Angle(tonumber(saved.ang and saved.ang.p) or 0,
                            tonumber(saved.ang and saved.ang.y) or 0, tonumber(saved.ang and saved.ang.r) or 0)
                        local plate = PL.SpawnPlate(number, ent:LocalToWorld(lp), ent:LocalToWorldAngles(la),
                            IsValid(ent.GRMGarageOwner) and ent.GRMGarageOwner or nil)
                        if IsValid(plate) and PL.Attach(plate, ent, ent.GRMGarageOwner) then restored = restored + 1 end
                    end
                end
            end
            return restored
        end
        local existing = PL.PlateOfVehicleKey(uid)
        if existing == "" then return 0 end
        local rec = PL.Get(existing)
        local mount = rec and istable(rec.mount) and rec.mount or nil
        local owner = IsValid(ent.GRMGarageOwner) and ent.GRMGarageOwner or nil
        local plate = PL.SpawnPlate(existing,
            mount and ent:LocalToWorld(Vector(mount.pos.x, mount.pos.y, mount.pos.z)) or ent:GetPos(),
            mount and ent:LocalToWorldAngles(Angle(mount.ang.p, mount.ang.y, mount.ang.r)) or ent:GetAngles(),
            owner)
        if not IsValid(plate) then return 0 end
        if mount then PL.Attach(plate, ent, owner) else PL.MountOnRear(plate, ent, owner) end
        return 1
    end

    --[[ Автоматический вызов EnsureServicePlate для единиц автопарка
         убран по заказу владельца 22.08: закупленная в автопарк техника
         не должна получать гражданский/ведомственный номер сама. Номер
         таким машинам ставится вручную, как и личному транспорту. ]]
    hook.Add("GRM_FleetIssued", "GRM_Plates_FleetRestore", function(ply, ent, unit)
        if not (IsValid(ent) and istable(unit)) then return end
        timer.Simple(0.2, function()
            if not IsValid(ent) then return end
            PL.RestoreFleetPlate(ent, "fleet:" .. tostring(unit.id), unit)
        end)
    end)

    --[[ МАШИНУ УБРАЛИ — НОМЕР ОСТАЛСЯ ЗА НЕЙ.
         Когда машина уезжает в гараж или удаляется с карты, её знаки
         исчезают вместе с ней (они припаркованы к энтити). Раньше это
         выглядело как «знак пропал»: в реестре крепление оставалось, но
         никто не помечал, что машина сейчас не на карте. Теперь запись
         остаётся с пометкой «в гараже», а сам знак вернётся на ту же
         машину при следующей выдаче — по UID, а не по имени класса. ]]
    hook.Add("EntityRemoved", "GRM_Plates_VehicleGone", function(ent)
        if not IsValid(ent) then return end
        if ent:GetClass() == "grm_plate" then return end
        if not (PL.LooksLikeVehicle and PL.LooksLikeVehicle(ent)) then return end
        local uid = (GRM.Vehicles and GRM.Vehicles.UID) and GRM.Vehicles.UID(ent) or ""
        if uid == "" then return end
        local touched = false
        for _, rec in pairs(PL.Data.plates or {}) do
            local mount = istable(rec.mount) and rec.mount or nil
            if mount and tostring(mount.parentKey or mount.vehicleID or "") == uid then
                mount.offMap = true
                mount.at = os.time()
                touched = true
            end
        end
        if touched then PL.Save("машина убрана с карты") end
    end)

    -- ── команды и сеть ──────────────────────────────────────────────

    local function onlineList()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                local rp = p:GetNWString("GRM_RPName", "")
                if rp == "" then rp = p:Nick() end
                out[#out + 1] = {
                    key = charKey(p), name = rp, nick = p:Nick(),
                    faction = p:GetNWString("GRM_Faction", ""),
                }
            end
        end
        table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
        return out
    end

    local function factionList()
        local out = {}
        for name, f in pairs(istable(Factions) and Factions or {}) do
            if istable(f) then
                out[#out + 1] = {
                    key = tostring(name),
                    name = tostring(f.DisplayName or f.displayName or name),
                    tag = tostring(f.Tag or ""),
                }
            end
        end
        table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
        return out
    end

    local function packRec(rec)
        if not istable(rec) then return nil end
        return {
            number = rec.number, type = rec.type, status = rec.status,
            ownerName = rec.ownerName, ownerKey = rec.ownerKey, faction = rec.faction,
            vehicle = rec.vehicle, note = rec.note, issued = rec.issued, byName = rec.byName,
            mounted = istable(rec.mount) and true or false,
            mountVehicle = istable(rec.mount) and tostring(rec.mount.parentName or rec.mount.vehicle or "") or "",
            mountKey = istable(rec.mount) and tostring(rec.mount.parentKey or rec.mount.vehicleID or "") or "",
            mountOffMap = istable(rec.mount) and rec.mount.offMap == true or false,
        }
    end

    --[[ СНИМОК ОКНА — ПОРЦИЯМИ.
         Раньше три таблицы (мои знаки, игроки онлайн, найденный номер)
         уходили одним net.WriteTable: на большом реестре это заметный пакет
         и микрофриз у получателя. Теперь снимок идёт через GRM.Net.Stream —
         он режет данные на куски и отдаёт их по кадрам. Плюс серия действий
         подряд схлопывается в одну отправку (GRM.Perf.Coalesce). ]]
    local function buildSnapshot(ply, found)
        local mine = {}
        local facName = ply:GetNWString("GRM_Faction", "")
        for _, rec in ipairs(PL.ListVisibleFor(charKey(ply), facName)) do mine[#mine + 1] = packRec(rec) end
        local officer, why = PL.IssueReason(ply)
        return {
            mine = mine,
            officer = officer == true,
            officerReason = tostring(why or ""),
            youKey = charKey(ply),
            youName = ply:GetNWString("GRM_RPName", ply:Nick()),
            youFaction = facName,
            online = officer and onlineList() or {},
            factions = officer and factionList() or {},
            found = found and { packRec(found) } or {},
        }
    end

    function PL.Push(ply, found)
        if not IsValid(ply) then return end
        local payload = buildSnapshot(ply, found)
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream(PL.Net.SYNC, payload, ply, { chunk = 8192, interval = 0.03 })
            return
        end
        net.Start(PL.Net.SYNC)
            net.WriteTable(payload.mine)
            net.WriteBool(payload.officer)
            net.WriteTable(payload.online)
            net.WriteTable(payload.found)
        net.Send(ply)
    end

    --- Отложенная отправка: пачка действий = один снимок.
    function PL.PushSoon(ply, found)
        if not IsValid(ply) then return end
        if found or not (GRM.Perf and GRM.Perf.Coalesce) then return PL.Push(ply, found) end
        GRM.Perf.Coalesce("plates.push." .. tostring(ply:SteamID64() or ply:EntIndex()), 0.15, function()
            if IsValid(ply) then PL.Push(ply) end
        end)
    end

    function PL.Open(ply)
        if not IsValid(ply) then return end
        net.Start(PL.Net.OPEN)
        net.Send(ply)
        PL.Push(ply)
    end

    --[[ Права выдали — обновляем окна у всех, у кого они открыты.
         Пачка изменений (лидер щёлкает несколько галочек подряд) схлопывается
         в одну рассылку через Coalesce: рывка не будет. ]]
    --[[ Модуль представляется общему реестру: теперь другие подсистемы
         знают, что знаки есть, а шина обновлений сама позовёт Refresh при
         любой смене прав, должности или персонажа. ]]
    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("plates", {
            label = "Номерные знаки", version = PL.Version or "1.0.0",
            Depends = { "access" },
            Refresh = function(ply)
                if IsValid(ply) then PL.Push(ply) return end
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) then PL.Push(p) end
                end
            end,
            Status = function()
                local n = 0
                for _ in pairs(PL.Data.plates or {}) do n = n + 1 end
                return ("номеров в реестре: %d"):format(n)
            end,
        })
    end

    hook.Add("GRM_AccessChanged", "GRM_Plates_AccessChanged", function()
        local function pushAll()
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then PL.Push(p) end
            end
        end
        if GRM.Perf and GRM.Perf.Coalesce then
            GRM.Perf.Coalesce("plates.access.push", 0.5, pushAll)
        else
            timer.Simple(0.5, pushAll)
        end
    end)

    hook.Add("GRM_FactionRoleChanged", "GRM_Plates_RoleChanged", function(ply)
        if IsValid(ply) then timer.Simple(0.3, function() if IsValid(ply) then PL.Push(ply) end end) end
    end)

    net.Receive(PL.Net.ACT, function(_, ply)
        if not IsValid(ply) then return end
        ply.GRMPlateNext = ply.GRMPlateNext or 0
        if CurTime() < ply.GRMPlateNext then return end
        ply.GRMPlateNext = CurTime() + 0.35

        local act = net.ReadString()
        local data = net.ReadTable() or {}

        if act == "refresh" then
            -- Первый снимок отдаём СРАЗУ: окно только что открылось, и
            -- ждать даже долю секунды незачем (жалоба владельца: «на старте
            -- пишет, что доступа нет»).
            PL.SetViewer(ply, true)
            PL.Push(ply)

        elseif act == "watch" then
            -- окно открыли или закрыли: подписка на живые обновления
            PL.SetViewer(ply, data.on == true)
            if data.on == true then PL.PushSoon(ply) end

        elseif act == "issue" then
            if not PL.CanIssue(ply) then notify(ply, "Выдавать номера может только Полиция и Автоинспекция.") return end
            local rec, err
            local ownerKind = tostring(data.ownerKind or "player")
            if ownerKind == "faction" then
                local facName = tostring(data.faction or "")
                if facName == "" then notify(ply, "Укажите организацию.") return end
                if GRM.Economy and GRM.Economy.ResolveFactionKey then
                    facName = tostring(GRM.Economy.ResolveFactionKey(facName) or facName)
                end
                local disp = facName
                if istable(Factions) and istable(Factions[facName]) then
                    disp = tostring(Factions[facName].DisplayName or Factions[facName].displayName or facName)
                end
                rec, err = PL.Issue({
                    type = data.type, number = data.number,
                    ownerKey = PL.FactionOwnerKey(facName),
                    ownerName = disp, faction = facName,
                    vehicle = data.vehicle, note = data.note,
                    by = charKey(ply), byName = ply:Nick(),
                })
                if not rec then notify(ply, tostring(err or "Не удалось выдать номер")) return end
                notify(ply, ("Номер %s зарегистрирован на организацию «%s»."):format(
                    PL.FormatNumber(rec.number, rec.type), disp), true)
            else
                local target = nil
                for _, p in ipairs(player.GetAll()) do
                    if IsValid(p) and charKey(p) == tostring(data.ownerKey or "") then target = p break end
                end
                if not IsValid(target) then notify(ply, "Владелец не в сети.") return end
                rec, err = PL.Issue({
                    type = data.type, number = data.number,
                    ownerKey = charKey(target),
                    ownerName = target:GetNWString("GRM_RPName", target:Nick()),
                    faction = target:GetNWString("GRM_Faction", ""),
                    vehicle = data.vehicle, note = data.note,
                    by = charKey(ply), byName = ply:Nick(),
                })
                if not rec then notify(ply, tostring(err or "Не удалось выдать номер")) return end
                notify(ply, ("Номер %s зарегистрирован на %s."):format(PL.FormatNumber(rec.number, rec.type), rec.ownerName), true)
                notify(target, ("Вам выдан регистрационный номер %s. Получите бланк командой /номера."):format(
                    PL.FormatNumber(rec.number, rec.type)), true)
                PL.PushSoon(target)
            end
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("plates", "issue", ply, { number = rec.number, owner = rec.ownerKey }, { type = rec.type })
            end
            PL.PushSoon(ply)

        elseif act == "edit" then
            if not PL.CanIssue(ply) then notify(ply, "Править реестр может только служба.") return end
            local rec = PL.Get(data.number)
            if not rec then notify(ply, "Номер не найден.") return end
            local fields = { vehicle = data.vehicle, note = data.note }
            local ownerKind = tostring(data.ownerKind or "")
            if ownerKind == "faction" then
                local facName = tostring(data.faction or "")
                if facName == "" then notify(ply, "Укажите организацию.") return end
                if GRM.Economy and GRM.Economy.ResolveFactionKey then
                    facName = tostring(GRM.Economy.ResolveFactionKey(facName) or facName)
                end
                local disp = facName
                if istable(Factions) and istable(Factions[facName]) then
                    disp = tostring(Factions[facName].DisplayName or Factions[facName].displayName or facName)
                end
                fields.ownerKey = PL.FactionOwnerKey(facName)
                fields.ownerName = disp
                fields.faction = facName
            elseif ownerKind == "player" then
                local target = nil
                for _, p in ipairs(player.GetAll()) do
                    if IsValid(p) and charKey(p) == tostring(data.ownerKey or "") then target = p break end
                end
                if not IsValid(target) then notify(ply, "Новый владелец не в сети.") return end
                fields.ownerKey = charKey(target)
                fields.ownerName = target:GetNWString("GRM_RPName", target:Nick())
                fields.faction = target:GetNWString("GRM_Faction", "")
            end
            local updated, err = PL.Update(data.number, fields, ply:Nick())
            if not updated then notify(ply, tostring(err or "Не удалось изменить запись")) return end
            notify(ply, ("Запись %s обновлена. Владелец: %s."):format(
                PL.FormatNumber(updated.number, updated.type), tostring(updated.ownerName)), true)
            PL.Push(ply, updated)

        elseif act == "spawn" then
            local rec = PL.Get(data.number)
            if not rec then notify(ply, "Номер не найден.") return end
            local mine = tostring(rec.ownerKey) == charKey(ply)
            local fac = ply:GetNWString("GRM_Faction", "")
            local org = fac ~= "" and tostring(rec.ownerKey) == PL.FactionOwnerKey(fac)
            if not (mine or org or PL.CanIssue(ply)) then notify(ply, "Это чужой номер.") return end
            if rec.status ~= "active" then
                notify(ply, ("Номер %s: %s — бланк не выдаётся."):format(
                    PL.FormatNumber(rec.number, rec.type), PL.Statuses[rec.status] or rec.status))
                return
            end
            local blanks = PL.SpawnLimitCvar:GetInt()
            if blanks > 0 and #PL.EntitiesOf(rec.number) >= blanks then
                notify(ply, ("Знаков с номером %s уже %d — больше не выдаём."):format(
                    PL.FormatNumber(rec.number, rec.type), blanks))
                return
            end
            local tr = ply:GetEyeTrace()
            local pos = (tr and tr.HitPos or ply:GetPos()) + Vector(0, 0, 6)
            if pos:Distance(ply:GetPos()) > 200 then pos = ply:GetPos() + ply:GetAimVector() * 60 + Vector(0, 0, 20) end
            local ent, err = PL.SpawnPlate(rec.number, pos, Angle(0, ply:EyeAngles().y - 90, 0), ply)
            if not IsValid(ent) then notify(ply, tostring(err or "Не удалось выдать бланк")) return end
            notify(ply, "Бланк знака выдан. Поставьте его физганом и нажмите [E], чтобы закрепить.", true)

        elseif act == "delete" then
            if not PL.CanIssue(ply) then notify(ply, "Удалять номера может только служба.") return end
            local del, errD = PL.Delete(data.number, ply:Nick())
            notify(ply, del and ("Номер %s удалён из реестра."):format(PL.FormatNumber(data.number))
                or tostring(errD), del == true)
            PL.PushSoon(ply)

        elseif act == "status" then
            if not PL.CanIssue(ply) then notify(ply, "Недостаточно прав.") return end
            local okSet, err = PL.SetStatus(data.number, data.status, ply:Nick())
            notify(ply, okSet and ("Номер %s: %s."):format(PL.FormatNumber(data.number), PL.Statuses[data.status] or "")
                or tostring(err), okSet)
            PL.PushSoon(ply)

        elseif act == "lost" then
            local rec = PL.Get(data.number)
            if not rec or tostring(rec.ownerKey) ~= charKey(ply) then notify(ply, "Это не ваш номер.") return end
            PL.SetStatus(rec.number, "lost", ply:Nick())
            notify(ply, "Заявление об утере принято. Обратитесь в Автоинспекцию за новым номером.", true)
            PL.PushSoon(ply)

        elseif act == "find" then
            if not PL.CanCheck(ply) then notify(ply, "Пробивать номера может только служба.") return end
            local rec = PL.Get(data.number)
            if not rec then
                notify(ply, ("Номер %s в базе не значится."):format(PL.FormatNumber(data.number)))
                PL.PushSoon(ply)
                return
            end
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("plates", "check", ply, { number = rec.number }, {})
            end
            PL.Push(ply, rec)

        --[[ РЕДАКТОР ПОЛОЖЕНИЯ. Клиент шлёт, какую именно живую пластину
             двигать (по entindex), и ось/шаг. Сервер сам повторно проверяет
             право (владелец знака или plates.issue) и родителя, чтобы
             подделкой пакета нельзя было двигать чужие номера. ]]
        elseif act == "nudge" then
            local plate = Entity(tonumber(data.ent) or -1)
            if not (IsValid(plate) and plate:GetClass() == "grm_plate") then
                notify(ply, "Знак не найден.") return
            end
            local canH, whyH = PL.CanHandle(ply, plate)
            if not canH then
                notify(ply, "Чужой знак двигать нельзя.") return
            end
            local okN, errN = PL.NudgeMounted(plate,
                tostring(data.kind or "move"), tostring(data.axis or "x"),
                tonumber(data.delta) or 1, data.forClass == true)
            if okN then notify(ply, "Положение знака обновлено.", true) else notify(ply, tostring(errN or "Не вышло")) end

        elseif act == "attach_auto" then
            local plate = Entity(tonumber(data.ent) or -1)
            if not (IsValid(plate) and plate:GetClass() == "grm_plate") then
                notify(ply, "Знак не найден.") return
            end
            local canH = PL.CanHandle(ply, plate)
            if not canH then notify(ply, "Чужой знак трогать нельзя.") return end
            local veh = plate:GetParent()
            if not IsValid(veh) then notify(ply, "Знак не закреплён — сначала [E] по бамперу.") return end
            if PL.ReattachAuto(plate, veh, ply) then
                notify(ply, "Знак переставлен на авто-точку борта.", true)
            else
                notify(ply, "Авто-точка не найдена — двигайте стрелками.")
            end

        elseif act == "detach" then
            local plate = Entity(tonumber(data.ent) or -1)
            if not (IsValid(plate) and plate:GetClass() == "grm_plate") then
                notify(ply, "Знак не найден.") return
            end
            if PL.CanHandle(ply, plate) then PL.HandlePlateUse(ply, plate) end

        --[[ Сохранить положение знака как РАСКЛАДКУ КЛАССА: все машины
             того же класса (например simfphys_mafia2_jeep) будут крепить
             номер в это место. ]]
        elseif act == "save_class" then
            local plate = Entity(tonumber(data.ent) or -1)
            if not (IsValid(plate) and plate:GetClass() == "grm_plate") then
                notify(ply, "Знак не найден.") return
            end
            if not PL.CanHandle(ply, plate) then notify(ply, "Чужой знак.") return end
            -- сохранять раскладку класса может только служба/суперадмин
            if not (ply:IsSuperAdmin() or PL.CanIssue(ply)) then
                notify(ply, "Сохранять для всего класса может только служба.") return
            end
            local okC, class = PL.SaveClassLayoutFromPlate(plate)
            if okC then
                notify(ply, ("Позиция сохранена для всех машин класса «%s»."):format(tostring(class)), true)
            else
                notify(ply, tostring(class or "Не удалось сохранить"))
            end
        end
    end)

    -- ── чат-команды ─────────────────────────────────────────────────
    local function chatCommand(ply, text)
        local msg = string.Trim(tostring(text or ""))
        local low = string.lower(msg)
        if low:find("^/номера") == 1 or low:find("^/plates") == 1 then
            PL.Open(ply)
            return true
        end
        if low == "/прикрепить" or low == "/номерприкрепить" or low == "/plateon" then
            local plate = nearestOwnPlate(ply, false)
            if not IsValid(plate) then notify(ply, "Рядом нет вашего свободного знака.") return true end
            PL.HandlePlateUse(ply, plate)
            return true
        end
        if low:find("^/номер_поворот") == 1 or low:find("^/plateyaw") == 1 then
            renderCommand(ply, "yaw", string.match(msg, "%s(%-?%d+)"))
            return true
        end
        if low:find("^/номер_ось") == 1 then renderCommand(ply, "axis") return true end
        if low:find("^/номер_зеркало") == 1 then renderCommand(ply, "flip") return true end
        if low:find("^/номер_масштаб") == 1 then
            renderCommand(ply, "scale", string.match(msg, "%s([%d%.]+)"))
            return true
        end
        if low:find("^/номер_вынос") == 1 then
            renderCommand(ply, "offset", string.match(msg, "%s([%d%.%-]+)"))
            return true
        end
        if low:find("^/номер_наклон") == 1 then
            local ax, val = string.match(msg, "^%S+%s+(%a)%s*(%-?[%d%.]*)")
            ax = string.lower(tostring(ax or "p"))
            local key = ax == "y" and "tiltY" or (ax == "r" and "tiltR" or "tiltP")
            renderCommand(ply, key, val)
            return true
        end
        if low:find("^/номер_сдвиг") == 1 then
            local ax, val = string.match(msg, "^%S+%s+(%a)%s*(%-?[%d%.]*)")
            ax = string.lower(tostring(ax or "x"))
            renderCommand(ply, ax == "y" and "moveY" or "moveX", val)
            return true
        end
        if low:find("^/номер_сброс") == 1 then renderCommand(ply, "reset") return true end
        if low:find("^/номер_настройки") == 1 then renderCommand(ply, "show") return true end
        --[[ ПОЛОЖЕНИЕ ЗНАКА НА МОДЕЛИ (заказ владельца 22.08).
             Без аргументов — сохранить layout машины, на которую смотришь
             (или на которой уже закреплён знак). С аргументами
             x y z [nx ny nz] [ux uy uz] — задать вручную. Суперадмин. ]]
        if low:find("^/номер_layout") == 1 or low:find("^/number_layout") == 1 then
            if not (IsValid(ply) and ply:IsSuperAdmin()) then
                notify(ply, "Настройка положения знаков — суперадмин.")
                return true
            end
            local nums = {}
            for w in string.gmatch(msg, "%-?%d+%.?%d*") do nums[#nums + 1] = tonumber(w) or 0 end
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply) or ply:GetEyeTrace()
            local base = tr and tr.Entity and PL.VehicleBase(tr.Entity) or nil
            if not IsValid(base) then base = nil end
            -- Если смотришь на знак/машину не нашли — берём машину со знаком
            if not IsValid(base) then
                local own = nearestOwnPlate(ply, true)
                if IsValid(own) and IsValid(own:GetParent()) then base = PL.VehicleBase(own:GetParent()) end
            end
            if not IsValid(base) then
                notify(ply, "Смотрите на транспорт (или на знак) и повторите команду.")
                return true
            end
            local class = PL.ClassFor(base)
            if #nums >= 3 then
                local layout = PL.SetLayout(class, {
                    pos = { x = nums[1], y = nums[2], z = nums[3] },
                    normal = { x = nums[4] or -1, y = nums[5] or 0, z = nums[6] or 0 },
                    upHint = { x = nums[7] or 0, y = nums[8] or 0, z = nums[9] or 1 },
                    enabled = true,
                })
                notify(ply, layout and ("Положение знака для «%s» сохранено."):format(class) or "Не сохранилось")
            else
                local vp = PL.VehiclePlates(base)
                local plate = vp and vp[1]
                if IsValid(plate) then
                    local lp = base:WorldToLocal(plate:GetPos())
                    local layout = PL.SetLayout(class, {
                        pos = { x = lp.x, y = lp.y, z = lp.z },
                        normal = { x = -1, y = 0, z = 0 },
                        upHint = { x = 0, y = 0, z = 1 },
                        enabled = true,
                    })
                    notify(ply, layout and ("Положение знака для «%s» запомнено: %.1f, %.1f, %.1f"):format(
                        class, lp.x, lp.y, lp.z) or "Не запомнилось")
                else
                    notify(ply, "На этой машине нет закреплённого знака — сначала закрепите его.")
                end
            end
            return true
        end
        if low:find("^/номер_layout_сброс") == 1 or low:find("^/number_layout_reset") == 1 then
            if not (IsValid(ply) and ply:IsSuperAdmin()) then notification.AddLegacy("Только суперадмин", NOTIFY_ERROR, 3) return true end
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply) or ply:GetEyeTrace()
            local base = tr and tr.Entity and PL.VehicleBase(tr.Entity) or nil
            if not IsValid(base) then
                local own = nearestOwnPlate(ply, true)
                if IsValid(own) and IsValid(own:GetParent()) then base = PL.VehicleBase(own:GetParent()) end
            end
            if not IsValid(base) then notify(ply, "Смотрите на транспорт.") return true end
            local class = tostring(base:GetClass() or "")
            PL.SetLayout(class, nil)
            notify(ply, ("Ручное положение знака для «%s» убрано — работает автоматика."):format(class))
            return true
        end
        if low == "/снятьномер" or low == "/plateoff" then
            local plate = nearestOwnPlate(ply, true)
            if not IsValid(plate) then notify(ply, "Рядом нет закреплённого знака.") return true end
            PL.HandlePlateUse(ply, plate)
            return true
        end
        --[[ Выдача номера командой — на случай, когда терминала нет под
             рукой: /номер_выдать <часть ника> [тип] [номер].
             Тип по умолчанию civil; номер пустой — система подберёт сама. ]]
        if low:find("^/номер_выдать") == 1 or low:find("^/plate_issue") == 1 then
            local okIssue, why = PL.IssueReason(ply)
            if not okIssue then
                notify(ply, "Выдавать номера может только служба (" .. tostring(why) .. ").")
                return true
            end
            local args = {}
            for word in string.gmatch(msg, "%S+") do args[#args + 1] = word end
            local nick = tostring(args[2] or "")
            if nick == "" then
                notify(ply, "Как пользоваться: /номер_выдать <ник> [тип] [номер]. Типы: " ..
                    table.concat((function() local t = {} for _, d in ipairs(PL.TypeList()) do t[#t + 1] = d.key end return t end)(), ", "))
                return true
            end
            local target
            local needle = string.lower(nick)
            for _, p in ipairs(player.GetAll()) do
                if IsValid(p) and (string.find(string.lower(p:Nick()), needle, 1, true)
                    or string.find(string.lower(p:GetNWString("GRM_RPName", "")), needle, 1, true)) then
                    target = p break
                end
            end
            if not IsValid(target) then notify(ply, "Игрок «" .. nick .. "» не найден в сети.") return true end
            local kind = tostring(args[3] or "civil")
            if not PL.TypeDef(kind) then kind = "civil" end
            local rec, err = PL.Issue({
                type = kind, number = tostring(args[4] or ""),
                ownerKey = charKey(target),
                ownerName = target:GetNWString("GRM_RPName", target:Nick()),
                faction = target:GetNWString("GRM_Faction", ""),
                by = charKey(ply), byName = ply:Nick(),
            })
            if not rec then notify(ply, tostring(err or "Не удалось выдать номер")) return true end
            notify(ply, ("Номер %s зарегистрирован на %s."):format(
                PL.FormatNumber(rec.number, rec.type), rec.ownerName), true)
            notify(target, ("Вам выдан регистрационный номер %s. Бланк — команда /номера."):format(
                PL.FormatNumber(rec.number, rec.type)), true)
            PL.PushSoon(ply) PL.PushSoon(target)
            return true
        end
        if low == "/номер_статус" or low == "/plate_status" then
            local okIssue, why = PL.IssueReason(ply)
            ply:ChatPrint(("[Номера] Право регистрации: %s (%s)"):format(okIssue and "есть" or "нет", tostring(why)))
            ply:ChatPrint(("[Номера] Ваша организация: %s"):format(
                ply:GetNWString("GRM_Faction", "") ~= "" and ply:GetNWString("GRM_Faction", "") or "нет"))
            ply:ChatPrint(("[Номера] Знаков на вас: %d"):format(#PL.ListFor(charKey(ply))))
            return true
        end
        if low:find("^/номер%s") == 1 or low:find("^/plate%s") == 1 then
            local arg = string.match(msg, "^%S+%s+(.+)$") or ""
            if not PL.CanCheck(ply) then
                notify(ply, "Пробивать номера может только служба.")
                return true
            end
            local rec = PL.Get(arg)
            if not rec then
                notify(ply, ("Номер %s в базе не значится."):format(PL.FormatNumber(arg)))
                return true
            end
            ply:ChatPrint(("[Учёт ТС] %s — %s"):format(PL.FormatNumber(rec.number, rec.type), PL.TypeDef(rec.type).name))
            ply:ChatPrint(("  Владелец: %s%s"):format(tostring(rec.ownerName or "—"),
                rec.faction ~= "" and (" (" .. rec.faction .. ")") or ""))
            ply:ChatPrint(("  Статус: %s   •   выдан: %s (%s)"):format(
                PL.Statuses[rec.status] or tostring(rec.status),
                os.date("%d.%m.%Y", tonumber(rec.issued) or os.time()), tostring(rec.byName or "—")))
            if rec.vehicle and rec.vehicle ~= "" then ply:ChatPrint("  Транспорт: " .. rec.vehicle) end
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_Plates_Chat", function(ply, text)
        if chatCommand(ply, text) then return "" end
    end)
    hook.Add("PlayerSay", "GRM_Plates_ChatT", function(ply, text, teamSays)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(pack) or not isstring(pack[1]) then return end
            if chatCommand(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end

        if pack.SkipPlayerSay == true then return "" end
    end)

    concommand.Add("grm_plates", function(ply) PL.Open(ply) end)

    concommand.Add("grm_plate_issue", function(ply, _, args)
        chatCommand(ply, "/номер_выдать " .. table.concat(args or {}, " "))
    end)
    concommand.Add("grm_plate_status", function(ply) chatCommand(ply, "/номер_статус") end)

    --[[ РЕЕСТР РЕЖИМОВ ПОДГОНКИ (ГРМ §5.4). Подгонка надписи прямо в игре:
         смотришь на знак, крутишь — видно сразу, и настройка сохраняется
         для всех. Раньше восемь веток if/elseif переписывали поле по имени
         `what`; наклон и сдвиг имели общие ветки `tiltP or tiltY or tiltR`
         — верный признак, что это режимы одной таблицы. Новый режим теперь
         одна запись, а неизвестный ключ (в т.ч. «show») молча ничего не
         меняет и лишь показывает текущие значения, как и раньше. ]]
    local RENDER_ADJUST = {
        yaw = function(r, v) r.yaw = ((tonumber(r.yaw) or 0) + (v or 90)) % 360 end,
        axis = function(r)
            local order = { auto = "x", x = "y", y = "z", z = "auto" }
            r.axis = order[tostring(r.axis or "auto")] or "auto"
        end,
        flip = function(r) r.flip = not r.flip end,
        scale = function(r, v) r.scale = math.Clamp(v or 1, 0.2, 3) end,
        offset = function(r, v) r.offset = math.Clamp(v or 1.5, 0, 12) end,
        -- reset возвращает новую таблицу: диспетчер заменит PL.Render целиком
        reset = function() return PL.NormalizeRender({ axis = "auto", yaw = 90, scale = 1, offset = 1.5 }) end,
    }
    -- три оси наклона и две оси сдвига — одна формула, не три и две ветки:
    -- расхождение шага между ними было бы неотличимо глазом в лестнице
    for _, f in ipairs({ "tiltP", "tiltY", "tiltR" }) do
        RENDER_ADJUST[f] = function(r, v) r[f] = math.Clamp((tonumber(r[f]) or 0) + (v or 15), -180, 180) end
    end
    for _, f in ipairs({ "moveX", "moveY" }) do
        RENDER_ADJUST[f] = function(r, v) r[f] = math.Clamp((tonumber(r[f]) or 0) + (v or 1), -24, 24) end
    end

    function renderCommand(ply, what, value)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then
            notify(ply, "Настройка знаков — только суперадмин.")
            return
        end
        local adj = RENDER_ADJUST[what]
        if adj then
            local replaced = adj(PL.Render, tonumber(value))
            if replaced then PL.Render = replaced end
        end
        PL.Render = PL.NormalizeRender(PL.Render)
        PL.SaveRender()
        PL.PushRender()
        local r = PL.Render
        notify(ply, ("Знаки: ось %s • поворот %d° • зеркало %s • масштаб %.2f • вынос %.1f"):format(
            r.axis, r.yaw, r.flip and "да" or "нет", r.scale, r.offset), true)
        ply:ChatPrint(("[Знаки] наклон P %.0f° / Y %.0f° / R %.0f°   •   сдвиг X %.1f / Y %.1f"):format(
            r.tiltP, r.tiltY, r.tiltR, r.moveX, r.moveY))
    end
    PL.RenderCommand = renderCommand

    concommand.Add("grm_plate_yaw", function(ply, _, args) renderCommand(ply, "yaw", args and args[1]) end)
    concommand.Add("grm_plate_axis", function(ply) renderCommand(ply, "axis") end)
    concommand.Add("grm_plate_flip", function(ply) renderCommand(ply, "flip") end)
    concommand.Add("grm_plate_scale", function(ply, _, args) renderCommand(ply, "scale", args and args[1]) end)
    concommand.Add("grm_plate_offset", function(ply, _, args) renderCommand(ply, "offset", args and args[1]) end)
    concommand.Add("grm_plate_tilt", function(ply, _, args)
        local ax = string.lower(tostring(args and args[1] or "p"))
        local key = ax == "y" and "tiltY" or (ax == "r" and "tiltR" or "tiltP")
        renderCommand(ply, key, args and args[2])
    end)
    concommand.Add("grm_plate_move", function(ply, _, args)
        local ax = string.lower(tostring(args and args[1] or "x"))
        renderCommand(ply, ax == "y" and "moveY" or "moveX", args and args[2])
    end)
    concommand.Add("grm_plate_reset", function(ply) renderCommand(ply, "reset") end)
    concommand.Add("grm_plate_show", function(ply) renderCommand(ply, "show") end)

    -- ── старт ───────────────────────────────────────────────────────
    local function boot()
        PL.Load()
        print(("[GRM Plates] реестр номеров загружен: %d"):format(table.Count(PL.Data.plates or {})))
    end

    -- читаем базу СРАЗУ: до этого момента запись заблокирована, но так
    -- реестр доступен и коду, который стартует раньше карты
    boot()
    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Plates_Load", "normal", boot)
    else
        hook.Add("InitPostEntity", "GRM_Plates_Load", boot)
    end

    -- ── справка госбазы: транспорт человека ─────────────────────────
    if GRM.PCBoard and GRM.PCBoard.RegisterProvider then
        GRM.PCBoard.RegisterProvider("plates", {
            label = "Транспорт и номерные знаки", order = 45,
            levels = { police = true, military = true, justice = true, special = true, admin = true },
            collect = function(ctx)
                local list = PL.ListFor(ctx and ctx.charKey or "")
                if #list == 0 then return { { "Номерные знаки", "не зарегистрированы" } } end
                local rows = {}
                for i, rec in ipairs(list) do
                    if i > 8 then rows[#rows + 1] = { "Ещё знаков", tostring(#list - 8) } break end
                    rows[#rows + 1] = {
                        PL.FormatNumber(rec.number, rec.type),
                        ("%s · %s%s"):format(PL.TypeDef(rec.type).name,
                            PL.Statuses[rec.status] or tostring(rec.status),
                            (rec.vehicle and rec.vehicle ~= "") and (" · " .. rec.vehicle) or ""),
                    }
                end
                return rows
            end,
        })
    end
end

if CLIENT then

    surface.CreateFont("GRMPlate_Title",  { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMPlate_Body",   { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMPlate_Small",  { font = "Roboto", size = 11, weight = 400, extended = true })
    surface.CreateFont("GRMPlate_Number", { font = "Roboto", size = 42, weight = 900, extended = true })
    surface.CreateFont("GRMPlate_Hud",    { font = "Roboto", size = 18, weight = 800, extended = true })

    local C = {
        bg      = Color(16, 20, 28, 252),
        card    = Color(22, 28, 38, 240),
        cardHov = Color(32, 42, 56, 240),
        border  = Color(38, 48, 66, 200),
        accent  = Color(65, 145, 235),
        green   = Color(55, 185, 110),
        gold    = Color(245, 195, 65),
        red     = Color(225, 70, 70),
        text    = Color(240, 244, 250),
        dim     = Color(155, 170, 190),
    }
    PL.Colors = C

    PL.Mine, PL.Online, PL.Found, PL.IsOfficer = {}, {}, {}, false
    PL.OfficerReason, PL.YouKey, PL.YouName, PL.YouFaction = "", "", "", ""
    PL.Factions = PL.Factions or {}

    local function act(name, data)
        net.Start(PL.Net.ACT)
        net.WriteString(tostring(name))
        net.WriteTable(istable(data) and data or {})
        net.SendToServer()
    end
    PL.Act = act

    local function button(parent, label, base, onClick)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        b.Paint = function(self, w, h)
            local col = base
            if not self:IsEnabled() then col = Color(38, 44, 56)
            elseif self:IsHovered() then col = Color(math.min(255, col.r + 24), math.min(255, col.g + 24), math.min(255, col.b + 24)) end
            draw.RoundedBox(6, 0, 0, w, h, col)
            draw.SimpleText(label, "GRMPlate_Body", w / 2, h / 2, self:IsEnabled() and C.text or C.dim,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function() if onClick then onClick() end end
        return b
    end

    --[[ ПАМЯТЬ ФОРМЫ И ПРОКРУТКИ (заказ владельца 22.08).
         Панель периодически пересобирается снимком, и всё, что игрок
         набрал или прокрутил, терялось. Теперь поле знает свой КЛЮЧ и
         восстанавливает значение само, а прокрутка возвращается циклом до
         восьми кадров (DScrollPanel зажимает SetScroll по высоте холста,
         известной только после раскладки). ]]
    PL.Form = PL.Form or {}
    PL.Scroll = PL.Scroll or {}

    function PL.RestoreScroll(list, key)
        if not IsValid(list) then return end
        local base = list.OnVScroll
        list.OnVScroll = function(pnl, offset)
            if base then base(pnl, offset) end
            PL.Scroll[key] = math.abs(tonumber(offset) or 0)
        end
        local want = tonumber(PL.Scroll[key]) or 0
        if want <= 0 then return end
        local tries = 0
        local function restore()
            tries = tries + 1
            if not IsValid(list) or tries > 8 then return end
            list:InvalidateLayout(true)
            if IsValid(list.VBar) then list.VBar:SetScroll(want) end
            timer.Simple(0, restore)
        end
        timer.Simple(0, restore)
    end

    local function entry(parent, placeholder, key)
        local e = vgui.Create("DTextEntry", parent)
        e:SetFont("GRMPlate_Body")
        e:SetPlaceholderText(placeholder or "")
        if key then
            e:SetValue(tostring(PL.Form[key] or ""))
            e.OnChange = function(self) PL.Form[key] = self:GetValue() or "" end
        end
        --[[ Со своим Paint GMod НЕ рисует подсказку поля: у окна получались
             безымянные пустые прямоугольники (заказ владельца 21.08).
             Рисуем подсказку сами, пока поле пустое и не в фокусе. ]]
        e.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(18, 23, 32))
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h, 1)
            if (self:GetText() or "") == "" and not self:HasFocus() then
                draw.SimpleText(placeholder or "", "GRMPlate_Small", 8, h / 2, C.dim,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            self:DrawTextEntryText(C.text, C.accent, C.text)
        end
        return e
    end

    local function combo(parent)
        local c = vgui.Create("DComboBox", parent)
        c:SetFont("GRMPlate_Body")
        c:SetTextColor(C.text)
        c.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(18, 23, 32))
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        return c
    end

    --- Окно правки уже выданного номера.
    function PL.OpenEdit(rec)
        if not istable(rec) then return end
        if IsValid(PL._edit) then PL._edit:Remove() end
        local f = vgui.Create("DFrame")
        f:SetSize(560, 280) f:Center() f:SetTitle("") f:ShowCloseButton(false) f:MakePopup()
        PL._edit = f
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.SimpleText("ПРАВКА ЗАПИСИ  ·  " .. PL.FormatNumber(rec.number, rec.type),
                "GRMPlate_Title", 16, 16, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Кому принадлежит номер: игрок онлайн или организация",
                "GRMPlate_Small", 16, 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        local close = button(f, "✕", C.red, function() f:Remove() end)
        close:SetSize(32, 28) close:SetPos(516, 12)

        local isFac = string.sub(tostring(rec.ownerKey or ""), 1, 8) == "faction:"
        local ownerKind = isFac and "faction" or "player"
        local kindWho = combo(f)
        kindWho:SetPos(16, 70) kindWho:SetSize(170, 30)
        kindWho:AddChoice("Игроку", "player", not isFac)
        kindWho:AddChoice("Организации", "faction", isFac)

        local who = combo(f)
        who:SetPos(194, 70) who:SetSize(250, 30)
        local pickedKey = tostring(rec.ownerKey or "")
        local pickedFac = tostring(rec.faction or "")
        if isFac then pickedFac = string.gsub(pickedKey, "^faction:", "") end

        local function refill()
            who:Clear()
            if ownerKind == "faction" then
                who:SetValue("Организация...")
                for _, org in ipairs(PL.Factions or {}) do
                    who:AddChoice(org.name, org.key, org.key == pickedFac)
                end
            else
                who:SetValue("Игрок онлайн...")
                for _, p in ipairs(PL.Online or {}) do
                    who:AddChoice(("%s [%s]"):format(p.name, p.faction ~= "" and p.faction or "гражданский"),
                        p.key, p.key == pickedKey)
                end
            end
        end
        refill()
        kindWho.OnSelect = function(_, _, _, val) ownerKind = tostring(val or "player") refill() end
        who.OnSelect = function(_, _, _, val)
            if ownerKind == "faction" then pickedFac = tostring(val or "") else pickedKey = tostring(val or "") end
        end

        local veh = vgui.Create("DTextEntry", f)
        veh:SetPos(16, 112) veh:SetSize(428, 30)
        veh:SetFont("GRMPlate_Body") veh:SetText(tostring(rec.vehicle or ""))
        veh:SetPlaceholderText("Транспорт (картотека)")

        local note = vgui.Create("DTextEntry", f)
        note:SetPos(16, 150) note:SetSize(428, 30)
        note:SetFont("GRMPlate_Body") note:SetText(tostring(rec.note or ""))
        note:SetPlaceholderText("Пометка")

        local save = button(f, "СОХРАНИТЬ", C.green, function()
            local payload = {
                number = rec.number, ownerKind = ownerKind,
                vehicle = veh:GetValue() or "", note = note:GetValue() or "",
            }
            if ownerKind == "faction" then
                if pickedFac == "" then notification.AddLegacy("Выберите организацию", NOTIFY_ERROR, 3) return end
                payload.faction = pickedFac
            else
                if pickedKey == "" then notification.AddLegacy("Выберите игрока (он должен быть в сети)", NOTIFY_ERROR, 3) return end
                payload.ownerKey = pickedKey
            end
            act("edit", payload)
            f:Remove()
        end)
        save:SetPos(16, 200) save:SetSize(200, 34)
    end

    --- Карточка знака: рисуем как настоящий знак — плашка с номером.
    --[[ ЯЧЕЙКА НОМЕРА (переработка 22.08).
         Раньше это была длинная серая строка. Теперь — карточка размером с
         настоящий знак: сам номер крупно, под ним тип серии, состояние,
         владелец и машина, а действия кнопками внизу. Сетка из таких ячеек
         читается с одного взгляда и одинаково выглядит и в окне /номера, и
         во вкладке терминала. ]]
    local function plateGrid(parent)
        local grid = vgui.Create("DIconLayout", parent)
        grid:Dock(TOP)
        grid:DockMargin(0, 0, 4, 8)
        grid:SetSpaceX(8)
        grid:SetSpaceY(8)
        return grid
    end

    local function plateCard(parent, rec, opts)
        opts = istable(opts) and opts or {}
        local def = PL.TypeDef(rec.type)
        local buttons = istable(opts.buttons) and opts.buttons or {}

        local card = vgui.Create("DPanel", parent)
        local rows = math.min(3, #buttons)
        card:SetSize(262, 168 + rows * 32)

        card.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, self:IsHovered() and C.cardHov or C.card)
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- сам знак: пропорции как у настоящей таблички
            local pw, ph = w - 24, 58
            draw.RoundedBox(4, 12, 12, pw, ph, Color(def.plate[1], def.plate[2], def.plate[3]))
            draw.RoundedBox(4, 12, 12, 18, ph, Color(def.band[1], def.band[2], def.band[3]))
            draw.SimpleText(PL.FormatNumber(rec.number, rec.type), "GRMPlate_Title",
                12 + 18 + (pw - 18) / 2, 12 + ph / 2,
                Color(def.text[1], def.text[2], def.text[3]), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText(def.name, "GRMPlate_Body", 12, 80, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local statusCol = rec.status == "active" and C.green
                or (rec.status == "lost" and C.gold or C.red)
            draw.SimpleText(PL.Statuses[rec.status] or tostring(rec.status), "GRMPlate_Small",
                w - 12, 82, statusCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

            local mount = rec.mounted
                and ("на машине: " .. (rec.mountVehicle ~= "" and rec.mountVehicle or "транспорт"))
                or "не установлен"
            if rec.mountOffMap then mount = mount .. " (в гараже)" end
            draw.SimpleText(mount, "GRMPlate_Small", 12, 102,
                rec.mounted and C.accent or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            if opts.showOwner then
                draw.SimpleText("владелец: " .. tostring(rec.ownerName or "—"), "GRMPlate_Small",
                    12, 120, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                if (rec.faction or "") ~= "" then
                    draw.SimpleText(tostring(rec.faction), "GRMPlate_Small", 12, 138, C.gold,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            elseif (rec.vehicle or "") ~= "" then
                draw.SimpleText("транспорт: " .. tostring(rec.vehicle), "GRMPlate_Small",
                    12, 120, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end

        local y = 168 - (opts.showOwner and 0 or 32)
        for i = 1, rows do
            local defBtn = buttons[i]
            if defBtn then
                local b = button(card, tostring(defBtn.label or ""), defBtn.color, defBtn.fn)
                b:SetPos(12, y) b:SetSize(238, 26)
                b:SetEnabled(defBtn.enabled ~= false)
                y = y + 32
            end
        end
        return card
    end

    --- Содержимое раздела «Номерные знаки» — и для окна, и для вкладки
    --  терминала (один код, без копий).
    function PL.BuildPanel(parent)
        parent:DockPadding(10, 10, 10, 10)

        local content = vgui.Create("DScrollPanel", parent)
        content:Dock(FILL)
        PL.RestoreScroll(content, "main")

        --[[ ЖИВОЕ ОКНО.
             Пока панель учёта открыта, сервер знает о ней и присылает
             свежий снимок сам: коллега зарегистрировал номер — таблица
             обновилась без единого клика. Плюс редкая страховка раз в
             10 секунд на случай потерянного пакета. Закрыли окно — подписка
             снимается, лишних пакетов нет. ]]
        act("watch", { on = true })
        parent.GRMWatchAt = RealTime() + 10
        parent.Think = function(self)
            if (self.GRMWatchAt or 0) > RealTime() then return end
            self.GRMWatchAt = RealTime() + 10
            act("watch", { on = true })
        end

        local rebuild
        rebuild = function()
            content:Clear()

            -- ── мои знаки ───────────────────────────────────────────
            local head = vgui.Create("DPanel", content)
            head:Dock(TOP) head:SetTall(46) head:DockMargin(0, 0, 4, 8)
            head.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("МОИ РЕГИСТРАЦИОННЫЕ ЗНАКИ", "GRMPlate_Body", 14, 14, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText("Получите бланк, поставьте физганом на бампер и нажмите [E], чтобы закрепить",
                    "GRMPlate_Small", 14, 30, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            local refresh = button(head, "Обновить", C.cardHov, function() act("refresh") end)
            refresh:Dock(RIGHT) refresh:SetWide(120) refresh:DockMargin(6, 8, 8, 8)

            --[[ Строка статуса: человек сразу видит, может ли он
                 регистрировать номера и почему (вопрос владельца 22.08). ]]
            local status = vgui.Create("DPanel", content)
            status:Dock(TOP) status:SetTall(46) status:DockMargin(0, 0, 4, 8)
            status.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.RoundedBox(8, 0, 0, 5, h, PL.IsOfficer and C.green or C.dim)
                draw.SimpleText(PL.IsOfficer and "ВЫ МОЖЕТЕ РЕГИСТРИРОВАТЬ НОМЕРА" or "РЕГИСТРАЦИЯ НОМЕРОВ ВАМ НЕДОСТУПНА",
                    "GRMPlate_Body", 16, 10, PL.IsOfficer and C.green or C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(PL.OfficerReason ~= "" and ("Основание: " .. PL.OfficerReason) or "",
                    "GRMPlate_Small", 16, 28, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end

            if not PL.IsOfficer then
                local howto = vgui.Create("DPanel", content)
                howto:Dock(TOP) howto:SetTall(76) howto:DockMargin(0, 0, 4, 8)
                howto.Paint = function(_, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, C.card)
                    draw.SimpleText("КАК ПОЛУЧИТЬ НОМЕР", "GRMPlate_Body", 14, 10, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText("Номер выдаёт сотрудник Полиции порядка, Жандармерии или Автоинспекции в этой же вкладке.",
                        "GRMPlate_Small", 14, 26, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText("Получив номер, возьмите бланк кнопкой «ПОЛУЧИТЬ БЛАНК» и закрепите его на машине по [E].",
                        "GRMPlate_Small", 14, 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText("Руководителю: право даётся в /factions → «Доступы» («Регистрация номерных знаков») или в /admin → «Привилегии» (plates.issue).",
                        "GRMPlate_Small", 14, 56, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            end

            if #PL.Mine == 0 then
                local empty = vgui.Create("DPanel", content)
                empty:Dock(TOP) empty:SetTall(60) empty:DockMargin(0, 0, 4, 8)
                empty.Paint = function(_, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, C.card)
                    draw.SimpleText("Номеров на вас не зарегистрировано. Обратитесь в Полицию или Автоинспекцию.",
                        "GRMPlate_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            if #PL.Mine > 0 then
                local mineGrid = plateGrid(content)
                for _, rec in ipairs(PL.Mine) do
                    plateCard(mineGrid, rec, {
                        buttons = {
                            { label = "ПОЛУЧИТЬ БЛАНК", color = C.green,
                              enabled = rec.status == "active",
                              fn = function() act("spawn", { number = rec.number }) end },
                            { label = "ЗАЯВИТЬ ОБ УТЕРЕ", color = C.cardHov,
                              enabled = rec.status == "active",
                              fn = function()
                                  Derma_Query("Заявить об утере номера " .. PL.FormatNumber(rec.number, rec.type) .. "?",
                                      "Номерные знаки", "Заявить",
                                      function() act("lost", { number = rec.number }) end, "Отмена")
                              end },
                        },
                    })
                end
            end

            -- ── поиск по номеру ─────────────────────────────────────
            local findCard = vgui.Create("DPanel", content)
            findCard:Dock(TOP) findCard:SetTall(84) findCard:DockMargin(0, 8, 4, 8)
            findCard.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("ПРОВЕРКА НОМЕРА ПО БАЗЕ", "GRMPlate_Body", 14, 12, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            local findEntry = entry(findCard, "Например: А123ВС (можно латиницей)", "find")
            findEntry:SetPos(14, 40) findEntry:SetSize(300, 30)
            local findBtn = button(findCard, "ПРОБИТЬ", C.accent, function()
                act("find", { number = findEntry:GetValue() or "" })
            end)
            findBtn:SetPos(324, 40) findBtn:SetSize(140, 30)

            if #PL.Found > 0 then
                local foundGrid = plateGrid(content)
                for _, rec in ipairs(PL.Found) do
                    local buttons = {}
                    if PL.IsOfficer then
                        buttons[#buttons + 1] = { label = "ИЗМЕНИТЬ В БАЗЕ", color = C.accent,
                            fn = function() PL.OpenEdit(rec) end }
                        buttons[#buttons + 1] = { label = rec.status == "revoked" and "ВОССТАНОВИТЬ" or "АННУЛИРОВАТЬ",
                            color = rec.status == "revoked" and C.cardHov or C.red,
                            fn = function()
                                act("status", { number = rec.number,
                                    status = rec.status == "revoked" and "active" or "revoked" })
                            end }
                        buttons[#buttons + 1] = { label = "УНИЧТОЖИТЬ НОМЕР", color = C.red,
                            fn = function()
                                Derma_Query("Полностью удалить номер " .. PL.FormatNumber(rec.number, rec.type)
                                    .. " из реестра? Физические бланки будут сняты.",
                                    "Удаление номера",
                                    "Удалить", function()
                                        act("delete", { number = rec.number })
                                    end,
                                    "Отмена", function() end)
                            end }
                    end
                    plateCard(foundGrid, rec, { showOwner = true, buttons = buttons })
                end
            end

            -- ── выдача (только служба) ──────────────────────────────
            if PL.IsOfficer then
                local issue = vgui.Create("DPanel", content)
                issue:Dock(TOP) issue:SetTall(196) issue:DockMargin(0, 8, 4, 8)
                issue.Paint = function(_, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, C.card)
                    draw.SimpleText("РЕГИСТРАЦИЯ НОВОГО ЗНАКА", "GRMPlate_Body", 14, 12, C.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText("Кому: себе, игроку или организации. Фракционные знаки не занимают личный лимит.",
                        "GRMPlate_Small", 14, 32, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end

                local ownerKind = tostring(PL.Form.issue_kind or "player")
                local kindWho = combo(issue)
                kindWho:SetPos(14, 54) kindWho:SetSize(180, 30)
                kindWho:AddChoice("Игроку", "player", ownerKind ~= "faction")
                kindWho:AddChoice("Организации", "faction", ownerKind == "faction")

                local who = combo(issue)
                who:SetPos(202, 54) who:SetSize(250, 30)
                local pickedKey = tostring(PL.Form.issue_owner or "")
                local pickedFac = tostring(PL.Form.issue_faction or PL.YouFaction or "")

                local function refillWho()
                    who:Clear()
                    if ownerKind == "faction" then
                        who:SetValue("Организация...")
                        for _, f in ipairs(PL.Factions or {}) do
                            local mineOrg = (f.key == PL.YouFaction)
                            who:AddChoice(("%s%s"):format(f.name, f.tag ~= "" and (" [" .. f.tag .. "]") or ""),
                                f.key, mineOrg or f.key == pickedFac)
                            if mineOrg and pickedFac == "" then pickedFac = f.key end
                        end
                    else
                        who:SetValue("Кому выдать...")
                        for _, p in ipairs(PL.Online) do
                            local mineOne = (p.key == PL.YouKey)
                            who:AddChoice(("%s [%s]"):format(tostring(p.name),
                                tostring(p.faction ~= "" and p.faction or "без организации")), p.key, mineOne or p.key == pickedKey)
                            if mineOne and pickedKey == "" then pickedKey = p.key end
                        end
                    end
                end
                refillWho()
                kindWho.OnSelect = function(_, _, _, val)
                    ownerKind = tostring(val or "player")
                    PL.Form.issue_kind = ownerKind
                    refillWho()
                end
                who.OnSelect = function(_, _, _, val)
                    if ownerKind == "faction" then
                        pickedFac = tostring(val or "")
                        PL.Form.issue_faction = pickedFac
                    else
                        pickedKey = tostring(val or "")
                        PL.Form.issue_owner = pickedKey
                    end
                end

                local selfBtn = button(issue, "СЕБЕ", C.cardHov, function()
                    ownerKind = "player"
                    PL.Form.issue_kind = "player"
                    kindWho:SetValue("Игроку")
                    refillWho()
                    if PL.YouKey == "" then return end
                    pickedKey = PL.YouKey
                    who:SetValue(PL.YouName ~= "" and PL.YouName or "Вы")
                end)
                selfBtn:SetPos(460, 54) selfBtn:SetSize(74, 30)

                local orgBtn = button(issue, "МОЕЙ ОРГ.", C.cardHov, function()
                    if (PL.YouFaction or "") == "" then
                        notification.AddLegacy("Вы не в организации", NOTIFY_ERROR, 3)
                        return
                    end
                    ownerKind = "faction"
                    PL.Form.issue_kind = "faction"
                    kindWho:SetValue("Организации")
                    pickedFac = PL.YouFaction
                    PL.Form.issue_faction = pickedFac
                    refillWho()
                    who:SetValue(PL.YouFaction)
                end)
                orgBtn:SetPos(540, 54) orgBtn:SetSize(110, 30)

                local kind = combo(issue)
                kind:SetPos(14, 94) kind:SetSize(250, 30)
                local pickedType = "civil"
                for _, t in ipairs(PL.TypeList()) do
                    kind:AddChoice(t.name .. "  (" .. t.pattern .. ")", t.key, t.key == "civil")
                end
                kind.OnSelect = function(_, _, _, val)
                    pickedType = tostring(val or "civil")
                    PL.Form.issue_type = pickedType
                end
                if PL.Form.issue_type then pickedType = PL.Form.issue_type end

                local numEntry = entry(issue, "Номер вручную (не обязательно)", "issue_number")
                numEntry:SetPos(272, 94) numEntry:SetSize(220, 30)

                local vehEntry = entry(issue, "Транспорт: марка / класс (для картотеки)", "issue_vehicle")
                vehEntry:SetPos(14, 136) vehEntry:SetSize(478, 30)

                local giveBtn = button(issue, "ЗАРЕГИСТРИРОВАТЬ", C.green, function()
                    if ownerKind == "faction" then
                        if pickedFac == "" then
                            notification.AddLegacy("Выберите организацию", NOTIFY_ERROR, 3)
                            return
                        end
                        act("issue", {
                            ownerKind = "faction", faction = pickedFac, type = pickedType,
                            number = numEntry:GetValue() or "", vehicle = vehEntry:GetValue() or "",
                        })
                    else
                        if pickedKey == "" then
                            notification.AddLegacy("Выберите владельца", NOTIFY_ERROR, 3)
                            return
                        end
                        act("issue", {
                            ownerKind = "player", ownerKey = pickedKey, type = pickedType,
                            number = numEntry:GetValue() or "", vehicle = vehEntry:GetValue() or "",
                        })
                    end
                end)
                giveBtn:SetPos(500, 136) giveBtn:SetSize(220, 30)

            end
        end

        rebuild()
        PL._rebuild = rebuild
        parent.OnRemove = function()
            if PL._rebuild == rebuild then PL._rebuild = nil end
            act("watch", { on = false })
        end
        return rebuild
    end

    --- Вкладка «Номерные знаки» в терминалах (тот же код, что и в окне).
    function PL.AttachTab(sheet)
        if not IsValid(sheet) then return end
        local pnl = vgui.Create("DPanel", sheet)
        pnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(20, 26, 36, 245)) end
        PL.BuildPanel(pnl)
        sheet:AddSheet("Номерные знаки", pnl, "icon16/car.png")
        act("refresh")
        return pnl
    end

    net.Receive(PL.Net.RENDER, function()
        PL.Render = PL.NormalizeRender({
            axis = net.ReadString(), yaw = net.ReadUInt(9), flip = net.ReadBool(),
            scale = net.ReadFloat(), offset = net.ReadFloat(),
            tiltP = net.ReadFloat(), tiltY = net.ReadFloat(), tiltR = net.ReadFloat(),
            moveX = net.ReadFloat(), moveY = net.ReadFloat(),
        })
        -- сбрасываем кэш граней у всех живых знаков: пересчитаются сами
        for _, ent in ipairs(ents.FindByClass("grm_plate")) do
            if IsValid(ent) then ent.GRMFace = nil end
        end
    end)

    --[[ ПЕРЕСБОРКА ТОЛЬКО ПО ДЕЛУ (заказ владельца 22.08: «обновление не
         должно сбивать текст и рябить»).

         Снимок приходит каждые несколько секунд, но данные в нём чаще всего
         те же самые. Раньше окно пересобиралось на КАЖДЫЙ пакет: список
         мигал, набранный в поле текст пропадал, прокрутка прыгала.

         Теперь считаем подпись снимка и сравниваем с прошлой: одинаково —
         не трогаем окно вообще. И даже при изменениях не пересобираем, пока
         игрок печатает: правки применятся, как только он уйдёт из поля. ]]
    local function snapshotSignature(data)
        local parts = {
            tostring(data.officer), tostring(data.officerReason),
            tostring(data.youKey), tostring(#(data.mine or {})), tostring(#(data.found or {})),
        }
        for _, rec in ipairs(data.mine or {}) do
            parts[#parts + 1] = table.concat({ rec.number, rec.type, rec.status,
                tostring(rec.mounted), tostring(rec.mountVehicle), tostring(rec.mountOffMap) }, ":")
        end
        for _, rec in ipairs(data.found or {}) do
            parts[#parts + 1] = "f:" .. table.concat({ rec.number, rec.status, tostring(rec.ownerName) }, ":")
        end
        for _, p in ipairs(data.online or {}) do parts[#parts + 1] = "o:" .. tostring(p.key) end
        return table.concat(parts, "|")
    end

    --- Печатает ли игрок прямо сейчас (тогда окно не трогаем).
    local function typingNow()
        local focus = vgui.GetKeyboardFocus()
        return IsValid(focus)
    end

    local function applySnapshot(data)
        if not istable(data) then return end
        PL.Mine = istable(data.mine) and data.mine or {}
        PL.IsOfficer = data.officer == true
        PL.OfficerReason = tostring(data.officerReason or "")
        PL.YouKey = tostring(data.youKey or "")
        PL.YouName = tostring(data.youName or "")
        PL.YouFaction = tostring(data.youFaction or "")
        PL.Online = istable(data.online) and data.online or {}
        -- список организаций приходит с сервера: без него комбобокс
        -- «Кому выдать» пустой и организацию выбрать нельзя.
        PL.Factions = istable(data.factions) and data.factions or PL.Factions
        if istable(data.found) and #data.found > 0 then PL.Found = data.found end

        local sig = snapshotSignature(data)
        if sig == PL._sig then return end          -- ничего не изменилось
        if typingNow() then PL._sigPending = sig return end
        PL._sig, PL._sigPending = sig, nil
        if PL._rebuild then PL._rebuild() end
    end

    --[[ Если игрок печатал в момент изменения — применяем, как только он
         освободит клавиатуру. Проверка редкая (раз в полсекунды). ]]
    hook.Add("Think", "GRM_Plates_PendingRebuild", function()
        if not PL._sigPending then return end
        if (PL._pendingAt or 0) > RealTime() then return end
        PL._pendingAt = RealTime() + 0.5
        if typingNow() then return end
        PL._sig, PL._sigPending = PL._sigPending, nil
        if PL._rebuild then PL._rebuild() end
    end)

    -- снимок приходит порциями (GRM.Net.Stream) — окно собирается один раз
    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive(PL.Net.SYNC, applySnapshot)
    end

    net.Receive(PL.Net.SYNC, function()
        applySnapshot({
            mine = net.ReadTable() or {},
            officer = net.ReadBool(),
            online = net.ReadTable() or {},
            found = net.ReadTable() or {},
        })
    end)

    net.Receive(PL.Net.OPEN, function()
        if IsValid(PL._frame) then PL._frame:Remove() end
        local f = vgui.Create("DFrame")
        f:SetSize(math.Clamp(ScrW() * 0.62, 900, 1200), math.Clamp(ScrH() * 0.7, 600, 860))
        f:Center() f:SetTitle("") f:ShowCloseButton(false) f:MakePopup()
        PL._frame = f
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_plates", f) end
        f.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(10, 0, 0, w, 48, Color(22, 28, 40), true, true, false, false)
            draw.RoundedBox(0, 0, 48, w, 2, C.accent)
            draw.SimpleText("УЧЁТ ТРАНСПОРТА · РЕГИСТРАЦИОННЫЕ ЗНАКИ", "GRMPlate_Title", 18, 16, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("/номера  •  выдача в Полиции и Автоинспекции", "GRMPlate_Small", 18, 32, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        local close = button(f, "✕", C.red, function() f:Remove() end)
        close:SetSize(32, 28) close:SetPos(f:GetWide() - 42, 10)

        local body = vgui.Create("DPanel", f)
        body:Dock(FILL) body:DockMargin(6, 52, 6, 6) body:SetPaintBackground(false)
        PL.BuildPanel(body)
    end)

    --[[ РЕДАКТОР ПОЛОЖЕНИЯ ЗНАКА.

         Смотришь на закреплённый знак, жмёшь кнопку в его 3D2D-плашке
         (или команду /номер_ред) — открывается компактное окно со
         стрелками: двигать на 1/5/20 см вдоль осей машины, крутить,
         «Авто» и «Снять». Каждый шаг уходит на сервер с entindex
         знака; сервер повторно проверяет право и родителя. Позиция
         сохраняется и в гараже/автопарке, и в реестре. ]]
    local editor

    local function nudge(plate, kind, axis, delta)
        if not (IsValid(plate) and plate:GetClass() == "grm_plate") then return end
        net.Start(PL.Net.ACT)
            net.WriteString("nudge")
            net.WriteTable({ ent = plate:EntIndex(), kind = kind, axis = axis,
                delta = delta, forClass = false })
        net.SendToServer()
    end

    local function canEditPlate(plate)
        if not (IsValid(plate) and plate:GetNWBool("GRM_PlateMounted", false)) then return false end
        local lp = LocalPlayer()
        if not IsValid(lp) then return false end
        if lp:IsSuperAdmin() then return true end
        if PL.IsOfficer then return true end
        -- владелец знака проверяется сервером (CanHandle); клиенту достаточно
        -- не показывать редактор на чужих знаках, точную проверку делает сервер
        return true
    end

    local function closeEditor()
        if IsValid(editor) then editor:Remove() end
        editor = nil
    end

    local function openEditor(plate)
        if not (IsValid(plate) and plate:GetClass() == "grm_plate") then return end
        closeEditor()
        local f = vgui.Create("DFrame")
        editor = f
        f:SetSize(390, 430) f:Center() f:MakePopup()
        f:SetTitle("") f:ShowCloseButton(false)
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("ПОЛОЖЕНИЕ ЗНАКА", "GRMPlate_Title", 14, 12, C.gold)
            local par = IsValid(plate:GetParent()) and plate:GetParent():GetClass() or "—"
            draw.SimpleText("на: " .. par, "GRMPlate_Small", 14, 34, C.dim)
        end
        local x = button(f, "✕", C.red, closeEditor); x:SetSize(28, 24); x:SetPos(324, 8)

        local body = vgui.Create("DPanel", f)
        body:Dock(FILL) body:DockMargin(10, 52, 10, 10) body:SetPaintBackground(false)

        local step = 1
        local function stepBtn(parent, label, x2, y2, w2, h2, fn)
            local b = button(parent, label, C.cardHov, fn)
            b:SetPos(x2, y2) b:SetSize(w2, h2)
            return b
        end

        -- переключатель шага
        local function stepRow(y2, label, val)
            local b = stepBtn(body, label, 10, y2, 108, 26, function() step = val end)
            return b
        end
        stepRow(0, "шаг 1 см", 1)
        local b5 = stepBtn(body, "шаг 5 см", 122, 0, 108, 26, function() step = 5 end)
        local b20 = stepBtn(body, "шаг 20 см", 234, 0, 106, 26, function() step = 20 end)
        f.Think = function()
            if not IsValid(plate) then closeEditor() return end
            local col1 = step == 1 and C.accent or C.cardHov
            local col5 = step == 5 and C.accent or C.cardHov
            local col20 = step == 20 and C.accent or C.cardHov
        end

        -- крестовина перемещения (по осям машины):
        -- Z вверх/вниз, Y влево/вправо, X вперёд/назад
        local function arrow(label, ax, ay, kind, axis, delta, w, h)
            stepBtn(body, label, ax, ay, w or 44, h or 34, function() nudge(plate, kind, axis, delta * step) end)
        end
        local function axisLbl(text, x, y, w)
            local l = vgui.Create("DLabel", body); l:SetPos(x, y); l:SetSize(w or 60, 14)
            l:SetFont("GRMPlate_Small"); l:SetTextColor(C.dim); l:SetText(text); l:SetContentAlignment(5)
        end

        local lbl = vgui.Create("DLabel", body); lbl:SetPos(10, 36); lbl:SetSize(340, 16)
        lbl:SetFont("GRMPlate_Small"); lbl:SetTextColor(C.dim); lbl:SetText("СДВИГ (локальные оси машины)")

        -- Z — вверх/вниз (центр)
        arrow("↑", 120, 56, "move", "z", 1, 44, 30)
        arrow("↓", 120, 124, "move", "z", -1, 44, 30)
        axisLbl("ВЕРХ", 112, 88, 60)

        -- Y — влево/вправо
        arrow("←", 70, 90, "move", "y", -1, 44, 30)
        arrow("→", 170, 90, "move", "y", 1, 44, 30)
        axisLbl("ЛЕВО", 60, 122, 64)
        axisLbl("ПРАВО", 160, 122, 64)

        -- X — вперёд/назад (третья колонка)
        arrow("ВПЕРЁД", 226, 56, "move", "x", 1, 110, 30)
        arrow("НАЗАД", 226, 124, "move", "x", -1, 110, 30)
        axisLbl("ВПЕРЁД/НАЗАД (F/R)", 226, 90, 110)

        -- поворот
        local rl = vgui.Create("DLabel", body); rl:SetPos(10, 168); rl:SetSize(200, 18)
        rl:SetFont("GRMPlate_Small"); rl:SetTextColor(C.dim); rl:SetText("ПОВОРОТ (градусы × шаг)")
        stepBtn(body, "P▼", 10, 190, 60, 30, function() nudge(plate, "turn", "p", -step) end)
        stepBtn(body, "P▲", 74, 190, 60, 30, function() nudge(plate, "turn", "p", step) end)
        stepBtn(body, "Y◀", 138, 190, 60, 30, function() nudge(plate, "turn", "y", -step) end)
        stepBtn(body, "Y▶", 202, 190, 60, 30, function() nudge(plate, "turn", "y", step) end)
        stepBtn(body, "R↶", 266, 190, 44, 30, function() nudge(plate, "turn", "r", -step) end)

        -- действия
        local auto = button(body, "АВТО", C.green, function()
            net.Start(PL.Net.ACT) net.WriteString("attach_auto")
                net.WriteTable({ ent = plate:EntIndex() }) net.SendToServer()
        end)
        auto:SetPos(10, 270) auto:SetSize(104, 30)

        --[[ Сохранить положение для ВСЕХ машин этого класса
             (simfphys_mafia2_jeep и т.п.). Требует права регистрации
             номеров или суперадмина — проверяет сервер. ]]
        local allClass = button(body, "ДЛЯ ВСЕХ ТАКИХ", C.gold, function()
            Derma_Query("Сохранить это положение для всех машин этого класса?\n"
                .. "Любой знак на такой модели будет вставать сюда.",
                "Раскладка класса",
                "Сохранить", function()
                    net.Start(PL.Net.ACT) net.WriteString("save_class")
                        net.WriteTable({ ent = plate:EntIndex() }) net.SendToServer()
                end,
                "Отмена", function() end)
        end)
        allClass:SetPos(120, 270) allClass:SetSize(120, 30)

        local detach = button(body, "СНЯТЬ", C.red, function()
            net.Start(PL.Net.ACT) net.WriteString("detach")
                net.WriteTable({ ent = plate:EntIndex() }) net.SendToServer()
            closeEditor()
        end)
        detach:SetPos(246, 270) detach:SetSize(94, 30)
        local hint = vgui.Create("DLabel", body); hint:SetPos(10, 308); hint:SetSize(330, 18)
        hint:SetFont("GRMPlate_Small"); hint:SetTextColor(C.dim)
        hint:SetText("F=вперёд R=назад. Позиция запоминается на этой машине.")
    end
    PL.OpenEditor = openEditor

    --[[ Какой знак редактировать.

         У закреплённого знака коллизия выключена (MOVETYPE_NONE /
         SOLID_NONE), поэтому EyeTrace по нему НЕ попадает — луч проходит
         сквозь табличку и бьёт в машину. Из-за этого /номер_ред и ПКМ
         работали только по снятому знаку. Ищем:
           1) знак напрямую (снятый, у него есть коллизия);
           2) знаки, припаркованные к транспорту, в который смотрим;
           3) ближайший незакреплённый знак в радиусе. ]]
    local function targetPlate()
        local lp = LocalPlayer()
        if not IsValid(lp) then return nil end
        local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp) or lp:GetEyeTrace()
        local ent = tr and tr.Entity
        if IsValid(ent) and ent:GetClass() == "grm_plate" then return ent end

        -- смотрим на транспорт — берём его знаки
        if IsValid(ent) and PL.VehicleBase and PL.VehicleBase(ent) then
            local base = PL.VehicleBase(ent)
            if IsValid(base) and base.GetChildren then
                local best, bestD
                for _, ch in ipairs(base:GetChildren() or {}) do
                    if IsValid(ch) and ch:GetClass() == "grm_plate" and canEditPlate(ch) then
                        -- ближайший к точке попадания лучом знак
                        local d = ch:GetPos():Distance(tr.HitPos or ch:GetPos())
                        if not bestD or d < bestD then best, bestD = ch, d end
                    end
                end
                if IsValid(best) then return best end
            end
        end

        -- фолбэк: ближайший свободный/закреплённый знак в пределах 180 юн.
        local best, bestD
        for _, ch in ipairs(ents.FindByClass("grm_plate")) do
            if IsValid(ch) and canEditPlate(ch) then
                local d = lp:GetPos():Distance(ch:GetPos())
                if d < 180 and (not bestD or d < bestD) then best, bestD = ch, d end
            end
        end
        return best
    end
    PL.TargetPlate = targetPlate

    concommand.Add("grm_plate_edit", function()
        local plate = targetPlate()
        if IsValid(plate) then openEditor(plate) end
    end)

    hook.Add("GRMRPChat_ClientCommand", "GRM_Plates_EditorChat", function(ply, text)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if not (istable(pack) and isstring(pack[1])) or ply ~= LocalPlayer() then return end
            local low = string.lower(string.Trim(pack[1]))
            if low == "/номер_ред" or low == "/номерред" or low == "/plate_edit" then
                pack[1] = "" pack.SkipPlayerSay = true
                RunConsoleCommand("grm_plate_edit")
            end

        if pack.SkipPlayerSay == true then return true end
    end)

    -- клик правой кнопкой по 3D2D-плашке над знаком — открыть редактор
    hook.Add("GUIMousePressed", "GRM_Plates_EditorClick", function(mc)
        if mc ~= MOUSE_RIGHT then return end
        local plate = targetPlate()
        if IsValid(plate) and canEditPlate(plate) then
            openEditor(plate)
        end
    end)

    --[[ НОМЕР НАД ЗНАКОМ — 3D2D В МИРЕ.

         Экранная плашка посреди монитора мешала (и появлялась не там, где
         смотришь). Теперь номер рисуется прямо над знаком в мире, лицом к
         игроку, и только когда прицел наведён НА САМ ЗНАК.

         Порядок работы в кадре сознательно дешёвый:
           • трассировка — раз в 0.2 с, не каждый кадр;
           • в кадре только математика билборда и две операции рисования;
           • дальше 400 юнитов не рисуем вовсе.  ]]
    local lookPlate, lookAt = nil, 0

    -- метка знака: позиция/краски — скретч и константы загрузки (§6.1.8)
    local PL_POS = Vector(0, 0, 0)
    local PL_BG = Color(12, 16, 24, 225)
    local PL_STATUS = Color(215, 75, 75)
    local PL_HINT = Color(150, 200, 255)
    local PL_TINT = Color(255, 255, 255, 255)
    hook.Add("PostDrawTranslucentRenderables", "GRM_Plates_WorldLabel", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end

        if CurTime() - lookAt > 0.2 then
            lookAt = CurTime()
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp) or lp:GetEyeTrace()
            local ent = tr and tr.Entity or nil
            lookPlate = (IsValid(ent) and ent:GetClass() == "grm_plate") and ent or nil
        end

        local ent = lookPlate
        if not IsValid(ent) then return end
        local number = ent:GetNWString("GRM_Plate", "")
        if number == "" then return end

        local origin = ent:GetPos()
        local dist = lp:GetPos():Distance(origin)
        if dist > 400 then return end

        local kind = ent:GetNWString("GRM_PlateType", "civil")
        local status = ent:GetNWString("GRM_PlateStatus", "active")
        local def = PL.TypeDef(kind)
        local text = PL.FormatNumber(number, kind)

        local ang = (lp:EyePos() - origin):Angle()
        ang:RotateAroundAxis(ang:Right(), -90)
        ang:RotateAroundAxis(ang:Up(), -90)

        surface.SetFont("GRMPlate_Hud")
        local tw, th = surface.GetTextSize(text)
        local w, h = tw + 46, th + 16

        local mounted = ent:GetNWBool("GRM_PlateMounted", false)
        local canEdit = mounted and canEditPlate(ent)
        local extraH = canEdit and 14 or 0
        local boxH = h + extraH
        PL_POS.x = origin.x
        PL_POS.y = origin.y
        PL_POS.z = origin.z + 14
        cam.Start3D2D(PL_POS, ang, 0.12)
            draw.RoundedBox(6, -w / 2, -boxH / 2, w, boxH, PL_BG)
            PL_TINT.r = def.band[1]; PL_TINT.g = def.band[2]; PL_TINT.b = def.band[3]; PL_TINT.a = 255
            draw.RoundedBox(6, -w / 2, -boxH / 2, 10, boxH, PL_TINT)
            PL_TINT.r = def.plate[1]; PL_TINT.g = def.plate[2]; PL_TINT.b = def.plate[3]
            draw.SimpleText(text, "GRMPlate_Hud", 6, -extraH / 2, PL_TINT,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if status ~= "active" then
                draw.SimpleText(string.upper(PL.Statuses[status] or status), "GRMPlate_Small",
                    0, h / 2 - extraH / 2 + 8, PL_STATUS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            if canEdit then
                draw.SimpleText("ПКМ — подвинуть", "GRMPlate_Small", 0, boxH / 2 - 9,
                    PL_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end)
end

print("[GRM Plates] v" .. PL.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/plate_edit", "/plate_status", "/plateoff", "/plateon", "/номер_ред", "/номер_статус", "/номерприкрепить", "/номерред", "/прикрепить", "/снятьномер" })
end
