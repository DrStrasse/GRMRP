--[[ Живой прогон «Купить ≠ Выдать» у дилера транспорта (заказ 21.08):
     покупка только оформляет машину в собственность, выдача — отдельное
     действие с выбором места (у дилера или в гараж).
     Грузятся РЕАЛЬНЫЕ lua/autorun/sh_grm_vehicle_dealer.lua и
     lua/autorun/sh_grm_garage.lua.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_dealer_buy_issue.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }
local NOW = 100
function CurTime() return NOW end
function SysTime() return 100 end
function RealTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" and v._valid ~= nil end
function ErrorNoHalt() end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE, FCVAR_NOTIFY = 1, 2
MASK_SOLID, MASK_SHOT, SOLID_VPHYSICS, MOVETYPE_VPHYSICS = 1, 2, 6, 6
COLLISION_GROUP_NONE = 0

local function mkVec(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    function v:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
    setmetatable(v, {
        __add = function(a, b) return mkVec(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return mkVec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b) if type(b) == "number" then return mkVec(a.x * b, a.y * b, a.z * b) end return mkVec(a.x * b.x, a.y * b.y, a.z * b.z) end,
    })
    return v
end
function Vector(x, y, z) return mkVec(x, y, z) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local CONVARS = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetBool() return tostring(self.value) == "1" end
    function cv:GetString() return tostring(self.value) end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end
function GetConVar(n) return CONVARS[n] end

game = { GetMap = function() return "sim_map" end }
local FS = {}
file = {
    IsDir = function() return true end, CreateDir = function() end,
    Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end, Delete = function(p) FS[p] = nil end,
    Find = function() return {}, {} end,
}
local function encode(v)
    local t = type(v)
    if t == "number" then return string.format("%.14g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local isArr = #v > 0
        local parts = {}
        if isArr then
            for _, i in ipairs(v) do parts[#parts + 1] = encode(i) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. encode(i) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
util = { TableToJSON = function(t) return encode(t) end, JSONToTable = function() return nil end,
         AddNetworkString = function() end, TraceLine = function() return { Hit = false, HitPos = Vector(0, 0, 0) } end,
         TraceHull = function() return { Hit = false } end,
         CRC = (function() local n = 0 return function() n = n + 1 return tostring(1000 + n) end end)() }

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Remove = function(e, n) if HOOKS[e] then HOOKS[e][n] = nil end end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do local r = fn(...) if r ~= nil then return r end end end,
    Call = function(e, _, ...) return hook.Run(e, ...) end,
}
timer = { Simple = function(_, fn) if fn then fn() end end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
concommand = { Add = function() end }
list = { Get = function() return {} end, Set = function() end }
duplicator = { RegisterEntityClass = function() end, StoreEntityModifier = function() end,
               RegisterEntityModifier = function() end }
resource = { AddFile = function() end }
properties = { Add = function() end }

local ENTS = {}
ents = {
    GetAll = function() return ENTS end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(ENTS) do if e:GetClass() == cls then out[#out + 1] = e end end
        return out
    end,
    FindInSphere = function() return {} end,
    FindInBox = function() return {} end,
    Create = function(cls)
        local e = { _valid = true, _class = cls, _pos = Vector(0, 0, 0), _nw = {} }
        function e:GetClass() return self._class end
        function e:SetPos(v) self._pos = v end
        function e:GetPos() return self._pos end
        function e:SetAngles() end
        function e:GetAngles() return Angle(0, 0, 0) end
        function e:Spawn() end
        function e:Activate() end
        function e:SetModel() end
        function e:GetModel() return "models/buggy.mdl" end
        function e:EntIndex() return 1 end
        function e:Remove() self._valid = false end
        function e:SetNWString(k, v) self._nw[k] = v end
        function e:GetNWString(k, d) local v = self._nw[k] if v == nil then return d end return v end
        function e:SetNWBool(k, v) self._nw[k] = v end
        function e:GetNWBool(k, d) local v = self._nw[k] if v == nil then return d end return v end
        function e:SetNWEntity(k, v) self._nw[k] = v end
        function e:SetOwner() end
        function e:GetPhysicsObject() return { IsValid = function() return false end } end
        function e:IsVehicle() return true end
        function e:GetDriver() return nil end
        ENTS[#ENTS + 1] = e
        return e
    end,
}
player = { GetAll = function() return {} end, GetBySteamID64 = function() return nil end }

local SENT = {}
net = {
    Receive = function(m, fn) SENT[m] = fn end,
    Start = function() end, Send = function() end, Broadcast = function() end,
    WriteString = function() end, WriteEntity = function() end, WriteTable = function() end,
    WriteBool = function() end, WriteUInt = function() end, WriteInt = function() end,
    ReadString = function() return "" end, ReadEntity = function() return nil end,
    ReadTable = function() return {} end, ReadBool = function() return false end,
}

local MONEY = {}
GRM = {
    Notify = function(_, msg) LASTMSG = tostring(msg) end,
    Format = function(n) return tostring(n) .. " GRM" end,
    HasMoney = function(ply, n) return (MONEY[ply] or 0) >= n end,
    TakeMoney = function(ply, n) MONEY[ply] = (MONEY[ply] or 0) - n return true end,
    GiveMoney = function(ply, n) MONEY[ply] = (MONEY[ply] or 0) + n return true end,
    Identity = { CharacterKey = function(p) return p:SteamID64() .. ":char1" end },
    Perf = { Entities = function(cls) return ents.FindByClass(cls) end, Players = function() return {} end,
             Throttle = function() return true end, Coalesce = function(_, fn) if fn then fn() end end },
    Audit = { Write = function() end, Log = function() end },
}
GRM.Doors = { IsDoor = function() return false end, GetDoorID = function() return nil end,
              IsDoorLocked = function() return false end, LockDoor = function() end }
GRM.Property = { Records = {} }

assert(loadfile("lua/autorun/sh_grm_vehicle_dealer.lua"))()
local VD = GRM.VehicleDealer
assert(loadfile("lua/autorun/sh_grm_garage.lua"))()
local G = GRM.Garage

-- Спавн машины подменяем: настоящий зовёт движок.
local SPAWNED = {}
function VD.Spawn(class, dealer, ply, place)
    local ent = ents.Create("sim_vehicle")
    ent:SetPos(place and place.pos or Vector(10, 0, 0))
    ent._place = place
    SPAWNED[#SPAWNED + 1] = { class = class, place = place }
    return ent, VD.VehicleInfo(class), nil
end

local function mkPly(name, key64)
    local p = { _valid = true, _pos = Vector(0, 0, 0), nw = {} }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return self.super == true end
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:Nick() return name end
    function p:SteamID() return name end
    function p:SteamID64() return key64 or name end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:ChatPrint() end
    function p:PrintMessage() end
    return p
end

local dealerEnt = ents.Create("sent_vehicle_dealer")
dealerEnt._class = "sent_vehicle_dealer"
dealerEnt.GetDealerID = function() return "dealer1" end
dealerEnt.GetDealerName = function() return "Автосалон" end
dealerEnt.VD_Vehicles = {
    { class = "car_personal", name = "Седан", price = 1000, category = "Личный" },
    { class = "car_service", name = "Патрульная", price = 0, service = true, ownershipType = "public" },
}

local buyer = mkPly("Buyer", "76561190000000011")
MONEY[buyer] = 100000

-- Читалка строк из net: подменяем последовательностью на каждый вызов.
local function feed(seq)
    local i = 0
    net.ReadString = function() i = i + 1 return seq[i] or "" end
end
net.ReadEntity = function() return dealerEnt end

local action = SENT["GRM_VD_Action"]
-- У дилера есть анти-спам (0.35 с на действие) — двигаем время между вызовами.
local function fire(seq)
    NOW = NOW + 1
    LASTMSG = nil
    feed(seq)
    action(0, buyer)
    if os.getenv("SIMDEBUG") then print("    [msg] " .. tostring(LASTMSG)) end
end

print("\n=== 1. ПОКУПКА НЕ ВЫДАЁТ МАШИНУ НА КАРТУ ===")
ok(isfunction(action), "обработчик действий дилера зарегистрирован")
fire({ "buy", "car_personal", "", "store" })
local records = VD.GarageRecords(buyer)
local rec, recID
for id, r in pairs(records) do rec, recID = r, id end
ok(rec ~= nil, "запись о покупке создана")
ok(rec and rec.stored == true, "машина сразу на хранении, а не на площадке", rec and tostring(rec.stored))
ok(#SPAWNED == 0, "при покупке ничего не спавнится", #SPAWNED)
ok((MONEY[buyer] or 0) == 99000, "деньги списаны один раз", MONEY[buyer])
ok(rec and rec.price == 1000, "цена записана в собственность")

print("\n=== 2. СЛУЖЕБНЫЙ ТРАНСПОРТ ВЫДАЁТСЯ СРАЗУ ===")
buyer.super = true -- служебный доступен
fire({ "buy", "car_service", "", "dealer" })
ok(#SPAWNED == 1, "служебная машина выдана на месте", #SPAWNED)
buyer.super = false

print("\n=== 3. ВЫДАЧА У ДИЛЕРА ===")
fire({ "retrieve", recID, "dealer", "" })
ok(#SPAWNED == 2, "по «ВЫДАТЬ у дилера» машина появилась", #SPAWNED)
ok(SPAWNED[2] and SPAWNED[2].place == nil, "у дилера машина ставится на площадку дилера")
ok(records[recID].stored == false, "запись помечена «на карте»")

-- вернём в гараж
fire({ "store", recID })
ok(records[recID].stored == true, "машина убрана обратно на хранение")

print("\n=== 4. ВЫДАЧА В ГАРАЖ ===")
local admin = mkPly("Admin", "76561190000000001") admin.super = true
local created, garageRec = G.Create(admin, Vector(-600, -600, 0), Vector(600, 600, 300),
    { name = "Северный", kind = "public", fee = 0 })
ok(created == true, "гараж для теста создан", garageRec)
G.AddSlot(garageRec.id, Vector(100, 100, 0), Angle(0, 90, 0), 10, "Бокс 1")

ok(isfunction(G.IssueRemote), "у гаражей есть удалённая подача транспорта")
fire({ "retrieve", recID, "garage", garageRec.id })
ok(#SPAWNED == 3, "машина подана", #SPAWNED)
ok(SPAWNED[3] and SPAWNED[3].place ~= nil, "подана именно НА МЕСТО гаража, а не к дилеру")
ok(records[recID].garageID == garageRec.id, "запись закреплена за этим гаражом")

print("\n=== 5. ЗАНЯТЫЙ ГАРАЖ И ЧУЖИЕ ЗАПИСИ ===")
fire({ "retrieve", recID, "garage", garageRec.id })
ok(#SPAWNED == 3, "повторная подача уже выданной машины не плодит дубликаты", #SPAWNED)
local okRemote, whyRemote = G.IssueRemote(buyer, "нет-такой-записи", garageRec.id)
ok(okRemote == false and isstring(whyRemote), "несуществующая запись отклонена с причиной", whyRemote)

print("\n=== 6. ПЛАТА ЗА ПОДАЧУ ===")
fire({ "store", recID })
G.Update(garageRec.id, { fee = 500 }, admin)
local before = MONEY[buyer]
local okFee, msgFee = G.IssueRemote(buyer, recID, garageRec.id)
ok(okFee == true, "подача с платой прошла", msgFee)
ok((MONEY[buyer] or 0) == before - 500, "плата за подачу списана", MONEY[buyer])

print("\n=== 7. МЕСТА ГАРАЖА РАБОТАЮТ И У ДИЛЕРА ===")
-- связываем дилера с гаражом: выдача «у дилера» должна уйти на МЕСТО гаража
ok(isfunction(VD.ResolveDeliveryPlace), "выбор места вынесен в одну функцию")
G.LinkDealer(garageRec.id, "dealer1")
local linked = false
for _, l in ipairs(G.Get(garageRec.id).linkedDealers or {}) do if l == "dealer1" then linked = true end end
ok(linked, "дилер связан с гаражом")

fire({ "store", recID })
local placeBefore = #SPAWNED
fire({ "retrieve", recID, "dealer", "" })
ok(#SPAWNED == placeBefore + 1, "машина выдана", #SPAWNED)
ok(SPAWNED[#SPAWNED].place ~= nil,
   "выдача У ДИЛЕРА ушла на МЕСТО связанного гаража, а не на площадку перед дилером")

-- без связи и без домашнего гаража — старое поведение (площадка дилера)
local lone = ents.Create("sent_vehicle_dealer")
lone.GetDealerID = function() return "dealer_lonely" end
lone.GetDealerName = function() return "Одинокий" end
lone.VD_Vehicles = dealerEnt.VD_Vehicles
lone:SetPos(Vector(90000, 90000, 0))          -- в чистом поле, гаражей рядом нет
records[recID].garageID = ""
fire({ "store", recID })
buyer:SetPos(Vector(90000, 90000, 0))
local place2, label2 = VD.ResolveDeliveryPlace(buyer, records[recID], lone, nil)
ok(place2 == nil and tostring(label2):find("дилера", 1, true) ~= nil,
   "у дилера в чистом поле остаётся его собственная площадка", label2)
ok(isstring(VD.LastPlaceReason) and VD.LastPlaceReason ~= "",
   "и система объясняет, почему места не сработали", VD.LastPlaceReason)
buyer:SetPos(Vector(0, 0, 0))

print("\n=== 8. МЕСТА РАБОТАЮТ БЕЗ ПРИВЯЗКИ ДИЛЕРА ===")
-- гараж, где стоит игрок, используется сам по себе
local free = select(2, G.Create(admin, Vector(20000, 20000, 0), Vector(20600, 20600, 300),
    { name = "Городской", kind = "public" }))
G.AddSlot(free.id, Vector(20100, 20100, 0), Angle(0, 0, 0), 10, "Место 1")
buyer:SetPos(Vector(20300, 20300, 0))
local place3, label3 = VD.ResolveDeliveryPlace(buyer, records[recID], lone, nil)
ok(place3 ~= nil and tostring(label3):find("Городской", 1, true) ~= nil,
   "стоишь в гараже — машина подаётся на его место, привязка дилера не нужна", label3)
buyer:SetPos(Vector(0, 0, 0))

print("\n=== 9. АКТИВНАЯ ТЕХНИКА АВТОПАРКА В «НА КАРТЕ» (22.08) ===")
buyer.nw.GRM_Faction = "police"
local fent = ents.Create("sim_vehicle")
fent:SetPos(Vector(50, 50, 0))
local funit = { id = "fu_act1", class = "sim_patrol", name = "Патрульный",
    model = "models/buggy.mdl", kind = "government", faction = "police" }
GRM.Fleet = GRM.Fleet or {}
GRM.Fleet.UnitsOf = function(f) if f == "police" then return { funit } end return {} end
GRM.Fleet.Active = { [funit.id] = fent }
local activeRows = VD.ActiveRows(buyer)
local found
for _, r in ipairs(activeRows) do
    if r.fleet == true and r.id == funit.id then found = r end
end
ok(found ~= nil, "у дилера в «На карте» видна активная служебная машина")
ok(found ~= nil and found.personal == false, "служебная строка не помечена личной")
ok(found ~= nil and found.ownershipName ~= "", "у служебной машины есть тип владения")

print(("\nDEALER BUY/ISSUE: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
