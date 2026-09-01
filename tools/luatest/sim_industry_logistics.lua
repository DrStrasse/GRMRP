--[[--------------------------------------------------------------------
    sim_industry_logistics — заказы, рейсы, склады фракций.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Логистику… надо полностью переделать».

    ЧТО БЫЛО В СТАРОЙ ЛОГИСТИКЕ. Награда платилась фиксом за коробку
    (600 за оружие, 300 за патроны, 200 за материалы), а минимум рейса —
    десять оружейных ящиков по семь стволов. Это 70 стволов при ёмкости
    склада 80, итого ~86 на ствол, тогда как скупщик даёт 1250–5000.
    Возить было невыгодно в десятки раз. Никакой связи с производством
    не существовало: общих идентификаторов и ёмкостей не было, перенос
    шёл только через руки игрока.

    ЧТО ПРОВЕРЯЕМ.
      * Склад сам формирует заказ по своему спросу.
      * Награда — процент от ценности груза, растёт с расстоянием и
        риском, падает при просрочке.
      * Груз возится в грузовом отсеке, а не в руках, и не пропадает
        при отказе от рейса.
      * На склад нельзя сдать больше, чем влезает — и это проверяется
        ДО разгрузки.
      * Просроченный заказ снимается, груз возвращается.

    Запуск: luajit tools/luatest/sim_industry_logistics.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- ================================================================
--  ОКРУЖЕНИЕ GMod
-- ================================================================
local NOW = 1000
local TIMERS = {}
local SIMPLE = {}
local NET_HANDLERS = {}
local PAID = {}

SERVER = true
function AddCSLuaFile() end

istable    = function(v) return type(v) == "table" end
isstring   = function(v) return type(v) == "string" end
isnumber   = function(v) return type(v) == "number" end
isfunction = function(v) return type(v) == "function" end
IsValid    = function(v) return type(v) == "table" and v.__dead ~= true end
function CurTime() return NOW end

game    = { GetMap = function() return "rp_test" end }
util    = { AddNetworkString = function() end }
weapons = { Get = function() return { WorldModel = "models/w.mdl" } end }
timer = {
    Create = function(name, delay, reps, fn) TIMERS[name] = fn end,
    Simple = function(delay, fn) SIMPLE[#SIMPLE + 1] = { at = NOW + (delay or 0), fn = fn } end,
}
local function runTimers()
    for i = #SIMPLE, 1, -1 do
        if NOW >= SIMPLE[i].at then
            local fn = SIMPLE[i].fn
            table.remove(SIMPLE, i)
            fn()
        end
    end
end

local Vec = {}
Vec.__index = Vec
local function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec) end
function Vec:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
function Vec:Distance(o) return math.sqrt(self:DistToSqr(o)) end

hook = { Add = function() end, Run = function() end, Remove = function() end }
net = {
    Start = function() net._buf = {} end,
    Send = function() end,
    SendToServer = function() end,
    Receive = function(name, fn) NET_HANDLERS[name] = fn end,
    WriteEntity = function() end, WriteString = function() end,
    WriteUInt = function() end, WriteFloat = function() end,
    WriteBool = function() end, WriteTable = function() end,
    ReadEntity = function() end, ReadString = function() return "" end,
    ReadUInt = function() return 0 end, ReadFloat = function() return 0 end,
    ReadBool = function() return false end, ReadTable = function() return {} end,
}
NULL = setmetatable({}, { __index = function() return function() return false end end })

concommand = { Add = function() end, Run = function() end }
HUD_PRINTCONSOLE = 2

GRM = GRM or {}
--[[ Хранилище в памяти с глубокой копией. Без копии сохранённая таблица
     продолжала бы меняться вместе с боевой, и круг save/load проверял бы
     сам себя. ]]
local STORE = {}
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end
GRM.Persistence = {
    SaveJSON = function(path, data) STORE[path] = deepCopy(data) return true, "saved" end,
    LoadJSON = function(path, defaults)
        if STORE[path] == nil then return deepCopy(defaults), "missing" end
        return deepCopy(STORE[path]), "ok"
    end,
}
GRM.Audit = { Write = function() end }
GRM.Access = { Register = function() end, Can = function() return true end }
GRM.Notify = function() end
GRM.GiveMoney = function(ply, amount) PAID[#PAID + 1] = { ply = ply, amount = amount } end
GRM.TakeMoney = function() end
GRM.GetBalance = function() return 0 end
GRM.HasMoney = function() return true end
GRM.Format = function(v) return tostring(v) end

-- ================================================================
--  БОЕВЫЕ ФАЙЛЫ
-- ================================================================
local function load(p)
    local chunk = assert(loadfile(p))
    chunk()
end
load("lua/autorun/sh_grm_industry_core.lua")
load("lua/autorun/sh_grm_industry_container.lua")
load("lua/autorun/server/sv_grm_industry.lua")
load("lua/autorun/server/sv_grm_industry_logistics.lua")

--[[ Регистрация предметов производства в инвентаре. Грузим её тем же
     файлом, что работает на сервере: без неё строгий инвентарь стенда
     отказывается принимать лом и изделия, и стенд краснеет ровно так,
     как краснел живой сервер. ]]
load("lua/autorun/zz_grm_industry_items.lua")

local I = GRM.Industry
local C = GRM.Container
local L = I.Config.Logistics
ok(I.Orders ~= nil and I.Routes ~= nil, "логистика загружена из боевого файла")
ok(I.NodeHandlers.depot ~= nil and I.NodeHandlers.warehouse ~= nil,
    "логистика зарегистрировала обработчики своих узлов")
ok(I.Actions.order_take ~= nil and I.Actions.order_deliver ~= nil,
    "действия логистики попали в общий реестр цеха")
ok(TIMERS["GRM_Industry_Logistics"] ~= nil, "тик логистики зарегистрирован")
local tickRoutes = TIMERS["GRM_Industry_Logistics"]

-- ================================================================
--  ФИКСИРОВАННЫЕ ОБЪЕКТЫ
-- ================================================================
local function newEnt(role)
    local e = { NodeRole = role, vars = {}, pos = V(0, 0, 0) }
    for _, name in ipairs({ "NodeID", "NodeKind", "FactionName", "NodeLabel", "WorkerName", "JobStage" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] or "" end
    end
    for _, name in ipairs({ "Stock", "Wear" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] or 0 end
    end
    for _, name in ipairs({ "Busy" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] == true end
    end
    e["SetProgress"] = function() end
    e.GetPos = function(self) return self.pos end
    e.SetModel = function() end
    e.PhysicsInit = function() end
    e.SetMoveType = function() end
    e.SetSolid = function() end
    e.GetPhysicsObject = function() return nil end
    e.EmitSound = function() end
    e.Nick = function() return "Логист" end
    e.GetNWString = function() return "" end
    e.SteamID64 = function() return "76561190000000002" end
    e.IsPlayer = function() return true end
    e.IsSuperAdmin = function() return true end
    return e
end

local function newPlayer(sid, faction, super)
    local p = newEnt("player")
    p.pos = V(0, 0, 0)
    p._sid = sid or "76561190000000002"
    p._faction = faction or ""
    p._super = super == true
    p.SteamID64 = function() return p._sid end
    p.GetNWString = function(_, key) return key == "GRM_Faction" and p._faction or "" end
    p.IsSuperAdmin = function() return p._super end
    p.Alive = function() return true end
    -- Оружие в руках: нужно для выдачи и сдачи в шкаф фракции.
    p._weapons = {}
    p.HasWeapon = function(_, cls) return p._weapons[cls] == true end
    p.Give = function(_, cls) p._weapons[cls] = true end
    p.StripWeapon = function(_, cls) p._weapons[cls] = nil end
    p.GetWeapon = function(_, cls)
        if not p._weapons[cls] then return nil end
        return { GetClass = function() return cls end }
    end
    p.GetWeapons = function()
        local out = {}
        for cls in pairs(p._weapons) do out[#out + 1] = { GetClass = function() return cls end } end
        return out
    end
    return p
end

--[[ Вызов боевого обработчика действий: читалки net подставляем сами.
     Так проверяется настоящая политика доступа из Actions, а не её копия. ]]
local function callAction(ply, ent, op, itemID, count)
    local handler = NET_HANDLERS["GRM_IND_Action"]
    if not handler then return end
    local strings = { op, itemID or "" }
    local si = 0
    net.ReadEntity = function() return ent end
    net.ReadString = function() si = si + 1 return strings[si] or "" end
    net.ReadUInt = function() return count or 1 end
    net.ReadTable = function() return {} end
    handler(64, ply)
end

--[[ Узлы и заказы живут в общих таблицах модуля, поэтому между
     разделами их надо сбрасывать. Без этого заказ второго раздела
     уезжал бы с депо из первого — и проверка «груз вернулся» проходила
     бы впустую, потому что груз никуда и не девался. ]]
local uid = 0
local function resetWorld()
    for id in pairs(I.Nodes) do I.Nodes[id] = nil end
    for id in pairs(C.Registry) do C.Registry[id] = nil end
    I.Orders = {}
    I.Routes = {}
    uid = 0
end

local function newNode(role, pos)
    uid = uid + 1
    local e = newEnt(role)
    e.pos = pos
    e.vars.NodeID = "node_" .. role .. "_" .. uid
    I.InitNode(e)
    return e, I.NodeFor(e)
end

-- ================================================================
print("\n=== 1. СКЛАД САМ ФОРМИРУЕТ ЗАКАЗ ===")
-- ================================================================
do
    resetWorld()
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(1000, 0, 0))
    wh.demand = { arccw_makarov = { min = 5, max = 20 }, gpu_basic = { min = 2, max = 8 } }

    local created = I.RefreshOrders(wh)
    ok(created == 1, "по спросу создан заказ", created)

    local order
    for _, o in pairs(I.Orders) do order = o break end
    ok(order ~= nil, "заказ виден в реестре")
    ok(order.from == depot.id, "груз везут с ближайшей точки отправления", order.from)
    ok(order.to == wh.id, "назначение — склад")
    ok(order.state == "open", "заказ открыт")
    ok(#order.lines == 2, "в заказе две позиции по спросу", #order.lines)
    ok(order.value > 0 and order.weight > 0, "у заказа посчитаны ценность и вес")

    -- Повторный вызов не плодит дубли.
    local again = I.RefreshOrders(wh)
    local count = 0
    for _ in pairs(I.Orders) do count = count + 1 end
    ok(count == 1, "повторный вызов обновил заказ, а не создал второй", count)

    -- Укомплектованный склад заказа не создаёт.
    local whEnt2, wh2 = newNode("warehouse", V(2000, 0, 0))
    wh2.demand = { gpu_basic = { min = 2, max = 8 } }
    C.Add(wh2.outID, "gpu_basic", 5)
    local before = 0
    for _ in pairs(I.Orders) do before = before + 1 end
    I.RefreshOrders(wh2)
    local after = 0
    for _ in pairs(I.Orders) do after = after + 1 end
    ok(after == before, "укомплектованный склад не заказывает", after - before)
end

-- ================================================================
print("\n=== 2. НАГРАДА СЧИТАЕТСЯ ОТ ЦЕННОСТИ ГРУЗА ===")
-- ================================================================
do
    resetWorld()
    -- ГЛАВНОЕ ОТЛИЧИЕ ОТ СТАРОЙ СИСТЕМЫ: не фикс за коробку.
    local cheap = I.RewardFor(1000, 0, 1, true)
    local rich = I.RewardFor(100000, 0, 1, true)
    ok(rich > cheap * 10, "ценный груз приносит пропорционально больше", rich / cheap)

    local near = I.RewardFor(100000, 0, 1, true)
    local far = I.RewardFor(100000, L.DistanceFull, 1, true)
    ok(far > near, "дальний рейс дороже", far .. " vs " .. near)

    local safe = I.RewardFor(100000, 0, 1, true)
    local risky = I.RewardFor(100000, 0, L.RiskMax, true)
    ok(risky > safe, "опасный район оплачивается выше")

    local onTime = I.RewardFor(100000, 0, 1, true)
    local late = I.RewardFor(100000, 0, 1, false)
    ok(late < onTime, "просрочка снижает оплату")

    --[[ СТАРАЯ БЕДА: 6000 за рейс из 70 стволов при цене ствола
         1250–5000. Проверяем, что награда сопоставима с ценой груза. ]]
    local bigOrder = { { itemID = "arccw_makarov", count = 20 } }
    local value = I.OrderValue(bigOrder)
    local reward = I.RewardFor(value, L.DistanceFull, L.RiskMax, true)
    ok(reward > value * 0.05, "награда за 20 стволов ощутима против их цены", reward .. " из " .. value)
    local perItem = reward / 20
    ok(perItem > I.PriceOf("arccw_makarov") * 0.05,
        "награда на ствол не унизительна против цены скупщика", perItem)
end

-- ================================================================
print("\n=== 3. РЕЙС: ВЗЯТЬ, ПОГРУЗИТЬ, ВЕЗТИ, СДАТЬ ===")
-- ================================================================
do
    resetWorld()
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(4000, 0, 0))
    wh.demand = { arccw_makarov = { min = 5, max = 10 } }

    -- Груз должен лежать на точке отправления.
    C.Add(depot.outID, "arccw_makarov", 12)
    C.Add(depot.outID, "components_box", 30)

    I.RefreshOrders(wh)
    local order
    for _, o in pairs(I.Orders) do order = o break end
    ok(order ~= nil, "заказ создан")

    local ply = newPlayer()
    ok(I.TakeOrder(ply, order.id) == true, "заказ взят")
    local route = I.RouteFor(ply)
    ok(route ~= nil, "рейс создан")
    ok(route.phase == "collect", "рейс на стадии погрузки", route.phase)
    ok(order.state == "taken", "заказ помечен взятым")
    ok(C.Capacity(route.cargo) > 0, "у грузового отсека есть лимит", C.Capacity(route.cargo))

    -- Второй рейс взять нельзя.
    local order2 = { id = "order_fake", state = "open" }
    I.Orders["order_fake"] = order2
    ok(I.TakeOrder(ply, "order_fake") == false, "второй рейс одновременно не взять")

    -- Погрузка: из заказа везём 10 стволов, не больше.
    local loaded = 0
    for i = 1, 12 do
        if I.LoadCargo(ply, depotEnt, "arccw_makarov", 10) then loaded = loaded + 1 end
    end
    ok(C.Count(route.cargo, "arccw_makarov") == 10, "погрузили ровно по заказу",
        C.Count(route.cargo, "arccw_makarov"))
    ok(I.LoadCargo(ply, depotEnt, "arccw_makarov", 1) == false,
        "сверх заказа не грузим — лишнее не повезём")

    -- То, чего нет в заказе, тоже не грузим.
    ok(I.LoadCargo(ply, depotEnt, "components_box", 5) == false, "груз вне заказа не принимается")

    ok(I.FinishLoading(ply) == true, "погрузка закрыта")
    ok(route.phase == "haul", "рейс в пути", route.phase)
    ok(I.LoadCargo(ply, depotEnt, "arccw_makarov", 1) == false, "после отправки грузить нельзя")

    -- Пробег копится, телепорт не считается.
    ply.pos = V(100, 0, 0)
    tickRoutes()
    ply.pos = V(200, 0, 0)
    tickRoutes()
    ok(route.distance > 0, "пробег считается", route.distance)
    local beforeTp = route.distance
    ply.pos = V(90000, 0, 0)
    tickRoutes()
    ok(route.distance == beforeTp, "телепорт пробегом не считается", route.distance - beforeTp)

    -- Сдача.
    PAID = {}
    ok(I.DeliverOrder(ply, whEnt) == true, "груз сдан")
    ok(C.Count(wh.outID, "arccw_makarov") == 10, "стволы на складе", C.Count(wh.outID, "arccw_makarov"))
    ok(C.IsEmpty(route.cargo) or C.Get(route.cargo) == nil, "грузовой отсек пуст")
    ok(I.RouteFor(ply) == nil, "рейс закрыт")
    ok(order.state == "delivered", "заказ выполнен")
    ok(#PAID == 1 and PAID[1].amount > 0, "награда выплачена", PAID[1] and PAID[1].amount)
    ok(PAID[1].amount > I.PriceOf("arccw_makarov") * 10 * 0.05,
        "награда соразмерна цене довезённого", PAID[1].amount)
    ok(PAID[1].ply == ply, "НАГРАДА УШЛА В РУКИ ВОДИТЕЛЯ, а не в казну фракции")
end

-- ================================================================
print("\n=== 4. ГРУЗ НЕ ПРОПАДАЕТ ===")
-- ================================================================
do
    resetWorld()
    -- ОТКАЗ ОТ РЕЙСА: груз возвращается на точку отправления.
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(3000, 0, 0))
    wh.demand = { gpu_basic = { min = 1, max = 5 } }
    C.Add(depot.outID, "gpu_basic", 8)
    I.RefreshOrders(wh)
    local order
    for _, o in pairs(I.Orders) do order = o break end

    local ply = newPlayer()
    I.TakeOrder(ply, order.id)
    local route = I.RouteFor(ply)
    I.LoadCargo(ply, depotEnt, "gpu_basic", 5)
    ok(C.Count(route.cargo, "gpu_basic") == 5, "погрузили пять карт")

    I.AbandonRoute(route, "Отказ")
    ok(I.RouteFor(ply) == nil, "рейс снят")
    ok(C.Count(depot.outID, "gpu_basic") == 8, "ВСЕ ПЯТЬ ВЕРНУЛИСЬ НА ТОЧКУ — груз не пропал",
        C.Count(depot.outID, "gpu_basic"))
    ok(order.state == "open", "заказ снова доступен другим")

    -- ПУСТЫМ НЕ ЕДЕМ.
    local depotEnt2, depot2 = newNode("depot", V(0, 0, 0))
    local whEnt2, wh2 = newNode("warehouse", V(2000, 0, 0))
    wh2.demand = { gpu_mid = { min = 1, max = 3 } }
    C.Add(depot2.outID, "gpu_mid", 3)
    I.RefreshOrders(wh2)
    local order2
    for _, o in pairs(I.Orders) do order2 = o break end
    local ply2 = newPlayer()
    ply2.SteamID64 = function() return "76561190000000099" end
    I.TakeOrder(ply2, order2.id)
    ok(I.FinishLoading(ply2) == false, "пустой рейс не отправляется")
    ok(I.RouteFor(ply2).phase == "collect", "рейс остался на погрузке")
end

-- ================================================================
print("\n=== 5. СКЛАД НЕ ПРИНИМАЕТ БОЛЬШЕ ВМЕСТИМОГО ===")
-- ================================================================
do
    --[[ СЦЕНАРИЙ СПЕЦИАЛЬНО ЧАСТИЧНЫЙ: места на складе хватает под одну
         позицию груза, но не под обе. Если проверять вместимость только
         посреди разгрузки, часть груза уже окажется на складе, а награда
         не выплатится — водитель останется и без оплаты, и с размазанным
         по двум местам грузом. ]]
    resetWorld()
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(2500, 0, 0))
    wh.demand = { gpu_basic = { min = 5, max = 20 }, components_box = { min = 2, max = 10 } }

    -- Оставляем на складе ровно 12 кг: videocard 1.5 кг влезут, ящики 3 кг — нет.
    local cap = C.Capacity(wh.outID)
    local unit = I.WeightOf("scrap_metal")
    C.Add(wh.outID, "scrap_metal", math.floor((cap - 12) / unit))
    ok(C.Free(wh.outID) >= I.WeightOf("gpu_basic") * 4, "под карты место есть", C.Free(wh.outID))
    ok(C.Free(wh.outID) < I.WeightOf("gpu_basic") * 4 + I.WeightOf("components_box") * 5,
        "под весь груз места нет", C.Free(wh.outID))

    C.Add(depot.outID, "gpu_basic", 30)
    C.Add(depot.outID, "components_box", 30)
    I.RefreshOrders(wh)
    local order
    for _, o in pairs(I.Orders) do order = o break end
    ok(order ~= nil, "заказ создан")
    if not order then return end

    local ply = newPlayer()
    I.TakeOrder(ply, order.id)
    local route = I.RouteFor(ply)
    local gpu = C.MoveUpTo(depot.outID, route.cargo, "gpu_basic", 4)
    local box = C.MoveUpTo(depot.outID, route.cargo, "components_box", 5)
    ok(gpu == 4 and box == 5, "в машине две позиции", gpu .. "/" .. box)
    I.FinishLoading(ply)

    PAID = {}
    ok(I.DeliverOrder(ply, whEnt) == false, "сдача в неполный склад не проходит")
    ok(#PAID == 0, "награда не выплачена — работа не сделана")
    ok(I.RouteFor(ply) ~= nil, "рейс остался активным")
    ok(C.Count(route.cargo, "gpu_basic") == 4, "карты остались в машине", C.Count(route.cargo, "gpu_basic"))
    ok(C.Count(route.cargo, "components_box") == 5, "ящики остались в машине", C.Count(route.cargo, "components_box"))
    ok(C.Count(wh.outID, "gpu_basic") == 0, "НИ ОДНОЙ КАРТЫ НЕ ПРОСОЧИЛОСЬ НА СКЛАД",
        C.Count(wh.outID, "gpu_basic"))
    ok(C.Count(wh.outID, "components_box") == 0, "НИ ОДНОГО ЯЩИКА НЕ ПРОСОЧИЛОСЬ",
        C.Count(wh.outID, "components_box"))
end

-- ================================================================
print("\n=== 6. ПРОСРОЧКА ===")
-- ================================================================
do
    resetWorld()
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(1500, 0, 0))
    wh.demand = { gpu_basic = { min = 1, max = 5 } }
    C.Add(depot.outID, "gpu_basic", 5)
    I.RefreshOrders(wh)
    local order
    for _, o in pairs(I.Orders) do order = o break end
    ok(order.state == "open", "заказ открыт")

    -- Сдвигаем срок в прошлое и прогоняем тик.
    order.deadline = os.time() - 10
    TIMERS["GRM_Industry_Logistics"]()
    ok(order.state == "expired", "просроченный заказ снят", order.state)
end

-- ================================================================
print("\n=== 7. ШКАФ ПРИНАДЛЕЖИТ ФРАКЦИИ (пункт 8) ===")
-- ================================================================
do
    --[[ БЫЛО: поле «фракция» у узла было подписью для окна, проверки не
         было вовсе — оружие из шкафа фракции мог забрать любой прохожий. ]]
    resetWorld()
    local armEnt, arm = newNode("armory", V(0, 0, 0))
    armEnt:SetFactionName("police")
    C.Add(arm.outID, "arccw_makarov", 3)

    local outsider = newPlayer("76561190000000101", "civ", false)
    local officer  = newPlayer("76561190000000102", "police", false)
    local chief    = newPlayer("76561190000000103", "army", true)   -- суперадмин

    ok(I.CanUseFactionNode(outsider, armEnt) == false, "чужой в шкаф не пускается")
    ok(I.CanUseFactionNode(officer, armEnt) == true, "сотрудник фракции пускается")
    ok(I.CanUseFactionNode(chief, armEnt) == true, "суперадмин пускается всегда")

    -- Действие приходит по сети, поэтому проверяем и сам обработчик:
    -- нельзя полагаться на то, что окно кто-то открывал.
    callAction(outsider, armEnt, "armory_take", "arccw_makarov", 1)
    ok(C.Count(arm.outID, "arccw_makarov") == 3, "ЧУЖОЙ НЕ ВЗЯЛ ОРУЖИЕ", C.Count(arm.outID, "arccw_makarov"))

    callAction(officer, armEnt, "armory_take", "arccw_makarov", 1)
    ok(C.Count(arm.outID, "arccw_makarov") == 2, "сотрудник фракции оружие взял",
        C.Count(arm.outID, "arccw_makarov"))

    -- Шкаф без фракции — общий.
    local pubEnt, pub = newNode("armory", V(50, 0, 0))
    C.Add(pub.outID, "arccw_p228", 1)
    ok(I.CanUseFactionNode(outsider, pubEnt) == true, "шкаф без фракции общий")
    callAction(outsider, pubEnt, "armory_take", "arccw_p228", 1)
    ok(C.Count(pub.outID, "arccw_p228") == 0, "из общего шкафа взял любой")
end

-- ================================================================
print("\n=== 8. РЕЙС ПЕРЕЖИВАЕТ ПЕРЕЗАПУСК (пункт 10) ===")
-- ================================================================
do
    --[[ БЫЛО: после рестарта рейс пропадал — груз уезжал обратно на
         точку отправления, а заказ снова открывался. Причина: рейс был
         привязан к персонажу, чей ключ после перезапуска не совпадал. ]]
    resetWorld()
    local depotEnt, depot = newNode("depot", V(0, 0, 0))
    local whEnt, wh = newNode("warehouse", V(6000, 0, 0))
    wh.demand = { arccw_makarov = { min = 5, max = 10 } }
    C.Add(depot.outID, "arccw_makarov", 12)

    I.RefreshOrders(wh)
    local order
    for _, o in pairs(I.Orders) do order = o break end

    local ply = newPlayer("76561190000000201", "", false)
    I.TakeOrder(ply, order.id)
    local route = I.RouteFor(ply)
    I.LoadCargo(ply, depotEnt, "arccw_makarov", 10)
    I.FinishLoading(ply)
    ok(route.phase == "haul", "рейс ушёл в путь")
    ok(C.Count(route.cargo, "arccw_makarov") == 10, "в машине десять стволов")

    -- Перезапуск: сохраняем и поднимаем состояние заново.
    I.SaveOrders()
    local savedKey = route.key
    I.Routes = {}
    C.Remove(route.cargo)
    ok(I.RouteFor(ply) == nil, "после «рестарта» рейса нет")

    I.LoadOrders()

    ok(I.Routes[savedKey] ~= nil, "РЕЙС ВОССТАНОВЛЕН после перезапуска")
    local back = I.Routes[savedKey]
    ok(back.phase == "haul", "стадия сохранена: груз в пути", back.phase)
    ok(C.Count(back.cargo, "arccw_makarov") == 10, "ГРУЗ ЦЕЛ — десять стволов в машине",
        C.Count(back.cargo, "arccw_makarov"))
    ok(back.driver == nil, "водителя пока нет — он ещё не зашёл")
    ok(I.Orders[order.id] ~= nil and I.Orders[order.id].state == "taken",
        "заказ остался за водителем, а не откатился в «открыт»")

    -- Водитель заходит — рейс подцепляется сам.
    ok(I.AttachRoute(ply) == back, "рейс подцепился к вошедшему водителю")
    ok(I.RouteFor(ply) == back, "RouteFor нашёл восстановленный рейс")

    -- И его можно довезти и сдать.
    PAID = {}
    ok(I.DeliverOrder(ply, whEnt) == true, "восстановленный рейс сдан")
    ok(C.Count(wh.outID, "arccw_makarov") == 10, "груз доехал до склада")
    ok(#PAID == 1 and PAID[1].ply == ply, "награда выплачена водителю")
end

-- ================================================================
print("\n=== ИТОГ ===")
print("  пройдено: " .. pass .. ", провалено: " .. fail)
if fail > 0 then os.exit(1) end
