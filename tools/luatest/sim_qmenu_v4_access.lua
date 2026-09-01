-- sim_qmenu_v4_access — матрица прав игрока / суперадмина (протокол v4)
string.Trim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end
math.Clamp = math.Clamp or function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o)
    if o == nil or o == false then return false end
    if type(o) == "table" then return rawget(o, "__removed") ~= true end
    return true
end
HUD_PRINTTALK, HUD_PRINTCENTER = 3, 4
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return nil end, TraceLine = function() return {} end,
         IsValidModel = function() return true end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end }
local hooks = {}
hook = { Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
         Run = function() end }
timer = { Simple = function(_, fn) if fn then fn() end end }
net = { Start = function() end, WriteTable = function() end, WriteUInt = function() end,
        WriteString = function() end, WriteBool = function() end, Send = function() end,
        Broadcast = function() end, Receive = function() end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end }
AddCSLuaFile = function() end
SERVER, CLIENT = true, false
CurTime = function() return 1 end

dofile("lua/autorun/sh_grm_qmenu.lua")
local QM = GRM.QMenu

local pass, fail = 0, 0
local function ok(c, m)
    if c then pass = pass + 1 print("  ok  " .. m)
    else fail = fail + 1 print("  FAIL " .. m) end
end

local function ply(sa)
    return setmetatable({ __sa = sa }, { __index = function(s, k)
        if k == "IsSuperAdmin" then return function() return s.__sa end end
        if k == "GetNWBool" then return function() return false end end
        if k == "IsPlayer" then return function() return true end end
        return function() end
    end })
end
local admin, user = ply(true), ply(false)

ok(QM.Version == "5.2.0", "версия 5.2.0")
ok(QM.CanUseTool(admin, "dynamite") == true, "суперадмин: динамит можно")
ok(QM.CanUseTool(user, "dynamite") == false, "игрок: динамит в deny")
ok(QM.CanUseTool(user, "weld") == true, "игрок: сварка можно")
ok(QM.CanUseTool(user, "grm_perm_tool") == false, "игрок: служебный перм-тул закрыт")
QM.Cfg.whitelistMode = true
ok(QM.CanUseTool(user, "weld") == false, "белый режим: вне allow — нет")
QM.Cfg.toolAllow.weld = true
ok(QM.CanUseTool(user, "weld") == true, "белый режим: в allow — да")
ok(QM.CanUseTool(admin, "weld") == true, "суперадмин обходит белый режим")
QM.Cfg.whitelistMode = false
ok(QM.CanSpawn(user, "npc") == false, "игрок: NPC закрыт")
ok(QM.CanSpawn(admin, "npc") == true, "суперадмин: NPC можно")
ok(QM.CanOpenQ(user) == (QM.Cfg.playersQ == true), "CanOpenQ игрока = playersQ")
QM.Cfg.playersQ = false
ok(QM.CanOpenQ(user) == false, "playersQ=false → игроку ванильное Q закрыто")
ok(QM.CanOpenQ(admin) == true, "суперадмину CanOpenQ всегда")
ok(QM.InCatalog("grm_perm_tool") == true, "перм-тул в каталоге")
ok(QM.InCatalog("grm_service_tool") == true, "служебный тул в каталоге")
ok(QM.ResolveSchema("grm_perm_tool") ~= nil, "схема перм-тула есть")
local sch, kind = QM.ResolveSchema("grm_perm_tool")
ok(kind == "hand" and sch[1].type == "choice", "схема перм-тула — ручная, choice")

print(("РЕЗУЛЬТАТ: %d/%d, fail=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
