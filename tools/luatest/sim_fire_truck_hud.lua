--[[ Строка пожарной машины внизу экрана.
     Заказ 21.08: «показывает воду и пену, хотя мы далеко от машины».
     Заказ 22.08: «должно показываться только когда смотрю на машину; после
     /firetruck строка появляется вообще у всех, даже без доступа».

     Правило гоняется вживую (F.TruckHUDVisible грузится из настоящего
     файла), плюс проверяется контракт клиентской части по исходнику.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fire_truck_hud.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p, y = y, r = r } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
hook = { Add = function() end, Run = function() end, Remove = function() end }
util = { JSONToTable = function() return {} end, TableToJSON = function() return "{}" end }
GRM = { Fire = {} }

assert(loadfile("lua/autorun/sh_grm_fire_truck.lua"))()
local F = GRM.Fire

print("\n=== 1. КОМУ И КОГДА ВИДНА СТРОКА ===")
ok(isfunction(F.TruckHUDVisible), "правило показа вынесено в чистую функцию")
ok(F.TruckHUDVisible(true, true, false, 0, 350) == true, "боец сидит в машине — видно")
ok(F.TruckHUDVisible(true, false, true, 200, 350) == true, "смотрит на машину вблизи — видно")
ok(F.TruckHUDVisible(true, false, true, 900, 350) == false, "смотрит издалека — не видно")
ok(F.TruckHUDVisible(true, false, false, 10, 350) == false,
   "стоит вплотную, но смотрит в другую сторону — НЕ видно")
ok(F.TruckHUDVisible(false, false, true, 100, 350) == false,
   "нет доступа к системе тушения — не видно, даже глядя в упор")
ok(F.TruckHUDVisible(false, true, true, 0, 350) == false,
   "и в кабине без доступа тоже не видно (после /firetruck строка была у всех)")
ok(F.TruckHUDVisible(nil, nil, nil, nil, nil) == false, "мусор на входе ничего не показывает")

print("\n=== 2. КОНТРАКТ КЛИЕНТСКОЙ ЧАСТИ ===")
local f = assert(io.open("lua/autorun/sh_grm_fire_truck.lua", "rb"))
local src = f:read("*a") f:close()
local function has(n) return src:find(n, 1, true) ~= nil end

ok(has('CreateClientConVar("grm_fire_hud_dist"'), "дальность показа настраивается конваром")
ok(has('ply:GetNWBool("GRM_FireCrew", false)'), "клиент спрашивает флаг доступа, а не решает сам")
ok(has("local function lookedTruck(ply)") and has("GRM.Perf.EyeTrace"),
   "взгляд на машину определяется трассировкой через кэш GRM.Perf")
ok(has("CurTime() - lookAt > 0.2"), "трассировка троттлится, а не идёт каждый кадр")
ok(has("F.TruckHUDVisible(crew, seat ~= nil, look ~= nil, dist, maxDist)"),
   "HUD ходит через то же правило, что и стенд")
ok(not has("holdingFireGear(ply)"), "старое правило «ствол в руках — показывать» убрано")
ok(not has("local near = ply:GetPos():Distance(veh:GetPos()) <= maxDist"),
   "старое правило «просто рядом — показывать» убрано")

print("\n=== 3. ФЛАГ ДОСТУПА ПУБЛИКУЕТ СЕРВЕР ===")
ok(has("function F.PublishCrewFlag(ply)") and has('ply:SetNWBool("GRM_FireCrew", can)'),
   "сервер выкладывает право одним флагом")
ok(has("F.CanUseFireTruck(ply) == true"), "флаг считается по настоящей проверке доступа")
ok(has('hook.Add("PlayerSpawn", "GRM_FireTruck_CrewFlag"'), "флаг обновляется на спавне")
ok(has('hook.Add("GRM_FireAccessChanged", "GRM_FireTruck_CrewFlag"'),
   "и при изменении доступов в /fire_access")
ok(has('timer.Create("GRM_FireTruck_CrewFlags", 20, 0'),
   "фоновое обновление редкое (20 c), в кадре ничего не считается")

local acc = assert(io.open("lua/autorun/sh_grm_fire_access.lua", "rb"))
local accSrc = acc:read("*a") acc:close()
ok(accSrc:find('hook.Run("GRM_FireAccessChanged", ply)', 1, true) ~= nil,
   "менеджер доступа сообщает об изменении прав")

print(("\nFIRE TRUCK HUD: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
