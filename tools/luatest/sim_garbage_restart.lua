--[[--------------------------------------------------------------------
    sim_garbage_restart — рейс мусоровоза переживает перезапуск сервера.

    БАГ (найден разбором 29.08). Пакеты в кузове жили ТОЛЬКО на энтити:
    поле veh.GRM_GarbageLoad и NW-переменная. Активная работа при этом
    честно сохранялась на диск, вместе со счётчиком garbageCollected.

    После рестарта машина исчезает, работа остаётся. Игрок возвращается
    к рейсу, где в прогрессе «собрано 3/3», а кузов пустой. Полигон
    принимает только полный рейс — доехать нельзя, сдать нельзя,
    остаётся только провалить работу и потерять время.

    ЧТО ПРОВЕРЯЕМ:
      1. загруженные пакеты попадают в сохраняемое поле работы;
      2. после «рестарта» (перезагрузка активных задач с диска) счётчик
         на месте;
      3. игрок может сдать восстановленный рейс на полигоне — груз
         возвращается в кузов новой машины, тупика нет;
      4. кузов не удаётся «надуть» сверх вместимости повторной посадкой.

    Запуск: luajit tools/luatest/sim_garbage_restart.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }

local now = 100
function CurTime() return now end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    function v:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
    return v
end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
math.Clamp = function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

local HOOKS = {}
hook = {
    Add = function(ev, name, fn) HOOKS[ev] = HOOKS[ev] or {} HOOKS[ev][name] = fn end,
    Remove = function(ev, name) if HOOKS[ev] then HOOKS[ev][name] = nil end end,
    Run = function() end,
}
timer = { Create = function() end, Simple = function(_, fn) fn() end, Remove = function() end }
util = { AddNetworkString = function() end }
net = { Receive = function() end, Start = function() end, Send = function() end,
        WriteTable = function() end, WriteUInt = function() end, WriteString = function() end }
ents = { FindByClass = function() return {} end, FindInSphere = function() return {} end }
player = { GetAll = function() return {} end }

GRM = { Jobs = {}, Notify = function() end, Format = tostring }
local JB = GRM.Jobs
JB.WorkConfig = { garbageCapacity = 3, garbageUnloadTime = 3, garbageDumpRadius = 320,
                  garbageBindRadius = 200, garbageStops = 3 }
JB.WorkPoints = {
    { id = "p1", type = "garbage", name = "Сбор 1", pos = { x = 0,    y = 0, z = 0 } },
    { id = "p2", type = "garbage", name = "Сбор 2", pos = { x = 500,  y = 0, z = 0 } },
    { id = "p3", type = "garbage", name = "Сбор 3", pos = { x = 900,  y = 0, z = 0 } },
    { id = "d1", type = "dump",    name = "Полигон", pos = { x = 2000, y = 0, z = 0 } },
}
JB.PushTracker = function() end
JB.PushMyState = function() end
JB.SaveActive = function() end
JB.IsVehicleClassAllowed = function() return true end

local ACTIVE
JB.GetActiveJob = function() return ACTIVE end

assert(loadfile("lua/autorun/sh_grm_jobs_v5.lua"))()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer()
    local p = { _valid = true, nw = {}, _pos = Vector(2000, 0, 0) }
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:Nick() return "Мусорщик" end
    function p:SetNWBool(k, v) self.nw[k] = v end
    function p:SetNWFloat(k, v) self.nw[k] = v end
    function p:SetNWEntity(k, v) self.nw[k] = v end
    function p:GetNWEntity(k) return self.nw[k] or NULL end
    function p:GetNWString(_, d) return d end
    function p:ChatPrint() end
    return p
end

local function mkTruck(load)
    local v = { _valid = true, nw = {}, GRM_GarbageLoad = load or 0, _pos = Vector(2000, 0, 0) }
    function v:GetParent() return nil end
    function v:GetNWEntity() return NULL end
    function v:GetPos() return self._pos end
    function v:GetVelocity() return Vector(0, 0, 0) end
    function v:GetDriver() return self._driver end
    function v:SetNWInt(k, x) self.nw[k] = x end
    function v:GetNWInt(k, d) local x = self.nw[k] if x == nil then return d end return x end
    function v:SetNWString(k, x) self.nw[k] = x end
    function v:GetNWString(k, d) local x = self.nw[k] if x == nil then return d end return x end
    function v:SetNWFloat(k, x) self.nw[k] = x end
    function v:GetNWFloat(k, d) local x = self.nw[k] if x == nil then return d end return x end
    function v:SetNWEntity(k, x) self.nw[k] = x end
    function v:EntIndex() return 77 end
    return v
end

print("\n=== 1. ГРУЗ ПОПАДАЕТ В СОХРАНЯЕМОЕ ПОЛЕ РАБОТЫ ===")
-- Собранные пакеты обязаны отражаться в garbageCollected: это
-- единственное поле рейса, которое переживает перезапуск.
ACTIVE = { tplId = "garbage", jtype = "garbage",
           points = { { x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 }, { x = 900, y = 0, z = 0 }, { x = 2000, y = 0, z = 0 } },
           pointNames = { "Сбор 1", "Сбор 2", "Сбор 3", "Полигон" },
           pointIndex = 4, garbageCollected = 3,
           garbagePointIDs = { "p1", "p2", "p3" }, garbageDumpID = "d1", routeState = "ready" }

local core = io.open("lua/autorun/sh_grm_jobs.lua"):read("*a")
ok(core:find("garbageCollected=tonumber(j.garbageCollected)or 0", 1, true) ~= nil,
    "счётчик собранных пакетов пишется в файл активных задач")
ok(core:find("garbageCollected=tonumber(r.garbageCollected)", 1, true) ~= nil,
    "и читается обратно при загрузке")

print("\n=== 2. ПОСЛЕ РЕСТАРТА КУЗОВ ВОССТАНАВЛИВАЕТСЯ ===")
--[[ Ключевая проверка. Машина после рестарта новая и пустая, но рейс
     помнит, что собрано 3 пакета. Система обязана вернуть груз в кузов,
     иначе полигон не примет рейс и работа станет тупиком. ]]
local ply = mkPlayer()
local truck = mkTruck(0)                       -- свежая машина: груза нет
truck._driver = ply

ok(isfunction(JB.RestoreGarbageLoad), "есть восстановление груза после рестарта")
if isfunction(JB.RestoreGarbageLoad) then
    JB.RestoreGarbageLoad(ply, ACTIVE, truck)
end
ok(JB.GetGarbageLoad(truck) == 3, "в кузов вернулись 3 собранных пакета",
    JB.GetGarbageLoad(truck))

print("\n=== 3. ВОССТАНОВЛЕННЫЙ РЕЙС МОЖНО СДАТЬ ===")
JB.Complete = function() JB.completed = true end
JB.completed = false
JB.TickGarbageDump(ply, ACTIVE, truck, Vector(2000, 0, 0), 170)
ok(ACTIVE.garbageUnloadAt ~= nil, "выгрузка началась, а не упёрлась в «соберите 3/3»",
    tostring(ACTIVE.garbageUnloadAt))
now = now + 10
JB.TickGarbageDump(ply, ACTIVE, truck, Vector(2000, 0, 0), 170)
ok(JB.completed == true, "рейс закрыт на полигоне")
ok(JB.GetGarbageLoad(truck) == 0, "кузов опустел после сдачи", JB.GetGarbageLoad(truck))

print("\n=== 4. ПОВТОРНАЯ ПОСАДКА НЕ НАДУВАЕТ КУЗОВ ===")
--[[ Восстановление не должно превращаться в дупликатор: сел-вышел-сел
     не обязано каждый раз доливать пакеты сверх собранного. ]]
local ply2 = mkPlayer()
local truck2 = mkTruck(0)
truck2._driver = ply2
local job2 = { tplId = "garbage", jtype = "garbage", garbageCollected = 2,
               points = { { x = 0, y = 0, z = 0 }, { x = 2000, y = 0, z = 0 } },
               pointNames = { "Сбор", "Полигон" }, pointIndex = 2,
               garbagePointIDs = { "p1" }, garbageDumpID = "d1", routeState = "ready" }
if isfunction(JB.RestoreGarbageLoad) then
    JB.RestoreGarbageLoad(ply2, job2, truck2)
    JB.RestoreGarbageLoad(ply2, job2, truck2)
    JB.RestoreGarbageLoad(ply2, job2, truck2)
end
ok(JB.GetGarbageLoad(truck2) == 2, "груз ровно как в рейсе, а не втрое больше",
    JB.GetGarbageLoad(truck2))

print("\n=== 5. ЧУЖОЙ ГРУЗ НЕ ЗАТИРАЕТСЯ ===")
-- Если в кузове уже больше, чем помнит рейс (доехал и догрузил), то
-- восстановление не должно уменьшать реальный груз.
local truck3 = mkTruck(3)
truck3._driver = ply2
local job3 = { tplId = "garbage", garbageCollected = 1 }
if isfunction(JB.RestoreGarbageLoad) then JB.RestoreGarbageLoad(ply2, job3, truck3) end
ok(JB.GetGarbageLoad(truck3) == 3, "фактический груз в кузове важнее счётчика",
    JB.GetGarbageLoad(truck3))

print(("\nGARBAGE RESTART: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
