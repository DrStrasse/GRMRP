--[[ Живой прогон домашней кровати (заказ владельца 28.08).

     «Для жилья нужна энтити домашней кровати, которая будет точкой
      сохранения/входа/выхода — models/props/de_inferno/bed.mdl.»

     Проверяется:
       1) кровать принадлежит квартире, а не игроку;
       2) ТОЧКА ВХОДА: спавн у кровати, приоритетнее эвристики от двери;
       3) ТОЧКА СОХРАНЕНИЯ: лёг — место записано сразу, без автоснимка;
       4) ТОЧКА ВЫХОДА: вышел лёжа — вернулся туда же;
       5) права берутся у модуля жилья, своей копии нет;
       6) лежащий не ходит, но и не заперт намертво.

     Запуск: luajit tools/luatest/sim_home_bed.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function ErrorNoHalt() end
HUD_PRINTTALK = 3
MOVETYPE_WALK, MOVETYPE_NONE = 2, 0
NULL = nil
CurTime = function() return 100 end
local REALTIME = 1700000000
os.time = function() return REALTIME end
game = { GetMap = function() return "rp_city" end }

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function VecMT:Angle() return Angle(0, math.deg(math.atan2(self.y, self.x)), 0) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function VecMT.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function VecMT.__tostring(a) return ("(%.0f %.0f %.0f)"):format(a.x,a.y,a.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end
local function runAll(e,...) for _,f in pairs(hook._t[e] or {}) do f(...) end end

timer = { Simple=function(_,f) f() end, Create=function() end, Remove=function() end,
          Exists=function() return false end }
local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }
util = { AddNetworkString=function() end, IsValidModel=function() return true end }
net = setmetatable({}, { __index = function() return function() return "" end end })
file = { Exists=function() return false end, Read=function() return "" end, Write=function() end,
         CreateDir=function() end, IsDir=function() return true end }
local PLAYERS = {}
player = { GetAll=function() return PLAYERS end }
local WORLD = {}
ents = {
    GetAll = function() return WORLD end,
    FindByClass = function(c)
        local o = {}
        for _, e in ipairs(WORLD) do if e:GetClass() == c then o[#o+1] = e end end
        return o
    end,
}
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,
    GetBool=function() return d~="0" end, GetString=function() return tostring(d) end,
    GetInt=function() return math.floor(tonumber(d) or 0) end} end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
bit = { bor = function(a,b) return (a or 0)+(b or 0) end }

local NOTIFIED = {}
GRM = { Perf = { Players=function() return PLAYERS end } }
GRM.Notify = function(p,msg) NOTIFIED[#NOTIFIED+1] = { to=p, msg=msg } end
GRM.Identity = { CharacterKey = function(p) return isstring(p) and p or p._key end }

-- Недвижимость и жильё.
GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    IsInside = function(r,pos)
        if not istable(r.zone) then return false end
        local a,b = r.zone.mins, r.zone.maxs
        return pos.x>=a.x and pos.y>=a.y and pos.z>=a.z
           and pos.x<=b.x and pos.y<=b.y and pos.z<=b.z
    end,
    CanAdmin = function(p) return IsValid(p) and p._admin == true end,
    HasAccess = function(p,r) return r.ownerKey == p._key end,
    Save = function() end,
}
GRM.Doors = { IsDoor=function() return false end, GetDoorID=function() end,
              HasWarrant=function() return false end, HasPropertyWarrant=function() return false end }
GRM.Access = { Can=function() return false end }
GRM.Estate = { ZoneCenter=function(r)
    if not istable(r.zone) then return nil end
    local a,b=r.zone.mins,r.zone.maxs
    return Vector((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
end }

-- Мир: пол на z=0, стен нет (проверяем логику, а не трассировку).
MASK_PLAYERSOLID = 1
function util.TraceHull() return { Hit=false, StartSolid=false } end
function util.TraceLine(t)
    return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0) }
end

assert(loadfile("lua/autorun/sh_grm_housing.lua"))()
assert(loadfile("lua/autorun/sh_grm_home_bed.lua"))()
local HS, B = GRM.Housing, GRM.HomeBed

-- Запоминание точки: следим, вызывается ли и с какой срочностью.
local REMEMBERED = {}
GRM.SpawnPick = {
    Remember = function(ply, immediate)
        REMEMBERED[#REMEMBERED+1] = { ply = ply, immediate = immediate, pos = ply._pos }
        return true
    end,
}

-----------------------------------------------------------------------
local function mkPly(o)
    o = o or {}
    local said = {}
    local nw = { GRM_RPName = o.name or "Игрок" }
    return {
        _valid=true, _key=o.key or "1:char1", _pos=o.pos or Vector(0,0,0),
        _move=MOVETYPE_WALK, _said=said, _admin=o.admin==true,
        SteamID64=function() return "1" end,
        Nick=function() return o.name or "Игрок" end,
        GetPos=function(s) return s._pos end,
        SetPos=function(s,v) s._pos=Vector(v.x,v.y,v.z) end,
        SetMoveType=function(s,v) s._move=v end,
        GetMoveType=function(s) return s._move end,
        EyeAngles=function() return Angle(0,0,0) end,
        IsPlayer=function() return true end,
        InVehicle=function() return o.veh == true end,
        Alive=function() return o.dead ~= true end,
        PrintMessage=function(_,_,t) said[#said+1]=t end,
        GetNWBool=function(_,k,d) if nw[k]~=nil then return nw[k] end return d or false end,
        SetNWBool=function(_,k,v) nw[k]=v end,
        GetNWString=function(_,k,d) return nw[k] or d or "" end,
        _nw = nw,
    }
end

local function mkBed(pos, rec)
    local e
    e = {
        _valid=true, _pos=pos, _sleeper=nil, _linked=false, _homeName="",
        GetClass=function() return "grm_home_bed" end,
        GetPos=function(s) return s._pos end,
        GetAngles=function() return Angle(0,0,0) end,
        GetRight=function() return Vector(0,1,0) end,
        GetForward=function() return Vector(1,0,0) end,
        OBBMins=function() return Vector(-30,-20,0) end,
        OBBMaxs=function() return Vector(30,20,16) end,
        GetSleeper=function(s) return s._sleeper end,
        SetSleeper=function(s,v) s._sleeper=v end,
        GetLinked=function(s) return s._linked end,
        SetLinked=function(s,v) s._linked=v end,
        SetHomeName=function(s,v) s._homeName=v end,
        GetHomeName=function(s) return s._homeName end,
        UpdateLink=function(s)
            local r = B.PropertyOf(s)
            s._linked = istable(r)
            s._homeName = istable(r) and tostring(r.name or "") or ""
        end,
    }
    WORLD[#WORLD+1] = e
    return e
end

local flat = {
    id="flat1", name="Квартира 14", type="apartment",
    ownerType="character", ownerKey="1:char1", tenure="owned",
    sealed=false, rentUntil=0, doors={}, guests={},
    zone={mins=Vector(-200,-200,-50), maxs=Vector(200,200,200)},
}
GRM.Property.Records = { flat1 = flat }

local owner = mkPly({ key="1:char1", name="Хозяин", pos=Vector(0,0,0) })
local stranger = mkPly({ key="9:char1", name="Чужой", pos=Vector(0,0,0) })
PLAYERS = { owner, stranger }

-----------------------------------------------------------------------
print("\n=== 1. МОДЕЛЬ И РЕГИСТРАЦИЯ ===")
-----------------------------------------------------------------------
local shared = readf("lua/entities/grm_home_bed/shared.lua")
ok(shared:find("models/props/de_inferno/bed.mdl", 1, true) ~= nil,
   "модель ровно та, что заказал владелец")
ok(shared:find("ENT.ModelFallback", 1, true) ~= nil,
   "есть запасная модель — иначе была бы ошибка-ERROR в квартире")

local perm = readf("lua/autorun/sh_grm_perm_entities.lua")
ok(perm:find("grm_home_bed", 1, true) ~= nil,
   "кровать в PERM_CLASSES — переживёт рестарт карты")

local initSrc = readf("lua/entities/grm_home_bed/init.lua")
ok(initSrc:find("EnableMotion(false)", 1, true) ~= nil,
   "кровать заморожена — мебель не ездит по комнате")
ok(initSrc:find("_grmNextUse", 1, true) ~= nil,
   "антиспам на E — лечь/встать не дёргается каждый тик")

-----------------------------------------------------------------------
print("\n=== 2. ПРИНАДЛЕЖИТ КВАРТИРЕ, А НЕ ИГРОКУ ===")
-----------------------------------------------------------------------
local bed = mkBed(Vector(50, 0, 0))
ok(B.PropertyOf(bed) == flat, "кровать определяет квартиру по зоне")
ok(B.BedOf(flat) == bed, "и квартира находит свою кровать")

local outside = mkBed(Vector(9999, 9999, 0))
ok(B.PropertyOf(outside) == nil, "кровать вне зоны ничьей квартире не принадлежит")
outside:UpdateLink()
ok(outside:GetLinked() == false, "и сама сообщает, что не привязана")

bed:UpdateLink()
ok(bed:GetLinked() == true, "а привязанная — что работает")
ok(bed:GetHomeName() == "Квартира 14", "с названием жилья", bed:GetHomeName())

-----------------------------------------------------------------------
print("\n=== 3. ТОЧКА ВХОДА ===")
-----------------------------------------------------------------------
local pos, ang = B.SpawnPointFor(flat)
ok(pos ~= nil, "точка входа от кровати найдена")
ok(pos and pos ~= bed:GetPos(),
   "ИСПРАВЛЕНО: игрок встаёт РЯДОМ с кроватью, а не внутри модели",
   tostring(pos))
ok(pos and math.abs(pos.y - bed:GetPos().y) > 10,
   "смещение сбоку от кровати", pos and pos.y)
ok(ang ~= nil, "и угол задан — игрок смотрит на кровать")

--[[ Главное: кровать должна быть ПРИОРИТЕТНЕЕ эвристики «от двери» и
     даже ручной админской точки. Она явная и её видит сам игрок. ]]
local hp, hang, how = HS.SpawnPoint(flat)
ok(how == "bed", "ИСПРАВЛЕНО: кровать — приоритетный источник точки входа", how)

flat.housingSpawn = { x = 111, y = 222, z = 0, yaw = 90 }
local _, _, how2 = HS.SpawnPoint(flat)
ok(how2 == "bed", "кровать важнее даже ручной точки админа", how2)
flat.housingSpawn = nil

-- Без кровати работает прежняя логика.
WORLD = {}
local _, _, how3 = HS.SpawnPoint(flat)
ok(how3 ~= "bed", "без кровати точка ищется по-старому — старое не сломано", how3)
bed = mkBed(Vector(50, 0, 0))

-----------------------------------------------------------------------
print("\n=== 4. СОН: ТОЧКА СОХРАНЕНИЯ ===")
-----------------------------------------------------------------------
REMEMBERED = {}
NOTIFIED = {}
ok(B.LieDown(owner, bed) == true, "владелец лёг")
ok(bed:GetSleeper() == owner, "кровать знает, кто в ней")
ok(owner.GRMBedEnt == bed, "и игрок знает свою кровать")
ok(owner._move == MOVETYPE_NONE, "лежащий не двигается")

ok(#REMEMBERED == 1,
   "ИСПРАВЛЕНО: место записано СРАЗУ при укладывании", #REMEMBERED)
ok(REMEMBERED[1] and REMEMBERED[1].immediate == true,
   "и немедленно на диск — лёг и закрыл игру, точка не потеряна")

-- Занято.
ok(B.LieDown(stranger, bed) == false, "вторым в ту же кровать не лечь")

-----------------------------------------------------------------------
print("\n=== 5. ПОДЪЁМ ===")
-----------------------------------------------------------------------
ok(B.GetUp(owner) == true, "владелец встал")
ok(bed:GetSleeper() == nil, "кровать освободилась")
ok(owner.GRMBedEnt == nil, "привязка снята")
ok(owner._move == MOVETYPE_WALK, "движение вернулось")
ok(owner._pos ~= bed:GetPos(), "встал рядом, а не в кровати")

ok(B.GetUp(owner) == true, "повторный подъём безопасен")
ok(B.IsSleeping(owner) == false, "и не спит")

-- Теперь место свободно для другого.
ok(B.LieDown(stranger, bed) == false,
   "но чужой всё равно не ляжет — это не его жильё")

-----------------------------------------------------------------------
print("\n=== 6. ПРАВА БЕРУТСЯ У МОДУЛЯ ЖИЛЬЯ ===")
-----------------------------------------------------------------------
local bedSrc = readf("lua/autorun/sh_grm_home_bed.lua")
ok(bedSrc:find("HS.CanEnter(ply, rec)", 1, true) ~= nil,
   "кровать спрашивает GRM.Housing.CanEnter, а не заводит свой список ключей")

-- Опечатка закрывает и кровать.
flat.sealed = true
ok(B.LieDown(owner, bed) == false, "в опечатанной квартире не поспишь")
flat.sealed = false
ok(B.LieDown(owner, bed) == true, "печать сняли — снова можно")
B.GetUp(owner)

-- Просроченная аренда.
flat.tenure = "rent" flat.rentUntil = REALTIME - 10
ok(B.LieDown(owner, bed) == false, "после конца аренды кровать чужая")
flat.tenure = "owned" flat.rentUntil = 0

-- Арест.
owner._nw.GRM_Arrested = true
ok(B.LieDown(owner, bed) == false, "под арестом спать нельзя")
owner._nw.GRM_Arrested = nil

-- Кровать вне жилья.
ok(B.LieDown(owner, outside) == false, "на кровать вне квартиры не лечь")

-----------------------------------------------------------------------
print("\n=== 7. ТОЧКА ВЫХОДА ===")
-----------------------------------------------------------------------
REMEMBERED = {}
B.LieDown(owner, bed)
REMEMBERED = {}
runAll("PlayerDisconnected", owner)
ok(#REMEMBERED == 1,
   "ИСПРАВЛЕНО: вышел лёжа — место выхода записано")
ok(REMEMBERED[1] and REMEMBERED[1].immediate == true,
   "немедленно, а не автоснимком через полминуты")
ok(B.IsSleeping(owner) == false, "и игрок поднят, чтобы не остаться в лимбе состояния")

-----------------------------------------------------------------------
print("\n=== 8. ЛЕЖАЩИЙ НЕ ЗАПЕРТ НАМЕРТВО ===")
-----------------------------------------------------------------------
--[[ Freeze() запирает игрока средствами движка: любой чужой код,
     снявший его, рассинхронил бы состояние навсегда. Поэтому ввод
     режем через StartCommand, как в социальных анимациях. ]]
--[[ Ищем ВЫЗОВ, а не любое упоминание: в комментарии рядом объяснено,
     почему Freeze не годится, и это не должно считаться ошибкой. ]]
ok(bedSrc:find("\n        ply:Freeze(", 1, true) == nil
   and bedSrc:find("\n    ply:Freeze(", 1, true) == nil,
   "ply:Freeze НЕ вызывается — состояние не рассинхронится")

--[[ Хук живёт внутри блока `if SERVER`, поэтому закрывается с отступом:
     прежний шаблон его не находил. ]]
local hold = bedSrc:match('"GRM_HomeBed_Hold".-\n    end%)')
ok(hold ~= nil, "ввод режется через StartCommand")
ok(hold and hold:find("cmd:ClearMovement()", 1, true) ~= nil, "движение обнуляется")
ok(hold and hold:find("SetViewAngles", 1, true) == nil,
   "камеру не трогаем — осмотреться лёжа можно")

-- Смерть и респавн поднимают.
B.LieDown(owner, bed)
runAll("PlayerDeath", owner)
ok(B.IsSleeping(owner) == false, "смерть поднимает — лежать мёртвым нельзя")

B.LieDown(owner, bed)
runAll("PlayerSpawn", owner)
ok(B.IsSleeping(owner) == false, "и респавн тоже")

-- Кровать убрали из-под лежащего.
B.LieDown(owner, bed)
ok(B.IsSleeping(owner) == true, "лежит")
local onRemove = initSrc:match("function ENT:OnRemove%(%).-\nend")
ok(onRemove and onRemove:find("B.GetUp(sleeper)", 1, true) ~= nil,
   "удаление кровати поднимает лежащего — иначе он замёрзнет навсегда")
B.GetUp(owner)

-----------------------------------------------------------------------
print("\n=== 9. КЛИЕНТСКАЯ ЧАСТЬ И ИНТЕГРАЦИЯ ===")
-----------------------------------------------------------------------
local clSrc = readf("lua/entities/grm_home_bed/cl_init.lua")
ok(clSrc:find("LocalToWorld", 1, true) ~= nil,
   "подпись — плашка на корпусе, а не текст в воздухе")
ok(clSrc:find("RotateAroundAxis(ang:Up(), 90)", 1, true) ~= nil,
   "тем же приёмом, что у шкафа и терминалов")
ok(clSrc:find("ВНЕ ЗОНЫ ЖИЛЬЯ", 1, true) ~= nil,
   "кровать мимо квартиры сама сообщает об ошибке установки")
ok(clSrc:find("ShouldDrawLocalPlayer", 1, true) ~= nil,
   "лежащий видит себя со стороны, а не из подушки")
ok(clSrc:find("320 * 320", 1, true) ~= nil,
   "далёкие кровати не рисуют подпись — бережём кадр")

ok(bedSrc:find("GRM_PropertyOwnerChanged", 1, true) ~= nil,
   "при смене хозяина квартиры привязка кровати обновляется")

local hub = readf("lua/autorun/sh_grm_admin_hub.lua")
ok(hub:find("Жильё: кровать", 1, true) ~= nil, "кровать есть в админ-хабе")
ok(isfunction(commands["grm_home_bed"]), "есть команда диагностики")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
