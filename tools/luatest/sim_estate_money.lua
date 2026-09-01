--[[ Живой прогон денег бизнеса, фаза 4 (заказ владельца 27.08):
     общая касса бизнеса вместо кассы на каждом автомате.

     Проверяется:
       1) касса бизнеса собирает выручку всех точек внутри зоны;
       2) долг по коммуналке гасится ПЕРВЫМ — иначе владелец копил бы
          пеню и снимал выручку мимо неё;
       3) дыра, найденная при разборе: прежний владелец автомата или
          колонки внутри чужой бизнес-зоны НЕ может снять кассу мимо
          владельца зоны;
       4) выкуп одиночной точки работает, в скоплении — требует зону;
       5) статистика: продано, заработано, доход в сутки;
       6) действия только вблизи объекта.

     Запуск: luajit tools/luatest/sim_estate_money.lua ]]
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
function CurTime() return 900 end
function ErrorNoHalt() end
function ConVarExists() return true end
function CreateConVar() end
function GetConVar() return { GetInt = function() return 3 end } end
bit = { bor = function(a) return a end }
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
    for _, e in ipairs(WORLD) do if e._class == c and e._valid ~= false then out[#out + 1] = e end end
    return out
end }

--- Кошелёк игроков.
local WALLET = {}
GRM = { GiveMoney = function(ply, n) WALLET[ply] = (WALLET[ply] or 0) + n end }

assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    Reindex = function() end,
    Save = function() end,
}
GRM.Identity = { CharacterKey = function(p) return p._key end }

--- Автомат со своей кассой (как в реальном модуле).
local function mkVending(pos, cash, sold, earned)
    local e = { _valid = true, _class = "grm_vending_machine", _pos = pos, _cash = cash or 0,
        GRMVendSold = sold or 0, GRMVendEarned = earned or 0,
        GetPos = function(s) return s._pos end,
        GetClass = function(s) return s._class end }
    WORLD[#WORLD + 1] = e
    return e
end
local function mkPump(pos, cash)
    local e = { _valid = true, _class = "grm_fuel_pump", _pos = pos, _cash = cash or 0,
        GetPos = function(s) return s._pos end,
        GetClass = function(s) return s._class end,
        GetCash = function(s) return s._cash end,
        SetCash = function(s, n) s._cash = n end }
    WORLD[#WORLD + 1] = e
    return e
end

GRM.VendingBiz = {
    GetCash = function(e) return e._cash or 0 end,
    SetCash = function(e, n) e._cash = math.max(0, math.floor(n or 0)) end,
    GetStats = function(e) return e.GRMVendSold or 0, e.GRMVendEarned or 0 end,
}

local shop = {
    id = "shop1", name = "Торговый угол", type = "shop", estateKind = "business",
    ownerType = "character", ownerKey = "1:char1", ownerName = "Иванов",
    utilityDebt = 0, utilityRate = 500, estatePenalty = 0,
    estateSince = os.time() - 2 * 86400,      -- владеет двое суток
    purchasePrice = 85000,
    zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 400, y = 400, z = 200 } },
}
GRM.Property.Records = { shop1 = shop }

local owner   = { _valid = true, _key = "1:char1", _pos = Vector(100, 100, 10),
    IsSuperAdmin = function() return false end, SteamID64 = function() return "1" end,
    GetPos = function(s) return s._pos end }
local stranger = { _valid = true, _key = "9:char1", _pos = Vector(100, 100, 10),
    IsSuperAdmin = function() return false end, SteamID64 = function() return "9" end,
    GetPos = function(s) return s._pos end }

print("\n=== 1. ОБЩАЯ КАССА БИЗНЕСА ===")
local v1 = mkVending(Vector(100, 100, 10), 400, 4, 1200)
local v2 = mkVending(Vector(200, 200, 10), 300, 3, 900)
local pump = mkPump(Vector(300, 150, 10), 500)
mkVending(Vector(9000, 9000, 10), 999)     -- снаружи, не считается

ES.InvalidateScan()
ok(ES.CashInZone(shop) == 1200, "касса бизнеса складывает выручку всех точек", ES.CashInZone(shop))

WALLET[owner] = 0
local okCol, msgCol = ES.Collect(owner, shop)
ok(okCol == true, "владелец снимает кассу разом", msgCol)
ok(WALLET[owner] == 1200, "деньги получены полностью", WALLET[owner])
ok(v1._cash == 0 and v2._cash == 0 and pump._cash == 0, "все точки обнулены")
ok(ES.CashInZone(shop) == 0, "касса пуста")
ok(select(1, ES.Collect(owner, shop)) == false, "пустую кассу снять нельзя")

print("\n=== 2. ДОЛГ ГАСИТСЯ ПЕРВЫМ ===")
v1._cash = 1000
shop.utilityDebt = 300
shop.estatePenalty = 50
WALLET[owner] = 0
ES.InvalidateScan()
local okDebt, msgDebt = ES.Collect(owner, shop)
ok(okDebt == true, "снятие проходит", msgDebt)
ok(shop.utilityDebt == 0, "долг погашен из выручки")
ok(WALLET[owner] == 700, "владелец получил остаток", WALLET[owner])
ok(tostring(msgDebt):find("погашен долг 300", 1, true) ~= nil,
   "и ему объяснили, почему меньше", msgDebt)
ok(shop.estatePenalty == 0, "пеня обнулилась вместе с долгом")

-- Долг больше выручки: уходит всё, владелец получает ноль.
v1._cash = 200
shop.utilityDebt = 1000
WALLET[owner] = 0
ES.InvalidateScan()
local okAll, msgAll = ES.Collect(owner, shop)
ok(okAll == true and WALLET[owner] == 0, "при большом долге владелец не получает ничего")
ok(shop.utilityDebt == 800, "долг уменьшился на сумму выручки", shop.utilityDebt)
ok(tostring(msgAll):find("на погашение долга", 1, true) ~= nil, "и это сказано прямо", msgAll)
shop.utilityDebt = 0

print("\n=== 3. ДЫРА ЗАКРЫТА: КАССА МИМО ВЛАДЕЛЬЦА ЗОНЫ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local vend = body("lua/autorun/sh_grm_vending_biz.lua")
local fuel = body("lua/autorun/sh_grm_fuel.lua")
ok(vend:find("GRM.Estate.ZoneAt(ent:GetPos())", 1, true) ~= nil,
   "снятие с автомата проверяет, не в бизнес-зоне ли он")
ok(vend:find("Автомат принадлежит бизнесу", 1, true) ~= nil,
   "чужому владельцу автомата отказывают")
ok(vend:find("return GRM.Estate.Collect(ply, zone)", 1, true) ~= nil,
   "а владелец зоны через ту же кнопку снимает всю кассу бизнеса")
ok(fuel:find("Колонка принадлежит бизнесу", 1, true) ~= nil,
   "та же защита у бензоколонок")
ok(fuel:find("GRM.Estate.Collect(ply, zone)", 1, true) ~= nil,
   "и тот же сбор через бизнес")

ok(ES.IsOwner(owner, shop) == true, "владелец зоны опознаётся")
ok(ES.IsOwner(stranger, shop) == false, "посторонний — нет")
ok(select(1, ES.Collect(stranger, shop)) == false, "чужой кассу бизнеса не снимет")

print("\n=== 4. ВЫКУП ТОЧКИ УВАЖАЕТ ЗОНУ ===")
ok(vend:find("GRM.Estate.CanOwnStandalone(ent)", 1, true) ~= nil,
   "выкуп автомата проверяет правило одиночной точки")
local lonely = mkVending(Vector(7000, 7000, 10), 0)
ok(ES.CanOwnStandalone(lonely) == true, "одиночный автомат выкупается лично — как решил владелец")
ok(select(1, ES.CanOwnStandalone(v1)) == false, "автомат внутри бизнес-зоны — нет")

print("\n=== 5. СТАТИСТИКА ===")
local sold, earned = ES.StatsInZone(shop)
ok(sold == 7 and earned == 2100, "продажи всех точек суммируются", sold .. " / " .. earned)
local daily = ES.DailyEstimate(shop)
ok(daily > 0 and daily <= earned, "доход в сутки посчитан", daily)
-- Пустая зона в другом месте карты: точек внутри нет, значит и дохода нет.
ok(ES.DailyEstimate({ id = "empty", zone = {
    mins = { x = 6000, y = 6000, z = 0 }, maxs = { x = 6100, y = 6100, z = 100 } } }) == 0,
   "без продаж дохода нет")

local sum = ES.Summary(shop)
ok(sum.kind == "business" and sum.equipment == 3, "сводка собирает всё для окна")
ok(sum.sold == 7 and sum.earned == 2100, "статистика в сводке на месте")
ok(sum.area > 0 and sum.price == 85000, "площадь и цена тоже")

local flat = { id = "f", name = "Квартира", type = "apartment", ownerType = "none",
    zone = { mins = { x = 800, y = 0, z = 0 }, maxs = { x = 900, y = 100, z = 100 } } }
GRM.Property.Records.f = flat
local flatSum = ES.Summary(flat)
ok(flatSum.kind == "estate" and flatSum.cash == 0, "у жилья кассы нет")
ok(select(1, ES.Collect(owner, flat)) == false, "и снять с него нечего")

print("\n=== 6. ОКНО И ДОСТУП ===")
local core = body("lua/autorun/sh_grm_estate.lua")
ok(core:find("function ES.ZoneOfPlayer(ply)", 1, true) ~= nil, "объект определяется по месту игрока")
ok(core:find('concommand.Add("grm_business"', 1, true) ~= nil, "есть команда открытия окна")
ok(core:find('low == "/business"', 1, true) ~= nil, "и чат-команда")
ok(core:find("not ES.PointInZone(rec, ply:GetPos())", 1, true) ~= nil,
   "управлять бизнесом издалека нельзя")
ok(core:find("СНЯТЬ КАССУ", 1, true) ~= nil, "в окне есть кнопка снятия")
ok(core:find("Долг по коммунальным", 1, true) ~= nil,
   "долг показан отдельной строкой — понятно, почему выдали меньше")
ok(core:find('GRM.Net.Guard(ply, "estate.act"', 1, true) ~= nil, "действия ограничены по частоте")
ok(core:find("Точка входа", 1, true) ~= nil, "у жилья показано, что оно даёт точку входа")

print("\n=== 7. СМЕНА ВЛАДЕЛЬЦА ОБНУЛЯЕТ ОТСЧЁТ ===")
ok(core:find('hook.Add("GRM_PropertyOwnerChanged", "GRM_Estate_OwnStamp"', 1, true) ~= nil,
   "начало владения отмечается")
ok(core:find("rec.estateSince = os.time()", 1, true) ~= nil,
   "чтобы прошлые продажи не искажали доход нового хозяина")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
