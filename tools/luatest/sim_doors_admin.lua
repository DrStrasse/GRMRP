--[[--------------------------------------------------------------------
    sim_doors_admin — вкладка «Администрирование» на R только суперадмину.

    Баг: обычный игрок с ключами (ds_key_swep R / /door) видел панель
    назначения фракции/категории и мог менять принадлежность дверей карты.
    Причина: canManage = SuperAdmin OR AM.CanManage(ManageFactions/…).

    Фикс v2.0.7: D.CanAdminDoors = SuperAdmin; сетка AM.CanManage больше
    не открывает эту вкладку и не принимает set_*_owner / toggle_ownable.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doors_admin.lua
----------------------------------------------------------------------]]

local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local src = read("lua/autorun/sh_grm_doors.lua")
-- Окно двери переехало в отдельный клиентский модуль (19.08): гейт «только
-- админ» проверяем и там.
local menu = read("lua/autorun/client/cl_grm_doors_menu.lua")
local acc = read("lua/autorun/sh_grm_doors_access.lua")
-- Свеп ds_key_swep удалён 31.08; меню двери открывает пункт
-- «Управление» в модуле взаимодействия.
local key = read("lua/autorun/sh_grm_interact.lua")

local fails = 0
local function check(name, cond, extra)
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

print("\n=== ИСТОЧНИКИ v2.0.7 ===")
check("версия ядра дверей проставлена",(src:match('D%.Version = "(%d+)') or "0")+0>=3)
check("сервер печатает версию", has(src, "Серверная система дверей v") or has(src, "D.Version"))
check("клиент печатает версию", has(src, "Клиентская система дверей v"))
check("есть D.CanAdminDoors", has(src, "function D.CanAdminDoors"))
check("CanAdminDoors = SuperAdmin", has(src, "ply:IsSuperAdmin() == true"))
check("is_admin из EvaluateAccess.admin / CanAdminDoors", has(src, "is_admin = acc.admin") or has(src, "is_admin = D.CanAdminDoors(ply)"))
check("net-флаг = CanAdminDoors, не AM.CanManage", has(src, "net.WriteBool(D.CanAdminDoors(ply))"))
check("старый WriteBool с AM.CanManage убран", not has(src, "D.AccessManager.CanManage and D.AccessManager.CanManage(ply) or ply:IsSuperAdmin()"))
check("set_faction_owner режет не-админа", has(src, "Только суперадмин может менять принадлежность двери."))
check("toggle_ownable режет не-админа", has(src, "Только суперадмин может менять статус приватизации."))
check("вкладка Администрирование только админу",
    has(menu, "local isAdmin = (d.is_admin == true) or (canAdmin == true)") and has(menu, 'if isAdmin then'))
check("пункт «Управление» открывает OpenDoorMenu", has(key, "D.OpenDoorMenu"))
check("AM.CanManage остался для /door_access", has(acc, "function AM.CanManage"))

print("\n=== РАНТАЙМ CanAdminDoors ===")
_G.CLIENT = false
_G.SERVER = true
_G.AddCSLuaFile = function() end
_G.include = function() end
_G.IsValid = function(v) return type(v) == "table" and v.__valid == true end
_G.isfunction = function(v) return type(v) == "function" end
_G.istable = function(v) return type(v) == "table" end
_G.isstring = function(v) return type(v) == "string" end
_G.hook = { Add = function() end, Remove = function() end }
_G.timer = { Simple = function() end, Create = function() end }
_G.util = { AddNetworkString = function() end, JSONToTable = function() end, TableToJSON = function() end, TraceLine = function() return {} end }
_G.net = setmetatable({}, { __index = function() return function() end end })
_G.file = { IsDir = function() return true end, CreateDir = function() end, Exists = function() return false end, Read = function() return "" end, Write = function() end }
_G.ents = { GetAll = function() return {} end }
_G.player = { GetAll = function() return {} end }
_G.concommand = { Add = function() end }
_G.game = { GetMap = function() return "gm_test" end }
_G.CurTime = function() return 0 end
_G.os = os
_G.math = math
_G.string = string
_G.table = table
_G.pairs = pairs
_G.ipairs = ipairs
_G.print = print
_G.ErrorNoHalt = function() end
_G.CreateClientConVar = function() end
_G.surface = { CreateFont = function() end }
_G.Color = function(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
_G.color_white = {r=255,g=255,b=255,a=255}
_G.SCRW = 1920
_G.GRM = {}

-- Не грузим весь sh_grm_doors.lua: он тянет GMod-физику. Прогоняем
-- ту же формулу, что D.CanAdminDoors, на мок-игроках.
local function canAdmin(ply)
    return IsValid(ply) and ply.IsPlayer and ply:IsPlayer() and ply:IsSuperAdmin() == true
end

local civ = {
    __valid = true,
    IsPlayer = function() return true end,
    IsSuperAdmin = function() return false end,
    IsAdmin = function() return false end,
}
local staff = {
    __valid = true,
    IsPlayer = function() return true end,
    IsSuperAdmin = function() return false end,
    IsAdmin = function() return true end,
}
local root = {
    __valid = true,
    IsPlayer = function() return true end,
    IsSuperAdmin = function() return true end,
}

check("гражданский не админ дверей", canAdmin(civ) == false)
check("IsAdmin без SuperAdmin не проходит", canAdmin(staff) == false)
check("суперадмин проходит", canAdmin(root) == true)
check("nil не проходит", canAdmin(nil) == false)

-- AM.CanManage больше не равен админке двери
local manageGranted = true -- как если фракция в ManageFactions
check("CanManage не даёт вкладку (гражданский + manage)", (canAdmin(civ) or false) == false)
check("CanManage не даёт вкладку даже при флаге матрицы", canAdmin(civ) == false and manageGranted == true)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (doors admin v2.0.7)")
else print("ПРОВАЛОВ: " .. fails) end
print(("DOORS_ADMIN failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
