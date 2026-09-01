--[[ Живой прогон лимита одинаковых машин у дилера и «узнаваемости»
     купленного транспорта.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_vehicle_class_limit.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }

function CurTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1

local convars = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) == "1" end
    convars[name] = cv
    return cv
end

-- Минимальный слой дилера: берём ровно те функции, которые отвечают за лимит.
GRM = { Format = function(n) return tostring(n) .. " GRM" end }
local VD = { Active = {}, Garages = {}, MaxActive = 3 }
GRM.VehicleDealer = VD
VD.ClassLimitCvar = CreateConVar("grm_vd_class_limit", "2", 1, "")

function VD.GarageRecords(ply) VD.Garages[ply] = VD.Garages[ply] or {} return VD.Garages[ply] end
function VD.ClassLimit() return math.max(0, VD.ClassLimitCvar:GetInt()) end
function VD.CountClass(ply, class)
    class = tostring(class or "") if class == "" then return 0 end
    local n, counted = 0, {}
    for id, rec in pairs(VD.GarageRecords(ply) or {}) do
        if istable(rec) and tostring(rec.class or "") == class then n = n + 1 counted[id] = true end
    end
    for id, ent in pairs(VD.Active) do
        if not counted[id] and IsValid(ent) and ent.GRMGarageOwner == ply and tostring(ent.VD_Class or "") == class then n = n + 1 end
    end
    return n
end
function VD.CanOwnMore(ply, class)
    local limit = VD.ClassLimit()
    if limit <= 0 then return true end
    local have = VD.CountClass(ply, class)
    if have < limit then return true, have, limit end
    return false, have, limit
end
function VD.TagVehicle(ent, ply, class, kind, record)
    if not IsValid(ent) then return end
    ent.VD_Class = class ent.VD_Owner = ply ent.GRMVehicleKind = kind
    ent.nw = ent.nw or {}
    ent.nw.GRM_VehicleClass = tostring(class or "")
    ent.nw.GRM_VehicleKind = tostring(kind or "personal")
    ent.nw.GRM_VehicleName = tostring(istable(record) and record.name or class or "")
    if IsValid(ply) then ent.nw.GRM_VehicleOwner = ply.name end
    if istable(record) and record.id then ent.nw.GRM_VehicleRecord = tostring(record.id) end
end
function VD.IsDealerVehicle(ent)
    return IsValid(ent) and (ent.GRMGarageID ~= nil or tostring((ent.nw or {}).GRM_VehicleClass or "") ~= "")
end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ply = { _valid = true, name = "Buyer" }
local other = { _valid = true, name = "Other" }
local BOBCAT = "simfphys_gta_sa_bobcat"

local function buy(owner, class, id, service)
    local allowed, have, limit = VD.CanOwnMore(owner, class)
    if not allowed then return false, ("У вас уже %d шт. — предел %d"):format(have, limit) end
    local rec = { id = id, class = class, name = "Bobcat", service = service == true }
    if not service then VD.GarageRecords(owner)[id] = rec end
    local ent = { _valid = true, GRMGarageID = id, GRMGarageOwner = owner }
    VD.TagVehicle(ent, owner, class, service and "government" or "personal", rec)
    VD.Active[id] = ent
    return true, ent
end

print("\n=== 1. ЛИМИТ НА КЛАСС ===")
ok(VD.ClassLimit() == 2, "лимит по умолчанию — 2 машины одного класса")
ok(select(1, buy(ply, BOBCAT, "v1")) == true, "первая машина покупается")
ok(select(1, buy(ply, BOBCAT, "v2")) == true, "вторая машина покупается")
local third, msg = buy(ply, BOBCAT, "v3")
ok(third == false and tostring(msg):find("предел"), "третья того же класса — отказ", msg)
ok(VD.CountClass(ply, BOBCAT) == 2, "счётчик класса показывает 2", VD.CountClass(ply, BOBCAT))

print("\n=== 2. ГРАНИЦЫ ЛИМИТА ===")
ok(select(1, buy(ply, "simfphys_gta_sa_infernus", "v4")) == true, "другой класс лимитом не тронут")
ok(select(1, buy(other, BOBCAT, "v5")) == true, "лимит считается на игрока, а не на сервер")

-- Машина, стоящая в гараже, всё равно занимает слот класса.
VD.Active["v1"] = nil
ok(VD.CountClass(ply, BOBCAT) == 2, "машина в гараже тоже считается")
ok(select(1, buy(ply, BOBCAT, "v6")) == false, "пока одна в гараже — третью не купить")

-- Продали одну: слот освободился.
VD.GarageRecords(ply)["v1"] = nil
ok(VD.CountClass(ply, BOBCAT) == 1, "после продажи остался один")
ok(select(1, buy(ply, BOBCAT, "v7")) == true, "освободившийся слот снова доступен")

print("\n=== 3. СЛУЖЕБНЫЕ И НАСТРОЙКА ===")
VD.Active = {} VD.Garages = {}
ok(select(1, buy(ply, BOBCAT, "s1", true)) == true and select(1, buy(ply, BOBCAT, "s2", true)) == true,
    "служебные без записи гаража тоже считаются по карте")
ok(select(1, buy(ply, BOBCAT, "s3", true)) == false, "третья служебная того же класса не выдаётся")

convars["grm_vd_class_limit"].value = "0"
ok(VD.CanOwnMore(ply, BOBCAT) == true, "лимит 0 = без ограничений")
convars["grm_vd_class_limit"].value = "1"
VD.Active = {} VD.Garages = {}
buy(ply, BOBCAT, "l1")
ok(select(1, buy(ply, BOBCAT, "l2")) == false, "лимит настраивается конваром (1)")
convars["grm_vd_class_limit"].value = "2"

print("\n=== 4. УЗНАВАЕМОСТЬ КУПЛЕННОГО ===")
VD.Active = {} VD.Garages = {}
local okBuy, ent = buy(ply, BOBCAT, "r1")
ok(okBuy and VD.IsDealerVehicle(ent) == true, "машина дилера опознаётся")
ok(ent.nw.GRM_VehicleClass == BOBCAT, "на машине записан класс")
ok(ent.nw.GRM_VehicleKind == "personal", "записан тип владения")
ok(ent.nw.GRM_VehicleOwner == "Buyer", "записан владелец")
ok(ent.nw.GRM_VehicleRecord == "r1", "записан id гаражной записи")
ok(VD.IsDealerVehicle({ _valid = true }) == false, "чужая машина за дилерскую не считается")

print("\n=== 4.1 ВЫКУП ГОСУДАРСТВОМ ===")
VD.StateBuybackCvar = CreateConVar("grm_vd_state_buyback", "93", 1, "")
function VD.StateBuybackRate() return math.Clamp(VD.StateBuybackCvar:GetInt(), 1, 100) end
function VD.StateBuybackPrice(record)
    if not istable(record) then return 0 end
    local price = math.max(0, math.floor(tonumber(record.price) or 0))
    if price <= 0 then return 0 end
    return math.max(1, math.floor(price * VD.StateBuybackRate() / 100))
end

ok(VD.StateBuybackRate() == 93, "ставка выкупа по умолчанию — 93%")
local sample = { price = 1500200 }
local payout = VD.StateBuybackPrice(sample)
ok(payout == 1395186, "выкуп считается от цены покупки", payout)
ok(payout < sample.price, "государство платит МЕНЬШЕ цены покупки")
convars["grm_vd_state_buyback"].value = "100"
ok(VD.StateBuybackPrice(sample) == 1500200, "ставку можно поднять до 100% (цена в цену)")
convars["grm_vd_state_buyback"].value = "150"
ok(VD.StateBuybackRate() == 100, "выше 100% ставка не поднимается — навар из воздуха запрещён")
convars["grm_vd_state_buyback"].value = "0"
ok(VD.StateBuybackRate() == 1, "ниже 1% тоже не опускается")
convars["grm_vd_state_buyback"].value = "93"
ok(VD.StateBuybackPrice({ price = 0 }) == 0, "бесплатная машина не выкупается")
ok(VD.StateBuybackPrice(nil) == 0, "мусор на входе не ломает расчёт")

print("\n=== 5. ЭТО ЖЕ ВКЛЮЧЕНО В САМОМ ДИЛЕРЕ ===")
local function read(path) local f = assert(io.open(path, "rb")) local src = f:read("*a") f:close() return src end
local core = read("lua/autorun/sh_grm_vehicle_dealer.lua")
local cl = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
local function has(src, n) return src:find(n, 1, true) ~= nil end

ok(has(core, 'VD.Version="3.8.0"'), "версия дилера поднята")
ok(has(core, 'CreateConVar("grm_vd_class_limit", "2"'), "лимит задан конваром со значением 2")
ok(has(core, "function VD.CountClass") and has(core, "function VD.CanOwnMore"), "счётчик и проверка лимита в дилере")
ok(has(core, "local allowed,have,limit=VD.CanOwnMore(ply,class)"), "покупка спрашивает лимит")
ok(has(core, "это предел (%d на класс)"), "отказ объясняет, сколько уже есть и какой предел")
ok(has(core, "function VD.TagVehicle") and has(core, "VD.TagVehicle(ent,ply,class,kind,record)"),
    "купленная машина помечается едиными метками")
ok(has(core, 'VD.TagVehicle(ent,ply,r.class,tostring(r.ownershipType or"personal"),r)'),
    "выдача из гаража ставит те же метки")
ok(has(core, "function VD.IsDealerVehicle"), "есть публичная проверка «машина от дилера»")
ok(has(core, "owned=VD.CountClass(ply,e.class),classLimit=VD.ClassLimit()"), "каталог знает про счётчик и лимит")
ok(has(cl, "У вас: %d из %d"), "в карточке видно, сколько таких машин уже есть")
-- 22.08: карточка каталога стала ячейкой общего слоя, блокировка кнопки
-- задаётся полем enabled.
ok(has(cl, 'capped and "ЛИМИТ"') and has(cl, "enabled = not capped"), "кнопка блокируется на пределе")

print("\n=== 6. РЕЖИМ ВЫДАЧИ У ДИЛЕРА ===")
local tool = read("lua/weapons/gmod_tool/stools/grm_transport.lua")
ok(has(core, "VD.DeliveryModes = {") and has(core, 'dealer = "Выдавать у дилера"')
    and has(core, 'garage = "Отправлять в гараж"') and has(core, 'both   = "На выбор игрока"'),
    "три режима выдачи покупок")
ok(has(core, "function VD.DeliveryMode") and has(core, "function VD.ShowRetrieve"),
    "режим и показ кнопки «ВЫДАТЬ» читаются из настроек дилера")
ok(has(core, "delivery=VD.DeliveryMode(ent),showRetrieve=VD.ShowRetrieve(ent)"),
    "настройки сохраняются в записи дилера (переживают рестарт)")
ok(has(core, 'ent.VD_Delivery=VD.DeliveryModes[tostring(r.delivery or"")]'), "и читаются при загрузке карты")
-- Заказ владельца 21.08: «Купить» ≠ «Выдать».
ok(has(core, 'local personal=(kind=="personal")') and has(core, "if not personal then"),
    "покупка личного транспорта ничего не спавнит — спавнится только служебный")
ok(has(core, 'stored=true,dealerID=dealer:GetDealerID()'),
    "купленная машина сразу встаёт на хранение (её нужно выдать отдельно)")
ok(has(core, 'if way=="garage" then') and has(core, "GRM.Garage.IssueRemote(ply,id"),
    "выдача умеет подать машину в гараж, а не только у дилера")
ok(has(core, 'if not VD.ShowRetrieve(dealer)then result(ply,false,"Этот дилер не выдаёт транспорт'),
    "при выключенной кнопке сервер тоже не выдаёт (не только UI)")
ok(has(core, "net.WriteString(VD.DeliveryMode(dealer))net.WriteBool(VD.ShowRetrieve(dealer))"),
    "режим уходит в окно игрока")
-- 22.08: служебная позиция каталога больше не «получить сразу» — это
-- заявка на закупку в автопарк, машина появится отдельной единицей.
ok(has(cl, '"КУПИТЬ · " .. money(v.price or 0)') and has(cl, "ЗАКУПИТЬ В АВТОПАРК"),
    "в каталоге честные кнопки: «КУПИТЬ» для личного, «ЗАКУПИТЬ В АВТОПАРК» для служебного")
ok(has(cl, 'send(dealer, "retrieve", v.id, "dealer", "")') and has(cl, 'send(dealer, "retrieve", v.id, "garage"'),
    "«ВЫДАТЬ» спрашивает, куда подать машину: к дилеру или в гараж")
ok(has(cl, "Выдача покупок:") and has(cl, "Показывать кнопку «ВЫДАТЬ» из гаража"),
    "настройки есть в админке дилера")
ok(has(cl, "delivery = deliveryMode, showRetrieve = showRetrieve"), "админка сохраняет настройки")
ok(has(tool, "delivery = GRM.VehicleDealer.DeliveryMode(trace.Entity)"), "тул отдаёт текущие настройки в админку")

print("\n=== 7. ВЫКУП ГОСУДАРСТВОМ В КОДЕ ДИЛЕРА ===")
ok(has(core, 'CreateConVar("grm_vd_state_buyback", "93"'), "ставка выкупа — конвар (93% по умолчанию)")
ok(has(core, "function VD.StateBuybackPrice"), "цена выкупа считается на сервере")
ok(has(core, 'if r.service then result(ply,false,"Служебный транспорт не выкупается")return end'),
    "служебный транспорт государство не выкупает")
ok(has(core, 'if IsValid(driver)and driver~=ply then result(ply,false,"В транспорте сидит водитель")return end'),
    "машину с чужим водителем не продать")
ok(has(core, "GRM.Economy.StateBudgetAdd,-payout"), "выплата списывается из государственного бюджета")
ok(has(core, '"state.buyback"'), "сделка пишется в аудит")
ok(has(core, "row.buyback=VD.StateBuybackPrice(r);row.buybackRate=VD.StateBuybackRate()"),
    "сумма выкупа уходит в окно")
ok(has(cl, "ПРОДАТЬ ГОСУДАРСТВУ · "), "на кнопке видно, сколько заплатят")
ok(not has(cl, "Продать (возврат 50%)"), "старый возврат 50% убран")
ok(has(cl, "VC.TableRow(parent, {") and has(cl, "ПРОДАТЬ ГОСУДАРСТВУ · "),
   "личная машина в таблице — строка с ценой покупки и суммой выкупа")

print(("\nVEHICLE CLASS LIMIT: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
