--[[ Живой прогон профиля категорий дверей: кто проходит, кто может замок,
     кто может приватизировать. Загружается ОБЩАЯ часть sh_grm_doors.lua
     (SERVER=false, CLIENT=false) — чистые функции без файлов и сети.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_door_categories.lua ]]
SERVER, CLIENT = false, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function CurTime() return 100 end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
hook = { Add = function() end, Run = function() end, Remove = function() end }
timer = { Create = function() end, Simple = function() end, Remove = function() end }
util = { AddNetworkString = function() end }
net = { Receive = function() end }
concommand = { Add = function() end }
CreateConVar = function() return { GetInt = function() return 0 end, GetBool = function() return false end } end
GRM = { Perf = {}, Identity = {} }
game = { GetMap = function() return "sim" end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end }
player = { GetAll = function() return {} end }
ents = { GetAll = function() return {} end, FindByClass = function() return {} end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
bit = { bor = function(a) return a end }

assert(loadfile("lua/autorun/sh_grm_doors.lua"))()
local D = GRM.Doors

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

-- Сотрудники.
local civ    = { faction = "", key = "civ:char1" }
local cop    = { faction = "police", department = "patrol", subdepartment = "swat", role = "officer", key = "cop:char1" }
local cop2   = { faction = "police", department = "detective", role = "cadet", key = "cop2:char1" }
local medic  = { faction = "medic", department = "ambulance", role = "doc", key = "med:char1" }
local admin  = { faction = "", superadmin = true, key = "adm:char1" }

print("\n=== 1. ФЛАГИ ПРОФИЛЯ ЕСТЬ И ОБЩИЕ ===")
ok(istable(D.CategoryFlags) and #D.CategoryFlags >= 6, "список флагов категории доступен обеим сторонам")
local flagKeys = {}
for _, f in ipairs(D.CategoryFlags or {}) do flagKeys[f.key] = true end
ok(flagKeys.everyone and flagKeys.noFaction and flagKeys.canLock and flagKeys.lockAdminOnly
    and flagKeys.keepLocked and flagKeys.allowBuy, "все шесть настроек на месте")

print("\n=== 2. КТО «СВОЙ» ===")
local catFaction = { id = "gov", name = "Государственная", factions = { "police" }, departments = {}, subdepartments = {}, roles = {} }
ok(D.CategoryMatch(catFaction, cop) == true, "член организации проходит")
ok(D.CategoryMatch(catFaction, medic) == false, "чужая организация не проходит")
ok(D.CategoryMatch(catFaction, civ) == false, "человек без организации не проходит")

local catDept = { id = "det", name = "Отдел", factions = {}, departments = { "police|detective" }, subdepartments = {}, roles = {} }
ok(D.CategoryMatch(catDept, cop2) == true, "нужный отдел проходит")
ok(D.CategoryMatch(catDept, cop) == false, "другой отдел той же организации не проходит")

local catSub = { id = "swat", name = "Подотдел", factions = {}, departments = {}, subdepartments = { "police|swat" }, roles = {} }
ok(D.CategoryMatch(catSub, cop) == true, "подотдел проходит")
ok(D.CategoryMatch(catSub, cop2) == false, "без подотдела доступа нет")

local catRole = { id = "off", name = "Должность", factions = {}, departments = {}, subdepartments = {}, roles = { "police|officer" } }
ok(D.CategoryMatch(catRole, cop) == true, "должность проходит")
ok(D.CategoryMatch(catRole, cop2) == false, "другая должность не проходит")

local catPublic = { id = "public", name = "Общественная", everyone = true, canLock = false }
ok(D.CategoryMatch(catPublic, civ) == true and D.CategoryMatch(catPublic, medic) == true,
    "общественная пускает вообще всех")
local catCivil = { id = "civil", name = "Для гражданских", noFaction = true }
ok(D.CategoryMatch(catCivil, civ) == true and D.CategoryMatch(catCivil, cop) == false,
    "чекбокс «лица без фракции» работает отдельно")

print("\n=== 3. ЗАМОК ===")
ok(D.CategoryCanLock(catPublic, civ) == false, "общественную дверь запереть нельзя (заказ владельца)")
ok(D.CategoryCanLock(catPublic, admin) == false or D.CategoryCanLock(catPublic, admin) == true,
    "администрация обрабатывается отдельно матрицей допуска")
ok(D.CategoryCanLock(catFaction, cop) == true, "свой сотрудник управляет замком служебной двери")
ok(D.CategoryCanLock(catFaction, medic) == false, "чужой замком не управляет")
local catAdminLock = { id = "court", name = "Суд", factions = { "police" }, lockAdminOnly = true }
ok(D.CategoryCanLock(catAdminLock, cop) == false and D.CategoryCanLock(catAdminLock, admin) == true,
    "режим «замком управляет только администрация»")

print("\n=== 4. МАТРИЦА ДОПУСКА ДВЕРИ ===")
local recCat = { owner_type = "category", owner_category = "public", ownable = true }
local accCivil = D.EvaluateAccess(recCat, {
    key = civ.key, faction = "", categoryHas = true, categoryLock = false, categoryBuy = false,
})
ok(accCivil.has_key == true, "общественная: проход есть у всех")
ok(accCivil.walk_locked == true, "общественная: даже запертая пускает своих")
ok(accCivil.lock == false, "общественная: замком не управляет никто из игроков")
ok(accCivil.buy == false, "общественная: приватизация закрыта")

local accAdmin = D.EvaluateAccess(recCat, { key = admin.key, superadmin = true })
ok(accAdmin.lock == true and accAdmin.admin == true, "администрация замок всё же контролирует")

local accGov = D.EvaluateAccess({ owner_type = "category", owner_category = "gov", ownable = true }, {
    key = cop.key, faction = "police", categoryHas = true, categoryLock = true,
})
ok(accGov.has_key == true and accGov.lock == true, "государственная: свои и проходят, и запирают")
local accGovAlien = D.EvaluateAccess({ owner_type = "category", owner_category = "gov", ownable = true }, {
    key = medic.key, faction = "medic", categoryHas = false, categoryLock = false,
})
ok(accGovAlien.has_key == false and accGovAlien.lock == false, "государственная: чужому закрыто")

local accKeep = D.EvaluateAccess({ owner_type = "category", owner_category = "vault", ownable = true }, {
    key = cop.key, faction = "police", categoryHas = true, categoryLock = true, categoryKeepLocked = true,
})
ok(accKeep.has_key == true and accKeep.lock == false, "«дверь всегда заперта»: пройти можно, открыть замок — нет")

local accBuy = D.EvaluateAccess({ owner_type = "category", owner_category = "flat", ownable = true }, {
    key = civ.key, faction = "", categoryHas = true, categoryBuy = true,
})
ok(accBuy.buy == true, "флаг «разрешить приватизацию» открывает покупку категорийной двери")

print("\n=== 5. СТАРОЕ ПОВЕДЕНИЕ НЕ СЛОМАНО ===")
local recFree = { owner_type = "none", ownable = true }
ok(D.EvaluateAccess(recFree, { key = "x" }).buy == true, "ничья дверь по-прежнему покупается")
local recOwner = { owner_type = "player", owner_key = "civ:char1", ownable = true }
local accOwner = D.EvaluateAccess(recOwner, { key = "civ:char1" })
ok(accOwner.is_owner == true and accOwner.lock == true, "личная дверь: владелец управляет замком")
local accGuest = D.EvaluateAccess(recOwner, { key = "other:char1" })
ok(accGuest.has_key == false and accGuest.walk_locked == false, "чужая личная дверь заперта для посторонних")

print(("\nDOOR CATEGORIES: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
