--[[ Живой прогон привязки значка объекта к двери (заказ владельца 28.08).

     «Красивее будет смотреться, если значок жилья будет крепиться лучше
      всего к дверям после создания зоны.»
     «И информация, допустим, Квартира №2 стоимость 85.000 GRM, тоже к
      двери чтобы крепилось.»

     ЧТО БЫЛО НЕ ТАК. Значок и подпись висели в геометрическом ЦЕНТРЕ
     зоны. Зону обводят вокруг всего дома, поэтому центр — это середина
     комнаты или стена: эмблема торчала в воздухе внутри помещения, а
     цену было видно только изнутри. Плюс свежесозданная зона вообще не
     имела дверей — их притягивало только в момент покупки.

     Стенд СНАЧАЛА воспроизводит старое поведение (значок далеко от
     двери, у новой зоны дверей нет), потом проверяет новое.

     Запуск: luajit tools/luatest/sim_estate_door_marker.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- ОКРУЖЕНИЕ GARRY'S MOD
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
function VecMT.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VecMT.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT) end

function CurTime() return 100 end
function ErrorNoHalt() end
function ConVarExists() return true end
function CreateConVar() end
function GetConVar() return { GetInt = function() return 3 end } end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2

hook = { _t = {} }
function hook.Add(e, i, f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Run(e, ...)
    for _, f in pairs(hook._t[e] or {}) do local r = f(...) if r ~= nil then return r end end
end

timer = { Simple = function(_, f) f() end, Create = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    Compress = function(x) return x end }
net = setmetatable({}, { __index = function() return function() return "" end end })
ents = { FindByClass = function() return {} end, GetAll = function() return {} end }

GRM = {}

assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

-----------------------------------------------------------------------
-- МИР: КВАРТИРА С ДВЕРЬЮ
-----------------------------------------------------------------------
--[[ Зона квартиры обведена вокруг помещения: 0..400 по X, 0..300 по Y,
     пол на z=0, потолок z=200. Центр — Vector(200,150,100), то есть
     ровно посреди комнаты, на уровне пояса. Именно туда раньше и
     цеплялся значок. ]]
local ZONE = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 400, y = 300, z = 200 } }

local DOORS = {}
local DOOR_INDEX = 0
local function mkDoor(id, pos, halfW, height)
    halfW = halfW or 24
    height = height or 82
    DOOR_INDEX = DOOR_INDEX + 1
    local idx = DOOR_INDEX
    local d = {
        _valid = true, _id = id, _pos = pos,
        -- В снимок уходит именно EntIndex: по нему клиент найдёт дверь.
        EntIndex = function() return idx end,
        GetPos = function(s) return s._pos end,
        WorldSpaceCenter = function(s) return Vector(s._pos.x, s._pos.y, s._pos.z + height * 0.5) end,
        WorldSpaceAABB = function(s)
            return Vector(s._pos.x - halfW, s._pos.y - halfW, s._pos.z),
                   Vector(s._pos.x + halfW, s._pos.y + halfW, s._pos.z + height)
        end,
    }
    DOORS[#DOORS + 1] = d
    return d
end

-- Входная дверь стоит в стене y=0 (южная), внутренняя — в глубине комнаты.
local frontDoor = mkDoor("map_m11", Vector(200, 0, 0))
local backDoor  = mkDoor("map_m12", Vector(200, 260, 0))

GRM.Doors = {
    AllDoors = function() return DOORS end,
    GetDoorID = function(e) return e._id end,
    IsDoor = function(e) return istable(e) and e._id ~= nil end,
}

local flat = {
    id = "flat2", name = "Квартира №2", type = "apartment",
    estateKind = "estate",
    ownerType = "none", ownerKey = "", ownerName = "",
    purchasePrice = 85000, utilityRate = 300, utilityDebt = 0,
    doors = { "map_m11", "map_m12" },
    zone = ZONE,
}
GRM.Property = { Records = { flat2 = flat }, Save = function() end, Reindex = function() end }

-----------------------------------------------------------------------
print("\n=== 1. БАГ ВОСПРОИЗВЕДЁН: СТАРЫЙ ЗНАЧОК ВИСЕЛ В ЦЕНТРЕ КОМНАТЫ ===")
-----------------------------------------------------------------------
local center = ES.ZoneCenter(flat)
local oldPos = Vector(center.x, center.y, center.z + ES.MarkerHeight)
local doorPos = frontDoor:GetPos()

local oldFlat = math.sqrt((oldPos.x - doorPos.x) ^ 2 + (oldPos.y - doorPos.y) ^ 2)
ok(oldFlat > 100,
   "БАГ: старая точка значка была в 100+ юнитах от входной двери",
   ("%.0f юнитов"):format(oldFlat))
ok(oldPos.z < 120 and oldPos.z > 80,
   "БАГ: и болталась на середине высоты комнаты, а не над входом", oldPos.z)

-----------------------------------------------------------------------
print("\n=== 2. ГЛАВНАЯ ДВЕРЬ ВЫБИРАЕТСЯ ОСМЫСЛЕННО И СТАБИЛЬНО ===")
-----------------------------------------------------------------------
--[[ ВАЖНО. Первая версия правки выбирала «дверь, ближайшую к ЦЕНТРУ
     зоны» — и этот стенд сразу её завалил: ближе всего к центру стоит
     внутренняя дверь комнаты (y=260 при центре y=150), а вход врезан в
     наружную стену y=0, то есть максимально далеко от центра. Правильный
     признак входа — близость к ГРАНИЦЕ зоны. ]]
local main = ES.MainDoor(flat)
ok(main == frontDoor,
   "ИСПРАВЛЕНО: выбрана дверь у наружной стены (вход), а не внутренняя",
   main and main._id)
ok(main ~= backDoor,
   "внутренняя дверь в глубине помещения главной не считается")

--[[ Прямая проверка признака: у входной двери запас до стены нулевой,
     у внутренней — большой. ]]
local mFront = ES.ZoneEdge(flat, frontDoor:GetPos())
local mBack  = ES.ZoneEdge(flat, backDoor:GetPos())
ok(mFront < mBack, "запас до границы зоны у входа меньше, чем у внутренней двери",
   ("вход %.0f, внутренняя %.0f"):format(mFront, mBack))

--[[ Порядок дверей в записи не должен влиять на результат: список
     rec.doors собирается обходом мира, его порядок не гарантирован. ]]
flat.doors = { "map_m12", "map_m11" }
ok(ES.MainDoor(flat) == frontDoor, "порядок в rec.doors на выбор не влияет")
flat.doors = { "map_m11", "map_m12" }

--[[ Ничья по расстоянию: две двери симметрично от центра. Без разрыва
     ничьей значок прыгал бы между ними от пересчёта к пересчёту. ]]
local tieRec = { id = "tie", estateKind = "estate", doors = { "tieB", "tieA" }, zone = ZONE }
local tA = mkDoor("tieA", Vector(200, 0, 0))
local tB = mkDoor("tieB", Vector(200, 300, 0))
local first = ES.MainDoor(tieRec)
tieRec.doors = { "tieA", "tieB" }
local second = ES.MainDoor(tieRec)
ok(first == second, "при равном расстоянии выбор детерминирован — значок не прыгает",
   (first and first._id or "?") .. " / " .. (second and second._id or "?"))
ok(first == tA, "ничья разрешается по идентификатору двери", first and first._id)
tA._valid, tB._valid = false, false

ok(ES.MainDoor({ id = "x", doors = {} }) == nil, "объект без дверей главной двери не имеет")
ok(ES.MainDoor(nil) == nil, "nil не роняет расчёт")

--[[ Дверь числится за объектом, но на карте её нет (снесли, сменили
     карту): не должно быть ни ошибки, ни выбора «мёртвой» двери. ]]
local ghost = { id = "gh", estateKind = "estate", doors = { "no_such_door" }, zone = ZONE }
ok(ES.MainDoor(ghost) == nil, "исчезнувшая дверь не выбирается и не роняет расчёт")

-----------------------------------------------------------------------
print("\n=== 3. ЗНАЧОК КРЕПИТСЯ К ДВЕРИ ===")
-----------------------------------------------------------------------
local anchor, onDoor, doorEnt = ES.MarkerAnchor(flat)
ok(anchor ~= nil, "точка значка посчитана")
ok(onDoor == true, "и помечена как «на двери» — клиент об этом знает")

--[[ ПЕРЕДЕЛКА 28.08: «таблички не НАД дверями, а НА дверях, как у
     автоматов с едой».

     Раньше сервер считал точку в стене над проёмом и слал угол. Теперь
     он возвращает САМУ ДВЕРЬ: где именно лечь на полотне, знает только
     клиент — по OBB двери, как это делает торговый автомат. ]]
ok(doorEnt == frontDoor,
   "ИСПРАВЛЕНО: сервер отдаёт саму дверь-носитель, а не угол в стене",
   doorEnt and doorEnt._id)

--[[ Позиция теперь совпадает с дверью, а не висит над ней: она нужна
     только для отсечения по дальности. ]]
local newFlat = math.sqrt((anchor.x - doorPos.x) ^ 2 + (anchor.y - doorPos.y) ^ 2)
ok(newFlat < oldFlat / 3,
   "ИСПРАВЛЕНО: точка объекта переехала к двери",
   ("было %.0f, стало %.0f юнитов"):format(oldFlat, newFlat))
ok(newFlat < 1,
   "и совпадает с самой дверью, а не отнесена в сторону",
   ("%.2f"):format(newFlat))

--[[ Точка обязана СОВПАДАТЬ с центром полотна, а не быть «где-то ниже
     верха двери»: первая версия проверки пропускала подъём на 40 юнитов,
     потому что дверь высокая и +40 всё ещё оказывался под её верхом. ]]
local bottom, top = frontDoor:WorldSpaceAABB()
local doorMidZ = (bottom.z + top.z) * 0.5
ok(math.abs(anchor.z - doorMidZ) < 1,
   "ИСПРАВЛЕНО: точка ровно на середине полотна, а не поднята над проёмом",
   ("центр двери %.0f, точка %.0f"):format(doorMidZ, anchor.z))
ok(anchor.z < top.z, "она внутри полотна по верху", anchor.z)
ok(anchor.z > bottom.z, "и по низу — не утоплена в пол", anchor.z)

--[[ Настенного выноса больше нет: убеждаемся, что старые ручки не
     остались висеть в конфиге и не путают. ]]
ok(ES.DoorOffset == nil, "ИСПРАВЛЕНО: настенный вынос убран из конфига")
ok(ES.DoorLift == nil, "и подъём над проёмом тоже")
ok(ES.OutwardDir == nil,
   "мёртвая функция разворота по зоне удалена, а не осталась приманкой")

-----------------------------------------------------------------------
print("\n=== 3b. ПЛАШКА ВПИСЫВАЕТСЯ В ПОЛОТНО ===")
-----------------------------------------------------------------------
--[[ Главное требование «как у автомата»: плашка не должна торчать за
     края двери. Типовое полотно Source около 48 юнитов шириной и
     82-96 высотой. ]]
local DOOR_W, DOOR_H = 48, 82
ok(ES.PlaqueWidth < DOOR_W,
   "ИСПРАВЛЕНО: ширина плашки меньше дверного полотна",
   ("плашка %d, дверь %d"):format(ES.PlaqueWidth, DOOR_W))
ok(ES.PlaqueHeight < DOOR_H,
   "и по высоте помещается", ("плашка %d, дверь %d"):format(ES.PlaqueHeight, DOOR_H))
ok(ES.PlaqueWidth >= DOOR_W * 0.6,
   "но не съёжилась до нечитаемой марки", ES.PlaqueWidth)

--[[ Прежняя настенная ширина 62 за края полотна вылезала — фиксируем
     это как воспроизведение проблемы. ]]
local OLD_W = 62
ok(OLD_W > DOOR_W,
   "БАГ ВОСПРОИЗВЕДЁН: прежняя ширина торчала за края двери",
   ("было %d при полотне %d"):format(OLD_W, DOOR_W))

--[[ Воспроизводим выбор лицевой оси из doorPlaqueFrame: у двери
     толщина — это МЕНЬШАЯ горизонтальная ось OBB. Ошибиться здесь
     значит положить табличку на торец шириной в пару сантиметров. ]]
local function faceAxis(sx, sy) return sx < sy and "x" or "y" end
ok(faceAxis(4, 48) == "x", "тонкая по X дверь показывает грань вдоль X")
ok(faceAxis(48, 4) == "y", "тонкая по Y — вдоль Y")

-- Высота плашки на полотне: чуть выше середины, как номер квартиры.
local function plaqueZ(minz, maxz) return minz + (maxz - minz) * 0.62 end
local pz = plaqueZ(0, DOOR_H)
ok(pz > DOOR_H * 0.5, "плашка выше середины полотна — на уровне глаз", pz)
ok(pz + ES.PlaqueHeight * 0.5 < DOOR_H,
   "и верхний край не вылезает за дверь", pz + ES.PlaqueHeight * 0.5)
ok(pz - ES.PlaqueHeight * 0.5 > 0, "нижний тоже внутри полотна")

-----------------------------------------------------------------------
print("\n=== 3c. УГЛОВАЯ ДВЕРЬ ===")
-----------------------------------------------------------------------
--[[ Раньше разворот считался от границы зоны, и дверь в углу требовала
     особой обработки. Теперь угол берётся у самой двери, поэтому
     угловая дверь ничем не отличается — проверяем, что она просто
     работает. ]]
local cornerDoor = mkDoor("corner_m1", Vector(4, 20, 0))
local corner = { id = "cr", name = "Угловая", estateKind = "estate",
    ownerType = "none", doors = { "corner_m1" }, zone = ZONE, purchasePrice = 1000 }
local cPos, cOnDoor, cDoor = ES.MarkerAnchor(corner)
ok(cOnDoor == true, "угловая дверь тоже становится носителем")
ok(cDoor == cornerDoor, "и отдаётся клиенту как энтити", cDoor and cDoor._id)
ok(math.abs(cPos.x - 4) < 1 and math.abs(cPos.y - 20) < 1,
   "точка совпадает с самой дверью — разворот считает клиент по её углам",
   ("%.1f %.1f"):format(cPos.x, cPos.y))
cornerDoor._valid = false

-----------------------------------------------------------------------
print("\n=== 4. ОБЪЕКТ БЕЗ ДВЕРЕЙ НЕ ТЕРЯЕТ ЗНАЧОК ===")
-----------------------------------------------------------------------
--[[ Старые зоны, к которым двери так и не привязали, обязаны рисоваться
     по-прежнему — иначе правка «спрячет» половину карты. ]]
local noDoors = { id = "nd", name = "Склад", estateKind = "business",
    ownerType = "none", doors = {}, zone = ZONE, purchasePrice = 10000 }
local ndPos, ndOnDoor = ES.MarkerAnchor(noDoors)
ok(ndPos ~= nil, "значок всё равно есть")
ok(ndOnDoor == false, "но помечен как «не на двери»")
ok(math.abs(ndPos.x - center.x) < 0.01 and math.abs(ndPos.y - center.y) < 0.01,
   "запасной вариант — прежний центр зоны")
ok(math.abs(ndPos.z - (center.z + ES.MarkerHeight)) < 0.01,
   "с прежней высотой MarkerHeight", ndPos.z)

local noZone = ES.MarkerAnchor({ id = "nz", doors = {} })
ok(noZone == nil, "объект вообще без зоны точки не даёт — в снимок не попадёт")

-----------------------------------------------------------------------
print("\n=== 5. СНИМОК ДЛЯ КЛИЕНТА НЕСЁТ ТОЧКУ ДВЕРИ ===")
-----------------------------------------------------------------------
ES.InvalidateScan()
local snap = ES.BuildSnapshot()
local row
for _, r in ipairs(snap) do if r.id == "flat2" then row = r end end
ok(row ~= nil, "квартира попала в снимок")
ok(row and row.onDoor == true, "в снимке есть признак «значок на двери»")
ok(row and math.abs(row.pos.x - anchor.x) < 0.01
       and math.abs(row.pos.y - anchor.y) < 0.01
       and math.abs(row.pos.z - anchor.z) < 0.01,
   "координаты в снимке = точка у двери, а не центр зоны",
   row and ("%.0f %.0f %.0f"):format(row.pos.x, row.pos.y, row.pos.z))
ok(row and row.price == 85000, "цена в снимке та, что назначил админ", row and row.price)

--[[ ПЕРЕДЕЛКА 28.08. Раньше в снимок клался УГОЛ плоскости, посчитанный
     от границы зоны. Теперь кладётся индекс двери-носителя, а угол
     клиент берёт у самой двери.

     Так правильнее по двум причинам: табличка едет вместе с
     открывающейся дверью, и косо поставленные двери получают ровную
     плашку, а не развёрнутую по сторонам света. ]]
ok(row and row.yaw == nil,
   "ИСПРАВЛЕНО: угол от зоны из снимка убран — его считает клиент по двери")
ok(row and row.door ~= nil, "в снимке есть дверь-носитель")
ok(row and row.door == frontDoor:EntIndex(),
   "и это именно входная дверь объекта", row and row.door)
ok(row and row.door > 0, "индекс валидный, клиенту будет что искать")

-- У объекта без дверей индекс нулевой: клиент нарисует запасной вариант.
local ndRow
for _, r in ipairs(snap) do if r.id == "nd" then ndRow = r end end
GRM.Property.Records.nd = { id = "nd", name = "Склад", type = "shop",
    estateKind = "business", ownerType = "none", doors = {}, zone = ZONE,
    purchasePrice = 10000 }
ES.InvalidateScan()
for _, r in ipairs(ES.BuildSnapshot()) do if r.id == "nd" then ndRow = r end end
ok(ndRow and ndRow.door == 0, "у зоны без дверей индекс двери нулевой", ndRow and ndRow.door)
ok(ndRow and ndRow.onDoor == false, "и признак «на двери» снят")
GRM.Property.Records.nd = nil

--[[ Точку считает СЕРВЕР: только он знает положение дверей. Проверяем,
     что клиент не пытается искать двери сам. ]]
local src = (function()
    local fh = assert(io.open("lua/autorun/sh_grm_estate.lua", "rb"))
    local t = fh:read("*a") fh:close() return t
end)()
local clientBlock = src:match("if CLIENT then.*$") or ""
ok(clientBlock ~= "", "клиентская часть найдена")
ok(clientBlock:find("MainDoor", 1, true) == nil,
   "клиент не ищет двери сам — берёт готовые координаты из снимка")

-----------------------------------------------------------------------
print("\n=== 6. ПОДПИСЬ ТОЖЕ У ДВЕРИ И ЧИТАЕМА ===")
-----------------------------------------------------------------------
--[[ ПЕРЕДЕЛКА ДИЗАЙНА 28.08 (скриншоты: «ну как-то такое себе»).

     Текст больше НЕ рисуется через HUDPaint для дверей. HUDPaint кладёт
     пиксели поверх всего кадра, игнорируя геометрию, — на скриншотах
     из-за этого были видны надписи соседних квартир прямо сквозь
     бетонную стену. Табличка рисуется в мире (3D2D), и стена честно
     её перекрывает. ]]
--[[ Проверяем именно ТЕЛО функции таблички, а не файл целиком: иначе
     тест проходил бы от любого случайного cam.Start3D2D в другом месте.
     Первая версия этой проверки так и промахнулась — откат рисования
     она не заметила. ]]
local plaqueFn = clientBlock:match("local function drawPlaque.-\n    end") or ""
ok(plaqueFn ~= "", "функция отрисовки таблички найдена")
local starts = select(2, plaqueFn:gsub("cam%.Start3D2D", ""))
local ends   = select(2, plaqueFn:gsub("cam%.End3D2D", ""))
ok(starts >= 1,
   "ИСПРАВЛЕНО: табличка рисуется в мире (3D2D), а не поверх кадра", starts)
ok(starts == ends,
   "каждый Start3D2D закрыт End3D2D — иначе поехал бы весь рендер кадра",
   ("start %d, end %d"):format(starts, ends))
ok(plaqueFn:find("draw.SimpleText(title", 1, true) ~= nil,
   "название объекта рисуется внутри таблички, а не в HUD")
ok(plaqueFn:find("draw.SimpleText(status", 1, true) ~= nil,
   "и строка со статусом/ценой тоже")

--[[ Табличку зовут из мирового прохода рендера, а не из HUDPaint.

     Шаблон цепляем за hook.Add, а НЕ за голое имя хука: первая версия
     совпадала с упоминанием PostDrawTranslucentRenderables в комментарии
     выше по файлу, захватывала заодно объявление drawPlaque и потому не
     замечала, что вызов удалили. ]]
local worldPass = clientBlock:match('hook%.Add%("PostDrawTranslucentRenderables".-\n    end%)') or ""
ok(worldPass ~= "", "мировой проход рендера найден")
ok(worldPass:find("local function drawPlaque", 1, true) == nil,
   "и это именно хук, а не захваченное объявление функции")
ok(worldPass:find("drawPlaque(zone, eyePos)", 1, true) ~= nil,
   "табличка вызывается из мирового прохода — стены её перекрывают")

local hudBlock = clientBlock:match('HUDPaint.-\n    end%)') or ""
ok(hudBlock ~= "", "блок HUDPaint найден")
ok(hudBlock:find("if not zone.onDoor then", 1, true) ~= nil,
   "ИСПРАВЛЕНО: HUD-подпись осталась ТОЛЬКО для зон без дверей — текст больше не светит сквозь стены")

--[[ ТАБЛИЧКА ДВУСТОРОННЯЯ (изменение 28.08).

     Настенная версия рисовалась только снаружи: с изнанки текст был бы
     зеркальным. У плашки НА ПОЛОТНЕ такого ограничения быть не должно —
     номер квартиры нужен и в подъезде, и внутри. Клиент выбирает ту
     грань двери, с которой на неё смотрят. ]]
ok(clientBlock:find("dx * nx + dy * ny > 0", 1, true) == nil,
   "ИСПРАВЛЕНО: одностороннее отсечение по нормали зоны убрано")
ok(clientBlock:find("local side =", 1, true) ~= nil,
   "вместо него выбирается сторона полотна")
ok(clientBlock:find("doorPlaqueFrame(door, side)", 1, true) ~= nil,
   "и плашка строится в углах именно этой грани")

-- Воспроизводим выбор стороны: с какой стороны стоим, ту грань и видим.
local function sideFor(eyeCoord, doorCoord) return (eyeCoord - doorCoord) >= 0 and 1 or -1 end
ok(sideFor(-100, 0) == -1, "игрок снаружи видит наружную грань")
ok(sideFor(150, 0) == 1, "игрок в подъезде — внутреннюю")
ok(sideFor(-100, 0) ~= sideFor(150, 0), "стороны различаются — плашка видна с обеих")

ok(clientBlock:find("Entity(zone.door)", 1, true) ~= nil,
   "клиент берёт дверь по индексу из снимка")
ok(clientBlock:find("door:LocalToWorld", 1, true) ~= nil,
   "и считает место плашки в СОБСТВЕННЫХ углах двери, как торговый автомат")
ok(clientBlock:find("door:OBBMins()", 1, true) ~= nil,
   "через OBB полотна, а не через координаты зоны")

--[[ Для дверных зон клиентская МОДЕЛЬ больше не создаётся: именно она
     на скриншотах врезалась в потолок. Табличка её заменяет. ]]
local ensureBlock = clientBlock:match("local function ensureMarkers.-\n    end") or ""
ok(ensureBlock ~= "", "функция создания моделей найдена")
ok(ensureBlock:find("if not zone.onDoor then", 1, true) ~= nil,
   "ИСПРАВЛЕНО: объёмная эмблема создаётся ТОЛЬКО для зон без дверей")

print("\n--- содержимое таблички ---")
--[[ Табличка обязана нести ровно то, что просил владелец:
     «Квартира №2 стоимость 85.000 GRM». ]]
local tTitle, tStatus, tHint = ES.PlaqueLines({
    name = "Квартира №2", kind = "estate", vacant = true, price = 85000 })
ok(tTitle == "Квартира №2", "на табличке название объекта", tTitle)
ok(tStatus == "СВОБОДНО · 85 000 GRM",
   "и цена с разделителями, как её пишет владелец", tStatus)
ok(tHint == "/buyhome", "для жилья подсказана нужная команда", tHint)

local bTitle, bStatus, bHint = ES.PlaqueLines({
    name = "Ларёк", kind = "business", vacant = true, price = 20000, equipment = 3 })
ok(bHint == "/buybusiness", "для бизнеса — своя команда", bHint)

local oTitle, oStatus, oHint = ES.PlaqueLines({
    name = "Квартира №3", kind = "estate", vacant = false,
    owner = "Александр Фон Грённер" })
ok(oStatus == "Александр Фон Грённер", "у занятого объекта показан владелец", oStatus)
ok(oHint == nil, "и никакой подсказки о покупке — объект не продаётся")

local eqTitle, eqStatus = ES.PlaqueLines({
    name = "Сеть", kind = "business", vacant = false, owner = "Иванов", equipment = 4 })
ok(eqStatus:find("точек: 4", 1, true) ~= nil,
   "у занятого бизнеса видно количество оборудования", eqStatus)

local noName = ES.PlaqueLines({ name = "", kind = "business", vacant = true, price = 0 })
ok(noName == "Бизнес", "объект без имени не даёт пустую табличку", noName)

print("\n--- цена в подписи ---")
ok(ES.Money(85000) == "85 000 GRM",
   "ИСПРАВЛЕНО: цена разбита по разрядам, как её пишет владелец («85.000»)",
   ES.Money(85000))
ok(ES.Money(0) == "0 GRM", "ноль форматируется без мусора", ES.Money(0))
ok(ES.Money(500) == "500 GRM", "короткие суммы не ломаются", ES.Money(500))
ok(ES.Money(1234567) == "1 234 567 GRM", "миллионы читаются", ES.Money(1234567))
--[[ Цену на табличку кладёт ES.PlaqueLines. Проверяем не текст файла, а
     сам результат: так стенд не сломается от перестановки кода. ]]
local _, priceLine = ES.PlaqueLines({ name = "К", kind = "estate", vacant = true, price = 85000 })
ok(priceLine:find("85 000", 1, true) ~= nil,
   "табличка печатает цену через форматирование, а не слитным числом", priceLine)
ok(priceLine:find("85000", 1, true) == nil, "слитного числа на табличке нет", priceLine)

--[[ Если модуль валюты загружен — берём его формат, чтобы табличка у
     двери и HUD показывали суммы одинаково. ]]
local savedFormat = GRM.Format
GRM.Format = function(n) return "≈" .. tostring(n) end
ok(ES.Money(85000) == "≈85000", "при живом модуле валюты используется общий формат",
   ES.Money(85000))
GRM.Format = savedFormat
ok(ES.Money(85000) == "85 000 GRM", "без него — собственный, значок не зависит от порядка загрузки")

-----------------------------------------------------------------------
print("\n=== 7. ДВЕРИ ПРИВЯЗЫВАЮТСЯ СРАЗУ ПРИ СОЗДАНИИ ЗОНЫ ===")
-----------------------------------------------------------------------
--[[ Главная причина, по которой значок «не крепился к дверям»: у
     свежесозданной зоны список дверей пустой, привязка случалась только
     при покупке. Значит до первой продажи эмблема висела в центре. ]]
local ATTACH_CALLS = {}
GRM.EstateDeal = {
    -- Упрощённая, но честная привязка: двери рядом с зоной и ничьи.
    AttachDoors = function(rec)
        ATTACH_CALLS[#ATTACH_CALLS + 1] = rec.id
        rec.doors = istable(rec.doors) and rec.doors or {}
        local have = {}
        for _, id in ipairs(rec.doors) do have[tostring(id)] = true end
        local added = 0
        for _, d in ipairs(DOORS) do
            if IsValid(d) then
                local p = d:GetPos()
                local a, b = rec.zone.mins, rec.zone.maxs
                local r = 96
                local inside = p.x >= a.x - r and p.y >= a.y - r and p.z >= a.z - r
                           and p.x <= b.x + r and p.y <= b.y + r and p.z <= b.z + r
                if inside and not have[d._id] and not GRM.Property.Records.flat2 then
                    rec.doors[#rec.doors + 1] = d._id
                    have[d._id] = true
                    added = added + 1
                end
            end
        end
        return added
    end,
}

-- Убираем прежнюю запись, чтобы двери считались ничьими.
GRM.Property.Records.flat2 = nil
GRM.Property.Normalize = function(r)
    r.doors = istable(r.doors) and r.doors or {}
    r.ownerType = r.ownerType or "none"
    r.utilityDebt = r.utilityDebt or 0
    return r
end

local admin = { _valid = true, IsSuperAdmin = function() return true end,
    SteamID64 = function() return "7" end }

local created, msg, rec = ES.CreateZone(admin,
    Vector(0, 0, 0), Vector(400, 300, 10), "Квартира №2", "estate", 85000)

ok(created == true, "зона создана", msg)
ok(#ATTACH_CALLS == 1, "ИСПРАВЛЕНО: привязка дверей вызвана прямо при создании зоны",
   #ATTACH_CALLS)
ok(rec and #rec.doors >= 1, "у свежей зоны СРАЗУ есть двери",
   rec and #rec.doors)
ok(tostring(msg):find("дверей:", 1, true) ~= nil,
   "админ видит в ответе, сколько дверей подтянулось", msg)

--[[ И главное: значок свежей зоны уже крепится к двери, ещё до того,
     как объект кто-то купил. Раньше здесь был бы центр комнаты. ]]
local freshPos, freshOnDoor = ES.MarkerAnchor(rec)
ok(freshOnDoor == true, "ИСПРАВЛЕНО: значок новой зоны сразу на двери")
local freshFlat = math.sqrt((freshPos.x - doorPos.x) ^ 2 + (freshPos.y - doorPos.y) ^ 2)
ok(freshFlat < oldFlat / 3, "и он рядом с дверью, а не посреди комнаты",
   ("%.0f юнитов"):format(freshFlat))
ok(rec.ownerType == "none", "при этом объект остался СВОБОДНЫМ — привязка не продаёт его")

-- Привязка не должна падать, если модуль сделок ещё не загружен.
GRM.EstateDeal = nil
local ok2, msg2, rec2 = ES.CreateZone(admin,
    Vector(1000, 0, 0), Vector(1400, 300, 10), "Склад", "business", 20000)
ok(ok2 == true, "без модуля сделок зона всё равно создаётся", msg2)
ok(rec2 and #rec2.doors == 0, "просто без дверей — падения нет")

-----------------------------------------------------------------------
print("\n=== 8. НАСТРОЙКИ РАЗМЕРА ЗДРАВЫЕ ===")
-----------------------------------------------------------------------
ok(ES.PlaqueWidth > 0 and ES.PlaqueWidth < 48,
   "ширина плашки положительная и меньше полотна", ES.PlaqueWidth)
ok(ES.PlaqueHeight > 0 and ES.PlaqueHeight < 40,
   "высота как у таблички с номером, а не во всю дверь", ES.PlaqueHeight)
ok(ES.PlaqueWidth > ES.PlaqueHeight,
   "плашка горизонтальная — так текст читается лучше")
ok(ES.PlaqueDistance > 0 and ES.PlaqueDistance <= ES.DrawDistance,
   "порог читаемости не больше дальности отрисовки",
   ("%d из %d"):format(ES.PlaqueDistance, ES.DrawDistance))

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
