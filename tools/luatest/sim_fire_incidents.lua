--[[ Живой прогон учёта пожаров: тушение НЕ должно сыпать сообщениями
     «Пожар потушен» и НЕ должно порождать новые вызовы (жалоба владельца
     21.08). Проверяем на «пожаре» из нескольких ячеек vFire, которые гасят
     одну за другой.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fire_incidents.lua ]]
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
function isentity(v) return type(v) == "table" and v._entity == true end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt() end

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _vector = true }
    return setmetatable(v, {
        __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __index = {
            DistToSqr = function(self, o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end,
            Distance = function(self, o) return math.sqrt(self:DistToSqr(o)) end,
        },
    })
end
function Color(r, g, b) return { r = r, g = g, b = b } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do fn(...) end end,
    GetTable = function() return hooks end,
}
local pending = {}
timer = {
    Create = function() end,
    Simple = function(_, fn) pending[#pending + 1] = fn end,
    Remove = function() end,
}
local function runTimers()
    local list = pending
    pending = {}
    for _, fn in ipairs(list) do fn() end
end
concommand = { Add = function() end }
net = { Receive = function() end, Start = function() end, WriteTable = function() end,
        WriteString = function() end, Send = function() end, Broadcast = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "[]" end,
         JSONToTable = function() return {} end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end }
local CVARS = { grm_fire_chat_dupe = "0" }
CreateConVar = function(name, default)
    CVARS[name] = CVARS[name] or tostring(default)
    return { GetBool = function() return CVARS[name] ~= "0" end,
             GetFloat = function() return tonumber(CVARS[name]) or 0 end,
             GetInt = function() return math.floor(tonumber(CVARS[name]) or 0) end,
             GetString = function() return CVARS[name] end }
end
GetConVar = function(name) if CVARS[name] == nil then return nil end return CreateConVar(name) end
bit = { bor = function() return 0 end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
game = { GetMap = function() return "rp_test" end, GetWorld = function() return { _entity = true, _valid = true } end }

-- ── «огонь» на карте ────────────────────────────────────────────────
local FIRES = {}
local function mkFire(x, y)
    local f = { _valid = true, _entity = true, pos = Vector(x, y, 0) }
    function f:GetPos() return self.pos end
    function f:GetClass() return "vfire" end
    function f:Remove() self._valid = false end
    FIRES[#FIRES + 1] = f
    return f
end
local function liveList()
    local out = {}
    for _, f in ipairs(FIRES) do if IsValid(f) then out[#out + 1] = f end end
    return out
end
ents = { FindByClass = function() return liveList() end, FindInSphere = function() return {} end,
         Create = function() return nil end, GetAll = function() return liveList() end }

local ALL = {}
player = { GetAll = function() return ALL end }

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.Perf.Entities = function() return liveList() end
GRM.Perf.Players = function() return ALL end

local NOTIFY = {}
GRM.Notify = function(p, text) NOTIFY[#NOTIFY + 1] = { to = p, text = text } end
GRM.Fire = { NotifyFactions = function() end, CanDispatch = function() return true end,
             CanFightPro = function() return true end }

local function mkPlayer(nick)
    local p = { _valid = true, nick = nick, chat = {}, pos = Vector(0, 0, 0) }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID() return "STEAM_0:1:1" end
    function p:SteamID64() return "76561190000000001" end
    function p:IsSuperAdmin() return true end
    function p:GetPos() return self.pos end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:GetActiveWeapon() return { _valid = true, GetClass = function() return "weapon_grm_hose" end } end
    ALL[#ALL + 1] = p
    return p
end
local firefighter = mkPlayer("Пожарный")

assert(loadfile("lua/autorun/sh_grm_fire_status.lua"))()
local F = GRM.Fire

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local opened, extinguished = 0, 0
hook.Add("GRM_FireIncidentOpened", "sim", function() opened = opened + 1 end)
hook.Add("GRM_FireExtinguished", "sim", function() extinguished = extinguished + 1 end)

local function created(fire) hooks["vFireCreated"]["GRM_Fire_Status"](fire) end
local function removed(fire)
    fire:Remove()
    hooks["vFireRemoved"]["GRM_Fire_Status"](fire)
    runTimers()
end
local function outMessages()
    local n = 0
    for _, row in ipairs(NOTIFY) do
        if tostring(row.text):find("потушен", 1, true) then n = n + 1 end
    end
    return n
end

print("\n=== 1. ОДИН ПОЖАР — ОДИН ИНЦИДЕНТ ===")
local cells = {}
for i = 1, 6 do
    cells[i] = mkFire(100 + i * 30, 0)
    created(cells[i])
end
ok(opened == 1, "шесть ячеек пламени рядом = ОДИН инцидент и один вызов", opened)
ok(#F.Incidents == 1, "в учёте один инцидент", #F.Incidents)

print("\n=== 2. ТУШЕНИЕ ===")
NOTIFY = {}
opened, extinguished = 0, 0
for i = 1, 5 do
    NOW = NOW + 1
    removed(cells[i])
end
ok(opened == 0, "во время тушения НОВЫЕ вызовы не создаются", opened)
ok(extinguished == 0, "пока горит последняя ячейка, «потушен» не объявляется", extinguished)

NOW = NOW + 1
removed(cells[6])
ok(extinguished == 1, "«Пожар потушен» объявлен РОВНО один раз", extinguished)
ok(outMessages() >= 1, "сообщение получили пожарные")
local firstBatch = outMessages()

print("\n=== 3. ПОСЛЕ ТУШЕНИЯ ТИШИНА ===")
NOTIFY = {}
for _ = 1, 5 do
    NOW = NOW + 1
    F.RefreshIncidents(Vector(150, 0, 0))
end
ok(outMessages() == 0, "повторные обновления не сыплют «потушен»", outMessages())
ok(opened == 0, "и не создают вызовов", opened)

print("\n=== 4. ОБНОВЛЕНИЕ НЕ ОТКРЫВАЕТ ОЧАГ ===")
opened = 0
F.RefreshIncidents(Vector(9000, 9000, 0))
ok(opened == 0, "подсказка о месте без огня не открывает инцидент", opened)
ok(F.OpenIncident(Vector(9000, 9000, 0), "fire") == nil,
    "OpenIncident отказывается создавать очаг там, где не горит")
local ghost = F.OpenIncident(Vector(9000, 9000, 0), "fire", { force = true })
ok(ghost ~= nil, "но принудительно (скан карты при загрузке) — можно")
ok((ghost.peak or 0) == 0, "у принудительного очага без огня peak = 0", ghost and ghost.peak)
ok(F.MarkExtinguished(ghost) == false,
    "такой «призрак» не объявляет себя потушенным")

print("\n=== 5. ПОВТОРНОЕ ВОЗГОРАНИЕ ===")
opened, extinguished = 0, 0
NOW = NOW + 5
local flare = mkFire(120, 0)
created(flare)
ok(opened == 0, "вспышка на месте только что потушенного очага не плодит новый вызов", opened)
local revived = 0
for _, inc in ipairs(F.Incidents) do
    if not inc.out and inc.origin:DistToSqr(Vector(120, 0, 0)) <= 480 * 480 then revived = revived + 1 end
end
ok(revived == 1, "очаг ожил тем же инцидентом", revived)

NOW = NOW + 200
removed(flare)
ok(extinguished == 1, "и закрывается снова один раз", extinguished)

opened = 0
NOW = NOW + 300
local fresh = mkFire(130, 0)
created(fresh)
ok(opened == 1, "через большой промежуток это уже НОВЫЙ пожар и новый вызов", opened)

print("\n=== 6. СООБЩЕНИЙ НЕ БОЛЬШЕ, ЧЕМ СОБЫТИЙ ===")
NOTIFY = {}
firefighter.chat = {}
NOW = NOW + 5
removed(fresh)
ok(outMessages() == 1, "на одно тушение — одно уведомление", outMessages())
ok(#firefighter.chat == 0,
    "дубля строкой в чат нет (включается конваром grm_fire_chat_dupe)", #firefighter.chat)
CVARS["grm_fire_chat_dupe"] = "1"
NOTIFY = {}
firefighter.chat = {}
local again = mkFire(2000, 2000)
created(again)
NOW = NOW + 5
removed(again)
ok(#firefighter.chat >= 1, "с включённым конваром дубль в чат возвращается", #firefighter.chat)
CVARS["grm_fire_chat_dupe"] = "0"

print(("\nFIRE INCIDENTS: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
