--[[--------------------------------------------------------------------
    GRM Food Kitchen v1.0.0 (Код 110, заказ владельца, находка 127)
    «GrandEats»: надстройка еды — ПЛИТА (готовка по рецептам),
    ХОЛОДИЛЬНИК (заморозка срока годности) и ГОРШОК (выращивание
    овощей из семян за деньги).

    Конфиг — sh_grm_food_config.lua (GRM.Food.Kitchen): модели
    печки/холодильника заказаны владельцем (furniturestove001a,
    furniturefridge001a), рецепты/культуры/сроки — там же, shared.

    Модели агрегатов и блюд — через util.IsValidModel с фолбэком
    (находка 85): сервер без CSS-контента получит кружку вместо
    экзотики, логика не ломается.

    Механика:
      ПЛИТА (grm_food_stove). [E] → окно: рецепты с живой проверкой
        ингредиентов по инвентарю. «Готовить» списывает продукты,
        блюдо готовится recipe.time секунд и ложится на выходной лоток
        (до ReadySlots штук). Забираешь готовое — оно попадает в
        инвентарь С ДАТОЙ срока годности (cooked=true портится за
        Kitchen.CookedSpoilSeconds в инвентаре и в мире).
      ХОЛОДИЛЬНИК (grm_food_fridge). FridgeSlots слотов; срок годности
        убранного складывается в слот и ЗАМОРАЖИВАЕТСЯ; при выдаче
        отсчёт продолжается с того же остатка.
      ГОРШОК (grm_food_planter). Пустой → посадил культуру за сумму
        (GRM.HasMoney/TakeMoney, как покупка в автомате) → ждёшь
        growSeconds → собрал crop.yield штук сырья. Полив раз в
        WaterCooldown сек срезает WaterBoost доли оставшегося времени.
      ПОРЧА. Свипер раз в Kitchen.SpoilSweepSeconds: приготовленное
        (cooked) в инвентаре любого игрока с просроченным data.spoilAt
        и мировые grm_food_item с полем GRMFoodSpoilAt — превращаются
        в «Испорченная еда» (grm_food_spoiled), съесть её нельзя.

    Персистентность — штатный GRM-путь: /permadd по агрегату допускает
    его класс (sh_grm_perm_entities v1.5.0) и складывает состояние
    (лоток плиты, содержимое холодильника, посадка горшка) в rec.data;
    после рестарта всё воскресает с учётом прошедшего времени.

    Окна (cl_grm_food_kitchen.lua) живут на одной паре net-строк:
    сервер→клиент «GRM_Kitchen_Open» (пэйлоад по виду агрегата),
    клиент→сервер «GRM_Kitchen_Op» (операция + аргументы). Каждая
    успешная операция — свежий пэйлоад (живое окно, урок Кода 108).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Food = GRM.Food or {}
GRM.FoodKitchen = GRM.FoodKitchen or {}
local FK = GRM.FoodKitchen

FK.Version = "1.0.0"  -- Код 110

-- net-строки протокола кухни
FK.NET_OPEN = "GRM_Kitchen_Open"
FK.NET_OP   = "GRM_Kitchen_Op"

-- какие энтити — «кухонные» (мультитул-окна и центральный диспетчер оп/)
FK.Classes = {
    grm_food_stove   = "stove",
    grm_food_fridge  = "fridge",
    grm_food_planter = "planter",
}

-- ============================================================
-- SHARED-ХЕЛПЕРЫ (конфиг, модели, константы)
-- ============================================================

function FK.Cfg() return GRM.Food.Kitchen or {} end
function FK.FoodData(itemID)
    local c = GRM.Food.Config
    return (c and c.FoodItems) and c.FoodItems[itemID] or nil
end
function FK.Recipe(rid) return (FK.Cfg().Recipes or {})[rid] end
function FK.Crop(cid) return (FK.Cfg().Crops or {})[cid] end
function FK.SpoilSeconds() return tonumber(FK.Cfg().CookedSpoilSeconds) or 2700 end
function FK.UseDist() return tonumber(FK.Cfg().UseDistance) or 150 end
FK.SPOILED_ID = "grm_food_spoiled"

-- модель с валидацией и фолбэком (находка 85)
function FK.SafeModel(m)
    m = tostring(m or "")
    local fb = tostring(FK.Cfg().ModelFallback or "models/props/cs_office/coffee_mug.mdl")
    if m == "" then return fb end
    if util.IsValidModel and not util.IsValidModel(m) then return fb end
    return m
end

-- можно ли этот id хранить/выдавать как «кухонную» позицию (еда из конфига, не мусор)
function FK.Storable(itemID)
    local d = FK.FoodData(itemID)
    return istable(d) and not d.spoiled
end

-- ============================================================
-- SERVER
-- ============================================================
if SERVER then
    util.AddNetworkString(FK.NET_OPEN)
    util.AddNetworkString(FK.NET_OP)

    function FK.Notify(ply, msg, r, g, b)
        if GRM.Notify then
            GRM.Notify(ply, msg, r or 255, g or 230, b or 140)
        elseif IsValid(ply) and ply.ChatPrint then
            ply:ChatPrint(tostring(msg))
        end
    end

    -- живое окно: пэйлоад по виду агрегата, свежий после каждой оп/
    function FK.OpenFor(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return end
        local kind = FK.Classes[ent:GetClass()]
        if not kind then return end
        if not (ent.BuildKitchenPayload) then return end
        local payload = ent:BuildKitchenPayload(ply)
        if not istable(payload) then return end
        payload.kind = kind
        payload.idx = ent:EntIndex()
        net.Start(FK.NET_OPEN)
            net.WriteTable(payload)
        net.Send(ply)
    end

    -- центральный диспетчер операций (валидация здесь, логика — у энтити)
    net.Receive(FK.NET_OP, function(_, ply)
        if not IsValid(ply) then return end
        ply.__grmKitchenNextOp = ply.__grmKitchenNextOp or 0
        local now = CurTime()
        if now < ply.__grmKitchenNextOp then return end
        ply.__grmKitchenNextOp = now + 0.2 -- анти-стукач (быстрый человек, н124)

        local idx = net.ReadUInt(16)
        local op = tostring(net.ReadString() or "")
        local data = net.ReadTable()
        if not istable(data) then data = {} end

        local ent = Entity(idx)
        if not IsValid(ent) then return end
        if not FK.Classes[ent:GetClass()] then return end
        local dist = FK.UseDist()
        if ply:GetPos():DistToSqr(ent:GetPos()) > dist * dist then
            FK.Notify(ply, "[Кухня] Подойдите ближе к агрегату.", 255, 180, 90)
            return
        end
        if not ent.kitchenOp then return end
        ent:kitchenOp(ply, op, data)
        if IsValid(ent) then FK.OpenFor(ply, ent) end -- живое обновление окна
    end)

    ----------------------------------------------------------------
    -- Выдача еды: в инвентарь (с датой годности у cooked) и в мир
    ----------------------------------------------------------------

    -- выдать n штук itemID игроку; cooked уходит с slot.data.spoilAt.
    -- Возврат: сколько НЕ влезло (0 = всё выдано).
    function FK.GiveFood(ply, itemID, n)
        if not (GRM.Inventory and GRM.Inventory.AddItem) then return tonumber(n) or 0 end
        n = math.max(1, math.floor(tonumber(n) or 1))
        local d = FK.FoodData(itemID)
        local data = nil
        if istable(d) and d.cooked then
            data = { spoilAt = os.time() + FK.SpoilSeconds() }
        end
        return GRM.Inventory.AddItem(ply, itemID, n, data) or 0
    end

    -- уронить n штук в мир grm_food_item-ами (модель с фолбэком; cooked
    -- получает мировой срок — при порче превратится в мусор на месте).
    -- remainSec: для cooked — какой остаток поставить (nil = полный срок)
    function FK.DropFood(itemID, n, pos, ang, remainSec)
        local d = FK.FoodData(itemID)
        if not istable(d) then return 0 end
        n = math.max(1, math.floor(tonumber(n) or 1))
        local dropped = 0
        for i = 1, n do
            local ent = ents.Create("grm_food_item")
            if IsValid(ent) then
                ent.GRMFoodItemID = itemID
                if ent.SetItemID then ent:SetItemID(itemID) end
                if ent.SetNWString then ent:SetNWString("ItemID", itemID) end
                if ent.SetModel then ent:SetModel(FK.SafeModel(d.model)) end
                ent:SetPos(pos + Vector(0, 0, 4 + i * 2))
                ent:SetAngles(ang or Angle(0, math.random(0, 360), 0))
                ent:Spawn()
                if ent.SetFoodItemID then ent:SetFoodItemID(itemID) end
                if istable(d) and d.cooked then
                    local rem = (remainSec ~= nil) and math.max(1, math.floor(tonumber(remainSec) or 1)) or FK.SpoilSeconds()
                    ent.GRMFoodSpoilAt = os.time() + rem
                end
                dropped = dropped + 1
            end
        end
        return dropped
    end

    -- деньги (семантика автомата: нет экономики — бесплатно)
    function FK.CanPay(ply, price)
        price = tonumber(price) or 0
        if price <= 0 then return true end
        if not GRM.HasMoney then return true end
        return GRM.HasMoney(ply, price) and true or false
    end
    function FK.Pay(ply, price, why)
        price = tonumber(price) or 0
        if price <= 0 then return end
        if GRM.TakeMoney then GRM.TakeMoney(ply, price) end
    end

    ----------------------------------------------------------------
    -- ПОРЧА: свипер инвентарей онлайн-игроков и предметов в мире
    ----------------------------------------------------------------
    local function spoilSweep()
        local sweep = tonumber(FK.Cfg().SpoilSweepSeconds) or 30
        local now = os.time()
        -- инвентари игроков: приготовленное с просроченным сроком → мусор
        if GRM.Inventory and GRM.Inventory.GetPlayerInv then
            for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(ply) then
                    local inv = GRM.Inventory.GetPlayerInv(ply)
                    local rotted = 0
                    if istable(inv) and istable(inv.slots) then
                        local maxSlots = (GRM.Inventory.Config and GRM.Inventory.Config.MaxSlots) or 24
                        for i = 1, maxSlots do
                            local s = inv.slots[i]
                            if istable(s) and isstring(s.id) and istable(s.data)
                                and tonumber(s.data.spoilAt) and now >= tonumber(s.data.spoilAt) then
                                local d = FK.FoodData(s.id)
                                if istable(d) and d.cooked then
                                    inv.slots[i] = { id = FK.SPOILED_ID, count = s.count or 1 }
                                    rotted = rotted + 1
                                    if GRM.Inventory.SyncSlot then GRM.Inventory.SyncSlot(ply, i) end
                                    if GRM.Inventory._devSaveSoon then GRM.Inventory._devSaveSoon("порча еды") end
                                end
                            end
                        end
                    end
                    if rotted > 0 then
                        FK.Notify(ply, "[Еда] Испортилось без холодильника: " .. rotted .. " позиц. — стала мусором.", 255, 170, 90)
                    end
                end
            end
        end
        -- мир: grm_food_item с просроченным мировым сроком → мусор на месте
        for _, ent in ipairs(ents.FindByClass("grm_food_item")) do
            if IsValid(ent) and tonumber(ent.GRMFoodSpoilAt) and now >= tonumber(ent.GRMFoodSpoilAt) then
                ent.GRMFoodSpoilAt = nil
                if ent.SetFoodItemID then
                    ent:SetFoodItemID(FK.SPOILED_ID)
                else
                    ent.GRMFoodItemID = FK.SPOILED_ID
                    if ent.SetItemID then ent:SetItemID(FK.SPOILED_ID) end
                end
            end
        end
    end
    timer.Create("GRM_Kitchen_SpoilSweep", tonumber(FK.Cfg().SpoilSweepSeconds) or 30, 0, spoilSweep)
    FK._devSpoilSweep = spoilSweep -- тест-экспорт (сим)

    ----------------------------------------------------------------
    -- ПЕРМ (sh_grm_perm_entities v1.5.0): состояние агрегатов едет
    -- в rec.data через делегаты энтити (KitchenPermData/KitchenPermApply).
    ----------------------------------------------------------------
    GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
    GRM.PermData.Extract = GRM.PermData.Extract or {}
    GRM.PermData.Apply = GRM.PermData.Apply or {}
    for class, kind in pairs(FK.Classes) do
        GRM.PermData.Extract[class] = function(ent)
            if ent.KitchenPermData then return ent:KitchenPermData() end
            return {}
        end
        GRM.PermData.Apply[class] = function(ent, t)
            if ent.KitchenPermApply and istable(t) then ent:KitchenPermApply(t) end
        end
    end

    print("[GRM Food Kitchen] v" .. FK.Version .. " (Код 110): плита/холодильник/горшок, порча, перм — готовы")
end
