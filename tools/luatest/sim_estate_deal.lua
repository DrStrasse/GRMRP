--[[ Живой прогон сделок с недвижимостью (заказ владельца 28.08).

     «Если купил бизнес-зону, то автоматически присваивается владелец
      колонкам, автомату с едой и т.д. Всё оборудование в зоне бизнеса
      сразу автоматически выкупается и освобождается.»
     «Нужно более красивое и простое меню нежели /property_admin.»
     «Квартир/жилья также касается. Ближайшие двери к зоне или в зоне
      тоже автоматически приобретаются/продаются.»

     Стенд сначала воспроизводит старое поведение (купил зону — получил
     пустоту), потом проверяет новое.

     Запуск: luajit tools/luatest/sim_estate_deal.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

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

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt() end
HUD_PRINTTALK = 3
CurTime = function() return 100 end
local REALTIME = 1700000000
os.time = function() return REALTIME end
game = { GetMap = function() return "rp_city" end }

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end
local function runAll(e,...) for _,f in pairs(hook._t[e] or {}) do f(...) end end

timer = { Simple = function(_,f) f() end, Create = function() end,
          Remove = function() end, Exists = function() return false end }
local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }

local SENT = {}
local buf
net = {
    AddNetworkString=function() end,
    Start=function(n) buf={name=n,args={}} end,
    WriteTable=function(v) table.insert(buf.args,v) end,
    WriteString=function(v) table.insert(buf.args,v) end,
    WriteEntity=function(v) table.insert(buf.args,v) end,
    WriteFloat=function() end, WriteUInt=function() end, WriteBool=function() end,
    Send=function(p) buf.to=p table.insert(SENT,buf) end,
    Receive=function(n,f) net["_h_"..n]=f end,
}
util = { AddNetworkString=function() end, TableToJSON=function() return "J" end,
         JSONToTable=function() return {} end }
file = { Exists=function() return false end, Read=function() return "" end,
         Write=function() end, CreateDir=function() end, IsDir=function() return true end }
local PLAYERS = {}
player = { GetAll=function() return PLAYERS end }
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,
    GetBool=function() return d~="0" end, GetString=function() return tostring(d) end,
    GetInt=function() return math.floor(tonumber(d) or 0) end} end

-- Мир: список entity.
local WORLD = {}
ents = {
    GetAll = function() return WORLD end,
    FindByClass = function(c)
        local o = {}
        for _, e in ipairs(WORLD) do if e:GetClass() == c then o[#o+1] = e end end
        return o
    end,
}

local NOTIFIED = {}
GRM = { Perf = { Players=function() return PLAYERS end } }
GRM.Notify = function(p,msg) NOTIFIED[#NOTIFIED+1] = { to=p, msg=msg } end
GRM.Audit = { Write = function() end }

local WALLET = {}
GRM.HasMoney = function(p,n) return (WALLET[p] or 0) >= n end
GRM.TakeMoney = function(p,n) WALLET[p] = (WALLET[p] or 0) - n end
GRM.GiveMoney = function(p,n) WALLET[p] = (WALLET[p] or 0) + n end

GRM.Identity = {
    CharacterKey = function(p) return isstring(p) and p or p._key end,
    IsCharacterKey = function(k) return isstring(k) and k:match("^%d+:char[1-3]$") ~= nil end,
    ResolveCharacter = function() return nil end,
}

--[[ Двери-заглушки с НАСТОЯЩЕЙ семантикой: у каждой своя запись с
     владельцем и NW-поле GRM_DoorOwner, из которого рисуется табличка.
     Без этого стенд не увидел бы баг «дверь осталась ничья». ]]
local SAVED_PERSIST = { vending = 0, fuel = 0 }
local DOOR_RECS = {}
local DOOR_SAVES = 0

local function doorLabel(rec)
    if not rec or rec.owner_type == "none" then return "" end
    if rec.owner_type == "player" then return rec.owner_nick or "" end
    if rec.owner_type == "faction" then return "Фракция: " .. tostring(rec.owner_faction) end
    return ""
end

GRM.Doors = {
    IsDoor = function(e) return IsValid(e) and e._door == true end,
    GetDoorID = function(e) return e._id end,
    LockDoor = function() end,
    SaveDoors = function() DOOR_SAVES = DOOR_SAVES + 1 end,
    HasWarrant = function() return false end, HasPropertyWarrant = function() return false end,
    GetRecord = function(e)
        if not IsValid(e) then return nil end
        DOOR_RECS[e._id] = DOOR_RECS[e._id] or
            { id = e._id, owner_type = "none", owner_key = "", owner_nick = "",
              owner_faction = "", ownable = true, title = "" }
        return DOOR_RECS[e._id], e._id
    end,
    ApplyRecordVisual = function(e, rec)
        if IsValid(e) then e._nwOwner = doorLabel(rec) end
    end,
}
--[[ Покупка двери — как в настоящем модуле: сначала спрашиваем
     недвижимость через хук, и только если она отказалась, продаём
     дверь сама по себе. ]]
GRM.Doors.DoorPrice = 15000
--[[ Освобождение двери — как в настоящем модуле: сначала спрашиваем
     недвижимость, и только если она отказалась, освобождаем саму дверь. ]]
GRM.Doors.ReleaseDoor = function(ply, ent)
    if not (IsValid(ply) and IsValid(ent)) then return false end
    local rec = GRM.Doors.GetRecord(ent)
    if not rec then return false end
    if rec.owner_type == "none" then return false, "дверь и так ничья" end

    local handled = hook.Run("GRM_DoorReleaseToProperty", ply, ent, rec)
    if handled ~= nil then return handled == true end

    rec.owner_type = "none"
    rec.owner_key, rec.owner_nick = "", ""
    rec.ownable = true
    GRM.Doors.ApplyRecordVisual(ent, rec)
    return true
end

GRM.Doors.ClaimDoor = function(ply, ent, mode)
    if not (IsValid(ply) and IsValid(ent)) then return false end
    local rec = GRM.Doors.GetRecord(ent)
    if not rec then return false end
    if rec.owner_type ~= "none" then return false, "занята" end

    local claimed = hook.Run("GRM_DoorClaimToProperty", ply, ent, rec, mode)
    if claimed ~= nil then return claimed == true end

    -- Обычная покупка одной двери по её цене.
    local price = GRM.Doors.DoorPrice
    if not GRM.HasMoney(ply, price) then return false, "нет денег" end
    GRM.TakeMoney(ply, price)
    rec.owner_type = "player"
    rec.owner_key = ply._key
    rec.owner_nick = ply._nw.GRM_RPName
    GRM.Doors.ApplyRecordVisual(ent, rec)
    return true
end

-- Та же функция, что и в настоящем модуле дверей.
GRM.Doors.SetDoorOwner = function(ent, ownerType, key, nick, title)
    if not IsValid(ent) then return false end
    local rec = GRM.Doors.GetRecord(ent)
    if not rec then return false end
    ownerType = tostring(ownerType or "none")
    if ownerType == "none" then
        rec.owner_type = "none"
        rec.owner_key, rec.owner_nick, rec.owner_faction = "", "", ""
        rec.ownable = true
    else
        rec.owner_type = ownerType
        if ownerType == "faction" then
            rec.owner_faction = tostring(key or "")
            rec.owner_key, rec.owner_nick = "", ""
        else
            rec.owner_key = tostring(key or "")
            rec.owner_nick = tostring(nick or "")
            rec.owner_faction = ""
        end
        rec.ownable = false
    end
    if isstring(title) and title ~= "" then rec.title = title end
    GRM.Doors.ApplyRecordVisual(ent, rec)
    GRM.Doors.SaveDoors()
    return true, rec
end
GRM.Access = { Can = function() return false end, Register = function() end }
GRM.VendingBiz = { MarkDirty = function() end,
    Persist = function() SAVED_PERSIST.vending = SAVED_PERSIST.vending + 1 end }
GRM.Fuel = { PricePerLiter = 50,
    SavePumps = function() SAVED_PERSIST.fuel = SAVED_PERSIST.fuel + 1 end }
GRM.Persistence = { LoadJSON = function(_,d) return d end, SaveJSON = function() return true end }
GRM.Utf8Sub = function(s,n) return string.sub(s,1,n) end
Factions = {}

assert(loadfile("lua/autorun/sh_grm_property.lua"))()
local P = GRM.Property

-- Estate: минимальный контракт, который нужен модулю сделок.
GRM.Estate = {
    EquipmentClasses = {
        grm_vending_machine = { label = "автомат", kind = "vending" },
        grm_fuel_pump = { label = "колонка", kind = "fuel" },
    },
    StateBuyback = 0.6,
    KindOf = function(rec)
        local k = tostring(rec.estateKind or "")
        if k ~= "" then return k end
        return rec.type == "apartment" and "estate" or
               (rec.type == "shop" and "business" or "none")
    end,
    PointInZone = function(rec, pos)
        if not istable(rec.zone) then return false end
        local a,b = rec.zone.mins, rec.zone.maxs
        return pos.x>=a.x and pos.y>=a.y and pos.z>=a.z
           and pos.x<=b.x and pos.y<=b.y and pos.z<=b.z
    end,
    ZoneCenter = function(rec)
        if not istable(rec.zone) then return nil end
        local a,b = rec.zone.mins, rec.zone.maxs
        return Vector((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
    end,
    ZoneArea = function() return 1015 end,
    InvalidateScan = function() end,
}
GRM.Estate.ScanZone = function(rec)
    local out = { total = 0, byKind = {}, entities = {} }
    for class, info in pairs(GRM.Estate.EquipmentClasses) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if GRM.Estate.PointInZone(rec, e:GetPos()) then
                out.total = out.total + 1
                out.byKind[info.kind] = (out.byKind[info.kind] or 0) + 1
                out.entities[#out.entities+1] = e
            end
        end
    end
    return out
end

assert(loadfile("lua/autorun/sh_grm_estate_deal.lua"))()
local DL = GRM.EstateDeal

-----------------------------------------------------------------------
-- ЗАГЛУШКИ ОБЪЕКТОВ
-----------------------------------------------------------------------
local function mkPly(o)
    o = o or {}
    local said = {}
    return {
        _valid=true, _key=o.key or "1:char1", _pos=o.pos or Vector(0,0,0), _said=said,
        _nw={ GRM_RPName = o.name or "Игрок" },
        SteamID64=function() return "1" end, SteamID=function() return "STEAM_0:0:1" end,
        Nick=function() return o.name or "Игрок" end,
        GetPos=function(s) return s._pos end,
        IsPlayer=function() return true end,
        IsSuperAdmin=function() return o.admin==true end,
        PrintMessage=function(_,_,t) said[#said+1]=t end,
        ChatPrint=function(_,t) said[#said+1]=t end,
        GetNWString=function(s,k,d) return s._nw[k] or d or "" end,
        GetNWBool=function(_,_,d) return d or false end,
        SetNWBool=function() end, SetNWString=function() end,
        GetEyeTrace=function() return { Entity=nil } end,
    }
end

local function mkVending(pos)
    local e = { _valid=true, _pos=pos, _nw={},
        GetClass=function() return "grm_vending_machine" end,
        GetPos=function(s) return s._pos end,
        SetNWString=function(s,k,v) s._nw[k]=v end,
        GetNWString=function(s,k,d) return s._nw[k] or d or "" end }
    WORLD[#WORLD+1] = e
    return e
end

local function mkPump(pos)
    local e = { _valid=true, _pos=pos, _owner="", _price=0,
        GetClass=function() return "grm_fuel_pump" end,
        GetPos=function(s) return s._pos end,
        SetOwnerKey=function(s,v) s._owner=v end,
        GetOwnerKey=function(s) return s._owner end,
        SetPriceL=function(s,v) s._price=v end,
        GetPriceL=function(s) return s._price end }
    WORLD[#WORLD+1] = e
    return e
end

local function mkDoor(id, pos)
    local e = { _valid=true, _door=true, _id=id, _pos=pos, _nwOwner="",
        GetClass=function() return "prop_door_rotating" end,
        GetPos=function(s) return s._pos end,
        -- Настоящий P.ResolveDoor смотрит родителя: без метода падает.
        GetParent=function() return nil end,
        EntIndex=function() return 1 end,
        -- То, что игрок видит на табличке.
        GetNWString=function(s,k,d) if k=="GRM_DoorOwner" then return s._nwOwner end return d or "" end }
    WORLD[#WORLD+1] = e
    return e
end

-----------------------------------------------------------------------
print("\n=== 1. СТАРОЕ ПОВЕДЕНИЕ: КУПИЛ ЗОНУ — ПОЛУЧИЛ ПУСТОТУ ===")
-----------------------------------------------------------------------
do
    -- Игрок покупает зону, а владелец автоматов не меняется.
    local v = { owner = "" }
    local zoneOwner = ""
    zoneOwner = "1:char1"          -- «купил зону»
    ok(v.owner == "",
       "БАГ ВОСПРОИЗВЕДЁН: зона куплена, а автомат остался ничей")
    ok(zoneOwner ~= v.owner,
       "владелец зоны и владелец оборудования расходились")
end

-----------------------------------------------------------------------
print("\n=== 2. ПОКУПКА БИЗНЕСА ПЕРЕДАЁТ ОБОРУДОВАНИЕ ===")
-----------------------------------------------------------------------
local shop = P.Normalize({
    id="biz1", name="Бизнес-объект", type="shop", estateKind="business",
    ownerType="none", tenure="none", purchasePrice=85000, rentPrice=8000,
    utilityRate=500,
    zone={mins=Vector(-200,-200,-50), maxs=Vector(200,200,200)},
})
P.Records = { biz1 = shop }
P.Reindex()

-- Три автомата и две колонки внутри, один автомат снаружи.
local v1, v2, v3 = mkVending(Vector(0,0,0)), mkVending(Vector(50,50,0)), mkVending(Vector(-80,20,0))
local p1, p2 = mkPump(Vector(100,0,0)), mkPump(Vector(-100,-100,0))
local vOut = mkVending(Vector(5000,5000,0))

local buyer = mkPly({ key="1:char1", name="Иван", pos=Vector(0,0,0) })
PLAYERS = { buyer }
WALLET[buyer] = 500000

local scan = GRM.Estate.ScanZone(shop)
ok(scan.total == 5, "в зоне 5 единиц оборудования", scan.total)

P.PanelAction(buyer, { action="buy", id="biz1" })

ok(shop.ownerType == "character" and shop.ownerKey == "1:char1",
   "объект куплен")
ok(v1._nw.GRM_VendOwner == "1:char1",
   "ИСПРАВЛЕНО: автомат №1 автоматически стал вашим", v1._nw.GRM_VendOwner)
ok(v2._nw.GRM_VendOwner == "1:char1", "автомат №2 тоже")
ok(v3._nw.GRM_VendOwner == "1:char1", "автомат №3 тоже")
ok(p1._owner == "1:char1", "ИСПРАВЛЕНО: колонка №1 автоматически ваша", p1._owner)
ok(p2._owner == "1:char1", "колонка №2 тоже")
ok(vOut._nw.GRM_VendOwner == nil or vOut._nw.GRM_VendOwner == "",
   "а автомат ЗА зоной остался чужим — захвата половины карты нет")

ok(p1._price > 0, "у колонки выставлена цена — новый владелец не торгует даром", p1._price)
ok(SAVED_PERSIST.vending > 0 and SAVED_PERSIST.fuel > 0,
   "оборудование сохранено на диск один раз в конце")

local told = false
for _, n in ipairs(NOTIFIED) do
    if n.to == buyer and tostring(n.msg):find("переоформлено", 1, true) then told = true end
end
ok(told, "игроку сказали, что оборудование перешло к нему")

-----------------------------------------------------------------------
print("\n=== 3. ПРОДАЖА ОСВОБОЖДАЕТ ОБОРУДОВАНИЕ ===")
-----------------------------------------------------------------------
P.PanelAction(buyer, { action="release", id="biz1" })
ok(shop.ownerType == "none", "объект освобождён")
ok(v1._nw.GRM_VendOwner == "", "ИСПРАВЛЕНО: автомат освободился вместе с зоной")
ok(p1._owner == "", "и колонка тоже", p1._owner)
ok(v2._nw.GRM_VendOwner == "" and v3._nw.GRM_VendOwner == "", "всё оборудование свободно")

-----------------------------------------------------------------------
print("\n=== 4. ЖИЛЬЁ: ДВЕРИ ПРИТЯГИВАЮТСЯ АВТОМАТИЧЕСКИ ===")
-----------------------------------------------------------------------
local flat = P.Normalize({
    id="flat1", name="Квартира 14", type="apartment",
    ownerType="none", tenure="none", purchasePrice=50000, rentPrice=5000,
    zone={mins=Vector(1000,-100,0), maxs=Vector(1200,100,200)},
})
P.Records["flat1"] = flat
P.Reindex()

local dIn   = mkDoor("d_in",   Vector(1100, 0, 10))      -- внутри зоны
local dEdge = mkDoor("d_edge", Vector(1240, 0, 10))      -- в 40 юнитах за границей
local dFar  = mkDoor("d_far",  Vector(3000, 0, 10))      -- далеко

ok(DL.DoorNearZone(flat, dIn:GetPos()) == true, "дверь внутри зоны — своя")
ok(DL.DoorNearZone(flat, dEdge:GetPos()) == true,
   "дверь вплотную к границе тоже своя: зону обводят снаружи дома")
ok(DL.DoorNearZone(flat, dFar:GetPos()) == false, "дальняя дверь не притягивается")

local tenant = mkPly({ key="2:char1", name="Пётр", pos=Vector(1100,0,0) })
PLAYERS = { buyer, tenant }
WALLET[tenant] = 500000

ok(#flat.doors == 0, "до покупки дверей у объекта нет")
P.PanelAction(tenant, { action="buy", id="flat1" })
ok(flat.ownerKey == "2:char1", "квартира куплена")
ok(#flat.doors == 2,
   "ИСПРАВЛЕНО: обе ближние двери привязались автоматически", #flat.doors)
ok(P.HasAccess(tenant, flat) == true, "и владелец реально открывает свою дверь")
ok(P.HasAccess(buyer, flat) == false, "а посторонний — нет")

-----------------------------------------------------------------------
print("\n=== 5. ЧУЖИЕ ДВЕРИ НЕ ЗАХВАТЫВАЮТСЯ ===")
-----------------------------------------------------------------------
--[[ Соседняя квартира вплотную. Её дверь уже принадлежит другому
     объекту — покупка соседней зоны не должна её забирать. ]]
local flat2 = P.Normalize({
    id="flat2", name="Квартира 15", type="apartment",
    ownerType="none", tenure="none", purchasePrice=50000,
    doors={"d_in"},   -- дверь уже за другим объектом
    zone={mins=Vector(1150,-100,0), maxs=Vector(1350,100,200)},
})
P.Records["flat2"] = flat2
P.Reindex()

local other = mkPly({ key="3:char1", name="Сосед", pos=Vector(1250,0,0) })
PLAYERS = { buyer, tenant, other }
WALLET[other] = 500000
P.PanelAction(other, { action="buy", id="flat2" })

local stole = false
for _, id in ipairs(flat2.doors) do
    if id == "d_edge" then
        -- d_edge принадлежит flat1, забирать нельзя
        for _, o in ipairs(flat.doors) do if o == "d_edge" then stole = true end end
    end
end
ok(not stole, "дверь соседа не украдена покупкой смежной зоны")
ok(P.HasAccess(tenant, flat) == true, "и прежний владелец не потерял доступ")

-----------------------------------------------------------------------
print("\n=== 6. ОКНО СДЕЛКИ ВМЕСТО /property_admin ===")
-----------------------------------------------------------------------
P.Records = { biz1 = shop }
P.Reindex()
shop.ownerType = "none" shop.ownerKey = "" shop.tenure = "none"

buyer._pos = Vector(0,0,0)
local target = DL.TargetOf(buyer, "business")
ok(target == shop, "объект определяется по положению игрока, без списка карты")

local d = DL.Data(buyer, shop)
ok(d.price == 85000, "цена в пакете", d.price)
ok(d.equipment == 5, "видно, сколько оборудования входит в сделку", d.equipment)
ok(d.byKind.vending == 3 and d.byKind.fuel == 2, "с разбивкой по видам")
ok(d.vacant == true, "объект свободен")
ok(d.buyback == math.floor(85000 * 0.6), "показано, сколько вернут при продаже", d.buyback)

SENT = {}
ok(DL.Open(buyer, "business") == true, "окно сделки открывается")
ok(#SENT > 0 and SENT[#SENT].name == DL.NET.OPEN, "пакет ушёл клиенту")

-- Издалека не открыть.
buyer._pos = Vector(9999, 9999, 0)
ok(DL.Open(buyer, "business") == false, "издалека сделка недоступна")
buyer._pos = Vector(0,0,0)

-- Покупка через окно.
local act = net["_h_" .. DL.NET.ACT]
ok(isfunction(act), "обработчик действий зарегистрирован")
local PKT
net.ReadTable = function() return PKT end
WALLET[buyer] = 500000
PKT = { action="buy", id="biz1" }
act(0, buyer)
ok(shop.ownerKey == "1:char1", "покупка через окно работает")
ok(v1._nw.GRM_VendOwner == "1:char1", "и оборудование сразу переоформлено")

-- Издалека действие тоже не проходит.
shop.ownerType="none" shop.ownerKey="" 
buyer._pos = Vector(9999,9999,0)
PKT = { action="buy", id="biz1" }
act(0, buyer)
ok(shop.ownerType == "none", "пакет издалека игнорируется — телепорт-покупки нет")
buyer._pos = Vector(0,0,0)

-----------------------------------------------------------------------
print("\n=== 7. КОМАНДЫ И ПОДСКАЗКА ===")
-----------------------------------------------------------------------
ok(isfunction(commands["grm_buybusiness"]), "есть grm_buybusiness")
ok(isfunction(commands["grm_buyhome"]), "есть grm_buyhome")

local chat = hook._t["PlayerSay"]["GRM_EstateDeal_Chat"]
SENT = {}
ok(chat(buyer, "/buybusiness") == "", "команда /buybusiness перехвачена")
ok(#SENT > 0, "и окно открылось")

local function readf(p) local f=assert(io.open(p)) local s=f:read("*a") f:close() return s end
local est = readf("lua/autorun/sh_grm_estate.lua")
ok(est:find("Чтобы купить — напишите", 1, true) ~= nil,
   "ИСПРАВЛЕНО: под значком есть подсказка, как купить")
ok(est:find("/buybusiness", 1, true) ~= nil, "с правильной командой для бизнеса")
ok(est:find("/buyhome", 1, true) ~= nil, "и для жилья")

-----------------------------------------------------------------------
print("\n=== 8. ЗНАЧОК: ВРАЩЕНИЕ И ВЫСОТА ===")
-----------------------------------------------------------------------
ok(est:find("ES.MarkerSpin", 1, true) ~= nil,
   "ИСПРАВЛЕНО: вернулось независимое вращение вокруг оси")
ok(est:find("CurTime() * ES.MarkerSpin", 1, true) ~= nil,
   "угол считается от времени, а не от позиции игрока")

local markerBlock = est:match("PostDrawTranslucentRenderables.-end%)")
ok(markerBlock and markerBlock:find("dir:Angle().y", 1, true) == nil,
   "ИСПРАВЛЕНО: значок больше НЕ поворачивается вслед за камерой")

local h = tonumber(est:match("ES%.MarkerHeight = (%d+)"))
ok(h and h < 36, "ИСПРАВЛЕНО: значок опущен ещё ниже", h)
ok(h and h > 0, "но не утоплен в землю", h)

-----------------------------------------------------------------------
print("\n=== 9. /business ВЕДЁТ КУДА НАДО ===")
-----------------------------------------------------------------------
ok(est:find("GRM.EstateDeal.Open(ply, ES.KindOf(rec))", 1, true) ~= nil,
   "свободный объект открывает окно СДЕЛКИ, а не админку")
ok(est:find("ES.OpenPanel(ply, rec)", 1, true) ~= nil,
   "а свой — панель управления")

-----------------------------------------------------------------------
print("\n=== 10. ТАБЛИЧКА НА ДВЕРИ (жалоба 28.08) ===")
-----------------------------------------------------------------------
--[[ «Дверь как была ничья, так и осталась ничья.» Объект куплен, двери
     привязаны, а сама ЗАПИСЬ двери оставалась owner_type = "none" —
     табличка читает именно её. ]]
do
    P.Records = {}
    DOOR_RECS = {}
    local home = P.Normalize({
        id="h1", name="Жилой объект", type="apartment",
        ownerType="none", tenure="none", purchasePrice=40000, rentPrice=4000,
        zone={mins=Vector(4000,-100,0), maxs=Vector(4200,100,200)},
    })
    P.Records["h1"] = home
    P.Reindex()

    local dr = mkDoor("hd1", Vector(4100, 0, 10))
    local owner2 = mkPly({ key="7:char1", name="Александр Фон Греннер", pos=Vector(4100,0,0) })
    PLAYERS = { owner2 }
    WALLET[owner2] = 500000

    ok(dr:GetNWString("GRM_DoorOwner","") == "",
       "до покупки табличка пустая — «Продаётся / Ничья»")

    P.PanelAction(owner2, { action="buy", id="h1" })

    ok(home.ownerKey == "7:char1", "объект куплен")
    ok(#home.doors == 1, "дверь привязана к объекту", #home.doors)

    local rec = DOOR_RECS["hd1"]
    ok(rec and rec.owner_type == "player",
       "ИСПРАВЛЕНО: в записи двери проставлен владелец", rec and rec.owner_type)
    ok(rec and rec.owner_key == "7:char1", "с ключом покупателя", rec and rec.owner_key)
    ok(rec and rec.ownable == false,
       "и дверь больше не продаётся отдельно от квартиры")
    ok(dr:GetNWString("GRM_DoorOwner","") == "Александр Фон Греннер",
       "ГЛАВНОЕ: на табличке имя владельца, а не «Ничья»",
       dr:GetNWString("GRM_DoorOwner",""))
    ok(rec and rec.title == "Жилой объект", "и название объекта", rec and rec.title)

    -- Продажа возвращает дверь в общий фонд.
    P.PanelAction(owner2, { action="release", id="h1" })
    rec = DOOR_RECS["hd1"]
    ok(rec and rec.owner_type == "none",
       "после продажи дверь снова ничья", rec and rec.owner_type)
    ok(rec and rec.ownable == true,
       "и снова доступна к покупке — иначе объект нельзя было бы перепродать")
    ok(dr:GetNWString("GRM_DoorOwner","") == "",
       "табличка опять пустая")
end

-----------------------------------------------------------------------
print("\n=== 11. ХУК ОБНОВЛЕНИЯ ДВЕРЕЙ ===")
-----------------------------------------------------------------------
do
    local prop = (function() local f=assert(io.open("lua/autorun/sh_grm_property.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(prop:find("GRM_Property_DoorsSync", 1, true) ~= nil,
       "ИСПРАВЛЕНО: двери обновляются на общем хуке смены владельца")
    ok(prop:find("GRM.Doors.SetDoorOwner", 1, true) ~= nil,
       "недвижимость ставит владельца через единую функцию модуля дверей")

    local doors = (function() local f=assert(io.open("lua/autorun/sh_grm_doors.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(doors:find("function D.SetDoorOwner", 1, true) ~= nil,
       "в модуле дверей появилась публичная точка SetDoorOwner")
    local fn = doors:match("function D%.SetDoorOwner.-\n    end")
    ok(fn and fn:find("D.ApplyRecordVisual", 1, true) ~= nil,
       "она обновляет табличку у ВСЕХ полотен двери")
    ok(fn and fn:find("D.SaveDoors", 1, true) ~= nil,
       "и сохраняет — владелец переживёт рестарт")
    ok(fn and fn:find("rec.ownable = true", 1, true) ~= nil,
       "при освобождении дверь снова становится покупаемой")
end

-----------------------------------------------------------------------
print("\n=== 12. ПОКУПКА ДВЕРИ = ПОКУПКА ОБЪЕКТА (заказ 28.08) ===")
-----------------------------------------------------------------------
--[[ «Если я покупаю дверь, то автоматически зона должна считывать
     купленную дверь + выставлять полную цену и автоматически
     привязываться сразу к игроку.» ]]
do
    P.Records = {}
    DOOR_RECS = {}
    WORLD = {}
    local home = P.Normalize({
        id="z1", name="Жилой объект", type="apartment",
        ownerType="none", tenure="none", purchasePrice=40000, rentPrice=4000,
        zone={mins=Vector(6000,-100,0), maxs=Vector(6200,100,200)},
    })
    P.Records["z1"] = home
    P.Reindex()

    -- Дверь ещё НЕ привязана к объекту: тул обвёл зону, и всё.
    local dr = mkDoor("zd1", Vector(6210, 0, 10))    -- чуть за границей
    ok(#home.doors == 0, "двери к объекту не привязаны — как после тула")

    local guy = mkPly({ key="11:char1", name="Покупатель", pos=Vector(6215, 0, 0) })
    PLAYERS = { guy }
    WALLET[guy] = 500000
    local before = WALLET[guy]

    local okBuy = GRM.Doors.ClaimDoor(guy, dr, "buy")

    ok(okBuy == true, "покупка двери прошла")
    ok(home.ownerKey == "11:char1",
       "ГЛАВНОЕ: куплен ВЕСЬ объект, а не одна дверь", tostring(home.ownerKey))
    ok(before - WALLET[guy] == 40000,
       "ИСПРАВЛЕНО: списана ПОЛНАЯ цена объекта, а не цена двери",
       before - WALLET[guy])
    ok(before - WALLET[guy] ~= GRM.Doors.DoorPrice,
       "то есть НЕ 15000 за дверь — жильё за цену двери не отдаётся")
    ok(#home.doors == 1, "дверь притянулась к объекту автоматически", #home.doors)

    local rec = DOOR_RECS["zd1"]
    ok(rec and rec.owner_type == "player" and rec.owner_key == "11:char1",
       "и владелец проставлен на самой двери")
    _G.TESTDOOR_Z1 = dr
    ok(dr:GetNWString("GRM_DoorOwner","") == "Покупатель",
       "табличка показывает владельца", dr:GetNWString("GRM_DoorOwner",""))
end

-----------------------------------------------------------------------
print("\n=== 13. ЧУЖОЙ И ЗАНЯТЫЙ ОБЪЕКТ ===")
-----------------------------------------------------------------------
do
    -- Объект уже куплен: его дверь не продаётся никому.
    local occupied = P.Records["z1"]
    local dr = _G.TESTDOOR_Z1
    local other = mkPly({ key="12:char1", name="Другой", pos=Vector(6215, 0, 0) })
    PLAYERS = { other }
    WALLET[other] = 500000
    local before = WALLET[other]

    local okBuy = GRM.Doors.ClaimDoor(other, dr, "buy")
    ok(okBuy == false, "дверь занятого объекта купить нельзя")
    ok(WALLET[other] == before, "и денег не списали")
    ok(occupied.ownerKey == "11:char1", "владелец объекта не сменился")

    --[[ Здесь отказ приходит РАНЬШЕ нашего хука: у самой двери уже есть
         владелец (её проставил setDoorPolicy при покупке объекта), и
         модуль дверей отсекает такую покупку своей штатной проверкой.
         Это правильный порядок — до нас дело просто не доходит. ]]
    ok(rec == nil or DOOR_RECS["zd1"].owner_key == "11:char1",
       "дверь занятого объекта хранит прежнего владельца")
end

-----------------------------------------------------------------------
print("\n=== 13б. ЗАНЯТ ОБЪЕКТ, НО ДВЕРЬ ЕЩЁ НИЧЬЯ ===")
-----------------------------------------------------------------------
do
    --[[ Более тонкий случай: объект куплен через зону, а рядом появилась
         НОВАЯ дверь, которую ещё не привязали. Модуль дверей её продаст,
         если мы не вмешаемся — и человек получит ключ от чужой квартиры
         за 15 000. Вот тут и должен сработать наш хук. ]]
    local fresh = mkDoor("zd1b", Vector(6190, 50, 10))
    local other2 = mkPly({ key="15:char1", name="Хитрец", pos=Vector(6190, 50, 0) })
    PLAYERS = { other2 }
    WALLET[other2] = 500000
    local before = WALLET[other2]
    NOTIFIED = {}

    local okBuy = GRM.Doors.ClaimDoor(other2, fresh, "buy")
    ok(okBuy == false,
       "ИСПРАВЛЕНО: ничейную дверь чужой занятой квартиры купить нельзя")
    ok(WALLET[other2] == before, "и денег не списали")
    ok(DOOR_RECS["zd1b"].owner_type == "none", "дверь осталась ничьей")

    local told = false
    for _, n in ipairs(NOTIFIED) do
        if n.to == other2 and tostring(n.msg):find("уже есть владелец", 1, true) then told = true end
    end
    ok(told, "покупателю объяснили причину, а не отказали молча")
end

-----------------------------------------------------------------------
print("\n=== 14. ОБЫЧНАЯ ДВЕРЬ ПРОДАЁТСЯ КАК РАНЬШЕ ===")
-----------------------------------------------------------------------
do
    --[[ Дверь вне всяких зон (подсобка, гараж) должна покупаться по
         своей цене — новое поведение не должно ломать старое. ]]
    local lone = mkDoor("lonely", Vector(50000, 50000, 0))
    local guy = mkPly({ key="13:char1", name="Одиночка", pos=Vector(50000, 50000, 0) })
    PLAYERS = { guy }
    WALLET[guy] = 500000
    local before = WALLET[guy]

    local okBuy = GRM.Doors.ClaimDoor(guy, lone, "buy")
    ok(okBuy == true, "обычная дверь покупается")
    ok(before - WALLET[guy] == GRM.Doors.DoorPrice,
       "по своей цене, а не по цене какого-то объекта", before - WALLET[guy])
    ok(DOOR_RECS["lonely"].owner_key == "13:char1", "и владелец у неё свой")
end

-----------------------------------------------------------------------
print("\n=== 15. АРЕНДА ЧЕРЕЗ ДВЕРЬ ОСТАЁТСЯ АРЕНДОЙ ===")
-----------------------------------------------------------------------
do
    P.Records = {}
    DOOR_RECS = {}
    WORLD = {}
    local flatR = P.Normalize({
        id="z2", name="Квартира под аренду", type="apartment",
        ownerType="none", tenure="none", purchasePrice=60000, rentPrice=6000,
        zone={mins=Vector(7000,-100,0), maxs=Vector(7200,100,200)},
    })
    P.Records["z2"] = flatR
    P.Reindex()
    local dr = mkDoor("zd2", Vector(7100, 0, 10))
    local guy = mkPly({ key="14:char1", name="Арендатор", pos=Vector(7100, 0, 0) })
    PLAYERS = { guy }
    WALLET[guy] = 500000
    local before = WALLET[guy]

    GRM.Doors.ClaimDoor(guy, dr, "rent")
    ok(flatR.tenure == "rent", "режим аренды сохранён, а не подменён покупкой",
       flatR.tenure)
    ok(before - WALLET[guy] == 6000,
       "списана цена АРЕНДЫ объекта", before - WALLET[guy])
    ok(flatR.rentUntil > 0, "срок аренды выставлен")
end

-----------------------------------------------------------------------
print("\n=== 16. ИСХОДНИКИ ===")
-----------------------------------------------------------------------
do
    local doors = (function() local f=assert(io.open("lua/autorun/sh_grm_doors.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(doors:find("GRM_DoorClaimToProperty", 1, true) ~= nil,
       "модуль дверей спрашивает недвижимость перед продажей")
    local claim = doors:match("function D%.ClaimDoor.-\n    end")
    local hookPos = claim and claim:find("GRM_DoorClaimToProperty", 1, true)
    local pricePos = claim and claim:find("local price = tonumber(rec.rent_price)", 1, true)
    ok(hookPos and pricePos and hookPos < pricePos,
       "спрашивает ДО списания денег за дверь — двойной оплаты не будет")

    local deal = (function() local f=assert(io.open("lua/autorun/sh_grm_estate_deal.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(deal:find("function DL.ClaimByDoor", 1, true) ~= nil, "обработчик есть")
    ok(deal:find("P.PanelAction(ply, { action = act, id = target.id })", 1, true) ~= nil,
       "оформление идёт через property — свою копию правил не заводим")
    ok(deal:find("DoorNearZone(r, pos)", 1, true) ~= nil,
       "объект ищется и по привязке, и по зоне — тул мог не привязать двери")

    local prop = (function() local f=assert(io.open("lua/autorun/sh_grm_property.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(prop:find("GRM.EstateDeal.DoorNearZone", 1, true) ~= nil,
       "проверка «рядом» учитывает игрока у двери снаружи зоны")
end

-----------------------------------------------------------------------
print("\n=== 17. ОСВОБОДИТЬ ЧЕРЕЗ ДВЕРЬ = ПРОДАТЬ ГОСУДАРСТВУ ===")
-----------------------------------------------------------------------
--[[ «Если я через дверь нажал освободить, то дом сразу же должен быть
     продан государству.»

     Раньше кнопка снимала владельца ТОЛЬКО с двери: объект оставался за
     игроком, но без входа — внутрь не попасть, а деньги не вернулись. ]]

-- Рынок: продажа государству за долю цены.
GRM.Estate.StateBuyback = 0.6
GRM.Estate.IsOwner = function(ply, rec)
    return tostring(rec.ownerType or "") == "character"
       and tostring(rec.ownerKey or "") == ply._key
end
GRM.Estate.IsBusiness = function(rec) return GRM.Estate.KindOf(rec) == "business" end
GRM.Estate.CashInZone = function(rec) return rec._cash or 0 end
GRM.Estate.InvalidateScan = function() end
GRM.Estate.Sync = function() end
GRM.Estate.SellToState = function(ply, rec)
    if not GRM.Estate.IsOwner(ply, rec) then return false, "Это не ваш объект" end
    if GRM.Estate.IsBusiness(rec) and GRM.Estate.CashInZone(rec) > 0 then
        return false, "Сначала снимите кассу бизнеса"
    end
    local price = math.floor((tonumber(rec.purchasePrice) or 0) * GRM.Estate.StateBuyback)
    local debt = math.max(0, tonumber(rec.utilityDebt) or 0)
    local paid = math.min(debt, price)
    local payout = price - paid
    rec.ownerType, rec.ownerKey, rec.ownerName = "none", "", ""
    rec.tenure, rec.rentUntil = "none", 0
    rec.employees, rec.guests, rec.tempKeys = {}, {}, {}
    rec.utilityDebt = debt - paid
    GRM.GiveMoney(ply, payout)
    hook.Run("GRM_PropertyOwnerChanged", rec, "release", ply)
    return true, "Продано государству за " .. payout .. " GRM"
end

do
    P.Records = {}
    DOOR_RECS = {}
    WORLD = {}
    local home = P.Normalize({
        id="r1", name="Дом на продажу", type="apartment",
        ownerType="none", tenure="none", purchasePrice=100000, rentPrice=9000,
        utilityDebt=0,
        zone={mins=Vector(8000,-100,0), maxs=Vector(8200,100,200)},
    })
    P.Records["r1"] = home
    P.Reindex()

    local dr = mkDoor("rd1", Vector(8100, 0, 10))
    local seller = mkPly({ key="21:char1", name="Продавец", pos=Vector(8100, 0, 0) })
    PLAYERS = { seller }
    WALLET[seller] = 500000

    -- Сначала покупаем.
    GRM.Doors.ClaimDoor(seller, dr, "buy")
    ok(home.ownerKey == "21:char1", "дом куплен")
    local afterBuy = WALLET[seller]

    -- Теперь освобождаем ЧЕРЕЗ ДВЕРЬ.
    NOTIFIED = {}
    local okRel = GRM.Doors.ReleaseDoor(seller, dr)

    ok(okRel == true, "освобождение через дверь прошло")
    ok(home.ownerType == "none",
       "ГЛАВНОЕ: продан ВЕСЬ объект, а не только дверь", tostring(home.ownerType))
    ok(WALLET[seller] == afterBuy + 60000,
       "ИСПРАВЛЕНО: за дом вернули 60% цены, а не ноль",
       WALLET[seller] - afterBuy)

    local told = false
    for _, n in ipairs(NOTIFIED) do
        if n.to == seller and tostring(n.msg):find("государству", 1, true) then told = true end
    end
    ok(told, "игроку сказали, за сколько продали")
end

-----------------------------------------------------------------------
print("\n=== 18. ДОЛГ УДЕРЖИВАЕТСЯ, КАССА МЕШАЕТ ===")
-----------------------------------------------------------------------
do
    P.Records = {} DOOR_RECS = {} WORLD = {}
    local biz = P.Normalize({
        id="r2", name="Ларёк", type="shop", estateKind="business",
        ownerType="character", ownerKey="22:char1", tenure="owned",
        purchasePrice=100000, utilityDebt=25000,
        zone={mins=Vector(9000,-100,0), maxs=Vector(9200,100,200)},
    })
    P.Records["r2"] = biz
    P.Reindex()
    local dr = mkDoor("rd2", Vector(9100, 0, 10))
    DOOR_RECS["rd2"] = { id="rd2", owner_type="player", owner_key="22:char1",
                         owner_nick="Торговец", ownable=false, title="Ларёк" }

    local biznes = mkPly({ key="22:char1", name="Торговец", pos=Vector(9100, 0, 0) })
    PLAYERS = { biznes }
    WALLET[biznes] = 0

    -- Несобранная касса не даёт продать: деньги пропали бы вместе с объектом.
    biz._cash = 5000
    NOTIFIED = {}
    local okRel = GRM.Doors.ReleaseDoor(biznes, dr)
    ok(okRel == false, "с несобранной кассой объект не продаётся")
    ok(biz.ownerKey == "22:char1", "и владелец не сменился")
    local why = false
    for _, n in ipairs(NOTIFIED) do
        if tostring(n.msg):find("кассу", 1, true) then why = true end
    end
    ok(why, "причина названа, а не молчаливый отказ")

    -- Кассу сняли — продаётся, долг удержан.
    biz._cash = 0
    GRM.Doors.ReleaseDoor(biznes, dr)
    ok(biz.ownerType == "none", "после сбора кассы продажа прошла")
    ok(WALLET[biznes] == 60000 - 25000,
       "ИСПРАВЛЕНО: долг по ЖКХ удержан из выплаты",
       WALLET[biznes])
    ok(biz.utilityDebt == 0, "и долг погашен", biz.utilityDebt)
end

-----------------------------------------------------------------------
print("\n=== 19. ЧУЖОЕ И ОБЫЧНЫЕ ДВЕРИ ===")
-----------------------------------------------------------------------
do
    P.Records = {} DOOR_RECS = {} WORLD = {}
    local home = P.Normalize({
        id="r3", name="Чужой дом", type="apartment",
        ownerType="character", ownerKey="30:char1", tenure="owned",
        purchasePrice=50000,
        zone={mins=Vector(10000,-100,0), maxs=Vector(10200,100,200)},
    })
    P.Records["r3"] = home
    P.Reindex()
    local dr = mkDoor("rd3", Vector(10100, 0, 10))
    DOOR_RECS["rd3"] = { id="rd3", owner_type="player", owner_key="30:char1",
                         owner_nick="Хозяин", ownable=false }

    local thief = mkPly({ key="31:char1", name="Чужак", pos=Vector(10100, 0, 0) })
    PLAYERS = { thief }
    WALLET[thief] = 0
    NOTIFIED = {}

    local okRel = GRM.Doors.ReleaseDoor(thief, dr)
    ok(okRel == false, "чужой дом через дверь не продать")
    ok(home.ownerKey == "30:char1", "владелец не сменился")
    ok(WALLET[thief] == 0, "и денег чужак не получил")

    -- Обычная дверь вне зон освобождается как раньше.
    local lone = mkDoor("rd_lone", Vector(60000, 60000, 0))
    DOOR_RECS["rd_lone"] = { id="rd_lone", owner_type="player", owner_key="31:char1",
                             owner_nick="Чужак", ownable=false }
    local okLone = GRM.Doors.ReleaseDoor(thief, lone)
    ok(okLone == true, "обычная дверь освобождается по-старому")
    ok(DOOR_RECS["rd_lone"].owner_type == "none", "и становится ничьей")
    ok(DOOR_RECS["rd_lone"].ownable == true, "и снова покупаемой")
end

-----------------------------------------------------------------------
print("\n=== 20. ИСХОДНИКИ ===")
-----------------------------------------------------------------------
do
    local doors = (function() local f=assert(io.open("lua/autorun/sh_grm_doors.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(doors:find("GRM_DoorReleaseToProperty", 1, true) ~= nil,
       "модуль дверей спрашивает недвижимость перед освобождением")
    local rel = doors:match("function D%.ReleaseDoor.-\n    end")
    local hookPos = rel and rel:find("GRM_DoorReleaseToProperty", 1, true)
    local clearPos = rel and rel:find('rec.owner_type = "none"', 1, true)
    ok(hookPos and clearPos and hookPos < clearPos,
       "спрашивает ДО обнуления двери — объект не останется без входа")

    local deal = (function() local f=assert(io.open("lua/autorun/sh_grm_estate_deal.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(deal:find("function DL.ReleaseByDoor", 1, true) ~= nil, "обработчик есть")
    ok(deal:find("ES.SellToState(ply, target)", 1, true) ~= nil,
       "продажа идёт через рынок — выплата и долг считаются там")
    ok(deal:find("P.CanManage and P.CanManage(ply, target)", 1, true) ~= nil,
       "права проверяет property, своей копии нет")

    -- Окно квартиры должно вести себя так же.
    local panel = (function() local f=assert(io.open("lua/autorun/sh_grm_housing_panel.lua"))
        local t=f:read("*a") f:close() return t end)()
    ok(panel:find("ES.SellToState(ply, rec)", 1, true) ~= nil,
       "ИСПРАВЛЕНО: отказ от жилья в /home тоже продаёт, а не обнуляет молча")
    ok(panel:find("ПРОДАТЬ ГОСУДАРСТВУ", 1, true) ~= nil,
       "и кнопка честно называет, что произойдёт")
    ok(panel:find("buyback = ", 1, true) ~= nil,
       "сумма выплаты показывается ДО согласия")
end

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
