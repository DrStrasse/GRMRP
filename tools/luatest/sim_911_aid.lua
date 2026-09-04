--[[ Живой прогон помощи пострадавшему: кто может реанимировать (цепочка
     источников), окно действий и приём команд стабилизации/реанимации/
     осмотра/вызова службы.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_911_aid.lua ]]
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
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function ErrorNoHalt() end
DMG_BULLET, CHAN_AUTO = 2, 0

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _vector = true }
    return setmetatable(v, {
        __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __index = { DistToSqr = function(self, o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end,
                    Distance = function(self, o) return math.sqrt(self:DistToSqr(o)) end } })
end
vector_origin = Vector(0, 0, 0)
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do fn(...) end end,
    GetTable = function() return hooks end,
}
timer = { Create = function() end, Simple = function(_, fn) fn() end, Remove = function() end,
          Adjust = function() return true end, Exists = function() return false end }
concommand = { Add = function() end }

local RECEIVERS, SENT = {}, {}
local packet
net = {
    Receive = function(name, fn) RECEIVERS[name] = fn end,
    Start = function(name) packet = { name = name, values = {} } end,
    WriteEntity = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteBool = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteString = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteUInt = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteTable = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteVector = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    Send = function(to) if packet then packet.to = to SENT[#SENT + 1] = packet end end,
    Broadcast = function() if packet then packet.to = "all" SENT[#SENT + 1] = packet end end,
}
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end, Delete = function() end }
CreateConVar = function() return { GetBool = function() return false end, GetInt = function() return 0 end,
    GetFloat = function() return 0 end, GetString = function() return "" end } end
GetConVar = CreateConVar
bit = { bor = function() return 0 end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
game = { GetMap = function() return "rp_test" end, GetWorld = function() return { _entity = true, _valid = true } end }
ents = { Create = function() return nil end, FindByClass = function() return {} end,
         FindInSphere = function() return {} end, GetAll = function() return {} end }

local ALL = {}
player = { GetAll = function() return ALL end }

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.Identity.CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end
GRM.Identity.FactionMember = function() return nil end
GRM.Perf.Players = function() return ALL end
GRM.Notify = function(p, msg) if IsValid(p) then p:ChatPrint(msg) end end
Factions = {}

local INVENTORY = {}
GRM.Inventory = { CountItem = function(ply, id) return (INVENTORY[ply] or {})[id] or 0 end,
                  GetItemDef = function() return nil end }

local function mkPlayer(nick, sid, x)
    local p = { _valid = true, _entity = true, nick = nick, sid = sid, nw = {}, chat = {}, pos = Vector(x or 0, 0, 0), hp = 100 }
    function p:IsPlayer() return true end
    function p:Alive() return self.hp > 0 end
    function p:Nick() return self.nick end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:SteamID64() return self.sid end
    function p:IsSuperAdmin() return self._super == true end
    function p:IsAdmin() return self._super == true end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWBool(k, v) self.nw[k] = v end
    function p:GetNWInt(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWInt(k, v) self.nw[k] = v end
    function p:GetPos() return self.pos end
    function p:SetPos(v) self.pos = v end
    function p:Health() return self.hp end
    function p:SetHealth(v) self.hp = v end
    function p:GetMaxHealth() return 100 end
    function p:Freeze() end
    function p:ExitVehicle() end
    function p:Kill() self.hp = 0 end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:GetEyeTrace() return { Entity = self._aim, HitPos = self.pos } end
    function p:EntIndex() return 1 end
    function p:SetNWEntity(k, v) self.nw[k] = v end
    function p:GetNWEntity(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWFloat(k, v) self.nw[k] = v end
    function p:GetNWFloat(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetVelocity() end
    function p:GetVelocity() return Vector(0, 0, 0) end
    function p:SetNoDraw() end
    function p:DrawShadow() end
    function p:SetMoveType() end
    function p:SetSolid() end
    function p:SetCollisionGroup() end
    function p:SetParent() end
    function p:Remove() self._valid = false end
    function p:GetModel() return "models/player.mdl" end
    function p:GetAngles() return Angle(0, 0, 0) end
    function p:SetAngles() end
    function p:GetClass() return "player" end
    function p:GetActiveWeapon() return nil end
    function p:SetupBones() end
    ALL[#ALL + 1] = p
    return p
end

-- Ядро GRM (ui/core/шина RP-отыгровок) — как на сервере, до модуля.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_911.lua"))()
local EM = GRM.EmergencyMedical or GRM.EM or GRM["911"] or GRM.Emergency
if not EM then
    for _, name in ipairs({ "EM", "Emergency", "EmergencyMedical", "Medical911", "Nine11" }) do
        if istable(GRM[name]) and isfunction(GRM[name].Stabilize) then EM = GRM[name] break end
    end
end
assert(istable(EM) and isfunction(EM.Stabilize), "не нашли таблицу модуля 911")

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local victim = mkPlayer("Раненый", "76561190000000002", 0)
local helper = mkPlayer("Прохожий", "76561190000000003", 30)
victim.nw.GRM_RPName = "Курт Вебер"
helper.nw.GRM_RPName = "Ганс Мюллер"

print("\n=== 1. КТО МОЖЕТ РЕАНИМИРОВАТЬ ===")
GRM.MedicalFull = { IsMedic = function() return false end }
GRM.Medical = { CanTreat = function() return false end }
GRM.PCBoard = nil
local can, why = EM.IsMedic(helper)
ok(can == false, "обычный прохожий без ничего — не медик")
ok(isstring(why) and why ~= "", "и ему объясняют, чего не хватает", why)

INVENTORY[helper] = { med_adrenaline = 1 }
ok(EM.IsMedic(helper) == true, "с адреналином в сумке помощь оказать можно")
INVENTORY[helper] = {}

GRM.PCBoard = { PlayerLevel = function(p) return p == helper and "medical" or "none" end }
ok(EM.IsMedic(helper) == true, "медицинский допуск госбазы делает игрока медиком")
GRM.PCBoard = { PlayerLevel = function(p) return p == helper and "fire" or "none" end }
ok(EM.IsMedic(helper) == true, "пожарная служба тоже может реанимировать")
GRM.PCBoard = { PlayerLevel = function() return "police" end }
ok(EM.IsMedic(helper) == false, "полицейскому допуску реанимация не даётся")

GRM.MedicalFull = { IsMedic = function() return false end }
GRM.Medical = { CanTreat = function(p) return p == helper end }
ok(EM.IsMedic(helper) == true,
    "проверка НЕ обрывается на первом источнике (это и был баг с одной кнопкой)")
GRM.Medical = { CanTreat = function() return false end }

helper._super = true
ok(EM.IsMedic(helper) == true, "суперадмин может всегда")
helper._super = false

print("\n=== 2. СОСТОЯНИЕ ПОСТРАДАВШЕГО ===")
victim.nw.GRM_911_Downed = true
victim.nw.GRM_911_Stable = false
victim.nw.GRM_911_DeathAt = os.time() + 100
ok(select(1, EM.Stabilize(helper, victim)) == true, "стабилизация проходит")
ok(victim.nw.GRM_911_Stable == true, "пациент помечен стабилизированным")
ok(select(1, EM.Stabilize(helper, victim)) == false, "повторная стабилизация отклоняется")

local okRevive, msg = EM.Revive(helper, victim)
ok(okRevive == false and tostring(msg):find("медик", 1, true) ~= nil,
    "без допуска реанимация отклоняется с понятным ответом", tostring(msg))

INVENTORY[helper] = { med_adrenaline = 1 }
ok(select(1, EM.Revive(helper, victim)) == true, "с медикаментом реанимация проходит")
ok(victim.nw.GRM_911_Downed ~= true, "пациент поднят на ноги")

print("\n=== 3. ПАКЕТ В ОКНО ПОМОЩИ ===")
SENT = {}
victim.nw.GRM_911_Downed = true
victim.nw.GRM_911_Stable = false
victim.nw.GRM_Bleed = 40
victim.nw.GRM_Pain = 65
helper._aim = victim
local chatFn = hooks["PlayerSay"] and next(hooks["PlayerSay"]) and select(2, next(hooks["PlayerSay"]))
if chatFn then chatFn(helper, "/aid") end
local sent
for _, pk in ipairs(SENT) do if pk.name == "GRM_911_Patient" then sent = pk end end
ok(sent ~= nil, "по команде /aid уходит пакет с карточкой пострадавшего")
if sent then
    ok(sent.values[2] == true, "в пакете есть флаг «можно реанимировать»", tostring(sent.values[2]))
    ok(sent.values[6] == 40 and sent.values[7] == 65,
        "и данные осмотра: кровопотеря и боль", tostring(sent.values[6]) .. "/" .. tostring(sent.values[7]))
end

print("\n=== 4. ДЕЙСТВИЯ ИЗ ОКНА ===")
local treat = RECEIVERS["GRM_911_Treat"]
ok(isfunction(treat), "приёмник действий на месте")

-- осмотр доступен без допуска
INVENTORY[helper] = {}
helper.chat = {}
net.ReadEntity = function() return victim end
net.ReadString = function() return "checkup" end
treat(nil, helper)
ok(#helper.chat > 0 and helper.chat[1]:find("Осмотр", 1, true) ~= nil,
    "осмотр доступен любому и печатает состояние", helper.chat[1])

-- реанимация без допуска: отказ с причиной, а не тишина
helper.chat = {}
net.ReadString = function() return "revive" end
treat(nil, helper)
ok(#helper.chat > 0 and helper.chat[1]:find("Реанимация недоступна", 1, true) ~= nil,
    "на реанимацию без допуска приходит понятный отказ", helper.chat[1])

-- вызов медслужбы
helper.chat = {}
helper._grm911CallAt = 0
net.ReadString = function() return "call" end
treat(nil, helper)
ok(#helper.chat > 0 and helper.chat[1]:find("Вызов", 1, true) ~= nil,
    "из окна можно вызвать медслужбу", helper.chat[1])

print("\n=== 5. СПИСОК ПРЕДМЕТОВ ПОМОЩИ ===")
ok(istable(EM.ReviveItems) and #EM.ReviveItems >= 2, "список предметов настраиваемый", #EM.ReviveItems)
INVENTORY[helper] = { medkit = 2 }
ok(EM.HasReviveItem(helper) == true, "аптечка тоже подходит")

print(("\n911 AID: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
