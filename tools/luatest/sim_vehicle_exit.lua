--[[ Живой прогон антистака транспорта: игрока не сталкивает корпусом,
     при выходе его ставит сбоку от МАШИНЫ (а не от сиденья) на заданное
     смещение, распознаются simfphys/LVS.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_vehicle_exit.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt() end
MOVETYPE_NOCLIP, MOVETYPE_WALK, MASK_PLAYERSOLID = 8, 2, 33636363
COLLISION_GROUP_PLAYER, COLLISION_GROUP_DEBRIS_TRIGGER = 5, 1

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _vector = true }
    return setmetatable(v, {
        __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b)
            if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
            return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
        end,
        __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
        __index = {
            Dot = function(self, o) return self.x * o.x + self.y * o.y + self.z * o.z end,
            DistToSqr = function(self, o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end,
            Distance = function(self, o) return math.sqrt(self:DistToSqr(o)) end,
            Length = function(self) return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end,
            Length2D = function(self) return math.sqrt(self.x ^ 2 + self.y ^ 2) end,
            LengthSqr = function(self) return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end,
            Length2DSqr = function(self) return self.x ^ 2 + self.y ^ 2 end,
            Normalize = function(self) return self end,
            Angle = function() return Angle(0, 0, 0) end,
            GetNormalized = function(self)
                local l = self:Length()
                if l == 0 then return Vector(0, 0, 0) end
                return Vector(self.x / l, self.y / l, self.z / l)
            end,
        },
    })
end
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    function a:Forward() local rad = math.rad(self.y) return Vector(math.cos(rad), math.sin(rad), 0) end
    function a:Right() local rad = math.rad(self.y - 90) return Vector(math.cos(rad), math.sin(rad), 0) end
    function a:Up() return Vector(0, 0, 1) end
    return a
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...)
        for _, fn in pairs(hooks[n] or {}) do local r = fn(...) if r ~= nil then return r end end
    end,
    GetTable = function() return hooks end,
}
local pending = {}
timer = {
    Create = function() end,
    Simple = function(_, fn) pending[#pending + 1] = fn end,
    Remove = function() end, Exists = function() return false end,
}
local function runTimers()
    local list = pending pending = {}
    for _, fn in ipairs(list) do fn() end
end
concommand = { Add = function() end }
net = { Receive = function() end }
CreateConVar = function() return { GetBool = function() return true end, GetFloat = function() return 0 end,
    GetInt = function() return 0 end, GetString = function() return "" end } end
GetConVar = CreateConVar

-- Мир: пол на z=0, никаких препятствий (кроме заданных «стен»)
local WALLS = {}
util = {
    TraceLine = function(t)
        return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0), HitNormal = Vector(0, 0, 1) }
    end,
    TraceHull = function(t)
        for _, wall in ipairs(WALLS) do
            if t.start:DistToSqr(wall) < 60 * 60 then return { StartSolid = true } end
        end
        return { StartSolid = false }
    end,
}
local ENTS = {}
ents = {
    FindInSphere = function(pos, r)
        local out = {}
        for _, e in ipairs(ENTS) do
            if IsValid(e) and e:GetPos():DistToSqr(pos) <= r * r then out[#out + 1] = e end
        end
        return out
    end,
    GetAll = function() return ENTS end,
    FindByClass = function() return {} end,
}
local ALL = {}
player = { GetAll = function() return ALL end }
GRM = { Perf = { Players = function() return ALL end } }

local function mkEnt(class, pos, ang, fields)
    local e = { _valid = true, _class = class, pos = pos or Vector(0, 0, 0), ang = ang or Angle(0, 0, 0) }
    for k, v in pairs(fields or {}) do e[k] = v end
    function e:GetClass() return self._class end
    function e:GetPos() return self.pos end
    function e:SetPos(p) self.pos = p end
    function e:GetAngles() return self.ang end
    function e:EntIndex() return self._index or 1 end
    function e:IsPlayer() return false end
    function e:IsVehicle() return self._isVehicle == true end
    function e:GetParent() return self._parent end
    function e:OBBMins() return self._mins or Vector(-120, -60, 0) end
    function e:OBBMaxs() return self._maxs or Vector(120, 60, 80) end
    function e:OBBCenter() return Vector(0, 0, 40) end
    function e:LocalToWorld(v) return self.pos + v end
    function e:WorldToLocal(v) return v - self.pos end
    function e:GetRight() return self.ang:Right() end
    function e:GetForward() return self.ang:Forward() end
    function e:GetUp() return Vector(0, 0, 1) end
    function e:GetVelocity() return Vector(0, 0, 0) end
    function e:GetPhysicsObject() return { _valid = true, GetMass = function() return 1000 end } end
    function e:GetChildren() return {} end
    ENTS[#ENTS + 1] = e
    e._index = #ENTS + 10
    return e
end

local function mkPlayer(pos)
    local p = mkEnt("player", pos or Vector(0, 0, 0))
    p._isPlayer = true
    function p:IsPlayer() return true end
    function p:IsVehicle() return false end
    function p:InVehicle() return self._inVehicle == true end
    function p:GetMoveType() return self._movetype or MOVETYPE_WALK end
    function p:SetLocalVelocity() end
    function p:GetCollisionGroup() return COLLISION_GROUP_PLAYER end
    function p:SetCollisionGroup(v) self._cg = v end
    function p:OBBMins() return Vector(-16, -16, 0) end
    function p:OBBMaxs() return Vector(16, 16, 72) end
    ALL[#ALL + 1] = p
    return p
end

assert(loadfile("lua/autorun/zz_grm_vehicle_antistuck.lua"))()
local AS = GRM.VehicleAntiStuck

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

-- БТР: корпус 240×120, сиденье-под внутри корпуса
local btr = mkEnt("simfphys_btr80", Vector(0, 0, 0), Angle(0, 0, 0), { IsSimfphysCar = true })
local seat = mkEnt("prop_vehicle_prisoner_pod", Vector(0, 0, 30), Angle(0, 0, 0),
    { _isVehicle = true, _parent = btr, _mins = Vector(-20, -20, 0), _maxs = Vector(20, 20, 40) })
local ply = mkPlayer(Vector(0, 20, 0))

print("\n=== 1. РАСПОЗНАВАНИЕ ТРАНСПОРТА ===")
local collide = hooks["ShouldCollide"]["GRM_VehicleAntiStuck_PlayerVehicle"]
ok(isfunction(collide), "хук постоянного no-collide зарегистрирован")
ok(collide(ply, btr) == false, "игрок не сталкивается с корпусом simfphys_btr80 (был не распознан)")
ok(collide(btr, ply) == false, "порядок аргументов не важен")
ok(collide(ply, seat) == false, "с сиденьем тоже не сталкивается")
local prop = mkEnt("prop_physics", Vector(500, 0, 0))
ok(collide(ply, prop) == nil, "обычные пропы остаются как были")
ok(collide(prop, btr) == nil, "столкновения без игрока не трогаем")

local lvs = mkEnt("lvs_wheeldrive_car", Vector(900, 0, 0), Angle(0, 0, 0), { LVS = true })
ok(collide(ply, lvs) == false, "LVS тоже распознан")

print("\n=== 2. ВЫХОД СБОКУ ОТ КОРПУСА ===")
ok(AS.Config.SideExitOffset == 10, "смещение по умолчанию 10 юнитов", AS.Config.SideExitOffset)
local spot = AS.SideExitPos(ply, btr)
ok(spot ~= nil, "точка выхода найдена")
ok(spot and math.abs(spot.y) >= 60, "точка ЗА бортом корпуса, а не у сиденья", spot and spot.y)
ok(spot and spot.y > 0, "выпускает с той стороны, где игрок (слева остался слева)", spot and spot.y)

ply.pos = Vector(0, -20, 0)
local spotRight = AS.SideExitPos(ply, btr)
ok(spotRight and spotRight.y < 0, "с другой стороны — другой борт", spotRight and spotRight.y)

print("\n=== 3. ЗАНЯТАЯ СТОРОНА ===")
WALLS = { Vector(0, -86, 0) }
ply.pos = Vector(0, -20, 0)
local blocked = AS.SideExitPos(ply, btr)
ok(blocked ~= nil and blocked.y > 0, "если у борта стена — выпускает с другой стороны",
    blocked and blocked.y)
WALLS = { Vector(0, -86, 0), Vector(0, 86, 0), Vector(-136, 0, 0), Vector(136, 0, 0) }
ok(AS.SideExitPos(ply, btr) == nil, "если свободного места нет — не двигаем вообще")
WALLS = {}

print("\n=== 4. ВЫХОД ИЗ МАШИНЫ ===")
local leave = hooks["PlayerLeaveVehicle"]["GRM_VehicleAntiStuck_OnLeave"]
ok(isfunction(leave), "обработчик выхода на месте")
ply.pos = Vector(0, 10, 0)
ply._inVehicle = false
leave(ply, seat)
runTimers()
ok(math.abs(ply.pos.y) >= 60, "после выхода игрок стоит у борта, а не в корпусе", ply.pos.y)

ply.pos = Vector(0, 10, 0)
ply._movetype = MOVETYPE_NOCLIP
leave(ply, seat)
runTimers()
ok(ply.pos.y == 10, "в ноклипе админа не двигаем", ply.pos.y)
ply._movetype = MOVETYPE_WALK

print("\n=== 5. НАСТРОЙКИ ===")
ok(AS.Config.AlwaysNoCollideWithVehicles == true, "постоянное отсутствие столкновения включено")
AS.Config.AlwaysNoCollideWithVehicles = false
ok(collide(ply, btr) == nil, "настройкой можно вернуть прежнее поведение")
AS.Config.AlwaysNoCollideWithVehicles = true
AS.Config.SideExitOnLeave = false
-- Ставим игрока ЗАВЕДОМО снаружи: иначе сработает старая спасалка от
-- застревания (она отдельная и отключается своими настройками).
ply.pos = Vector(0, 300, 0)
leave(ply, seat)
runTimers()
ok(ply.pos.y == 300, "боковой выход отключается настройкой", ply.pos.y)
AS.Config.SideExitOnLeave = true

print(("\nVEHICLE EXIT: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
