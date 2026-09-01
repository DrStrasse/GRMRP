--[[--------------------------------------------------------------------
    grm_food_stove — init.lua (сервер плиты, Код 110)
    Логика: рецепт списывает ингредиенты из инвентаря → ждём time сек
    → блюдо (cooked, срок годности!) ложится на лоток (до ReadySlots)
    → «Забрать» выдаёт в инвентарь (не влезло — на пол перед плитой).
    «Отмена» возвращает ингредиенты. Перм хранит лоток и недожатую
    готовку с учётом прошедшего времени.
----------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function FK() return GRM.FoodKitchen end

--[[ ЗВУК ГОТОВКИ (заказ владельца 28.08).

     «При начале варки проигрывается звук gascan_ignite1, затем следом
      идёт fire_big_loop1.»

     Розжиг — разовый EmitSound. А вот гудение огня ЗАЦИКЛЕНО, и его
     обязательно нужно уметь выключить: EmitSound для петли не годится,
     она бы играла вечно, даже после снятия кастрюли или удаления плиты.
     Поэтому держим CreateSound на entity и глушим во всех местах, где
     готовка заканчивается: готово, отмена, рестарт, удаление плиты. ]]
local STOVE_IGNITE = "ambient/fire/gascan_ignite1.wav"
local STOVE_LOOP   = "ambient/fire/fire_big_loop1.wav"

function ENT:StartCookSound(ignite)
    -- Розжиг только при живом старте, а не при восстановлении после рестарта.
    if ignite then self:EmitSound(STOVE_IGNITE, 65, 100) end

    if self.CookLoop then self.CookLoop:Stop() self.CookLoop = nil end
    --[[ CreateSound есть не всегда (стенды, урезанные окружения), а без
         звука плита обязана продолжать готовить. Поэтому проверяем, а не
         падаем: готовка важнее озвучки. ]]
    if not isfunction(CreateSound) then return end
    self.CookLoop = CreateSound(self, STOVE_LOOP)
    if self.CookLoop then
        --[[ Задержка ровно на длину розжига: сначала «пшик» газа, потом
             ровное гудение. Одновременно они звучали бы кашей. ]]
        local delay = ignite and 0.6 or 0
        timer.Simple(delay, function()
            if not IsValid(self) then return end
            -- За эти полсекунды готовку могли отменить.
            if self:GetStoveState() ~= 1 then return end
            if not self.CookLoop then return end
            self.CookLoop:SetSoundLevel(62)
            self.CookLoop:PlayEx(0.55, 100)
        end)
    end
end

function ENT:StopCookSound()
    if not self.CookLoop then return end
    self.CookLoop:Stop()
    self.CookLoop = nil
end

function ENT:Initialize()
    local cfg = self:KitchenCfg()
    self:SetModel(FK().SafeModel(cfg.StoveModel or "models/props_c17/furniturestove001a.mdl"))
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self.ReadyDishes = istable(self.ReadyDishes) and self.ReadyDishes or {}
    self.FinishAt = tonumber(self.FinishAt) or 0
    self:SetStoveState(self:GetStoveState() or 0)
    self:SyncReadyNW()
end

function ENT:SyncReadyNW()
    self:SetStoveReady(#(self.ReadyDishes or {}))
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if FK() and FK().OpenFor then FK().OpenFor(ply, self) end
end

-- таймер плиты тикает, только пока есть готовка
local function stoveTimerName(idx) return "GRM_Kitchen_Stove_" .. tostring(idx) end

function ENT:ArmStoveTimer()
    local idx = self:EntIndex()
    timer.Create(stoveTimerName(idx), 1, 0, function()
        if not IsValid(self) then
            timer.Remove(stoveTimerName(idx))
            return
        end
        if self:GetStoveState() ~= 1 then return end
        if os.time() < (tonumber(self.FinishAt) or 0) then return end
        -- готовка завершена: выкладываем блюдо на лоток; нет места — ждём
        local cap = tonumber(self:KitchenCfg().ReadySlots) or 4
        if #(self.ReadyDishes or {}) >= cap then return end
        local rec = FK().Recipe(self:GetStoveRecipe())
        if not istable(rec) then
            self:SetStoveState(0)
            self:StopCookSound()
            self:SyncReadyNW()
            return
        end
        self.ReadyDishes = self.ReadyDishes or {}
        for i = 1, math.max(1, tonumber(rec.n) or 1) do
            if #(self.ReadyDishes) < cap then
                self.ReadyDishes[#self.ReadyDishes + 1] = tostring(rec.out)
            end
        end
        self:SetStoveState(0)
        self:SetStoveRecipe("")
        self:SyncReadyNW()
        self:StopCookSound()
        self:EmitSound("buttons/bell1.wav", 70, 100)
    end)
end

local function countReadyCap(self) return tonumber(self:KitchenCfg().ReadySlots) or 4 end

-- окно плиты: рецепты с разбором «чего не хватает», прогресс, лоток
function ENT:BuildKitchenPayload(ply)
    local have = {}
    if GRM.Inventory and GRM.Inventory.CountItem and IsValid(ply) then
        for rid, rec in pairs(FK().Cfg().Recipes or {}) do
            for itemID, need in pairs(rec.raw or {}) do
                if have[itemID] == nil then
                    have[itemID] = GRM.Inventory.CountItem(ply, itemID) or 0
                end
            end
        end
    end
    local recipes = {}
    for rid, rec in pairs(FK().Cfg().Recipes or {}) do
        local needList, can = {}, true
        for itemID, need in pairs(rec.raw or {}) do
            local h = have[itemID] or 0
            if h < (tonumber(need) or 1) then can = false end
            local d = FK().FoodData(itemID)
            needList[#needList + 1] = { id = itemID, name = (d and d.name) or itemID, n = tonumber(need) or 1, have = h }
        end
        local od = FK().FoodData(rec.out)
        recipes[#recipes + 1] = {
            id = rid, name = tostring(rec.name or rid), time = tonumber(rec.time) or 30,
            outName = (od and od.name) or tostring(rec.out), can = can, need = needList,
        }
    end
    table.sort(recipes, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local readyList = {}
    for _, itemID in ipairs(self.ReadyDishes or {}) do
        local d = FK().FoodData(itemID)
        readyList[#readyList + 1] = { id = itemID, name = (d and d.name) or itemID }
    end
    return {
        state = self:GetStoveState(),
        recipe = self:GetStoveRecipe(),
        finish = tonumber(self.FinishAt) or 0,
        now = os.time(),
        ready = readyList,
        readyCap = countReadyCap(self),
        recipes = recipes,
    }
end

-- операции окна (диспетчер модуля уже проверил дистанцию)
function ENT:kitchenOp(ply, op, data)
    data = istable(data) and data or {}
    if op == "stove_cook" then
        if self:GetStoveState() ~= 0 then
            FK().Notify(ply, "[Плита] Она занята готовкой — дождитесь или отмените.", 255, 190, 90)
            return
        end
        local rid = tostring(data.recipe or "")
        local rec = FK().Recipe(rid)
        if not istable(rec) then return end
        if not (GRM.Inventory and GRM.Inventory.CountItem and GRM.Inventory.RemoveItem) then
            FK().Notify(ply, "[Плита] Инвентарь не загружен — готовить не из чего.", 255, 140, 110)
            return
        end
        for itemID, need in pairs(rec.raw or {}) do
            if (GRM.Inventory.CountItem(ply, itemID) or 0) < (tonumber(need) or 1) then
                local d = FK().FoodData(itemID)
                FK().Notify(ply, "[Плита] Не хватает: " .. tostring((d and d.name) or itemID) .. " ×" .. tostring(tonumber(need) or 1), 255, 170, 90)
                return
            end
        end
        for itemID, need in pairs(rec.raw or {}) do
            GRM.Inventory.RemoveItem(ply, itemID, tonumber(need) or 1)
        end
        self:SetStoveRecipe(rid)
        self:SetStoveState(1)
        -- Начало и конец пишем парой: по ним считается доля прогресса.
        self:SetStoveStart(os.time())
        self.FinishAt = os.time() + (tonumber(rec.time) or 30)
        self:SetStoveFinish(self.FinishAt)
        self:ArmStoveTimer()
        self:StartCookSound(true)
        FK().Notify(ply, "[Плита] Готовим: " .. tostring(rec.name or rid) .. " (" .. tostring(tonumber(rec.time) or 30) .. " сек)", 120, 220, 140)
        return
    end

    if op == "stove_cancel" then
        if self:GetStoveState() ~= 1 then
            FK().Notify(ply, "[Плита] Сейчас ничего не готовится.", 255, 190, 90)
            return
        end
        local rec = FK().Recipe(self:GetStoveRecipe())
        if istable(rec) and GRM.Inventory and GRM.Inventory.AddItem then
            for itemID, need in pairs(rec.raw or {}) do
                local left = GRM.Inventory.AddItem(ply, itemID, tonumber(need) or 1) or 0
                if left > 0 then
                    FK().DropFood(itemID, left, self:GetPos() + self:GetForward() * 42, self:GetAngles())
                end
            end
        end
        self:SetStoveState(0)
        self:SetStoveRecipe("")
        self:StopCookSound()
        self:EmitSound("buttons/button18.wav", 65, 100)
        FK().Notify(ply, "[Плита] Готовка отменена, ингредиенты возвращены.", 235, 190, 90)
        return
    end

    if op == "stove_collect" then
        local n = #(self.ReadyDishes or {})
        if n <= 0 then
            FK().Notify(ply, "[Плита] Лоток пуст — готовых блюд нет.", 255, 190, 90)
            return
        end
        local given, dropped = 0, 0
        for _, itemID in ipairs(self.ReadyDishes) do
            local left = FK().GiveFood(ply, itemID, 1)
            if (left or 0) > 0 then
                dropped = dropped + FK().DropFood(itemID, 1, self:GetPos() + self:GetForward() * 42 + Vector(0, 0, 6))
            else
                given = given + 1
            end
        end
        self.ReadyDishes = {}
        self:SyncReadyNW()
        local msg = "[Плита] Забрано блюд: " .. tostring(given) .. "."
        if dropped > 0 then msg = msg .. " Не влезло в инвентарь: " .. tostring(dropped) .. " (лежат у плиты)." end
        FK().Notify(ply, msg, 120, 220, 140)
        return
    end
end

-- ============================================================
-- ПЕРМ (Код 110): лоток + недожатая готовка переживают рестарт
-- ============================================================
function ENT:KitchenPermData()
    local rec = {
        ready = table.Copy(self.ReadyDishes or {}),
    }
    if self:GetStoveState() == 1 and tostring(self:GetStoveRecipe() or "") ~= "" then
        rec.recipe = tostring(self:GetStoveRecipe())
        rec.remain = math.max(0, (tonumber(self.FinishAt) or 0) - os.time())
    end
    return rec
end

function ENT:KitchenPermApply(t)
    if istable(t.ready) then
        self.ReadyDishes = {}
        local cap = countReadyCap(self)
        for _, itemID in ipairs(t.ready) do
            if #self.ReadyDishes < cap and FK().FoodData(itemID) then
                self.ReadyDishes[#self.ReadyDishes + 1] = tostring(itemID)
            end
        end
    end
    if isstring(t.recipe) and FK().Recipe(t.recipe) then
        self:SetStoveRecipe(t.recipe)
        self:SetStoveState(1)
        local remain = math.max(1, tonumber(t.remain) or 1)
        self.FinishAt = os.time() + remain
        self:SetStoveFinish(self.FinishAt)
        --[[ После рестарта началом считаем «сейчас минус уже пройденное».
             Полную длительность берём из рецепта: иначе бар прыгнул бы
             на ноль и блюдо, которому осталось 5 секунд, показывало бы
             «только начали». ]]
        local recDef = FK().Recipe(t.recipe)
        local total = (istable(recDef) and tonumber(recDef.time)) or remain
        self:SetStoveStart(os.time() - math.max(0, total - remain))
        -- Готовка продолжается с прошлой сессии: розжига не было.
        self:StartCookSound(false)
        self:ArmStoveTimer()
    end
    self:SyncReadyNW()
end

--[[ Плиту убрали или карта сменилась — зацикленный звук обязан умереть
     вместе с ней, иначе гудение останется висеть в мире. ]]
function ENT:OnRemove()
    self:StopCookSound()
    timer.Remove("GRM_Kitchen_Stove_" .. tostring(self:EntIndex()))
end
