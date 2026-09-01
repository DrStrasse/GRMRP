--[[--------------------------------------------------------------------
    sim_doors_access — контракт Access Manager v3.0.0
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doors_access.lua
----------------------------------------------------------------------]]
local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local acc = read("lua/autorun/sh_grm_doors_access.lua")
local ram = read("lua/weapons/ds_battering_ram/shared.lua")
local core = read("lua/autorun/sh_grm_doors.lua")

local fails = 0
local function check(name, cond, extra)
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

print("\n=== ИСТОЧНИКИ access v3.0.0 ===")
check("версия 3.0.0", has(acc, 'AM.Version = "3.0.0"'))
check("Evaluate — единая матрица", has(acc, "function AM.Evaluate"))
check("jsonT ignoreConversions", has(acc, "util.JSONToTable, txt, false, true"))
check("персист version=3", has(acc, "version = 3"))
check("Steam массивами", has(acc, "setToArray"))
check("карантин битого файла", has(acc, ".corrupt."))
check("read-back записи", has(acc, 'file.Read(path, "DATA") == txt'))
check("открытие SuperAdmin или CanManage", has(acc, "ply:IsSuperAdmin() or AM.CanManage(ply)"))
check("сохранение матрицы только SuperAdmin", has(acc, "Матрицу ордеров/тарана правит только суперадмин."))
check("категории через canOpen", has(acc, "Нет прав управлять категориями."))
check("менеджеру матрица не уезжает", has(acc, "canEdit and AM.Normalize(AM.Data"))
check("rate-limit", has(acc, "GRM_DoorAccNext"))
check("GRM.UI.Track", has(acc, 'GRM.UI.Track("grm_door_access"'))
check("вкладка Steam", has(acc, 'tabs:AddSheet("Steam"'))
check("сигналка по категориям в UI", has(acc, "Своя категория:"))
check("вкладка через хук меню (без подмены OpenAdminMenu)", has(acc, 'hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_DoorsAccess_Tab"') and not has(acc, "OpenAdminMenu = function"))
check("нет local OpenAdminMenu", not acc:find("local OpenAdminMenu", 1, true))
check("нет local Factions", not acc:find("local Factions", 1, true))
check("ядро не отдаёт R-админку CanManage", has(core, "function D.CanAdminDoors") and has(core, "IsSuperAdmin() == true"))
check("таран читает owner_key", has(ram, "rec.owner_key or rec.owner_sid"))
check("таран не смотрит только owner_sid", not ram:match("rec%.owner_sid%s*~=%s*\"\""))

print("\n=== РАНТАЙМ AM.Evaluate ===")
_G.CLIENT, _G.SERVER = false, false
_G.IsValid = function(v) return type(v) == "table" and v.__valid == true end
_G.istable = function(v) return type(v) == "table" end
_G.isstring = function(v) return type(v) == "string" end
_G.isfunction = function(v) return type(v) == "function" end
_G.ipairs = ipairs
_G.pairs = pairs
_G.tostring = tostring
_G.table = table
_G.string = string
_G.util = { JSONToTable = function() return nil end, TableToJSON = function() return "{}" end }
_G.hook = { Add = function() end }
_G.timer = { Simple = function() end, Create = function() end }
_G.AddCSLuaFile = function() end
_G.GRM = {}
dofile("lua/autorun/sh_grm_doors_access.lua")

local E = GRM.Doors.AccessManager.Evaluate
local N = GRM.Doors.AccessManager.Normalize

local data = N({
    WarrantFactions = { OrdnungPolizei = true },
    WarrantRoles = { Feldgendarmerie = { Offizier = true } },
    WarrantSteam = { "111:char1" },
    ForceFactions = { SWAT = true },
    ForceSteam = { "222" },
    ManageFactions = { Regierung = true },
    ManageSteam = { "STEAM_0:1:9" },
})

local civ = { superadmin = false, key = "9:char1", sid64 = "9", sid = "STEAM_0:0:1" }
local cop = { superadmin = false, key = "2:char1", faction = "OrdnungPolizei", role = "Офицер" }
local feld = { superadmin = false, key = "3:char1", faction = "Feldgendarmerie", role = "Offizier" }
local swat = { superadmin = false, key = "4:char1", faction = "SWAT" }
local gov  = { superadmin = false, key = "5:char1", faction = "Regierung" }
local root = { superadmin = true, key = "0:char1" }

check("гражданский без ордера", E(data, civ, "warrant") == false)
check("полицейский по фракции имеет ордер", E(data, cop, "warrant") == true)
check("полицейский без тарана", E(data, cop, "force") == false)
check("полицейский без управления", E(data, cop, "manage") == false)
check("жандарм по рангу имеет ордер", E(data, feld, "warrant") == true)
check("жандарм без тарана", E(data, feld, "force") == false)
check("SWAT имеет таран, не ордер", E(data, swat, "force") == true and E(data, swat, "warrant") == false)
check("правительство управляет категориями", E(data, gov, "manage") == true)
check("правительство не ордер и не таран", E(data, gov, "warrant") == false and E(data, gov, "force") == false)
check("Steam CharacterKey даёт ордер", E(data, { superadmin = false, key = "111:char1" }, "warrant") == true)
check("Steam sid64 даёт таран", E(data, { superadmin = false, key = "x", sid64 = "222" }, "force") == true)
check("Steam STEAM_ даёт управление", E(data, { superadmin = false, sid = "STEAM_0:1:9" }, "manage") == true)
check("SuperAdmin всё", E(data, root, "warrant") and E(data, root, "force") and E(data, root, "manage"))
check("чужой Steam не проходит", E(data, { superadmin = false, key = "999:char1", sid64 = "999" }, "warrant") == false)
check("нормализация массива Steam", N({ WarrantSteam = { "aaa", "bbb" } }).WarrantSteam.aaa == true)
check("нормализация карты фракции", N({ ForceFactions = { Polizei = true } }).ForceFactions.Polizei == true)
check("пустой kind — отказ", E(data, root, "nope") == false)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (doors access v3)")
else print("ПРОВАЛОВ: " .. fails) end
print(("DOORS_ACCESS failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
