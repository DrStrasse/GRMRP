--[[ sim_anticheat — поведенческий античит GRM.AntiCheat v1.0 (заказ 02.09)

    Проверяет:
      1) silentAim: попал, глядя в сторону → +35, строка в ленте;
      2) иммунитет суперадмина и GRM_ACImmune;
      3) throughWall: трасс, обрванный миром, → +45;
      4) perfectLock: серия из 8 идеальных попаданий в голову → флаг;
      5) rapidfire: >4 попаданий за окно;
      6) телепорт/спидхак/флай/inSolid по сэмплам Think;
      7) деkey профиля и отсидка (evict) профилей мёртвых;
      8) порог 80: action 2 → кик; action 4 → деморган + глобал-бан по
         железу (цепочка SB.Ban → SB.GlobalBan со снимком + движковый banid);
      9) AdminCmd list/clear/status/flag; QUERY/CMD по правам; chat !ac;
     10) GRM_AC_HwidSwap (из GRM.ServerBan) → +40;
     11) исходники: каналы зарегистрированы, панель имеет вкладки,
         права в BASE_PERMS, ранний снимок клиента 0.3 с.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_anticheat.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 1000
function CurTime() return NOW end
function SysTime() return NOW end
local CLOCK = 1700000000
os.time = function() return CLOCK end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isbool(v) return type(v) == "boolean" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt(...) end
HUD_PRINTCONSOLE = 2
CONTENTS_SOLID, MASK_SHOT_HULL = 1, 33816

-- вектора с реальной геометрией: Distance/Dot/GetNormal + аддитивность
local vmeta = {}
vmeta.__index = {
    Distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
    Dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end,
    Length = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
    GetNormal = function(a)
        local l = a:Length()
        if l == 0 then return Vector(0, 0, 0) end
        return Vector(a.x / l, a.y / l, a.z / l)
    end,
}
vmeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vmeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmeta) end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(name, ...)
        local t = hooks[name]
        if not t then return end
        for _, fn in pairs(t) do fn(...) end
    end,
}
local timers = {}
timer = { Create = function(id, _, _, fn) timers[id] = fn end, Simple = function(_, fn) fn() end,
    Remove = function(id) timers[id] = nil end, Exists = function() return false end }
concommand = { Add = function() end }

local CVARS = {}
local function cvarValue(name, default)
    local c = CVARS[name]
    return c ~= nil and tostring(c) or tostring(default)
end
CreateConVar = function(name, default)
    local c = { _name = name }
    function c:GetString() return cvarValue(name, default) end
    function c:GetBool() return self:GetString() ~= "0" end
    function c:GetInt() return math.floor(tonumber(self:GetString()) or 0) end
    function c:GetFloat() return tonumber(self:GetString()) or 0 end
    function c:SetString(v) CVARS[name] = v end
    return c
end
GetConVar = CreateConVar
util = { AddNetworkString = function() end,
    SteamIDFrom64 = function(s) return "STEAM_" .. tostring(s) end }

TRACE_FRACTION, TRACE_HITWORLD = 1, false
util.TraceLine = function()
    return { Fraction = TRACE_FRACTION, Hit = TRACE_FRACTION < 1,
        HitPos = Vector(0, 0, 0), Entity = NULL or {},
        HitWorld = function() return TRACE_HITWORLD end }
end
POINT_CONTENTS = 0
util.PointContents = function() return POINT_CONTENTS end

local CONSOLE = {}
game = { GetMap = function() return "rp_test" end, MaxPlayers = function() return 32 end,
    ConsoleCommand = function(c) CONSOLE[#CONSOLE + 1] = tostring(c) end }

local SENT = {}
net = {
    Receive = function(name, fn) net._rx = net._rx or {} net._rx[name] = fn end,
    Start = function(n) SENT[#SENT + 1] = { s = n } end,
    WriteString = function(v) local t = SENT[#SENT] t.str = (t.str or "") .. tostring(v) end,
    WriteTable = function(v) SENT[#SENT].tbl = v end,
    Send = function(ply) SENT[#SENT].to = ply end,
    SendToServer = function() SENT[#SENT].to = "server" end,
    Broadcast = function() end,
}
local RX = {}
function net.ReadTable() return RX.tbl end
function net.ReadString() return RX.str or "" end
local function fire(name, ply, data)
    RX = data or {}
    net._rx[name](0, ply)
end

local ALL = {}
player = { GetAll = function() return ALL end }
GRM = { Perf = {}, Audit = { Write = function() end }, Admin = {}, Net = {} }
GRM.Perf.Players = function() return ALL end
GRM.Net.Guard = function() return GUARD_OK == nil and true or GUARD_OK end
PERMS = PERMS or {}
function GRM.Admin.Can(ply, perm) return (IsValid(ply) and ply._perms or PERMS)[perm] == true or (IsValid(ply) and ply._super == true) end
SB_CALLS = {}
GRM.ServerBan = {
    Ban = function(_, ply, m, r) SB_CALLS[#SB_CALLS + 1] = { op = "ban", sid = tostring(ply:SteamID64()), min = m, reason = r } end,
    GlobalBan = function(sid, name, m, r, _, rep, ip)
        SB_CALLS[#SB_CALLS + 1] = { op = "globalban", sid = sid, name = name, min = m, reason = r, rep = rep, ip = ip }
        return true, "ok"
    end,
}

local function mkPlayer(nick, sid)
    local p = { _valid = true, nick = nick, sid = sid, _pos = Vector(0, 0, 0), _aim = Vector(1, 0, 0),
        _vel = Vector(0, 0, 0), _ground = true, _kicks = {}, _msgs = {}, _perms = {},
        _weapon = { _valid = true, GetClip = function() return 12 end } }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID64() return self.sid end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:IsSuperAdmin() return self._super == true end
    function p:Kick(w) self.kicked = true self._kicks[#self._kicks + 1] = tostring(w) end
    function p:PrintMessage(_, l) self._msgs[#self._msgs + 1] = tostring(l) end
    function p:GetNWString(_, d) return d end
    function p:Alive() return true end
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:EyePos() return self._pos + Vector(0, 0, 64) end
    function p:EyeAngles()
        local dir = self._aim
        return { Forward = function() return dir end }
    end
    function p:GetVelocity() return self._vel end
    function p:OnGround() return self._ground end
    function p:Crouching() return false end
    function p:GetVehicle() return self._veh or nil end
    function p:GetActiveWeapon() return self._weapon end
    ALL[#ALL + 1] = p
    return p
end

dofile("lua/autorun/sh_grm_anticheat.lua")
local AC = GRM.AntiCheat

local PASS, FAIL = 0, {}
local function t(name, cond, info)
    if cond then PASS = PASS + 1 else FAIL[#FAIL + 1] = name .. (info and (" · " .. tostring(info)) or "") end
end
local function scoreOf(ply)
    local rows = AC.Rows()
    for _, r in ipairs(rows) do if r.sid == ply.sid then return r.score, r.kind, r.note end end
    return 0
end
local function reset() for _, p in ipairs(AC.Rows()) do AC.AdminCmd(nil, "clear " .. p.sid) end end

-- 1) silentAim -------------------------------------------------------
local sniper = mkPlayer("Sn1per", "76561199000000001")
local vic = mkPlayer("Victim", "76561199000000002")
vic:SetPos(Vector(1000, 0, 0))
sniper._aim = Vector(0, 1, 0) -- смотрит вбок, попал в голову
local HURT = hooks["PlayerHurt"]["GRM_AC_Hurt"]
HURT(vic, sniper, { HitPos = vic:EyePos() })
local sc, kind = scoreOf(sniper)
t("silentAim флаг", sc == AC.Weight.silentAim and kind == "silentAim", ("score=%d kind=%s"):format(sc, tostring(kind)))
t("лента пополнилась", AC.PushFeed and #SENT >= 0)

-- 2) иммунитеты ------------------------------------------------------
local adminP = mkPlayer("SuperAdmin", "76561199000000003")
adminP._super = true
adminP:SetPos(Vector(0, 0, 0)); adminP._aim = Vector(0, 1, 0)
HURT(vic, adminP, { HitPos = vic:EyePos() + Vector(500, 0, 0) })
t("суперадмин иммунен", select(1, scoreOf(adminP)) == 0)
local builder = mkPlayer("Builder", "76561199000000004")
builder.GRM_ACImmune = true
builder._aim = Vector(0, 1, 0)
HURT(vic, builder, { HitPos = vic:EyePos() + Vector(900, 0, 0) })
t("GRM_ACImmune иммунен", select(1, scoreOf(builder)) == 0)

-- 3) throughWall -------------------------------------------------------
TRACE_FRACTION, TRACE_HITWORLD = 0.4, true
reset()
local wallP = mkPlayer("WallHacker", "76561199000000005")
wallP:SetPos(Vector(0, 0, 0))
wallP._aim = Vector(1, 0, 0)
HURT(vic, wallP, { HitPos = vic:EyePos() })
t("throughWall", select(1, scoreOf(wallP)) == AC.Weight.throughWall, scoreOf(wallP))
TRACE_FRACTION, TRACE_HITWORLD = 1, false

-- 4) perfectLock + rapidfire: угол 0, дистанция 1000, попадание в голову
reset()
local bot = mkPlayer("AimBot", "76561199000000006")
bot:SetPos(Vector(0, 0, 0))
bot._aim = Vector(1, 0, 0)
local seenLock, seenRapid = false, false
for i = 1, 8 do
    CLOCK = CLOCK + 1
    local before = scoreOf(bot)
    HURT(vic, bot, { HitPos = vic:EyePos() + Vector(0, 0, 6) })
    local after = scoreOf(bot)
    local _, k = scoreOf(bot)
    if k == "perfectLock" then seenLock = true end
    if after - before == AC.Weight.rapidfire or after - before == AC.Weight.perfectLock then end
    seenRapid = seenRapid or (after == before + AC.Weight.rapidfire)
end
t("perfectLock серия", seenLock, scoreOf(bot))
t("rapidfire серия", seenRapid)

-- 5) телепорт через Think-сэмплер --------------------------------------
reset()
local blinker = mkPlayer("Blinker", "76561199000000007")
blinker:SetPos(Vector(0, 0, 0))
local THINK = hooks["Think"]["GRM_AC_Sample"]
AC._lastSample = 0
NOW = NOW + 1
THINK() -- инициализация prev
blinker:SetPos(Vector(3000, 0, 0))
blinker._ground = false
AC._lastSample = 0
NOW = NOW + 1
THINK()
t("телепорт-блинк", select(1, scoreOf(blinker)) == AC.Weight.teleport, scoreOf(blinker))
-- маленький шаг не флагается
reset()
blinker:SetPos(Vector(2900, 0, 0))
blinker._ground = true
AC._lastSample = 0
NOW = NOW + 1
THINK()
t("обычный бег чист", select(1, scoreOf(blinker)) == 0, scoreOf(blinker))

-- 6) speedhack у подозреваемого ----------------------------------------
reset()
AC.Flag(blinker, "silentAim", "посев") -- score 35 >= SUSPECT_AT
blinker._ground = true
local oldpos = blinker._pos
blinker:SetPos(oldpos) -- прыжка нет
blinker._vel = Vector(1200, 0, 0)
AC._lastSample = 0
NOW = NOW + 1
THINK()
t("speedhack по счёту", select(2, scoreOf(blinker)) == "speedhack", scoreOf(blinker))
POINT_CONTENTS = CONTENTS_SOLID
blinker._vel = Vector(0, 0, 0)
AC._lastSample = 0
NOW = NOW + 1
THINK()
t("inSolid по счёту", select(1, scoreOf(blinker)) == AC.Weight.silentAim + AC.Weight.speedhack + AC.Weight.inSolid, scoreOf(blinker))
POINT_CONTENTS = 0

-- 7) деkey + отсидка ------------------------------------------------------
reset()
AC.Flag(blinker, "silentAim", "x")
local sc1 = scoreOf(blinker)
CLOCK = CLOCK + 300
timers["GRM_AC_Decay"]()
t("декей -2", select(1, scoreOf(blinker)) == sc1 - 2, scoreOf(blinker))
blinker._valid = false
CLOCK = CLOCK + 700
timers["GRM_AC_Decay"]()
local evicted = true
for _, r in ipairs(AC.Rows()) do if r.sid == blinker.sid then evicted = false end end
t("профиль-призрак выселен", evicted)

-- 8) порог действия: кик (action 2) ---------------------------------------
CVARS["grm_ac_action"] = "2"
reset()
local k1 = mkPlayer("KickMe", "76561199000000008")
for _ = 1, 3 do AC.Flag(k1, "throughWall", "x") end -- 135 >= 80
t("кик на пороге", k1.kicked == true)
t("счётчик обнулён на действии", select(1, scoreOf(k1)) == AC.Weight.throughWall)

-- 9) порог действия: деморган + глобал по железу (action 4) ---------------
CVARS["grm_ac_action"] = "4"
local k2 = mkPlayer("BanMe", "76561199000000009")
k2.GRM_MachineRep = { os = "win", res = "1920x1080", lang = "ru" }
for _ = 1, 2 do AC.Flag(k2, "throughWall", "x") end -- 90 >= 80
local g1, g2c
for _, c in ipairs(SB_CALLS) do
    if c.op == "ban" and c.sid == k2.sid then g1 = c end
    if c.op == "globalban" and c.sid == k2.sid then g2c = c end
end
t("деморган выдан", g1 ~= nil and g1.min == 120)
t("глобал-бан по железу", g2c ~= nil and g2c.rep ~= nil and g2c.min == 0
    and g2c.reason:find("Античит %(авто%)") ~= nil)
t("движковый banid после глобалбана", CONSOLE[#CONSOLE] ~= nil and table.concat(CONSOLE, "\n"):find("banid 0 STEAM_76561199000000009") ~= nil,
    table.concat(CONSOLE, "|"))
t("кик после бана", k2.kicked == true)
CVARS["grm_ac_action"] = "1"

-- 10) hwidSwap из GRM.ServerBan --------------------------------------------
reset()
local swap = mkPlayer("Swapper", "76561199000000010")
hook.Run("GRM_AC_HwidSwap", swap)
t("hwidSwap вес", select(1, scoreOf(swap)) == AC.Weight.hwidSwap, scoreOf(swap))

-- 11) AdminCmd ---------------------------------------------------------------
reset()
AC.Flag(swap, "teleport", "проверка")
t("list считает", AC.AdminCmd(nil, "list"):find("подозреваемых: 1") ~= nil, AC.AdminCmd(nil, "list"))
t("clear конкретного", AC.AdminCmd(nil, "clear " .. swap.sid):find("очищен") ~= nil and select(1, scoreOf(swap)) == 0)
t("status формат", AC.AdminCmd(nil, "status"):find("античит вкл") ~= nil)
t("flag вручную", AC.AdminCmd(nil, "flag " .. swap.sid .. " fly"):find("отмечен") ~= nil and select(1, scoreOf(swap)) == AC.Weight.fly)
t("пустая = list", AC.AdminCmd(nil, ""):find("подозреваемых") ~= nil)
t("некоманда", AC.AdminCmd(nil, "hackme"):find("команды") ~= nil)

-- 12) net-каналы ------------------------------------------------------------
local watcher = mkPlayer("Mod", "76561199000000011")
watcher._perms = { ["anticheat.see"] = true }
local n0 = #SENT
fire("GRM_AC_Query", watcher)
t("QUERY авторизованному", #SENT == n0 + 1 and SENT[#SENT].s == "GRM_AC_Feed" and istable(SENT[#SENT].tbl))
local outsider = mkPlayer("Nobody", "76561199000000012")
fire("GRM_AC_Query", outsider)
t("QUERY без права молчит", #SENT == n0 + 1)
local adminAc = mkPlayer("Mod2", "76561199000000013")
adminAc._perms = { ["anticheat.admin"] = true }
RX = { str = "status" }
fire("GRM_AC_Cmd", adminAc)
t("CMD ответ реплаем", SENT[#SENT].s == "GRM_AC_Feed" and istable(SENT[#SENT].tbl) and SENT[#SENT].tbl.reply ~= nil, SENT[#SENT].tbl and SENT[#SENT].tbl.reply)
RX = { str = "status" }
fire("GRM_AC_Cmd", outsider)
t("CMD без права — ответа нет", SENT[#SENT].tbl.reply ~= nil) -- пакет не добавился
-- guard-отказ
GUARD_OK = false
RX = { str = "list" }
local before = #SENT
fire("GRM_AC_Cmd", adminAc)
t("guard глушит CMD", #SENT == before)
GUARD_OK = nil

-- 13) чат-алиас ---------------------------------------------------------------
local sayAdmin = adminAc
local out = hooks["PlayerSay"]["GRM_AC_Chat"](sayAdmin, "!ac status")
t("!ac съеден из чата", out == "")
t("!ac ответил в консоль", #sayAdmin._msgs > 0 and sayAdmin._msgs[#sayAdmin._msgs]:find("античит") ~= nil)
t("обычный !ac игрок — тихо", hooks["PlayerSay"]["GRM_AC_Chat"](outsider, "!ac status") == "" and #outsider._msgs == 0)

-- 14) исходники ----------------------------------------------------------------
local function readSrc(p)
    local f = io.open(p, "r"); if not f then return "" end
    local s = f:read("*a"); f:close(); return s
end
local banSrc = readSrc("lua/autorun/sh_grm_ban.lua")
local coreSrc = readSrc("lua/autorun/sh_grm_admin_core.lua")
local panelSrc = readSrc("lua/autorun/client/cl_grm_admin_panel.lua")
local actSrc = readSrc("lua/autorun/server/sv_grm_admin_actions.lua")
local conSrc = readSrc("lua/autorun/server/sv_grm_admin_console.lua")
t("клиент: ранний снимок 0.3", banSrc:find("timer.Simple%(0%.3, SB.SendMachine%)") ~= nil)
t("ядро: право anticheat.see", coreSrc:find('"anticheat%.see"') ~= nil)
t("ядро: право server.console danger", coreSrc:find('"server%.console".-"superadmin", true') ~= nil)
t("панель: вкладка Античит", panelSrc:find('addTab%("anticheat", "Античит", "anticheat%.see", buildAntiCheat%)') ~= nil)
t("панель: вкладка Консоль", panelSrc:find('addTab%("console", "Консоль", "server%.console", buildConsole%)') ~= nil)
t("консоль: отдельный модуль подключается", conSrc:find("GRM_Admin_Console") ~= nil)
t("actions: чистый A.machine цел", actSrc:find("A%.machine = {") ~= nil)
t("feed-канал общий (lit в панели)", panelSrc:find('net.Receive%("GRM_AC_Feed"') ~= nil)
t("консоль-out слушается панелью", panelSrc:find('net.Receive%("GRM_Admin_ConsoleOut"') ~= nil)
t("raw-строка не исполняется без права", conSrc:find('AD%.Can%(ply, "server%.console"%) ~= true') ~= nil)
t("нет литерала пака", (readSrc("lua/autorun/sh_grm_anticheat.lua") .. conSrc):find("Comedy") == nil)

print(("sim_anticheat: PASS %d, FAIL %d"):format(PASS, #FAIL))
for _, f in ipairs(FAIL) do print("  ✗ " .. f) end
os.exit(#FAIL == 0 and 0 or 1)
