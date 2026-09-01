--[[ Живой прогон предзагрузки моделей транспорта (заказ владельца 22.08:
     «модели у дилера видны только после первого спавна, и то не все»)
     и восстановления выносливости в машине.
     Грузится РЕАЛЬНЫЙ lua/autorun/sh_grm_vehicle_precache.lua.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_vehicle_precache.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
FCVAR_ARCHIVE, FCVAR_REPLICATED, RENDERGROUP_OPAQUE = 1, 2, 0
bit = { bor = function(a, b) return a + b end }

local PRECACHED = {}
util = { PrecacheModel = function(m) PRECACHED[m] = true end }
list = { Get = function() return {} end }
ents = { FindByClass = function() return {} end }
local HOOKS = {}
hook = { Add = function(e, n, f) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = f end, Run = function() end }
local TIMERS = {}
timer = {
    Create = function(n, d, r, f) TIMERS[n] = { delay = d, fn = f } end,
    Simple = function() end, Remove = function(n) TIMERS[n] = nil end,
    Exists = function(n) return TIMERS[n] ~= nil end,
}
local CMDS = {}
concommand = { Add = function(n, f) CMDS[n] = f end }
local CONVARS = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) ~= "0" end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end

local SPREAD = nil
GRM = {
    Perf = {
        Spread = function(id, listIn, fn, opts) SPREAD = { id = id, list = listIn, fn = fn, opts = opts or {} } return true end,
        Coalesce = function(_, fn) fn() end,
    },
    Boot = { OnMapStart = function(id, tier, fn) GRM._boot = { id = id, tier = tier, fn = fn } return true end },
}

assert(loadfile("lua/autorun/sh_grm_vehicle_precache.lua"))()
local VP = GRM.VehiclePrecache

print("\n=== 1. СБОР СПИСКА ===")
ok(isfunction(VP.Collect) and isfunction(VP.ValidModel), "чистые функции сбора объявлены")
ok(VP.ValidModel("models/buggy.mdl") and not VP.ValidModel("") and not VP.ValidModel("буквы"),
   "мусор не попадает в список моделей")
local models = VP.Collect({
    { { model = "models/Buggy.mdl" }, { model = "models/jeep.mdl" } },
    { { Model = "models/BUGGY.mdl" } },                 -- дубль в другом регистре
    { "models/airboat.mdl", "" },                       -- строки и пустышка
    { { model = 5 } },                                  -- мусор
})
ok(#models == 3, "дубли и мусор отсеяны", #models)
ok(models[1] == "models/airboat.mdl" and models[2] == "models/buggy.mdl",
   "список приведён к нижнему регистру и отсортирован", table.concat(models, ","))
ok(VP.Pending(models, { ["models/buggy.mdl"] = true }) == 2, "остаток считается верно")

print("\n=== 2. СТАРТ ПОРЦИЯМИ ===")
ok(istable(GRM._boot) and GRM._boot.tier == "idle",
   "предзагрузка вешается на GRM.Boot и в самый спокойный тир", GRM._boot and GRM._boot.tier)
list.Get = function(name)
    if name == "Vehicles" then
        return { car1 = { Model = "models/car1.mdl" }, car2 = { Model = "models/car2.mdl" } }
    end
    return {}
end
local queued = VP.Run(true)
ok(queued == 2, "в очередь встали обе модели", queued)
ok(istable(SPREAD) and SPREAD.opts.chunk == 4,
   "обход идёт через GRM.Perf.Spread порциями", SPREAD and SPREAD.opts.chunk)
ok((SPREAD.opts.priority or 0) < 0, "приоритет ниже игровых задач", SPREAD.opts.priority)

for _, m in ipairs(SPREAD.list) do SPREAD.fn(m) end
ok(PRECACHED["models/car1.mdl"] and PRECACHED["models/car2.mdl"], "модели реально прекэшированы")
ok(VP.Run(true) == 0, "повторный запуск не грузит то же самое дважды")

print("\n=== 3. ВЫКЛЮЧАТЕЛЬ И КОМАНДЫ ===")
CONVARS["grm_vehicle_precache"]:SetValue("0")
VP.Done = {}
ok(VP.Run() == 0, "конваром предзагрузку можно выключить")
CONVARS["grm_vehicle_precache"]:SetValue("1")
ok(isfunction(CMDS["grm_vehicles_precache"]) and isfunction(CMDS["grm_vehicles_precache_status"]),
   "команды принудительного запуска и статуса объявлены")

print("\n=== 4. ВЫНОСЛИВОСТЬ В МАШИНЕ ===")
local mv = (function()
    local f = io.open("lua/autorun/sh_grm_movement.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(mv:find("StaminaRegenSeated", 1, true) ~= nil, "у сидящего своя скорость восстановления")
ok(mv:find("if ply:InVehicle() then", 1, true) ~= nil
   and mv:find("data.stamina + (cfg.StaminaRegenSeated or cfg.StaminaRegen) * dt", 1, true) ~= nil,
   "в машине выносливость растёт, а не стоит на месте")
ok(mv:find("if IsValid(ply) and not ply:InVehicle() then", 1, true) == nil,
   "старое условие, выкидывавшее сидящих из тика, убрано")

print(("\nVEHICLE PRECACHE: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
