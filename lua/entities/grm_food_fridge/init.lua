--[[--------------------------------------------------------------------
    grm_food_fridge — init.lua (сервер холодильника, Код 110)
    Слоты: { id, n, remain } — remain = остаток срока годности в СЕКУНДАХ
    (0 = «не портится»: упаковка из автомата, сырые овощи). Заморожен:
    при выдаче обратно в инвентарь cooked получает spoilAt = now+remain.
    Стакается одинаковый id с близким остатком (±3 сек) до maxStack.
    Перм хранит слоты как есть — время внутри заморожено, рестарт всё
    равно не двигает остаток.
----------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function FK() return GRM.FoodKitchen end

function ENT:Initialize()
    local cfg = self:KitchenCfg()
    self:SetModel(FK().SafeModel(cfg.FridgeModel or "models/props_c17/furniturefridge001a.mdl"))
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self.FoodSlots = istable(self.FoodSlots) and self.FoodSlots or {}
    self:SyncFridgeNW()
end

function ENT:SyncFridgeNW()
    self:SetFridgeCount(#(self.FoodSlots or {}))
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if FK() and FK().OpenFor then FK().OpenFor(ply, self) end
end

local function fridgeCap(self) return tonumber(self:KitchenCfg().FridgeSlots) or 12 end

local function slotMax(itemID)
    if GRM.Inventory and GRM.Inventory.GetMaxStack then
        return math.max(1, tonumber(GRM.Inventory.GetMaxStack(itemID)) or 10)
    end
    return 10
end

-- вложить пачку (id, n, remain); возврат — сколько НЕ влезло
function ENT:FridgePut(itemID, n, remain)
    n = math.max(0, math.floor(tonumber(n) or 0))
    remain = math.max(0, math.floor(tonumber(remain) or 0))
    self.FoodSlots = istable(self.FoodSlots) and self.FoodSlots or {}
    -- сначала долить в существующие (тот же id и почти тот же остаток)
    for _, s in ipairs(self.FoodSlots) do
        if n <= 0 then break end
        if s.id == itemID and math.abs((tonumber(s.remain) or 0) - remain) <= 3 then
            local room = slotMax(itemID) - (tonumber(s.n) or 0)
            if room > 0 then
                local add = math.min(room, n)
                s.n = s.n + add
                n = n - add
            end
        end
    end
    -- затем новые слоты
    while n > 0 and #(self.FoodSlots) < fridgeCap(self) do
        local add = math.min(slotMax(itemID), n)
        self.FoodSlots[#self.FoodSlots + 1] = { id = itemID, n = add, remain = remain }
        n = n - add
    end
    self:SyncFridgeNW()
    return n
end

-- содержимое окна холодильника + что игрок может положить из инвентаря
function ENT:BuildKitchenPayload(ply)
    local slots = {}
    for i, s in ipairs(self.FoodSlots or {}) do
        local d = FK().FoodData(s.id)
        slots[#slots + 1] = {
            slot = i, id = s.id, name = (d and d.name) or s.id, n = tonumber(s.n) or 0,
            remain = tonumber(s.remain) or 0, cooked = (d and d.cooked) == true,
            -- Иконка нужна сетке слотов: без неё ячейка была бы пустой.
            icon = (d and d.icon) or "icon16/box.png",
        }
    end
    local storeable = {}
    if GRM.Inventory and GRM.Inventory.GetPlayerInv and IsValid(ply) then
        local inv = GRM.Inventory.GetPlayerInv(ply)
        local counts = {}
        if istable(inv) and istable(inv.slots) then
            for _, s in pairs(inv.slots) do
                if istable(s) and isstring(s.id) and FK().Storable(s.id) then
                    counts[s.id] = (counts[s.id] or 0) + (tonumber(s.count) or 1)
                end
            end
        end
        local dsort = {}
        for id, cnt in pairs(counts) do dsort[#dsort + 1] = { id = id, cnt = cnt } end
        table.sort(dsort, function(a, b)
            local da, db = FK().FoodData(a.id), FK().FoodData(b.id)
            return tostring((da and da.name) or a.id) < tostring((db and db.name) or b.id)
        end)
        for _, row in ipairs(dsort) do
            local d = FK().FoodData(row.id)
            storeable[#storeable + 1] = { id = row.id, name = (d and d.name) or row.id,
                n = row.cnt, cooked = (d and d.cooked) == true,
                icon = (d and d.icon) or "icon16/box.png" }
        end
    end
    return {
        slots = slots, cap = fridgeCap(self), store = storeable,
        spoilSec = FK().SpoilSeconds(), now = os.time(),
    }
end

-- изъять из инвентаря n штук id; для cooked собирает остатки срока
-- по слотам (ts целого слота действует на весь его стак — документ).
-- Возврат: { {n=сколько, remain=срок}, ... } и сколько фактически взято.
local function takeFromInventory(ply, itemID, n)
    local out, taken = {}, 0
    if not (GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.RemoveFromSlot) then
        return out, 0
    end
    local inv = GRM.Inventory.GetPlayerInv(ply)
    if not (istable(inv) and istable(inv.slots)) then return out, 0 end
    local d = FK().FoodData(itemID)
    local isCooked = istable(d) and d.cooked
    local now = os.time()
    local maxSlots = (GRM.Inventory.Config and GRM.Inventory.Config.MaxSlots) or 24
    for i = 1, maxSlots do
        if taken >= n then break end
        local s = inv.slots[i]
        if istable(s) and s.id == itemID then
            local want = math.min(tonumber(s.count) or 1, n - taken)
            local remain = 0
            if isCooked then
                local ts = (istable(s.data) and tonumber(s.data.spoilAt)) or 0
                remain = ts > 0 and math.max(0, ts - now) or FK().SpoilSeconds()
            end
            if GRM.Inventory.RemoveFromSlot(ply, i, want) then
                out[#out + 1] = { n = want, remain = remain }
                taken = taken + want
            end
        end
    end
    return out, taken
end

function ENT:kitchenOp(ply, op, data)
    data = istable(data) and data or {}
    if op == "fridge_store" then
        local itemID = tostring(data.id or "")
        if not FK().Storable(itemID) then
            FK().Notify(ply, "[Холодильник] Это хранить нельзя (мусор не кладём).", 255, 170, 90)
            return
        end
        local want = math.max(1, math.floor(tonumber(data.n) or 1))
        local batches, taken = takeFromInventory(ply, itemID, want)
        if taken <= 0 then
            FK().Notify(ply, "[Холодильник] В инвентаре нет такого продукта.", 255, 170, 90)
            return
        end
        local put = 0
        for _, b in ipairs(batches) do
            local left = self:FridgePut(itemID, b.n, b.remain)
            if left > 0 then
                -- не влезло — честно возвращаем игроку с тем же остатком
                local d = FK().FoodData(itemID)
                local dataAdd = nil
                if istable(d) and d.cooked then dataAdd = { spoilAt = os.time() + b.remain } end
                local back = (GRM.Inventory and GRM.Inventory.AddItem) and GRM.Inventory.AddItem(ply, itemID, left, dataAdd) or left
                if (back or 0) > 0 then
                    FK().DropFood(itemID, back, self:GetPos() + self:GetForward() * 38 + Vector(0, 0, 8), nil, b.remain)
                end
            else
                put = put + b.n
            end
        end
        self:SyncFridgeNW()
        if put > 0 then
            FK().Notify(ply, "[Холодильник] Убрано: " .. tostring(put) .. " × " .. ((FK().FoodData(itemID) or {}).name or itemID), 120, 220, 140)
        end
        return
    end

    if op == "fridge_take" then
        local slotIdx = math.floor(tonumber(data.slot) or 0)
        local s = istable(self.FoodSlots) and self.FoodSlots[slotIdx] or nil
        if not istable(s) then return end
        local want = math.max(1, math.floor(tonumber(data.n) or 1))
        want = math.min(want, tonumber(s.n) or 0)
        local d = FK().FoodData(s.id)
        local dataAdd = nil
        if istable(d) and d.cooked then dataAdd = { spoilAt = os.time() + (tonumber(s.remain) or 0) } end
        local left = (GRM.Inventory and GRM.Inventory.AddItem) and GRM.Inventory.AddItem(ply, s.id, want, dataAdd) or want
        local given = want - (left or 0)
        if (left or 0) > 0 then
            FK().DropFood(s.id, left, self:GetPos() + self:GetForward() * 38 + Vector(0, 0, 8), nil, tonumber(s.remain) or 0)
        end
        s.n = (tonumber(s.n) or 0) - want
        if s.n <= 0 then table.remove(self.FoodSlots, slotIdx) end
        self:SyncFridgeNW()
        FK().Notify(ply, "[Холодильник] Взято: " .. tostring(given) .. " × " .. ((d and d.name) or s.id), 120, 220, 140)
        return
    end
end

-- ============================================================
-- ПЕРМ (Код 110): слоты с замороженным остатком — как есть
-- ============================================================
function ENT:KitchenPermData()
    local out = { slots = {} }
    for _, s in ipairs(self.FoodSlots or {}) do
        out.slots[#out.slots + 1] = { id = tostring(s.id), n = tonumber(s.n) or 0, remain = tonumber(s.remain) or 0 }
    end
    return out
end

function ENT:KitchenPermApply(t)
    self.FoodSlots = {}
    for _, s in ipairs(istable(t.slots) and t.slots or {}) do
        if FK().Storable(s.id) then
            self.FoodSlots[#self.FoodSlots + 1] = {
                id = tostring(s.id),
                n = math.max(1, math.floor(tonumber(s.n) or 1)),
                remain = math.max(0, math.floor(tonumber(s.remain) or 0)),
            }
        end
    end
    self:SyncFridgeNW()
end
