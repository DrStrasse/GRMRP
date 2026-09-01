--[[ Живой прогон рынка объектов, фаза 5 (заказ владельца 27.08):
     покупка и продажа бизнеса и жилья, лимит 2-3 в одни руки.

     Проверяется:
       1) продажа государству за долю цены;
       2) выставление на рынок и покупка другим игроком;
       3) ДОЛГ УДЕРЖИВАЕТСЯ при продаже — иначе продажа стала бы
          способом сбросить накопленную пеню;
       4) лимит бизнесов соблюдается и при покупке с рынка;
       5) кассу нельзя потерять вместе с объектом;
       6) предложение конкретному игроку и его срок;
       7) объект, размеченный тулом без дверей, всё равно покупается.

     Запуск: luajit tools/luatest/sim_estate_market.lua ]]
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
function CurTime() return 1200 end
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

local function mkPly(key, money)
    local p = { _valid = true, _key = key, _pos = Vector(100, 100, 10),
        IsSuperAdmin = function() return false end,
        SteamID64 = function() return key end,
        GetPos = function(s) return s._pos end,
        Nick = function() return key end,
        GetNWString = function(_, _, d) return d or key end }
    WALLET[p] = money or 0
    return p
end
local seller = mkPly("1:char1", 0)
local buyer  = mkPly("2:char1", 200000)
local poor   = mkPly("3:char1", 100)
GRM.Identity = {
    CharacterKey = function(p) return p._key end,
    ResolveCharacter = function(k)
        for _, p in ipairs({ seller, buyer, poor }) do if p._key == k then return p end end
    end,
}

local function mkShop(id, price)
    local r = {
        id = id, name = "Точка " .. id, type = "shop", estateKind = "business",
        ownerType = "character", ownerKey = "1:char1", ownerName = "Продавец",
        purchasePrice = price or 100000, utilityDebt = 0, estatePenalty = 0,
        estateSince = os.time() - 86400,
        zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 400, y = 400, z = 200 } },
    }
    GRM.Property.Records[id] = r
    return r
end

print("\n=== 1. ПРОДАЖА ГОСУДАРСТВУ ===")
local shop = mkShop("shop1", 100000)
WALLET[seller] = 0
local okState, msgState = ES.SellToState(seller, shop)
ok(okState == true, "объект продаётся государству", msgState)
ok(WALLET[seller] == 60000, "выплачено 60% от цены", WALLET[seller])
ok(ES.IsVacant(shop) == true, "объект стал свободным")
ok(shop.ownerKey == "" and shop.estateSince == nil, "владелец и отсчёт очищены")
ok(select(1, ES.SellToState(buyer, shop)) == false, "чужой объект продать нельзя")

print("\n=== 2. ДОЛГ УДЕРЖИВАЕТСЯ ===")
local debtShop = mkShop("shop2", 100000)
debtShop.utilityDebt = 25000
debtShop.estatePenalty = 5000
WALLET[seller] = 0
local okDebt, msgDebt = ES.SellToState(seller, debtShop)
ok(okDebt == true, "продажа с долгом проходит", msgDebt)
ok(WALLET[seller] == 35000, "выплата уменьшена на долг", WALLET[seller])
ok(tostring(msgDebt):find("удержан долг 25000", 1, true) ~= nil,
   "и продавцу сказано почему", msgDebt)
ok(debtShop.utilityDebt == 0, "долг закрыт продажей, а не сброшен молча")

print("\n=== 3. РЫНОК: ВЫСТАВИТЬ И КУПИТЬ ===")
local market = mkShop("shop3", 80000)
local okSale, msgSale = ES.SetForSale(seller, market, 90000)
ok(okSale == true, "объект выставлен на продажу", msgSale)
ok(istable(market.estateSale) and market.estateSale.price == 90000, "цена записана")
ok(#ES.MarketList() == 1, "объект попал в витрину рынка")

WALLET[seller], WALLET[buyer] = 0, 200000
local okBuy, msgBuy = ES.BuyFromMarket(buyer, market)
ok(okBuy == true, "покупатель выкупает объект", msgBuy)
ok(WALLET[buyer] == 110000, "деньги списаны с покупателя", WALLET[buyer])
ok(WALLET[seller] == 90000, "и получены продавцом", WALLET[seller])
ok(market.ownerKey == "2:char1", "владелец сменился")
ok(market.estateSale == nil, "объект снят с продажи")
ok(market.estateSince ~= nil, "отсчёт дохода начат заново для нового хозяина")
ok(#ES.MarketList() == 0, "витрина опустела")

print("\n=== 3б. ОТКАЗЫ ПРИ ПОКУПКЕ ===")
local m2 = mkShop("shop4", 50000)
ES.SetForSale(seller, m2, 50000)
ok(select(1, ES.BuyFromMarket(poor, m2)) == false, "без денег объект не купить")
ok(select(1, ES.BuyFromMarket(seller, m2)) == false, "свой же объект купить нельзя")
local notSold = mkShop("shop5", 50000)
ok(select(1, ES.BuyFromMarket(buyer, notSold)) == false, "не выставленный объект не купить")

local okOff, msgOff = ES.SetForSale(seller, m2, 0)
ok(okOff == true and m2.estateSale == nil, "объект снимается с продажи", msgOff)

print("\n=== 4. ЛИМИТ ДЕЙСТВУЕТ И НА РЫНКЕ ===")
for i = 1, 3 do
    local r = mkShop("own" .. i, 1000)
    r.ownerKey = "2:char1"
    r.ownerName = "Покупатель"
end
ok(ES.CountOwned("2:char1") == 4, "у покупателя уже несколько бизнесов",
   ES.CountOwned("2:char1"))
local overLimit = mkShop("shop6", 1000)
ES.SetForSale(seller, overLimit, 1000)
local okLimit, whyLimit = ES.BuyFromMarket(buyer, overLimit)
ok(okLimit == false, "сверх лимита купить нельзя", whyLimit)
ok(tostring(whyLimit):find("Лимит", 1, true) ~= nil, "и причина названа", whyLimit)

-- Жильё лимитом не ограничено.
local flat = { id = "flat1", name = "Квартира", type = "apartment",
    ownerType = "character", ownerKey = "1:char1", ownerName = "Продавец",
    purchasePrice = 40000, utilityDebt = 0,
    zone = { mins = { x = 900, y = 0, z = 0 }, maxs = { x = 1000, y = 100, z = 100 } } }
GRM.Property.Records.flat1 = flat
ES.SetForSale(seller, flat, 40000)
WALLET[buyer] = 100000
ok(select(1, ES.BuyFromMarket(buyer, flat)) == true,
   "жильё покупается сверх лимита бизнесов — как решил владелец")

for i = 1, 3 do GRM.Property.Records["own" .. i] = nil end

print("\n=== 5. КАССА НЕ ТЕРЯЕТСЯ ПРИ ПРОДАЖЕ ===")
local cashShop = mkShop("shop7", 60000)
local vend = { _valid = true, _class = "grm_vending_machine", _cash = 700,
    _pos = Vector(100, 100, 10),
    GetPos = function(s) return s._pos end, GetClass = function(s) return s._class end }
WORLD[#WORLD + 1] = vend
GRM.VendingBiz = {
    GetCash = function(e) return e._cash or 0 end,
    SetCash = function(e, n) e._cash = n end,
    GetStats = function() return 0, 0 end,
}
ES.InvalidateScan()
local okCash, msgCash = ES.SellToState(seller, cashShop)
ok(okCash == false, "с непустой кассой объект не продаётся", msgCash)
ok(tostring(msgCash):find("снимите кассу", 1, true) ~= nil, "и сказано, что сделать", msgCash)
vend._cash = 0
ES.InvalidateScan()
ok(select(1, ES.SellToState(seller, cashShop)) == true, "после снятия кассы продаётся")

print("\n=== 6. ПРЕДЛОЖЕНИЕ ИГРОКУ ===")
local offerShop = mkShop("shop8", 30000)
ES.Offers = {}
local okOffer, msgOffer = ES.OfferTo(seller, offerShop, buyer, 30000)
ok(okOffer == true, "предложение отправляется", msgOffer)
ok(ES.Offers["2:char1"] ~= nil, "и ждёт покупателя")
ok(select(1, ES.OfferTo(seller, offerShop, seller, 100)) == false, "себе предложить нельзя")

WALLET[buyer] = 100000
local okAcc, msgAcc = ES.AcceptOffer(buyer)
ok(okAcc == true, "покупатель принимает предложение", msgAcc)
ok(offerShop.ownerKey == "2:char1", "объект перешёл")
ok(ES.Offers["2:char1"] == nil, "предложение израсходовано")
ok(select(1, ES.AcceptOffer(poor)) == false, "кому не предлагали — тому нечего принимать")

-- Просроченное предложение не срабатывает.
local staleShop = mkShop("shop9", 10000)
ES.Offers["3:char1"] = { id = "shop9", price = 10000, from = "1:char1",
    at = os.time() - (ES.OfferLifetime + 60) }
local okStale, msgStale = ES.AcceptOffer(poor)
ok(okStale == false, "просроченное предложение отклоняется", msgStale)

-- Владелец сменился, пока покупатель думал.
local raceShop = mkShop("shop10", 10000)
ES.Offers["3:char1"] = { id = "shop10", price = 10000, from = "1:char1", at = os.time() }
raceShop.ownerKey = "9:char1"
local okRace, msgRace = ES.AcceptOffer(poor)
ok(okRace == false, "объект успели перепродать — сделка отменяется", msgRace)

print("\n=== 7. ОБЪЕКТ БЕЗ ДВЕРЕЙ ПОКУПАЕТСЯ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local prop = body("lua/autorun/sh_grm_property.lua")
ok(prop:find("GRM.Estate.PointInZone(r,p:GetPos())", 1, true) ~= nil,
   "зона из тула считается «рядом» — иначе такой объект нельзя было бы купить")
ok(prop:find("GRM.Estate.CanAcquire(p,r)", 1, true) ~= nil,
   "штатная покупка тоже проверяет лимит бизнесов")

print("\n=== 8. ИНТЕРФЕЙС ===")
local core = body("lua/autorun/sh_grm_estate.lua")
ok(core:find("ПРОДАТЬ ГОСУДАРСТВУ", 1, true) ~= nil, "кнопка продажи государству")
ok(core:find("ВЫСТАВИТЬ НА ПРОДАЖУ", 1, true) ~= nil, "кнопка выставления на рынок")
ok(core:find("СНЯТЬ С ПРОДАЖИ", 1, true) ~= nil, "и снятия с продажи")
ok(core:find('КУПИТЬ ЗА " .. d.forSale', 1, true) ~= nil, "покупатель видит кнопку выкупа")
ok(core:find('concommand.Add("grm_market"', 1, true) ~= nil, "есть витрина рынка")
ok(core:find('low == "/market"', 1, true) ~= nil, "и чат-команда к ней")
ok(core:find("vacant = ES.IsVacant(rec) or istable(rec.estateSale)", 1, true) ~= nil,
   "значок продающегося объекта синеет — видно с улицы")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
