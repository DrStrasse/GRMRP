--[[ Живой прогон владения колонками (баг владельца 28.08).

     «C колонками баг, когда их покупаешь или продаёшь они пишут, что
      куплено, а на деле нет. И кнопка после покупки "купить
      колонку/заправку" должна исчезать по сути.»

     ЧТО БЫЛО НЕ ТАК.

     1) У автоматов с едой покупка спрашивала ES.CanOwnStandalone: точка
        внутри бизнес-зоны принадлежит бизнесу, лично её выкупать
        нельзя. У КОЛОНОК этой проверки не было вообще. Игрок платил,
        F.BuyPump писал «Колонка куплена», ставил владельца — а следом
        DL.TransferEquipment (он срабатывает на смену владельца зоны)
        переписывал всё оборудование зоны на владельца бизнеса. Деньги
        ушли, надпись соврала, колонка чужая.

     2) Кнопки «Купить колонку» и «Купить заправку» висели в меню
        ВСЕГДА, даже у своей колонки: повторное нажатие снова говорило
        «куплено».

     3) Продажи не существовало — только «Удалить колонку», то есть
        полная потеря денег.

     Стенд сначала ВОСПРОИЗВОДИТ каждый баг на старой логике, потом
     проверяет новую.

     Запуск: luajit tools/luatest/sim_fuel_ownership.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- ОКРУЖЕНИЕ
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
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

function CurTime() return 100 end
function ErrorNoHalt() end
function ConVarExists() return true end
function CreateConVar() end
function GetConVar() return { GetInt = function() return 3 end } end
function SafeRemoveEntity(e) if istable(e) then e._valid = false end end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
HUD_PRINTTALK, HUD_PRINTCONSOLE = 3, 2
os.time = function() return 1700000000 end

hook = { _t = {} }
function hook.Add(e, i, f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Run(e, ...)
    for _, f in pairs(hook._t[e] or {}) do local r = f(...) if r ~= nil then return r end end
end
timer = { Simple = function(_, f) f() end, Create = function() end, Remove = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "[]" end,
    JSONToTable = function() return {} end, Compress = function(x) return x end }
file = { Exists = function() return false end, Read = function() return "" end,
    Write = function() end, CreateDir = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
game = { GetMap = function() return "rp_city" end }

local WORLD = {}
ents = {
    FindByClass = function(c)
        local o = {}
        for _, e in ipairs(WORLD) do if e._valid ~= false and e:GetClass() == c then o[#o + 1] = e end end
        return o
    end,
    FindInSphere = function() return {} end,
    GetAll = function() return WORLD end,
    Create = function() return { _valid = false } end,
}

GRM = { Perf = {} }

local WALLET = {}
GRM.HasMoney = function(p, n) return (WALLET[p] or 0) >= n end
GRM.TakeMoney = function(p, n) WALLET[p] = (WALLET[p] or 0) - n end
GRM.GiveMoney = function(p, n) WALLET[p] = (WALLET[p] or 0) + n end

local NOTES = {}
GRM.Notify = function(p, msg) NOTES[#NOTES + 1] = tostring(msg) end

GRM.Identity = {
    CharacterKey = function(p) return isstring(p) and p or (p and p._key) or "" end,
}

-----------------------------------------------------------------------
-- КОЛОНКА-ЗАГЛУШКА с настоящей семантикой NetworkVar
-----------------------------------------------------------------------
local function mkPump(pos, owner)
    local p = {
        _valid = true, _pos = pos,
        _owner = owner or "", _station = "", _price = 0, _cash = 0, _kind = "petrol",
        GetClass = function() return "grm_fuel_pump" end,
        GetPos = function(s) return s._pos end,
        GetAngles = function() return Angle(0, 0, 0) end,
        GetOwnerKey = function(s) return s._owner end,
        SetOwnerKey = function(s, v) s._owner = tostring(v or "") end,
        GetStationID = function(s) return s._station end,
        SetStationID = function(s, v) s._station = tostring(v or "") end,
        GetPriceL = function(s) return s._price end,
        SetPriceL = function(s, v) s._price = tonumber(v) or 0 end,
        GetCash = function(s) return s._cash end,
        SetCash = function(s, v) s._cash = math.floor(tonumber(v) or 0) end,
        GetFuelKind = function(s) return s._kind end,
        SetFuelKind = function(s, v) s._kind = v end,
    }
    WORLD[#WORLD + 1] = p
    return p
end

local function mkPly(key, money, admin)
    local ply
    ply = {
        _valid = true, _key = key, _pos = Vector(0, 0, 0),
        GetPos = function(s) return s._pos end,
        IsSuperAdmin = function() return admin == true end,
        SteamID64 = function() return "76561" end,
        Nick = function() return key end,
        GetNWString = function(_, _, d) return d or key end,
        PrintMessage = function() end,
        ConCommand = function() end,
    }
    WALLET[ply] = money or 0
    return ply
end

assert(loadfile("lua/autorun/sh_grm_fuel.lua"))()
local F = GRM.Fuel
assert(F, "GRM.Fuel не загрузился")

-----------------------------------------------------------------------
print("\n=== 1. БАГ ВОСПРОИЗВЕДЁН: «КУПЛЕНО», А НА ДЕЛЕ НЕТ ===")
-----------------------------------------------------------------------
--[[ Ставим колонку ВНУТРИ чужой бизнес-зоны и воспроизводим старую
     логику покупки: она не спрашивала CanOwnStandalone. ]]
local BIZ = {
    id = "biz1", name = "АЗС «Восток»", type = "shop", estateKind = "business",
    ownerType = "character", ownerKey = "999:char1", ownerName = "Чужой",
    zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 600, y = 600, z = 300 } },
}
GRM.Property = { Records = { biz1 = BIZ }, Save = function() end, Reindex = function() end }

-- Минимальный GRM.Estate с настоящей семантикой правила одиночной точки.
GRM.Estate = {
    EquipmentClasses = { grm_fuel_pump = { kind = "fuel" }, grm_vending_machine = { kind = "vending" } },
    ClusterRadius = 700,
    PointInZone = function(rec, pos)
        local a, b = rec.zone.mins, rec.zone.maxs
        return pos.x >= a.x and pos.y >= a.y and pos.z >= a.z
           and pos.x <= b.x and pos.y <= b.y and pos.z <= b.z
    end,
}
GRM.Estate.KindOf = function(rec) return rec.estateKind or "none" end
GRM.Estate.IsBusiness = function(rec) return GRM.Estate.KindOf(rec) == "business" end
GRM.Estate.ZoneAt = function(pos)
    for _, r in pairs(GRM.Property.Records) do
        if GRM.Estate.PointInZone(r, pos) then return r end
    end
end
GRM.Estate.CanOwnStandalone = function(ent)
    local zone = GRM.Estate.ZoneAt(ent:GetPos())
    if zone and GRM.Estate.IsBusiness(zone) then
        return false, "Точка входит в бизнес «" .. tostring(zone.name) .. "»"
    end
    return true
end

local inZone = mkPump(Vector(100, 100, 10))
local buyer = mkPly("111:char1", 500000)
buyer._pos = Vector(120, 100, 10)

--[[ СТАРАЯ логика — ровно то, что было в коде до фикса: никакой
     проверки зоны, сразу списание и присвоение. ]]
local function oldBuyPump(ply, pump)
    if (pump:GetOwnerKey() or "") ~= "" then return false, "занята" end
    GRM.TakeMoney(ply, F.PumpPrice)
    pump:SetOwnerKey(GRM.Identity.CharacterKey(ply))
    return true, "Колонка куплена за " .. F.PumpPrice .. " GRM"
end

local moneyBefore = WALLET[buyer]
local oldOk, oldMsg = oldBuyPump(buyer, inZone)
ok(oldOk == true and tostring(oldMsg):find("куплена", 1, true) ~= nil,
   "БАГ: старая покупка отрапортовала «куплено»", oldMsg)
ok(WALLET[buyer] == moneyBefore - F.PumpPrice,
   "БАГ: и списала деньги", moneyBefore - WALLET[buyer])

--[[ А теперь то, что происходило следом на живом сервере: бизнес-зона
     переписывала всё оборудование внутри себя на своего владельца. ]]
local function transferEquipment(rec, key)
    for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
        if GRM.Estate.PointInZone(rec, e:GetPos()) then e:SetOwnerKey(key) end
    end
end
transferEquipment(BIZ, BIZ.ownerKey)

ok(inZone:GetOwnerKey() ~= GRM.Identity.CharacterKey(buyer),
   "БАГ ВОСПРОИЗВЕДЁН: владельцем стал бизнес, а не покупатель",
   inZone:GetOwnerKey())
ok(WALLET[buyer] == moneyBefore - F.PumpPrice,
   "БАГ: деньги при этом НЕ вернулись — ровно жалоба владельца")

-- Возвращаем колонку в исходное состояние для новой логики.
inZone:SetOwnerKey("")
WALLET[buyer] = moneyBefore

-----------------------------------------------------------------------
print("\n=== 2. ИСПРАВЛЕНО: КОЛОНКУ В БИЗНЕС-ЗОНЕ ЛИЧНО НЕ КУПИТЬ ===")
-----------------------------------------------------------------------
local can, why = F.CanBuyPump(buyer, inZone)
ok(can == false, "проверка запрещает личную покупку внутри бизнеса", tostring(why))
ok(tostring(why):find("бизнес", 1, true) ~= nil, "и объясняет причину", why)

local newOk, newMsg = F.BuyPump(buyer, inZone, false)
ok(newOk == false, "ИСПРАВЛЕНО: покупка отклонена, а не «куплено»", newMsg)
ok(WALLET[buyer] == moneyBefore, "ИСПРАВЛЕНО: деньги не списаны",
   moneyBefore - WALLET[buyer])
ok(inZone:GetOwnerKey() == "", "и владелец не проставлен")

--[[ Проверяем главное свойство: теперь отчёт СОВПАДАЕТ с реальностью.
     Прогоняем перенос оборудования ещё раз — терять нечего. ]]
transferEquipment(BIZ, BIZ.ownerKey)
ok(WALLET[buyer] == moneyBefore,
   "после переноса оборудования игрок по-прежнему при деньгах")
inZone:SetOwnerKey("")

-----------------------------------------------------------------------
print("\n=== 3. СВОБОДНАЯ КОЛОНКА ВНЕ ЗОН ПОКУПАЕТСЯ КАК РАНЬШЕ ===")
-----------------------------------------------------------------------
local lonely = mkPump(Vector(5000, 5000, 10))
buyer._pos = Vector(5020, 5000, 10)

local freeOk, freeMsg = F.BuyPump(buyer, lonely, false)
ok(freeOk == true, "одиночная колонка в чистом поле покупается", freeMsg)
ok(lonely:GetOwnerKey() == "111:char1", "владелец проставлен", lonely:GetOwnerKey())
ok(WALLET[buyer] == moneyBefore - F.PumpPrice, "и деньги списаны ровно один раз",
   moneyBefore - WALLET[buyer])
ok(lonely:GetStationID() ~= "", "станции присвоен идентификатор")
ok((lonely:GetPriceL() or 0) > 0,
   "цена литра выставлена — новый владелец не торгует даром", lonely:GetPriceL())

-----------------------------------------------------------------------
print("\n=== 4. ПОВТОРНАЯ ПОКУПКА НЕ ВРЁТ И НЕ СПИСЫВАЕТ ===")
-----------------------------------------------------------------------
--[[ Раньше повторное нажатие на свою колонку проходило по ветке
     «o == CharKey → free», needBuy получался 0, price 0 — и функция
     всё равно возвращала true с текстом «Колонка куплена за 0 GRM». ]]
local moneyNow = WALLET[buyer]
local againOk, againMsg = F.BuyPump(buyer, lonely, false)
ok(againOk == false, "ИСПРАВЛЕНО: повторная покупка своей колонки отклонена", againMsg)
ok(tostring(againMsg):find("уже ваша", 1, true) ~= nil,
   "и сказано прямо, что она уже ваша", againMsg)
ok(tostring(againMsg):find("куплена", 1, true) == nil,
   "ИСПРАВЛЕНО: слова «куплена» больше нет", againMsg)
ok(WALLET[buyer] == moneyNow, "деньги не тронуты")

-----------------------------------------------------------------------
print("\n=== 5. ПРОДАЖА КОЛОНКИ (её вообще не было) ===")
-----------------------------------------------------------------------
ok(isfunction(F.SellPump), "ИСПРАВЛЕНО: появилась продажа колонки")

local beforeSell = WALLET[buyer]
local sellOk, sellMsg = F.SellPump(buyer, lonely, false)
ok(sellOk == true, "своя колонка продаётся", sellMsg)
ok(lonely:GetOwnerKey() == "", "владелец снят — колонка снова свободна")
local payout = WALLET[buyer] - beforeSell
ok(payout == math.floor(F.PumpPrice * F.SellRate),
   "выплачена половина цены, как при выкупе государством", payout)
ok(payout > 0 and payout < F.PumpPrice, "продажа невыгоднее покупки — спекуляция бессмысленна")

-- Чужую колонку продать нельзя.
local other = mkPump(Vector(5200, 5000, 10), "222:char1")
buyer._pos = Vector(5210, 5000, 10)
local badOk, badMsg = F.SellPump(buyer, other, false)
ok(badOk == false, "чужую колонку продать нельзя", badMsg)
ok(other:GetOwnerKey() == "222:char1", "и её владелец не пострадал")

--[[ Касса не должна пропадать вместе с колонкой: та же защита, что у
     продажи бизнеса государству. ]]
local withCash = mkPump(Vector(5400, 5000, 10), "111:char1")
withCash:SetCash(3000)
buyer._pos = Vector(5410, 5000, 10)
local cashOk, cashMsg = F.SellPump(buyer, withCash, false)
ok(cashOk == false, "колонку с деньгами в кассе продать нельзя", cashMsg)
ok(tostring(cashMsg):find("кассу", 1, true) ~= nil, "и сказано, что сделать", cashMsg)
ok(withCash:GetOwnerKey() == "111:char1", "владелец сохранён — деньги не сгорели")
withCash:SetCash(0)
local nowOk = F.SellPump(buyer, withCash, false)
ok(nowOk == true, "после снятия кассы продажа проходит")

-----------------------------------------------------------------------
print("\n=== 6. КНОПКИ МЕНЮ ЗАВИСЯТ ОТ ВЛАДЕЛЬЦА ===")
-----------------------------------------------------------------------
local src = (function()
    local fh = assert(io.open("lua/autorun/sh_grm_fuel.lua", "rb"))
    local t = fh:read("*a") fh:close() return t
end)()
local menu = src:match("function F%.OpenStation.-\n    end") or ""
ok(menu ~= "", "меню заправки найдено")

--[[ Главная жалоба: «кнопка после покупки должна исчезать». Значит
     создание кнопок обязано быть ВНУТРИ условия, а не безусловным. ]]
--[[ Проверяем именно УСЛОВИЕ над кнопкой, а не просто «где-то выше по
     тексту есть if». Первая версия сравнивала позиции в строке и
     пропустила откат, где условие подменили на `if true then`. ]]
local buyPos = menu:find('SetText("Купить колонку")', 1, true)
ok(buyPos ~= nil, "кнопка покупки в меню есть")

-- Берём ближайший if ПЕРЕД кнопкой покупки: он и решает её судьбу.
local guard
for cond in menu:sub(1, buyPos):gmatch("if%s+([^\n]-)%s+then") do guard = cond end
ok(guard ~= nil, "у кнопки покупки есть управляющее условие", tostring(guard))
ok(guard == 'own == ""',
   "ИСПРАВЛЕНО: «Купить колонку» создаётся ТОЛЬКО когда колонка свободна",
   tostring(guard))
ok(guard ~= "true", "условие не выродилось в «показывать всегда»", tostring(guard))

local allPos = menu:find('SetText("Купить заправку")', 1, true)
ok(allPos and allPos > buyPos, "«Купить заправку» в той же ветке")

--[[ И обратное: у ветки своей колонки условие должно быть про «моё». ]]
local sellPos = menu:find("Продать колонку", 1, true)
local sellGuard
for cond in menu:sub(1, sellPos or 1):gmatch("if%s+([^\n]-)%s+then") do sellGuard = cond end
ok(sellPos ~= nil and tostring(sellGuard):find("mine", 1, true) ~= nil,
   "продажа показывается только владельцу", tostring(sellGuard))

ok(menu:find("mine", 1, true) ~= nil, "у своей колонки своя ветка кнопок")
ok(menu:find("Продать колонку", 1, true) ~= nil, "с продажей колонки")
ok(menu:find("Продать заправку", 1, true) ~= nil, "и продажей всей заправки")

--[[ «Моя» определяется по ключу персонажа, а не по «владелец не пуст»:
     иначе на ЧУЖОЙ колонке появились бы кнопки продажи. ]]
ok(menu:find("CharacterKey", 1, true) ~= nil,
   "принадлежность считается по ключу персонажа")
ok(menu:find('own ~= "" and own == myKey', 1, true) ~= nil,
   "и это именно сравнение с собой, а не просто «занята»")
ok(menu:find("Чужая колонка", 1, true) ~= nil,
   "на чужой колонке честно написано, что купить нельзя")

-- Воспроизводим логику показа кнопок.
local function buttonsFor(own, myKey)
    local mine = own ~= "" and own == myKey
    if own == "" then return "buy" elseif mine then return "sell" else return "none" end
end
ok(buttonsFor("", "111:char1") == "buy", "свободная → кнопки покупки")
ok(buttonsFor("111:char1", "111:char1") == "sell", "своя → кнопки продажи")
ok(buttonsFor("222:char1", "111:char1") == "none", "чужая → никаких кнопок покупки")

-----------------------------------------------------------------------
print("\n=== 7. МЕНЮ ПЕРЕРИСОВЫВАЕТСЯ ПОСЛЕ ДЕЙСТВИЯ ===")
-----------------------------------------------------------------------
--[[ Даже правильные кнопки бесполезны, если окно не обновилось: раньше
     клиент закрывал его по клику и состояние оставалось старым. ]]
ok(src:find('net.WriteString("refresh")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: сервер просит клиента перерисовать окно")
ok(src:find('if op ~= "refresh"', 1, true) ~= nil,
   "и клиент это сообщение обрабатывает")

local recv = src:match('net%.Receive%("GRM_Fuel_Station", function%(%)(.-)end%)') or ""
ok(recv:find("F.OpenStation(ent)", 1, true) ~= nil,
   "перерисовка действительно открывает окно заново")
ok(recv:find("timer.Simple", 1, true) ~= nil,
   "с задержкой: NW-владелец доезжает отдельным пакетом, иначе кнопка не исчезнет")

--[[ Клиент больше не должен закрывать окно сразу по клику покупки:
     иначе перерисовывать будет нечего. ]]
ok(menu:find('send("buy", ent) fr:Close()', 1, true) == nil,
   "ИСПРАВЛЕНО: окно не закрывается мгновенно по клику покупки")
ok(menu:find('send("buy", ent)', 1, true) ~= nil, "но действие по-прежнему отправляется")

-----------------------------------------------------------------------
print("\n=== 8. ПАРИТЕТ С ЖИЛЬЁМ: ЧТО СДЕЛАНО ДЛЯ ЗОН, РАБОТАЕТ И ДЛЯ БИЗНЕСА ===")
-----------------------------------------------------------------------
--[[ Владелец: «все изменения, которые ты делал для зоны жилья, теперь
     надо и для бизнеса». Проверяем, что дверная логика и табличка не
     завязаны на вид объекта. ]]
local est = (function()
    local fh = assert(io.open("lua/autorun/sh_grm_estate.lua", "rb"))
    local t = fh:read("*a") fh:close() return t
end)()
local deal = (function()
    local fh = assert(io.open("lua/autorun/sh_grm_estate_deal.lua", "rb"))
    local t = fh:read("*a") fh:close() return t
end)()

-- Привязка дверей при создании зоны — общая, до выбора вида.
local createFn = est:match("function ES%.CreateZone.-\n    end") or ""
ok(createFn ~= "", "функция создания зоны найдена")
ok(createFn:find("AttachDoors", 1, true) ~= nil,
   "двери привязываются при создании ЛЮБОЙ зоны")
ok(createFn:match('AttachDoors.-kind == "estate"') == nil,
   "привязка НЕ ограничена жильём — бизнес получает двери так же")

-- Табличка и её содержимое знают про оба вида.
ok(est:find('zone.kind == "business" and "/buybusiness" or "/buyhome"', 1, true) ~= nil,
   "на табличке бизнеса своя команда покупки, у жилья своя")
local plaque = est:match("function ES%.PlaqueLines.-\nend") or ""
ok(plaque ~= "", "сборка строк таблички найдена")
ok(plaque:find('kind == "business"', 1, true) ~= nil,
   "табличка различает бизнес и жильё")

-- Продажа через дверь и покупка через дверь — обе по KindOf ~= none.
ok(deal:find('ES.KindOf(r) ~= "none"', 1, true) ~= nil,
   "поиск объекта по двери берёт любой вид, а не только жильё")
local releaseFn = deal:match("function DL%.ReleaseByDoor.-\n    end") or ""
ok(releaseFn ~= "", "освобождение по двери найдено")
ok(releaseFn:find('"estate"', 1, true) == nil,
   "освобождение двери не ограничено жильём — бизнес продаётся так же")

-- Якорь таблички считается для всех записей снимка.
local snap = est:match("function ES%.BuildSnapshot.-\n    end") or ""
ok(snap:find("ES.MarkerAnchor(rec, doorIndex)", 1, true) ~= nil,
   "точка значка считается для каждого объекта снимка")
ok(snap:match('MarkerAnchor.-kind == "estate"') == nil,
   "и не только для жилья")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
