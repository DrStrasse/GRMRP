--[[--------------------------------------------------------------------
    GRM Industry — логистика: заказы, рейсы, склады и шкафы фракций.

    ЧТО ИЗМЕНИЛОСЬ ПРИНЦИПИАЛЬНО. Старая логистика платила фиксированную
    сумму за коробку (600 за оружие, 300 за патроны, 200 за материалы)
    и требовала довезти минимум десять оружейных ящиков по семь стволов —
    то есть 70 стволов при ёмкости склада 80. Награда за такой рейс
    выходила ~86 на ствол, тогда как скупщик даёт 1250–5000. Возить
    было невыгодно в десятки раз, и система держалась только на роли.

    Здесь рейс закрывает ЗАКАЗ склада, а награда считается процентом от
    ценности груза с надбавками за расстояние и риск. Возить ценное
    на дальняк через опасный район выгодно; возить дешёвое через
    дорогу — нет. Выбор появляется у игрока, а не у таблицы.
----------------------------------------------------------------------]]

if not SERVER then return end

GRM = GRM or {}
local I = GRM.Industry
local C = GRM.Container
if not I or not C then
    print("[GRM Industry] логистика: ядро не загружено")
    return
end

local CFG = I.Config
local L = I.Config.Logistics
local NET = I.NET

I.Orders = I.Orders or {}
I.Routes = I.Routes or {}          -- [charKey] = рейс

local ROUTE_CAPACITY = 1200        -- кг, грузовой отсек машины
local PICKUP_RANGE   = 260

-- ================================================================
--  ПОМОЩНИКИ
-- ================================================================
local function notify(ply, message, ok)
    if not IsValid(ply) then return end
    if GRM.Notify then GRM.Notify(ply, tostring(message or ""), ok and 100 or 235, ok and 220 or 90, ok and 100 or 90) end
end

local function newID(prefix)
    return tostring(prefix or "x") .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

local function inRange(ply, ent, range)
    if not (IsValid(ply) and IsValid(ent)) then return false end
    return ply:GetPos():DistToSqr(ent:GetPos()) <= (tonumber(range) or 200) ^ 2
end

local function routeContainerID(key)
    return "ind:route:" .. tostring(key)
end

local function riskAt(ply, pos)
    local risk = tonumber(L.RiskDefault) or 1
    local extra = hook.Run("GRM_IndustryRouteRisk", ply, pos)
    if tonumber(extra) then risk = risk + tonumber(extra) end
    return math.max(1, math.min(tonumber(L.RiskMax) or 1.6, risk))
end

-- ================================================================
--  ЗАКАЗЫ
-- ================================================================
--[[ Склад формирует потребность сам: чего меньше минимума — то и
     заказывается. Раньше логист решал это на глаз и вёз что придётся. ]]
function I.RefreshOrders(warehouseRec)
    if not warehouseRec or warehouseRec.role ~= "warehouse" then return 0 end
    local stock = {}
    for _, line in ipairs(C.List(warehouseRec.outID)) do stock[line.itemID] = line.count end

    local lines = I.DemandLines(stock, warehouseRec.demand or {})
    if #lines == 0 then return 0 end

    -- Уже висящий заказ этого склада обновляем, а не плодим новые.
    local existing
    for _, order in pairs(I.Orders) do
        if order.to == warehouseRec.id and order.state == "open" then existing = order break end
    end

    local value, weight = I.OrderValue(lines)
    local source = I.NearestDepot(warehouseRec)
    if not source then return 0 end

    if existing then
        existing.lines = lines
        existing.value = value
        existing.weight = weight
        existing.from = source
        existing.reward = I.RewardFor(value, I.DistanceBetween(source, warehouseRec.id),
            tonumber(L.RiskDefault) or 1, true)
        return 0
    end

    local order = {
        id = newID("order"),
        from = source,
        to = warehouseRec.id,
        lines = lines,
        value = value,
        weight = weight,
        reward = I.RewardFor(value, I.DistanceBetween(source, warehouseRec.id), tonumber(L.RiskDefault) or 1, true),
        createdAt = os.time(),
        deadline = os.time() + (tonumber(L.DefaultDeadline) or 1800),
        state = "open",
        carrier = nil,
        public = true,
    }
    I.Orders[order.id] = order
    I.SaveSoon()
    return 1
end

function I.NearestDepot(warehouseRec)
    if not (IsValid(warehouseRec.ent)) then
        -- Склад ещё не заспавнен на карте — берём первый попавшийся депо.
        for _, rec in pairs(I.Nodes) do if rec.role == "depot" then return rec.id end end
        return nil
    end
    local best, bestD = nil, math.huge
    local pos = warehouseRec.ent:GetPos()
    for _, rec in pairs(I.Nodes) do
        if rec.role == "depot" and IsValid(rec.ent) then
            local d = rec.ent:GetPos():DistToSqr(pos)
            if d < bestD then best, bestD = rec.id, d end
        end
    end
    return best
end

-- Расстояние между узлами: по сущностям, если они на карте, иначе 0.
function I.DistanceBetween(aID, bID)
    local a, b = I.Nodes[aID], I.Nodes[bID]
    if not (a and b) then return 0 end
    if IsValid(a.ent) and IsValid(b.ent) then return a.ent:GetPos():Distance(b.ent:GetPos()) end
    return 0
end

local function expireOrders()
    if not next(I.Orders) then return end
    local now = os.time()
    for id, order in pairs(I.Orders) do
        if order.state == "open" and now > (tonumber(order.deadline) or now) then
            order.state = "expired"
        elseif order.state == "taken" and now - (tonumber(order.takenAt) or now) > (tonumber(L.ExpireAfter) or 21600) then
            order.state = "expired"
            local route = order.carrier and I.Routes[order.carrier] or nil
            if route then I.AbandonRoute(route, "Заказ просрочен") end
        end
    end
end

-- ================================================================
--  РЕЙСЫ
-- ================================================================
--[[ КЛЮЧ РЕЙСА — ПО АККАУНТУ, а не по персонажу (пункт 10 из списка
     вопросов владельца). Раньше рейс не переживал перезапуск сервера:
     груз уезжал обратно на точку отправления, а заказ снова открывался,
     потому что привязанный к персонажу ключ после рестарта не совпадал.

     Персонаж один активный на аккаунт, поэтому рейс логично вешается
     на SteamID64: тогда после входа игрока рейс подцепляется сам, а
     смена персонажа не теряет груз. ]]
function I.RouteKey(ply)
    if not IsValid(ply) then return "" end
    return "s" .. tostring(ply:SteamID64() or "")
end

function I.RouteFor(ply)
    if not IsValid(ply) then return nil end
    return I.Routes[I.RouteKey(ply)]
end

--[[ ПОДЦЕПИТЬ РЕЙС К ВОШЕДШЕМУ ИГРОКУ. Вызывается при входе: если есть
     сохранённый рейс этого аккаунта без живого водителя, он продолжается
     с той же стадии и с тем же грузом. ]]
function I.AttachRoute(ply)
    if not IsValid(ply) then return nil end
    local sid = tostring(ply:SteamID64() or "")
    if sid == "" then return nil end
    for key, route in pairs(I.Routes) do
        if not IsValid(route.driver) and route.driverSID == sid then
            route.driver = ply
            route.lastPos = ply:GetPos()
            notify(ply, "Рейс восстановлен: " ..
                (route.phase == "collect" and "догрузитесь на точке отправления"
                                           or "везём груз на склад"), true)
            return route
        end
    end
    return nil
end

hook.Add("PlayerInitialSpawn", "GRM_Industry_RouteAttach", function(ply)
    timer.Simple(3, function()
        if IsValid(ply) then I.AttachRoute(ply) end
    end)
end)

function I.TakeOrder(ply, orderID)
    local key = I.RouteKey(ply)
    if I.Routes[key] then notify(ply, "У вас уже есть рейс", false) return false end

    local order = I.Orders[orderID]
    if not order or order.state ~= "open" then notify(ply, "Заказ недоступен", false) return false end

    local cargoID = routeContainerID(key)
    C.Remove(cargoID)
    C.Ensure(cargoID, "store", key, ROUTE_CAPACITY)

    local route = {
        key = key,
        driver = ply,
        driverSID = tostring(ply:SteamID64() or ""),
        cargo = cargoID,
        orders = { orderID },
        phase = "collect",
        startPos = IsValid(ply) and ply:GetPos() or nil,
        distance = 0,
        lastPos = IsValid(ply) and ply:GetPos() or nil,
        startedAt = os.time(),
    }
    I.Routes[key] = route
    order.state = "taken"
    order.carrier = key
    order.takenAt = os.time()

    notify(ply, "Заказ взят. Погрузка на точке отправления.", true)
    I.SaveSoon()
    return true
end

-- Погрузка: из контейнера депо в грузовой отсек.
function I.LoadCargo(ply, ent, itemID, count)
    local key = I.RouteKey(ply)
    local route = I.Routes[key]
    if not route then notify(ply, "Нет активного рейса", false) return false end
    if route.phase ~= "collect" then notify(ply, "Погрузка уже закончена", false) return false end

    local rec = I.NodeFor(ent)
    if not rec or rec.role ~= "depot" then notify(ply, "Грузить можно только на точке отправления", false) return false end

    -- Везём только то, что есть в заказе, и не больше нужного.
    local need = 0
    for _, orderID in ipairs(route.orders) do
        local order = I.Orders[orderID]
        if order and order.from == rec.id then
            for _, line in ipairs(order.lines or {}) do
                if line.itemID == itemID then need = need + (line.count or 0) end
            end
        end
    end
    if need <= 0 then notify(ply, "Этот груз в заказе не значится", false) return false end

    local have = C.Count(route.cargo, itemID)
    local room = math.max(0, need - have)
    if room <= 0 then notify(ply, "Этот груз уже загружен полностью", false) return false end

    local moved = C.MoveUpTo(rec.outID, route.cargo, itemID, math.min(count, room))
    if moved <= 0 then notify(ply, "Не удалось погрузить (нет груза или места)", false) return false end
    notify(ply, "Погружено: " .. I.NameOf(itemID) .. " ×" .. moved, true)
    I.SaveSoon()
    return true
end

function I.FinishLoading(ply)
    local key = I.RouteKey(ply)
    local route = I.Routes[key]
    if not route or route.phase ~= "collect" then notify(ply, "Сейчас нечего закрывать", false) return false end
    if C.IsEmpty(route.cargo) then notify(ply, "Пустым не поедете", false) return false end

    route.phase = "haul"
    route.lastPos = IsValid(ply) and ply:GetPos() or nil
    notify(ply, "Груз в машине. Везём на склад.", true)
    I.SaveSoon()
    return true
end

function I.DeliverOrder(ply, ent)
    local key = I.RouteKey(ply)
    local route = I.Routes[key]
    if not route then notify(ply, "Нет активного рейса", false) return false end
    if route.phase ~= "haul" then notify(ply, "Сначала завершите погрузку", false) return false end

    local rec = I.NodeFor(ent)
    if not rec or rec.role ~= "warehouse" then notify(ply, "Сдать груз можно только на складе", false) return false end

    local totalValue, onTime = 0, true
    for _, orderID in ipairs(route.orders) do
        local order = I.Orders[orderID]
        if order and order.to == rec.id then
            totalValue = totalValue + (tonumber(order.value) or 0)
            if os.time() > (tonumber(order.deadline) or 0) then onTime = false end
        end
    end

    --[[ МЕСТО ПРОВЕРЯЕМ ДО РАЗГРУЗКИ, а не посреди. Иначе часть груза
         уже окажется на складе, а награда не выплатится: водитель
         останется и без оплаты, и с претензией. ]]
    local cargoWeight = C.Weight(route.cargo)
    if C.Capacity(rec.outID) >= 0 and C.Free(rec.outID) < cargoWeight then
        notify(ply, "На складе не хватило места: нужно " .. tostring(cargoWeight) ..
            " кг, свободно " .. tostring(I.Round(C.Free(rec.outID), 1)) .. " кг", false)
        return false
    end

    local moved = {}
    for _, line in ipairs(C.List(route.cargo)) do
        local n = C.MoveUpTo(route.cargo, rec.outID, line.itemID, line.count)
        if n > 0 then moved[#moved + 1] = { itemID = line.itemID, count = n } end
    end
    if not C.IsEmpty(route.cargo) then
        notify(ply, "На складе не хватило места. Освободите склад.", false)
        return false
    end

    -- Награда считается от фактически довезённой ценности.
    local deliveredValue = I.OrderValueByLines(moved)
    local risk = riskAt(ply, IsValid(rec.ent) and rec.ent:GetPos() or nil)
    local reward = I.RewardFor(deliveredValue, route.distance or 0, risk, onTime)

    --[[ РЕШЕНИЕ ВЛАДЕЛЬЦА (31.08): «награду за выполненную работу
         оставить на руки». Платим лично водителю, а не в казну фракции:
         рейс — его заработок. Стенд sim_industry_logistics проверяет,
         что деньги уходят именно тому, кто вёз. ]]
    if GRM.GiveMoney then GRM.GiveMoney(ply, reward, "industry_route") end
    if GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("industry", "deliver", ply, nil,
            { value = deliveredValue, distance = math.floor(route.distance or 0), reward = reward, risk = risk, onTime = onTime })
    end

    for _, orderID in ipairs(route.orders) do
        local order = I.Orders[orderID]
        if order then order.state = "delivered" end
    end

    I.Routes[key] = nil
    C.Remove(route.cargo)

    notify(ply, "Груз сдан. Награда: " .. tostring(GRM.Format and GRM.Format(reward) or reward) ..
        (onTime and "" or " (срок нарушен)"), true)
    I.RefreshOrders(rec)
    I.SaveSoon()
    return true
end

function I.AbandonRoute(route, reason)
    if not route then return end
    -- Груз возвращаем на точку отправления, чтобы он не исчез.
    for _, orderID in ipairs(route.orders or {}) do
        local order = I.Orders[orderID]
        if order then
            if order.state == "taken" then
                order.state = "open"
                order.carrier = nil
            end
            -- Точки отправления могло не стать (узел удалили): тогда груз
            -- уходит на склад-получатель, а не пропадает.
            local back = I.Nodes[order.from]
            if not (back and back.outID) then back = I.Nodes[order.to] end
            if back and back.outID then
                for _, line in ipairs(C.List(route.cargo)) do
                    C.MoveUpTo(route.cargo, back.outID, line.itemID, line.count)
                end
            end
        end
    end
    if IsValid(route.driver) then notify(route.driver, tostring(reason or "Рейс отменён") .. ". Груз возвращён.", false) end
    I.Routes[route.key] = nil
    C.Remove(route.cargo)
    I.SaveSoon()
end

-- Стоимость фактически довезённых строк.
function I.OrderValueByLines(lines)
    local value = 0
    for _, line in ipairs(lines or {}) do
        value = value + I.PriceOf(line.itemID) * (tonumber(line.count) or 0)
    end
    return math.floor(value)
end

-- ================================================================
--  СОХРАНЕНИЕ ЗАКАЗОВ И РЕЙСОВ
-- ================================================================
--[[ Заказы хранятся отдельным файлом: узлы и задачи принадлежат цеху,
     заказы — логистике. Рейсы НЕ восстанавливаются: водителя после
     перезапуска на сервере нет, а полуживой рейс без водителя хуже
     честного возврата груза. Всё, что было в машине, уезжает обратно
     на точку отправления — владелец груза не теряет ничего. ]]
local ORDER_FILE = "grm_industry/orders_" .. tostring(game.GetMap() or "unknown") .. ".json"

function I.SaveOrders()
    if not (GRM.Persistence and GRM.Persistence.SaveJSON) then return false end
    local routes = {}
    for key, route in pairs(I.Routes) do
        routes[key] = {
            key = key, orders = route.orders, phase = route.phase,
            driverSID = route.driverSID or "",
            distance = math.floor(route.distance or 0), startedAt = route.startedAt,
            cargo = C.List(route.cargo),
        }
    end
    return GRM.Persistence.SaveJSON(ORDER_FILE, { version = 1, orders = I.Orders, routes = routes })
end

function I.LoadOrders()
    if not (GRM.Persistence and GRM.Persistence.LoadJSON) then return end
    local data = GRM.Persistence.LoadJSON(ORDER_FILE, { version = 1, orders = {}, routes = {} })
    if not istable(data) then return end

    I.Orders = {}
    for id, order in pairs(data.orders or {}) do
        if istable(order) and order.state ~= "delivered" and order.state ~= "expired" then
            I.Orders[id] = order
        end
    end

    --[[ РЕЙСЫ ВОССТАНАВЛИВАЮТСЯ, А НЕ ВЫБРАСЫВАЮТСЯ (пункт 10). Водителя
         на сервере ещё нет — он войдёт позже, поэтому ставим driver = nil
         и ждём входа: I.AttachRoute подцепит рейс по SteamID. Груз лежит
         в грузовом отсеке и никуда не девается.

         Раньше здесь всё возвращалось на точку отправления, а заказ снова
         открывался: рейс был привязан к персонажу, чей ключ после
         перезапуска не совпадал. ]]
    local restored = 0
    for key, route in pairs(data.routes or {}) do
        if istable(route) and istable(route.orders) and #route.orders > 0 then
            local alive = false
            for _, orderID in ipairs(route.orders) do
                if I.Orders[orderID] then alive = true break end
            end
            if alive then
                local cargoID = routeContainerID(key)
                C.Remove(cargoID)
                C.Ensure(cargoID, "store", key, ROUTE_CAPACITY)
                for _, line in ipairs(route.cargo or {}) do
                    C.Add(cargoID, line.itemID, math.floor(tonumber(line.count) or 0))
                end
                I.Routes[key] = {
                    key = key,
                    driver = nil,
                    driverSID = tostring(route.driverSID or ""),
                    cargo = cargoID,
                    orders = route.orders,
                    phase = (route.phase == "haul") and "haul" or "collect",
                    startPos = nil,
                    distance = tonumber(route.distance) or 0,
                    lastPos = nil,
                    startedAt = route.startedAt or os.time(),
                }
                -- Заказ остаётся за водителем: он его и довезёт.
                for _, orderID in ipairs(route.orders) do
                    local order = I.Orders[orderID]
                    if order then order.state = "taken" order.carrier = key end
                end
                restored = restored + 1
            end
        end
    end

    -- Рейс, у которого не нашлось ни одного заказа, всё равно держит груз:
    -- возвращаем его, чтобы он не висел мёртвым контейнером.
    for key, route in pairs(I.Routes) do
        local any = false
        for _, orderID in ipairs(route.orders) do if I.Orders[orderID] then any = true break end end
        if not any then I.AbandonRoute(route, "Заказ исчез") end
    end

    if restored > 0 then
        print("[GRM Industry] восстановлено рейсов после перезапуска: " .. restored ..
            " (водители подцепятся при входе)")
    end
end

-- ================================================================
--  ПРОБЕГ
-- ================================================================
local function tickRoutes()
    -- Сторож: без активных рейсов тик не перебирает ничего.
    if not next(I.Routes) then return end
    for key, route in pairs(I.Routes) do
        local ply = route.driver
        if not IsValid(ply) then
            -- Водитель вышел: рейс остаётся, но пробег не копим.
            route.lastPos = nil
        elseif route.phase == "haul" then
            local pos = ply:GetPos()
            if route.lastPos then
                local step = route.lastPos:Distance(pos)
                -- Телепорт и респавн не считаем пробегом.
                if step > 0 and step < 200 then route.distance = (route.distance or 0) + step end
            end
            route.lastPos = pos
        end
    end
end

timer.Create("GRM_Industry_Logistics", 2, 0, function()
    tickRoutes()
    expireOrders()
    -- Склады сами формируют спрос, но только если он вообще задан.
    for _, rec in pairs(I.Nodes) do
        if rec.role == "warehouse" and rec.demand and next(rec.demand) then
            I.RefreshOrders(rec)
        end
    end
end)

-- ================================================================
--  ОКНА РОЛЕЙ ЛОГИСТИКИ
-- ================================================================
local function openDepot(ply, ent, rec)
    local route = I.RouteFor(ply)
    local payload = {
        role = "depot",
        label = tostring(ent:GetNodeLabel() or ""),
        stock = C.List(rec.outID),
        weight = C.Weight(rec.outID),
        capacity = C.Capacity(rec.outID),
        route = nil,
    }
    if route then
        local needed = {}
        for _, orderID in ipairs(route.orders) do
            local order = I.Orders[orderID]
            if order then
                for _, line in ipairs(order.lines or {}) do
                    needed[line.itemID] = (needed[line.itemID] or 0) + (line.count or 0)
                end
            end
        end
        local lines = {}
        for itemID, need in pairs(needed) do
            lines[#lines + 1] = { itemID = itemID, name = I.NameOf(itemID), need = need, loaded = C.Count(route.cargo, itemID) }
        end
        table.sort(lines, function(a, b) return a.name < b.name end)
        payload.route = {
            phase = route.phase,
            cargo = C.List(route.cargo),
            cargoWeight = C.Weight(route.cargo),
            cargoCapacity = C.Capacity(route.cargo),
            lines = lines,
            destination = (I.Nodes[(I.Orders[route.orders[1]] or {}).to] or {}).id,
        }
    end
    net.Start(NET.open) net.WriteEntity(ent) net.WriteTable(payload) net.Send(ply)
end

local function openWarehouse(ply, ent, rec)
    local orders = {}
    for _, order in pairs(I.Orders) do
        if order.to == rec.id and (order.state == "open" or order.carrier == I.CharKey(ply)) then
            orders[#orders + 1] = {
                id = order.id, state = order.state,
                value = order.value, weight = order.weight, reward = order.reward,
                lines = order.lines,
                deadline = order.deadline,
                mine = order.carrier == I.CharKey(ply),
            }
        end
    end
    table.sort(orders, function(a, b) return (a.deadline or 0) < (b.deadline or 0) end)

    local payload = {
        role = "warehouse",
        label = tostring(ent:GetNodeLabel() or ""),
        faction = tostring(ent:GetFactionName() or ""),
        stock = C.List(rec.outID),
        weight = C.Weight(rec.outID),
        capacity = C.Capacity(rec.outID),
        demand = rec.demand or {},
        canManage = I.CanManage(ply),
        orders = orders,
        route = nil,
        itemNames = {},
    }
    for _, itemID in ipairs(I.KnownItemIDs()) do payload.itemNames[itemID] = I.NameOf(itemID) end

    local route = I.RouteFor(ply)
    if route then
        payload.route = { phase = route.phase, cargo = C.List(route.cargo), distance = math.floor(route.distance or 0) }
    end

    net.Start(NET.open) net.WriteEntity(ent) net.WriteTable(payload) net.Send(ply)
end

local function openArmory(ply, ent, rec)
    local payload = {
        role = "armory",
        label = tostring(ent:GetNodeLabel() or ""),
        faction = tostring(ent:GetFactionName() or ""),
        stock = C.List(rec.outID),
        weight = C.Weight(rec.outID),
        capacity = C.Capacity(rec.outID),
        carried = {},
    }
    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) and wep:GetClass() ~= "weapon_fists" then
            payload.carried[#payload.carried + 1] = { itemID = wep:GetClass(), name = wep:GetPrintName() or wep:GetClass() }
        end
    end
    net.Start(NET.open) net.WriteEntity(ent) net.WriteTable(payload) net.Send(ply)
end

I.NodeHandlers.depot = openDepot
I.NodeHandlers.warehouse = openWarehouse
I.NodeHandlers.armory = openArmory

-- Все предметы, которые производство и логистика умеют возить.
function I.KnownItemIDs()
    local ids = {}
    for id in pairs(I.Items) do ids[#ids + 1] = id end
    for id, recipe in pairs(I.Recipes) do
        if recipe.station == "weapon" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

-- ================================================================
--  ДЕЙСТВИЯ ЛОГИСТИКИ
-- ================================================================
local Actions = {}

Actions.order_take = function(ply, ent, rec)
    local orderID = net.ReadString()
    if I.TakeOrder(ply, orderID) then I.OpenNode(ply, ent) end
    return true
end

Actions.order_load = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    if I.LoadCargo(ply, ent, itemID, count) then I.OpenNode(ply, ent) end
    return true
end

Actions.order_go = function(ply, ent, rec)
    if I.FinishLoading(ply) then I.OpenNode(ply, ent) end
    return true
end

Actions.order_deliver = function(ply, ent, rec)
    if I.DeliverOrder(ply, ent) then I.OpenNode(ply, ent) end
    return true
end

Actions.route_abandon = function(ply, ent, rec)
    local route = I.RouteFor(ply)
    if route then I.AbandonRoute(route, "Рейс отменён") end
    I.OpenNode(ply, ent)
    return true
end

-- Спрос склада: какие позиции и в каких границах держать.
Actions.warehouse_demand = function(ply, ent, rec)
    if not I.CanManage(ply) then notify(ply, "Нет права наладки цеха", false) return false end
    local demand = net.ReadTable()
    local clean = {}
    if istable(demand) then
        for itemID, rule in pairs(demand) do
            if istable(rule) then
                local min = math.max(0, math.floor(tonumber(rule.min) or 0))
                local max = math.max(min, math.floor(tonumber(rule.max) or 0))
                if max > 0 then clean[tostring(itemID)] = { min = min, max = max } end
            end
        end
    end
    rec.demand = clean
    I.RefreshOrders(rec)
    notify(ply, "Спрос склада обновлён", true)
    I.OpenNode(ply, ent)
    return true
end

-- Шкаф фракции: положить оружие с рук.
--[[ ШКАФ ФРАКЦИИ (пункт 8). Проверяем фракцию и здесь, а не только при
     открытии окна: действие приходит по сети, и полагаться на то, что
     окно кто-то открывал, нельзя. ]]
local function armoryAllowed(ply, ent)
    local allowed, why = I.CanUseFactionNode(ply, ent)
    if not allowed then notify(ply, "Шкаф принадлежит другой фракции", false) end
    return allowed
end

Actions.armory_store = function(ply, ent, rec)
    if not armoryAllowed(ply, ent) then return false end
    local class = net.ReadString()
    local wep = ply:GetWeapon(class)
    if not IsValid(wep) then notify(ply, "У вас нет этого оружия", false) return false end
    local unit = I.WeightOf(class)
    if C.Capacity(rec.outID) >= 0 and C.Weight(rec.outID) + unit > C.Capacity(rec.outID) then
        notify(ply, "В шкафу нет места", false) return false
    end
    local ok = C.Add(rec.outID, class, 1)
    if not ok then notify(ply, "Не удалось положить", false) return false end
    ply:StripWeapon(class)
    notify(ply, "Оружие убрано в шкаф", true)
    I.OpenNode(ply, ent)
    return true
end

-- Шкаф фракции: взять оружие в руки.
Actions.armory_take = function(ply, ent, rec)
    if not armoryAllowed(ply, ent) then return false end
    local class = net.ReadString()
    if C.Count(rec.outID, class) < 1 then notify(ply, "В шкафу этого нет", false) return false end
    if ply:HasWeapon(class) then notify(ply, "Оно у вас уже есть", false) return false end
    C.Take(rec.outID, class, 1)
    ply:Give(class)
    notify(ply, "Оружие выдано", true)
    I.OpenNode(ply, ent)
    return true
end

--[[ Действия складываем в ОБЩИЙ реестр цеха, а не вешаем свой хук.
     Файлы autorun грузятся по алфавиту: этот файл приходит после
     sv_grm_industry.lua, и регистрация через hook.Add потребовала бы
     отдельного порядка загрузки. Общая таблица от порядка не зависит. ]]
I.Actions = I.Actions or {}
for name, fn in pairs(Actions) do I.Actions[name] = fn end

-- Заказы восстанавливаются после узлов: им нужны уже созданные склады.
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("industry.logistics", "late", function() I.LoadOrders() end)
end

print("[GRM Industry] логистика загружена")
