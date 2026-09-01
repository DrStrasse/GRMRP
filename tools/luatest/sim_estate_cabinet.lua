--[[ Живой прогон кабинета владельца, фаза 6 (заказ владельца 27.08):
     «чем я владею и сколько это приносит» — один список вместо обхода
     карты и открытия каждого объекта отдельно.

     Проверяется:
       1) в кабинет попадают только СВОИ объекты;
       2) общий доход, касса и долги суммируются верно;
       3) сбор касс со всех объектов разом, с гашением долгов;
       4) сортировка: бизнес выше жилья, где деньги — то сверху;
       5) аренда показывает остаток срока;
       6) /business: свободный объект → окно сделки, свой → панель,
          вне зоны → кабинет (уточнено 28.08).

     Запуск: luajit tools/luatest/sim_estate_cabinet.lua ]]
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
function CurTime() return 1500 end
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

local WALLET = {}
GRM = {
    GiveMoney = function(p, n) WALLET[p] = (WALLET[p] or 0) + n end,
    TakeMoney = function(p, n) WALLET[p] = (WALLET[p] or 0) - n end,
    HasMoney = function(p, n) return (WALLET[p] or 0) >= n end,
}

assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

GRM.Property = { Records = {}, Normalize = function(r) return r end,
    Reindex = function() end, Save = function() end }

local me = { _valid = true, _key = "1:char1", _pos = Vector(50, 50, 10),
    IsSuperAdmin = function() return false end, SteamID64 = function() return "1" end,
    GetPos = function(s) return s._pos end, Nick = function() return "Я" end,
    GetNWString = function(_, _, d) return d or "Я" end }
local other = { _valid = true, _key = "2:char1", _pos = Vector(50, 50, 10),
    IsSuperAdmin = function() return false end, SteamID64 = function() return "2" end,
    GetPos = function(s) return s._pos end, Nick = function() return "Он" end,
    GetNWString = function(_, _, d) return d or "Он" end }
GRM.Identity = { CharacterKey = function(p) return p._key end,
    ResolveCharacter = function(k) if k == "1:char1" then return me end return other end }

--- Автоматы с кассой внутри конкретной зоны.
local function mkVend(pos, cash, sold, earned)
    local e = { _valid = true, _class = "grm_vending_machine", _pos = pos, _cash = cash or 0,
        GRMVendSold = sold or 0, GRMVendEarned = earned or 0,
        GetPos = function(s) return s._pos end, GetClass = function(s) return s._class end }
    WORLD[#WORLD + 1] = e
    return e
end
GRM.VendingBiz = {
    GetCash = function(e) return e._cash or 0 end,
    SetCash = function(e, n) e._cash = math.max(0, math.floor(n or 0)) end,
    GetStats = function(e) return e.GRMVendSold or 0, e.GRMVendEarned or 0 end,
}

local function mkRec(id, name, kind, ownerKey, x, opts)
    opts = opts or {}
    local r = {
        id = id, name = name, type = kind == "estate" and "apartment" or "shop",
        estateKind = kind,
        ownerType = ownerKey ~= "" and "character" or "none",
        ownerKey = ownerKey, ownerName = ownerKey == "1:char1" and "Я" or "Он",
        purchasePrice = opts.price or 50000,
        utilityDebt = opts.debt or 0, estatePenalty = 0,
        estateSince = os.time() - 86400,
        tenure = opts.tenure or "owned",
        rentUntil = opts.rentUntil or 0,
        zone = { mins = { x = x, y = 0, z = 0 }, maxs = { x = x + 300, y = 300, z = 200 } },
    }
    GRM.Property.Records[id] = r
    return r
end

print("\n=== 1. В КАБИНЕТ ПОПАДАЮТ ТОЛЬКО СВОИ ===")
local shopA = mkRec("a", "Магазин на углу", "business", "1:char1", 0)
local shopB = mkRec("b", "Заправка", "business", "1:char1", 1000, { debt = 400 })
local flat  = mkRec("c", "Квартира 14", "estate", "1:char1", 2000)
mkRec("d", "Чужой ларёк", "business", "2:char1", 3000)
mkRec("e", "Свободная точка", "business", "", 4000)

mkVend(Vector(100, 100, 10), 500, 5, 1500)      -- в shopA
mkVend(Vector(1100, 100, 10), 900, 9, 2700)     -- в shopB
ES.InvalidateScan()

local data = ES.CabinetData(me)
ok(#data.rows == 3, "видны три своих объекта", #data.rows)
for _, row in ipairs(data.rows) do
    ok(row.name ~= "Чужой ларёк" and row.name ~= "Свободная точка",
       "чужое и свободное в кабинет не попало: " .. tostring(row.name))
    break
end
local names = {}
for _, row in ipairs(data.rows) do names[row.name] = true end
ok(names["Чужой ларёк"] == nil, "чужой объект отсутствует")
ok(names["Свободная точка"] == nil, "свободный объект отсутствует")
ok(#ES.CabinetData(other).rows == 1, "у другого игрока свой список", #ES.CabinetData(other).rows)

print("\n=== 2. ИТОГИ СУММИРУЮТСЯ ===")
ok(data.totals.cash == 1400, "касса собрана со всех объектов", data.totals.cash)
ok(data.totals.debt == 400, "долги тоже сложены", data.totals.debt)
ok(data.totals.earned == 4200, "заработок за всё время суммируется", data.totals.earned)
ok(data.totals.business == 2 and data.totals.estate == 1,
   "бизнесы и жильё посчитаны раздельно")
ok(data.totals.daily > 0, "общий доход в сутки посчитан", data.totals.daily)
ok(data.limit == 3 and data.owned == 2, "лимит и занятые места видны", data.owned .. "/" .. data.limit)

print("\n=== 3. СОРТИРОВКА ===")
ok(data.rows[1].kind == "business", "бизнес выше жилья")
ok(data.rows[#data.rows].kind == "estate", "жильё в конце")
ok(data.rows[1].cash >= data.rows[2].cash, "внутри вида сверху то, где больше касса",
   data.rows[1].cash .. " >= " .. data.rows[2].cash)

print("\n=== 4. СБОР СО ВСЕХ ОБЪЕКТОВ РАЗОМ ===")
WALLET[me] = 0
local okAll, msgAll = ES.CollectAll(me)
ok(okAll == true, "кассы собираются одной кнопкой", msgAll)
--[[ 1400 в кассах минус 400 долга на второй точке = 1000 на руки. ]]
ok(WALLET[me] == 1000, "на руки пришло за вычетом долга", WALLET[me])
ok(shopB.utilityDebt == 0, "долг погашен из выручки объекта")
ok(tostring(msgAll):find("погашено долгов 400", 1, true) ~= nil,
   "и это сказано владельцу", msgAll)
ok(ES.CabinetData(me).totals.cash == 0, "кассы пусты")
ok(select(1, ES.CollectAll(me)) == false, "повторный сбор отклоняется")
ok(select(1, ES.CollectAll(other)) == false, "чужие кассы не собираются")

print("\n=== 5. АРЕНДА ПОКАЗЫВАЕТ СРОК ===")
local rented = mkRec("r", "Съёмный офис", "business", "1:char1", 5000,
    { tenure = "rent", rentUntil = os.time() + 7200 })
local d2 = ES.CabinetData(me)
local rentRow
for _, row in ipairs(d2.rows) do if row.id == "r" then rentRow = row end end
ok(rentRow ~= nil and rentRow.tenure == "rent", "аренда помечена")
ok(rentRow and rentRow.rentLeft == 2, "остаток срока в часах", rentRow and rentRow.rentLeft)
local ownRow
for _, row in ipairs(d2.rows) do if row.id == "a" then ownRow = row end end
ok(ownRow and ownRow.rentLeft == 0, "у собственности срока нет")

print("\n=== 6. ПРОДАЖА ВИДНА В КАБИНЕТЕ ===")
ES.SetForSale(me, shopA, 70000)
local d3 = ES.CabinetData(me)
local saleRow
for _, row in ipairs(d3.rows) do if row.id == "a" then saleRow = row end end
ok(saleRow and saleRow.forSale == 70000, "выставленный объект помечен ценой",
   saleRow and saleRow.forSale)

print("\n=== 7. КОМАНДЫ И ИНТЕРФЕЙС ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local core = body("lua/autorun/sh_grm_estate.lua")
ok(core:find('concommand.Add("grm_cabinet"', 1, true) ~= nil, "есть команда кабинета")
ok(core:find('low == "/cabinet"', 1, true) ~= nil, "и чат-команда")
--[[ Ветвление уточнено 28.08: у свободного объекта теперь открывается
     окно сделки, а не админское /property_admin. ]]
ok(core:find("ES.OpenCabinet(ply)", 1, true) ~= nil,
   "/business вне зоны открывает кабинет")
ok(core:find("GRM.EstateDeal.Open(ply, ES.KindOf(rec))", 1, true) ~= nil,
   "у свободного объекта — окно сделки с ценой и кнопкой")
ok(core:find("ES.OpenPanel(ply, rec)", 1, true) ~= nil,
   "у своего — панель управления")
ok(core:find("СОБРАТЬ КАССЫ СО ВСЕХ ОБЪЕКТОВ", 1, true) ~= nil, "кнопка общего сбора")
ok(core:find("МОИ ОБЪЕКТЫ", 1, true) ~= nil, "заголовок кабинета")
ok(core:find("Доход в сутки: ", 1, true) ~= nil, "общий доход показан крупно")
ok(core:find('GRM.Net.Guard(ply, "estate.cabinet"', 1, true) ~= nil,
   "запросы кабинета ограничены по частоте")
ok(core:find("У вас пока нет объектов", 1, true) ~= nil,
   "пустой кабинет объясняет, где искать объекты")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
