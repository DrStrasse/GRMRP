--[[--------------------------------------------------------------------
    sim_taxi_ride — живой прогон заказа такси от вызова до высадки.

    ЧТО ЛОВИТ (найдено разбором 29.08, все пять багов воспроизводятся
    этим стендом на коде ДО фикса):

      1. У заявки не было точки назначения. Тип точки taxi_dropoff есть
         в конфиге, но живое такси его не использовало: заказ закрывался
         на посадке, поездки в системе не существовало.
      2. Деньги списывались при ПОСАДКЕ. Водителю было выгодно тут же
         высадить клиента: оплата уже получена, заказ закрыт.
      3. Возврата не было ни в одном сценарии — ни при отмене в пути,
         ни при выходе водителя с сервера.
      4. JB.TaxiRequests только пополнялась. Свип помечал cancelled, но
         записи не удалял: утечка памяти, и каждый вызов такси перебирал
         всё кладбище заявок.
      5. Не было проверки «заказчик ≠ водитель» — таксист вызывал сам
         себе и перекладывал деньги из кармана в карман, накручивая
         статистику.

    Запуск: luajit tools/luatest/sim_taxi_ride.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }

local now = 100
local wallTime = 1700000000
function CurTime() return now end
function SysTime() return now end
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
math.Clamp = function(v, lo, hi) v = tonumber(v) or lo if v < lo then return lo end if v > hi then return hi end return v end
string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

os = setmetatable({ time = function() return wallTime end }, { __index = _G.os })

local HOOKS = {}
hook = {
    Add = function(ev, name, fn) HOOKS[ev] = HOOKS[ev] or {} HOOKS[ev][name] = fn end,
    Remove = function(ev, name) if HOOKS[ev] then HOOKS[ev][name] = nil end end,
    Run = function(ev, ...) for _, fn in pairs(HOOKS[ev] or {}) do fn(...) end end,
}
local function fire(ev, ...) for _, fn in pairs(HOOKS[ev] or {}) do fn(...) end end

local TIMERS = {}
timer = {
    Create = function(name, delay, reps, fn) TIMERS[name] = fn end,
    Simple = function(_, fn) fn() end,
    Remove = function(name) TIMERS[name] = nil end,
}
util = { AddNetworkString = function() end }
net = {
    Receive = function() end, Start = function() end, Send = function() end,
    WriteTable = function() end, WriteUInt = function() end, WriteString = function() end,
    ReadTable = function() return {} end, ReadUInt = function() return 0 end,
}

-- Кошельки: считаем каждое движение денег, чтобы поймать двойные списания.
local WALLET, MONEYLOG = {}, {}
GRM = {
    Jobs = {},
    HasMoney = function(p, amount) return (WALLET[p] or 0) >= amount end,
    TakeMoney = function(p, amount, why)
        WALLET[p] = (WALLET[p] or 0) - amount
        MONEYLOG[#MONEYLOG + 1] = { who = p, delta = -amount, why = why }
    end,
    GiveMoney = function(p, amount, why)
        WALLET[p] = (WALLET[p] or 0) + amount
        MONEYLOG[#MONEYLOG + 1] = { who = p, delta = amount, why = why }
    end,
    Notify = function() end,
    Format = function(v) return tostring(v) end,
}

local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }

local function mkPlayer(name, charKey, x)
    local p = {
        _valid = true, _key = charKey, _pos = Vector(x or 0, 0, 0), nw = {}, _veh = nil,
    }
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:IsPlayer() return true end
    function p:Alive() return true end
    function p:Nick() return name end
    function p:SteamID64() return charKey:match("^(%d+)") or "1" end
    function p:GetNWString(_, d) return name end
    function p:SetNWString() end
    function p:SetNWBool() end
    function p:SetNWInt() end
    function p:InVehicle() return self._veh ~= nil end
    function p:GetVehicle() return self._veh end
    function p:ChatPrint() end
    -- На PlayerDisconnected висит ещё и хук мусора (снимает коробку из рук).
    -- Без этой заглушки стенд падал бы в чужом обработчике, а не проверял такси.
    function p:GetNWEntity() return NULL end
    PLAYERS[#PLAYERS + 1] = p
    return p
end

local function mkVehicle()
    local v = { _valid = true, nw = {} }
    function v:GetParent() return nil end
    function v:GetNWEntity() return nil end
    function v:EntIndex() return 42 end
    return v
end

local JB = GRM.Jobs
JB.WorkConfig = { taxiMin = 100, taxiMax = 5000, taxiDefault = 700 }
JB.WorkPoints = {
    { id = "pu1", type = "taxi_pickup",  name = "Вокзал",  pos = { x = 0,    y = 0, z = 0 } },
    { id = "do1", type = "taxi_dropoff", name = "Аэропорт", pos = { x = 4000, y = 0, z = 0 } },
    { id = "do2", type = "taxi_dropoff", name = "Рынок",    pos = { x = 6000, y = 0, z = 0 } },
}
--[[ Ключ персонажа берём с объекта БЕЗ проверки IsValid: в момент
     PlayerDisconnected игрок в GMod ещё существует, но часть кода уже
     считает его невалидным. Если ключ в этот момент выродится в "",
     заказ не найдётся и повиснет — именно это и проверяет раздел 7. ]]
JB.CharacterKey = function(p) return (type(p) == "table" and p._key) or "" end
JB.GetTaxiFare = function() return 700 end
JB.IsWorkVehicleAllowed = function() return true end
JB.SaveActive = function() end
JB.PushTracker = function() end
JB.PushMyState = function() end

local ACTIVE = {}
JB.GetActiveJob = function(p) return ACTIVE[p] end

-- Точки назначения берём из общего конфига работ, как это делает боевой код.
local function pointObject(rec)
    local pos = Vector(rec.pos.x, rec.pos.y, rec.pos.z)
    return { _grmJobPoint = rec, GetPos = function() return pos end,
        GetNWString = function(_, k, d) if k == "GRM_JobZoneName" then return rec.name end return d end }
end
JB.GetRoutePoints = function(kind)
    local out = {}
    for _, rec in ipairs(JB.WorkPoints) do if rec.type == kind then out[#out + 1] = pointObject(rec) end end
    if #out > 0 then return out end
    return nil
end

assert(loadfile("lua/autorun/sh_grm_jobs_v4.lua"))()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

--[[ УСТОЙЧИВОСТЬ СТЕНДА.
     На коде ДО фикса половины API просто нет (JB.AcceptTaxi была приватной,
     dropoff не существовал). Если стенд свалится на первом же nil, он
     покажет три провала вместо всех и создаст ложное впечатление, будто
     остальное в порядке. Поэтому вызовы отсутствующего API оборачиваем:
     проверка честно краснеет, а прогон продолжается. ]]
local function callAccept(driver, id)
    if not isfunction(JB.AcceptTaxi) then return false, "JB.AcceptTaxi отсутствует" end
    local good, res = pcall(JB.AcceptTaxi, driver, id)
    if not good then return false, tostring(res) end
    return res
end
local function tick(driver)
    if not isfunction(JB.TickTaxiJob) then return end
    pcall(JB.TickTaxiJob, driver, ACTIVE[driver])
end
local function reqOf(id) return (id and JB.TaxiRequests[id]) or {} end

local driver = mkPlayer("Водитель", "111:char1", 3000)
local rider  = mkPlayer("Пассажир", "222:char1", 0)
WALLET[driver], WALLET[rider] = 0, 5000

ACTIVE[driver] = { tplId = "taxi", jtype = "taxi", taxiStandby = true, stage = 0 }

print("\n=== 1. ВЫЗОВ: У ЗАКАЗА ЕСТЬ ТОЧКА НАЗНАЧЕНИЯ ===")
local called, id = JB.CallTaxi(rider, "chat")
ok(called, "заказ создан", id)
local req = JB.TaxiRequests[id]
ok(istable(req) and istable(req.dropoff), "у заявки есть точка назначения",
    req and tostring(req.dropoff))
ok(istable(req) and tostring(req.dropoffName or "") ~= "", "назначение названо человеко-понятно",
    req and req.dropoffName)

print("\n=== 2. ТАКСИСТ НЕ ВОЗИТ САМ СЕБЯ ===")
-- Водитель на линии вызывает такси сам себе: раньше это проходило и
-- позволяло гонять деньги по кругу, накручивая статистику.
local selfOK, selfWhy = JB.CallTaxi(driver, "chat")
ok(not selfOK, "водителю на линии отказано в вызове такси", selfWhy)

print("\n=== 3. ПОСАДКА НЕ ЗАБИРАЕТ ДЕНЬГИ ===")
ok(callAccept(driver, id) == true, "водитель принял заказ")
driver:SetPos(Vector(0, 0, 0))                  -- подъехал к клиенту
tick(driver)
ok(reqOf(id).status == "arrived", "статус: прибыл на посадку", reqOf(id).status)

local veh = mkVehicle()
driver._veh, rider._veh = veh, veh
fire("PlayerEnteredVehicle", rider, veh)

local riderBefore = WALLET[rider]
ok(WALLET[rider] == 5000, "при посадке с пассажира НЕ списано", WALLET[rider])
ok(WALLET[driver] == 0, "при посадке водителю НЕ начислено", WALLET[driver])
ok(reqOf(id).status == "riding", "заказ перешёл в поездку, а не закрылся", reqOf(id).status)

print("\n=== 4. ОПЛАТА ТОЛЬКО ПО ПРИБЫТИИ В НАЗНАЧЕНИЕ ===")
driver:SetPos(Vector(2000, 0, 0)) rider:SetPos(Vector(2000, 0, 0))
tick(driver)
ok(WALLET[rider] == riderBefore, "на полпути денег не берут", WALLET[rider])
ok(reqOf(id).status == "riding", "заказ ещё в пути", reqOf(id).status)

local dp = reqOf(id).dropoff or { x = 4000, y = 0, z = 0 }
driver:SetPos(Vector(dp.x, dp.y, dp.z)) rider:SetPos(Vector(dp.x, dp.y, dp.z))
tick(driver)
ok(reqOf(id).status == "completed", "по прибытии заказ завершён", reqOf(id).status)
ok(WALLET[rider] == 5000 - 700, "с пассажира списана такса ровно один раз", WALLET[rider])
ok(WALLET[driver] == 700, "водитель получил оплату", WALLET[driver])

print("\n=== 5. ЗАВЕРШЁННЫЕ ЗАЯВКИ НЕ КОПЯТСЯ В ПАМЯТИ ===")
-- Свип обязан убирать закрытые записи, иначе таблица растёт вечно, а
-- TaxiStatus перебирает её на каждый вызов такси.
if JB.TaxiRequests[id] then JB.TaxiRequests[id].completed = wallTime - 600 end
wallTime = wallTime + 600
if TIMERS["GRM_Taxi_RequestSweep"] then TIMERS["GRM_Taxi_RequestSweep"]() end
ok(JB.TaxiRequests[id] == nil, "закрытая заявка удалена свипом")
ok(table.Count(JB.TaxiRequests) == 0, "кладбище заявок пустое",
    table.Count(JB.TaxiRequests))

print("\n=== 6. ОТМЕНА В ПУТИ ВОЗВРАЩАЕТ ДЕНЬГИ ===")
driver._veh, rider._veh = nil, nil
rider:SetPos(Vector(0, 0, 0)) driver:SetPos(Vector(3000, 0, 0))
ACTIVE[driver] = { tplId = "taxi", jtype = "taxi", taxiStandby = true, stage = 0 }
WALLET[driver], WALLET[rider] = 0, 5000

local ok2, id2 = JB.CallTaxi(rider, "chat")
ok(ok2, "второй заказ создан")
callAccept(driver, id2)
driver:SetPos(Vector(0, 0, 0))
tick(driver)
local veh2 = mkVehicle()
driver._veh, rider._veh = veh2, veh2
fire("PlayerEnteredVehicle", rider, veh2)
ok(reqOf(id2).status == "riding", "поездка началась", reqOf(id2).status)

JB.CancelTaxi(rider, "передумал в пути")
ok(WALLET[rider] == 5000, "пассажиру ничего не стоило: деньги не списывались вперёд",
    WALLET[rider])
ok(reqOf(id2).status == "cancelled", "заказ отменён", reqOf(id2).status)

print("\n=== 7. ВОДИТЕЛЬ УШЁЛ С СЕРВЕРА — ПАССАЖИР НЕ В МИНУСЕ ===")
ACTIVE[driver] = { tplId = "taxi", jtype = "taxi", taxiStandby = true, stage = 0 }
WALLET[driver], WALLET[rider] = 0, 5000
rider:SetPos(Vector(0, 0, 0)) driver:SetPos(Vector(3000, 0, 0))
driver._veh, rider._veh = nil, nil
local ok3, id3 = JB.CallTaxi(rider, "chat")
callAccept(driver, id3)
driver:SetPos(Vector(0, 0, 0))
tick(driver)
local veh3 = mkVehicle()
driver._veh, rider._veh = veh3, veh3
fire("PlayerEnteredVehicle", rider, veh3)
ok(WALLET[rider] == 5000, "в поездке деньги ещё у пассажира", WALLET[rider])

driver._valid = false                            -- водитель отключился
fire("PlayerDisconnected", driver)
ok(WALLET[rider] == 5000, "пассажир не потерял ни копейки", WALLET[rider])
ok(JB.TaxiRequests[id3] == nil or JB.TaxiRequests[id3].status == "cancelled",
    "заказ снят вместе с водителем")

print(("\nTAXI RIDE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
