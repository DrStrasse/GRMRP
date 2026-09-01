--[[ Живой прогон клетки админ-меню: геометрия по габаритам модели,
     выравнивание по земле, «поводок», общий таймер сроков, возврат позиции,
     защита решёток от физгана/тулгана/урона и уборка после смерти.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_admin_jail.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
function SysTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isvector(v) return type(v) == "table" and v._vector == true end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function ErrorNoHalt() end
MASK_SOLID_BRUSHONLY, MOVETYPE_NONE, SOLID_VPHYSICS, COLLISION_GROUP_NONE = 1, 0, 6, 0
RENDERMODE_TRANSALPHA, HUD_PRINTCONSOLE = 4, 2

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _vector = true }
    local mt = {
        __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b)
            if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
            return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
        end,
        __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
        __index = {
            DistToSqr = function(self, o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end,
            Distance = function(self, o) return math.sqrt(self:DistToSqr(o)) end,
        },
    }
    return setmetatable(v, mt)
end

function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    function a:Forward()
        local rad = math.rad(self.y)
        return Vector(math.cos(rad), math.sin(rad), 0)
    end
    return a
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Remove = function(name, id) if hooks[name] then hooks[name][id] = nil end end,
    Run = function(name, ...)
        for _, fn in pairs(hooks[name] or {}) do
            local r = fn(...)
            if r ~= nil then return r end
        end
    end,
    GetTable = function() return hooks end,
}
local timers = {}
timer = {
    Create = function(id, delay, reps, fn) timers[id] = fn end,
    Simple = function(_, fn) fn() end,
    Remove = function(id) timers[id] = nil end,
    Exists = function(id) return timers[id] ~= nil end,
}
concommand = { Add = function() end }
net = { Receive = function() end, Start = function() end, WriteTable = function() end,
        WriteString = function() end, WriteBool = function() end, Send = function() end,
        Broadcast = function() end }
util = {
    AddNetworkString = function() end,
    TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end,
    TraceLine = function(t)
        -- «Пол» на высоте 0: клетка обязана вставать на землю.
        return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0) }
    end,
}
file = { Exists = function() return false end, Read = function() return "" end,
         Write = function() end, IsDir = function() return true end, CreateDir = function() end }
CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
GetConVar = CreateConVar
bit = { bor = function() return 0 end }
FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED = 1, 2, 4

-- ── мир ─────────────────────────────────────────────────────────────
local SPAWNED = {}
local function mkEnt(class)
    local e = { _valid = true, _class = class, pos = Vector(0, 0, 0), ang = Angle(0, 0, 0),
        moveType = nil, solid = nil, collision = nil }
    function e:SetModel(m) self.model = m end
    function e:GetModel() return self.model end
    function e:Spawn() self.spawned = true end
    function e:SetPos(p) self.pos = p end
    function e:GetPos() return self.pos end
    function e:SetAngles(a) self.ang = a end
    function e:GetAngles() return self.ang end
    function e:SetMoveType(v) self.moveType = v end
    function e:SetSolid(v) self.solid = v end
    function e:SetCollisionGroup(v) self.collision = v end
    function e:GetClass() return self._class end
    function e:Remove() self._valid = false end
    function e:OBBMins() return Vector(-64, -4, 0) end
    function e:OBBMaxs() return Vector(64, 4, 96) end
    function e:GetPhysicsObject() return { _valid = true, EnableMotion = function() end } end
    SPAWNED[#SPAWNED + 1] = e
    return e
end
ents = { Create = function(class) return mkEnt(class) end, FindByClass = function() return {} end,
         GetAll = function() return SPAWNED end }

local ALL = {}
player = { GetAll = function() return ALL end }

local function mkPlayer(nick, x)
    local p = { _valid = true, nick = nick, pos = Vector(x or 0, 0, 40), chat = {}, nw = {} }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID64() return "76561190000000001" end
    function p:IsSuperAdmin() return true end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetPos(v) self.pos = v end
    function p:GetPos() return self.pos end
    function p:SetVelocity() end
    function p:GetVelocity() return Vector(0, 0, 0) end
    function p:Freeze(v) self.frozen = v end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:GodEnable() end
    function p:SetRenderMode() end
    function p:SetColor() end
    ALL[#ALL + 1] = p
    return p
end

GRM = { Identity = {}, Perf = {}, Admin = {}, Audit = { Write = function() end } }
GRM.Identity.CharacterKey = function(p) return IsValid(p) and p:SteamID64() .. ":char1" or "" end
GRM.Notify = function(p, msg) if IsValid(p) then p:ChatPrint(msg) end end
GRM.Admin.Can = function() return true end
GRM.Admin.Net = { ACT = "GRM_Admin_Act", RESULT = "GRM_Admin_Result", SYNC = "GRM_Admin_Sync" }
GRM.Admin.Result = function() end
GRM.Admin.PlayerRows = function() return {} end
GRM.Admin.CanTarget = function() return true end

assert(loadfile("lua/autorun/server/sv_grm_admin_actions.lua"))()
local AD = GRM.Admin
local A = AD.Actions

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function bars(ply)
    local n = 0
    for _, b in ipairs(ply.GRM_AdminJailBars or {}) do if IsValid(b) then n = n + 1 end end
    return n
end

local admin = mkPlayer("Админ", 0)
local target = mkPlayer("Нарушитель", 300)
target.pos = Vector(300, 0, 55)   -- стоит выше «пола»

print("\n=== 1. ПОСТРОЙКА КЛЕТКИ ===")
local okJail, msg = A.jail.fn(admin, target, { seconds = 60 })
ok(okJail == true, "команда «Клетка» отработала", tostring(msg))
ok(target.GRM_AdminJailed == true, "игрок помечен как в клетке")
ok(bars(target) == 4, "поставлены четыре стенки", bars(target))
ok(target.GRM_AdminJailCenter ~= nil and target.GRM_AdminJailCenter.z <= 5,
    "клетка выровнена по земле, а не висит в воздухе",
    target.GRM_AdminJailCenter and target.GRM_AdminJailCenter.z)
ok(target:GetPos():DistToSqr(target.GRM_AdminJailCenter) < 1,
    "игрок поставлен в центр клетки, а не внутрь стенки")
ok(isvector(target.GRM_AdminJailReturn) and target.GRM_AdminJailReturn.z == 55,
    "прежняя позиция запомнена для возврата")

print("\n=== 2. ГЕОМЕТРИЯ ПО ГАБАРИТАМ МОДЕЛИ ===")
local center = target.GRM_AdminJailCenter
local half = 128 * 0.5 -- ширина модели-заглушки из OBB
local offsets = {}
for _, b in ipairs(target.GRM_AdminJailBars) do
    offsets[#offsets + 1] = math.floor(Vector(b.pos.x, b.pos.y, center.z):Distance(center) + 0.5)
end
table.sort(offsets)
ok(offsets[1] == offsets[#offsets], "все стенки на одинаковом расстоянии от центра",
    table.concat(offsets, "/"))
ok(offsets[1] >= half, "расстояние взято из габаритов модели — стенки стыкуются без щелей",
    offsets[1] .. " >= " .. half)
local mt = true
for _, b in ipairs(target.GRM_AdminJailBars) do
    if b.moveType ~= MOVETYPE_NONE or b.solid ~= SOLID_VPHYSICS then mt = false end
end
ok(mt, "решётки статичны и твёрдые")

print("\n=== 3. ЗАЩИТА РЕШЁТОК ===")
local bar = target.GRM_AdminJailBars[1]
ok(hook.Run("PhysgunPickup", admin, bar) == false, "решётку не поднять физганом")
ok(hook.Run("CanTool", admin, { Entity = bar }) == false, "по решётке не работает тулган")
ok(hook.Run("EntityTakeDamage", bar) == true, "решётка не ломается уроном")
ok(hook.Run("PlayerNoClip", target) == false, "из клетки не выйти ноклипом")
ok(hook.Run("PlayerNoClip", admin) == nil, "свободному игроку ноклип не запрещают")

print("\n=== 4. ПОВОДОК ===")
local watch = timers["GRM_Admin_JailWatch"]
ok(isfunction(watch), "надзор ведёт ОДИН общий таймер, а не таймер на каждого")
target.pos = Vector(center.x + 400, center.y, center.z)
NOW = NOW + 1
watch()
ok(target:GetPos():DistToSqr(center) < 1, "вышедшего за периметр возвращают в центр")
target.pos = Vector(center.x + 20, center.y, center.z)
NOW = NOW + 1
watch()
ok(target:GetPos().x == center.x + 20, "внутри клетки игрок ходит свободно")

print("\n=== 5. СРОК И ОСВОБОЖДЕНИЕ ===")
NOW = NOW + 30
watch()
ok(target.GRM_AdminJailed == true, "до конца срока клетка держит")
NOW = NOW + 40
watch()
ok(target.GRM_AdminJailed == nil, "по истечении срока освобождает")
ok(bars(target) == 0, "решётки убраны")
ok(target:GetPos().z == 55, "игрок возвращён на прежнее место", target:GetPos().z)

print("\n=== 6. ПОВТОРНОЕ ПРИМЕНЕНИЕ И УБОРКА ===")
A.jail.fn(admin, target, { seconds = 60 })
ok(target.GRM_AdminJailed == true, "посадили снова")
local okRelease = A.jail.fn(admin, target, {})
ok(okRelease == true and target.GRM_AdminJailed == nil, "повторное нажатие выпускает")
ok(bars(target) == 0, "решётки убраны при досрочном освобождении")

A.jail.fn(admin, target, { seconds = 60 })
hook.Run("PlayerDeath", target)
ok(target.GRM_AdminJailed == nil and bars(target) == 0, "смерть в клетке не оставляет решётки")

A.jail.fn(admin, target, { seconds = 60 })
hook.Run("PlayerDisconnected", target)
ok(bars(target) == 0, "выход из игры не оставляет решётки на карте")

print("\n=== 7. ГРАНИЦЫ СРОКА ===")
A.jail.fn(admin, target, { seconds = 99999 })
ok(target.GRM_AdminJailUntil - NOW <= 3600, "срок зажат сверху часом",
    target.GRM_AdminJailUntil - NOW)
AD.ReleaseJail(target)
A.jail.fn(admin, target, { seconds = 1 })
ok(target.GRM_AdminJailUntil - NOW >= 10, "срок зажат снизу десятью секундами",
    target.GRM_AdminJailUntil - NOW)
AD.ReleaseJail(target)

print(("\nADMIN JAIL: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
