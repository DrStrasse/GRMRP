-- Симуляция v2: готовый набор работ — мусоровоз (маршрут) и таксист (посадка→назначение).
-- Проверяет генерацию offers с needVehicle/points, прохождение маршрута на транспорте.
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
local H = { hooks = {}, netrecv = {}, concommands = {}, timers = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end

function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false end
table.Count = function(t) local n = 0 for k in pairs(t or {}) do n = n + 1 end return n end

local VMT = {}
VMT.__index = function(self, k)
    if k == "Distance" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return math.sqrt(dx * dx + dy * dy + dz * dz) end end
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

util = { AddNetworkString = function() end, JSONToTable = function() return nil end, TableToJSON = function() return "{}" end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end, IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end }
timer = { Create = function(name, d, r, fn) if type(name) == "function" then fn = name end if fn then H.timers[tostring(name)] = fn end end,
          Simple = function(d, fn) if type(d) == "function" then d() elseif fn then fn() end end,
          Remove = function(name) H.timers[tostring(name)] = nil end }
ents = { FindByClass = function(c) return H.entsByClass and H.entsByClass[c] or {} end, Create = function(c) return nil end }
player = { GetAll = function() return H.players or {} end, GetBySteamID = function() return nil end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "gm_test" end }
function CurTime() return 1000 end
HUD_PRINTTALK = 3

local netlog = {}
net = { Start = function(m) netlog.cur = { msg = m } end,
        WriteString = function() end, WriteUInt = function() end, WriteInt = function() end,
        WriteBool = function() end, WriteTable = function() end, WriteVector = function() end,
        Send = function(tg) netlog.sent = netlog.sent or {} table.insert(netlog.sent, { msg = netlog.cur and netlog.cur.msg, to = "P" }) netlog.cur = nil end,
        Broadcast = function() end, SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
AddCSLuaFile = function() end

local function netInject(msg, fields)
    local i = 0
    net.ReadString = function() i = i + 1 return fields[i] end
    net.ReadUInt = function() i = i + 1 return fields[i] end
    net.ReadInt = function() i = i + 1 return fields[i] end
    net.ReadBool = function() i = i + 1 return fields[i] end
    net.ReadTable = function() i = i + 1 return fields[i] end
    local fn = H.netrecv[msg]
    assert(fn, "нет receiver для " .. tostring(msg))
    fn(0, H._curPly)
    return i
end

GRM = GRM or {}
GRM.Format = function(n) return tostring(n) .. " GRM" end
GRM.GiveMoney = function(ply, amount, reason) ply._bal = (ply._bal or 1000) + amount return true end
GRM.Notify = function(ply, msg, r, g, b) P("NOTIFY[" .. ply:Nick() .. "]: " .. tostring(msg)) end

Factions = {}

local function mkPly(nick, sid, s64, super)
    local p = {
        _pos = Vector(0, 0, 0), _bal = 1000, _inVeh = false,
        SteamID = function() return sid end,
        SteamID64 = function() return s64 end,
        Nick = function() return nick end,
        IsSuperAdmin = function() return super end,
        IsAdmin = function() return super end,
        IsPlayer = function() return true end,
        Alive = function() return true end,
        InVehicle = function(self) return self._inVeh == true end,
        GetPos=function(self)return self._pos end,GetVehicle=function(self)return self._veh end,
        GetNWString = function() return "" end,
        PrintMessage = function(_, ch, txt) P("CHAT[" .. nick .. "]: " .. tostring(txt)) end,
        GetEyeTrace = function() return {} end,
    }
    return p
end

local worker = mkPly("Водила", "STEAM_0:2:222", "76000000000000222", false)
H.players = { worker }

local center = { GetPos = function() return Vector(0, 0, 0) end, EntIndex = function() return 7 end, GetClass = function() return "grm_jobcenter" end }
local function depot(x, y, z) return { GetPos = function() return Vector(x, y, z) end, GetClass = function() return "grm_depot" end } end
H.entsByClass = {
    grm_jobcenter = { center },
    grm_depot = { depot(2000, 0, 0), depot(-1500, 500, 0), depot(500, 2000, 0), depot(-800, -1200, 0) },
}

SERVER = true
CLIENT = false

dofile("lua/autorun/sh_grm_jobs.lua")
local JB = GRM.Jobs
assert(JB, "модуль не поднялся")

local fails = 0
local function CHECK(name, cond)
    if cond then P("OK: " .. name) else fails = fails + 1 P("FAIL: " .. name) end
end

-- 1) набор работ: 3 карточки (курьер/мусоровоз/такси), маршрутные — с needVehicle
JB.OpenMenu(worker, center)
local wsid = worker:SteamID64()
local offers = JB._lastOffers[wsid] and JB._lastOffers[wsid].list or {}
CHECK("вакансий 3 (курьер/мусоровоз/такси)", #offers == 3)
local byTpl = {}
for _, o in ipairs(offers) do byTpl[o.tplId] = o end
CHECK("есть курьер", istable(byTpl.courier))
CHECK("есть мусоровоз", istable(byTpl.garbage))
CHECK("есть таксист", istable(byTpl.taxi))
CHECK("нет грузчика/патрульного", byTpl.loader == nil and byTpl.patrol == nil)
CHECK("мусоровоз: needVehicle", byTpl.garbage and byTpl.garbage.needVehicle == true)
CHECK("мусоровоз: 4 точки маршрута (3 контейнера + полигон)", byTpl.garbage and #byTpl.garbage.points == 4)
CHECK("таксист: смена ожидания живых заказов",byTpl.taxi and byTpl.taxi.needVehicle==true and byTpl.taxi.taxiStandby==true and byTpl.taxi.reward==0)

-- 2) мусоровоз: без транспорта прогресса нет
H._curPly = worker
worker._inVeh = false
netInject("GRM_Jobs_Accept", { byTpl.garbage.idx })
local jg = JB.Active[wsid]
CHECK("мусоровоз принят", istable(jg) and jg.jtype == "garbage")
CHECK("pointIndex = 1", jg.pointIndex == 1)
worker._pos = Vector(jg.points[1].x, jg.points[1].y, jg.points[1].z)
JB.TickJobs()
CHECK("без транспорта маршрут не идёт (pointIndex=1)", jg.pointIndex == 1)

-- 3) физический цикл: подъезд к контейнеру сам по себе больше не засчитывает сбор.
worker._inVeh=true
worker._pos=Vector(jg.points[1].x,jg.points[1].y,jg.points[1].z)
JB.TickJobs()
CHECK("контейнер не собирается автоматически из кабины",jg.pointIndex==1)
-- grm_jobs_v4 увеличивает pointIndex только после коробки + G сзади машины.
jg.pointIndex=#jg.points
worker._veh={GRM_GarbageLoad=2,SetNWInt=function(self,_,v)self.GRM_GarbageLoad=v end}
local dump=jg.points[#jg.points];worker._pos=Vector(dump.x,dump.y,dump.z);JB.TickJobs()
CHECK("загруженный мусоровоз разгружен на свалке",JB.Active[wsid]==nil and worker._veh.GRM_GarbageLoad==0)
CHECK("начисление прошло",worker._bal>1000)

-- 4) таксист выходит на линию без синтетического NPC-маршрута.
JB.OpenMenu(worker,center);offers=JB._lastOffers[wsid].list;byTpl={};for _,o in ipairs(offers)do byTpl[o.tplId]=o end
worker._inVeh=true;netInject("GRM_Jobs_Accept",{byTpl.taxi.idx});local jt=JB.Active[wsid]
CHECK("такси принято как standby-смена",istable(jt)and jt.jtype=="taxi"and jt.taxiStandby==true)
CHECK("у standby нет искусственной награды и заказа",jt.reward==0 and jt.taxiRequestID==nil)

P("=== ИТОГ: " .. (fails == 0 and "ВСЕ ПРОВЕРКИ ПРОШЛИ" or ("ПРОВАЛОВ: " .. tostring(fails))) .. " ===")
os.exit(fails == 0 and 0 or 1)
