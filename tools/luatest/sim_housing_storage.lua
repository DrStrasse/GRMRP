--[[ Живой прогон домашнего хранилища (жильё, фаза 2).

     Владелец на вопрос «что даёт жильё кроме спавна» ответил «да» на
     хранилище/отдых/приватность, и «да» на вход полиции по ордеру.
     Отдых сделан в фазе 1, здесь — шкаф.

     Проверяется:
       1) шкаф принадлежит квартире, а не игроку;
       2) доступ — тот же, что вход в квартиру (единая точка правды);
       3) анти-дюп: сервер сам считает, сколько влезло;
       4) вес и слоты реально ограничивают;
       5) обыск по ордеру виден и логируется;
       6) продажа квартиры не телепортирует склад;
       7) отошёл от шкафа — окно закрылось.

     Запуск: luajit tools/luatest/sim_housing_storage.lua ]]

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
function VecMT:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function VecMT:Normalize() local l=self:Length() if l>0 then self.x,self.y,self.z=self.x/l,self.y/l,self.z/l end return self end
function VecMT:Angle() return Angle(0, math.deg(math.atan2(self.y, self.x)), 0) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt() end
CurTime = function() return 100 end
HUD_PRINTTALK = 3
MASK_PLAYERSOLID = 33570819
FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
bit = { bor = function(a,b) return a+b end }

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r,b=f(...) if r~=nil then return r,b end end end

timer = { _c = {} }
function timer.Simple(_,f) f() end
function timer.Create(id,_,_,f) timer._c[id]=f end
function timer.Remove(id) timer._c[id]=nil end
local function tick(id) if timer._c[id] then timer._c[id]() end end

local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }

-- Сеть: пишем, что улетело клиенту.
local SENT = {}
local writeBuf
net = {
    AddNetworkString = function() end,
    Start = function(n) writeBuf = { name = n, args = {} } end,
    WriteEntity = function(v) table.insert(writeBuf.args, v) end,
    WriteTable  = function(v) table.insert(writeBuf.args, v) end,
    WriteFloat  = function(v) table.insert(writeBuf.args, v) end,
    WriteUInt   = function(v) table.insert(writeBuf.args, v) end,
    WriteString = function(v) table.insert(writeBuf.args, v) end,
    WriteBool   = function(v) table.insert(writeBuf.args, v) end,
    Send = function(p) writeBuf.to = p; table.insert(SENT, writeBuf) end,
    Broadcast = function() table.insert(SENT, writeBuf) end,
    Receive = function(n, f) net["_h_" .. n] = f end,
    ReadEntity = function() return net._r[1] end,
    ReadBool = function() return net._r[2] end,
    ReadUInt = function() net._ri = (net._ri or 2) + 1 return net._r[net._ri] end,
    ReadTable = function() return {} end,
    ReadFloat = function() return 0 end,
    ReadString = function() return "" end,
}
util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) return "JSON" end,
    JSONToTable = function() return {} end,
    IsValidModel = function() return true end,
}
local FS = { data = {}, writes = 0 }
file = {
    Exists = function(n) return FS.data[n] ~= nil end,
    Read = function(n) return FS.data[n] or "" end,
    Write = function(n,t) FS.data[n]=t FS.writes=FS.writes+1 end,
    CreateDir = function() end, IsDir = function() return true end,
}
local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }
ents = { GetAll = function() return {} end, FindByClass = function() return {} end, FindInSphere = function() return {} end }
function CreateConVar(_, d) return { GetFloat=function() return tonumber(d) or 0 end, GetBool=function() return d~="0" end, GetString=function() return tostring(d) end, GetInt=function() return math.floor(tonumber(d) or 0) end } end

local NOTIFIED = {}
GRM = {
    Perf = { Players = function() return PLAYERS end },
    Notify = function(p, msg) NOTIFIED[#NOTIFIED+1] = msg end,
}
local AUDIT = {}
GRM.Audit = { Write = function(cat, act, ply, ids, d) AUDIT[#AUDIT+1] = { cat=cat, act=act, ids=ids, d=d } end }

-- Инвентарь: настоящая семантика в миниатюре.
local INV = {}
GRM.Inventory = {
    ItemDefs = {
        bread  = { name = "Хлеб",  weight = 0.5, maxStack = 10 },
        brick  = { name = "Кирпич", weight = 50,  maxStack = 10 },
    },
    GetItemDef = function(id) return GRM.Inventory.ItemDefs[id] end,
    GetMaxStack = function(id)
        local d = GRM.Inventory.ItemDefs[id]
        return (d and d.maxStack) or 99
    end,
    GetPlayerInv = function(p) INV[p] = INV[p] or { slots = {} } return INV[p] end,
    RemoveFromSlot = function(p, idx, n)
        local inv = INV[p]
        local s = inv and inv.slots[idx]
        if not s then return end
        s.count = (s.count or 1) - n
        if s.count <= 0 then inv.slots[idx] = nil end
    end,
    AddItem = function(p, id, n)
        INV[p] = INV[p] or { slots = {} }
        if INV[p]._full then return n end   -- имитация «нет места»
        for i = 1, 24 do
            local s = INV[p].slots[i]
            if not s then INV[p].slots[i] = { id = id, count = n } return 0 end
        end
        return n
    end,
    AddWeapon = function(p, cls)
        INV[p] = INV[p] or { slots = {} }
        if INV[p]._full then return false end
        for i = 1, 24 do
            if not INV[p].slots[i] then INV[p].slots[i] = { id="weapon:"..cls, count=1 } return true end
        end
        return false
    end,
}

-- Недвижимость и жильё.
GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    IsInside = function(r, pos)
        if not istable(r.zone) then return false end
        local a,b = r.zone.mins, r.zone.maxs
        return pos.x>=a.x and pos.y>=a.y and pos.z>=a.z and pos.x<=b.x and pos.y<=b.y and pos.z<=b.z
    end,
    CanAdmin = function(p) return IsValid(p) and p._admin == true end,
    HasAccess = function(p, r)
        if not IsValid(p) then return false end
        return r.ownerType == "character" and r.ownerKey == p._key
    end,
    Save = function() end,
}
local WARRANTS = { byOwner = {}, byProperty = {} }
GRM.Doors = {
    IsDoor = function() return false end,
    HasWarrant = function(k) return WARRANTS.byOwner[k] == true end,
    HasPropertyWarrant = function(id) return WARRANTS.byProperty[id] == true end,
}
GRM.Access = { Can = function(p, c) return IsValid(p) and p._caps and p._caps[c] == true end }
GRM.Estate = { ZoneCenter = function(r)
    if not istable(r.zone) then return nil end
    local a,b = r.zone.mins, r.zone.maxs
    return Vector((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
end }
GRM.Identity = { CharacterKey = function(p) return p._key end }

assert(loadfile("lua/autorun/sh_grm_housing.lua"))()
assert(loadfile("lua/autorun/sh_grm_housing_storage.lua"))()
local HS, ST = GRM.Housing, GRM.HomeStorage

local function mkPly(o)
    o = o or {}
    return {
        _valid = true, _key = o.key or "1:char1", _admin = o.admin == true,
        _caps = o.caps or {}, _pos = o.pos or Vector(0,0,0),
        SteamID64 = function() return "1" end,
        GetPos = function(s) return s._pos end,
        EyeAngles = function() return Angle(0,0,0) end,
        GetEyeTrace = function() return { Entity = o.aim } end,
        PrintMessage = function(_,_,t) o.said = (o.said or "") .. t .. "\n" end,
        IsPlayer = function() return true end,
    }
end

local function mkLocker(pos)
    local filled = 0
    return {
        _valid = true, _pos = pos or Vector(50, 0, 0),
        GetPos = function(s) return s._pos end,
        GetClass = function() return "grm_home_locker" end,
        UpdateFill = function(s) s._fillCalls = (s._fillCalls or 0) + 1 end,
        EmitSound = function() end,
    }
end

local flat = {
    id = "flat1", name = "Квартира 14", type = "apartment",
    ownerType = "character", ownerKey = "1:char1", tenure = "owned",
    sealed = false, rentUntil = 0, doors = {},
    zone = { mins = Vector(-100,-100,-50), maxs = Vector(200,100,200) },
}
GRM.Property.Records = { flat1 = flat }

local owner = mkPly({ key = "1:char1", pos = Vector(50, 0, 0) })
local stranger = mkPly({ key = "9:char1", pos = Vector(50, 0, 0) })
local cop = mkPly({ key = "7:char1", pos = Vector(50,0,0), caps = { ["wanted.civil.edit"] = true } })
local admin = mkPly({ key = "8:char1", pos = Vector(50,0,0), admin = true })
local locker = mkLocker(Vector(50, 0, 0))

-----------------------------------------------------------------------
print("\n=== 1. ШКАФ ПРИНАДЛЕЖИТ КВАРТИРЕ, А НЕ ИГРОКУ ===")
-----------------------------------------------------------------------
ok(ST.PropertyOf(locker) == flat, "шкаф определяет свою квартиру по зоне")
local slots, sid = ST.SlotsFor(flat)
ok(istable(slots), "слоты создаются лениво под ID объекта")
ok(sid == "flat1", "ключ хранения — ID недвижимости, а не SteamID", sid)

local outside = mkLocker(Vector(9999, 9999, 0))
ok(ST.PropertyOf(outside) == nil, "шкаф вне зоны ничьей квартире не принадлежит")
--[[ Встаём вплотную к «бесхозному» шкафу: дистанция проверяется раньше
     принадлежности (дешёвая проверка первой), и издалека мы бы получили
     «far», не дойдя до интересующей нас ветки. ]]
local nearOutside = mkPly({ key = "9:char1", pos = Vector(9999, 9999, 0) })
local adminOutside = mkPly({ key = "8:char1", pos = Vector(9999, 9999, 0), admin = true })
local a1, r1 = ST.CanUse(nearOutside, outside)
ok(a1 == false and r1 == "no_property",
   "и обычный игрок его не откроет — иначе это склад посреди улицы", r1)
local a2, r2 = ST.CanUse(adminOutside, outside)
ok(a2 == true and r2 == "admin_loose", "но админ откроет, чтобы убрать ошибку установки", r2)

-----------------------------------------------------------------------
print("\n=== 2. ДОСТУП = ВХОД В КВАРТИРУ ===")
-----------------------------------------------------------------------
local allowed, reason = ST.CanUse(owner, locker)
ok(allowed == true and reason == "key", "владелец открывает шкаф", reason)

allowed, reason = ST.CanUse(stranger, locker)
ok(allowed == false and reason == "no_key", "чужой не открывает", reason)

-- Далеко.
stranger._pos = Vector(9000, 0, 0)
allowed, reason = ST.CanUse(stranger, locker)
ok(allowed == false and reason == "far", "издалека шкаф не открыть", reason)
stranger._pos = Vector(50, 0, 0)

-- Опечатка сильнее всего, как и на двери.
flat.sealed = true
allowed, reason = ST.CanUse(owner, locker)
ok(allowed == false and reason == "sealed", "в опечатанной квартире шкаф закрыт даже владельцу")
flat.sealed = false

-- Просроченная аренда.
flat.tenure = "rent"; flat.rentUntil = os.time() - 10
allowed, reason = ST.CanUse(owner, locker)
ok(allowed == false and reason == "rent_expired", "после конца аренды шкаф недоступен", reason)
flat.tenure = "owned"; flat.rentUntil = 0

-----------------------------------------------------------------------
print("\n=== 3. КЛАДЁМ В ШКАФ: АНТИ-ДЮП И ЛИМИТЫ ===")
-----------------------------------------------------------------------
slots = ST.SlotsFor(flat)
for k in pairs(slots) do slots[k] = nil end

local moved = ST.Deposit(slots, { id = "bread", count = 5 }, 5)
ok(moved == 5, "положили 5 хлеба", moved)
ok(slots[1] and slots[1].count == 5, "лёг одним стаком")

-- Добиваем стак до максимума, остаток уходит в новый слот.
moved = ST.Deposit(slots, { id = "bread", count = 8 }, 8)
ok(moved == 8, "положили ещё 8")
ok(slots[1].count == 10, "первый стак добит до maxStack=10", slots[1].count)
ok(slots[2] and slots[2].count == 3, "остаток ушёл во второй слот", slots[2] and slots[2].count)

-- Просят больше, чем есть в исходном слоте — клэмп до наличия.
moved = ST.Deposit(slots, { id = "bread", count = 2 }, 999)
ok(moved == 2, "нельзя положить больше, чем реально есть в слоте — это был бы дюп", moved)

-- Вес.
for k in pairs(slots) do slots[k] = nil end
moved = ST.Deposit(slots, { id = "brick", count = 10 }, 10)
ok(moved == 4, "кирпич по 50 кг: влезло ровно 4 при лимите 200 кг", moved)
ok(math.abs(ST.TotalWeight(slots) - 200) < 0.01, "вес ровно на пределе", ST.TotalWeight(slots))
moved = ST.Deposit(slots, { id = "brick", count = 1 }, 1)
ok(moved == 0, "сверх лимита не влезает ничего")

-- Слоты.
for k in pairs(slots) do slots[k] = nil end
for i = 1, ST.MaxSlots do slots[i] = { id = "bread", count = 1 } end
moved = ST.Deposit(slots, { id = "brick", count = 1 }, 1)
ok(moved == 0, "все слоты заняты — новый предмет не влезает")

-- Оружие не стакается.
for k in pairs(slots) do slots[k] = nil end
ST.Deposit(slots, { id = "weapon:pistol", count = 1, data = { class = "pistol" } }, 1)
ST.Deposit(slots, { id = "weapon:pistol", count = 1, data = { class = "pistol" } }, 1)
ok(slots[1] and slots[2], "два пистолета заняли два разных слота")
ok(slots[1].count == 1 and slots[2].count == 1, "оружие не стакается")

-----------------------------------------------------------------------
print("\n=== 4. ПЕРЕКЛАДЫВАНИЕ ЧЕРЕЗ СЕТЬ (сервер не верит клиенту) ===")
-----------------------------------------------------------------------
for k in pairs(slots) do slots[k] = nil end
INV[owner] = { slots = { [1] = { id = "bread", count = 6 } } }
ST.Viewers[locker] = { [owner] = true }

local xfer = net["_h_" .. ST.NET.XFER]
ok(isfunction(xfer), "обработчик перекладывания зарегистрирован")

-- Кладём весь стак.
net._r = { locker, true, 1, 999 } net._ri = 2
xfer(0, owner)
ok(slots[1] and slots[1].count == 6, "6 хлеба уехали в шкаф", slots[1] and slots[1].count)
ok(INV[owner].slots[1] == nil, "и списались из инвентаря ровно те, что влезли")

-- Забираем обратно одну штуку.
net._r = { locker, false, 1, 1 } net._ri = 2
xfer(0, owner)
ok(slots[1].count == 5, "из шкафа ушла одна штука", slots[1].count)

-- Чужой не может копаться, даже если пришлёт пакет.
net._r = { locker, false, 1, 999 } net._ri = 2
local before = slots[1].count
xfer(0, stranger)
ok(slots[1].count == before, "пакет от постороннего игнорируется")

-- Не открывал шкаф — не трогает, даже имея ключ.
ST.Viewers[locker] = {}
net._r = { locker, false, 1, 999 } net._ri = 2
xfer(0, owner)
ok(slots[1].count == before, "владелец, не открывший шкаф, тоже не может дёргать слоты пакетом")
ST.Viewers[locker] = { [owner] = true }

-- Инвентарь полон — вещь остаётся в шкафу, а не исчезает.
INV[owner]._full = true
net._r = { locker, false, 1, 999 } net._ri = 2
xfer(0, owner)
ok(slots[1] and slots[1].count == before, "при полном инвентаре предмет НЕ пропадает из шкафа")
INV[owner]._full = nil

-----------------------------------------------------------------------
print("\n=== 5. ОБЫСК ПО ОРДЕРУ ===")
-----------------------------------------------------------------------
local searched = {}
hook.Add("GRM_HomeStorageSearched", "test", function(p, rec, ent, why)
    searched[#searched+1] = { ply = p, rec = rec, why = why }
end)

WARRANTS.byProperty["flat1"] = true
local nAudit = #AUDIT
ST.Viewers[locker] = {}
ok(ST.Open(cop, locker) == true, "полиция с ордером открывает шкаф — это и есть обыск")
ok(#searched == 1 and searched[1].why == "warrant_property",
   "событие обыска брошено, фаза 3 повесит на него уведомление владельцу")
ok(#AUDIT > nAudit, "обыск записан в аудит")
ok(AUDIT[#AUDIT].act == "storage.search", "с правильным действием", AUDIT[#AUDIT].act)
WARRANTS.byProperty["flat1"] = nil

-- Обычное открытие владельцем обыском не считается.
searched = {}
nAudit = #AUDIT
ST.Viewers[locker] = {}
ST.Open(owner, locker)
ok(#searched == 0, "владелец открывает свой шкаф — это не обыск")
ok(#AUDIT == nAudit, "и в журнал обысков не пишется")

-- Без ордера полиция не лезет.
ok(ST.Open(cop, locker) == false, "без ордера полиция шкаф не откроет")

-----------------------------------------------------------------------
print("\n=== 6. СМЕНА ХОЗЯИНА КВАРТИРЫ ===")
-----------------------------------------------------------------------
slots = ST.SlotsFor(flat)
for k in pairs(slots) do slots[k] = nil end
slots[1] = { id = "bread", count = 3 }

ST.Viewers[locker] = { [owner] = true }
hook.Run("GRM_PropertyOwnerChanged", flat, "sold")
ok(ST.Viewers[locker][owner] == nil, "при смене хозяина открытое окно закрывается")

local after = ST.SlotsFor(flat)
ok(after[1] and after[1].count == 3,
   "вещи остаются в шкафу как мебель — иначе продажа была бы телепортом склада")

-- Новый владелец получает доступ к тем же вещам.
flat.ownerKey = "9:char1"
allowed = ST.CanUse(stranger, locker)
ok(allowed == true, "новый хозяин открывает шкаф")
ok(ST.CanUse(owner, locker) == false, "а прежний — уже нет")
flat.ownerKey = "1:char1"

-----------------------------------------------------------------------
print("\n=== 7. ОТОШЁЛ — ЗАКРЫЛОСЬ ===")
-----------------------------------------------------------------------
ST.Viewers[locker] = { [owner] = true }
owner._pos = Vector(9000, 0, 0)
tick("GRM_HomeStorage_Range")
ok(ST.Viewers[locker][owner] == nil,
   "ушёл далеко — шкаф закрылся сам, нельзя таскать вещи с другого конца карты")
owner._pos = Vector(50, 0, 0)

-----------------------------------------------------------------------
print("\n=== 8. СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
FS.writes = 0
ST.MarkDirty()
ok(FS.writes == 0, "перекладывание не пишет файл сразу — дебаунс")
tick("GRM_HomeStorage_Debounce")
ok(FS.writes == 1, "но по дебаунсу запись доходит", FS.writes)

FS.writes = 0
ST.MarkDirty()
hook.Run("ShutDown")
ok(FS.writes >= 1, "на выключении сервера вещи сохраняются немедленно", FS.writes)

FS.writes = 0
ST.MarkDirty()
hook.Run("PlayerDisconnected", owner)
ok(FS.writes >= 1, "и на выходе игрока тоже")

-----------------------------------------------------------------------
print("\n=== 9. ИНТЕГРАЦИЯ ===")
-----------------------------------------------------------------------
local perm = assert(io.open("lua/autorun/sh_grm_perm_entities.lua")):read("*a")
ok(perm:find("grm_home_locker", 1, true) ~= nil,
   "шкаф в PERM_CLASSES — переживёт рестарт карты")

local hub = assert(io.open("lua/autorun/sh_grm_admin_hub.lua")):read("*a")
ok(hub:find("grm_home_storage", 1, true) ~= nil, "шкафы есть в админ-хабе")
ok(hub:find("grm_housing", 1, true) ~= nil, "и диагностика жилья тоже")

local entSrc = assert(io.open("lua/entities/grm_home_locker/cl_init.lua")):read("*a")
ok(entSrc:find("LocalToWorld", 1, true) ~= nil,
   "подпись шкафа — плашка на корпусе, как просил владелец по автомату")
ok(entSrc:find("RotateAroundAxis(ang:Up(), 90)", 1, true) ~= nil,
   "тем же приёмом, что у терминалов")
ok(entSrc:find("ВНЕ ЗОНЫ ЖИЛЬЯ", 1, true) ~= nil,
   "шкаф, поставленный мимо квартиры, сам сообщает об ошибке установки")

local initSrc = assert(io.open("lua/entities/grm_home_locker/init.lua")):read("*a")
ok(initSrc:find("EnableMotion(false)", 1, true) ~= nil,
   "шкаф заморожен — мебель не должна ездить по квартире")
ok(initSrc:find("_grmNextUse", 1, true) ~= nil,
   "антиспам на E — окно не пересоздаётся каждый тик")

ok(isfunction(commands["grm_home_storage"]), "есть команда диагностики")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
