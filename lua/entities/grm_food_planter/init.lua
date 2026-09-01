--[[--------------------------------------------------------------------
    grm_food_planter — init.lua (сервер горшка, Код 110)
    Семена покупаются прямо в окне горшка (GRM.HasMoney/TakeMoney —
    семантика торгового автомата: нет экономики — бесплатно). Стадии
    модели: пусто = кадка (terracotta01), растёт/готово = растение
    (cs_office plant01, рост масштабом 0.45→1.0). Собранный урожай
    идёт в инвентарь (сырые овощи срока не имеют), не влезло — на землю.
    Перм: культура + остаток роста + кулдаун полива.
----------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function FK() return GRM.FoodKitchen end
local function planterTimerName(idx) return "GRM_Kitchen_Planter_" .. tostring(idx) end

function ENT:SetPotLook()
    local cfg = self:KitchenCfg()
    self:SetModel(FK().SafeModel(cfg.PotModel or "models/props_junk/terracotta01.mdl"))
    self:SetModelScale(1, 0)
end

function ENT:SetPlantLook(progress)
    local cfg = self:KitchenCfg()
    local plant = cfg.PlantModel or "models/props/cs_office/plant01.mdl"
    if util.IsValidModel and util.IsValidModel(plant) then
        if self:GetModel() ~= plant then self:SetModel(plant) end
        self:SetModelScale(0.45 + 0.55 * math.Clamp(tonumber(progress) or 0, 0, 1), 0)
    end
end

function ENT:Initialize()
    self:SetPotLook()
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self.FinishAt = tonumber(self.FinishAt) or 0
    self.WaterAt = tonumber(self.WaterAt) or 0
    self.PlantedCrop = isstring(self.PlantedCrop) and self.PlantedCrop or tostring(self:GetPlanterCrop() or "")
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if FK() and FK().OpenFor then FK().OpenFor(ply, self) end
end

-- растущий таймер: масштаб по прогрессу + переход в «готово»
function ENT:ArmPlanterTimer()
    local idx = self:EntIndex()
    timer.Create(planterTimerName(idx), 1, 0, function()
        if not IsValid(self) then
            timer.Remove(planterTimerName(idx))
            return
        end
        if self:GetPlanterState() ~= 1 then return end
        local now = os.time()
        local fin = tonumber(self.FinishAt) or 0
        local crop = FK().Crop(self.PlantedCrop or "")
        local total = (crop and tonumber(crop.growSeconds)) or 60
        local left = math.max(0, fin - now)
        self:SetPlantLook(1 - left / total)
        if left <= 0 then
            self:SetPlanterState(2)
            self:SetPlantLook(1)
            self:EmitSound("buttons/button9.wav", 70, 120)
        end
    end)
end

function ENT:BuildKitchenPayload(ply)
    local crops = {}
    for cid, c in pairs(FK().Cfg().Crops or {}) do
        crops[#crops + 1] = {
            id = cid, name = tostring(c.name or cid), cost = tonumber(c.cost) or 0,
            time = tonumber(c.growSeconds) or 60, yield = tonumber(c.yield) or 1,
        }
    end
    table.sort(crops, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local cur = FK().Crop(self.PlantedCrop or "")
    return {
        state = self:GetPlanterState(),
        crop = tostring(self.PlantedCrop or ""),
        cropName = cur and tostring(cur.name) or "",
        finish = tonumber(self.FinishAt) or 0,
        waterAt = tonumber(self.WaterAt) or 0,
        yield = cur and tonumber(cur.yield) or 0,
        now = os.time(),
        boost = tonumber(FK().Cfg().WaterBoost) or 0.25,
        crops = crops,
    }
end

function ENT:kitchenOp(ply, op, data)
    data = istable(data) and data or {}
    local now = os.time()

    if op == "planter_plant" then
        if self:GetPlanterState() ~= 0 then
            FK().Notify(ply, "[Горшок] Здесь уже что-то растёт — сначала соберите урожай.", 255, 190, 90)
            return
        end
        local cid = tostring(data.crop or "")
        local c = FK().Crop(cid)
        if not istable(c) then return end
        local cost = tonumber(c.cost) or 0
        if cost > 0 and not FK().CanPay(ply, cost) then
            local price = (GRM.Format and GRM.Format(cost)) or tostring(cost)
            FK().Notify(ply, "[Горшок] Семена «" .. tostring(c.name) .. "» стоят " .. price .. " — недостаточно денег.", 255, 170, 90)
            return
        end
        FK().Pay(ply, cost, "семена «" .. tostring(c.name) .. "»")
        self.PlantedCrop = cid
        self:SetPlanterCrop(cid)
        self.FinishAt = now + (tonumber(c.growSeconds) or 60)
        self:SetPlanterFinish(self.FinishAt)
        self.WaterAt = 0
        self:SetPlanterWater(0)
        self:SetPlanterState(1)
        self:SetPlantLook(0)
        self:ArmPlanterTimer()
        self:EmitSound("ambient/materials/dirt_impact1.wav", 70, 100)
        FK().Notify(ply, "[Горшок] Посажено: " .. tostring(c.name) .. ". Готово через " .. tostring(tonumber(c.growSeconds) or 60) .. " сек. Полив ускоряет рост!", 120, 220, 140)
        return
    end

    if op == "planter_water" then
        if self:GetPlanterState() ~= 1 then
            FK().Notify(ply, "[Горшок] Поливать сейчас нечего.", 255, 190, 90)
            return
        end
        if now < (tonumber(self.WaterAt) or 0) then
            FK().Notify(ply, "[Горшок] Поливать можно раз в " .. tostring(tonumber(FK().Cfg().WaterCooldown) or 60) .. " сек — подождите ещё " .. tostring(math.ceil((tonumber(self.WaterAt) or 0) - now)) .. " сек.", 255, 190, 90)
            return
        end
        local cd = tonumber(FK().Cfg().WaterCooldown) or 60
        local boost = tonumber(FK().Cfg().WaterBoost) or 0.25
        self.WaterAt = now + cd
        self:SetPlanterWater(self.WaterAt)
        local left = math.max(0, (tonumber(self.FinishAt) or 0) - now)
        self.FinishAt = now + math.floor(left * (1 - boost) + 0.5)
        self:SetPlanterFinish(self.FinishAt)
        self:EmitSound("ambient/water/water_splash1.wav", 70, 110)
        FK().Notify(ply, "[Горшок] Полито: рост ускорен (−" .. tostring(math.floor(boost * 100)) .. "% к оставшемуся времени).", 120, 220, 140)
        return
    end

    if op == "planter_harvest" then
        if self:GetPlanterState() == 1 and now >= (tonumber(self.FinishAt) or 0) then
            self:SetPlanterState(2) -- ленивая догонка, даже если тик ещё не прошёл
        end
        if self:GetPlanterState() ~= 2 then
            FK().Notify(ply, "[Горшок] Урожай ещё не созрел — осталось " .. tostring(math.max(0, (tonumber(self.FinishAt) or 0) - now)) .. " сек.", 255, 190, 90)
            return
        end
        local c = FK().Crop(self.PlantedCrop or "")
        if not istable(c) then return end
        local yield = math.max(1, tonumber(c.yield) or 1)
        local left = (GRM.Inventory and GRM.Inventory.AddItem) and GRM.Inventory.AddItem(ply, tostring(c.item), yield) or yield
        local given = yield - (left or 0)
        if (left or 0) > 0 then
            FK().DropFood(tostring(c.item), left, self:GetPos() + self:GetForward() * 30 + Vector(0, 0, 20))
        end
        local msg = "[Горшок] Урожай собран: " .. tostring(c.name) .. " ×" .. tostring(given) .. "."
        if (left or 0) > 0 then msg = msg .. " Не влезло " .. tostring(left) .. " — уложено рядом." end
        FK().Notify(ply, msg, 120, 220, 140)
        -- горшок пуст, ждёт новой посадки
        self.PlantedCrop = ""
        self:SetPlanterCrop("")
        self.FinishAt = 0
        self:SetPlanterState(0)
        self:SetPotLook()
        timer.Remove(planterTimerName(self:EntIndex()))
        self:EmitSound("buttons/button14.wav", 70, 100)
        return
    end
end

-- ============================================================
-- ПЕРМ (Код 110): культура + остаток роста + кулдаун полива
-- ============================================================
function ENT:KitchenPermData()
    local rec = { crop = tostring(self.PlantedCrop or "") }
    if self:GetPlanterState() ~= 0 and rec.crop ~= "" then
        rec.remain = math.max(0, (tonumber(self.FinishAt) or 0) - os.time())
        rec.water = math.max(0, (tonumber(self.WaterAt) or 0) - os.time())
    end
    return rec
end

function ENT:KitchenPermApply(t)
    local cid = tostring(t.crop or "")
    local c = FK().Crop(cid)
    if not istable(c) or cid == "" then return end
    self.PlantedCrop = cid
    self:SetPlanterCrop(cid)
    local now = os.time()
    local remain = math.max(0, tonumber(t.remain) or 0)
    self.FinishAt = now + remain
    self.WaterAt = now + math.max(0, tonumber(t.water) or 0)
    self:SetPlanterFinish(self.FinishAt)
    self:SetPlanterWater(self.WaterAt)
    if remain <= 0 then
        self:SetPlanterState(2)
        self:SetPlantLook(1)
    else
        self:SetPlanterState(1)
        local total = tonumber(c.growSeconds) or 60
        self:SetPlantLook(1 - remain / total)
        self:ArmPlanterTimer()
    end
end
