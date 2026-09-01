--[[ Живой прогон объявлений администрации: смена группы и наказания уходят
     красной строкой ВСЕМ, формулировки различают «посадил/выпустил», группа
     висит на игроке и видна в TAB сразу.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_admin_announce.lua ]]
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
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt() end
MASK_SOLID_BRUSHONLY, MOVETYPE_NONE, SOLID_VPHYSICS, COLLISION_GROUP_NONE = 1, 0, 6, 0
HUD_PRINTCONSOLE, RENDERMODE_TRANSALPHA = 2, 4

function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _vector = true }
    return setmetatable(v, { __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end,
        __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
        __index = { DistToSqr = function(self, o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end } })
end
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    function a:Forward() local rad = math.rad(self.y) return Vector(math.cos(rad), math.sin(rad), 0) end
    return a
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do local r = fn(...) if r ~= nil then return r end end end,
    GetTable = function() return hooks end,
}
local timers = {}
timer = { Create = function(id, _, _, fn) timers[id] = fn end, Simple = function(_, fn) fn() end,
          Remove = function(id) timers[id] = nil end, Exists = function(id) return timers[id] ~= nil end }
concommand = { Add = function() end }

local BROADCAST = {}
local currentPacket
net = {
    Receive = function(name, fn) net["_" .. name] = fn end,
    Start = function(name) currentPacket = { name = name, strings = {} } end,
    WriteString = function(v) if currentPacket then currentPacket.strings[#currentPacket.strings + 1] = v end end,
    WriteTable = function(t) if currentPacket then currentPacket.data = t end end,
    WriteBool = function() end, WriteUInt = function() end,
    ReadString = function() return "" end, ReadTable = function() return {} end, ReadBool = function() return false end,
    Send = function(p) if currentPacket then currentPacket.to = p BROADCAST[#BROADCAST + 1] = currentPacket end end,
    Broadcast = function() if currentPacket then currentPacket.to = "all" BROADCAST[#BROADCAST + 1] = currentPacket end end,
}
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end,
         TraceLine = function(t) return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0) } end,
         SteamIDTo64 = function(s) return s end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end }
CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
GetConVar = CreateConVar
bit = { bor = function() return 0 end }
FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED = 1, 2, 4
CAMI = nil
ULib, ulx = nil, nil

local SPAWNED = {}
ents = {
    Create = function(class)
        local e = { _valid = true, pos = Vector(0, 0, 0) }
        function e:SetModel(m) self.model = m end
        function e:Spawn() end
        function e:SetPos(p) self.pos = p end
        function e:GetPos() return self.pos end
        function e:SetAngles() end
        function e:SetMoveType() end
        function e:SetSolid() end
        function e:SetCollisionGroup() end
        function e:Remove() self._valid = false end
        function e:OBBMins() return Vector(-64, -4, 0) end
        function e:OBBMaxs() return Vector(64, 4, 96) end
        function e:GetPhysicsObject() return { _valid = true, EnableMotion = function() end } end
        SPAWNED[#SPAWNED + 1] = e
        return e
    end,
    FindByClass = function() return {} end, GetAll = function() return SPAWNED end,
}

local ALL = {}
player = { GetAll = function() return ALL end }
local function mkPlayer(nick, sid64, super)
    local p = { _valid = true, nick = nick, sid = sid64, nw = {}, chat = {}, pos = Vector(0, 0, 0), _super = super }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:SteamID64() return self.sid end
    function p:IsSuperAdmin() return self._super == true end
    function p:IsAdmin() return self._super == true or self._admin == true end
    function p:SetUserGroup(g) self.group = g end
    function p:GetUserGroup() return self.group or "user" end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetPos(v) self.pos = v end
    function p:GetPos() return self.pos end
    function p:SetVelocity() end
    function p:GetVelocity() return Vector(0, 0, 0) end
    function p:Freeze(v) self.frozen = v end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:Ping() return 20 end
    function p:IsBot() return false end
    function p:Kick() end
    function p:GodEnable() end
    function p:SetRenderMode() end
    function p:SetColor() end
    ALL[#ALL + 1] = p
    return p
end

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.Identity.CharacterKey = function(p) return IsValid(p) and p:SteamID64() .. ":char1" or "" end
GRM.Notify = function(p, msg) if IsValid(p) then p:ChatPrint(msg) end end
GRM.Perf.Players = function() return ALL end

assert(loadfile("lua/autorun/sh_grm_admin_core.lua"))()
local AD = GRM.Admin
AD.LoadGroups()
AD.Users = {}
assert(loadfile("lua/autorun/server/sv_grm_admin_actions.lua"))()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function lastAnnounce()
    for i = #BROADCAST, 1, -1 do
        if BROADCAST[i].name == AD.Net.ANNOUNCE then return BROADCAST[i] end
    end
end
local function announceText()
    local packet = lastAnnounce()
    return packet and packet.strings[1] or ""
end

local admin = mkPlayer("Шеф", "76561190000000001", true)
local target = mkPlayer("Новичок", "76561190000000002", false)
admin.nw.GRM_RPName = "Александр Фон Грённер"
target.nw.GRM_RPName = "Моров Морозов"

print("\n=== 1. НАЗНАЧЕНИЕ ГРУППЫ ===")
BROADCAST = {}
local okApply, msg = AD.ApplyGroup(target, "moderator", admin, {})
ok(okApply == true, "группа назначена", tostring(msg))
local packet = lastAnnounce()
ok(packet ~= nil, "об этом ушло объявление")
ok(packet and packet.to == "all", "объявление ушло ВСЕМ, а не одному")
ok(packet and packet.strings[2] == "group", "объявление помечено как «группа»")
local text = announceText()
ok(text:find("Александр Фон Грённер", 1, true) ~= nil, "в тексте кто назначил (RP-имя)", text)
ok(text:find("Новичок", 1, true) ~= nil, "в тексте кого назначили", text)
ok(text:find("Модератор", 1, true) ~= nil, "в тексте НАЗВАНИЕ группы, а не её id", text)
ok(text:find("Игрок", 1, true) ~= nil, "в тексте видно, из какой группы перевели", text)

print("\n=== 2. ГРУППА ВИДНА СРАЗУ ===")
ok(target.nw.GRM_AdminGroup == "moderator", "группа висит на игроке NW-строкой")
ok(AD.GroupOf(target) == "moderator", "GroupOf отдаёт новую группу")
local label, col = AD.GroupLabel("moderator")
ok(label == "Модератор", "GroupLabel отдаёт человеческое название", label)
ok(istable(col) and col.g == 190, "GroupLabel отдаёт цвет группы для списков")
local hookFired
hook.Add("GRM_AdminGroupChanged", "sim_check", function(ply, from, to) hookFired = { from, to } end)
AD.ApplyGroup(target, "admin", admin, {})
ok(istable(hookFired) and hookFired[1] == "moderator" and hookFired[2] == "admin",
    "смена группы поднимает хук GRM_AdminGroupChanged (по нему обновляется TAB)",
    hookFired and (hookFired[1] .. "→" .. hookFired[2]))

AD.ApplyGroup(target, "user", admin, {})
ok(target.nw.GRM_AdminGroup == "user", "понижение тоже отражается на игроке")
ok(announceText():find("Администратор", 1, true) ~= nil and announceText():find("Игрок", 1, true) ~= nil,
    "в объявлении о понижении видны обе группы", announceText())

print("\n=== 3. НАКАЗАНИЯ ===")
local function act(op, args)
    BROADCAST = {}
    local action = AD.Actions[op]
    if not action then return "нет действия" end
    local row = AD.PunishActions[op]
    local was = false
    if row and row.toggle then was = target[row.toggle] ~= nil and target[row.toggle] ~= false end
    local okAct = action.fn(admin, target, args or {})
    if okAct then
        local t = AD.PunishText("Александр Фон Грённер", "Моров Морозов", op, args or {}, was)
        if t then AD.Announce(t, "mod") end
    end
    return announceText()
end

local jailText = act("jail", { seconds = 90 })
ok(jailText:find("посадил в клетку", 1, true) ~= nil, "клетка объявляется", jailText)
ok(jailText:find("90 с", 1, true) ~= nil, "в объявлении указан срок", jailText)
local freeText = act("jail", {})
ok(freeText:find("выпустил из клетки", 1, true) ~= nil,
    "повторное нажатие объявляется как освобождение, а не как посадка", freeText)

local muteText = act("mute")
ok(muteText:find("закрыл текстовый чат", 1, true) ~= nil, "мут объявляется", muteText)
local unmuteText = act("mute")
ok(unmuteText:find("вернул текстовый чат", 1, true) ~= nil, "размут объявляется", unmuteText)

local warnText = act("warn", { reason = "оскорбления в чате" })
ok(warnText:find("предупреждение", 1, true) ~= nil and warnText:find("оскорбления", 1, true) ~= nil,
    "предупреждение объявляется с причиной", warnText)

print("\n=== 4. ФОРМУЛИРОВКИ ===")
ok(AD.PunishText("A", "B", "ban", { minutes = 60, reason = "чит" }, false)
    :find("на 60 мин.", 1, true) ~= nil, "у бана указан срок")
ok(AD.PunishText("A", "B", "ban", { minutes = 0 }, false):find("навсегда", 1, true) ~= nil,
    "вечный бан назван вечным")
ok(AD.PunishText("A", "B", "kick", { reason = "AFK" }):find("причина: AFK", 1, true) ~= nil,
    "у кика указана причина")
ok(AD.PunishText("A", "B", "goto", {}) == nil, "перемещение админа НЕ объявляется всем")
ok(AD.PunishText("A", "B", "spectate", {}) == nil, "наблюдение НЕ объявляется всем")

print("\n=== 5. КАНАЛ ОБЪЯВЛЕНИЙ ===")
BROADCAST = {}
ok(AD.Announce("тестовая строка", "mod") == true, "Announce отправляет")
ok(lastAnnounce() ~= nil and lastAnnounce().to == "all", "и всегда всем")
ok(AD.Announce("") == false, "пустое объявление не шлётся")

print(("\nADMIN ANNOUNCE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
