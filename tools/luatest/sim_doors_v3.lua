--[[--------------------------------------------------------------------
    sim_doors_v3 — контракт ядра дверей (актуально для v5.0.0)
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doors_v3.lua
----------------------------------------------------------------------]]
local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local src = read("lua/autorun/sh_grm_doors.lua")
-- Окно двери с 19.08 живёт отдельным клиентским модулем — контракт ядра
-- проверяем по обоим файлам.
src = src .. "\n" .. read("lua/autorun/client/cl_grm_doors_menu.lua")
local fails = 0
local function check(name, cond, extra)
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function has(n) return src:find(n, 1, true) ~= nil end

print("\n=== ИСТОЧНИКИ ЯДРА ДВЕРЕЙ ===")
check("версия ядра актуальна (>=5.0.0)", (src:match('D%.Version = "(%d+)') or "0") + 0 >= 5)
check("EvaluateAccess — единая матрица", has("function D.EvaluateAccess"))
check("антиспам тоста замка", has("function D.ShouldNotifyLockDeny"))
check("сброс удержания E", has("function D.ClearLockDenyHold"))
check("PlayerUse зовёт ShouldNotifyLockDeny", has("D.ShouldNotifyLockDeny("))
check("CanAdminDoors SuperAdmin", has("function D.CanAdminDoors") and has("IsSuperAdmin() == true"))
check("net-флаг админки = CanAdminDoors", has("net.WriteBool(D.CanAdminDoors(ply))"))
check("jsonT ignoreConversions", has("util.JSONToTable, txt, false, true"))
check("персист version=3 массивом", has("version = 3, doors = arr"))
check("карантин битого файла", has(".corrupt."))
check("не создаём запись на каждый взгляд (_ephemeral)", has("_ephemeral"))
check("PlayerUse только если заперта", has("if not D.IsDoorLocked(ent) then return end"))
check("нет FindInSphere(12)", not has("ents.FindInSphere(ent:GetPos(), 12)"))
check("пара только через parent", has("function D.GetPartnerDoor"))
check("CharacterKey", has("GRM.Identity.CharacterKey"))
check("GRM.UI.Track", has('GRM.UI.Track("grm_door_menu"'))
check("rate-limit приёма", has("GRM_DoorActNext"))
check("дистанция на приёме", has("function nearDoor") or has("nearDoor(ply, ent)"))
check("ACL массивами", has("function toArray") or has("toArray(raw.factions)"))

print("\n=== РАНТАЙМ EvaluateAccess ===")
_G.CLIENT, _G.SERVER = false, false
_G.IsValid = function(v) return type(v) == "table" and v.__valid == true end
_G.istable = function(v) return type(v) == "table" end
_G.isstring = function(v) return type(v) == "string" end
_G.isfunction = function(v) return type(v) == "function" end
_G.hook = { Add = function() end }
_G.timer = { Simple = function() end, Create = function() end }
_G.ents = { GetAll = function() return {} end }
_G.game = { GetMap = function() return "gm_test" end }
_G.AddCSLuaFile = function() end
_G.include = function() end
_G.GRM = {}
dofile("lua/autorun/sh_grm_doors.lua")
local E = GRM.Doors.EvaluateAccess

local civ = { superadmin = false, key = "1:char1", faction = nil, role = nil }
local cop = { superadmin = false, key = "2:char1", faction = "OrdnungPolizei", role = "Офицер" }
local owner = { superadmin = false, key = "3:char1", faction = nil }
local root = { superadmin = true, key = "9:char1" }

local unowned = { owner_type = "none", ownable = true, locked = false }
local gov = { owner_type = "faction", owner_faction = "OrdnungPolizei", ownable = false, locked = true }
local house = { owner_type = "player", owner_key = "3:char1", ownable = false, locked = true, co_owners = {} }
local rented = { owner_type = "player", owner_key = "3:char1", ownable = true, locked = true, rent_until = os.time() + 100 }

check("ничья: гражданский может купить", E(unowned, civ).buy == true)
check("ничья: гражданский без ключа", E(unowned, civ).has_key == false)
check("ничья: проход незапертой всегда", E(unowned, civ).walk_unlocked == true)
check("ведомственная непродаваемая: гражданский НЕ имеет ключа", E(gov, civ).has_key == false)
check("ведомственная непродаваемая: гражданский НЕ покупает", E(gov, civ).buy == false)
check("ведомственная: полицейский имеет ключ", E(gov, cop).has_key == true)
check("ведомственная: полицейский не админ карты", E(gov, cop).admin == false)
check("дом: владелец имеет ключ и хозяйство", E(house, owner).own == true and E(house, owner).has_key == true)
check("дом: чужой без ключа", E(house, civ).has_key == false and E(house, civ).own == false)
check("дом: SuperAdmin админ и ключ", E(house, root).admin == true and E(house, root).has_key == true)
check("ACL фракции даёт ключ", E({
    owner_type = "player", owner_key = "3:char1", factions = { "OrdnungPolizei" }, locked = true,
}, cop).has_key == true)
check("ордер+CanWarrant даёт ключ", E(house, {
    superadmin = false, key = "4:char1", canWarrant = true, hasWarrantOnOwner = true,
}).has_key == true)
check("ордер без CanWarrant не даёт ключ", E(house, {
    superadmin = false, key = "4:char1", canWarrant = false, hasWarrantOnOwner = true,
}).has_key == false)
check("CanForce не есть ключ на E", E(house, {
    superadmin = false, key = "5:char1", canForce = true,
}).has_key == false and E(house, { superadmin = false, key = "5:char1", canForce = true }).force == true)
check("совладелец имеет ключ, не хозяйство", E({
    owner_type = "player", owner_key = "3:char1", co_owners = { "1:char1" }, locked = true,
}, civ).has_key == true and E({
    owner_type = "player", owner_key = "3:char1", co_owners = { "1:char1" },
}, civ).own == false)

print("\n=== РАНТАЙМ тост замка один раз ===")
local N = GRM.Doors.ShouldNotifyLockDeny
local C = GRM.Doors.ClearLockDenyHold
local st = {}
local a, st = N(st, "door_a", 1.0, true, 1.5)
check("первое нажатие — показать", a == true)
local b, st = N(st, "door_a", 1.05, true, 1.5)
check("удержание E — молчать", b == false)
local c, st = N(st, "door_b", 1.10, true, 1.5)
check("вторая половинка в том же тике — молчать (burst)", c == false)
st = C(st)
local d, st = N(st, "door_a", 1.20, true, 1.5)
check("повтор до кулдауна после отпускания — молчать", d == false)
local e, st = N(st, "door_a", 3.0, true, 1.5)
check("новое нажатие после кулдауна — показать", e == true)
local f, st = N({}, "", 1.0, true, 1.5)
check("пустой id — не слать", f == false)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (doors v3)")
else print("ПРОВАЛОВ: " .. fails) end
print(("DOORS_V3 failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
