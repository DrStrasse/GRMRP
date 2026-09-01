--[[ Живой прогон ядра зон бизнеса и жилья, фаза 2 (заказ владельца 27.08).

     Проверяется, что заложены именно решения владельца:
       1) вид объекта: жильё и бизнес, значки нужного цвета и размера;
       2) СКАНИРОВАНИЕ: зона сама знает, что внутри — вручную ничего
          не привязывается, убрали автомат и точка пересчиталась;
       3) одиночный автомат живёт без зоны, несколько — только через
          бизнес-зону;
       4) лимит 3 бизнеса в одни руки, жильё в лимит не входит;
       5) просрочка коммуналки даёт ПЕНЮ, а не отключение и не изъятие;
       6) цену назначает админ, площадь — только подсказка.

     Запуск: luajit tools/luatest/sim_estate_core.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o)
        local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
        return dx * dx + dy * dy + dz * dz
    end
    return v
end
function CurTime() return _G.__now or 0 end
function ErrorNoHalt() end
function ConVarExists() return true end
function CreateConVar() end
function GetConVar() return { GetInt = function() return 3 end } end
bit = { bor = function(a, b) return a end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    Compress = function(x) return x end }
net = setmetatable({}, { __index = function() return function() return "" end end })
local WORLD = {}
ents = { FindByClass = function(c)
    local out = {}
    for _, e in ipairs(WORLD) do if e._class == c then out[#out + 1] = e end end
    return out
end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

local function mkEnt(class, pos)
    local e = { _valid = true, _class = class, _pos = pos,
        GetPos = function(s) return s._pos end }
    WORLD[#WORLD + 1] = e
    return e
end

--- Объект недвижимости с зоной 0..400 по X и Y.
local shop = {
    id = "shop1", name = "Торговый угол", type = "shop",
    ownerType = "none", ownerKey = "", ownerName = "",
    purchasePrice = 85000, utilityRate = 500, utilityDebt = 0,
    zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 400, y = 400, z = 200 } },
}
local flat = {
    id = "flat1", name = "Квартира 14", type = "apartment",
    ownerType = "character", ownerKey = "1:char1", ownerName = "Иванов",
    purchasePrice = 50000, utilityRate = 300, utilityDebt = 0,
    zone = { mins = { x = 900, y = 0, z = 0 }, maxs = { x = 1100, y = 200, z = 200 } },
}
GRM.Property = { Records = { shop1 = shop, flat1 = flat }, Save = function() end }

print("\n=== 1. ВИД ОБЪЕКТА И ЗНАЧКИ ===")
ok(ES.KindOf(shop) == "business", "магазин — это бизнес")
ok(ES.KindOf(flat) == "estate", "квартира — это жильё")
ok(ES.KindOf({ type = "government" }) == "none", "госздание значка не получает")
shop.estateKind = "estate"
ok(ES.KindOf(shop) == "estate", "явно заданный вид сильнее типа")
shop.estateKind = ""

ok(ES.MarkerModel == "models/props_phx/facepunch_logo.mdl", "модель значка как в заказе")
--[[ Размеры пересмотрены 27.08: владелец увидел значки на карте и
     попросил «масштаб ещё меньше, а то слишком большой размер».
     Исходные 1/1.5 и 1/2 перекрывали полдороги. Подробности размера,
     поворота и материала — в sim_estate_marker_ui.lua. ]]
ok(ES.MarkerScale.business < 1 / 1.5 and ES.MarkerScale.business > 0.05,
   "бизнес-значок уменьшен по замечанию владельца", ES.MarkerScale.business)
ok(ES.MarkerScale.estate < 1 / 2 and ES.MarkerScale.estate > 0.05,
   "значок жилья уменьшен по замечанию владельца", ES.MarkerScale.estate)
ok(ES.MarkerScale.business > ES.MarkerScale.estate,
   "бизнес крупнее жилья — виды различимы")
local yellow = ES.MarkerColor.business
ok(yellow.r > 200 and yellow.g > 150 and yellow.b < 120, "бизнес жёлтый")
local green = ES.MarkerColor.estate
ok(green.g > 180 and green.r < 140, "жильё зелёное")

print("\n=== 2. ЗОНА САМА ЗНАЕТ, ЧТО ВНУТРИ ===")
local v1 = mkEnt("grm_vending_machine", Vector(100, 100, 10))
local v2 = mkEnt("grm_vending_machine", Vector(200, 150, 10))
local pump = mkEnt("grm_fuel_pump", Vector(300, 300, 10))
mkEnt("grm_vending_machine", Vector(5000, 5000, 10))   -- далеко, не считается

ES.InvalidateScan()
local scan = ES.ScanZone(shop)
ok(scan.total == 3, "внутри зоны найдено три точки", scan.total)
ok(scan.byKind.vending == 2 and scan.byKind.fuel == 1, "автоматы и колонки различаются")
ok(ES.EquipmentSummary(shop):find("2 автом", 1, true) ~= nil,
   "сводка читаемая", ES.EquipmentSummary(shop))

-- Убрали автомат — точка обязана пересчитаться сама.
v2._valid = false
ES.InvalidateScan()
ok(ES.ScanZone(shop).total == 2, "убрали автомат — зона пересчиталась без ручной правки")
v2._valid = true
ES.InvalidateScan()

ok(ES.PointInZone(shop, Vector(200, 200, 50)) == true, "точка внутри опознаётся")
ok(ES.PointInZone(shop, Vector(700, 200, 50)) == false, "точка снаружи — нет")
ok(ES.ScanZone({ id = "x" }).total == 0, "объект без зоны не роняет сканирование")

print("\n=== 3. ОДИНОЧНАЯ ТОЧКА ЖИВЁТ БЕЗ ЗОНЫ (решение владельца) ===")
-- Автомат в чистом поле, соседей нет.
local lonely = mkEnt("grm_vending_machine", Vector(9000, 9000, 10))
ok(ES.CanOwnStandalone(lonely) == true,
   "одиночный автомат можно выкупить лично, как раньше")

-- Рядом поставили второй — это уже сеть.
local buddy = mkEnt("grm_vending_machine", Vector(9200, 9000, 10))
local canPair, whyPair = ES.CanOwnStandalone(lonely)
ok(canPair == false, "две точки рядом — требуется бизнес-зона", whyPair)
ok(tostring(whyPair):find("бизнес%-зону") ~= nil, "и причина понятная", whyPair)
buddy._valid = false

-- Точка внутри оформленного бизнеса принадлежит ему.
local inside, whyInside = ES.CanOwnStandalone(v1)
ok(inside == false, "точка внутри бизнес-зоны лично не выкупается", whyInside)
ok(tostring(whyInside):find("Торговый угол", 1, true) ~= nil,
   "и сказано, какому бизнесу она принадлежит", whyInside)

ok(ES.ZoneAt(Vector(100, 100, 10)) == shop, "зона по координатам находится")
ok(ES.ZoneAt(Vector(9000, 9000, 10)) == nil, "в чистом поле зоны нет")

print("\n=== 4. ЛИМИТ БИЗНЕСОВ (решение владельца: 2-3) ===")
ok(ES.Limit() == 3, "лимит по умолчанию — 3", ES.Limit())
local ply = { _valid = true, IsSuperAdmin = function() return false end,
    SteamID64 = function() return "1" end }
GRM.Identity = { CharacterKey = function() return "1:char1" end }

ok(ES.CountOwned("1:char1") == 0, "у игрока пока нет бизнесов")
ok(ES.CanAcquire(ply, shop) == true, "первый бизнес купить можно")

-- Набираем лимит.
for i = 1, 3 do
    GRM.Property.Records["b" .. i] = { id = "b" .. i, name = "Точка " .. i, type = "shop",
        ownerType = "character", ownerKey = "1:char1",
        zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 1, y = 1, z = 1 } } }
end
ok(ES.CountOwned("1:char1") == 3, "три бизнеса засчитаны", ES.CountOwned("1:char1"))
local canMore, whyMore = ES.CanAcquire(ply, shop)
ok(canMore == false, "четвёртый бизнес не даётся", whyMore)
ok(tostring(whyMore):find("Лимит", 1, true) ~= nil, "и объясняет почему", whyMore)

ok(ES.CanAcquire(ply, flat) == true,
   "жильё в лимит бизнесов НЕ входит — его купить по-прежнему можно")
local admin = { _valid = true, IsSuperAdmin = function() return true end,
    SteamID64 = function() return "9" end }
ok(ES.CanAcquire(admin, shop) == true, "суперадмина лимит не держит")

for i = 1, 3 do GRM.Property.Records["b" .. i] = nil end

print("\n=== 5. ПЕНЯ ЗА ПРОСРОЧКУ (не отключение и не изъятие) ===")
shop.ownerType = "character"
shop.ownerKey = "1:char1"
shop.utilityRate = 500
shop.utilityDebt = 0
ok(ES.ApplyPenalty(shop) == 0, "без долга пени нет")

shop.utilityDebt = 1000    -- два периода: ещё в пределах терпимости
ok(ES.ApplyPenalty(shop) == 0, "небольшая просрочка прощается")

shop.utilityDebt = 2000    -- четыре периода
local add = ES.ApplyPenalty(shop)
ok(add > 0, "долгая просрочка начисляет пеню", add)
ok(shop.utilityDebt > 2000, "долг вырос", shop.utilityDebt)
ok(shop.estatePenalty == add, "накопленная пеня видна отдельным полем")
ok(shop.ownerType == "character", "объект при этом НЕ изымается — как и просил владелец")

local before = shop.utilityDebt
ES.ApplyPenalty(shop)
ok(shop.utilityDebt > before, "пеня продолжает капать, пока долг не погашен")
shop.utilityDebt = 0
ES.ApplyPenalty(shop)
ok(shop.estatePenalty == 0, "погасили долг — счётчик пени обнулился")
shop.ownerType = "none"; shop.ownerKey = ""

print("\n=== 6. ЦЕНА И ПЛОЩАДЬ ===")
ok(shop.purchasePrice == 85000, "цену задаёт админ, автоподсчёт её не трогает")
local area = ES.ZoneArea(shop)
ok(area > 0, "площадь считается как подсказка", area .. " м²")
ok(ES.ZoneArea({}) == 0, "объект без зоны не роняет расчёт")

print("\n=== 7. СНИМОК ДЛЯ КЛИЕНТА ===")
ES.InvalidateScan()
local snap = ES.BuildSnapshot()
ok(#snap == 2, "в снимок попали оба объекта с зонами", #snap)
local shopRow
for _, row in ipairs(snap) do if row.id == "shop1" then shopRow = row end end
ok(shopRow ~= nil and shopRow.kind == "business", "бизнес помечен видом")
ok(shopRow and shopRow.vacant == true, "свободный объект помечен — значок станет синим")
ok(shopRow and shopRow.equipment == 3, "в снимке видно количество точек", shopRow and shopRow.equipment)
ok(shopRow and shopRow.pos.z > 100, "значок поднят над центром зоны")

GRM.Property.Records.gov = { id = "gov", name = "Мэрия", type = "government",
    ownerType = "none", zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 10, y = 10, z = 10 } } }
ok(#ES.BuildSnapshot() == 2, "госздание значка не получает и в снимок не идёт")

print("\n=== 8. СВЯЗЬ С МОДУЛЕМ НЕДВИЖИМОСТИ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local prop = body("lua/autorun/sh_grm_property.lua")
ok(prop:find("r.estateKind=", 1, true) ~= nil, "вид объекта хранится в записи недвижимости")
ok(prop:find("r.estatePenalty=", 1, true) ~= nil, "и накопленная пеня тоже")
ok(prop:find("if a.estateKind~=nil then", 1, true) ~= nil, "админ может задать вид вручную")
ok(prop:find("GRM.Estate.InvalidateScan(r)", 1, true) ~= nil,
   "правка объекта сбрасывает кэш сканирования")
ok(prop:find("estateKind=(GRM.Estate and GRM.Estate.KindOf", 1, true) ~= nil,
   "вид уходит клиенту в снимке объекта")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
