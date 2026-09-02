--[[ Живой прогон: обычный стул больше не считается транспортом.

     Отчёт владельца 27.08 со скриншотом: «Когда сажусь в любой стул,
     кресло — срабатывает худ и функционал simfphys транспорта. И это я
     даже не в машине по факту.» На экране: приборник со спидометром,
     баком «70/100 л», полосой поломки и сообщением «Не заводится:
     поломана» — при том, что игрок сидит на стуле в помещении.

     ПРИЧИНА. В GMod сиденье это тоже vehicle: у стула класс
     prop_vehicle_prisoner_pod, поэтому ply:InVehicle() и ent:IsVehicle()
     возвращают true. GRM.Fuel.RootVehicle, не найдя родителя-машины,
     возвращал САМ СТУЛ — и топливо, прочность, круиз-контроль и HUD
     работали с креслом как с автомобилем.

     Запуск: luajit tools/luatest/sim_seat_not_vehicle.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
hook = { Add = function() end, Run = function() end, Remove = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end,
    Exists = function() return false end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
function CurTime() return 0 end
function ErrorNoHalt() end
game = { GetMap = function() return "gm_test" end }
GRM = {}

--- Заглушка сущности: минимум, который читает RootVehicle.
local function makeEnt(class, opts)
    opts = opts or {}
    local e = {
        _valid = true, _class = class, _parent = opts.parent,
        GetClass = function(s) return s._class end,
        GetParent = function(s) return s._parent or { _valid = false } end,
        GetNWEntity = function() return { _valid = false } end,
    }
    for k, v in pairs(opts.flags or {}) do e[k] = v end
    return e
end

assert(loadfile("lua/autorun/sh_grm_fuel.lua"))()
local F = GRM.Fuel

print("\n=== 1. ВОСПРОИЗВОДИМ СЛУЧАЙ СО СКРИНШОТА ===")
-- Обычный стул: одиночный prisoner_pod без родителя.
local chair = makeEnt("prop_vehicle_prisoner_pod")
ok(F.RootVehicle(chair) == nil,
   "стул НЕ выдаётся за транспорт — приборник и «Не заводится» не появятся")
ok(F.IsRealVehicle(chair) == false, "стул не проходит проверку настоящего транспорта")

-- Мебельные сиденья аддонов обычно тоже prisoner_pod или свой класс.
local sofa = makeEnt("prop_vehicle_prisoner_pod")
ok(F.RootVehicle(sofa) == nil, "кресло/диван тоже не транспорт")
local seatAddon = makeEnt("gmod_sitting_chair")
ok(F.RootVehicle(seatAddon) == nil, "сидячий стул из аддона не транспорт")

print("\n=== 2. НАСТОЯЩИЙ ТРАНСПОРТ РАБОТАЕТ КАК РАНЬШЕ ===")
local simf = makeEnt("simfphys_gta_sa_enforcer", { flags = { IsSimfphysCar = true } })
ok(F.RootVehicle(simf) == simf, "машина simfphys опознаётся")
ok(F.IsRealVehicle(simf) == true, "и проходит проверку транспорта")

local simfByClass = makeEnt("simfphys_mafia2_jeep")
ok(F.RootVehicle(simfByClass) == simfByClass, "simfphys опознаётся и по классу, без флага")

local fphysBase = makeEnt("gmod_sent_vehicle_fphysics_base")
ok(F.RootVehicle(fphysBase) == fphysBase, "база fphysics опознаётся")

local lvs = makeEnt("lvs_car_something", { flags = { LVS = true } })
ok(F.RootVehicle(lvs) == lvs, "LVS опознаётся")

local jeep = makeEnt("prop_vehicle_jeep")
ok(F.RootVehicle(jeep) == jeep, "ванильный джип — транспорт")
local airboat = makeEnt("prop_vehicle_airboat")
ok(F.RootVehicle(airboat) == airboat, "ванильный аэробот — транспорт")

print("\n=== 3. СИДЕНЬЕ ВНУТРИ МАШИНЫ — ЭТО МАШИНА ===")
--[[ Ключевой случай: пассажирский под simfphys это тот же prisoner_pod,
     но прицеплен к корпусу. Он обязан вести к машине, иначе пассажир
     потеряет приборник. ]]
local pod = makeEnt("prop_vehicle_prisoner_pod", { parent = simf })
ok(F.RootVehicle(pod) == simf, "пассажирское место ведёт к своей машине")
ok(F.RootVehicle(pod) ~= pod, "а не к самому себе")

local podLVS = makeEnt("prop_vehicle_prisoner_pod", { parent = lvs })
ok(F.RootVehicle(podLVS) == lvs, "то же для LVS")

print("\n=== 4. ГРАНИЧНЫЕ СЛУЧАИ ===")
ok(F.RootVehicle(nil) == nil, "nil не роняет вызов")
ok(F.RootVehicle({ _valid = false }) == nil, "мёртвая сущность отбрасывается")
ok(F.IsRealVehicle(nil) == false, "проверка транспорта переживает nil")
local orphanPod = makeEnt("prop_vehicle_prisoner_pod", { parent = { _valid = false } })
ok(F.RootVehicle(orphanPod) == nil, "под без живого родителя — обычный стул")

print("\n=== 5. ФОЛБЭКИ В МОДУЛЯХ ТОЖЕ ПОЧИНЕНЫ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
--[[ Раньше у HUD, прочности и круиза были свои копии root() на случай,
     если модуль топлива не загрузился, и все три возвращали сам стул.
     Волна дедупа 1 (02.09.2026): явный фолбэк живёт в ОДНОМ месте —
     GRM.Core.VehRoot; прочность и круиз делегируют ему; HUD остаётся
     самодостаточным (клиент может жить без core-секции?). Контракт:
     1) фолбэк опознаёт транспорт явно (jeep/airboat), а не любое сиденье;
     2) ни одна из копий не возвращает стул по умолчанию. ]]
local coreSrc = body("lua/autorun/sh_01_grm_core.lua")
ok(coreSrc:find("prop_vehicle_jeep", 1, true) ~= nil,
   "GRM.Core.VehRoot: фолбэк опознаёт транспорт явно, а не считает им любое сиденье")
ok(coreSrc:find("    return ent\nend", 1, true) == nil,
   "GRM.Core.VehRoot: фолбэк не возвращает стул по умолчанию")
for label, path in pairs({
    ["приборник"] = "lua/autorun/client/cl_grm_vehicle_hud.lua",
}) do
    local src = body(path)
    ok(src:find("prop_vehicle_jeep", 1, true) ~= nil,
       label .. ": фолбэк опознаёт транспорт явно, а не считает им любое сиденье")
    ok(src:find("    return ent\nend", 1, true) == nil or src:find("or ent", 1, true) ~= nil,
       label .. ": фолбэк больше не возвращает стул по умолчанию")
end
for label, path in pairs({
    ["прочность"] = "lua/autorun/sh_grm_vehicle_health.lua",
    ["круиз-контроль"] = "lua/autorun/sh_grm_cruise.lua",
}) do
    local src = body(path)
    ok(src:find("GRM.Core.VehRoot", 1, true) ~= nil,
       label .. ": корень берётся из общего GRM.Core.VehRoot (копия вырезана)")
    ok(src:find("prop_vehicle_jeep", 1, true) == nil,
       label .. ": локального клона фолбэка больше нет")
end

print("\n=== 6. ПОТРЕБИТЕЛИ ПЕРЕЖИВАЮТ nil ===")
local health = body("lua/autorun/sh_grm_vehicle_health.lua")
ok(health:find("if not isVeh(ent) then return false", 1, true) ~= nil,
   "ремонт отклоняет не-транспорт вместо падения")
ok(health:find("ent = root(ent) or ent", 1, true) ~= nil,
   "там, где нужен объект, есть запасной вариант")
local fuel = body("lua/autorun/sh_grm_fuel.lua")
ok(fuel:find("local veh = F.RootVehicle(seat)", 1, true) ~= nil
   and fuel:find("if IsValid(veh) then", 1, true) ~= nil,
   "посадка в сиденье проверяет результат перед использованием")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
