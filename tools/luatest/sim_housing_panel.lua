--[[ Живой прогон окна квартиры (жильё, фаза 4 — завершающая).

     ЗАЧЕМ ФАЗА. Всё нужное жильцу было разбросано: ключи и коммуналка в
     /property (окно со списком ВСЕХ объектов карты и админ-полями),
     журнал в /housing_log, шкаф на самом шкафу. Игрок не знал, где что.

     ГЛАВНОЕ, ЧТО ЧИНИТСЯ: аренду НЕЛЬЗЯ БЫЛО ПРОДЛИТЬ. Она молча
     истекала по таймеру биллинга, человека выселяло вместе с ключами и
     доступом к шкафу. Единственным «продлением» было успеть арендовать
     заново раньше других.

     Проверяется:
       1) продление аренды и что оно НЕ сжигает оплаченный остаток;
       2) предупреждение за сутки до конца;
       3) панель не дублирует правила доступа, а зовёт property;
       4) ключ выдаётся по имени соседа, а не вводом CharacterKey;
       5) чужой не управляет чужой квартирой;
       6) данные всех трёх прошлых фаз собраны в одном пакете.

     Запуск: luajit tools/luatest/sim_housing_panel.lua ]]

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
function VecMT:Normalize() return self end
function VecMT:Angle() return Angle(0,0,0) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt() end
HUD_PRINTTALK = 3
MASK_PLAYERSOLID = 33570819
FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
bit = { bor = function(a,b) return a+b end }
CurTime = function() return 100 end

local REALTIME = 1700000000
os.time = function() return REALTIME end

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end

timer = { _c = {} }
function timer.Create(id,_,_,f) timer._c[id]=f end
function timer.Simple(_,f) f() end
function timer.Remove(id) timer._c[id]=nil end
function timer.Exists(id) return timer._c[id]~=nil end
local function tick(id) if timer._c[id] then timer._c[id]() end end

local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }

local SENT = {}
local buf
net = {
    AddNetworkString=function() end,
    Start=function(n) buf={name=n,args={}} end,
    WriteEntity=function(v) table.insert(buf.args,v) end,
    WriteTable=function(v) table.insert(buf.args,v) end,
    WriteString=function(v) table.insert(buf.args,v) end,
    WriteFloat=function(v) table.insert(buf.args,v) end,
    WriteUInt=function(v) table.insert(buf.args,v) end,
    WriteBool=function(v) table.insert(buf.args,v) end,
    Send=function(p) buf.to=p table.insert(SENT,buf) end,
    Receive=function(n,f) net["_h_"..n]=f end,
}
util = { AddNetworkString=function() end, TableToJSON=function() return "J" end,
         JSONToTable=function() return {} end, IsValidModel=function() return true end }
local FS = { data={}, writes=0 }
file = { Exists=function(n) return FS.data[n]~=nil end, Read=function(n) return FS.data[n] or "" end,
         Write=function(n,t) FS.data[n]=t FS.writes=FS.writes+1 end,
         CreateDir=function() end, IsDir=function() return true end }
local PLAYERS = {}
player = { GetAll=function() return PLAYERS end }
game = { GetMap=function() return "rp_city" end, GetWorld=function() return {} end }
ents = { GetAll=function() return {} end, FindByClass=function() return {} end }
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,
    GetBool=function() return d~="0" end, GetString=function() return tostring(d) end,
    GetInt=function() return math.floor(tonumber(d) or 0) end} end

local NOTIFIED = {}
GRM = { Perf = { Players=function() return PLAYERS end } }
GRM.Notify = function(p,msg) NOTIFIED[#NOTIFIED+1]={to=p,msg=msg} end

-- Деньги.
local WALLET = {}
GRM.HasMoney = function(p,n) return (WALLET[p] or 0) >= n end
GRM.TakeMoney = function(p,n) WALLET[p] = (WALLET[p] or 0) - n end
GRM.Audit = { Write=function() end }
GRM.Persistence = {
    LoadJSON=function(_,d) return d end,
    SaveJSON=function() return true end,
}
GRM.Utf8Sub = function(s,n) return string.sub(s,1,n) end
Factions = {}

local ONLINE = {}
GRM.Identity = {
    CharacterKey=function(p) return isstring(p) and p or p._key end,
    IsCharacterKey=function(k) return isstring(k) and k:match("^%d+:char[1-3]$")~=nil end,
    ResolveCharacter=function(k) return ONLINE[k] end,
}
GRM.Doors = { IsDoor=function() return false end, GetDoorID=function() end,
              HasWarrant=function() return false end, HasPropertyWarrant=function() return false end,
              LockDoor=function() end, GetRecord=function() end, SaveDoors=function() end }
GRM.Access = { Can=function(p,c) return IsValid(p) and p._caps and p._caps[c]==true end,
               Register=function() end }
GRM.Boot = nil

local function mkPly(o)
    o = o or {}
    local said = {}
    return {
        _valid=true, _key=o.key or "1:char1", _admin=o.admin==true,
        _caps=o.caps or {}, _pos=o.pos or Vector(0,0,0), _said=said,
        _nw={ GRM_RPName=o.name or "" },
        SteamID64=function() return (o.key or "1:char1"):match("^(%d+)") end,
        SteamID=function() return "STEAM_0:0:1" end,
        Nick=function() return o.nick or "tester" end,
        GetPos=function(s) return s._pos end,
        SetPos=function(s,v) s._pos=v end,
        EyeAngles=function() return Angle(0,0,0) end,
        GetEyeTrace=function() return { Entity=o.aim } end,
        IsPlayer=function() return true end,
        IsSuperAdmin=function() return o.admin==true end,
        PrintMessage=function(_,_,t) said[#said+1]=t end,
        ChatPrint=function(_,t) said[#said+1]=t end,
        GetNWString=function(s,k,d) return s._nw[k] or d or "" end,
        GetNWBool=function(_,_,d) return d or false end,
        SetNWBool=function() end, SetNWString=function() end,
    }
end

-- Ядро грузится первым и на живом сервере (sh_01_grm_core.lua), и здесь:
-- модули ниже берут из него канон GRM.CharKey (§5.2.6, одна реализация).
assert(loadfile("lua/autorun/sh_01_grm_core.lua"))()
assert(loadfile("lua/autorun/sh_grm_property.lua"))()
local P = GRM.Property

-- Модули жилья поверх property.
assert(loadfile("lua/autorun/sh_grm_housing.lua"))()
assert(loadfile("lua/autorun/sh_grm_housing_search.lua"))()
assert(loadfile("lua/autorun/sh_grm_housing_panel.lua"))()
local HS, SR, HP = GRM.Housing, GRM.HousingSearch, GRM.HousingPanel

-- Шкаф-заглушка (фаза 2 в этом стенде не грузим целиком).
GRM.HomeStorage = {
    MaxSlots = 30, MaxWeight = 200,
    _slots = {},
    SlotsFor = function(rec) GRM.HomeStorage._slots[rec.id] = GRM.HomeStorage._slots[rec.id] or {} return GRM.HomeStorage._slots[rec.id] end,
    UsedSlots = function(s) local n=0 for _,v in pairs(s or {}) do if v and v.id then n=n+1 end end return n end,
    TotalWeight = function(s) local w=0 for _,v in pairs(s or {}) do w=w+(v.w or 0) end return w end,
}

local flat = P.Normalize({
    id="flat1", name="Квартира 14", type="apartment",
    ownerType="character", ownerKey="1:char1", ownerName="Иван Петров",
    tenure="rent", rentUntil=REALTIME + 3*86400, rentPrice=5000,
    utilityDebt=1500, utilityRate=500, sealed=false, doors={"d1"},
    zone={mins=Vector(-100,-100,-50),maxs=Vector(200,100,200)},
})
P.Records = { flat1 = flat }
P.Reindex()

local owner = mkPly({ key="1:char1", name="Иван Петров", pos=Vector(0,0,0) })
local buddy = mkPly({ key="5:char1", name="Пётр Сидоров", pos=Vector(50,0,0) })
local far   = mkPly({ key="6:char1", name="Далёкий", pos=Vector(5000,0,0) })
local stranger = mkPly({ key="9:char1", name="Чужой", pos=Vector(0,0,0) })
ONLINE["1:char1"]=owner ONLINE["5:char1"]=buddy ONLINE["6:char1"]=far ONLINE["9:char1"]=stranger
PLAYERS = { owner, buddy, far, stranger }
WALLET[owner] = 100000

-----------------------------------------------------------------------
print("\n=== 1. ГЛАВНОЕ: ПРОДЛЕНИЕ АРЕНДЫ ===")
-----------------------------------------------------------------------
--[[ Раньше действия extend_rent НЕ СУЩЕСТВОВАЛО. Аренда истекала, и
     человека выселяло вместе с ключами и шкафом. ]]
local propSrc = (function() local f=assert(io.open("lua/autorun/sh_grm_property.lua")) local s=f:read("*a") f:close() return s end)()
ok(propSrc:find('act=="extend_rent"', 1, true) ~= nil,
   "ИСПРАВЛЕНО: появилось действие extend_rent — аренду стало чем продлевать")

local before = flat.rentUntil
local money = WALLET[owner]
P.PanelAction(owner, { action="extend_rent", id="flat1" })
ok(flat.rentUntil > before, "аренда продлена", flat.rentUntil - before)
ok(flat.rentUntil == before + P.Config.RentSeconds,
   "ровно на один оплаченный период")
ok(WALLET[owner] == money - flat.rentPrice, "деньги списаны один раз",
   money - WALLET[owner])

--[[ Ключевая деталь: продление ОТ rentUntil, а не от «сейчас». Иначе
     досрочная оплата сжигала бы уже оплаченный остаток. ]]
local remaining = flat.rentUntil - REALTIME
ok(remaining > P.Config.RentSeconds,
   "оплаченный остаток НЕ сгорел при досрочном продлении", remaining)

-- Нет денег — нет продления.
WALLET[owner] = 10
local was = flat.rentUntil
P.PanelAction(owner, { action="extend_rent", id="flat1" })
ok(flat.rentUntil == was, "без денег аренда не продлевается")
WALLET[owner] = 100000

-- Купленное жильё продлевать нечего.
flat.tenure = "owned"
was = flat.rentUntil
P.PanelAction(owner, { action="extend_rent", id="flat1" })
ok(flat.rentUntil == was, "в собственности продление недоступно")
flat.tenure = "rent"

-- Чужой не продлевает чужое (и не платит за это).
local m2 = WALLET[stranger] or 0
WALLET[stranger] = 100000
was = flat.rentUntil
P.PanelAction(stranger, { action="extend_rent", id="flat1" })
ok(flat.rentUntil == was, "чужой не может продлить чужую аренду")
ok(WALLET[stranger] == 100000, "и денег у него не списали")

-----------------------------------------------------------------------
print("\n=== 2. ПРЕДУПРЕЖДЕНИЕ ОБ ОКОНЧАНИИ ===")
-----------------------------------------------------------------------
NOTIFIED = {}
flat.rentUntil = REALTIME + 3*86400
flat.rentWarned = nil
tick("GRM_Property_Billing")
ok(#NOTIFIED == 0, "за três суток до конца не беспокоим")

flat.rentUntil = REALTIME + 3600      -- час до конца
flat.rentWarned = nil
NOTIFIED = {}
tick("GRM_Property_Billing")
ok(#NOTIFIED > 0, "ИСПРАВЛЕНО: за сутки приходит предупреждение — раньше выселяло молча")
ok(NOTIFIED[1] and NOTIFIED[1].to == owner, "именно владельцу")
ok(NOTIFIED[1] and NOTIFIED[1].msg:find("заканчивается", 1, true) ~= nil,
   "и текст понятный", NOTIFIED[1] and NOTIFIED[1].msg)

-- Второй раз не спамим.
NOTIFIED = {}
tick("GRM_Property_Billing")
ok(#NOTIFIED == 0, "повторно не спамим — флаг rentWarned")

-- Продление сбрасывает флаг: срок новый, предупредим заново.
P.PanelAction(owner, { action="extend_rent", id="flat1" })
ok(flat.rentWarned == nil, "после продления предупреждение выдастся заново")

-- Выселение тоже уведомляет.
flat.rentUntil = REALTIME - 10
NOTIFIED = {}
tick("GRM_Property_Billing")
ok(flat.ownerType == "none", "просроченная аренда освобождает объект")
local told = false
for _, n in ipairs(NOTIFIED) do
    if n.to == owner and tostring(n.msg):find("закончилась", 1, true) then told = true end
end
ok(told, "ИСПРАВЛЕНО: о выселении сообщают, а не ставят перед фактом")

-- Возвращаем состояние.
flat.ownerType="character" flat.ownerKey="1:char1" flat.ownerName="Иван Петров"
flat.tenure="rent" flat.rentUntil=REALTIME+3*86400 flat.rentWarned=nil
flat.utilityDebt=1500 flat.guests={} flat.employees={} flat.tempKeys={}

-----------------------------------------------------------------------
print("\n=== 3. ПАНЕЛЬ НЕ ДУБЛИРУЕТ ПРАВИЛА ===")
-----------------------------------------------------------------------
ok(isfunction(P.PanelAction),
   "property публикует единую точку действий P.PanelAction")
local panelSrc = (function() local f=assert(io.open("lua/autorun/sh_grm_housing_panel.lua")) local s=f:read("*a") f:close() return s end)()
ok(panelSrc:find("P.PanelAction", 1, true) ~= nil,
   "панель зовёт её, а не пишет свою копию проверок")
ok(panelSrc:find("r.utilityDebt%s*=") == nil,
   "панель не меняет поля объекта напрямую — только через property")
ok(propSrc:find("function P._Act", 1, true) ~= nil,
   "ядро действий вынесено из net.Receive и переиспользуется")

-----------------------------------------------------------------------
print("\n=== 4. КЛЮЧ ПО СОСЕДУ, А НЕ ПО CharacterKey РУКАМИ ===")
-----------------------------------------------------------------------
local act = net["_h_" .. HP.NET.ACT]
ok(isfunction(act), "обработчик панели зарегистрирован")

-- Заглушка чтения пакета.
local PKT
net.ReadTable = function() return PKT end

PKT = { action="give_key", key="5:char1" }
act(0, owner)
local hasKey = false
for _, v in ipairs(flat.guests or {}) do if v.key == "5:char1" then hasKey = true end end
ok(hasKey, "ключ выдан соседу по одному клику, без ввода SteamID64")
ok(P.HasAccess(buddy, flat) == true, "и он реально открывает дверь")

-- Далёкому нельзя.
PKT = { action="give_key", key="6:char1" }
act(0, owner)
local farKey = false
for _, v in ipairs(flat.guests or {}) do if v.key == "6:char1" then farKey = true end end
ok(not farKey, "через полкарты ключ не выдать — только тому, кто рядом")

-- Забрать ключ.
PKT = { action="take_key", key="5:char1" }
act(0, owner)
ok(P.HasAccess(buddy, flat) == false, "ключ отобран, доступ пропал")

-- Чужой не управляет.
PKT = { action="give_key", key="5:char1" }
act(0, stranger)
ok(P.HasAccess(buddy, flat) == false, "чужой не раздаёт ключи от не своей квартиры")

-----------------------------------------------------------------------
print("\n=== 5. ОПЛАТА КОММУНАЛКИ ЧЕРЕЗ ПАНЕЛЬ ===")
-----------------------------------------------------------------------
flat.utilityDebt = 1500
WALLET[owner] = 100000
PKT = { action="pay" }
act(0, owner)
ok(flat.utilityDebt == 0, "долг погашен", flat.utilityDebt)
ok(WALLET[owner] == 100000 - 1500, "списано ровно по долгу")

-----------------------------------------------------------------------
print("\n=== 6. ДАННЫЕ ВСЕХ ФАЗ В ОДНОМ ПАКЕТЕ ===")
-----------------------------------------------------------------------
flat.utilityDebt = 700
flat.guests = { { key="5:char1", name="Пётр Сидоров" } }
flat.entryLog = { { at=REALTIME, kind="warrant", who="Сержант", warrantNo="42" } }
GRM.HomeStorage._slots["flat1"] = { [1] = { id="bread", w=5 } }

local d = HP.Data(owner, flat)
ok(d.name == "Квартира 14", "название объекта")
ok(d.isOwner == true, "видно, что игрок владелец")
ok(d.tenure == "rent" and d.rentUntil > 0, "фаза аренды на месте")
ok(d.utilityDebt == 700, "долг в пакете")
ok(#d.keys == 1 and d.keys[1].kind == "guest", "жильцы (фаза 4)", #d.keys)
ok(#d.log == 1 and d.log[1].warrantNo == "42", "журнал входов (фаза 3)")
ok(istable(d.storage) and d.storage.used == 1, "сводка шкафа (фаза 2)")
ok(isstring(d.spawnKind), "точка входа (фаза 1)", d.spawnKind)
ok(#d.neighbours > 0, "соседи для выдачи ключа", #d.neighbours)

-- Тот, у кого ключ уже есть, в кандидаты не попадает.
local dupe = false
for _, n in ipairs(d.neighbours) do if n.key == "5:char1" then dupe = true end end
ok(not dupe, "уже имеющий ключ не предлагается повторно")

-- Не владельцу лишнего не показываем.
local d2 = HP.Data(buddy, flat)
ok(d2.isOwner == false, "жилец видит, что он не владелец")
ok(#d2.neighbours == 0, "и списка кандидатов на ключ ему не дают")

-----------------------------------------------------------------------
print("\n=== 7. ЧЬЮ КВАРТИРУ ОТКРЫВАЕМ ===")
-----------------------------------------------------------------------
ok(HP.TargetOf(owner) == flat, "владелец видит свою")
owner._pos = Vector(9000, 9000, 0)
ok(HP.TargetOf(owner) == flat, "и вне дома тоже — это его жильё")
owner._pos = Vector(0, 0, 0)

stranger._pos = Vector(0, 0, 0)
ok(HP.TargetOf(stranger) == nil, "постороннему внутри чужой квартиры окно не даёт объект")

-- Жилец с ключом — даёт.
flat.guests = { { key="5:char1", name="Пётр" } }
buddy._pos = Vector(0, 0, 0)
ok(HP.TargetOf(buddy) == flat, "жилец с ключом видит квартиру, в которой стоит")

ok(HP.Open(stranger) == false, "без жилья окно не открывается")
SENT = {}
ok(HP.Open(owner) == true, "владельцу окно открывается")
ok(#SENT > 0 and SENT[#SENT].name == HP.NET.OPEN, "пакет ушёл клиенту")

-----------------------------------------------------------------------
print("\n=== 8. ФОРМАТ СРОКА ===")
-----------------------------------------------------------------------
--[[ Клиентская функция, но чистая — проверяем прямо тут через отдельную
     загрузку в CLIENT-режиме не нужна: логика тривиальна и вынесена. ]]
ok(propSrc:find("P.RentWarnBefore", 1, true) ~= nil,
   "порог предупреждения вынесен в настройку, а не зашит числом")
ok(propSrc:find("r.rentWarned=r.rentWarned==true or nil", 1, true) ~= nil,
   "флаг предупреждения нормализуется — переживёт сохранение")

-----------------------------------------------------------------------
print("\n=== 9. ИНТЕГРАЦИЯ ===")
-----------------------------------------------------------------------
ok(isfunction(commands["grm_home"]), "есть команда grm_home")
local hub = (function() local f=assert(io.open("lua/autorun/sh_grm_admin_hub.lua")) local s=f:read("*a") f:close() return s end)()
ok(hub:find("Жильё: окно квартиры", 1, true) ~= nil, "окно есть в админ-хабе")
ok(panelSrc:find("/home", 1, true) ~= nil, "команда /home документирована в модуле")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
