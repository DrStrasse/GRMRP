AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local model = "models/props_junk/cardboard_box004a.mdl"
    local id = self:GetItemID()
    if isstring(id) and string.StartWith(id, "weapon:") then
        model = "models/weapons/w_pistol.mdl"
        local class = self.ItemData and self.ItemData.class
        if isstring(class) and weapons.GetStored and weapons.GetStored(class) then
            local wep = weapons.GetStored(class)
            if wep and isstring(wep.WorldModel) and wep.WorldModel ~= "" then
                model = wep.WorldModel
            end
        end
    elseif GRM and GRM.Inventory and GRM.Inventory.GetItemDef then
        local def = GRM.Inventory.GetItemDef(id)
        if def and isstring(def.model) and def.model ~= "" then
            model = def.model
        end
    end
    self:SetModel(model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    if self:GetItemCount() <= 0 then self:SetItemCount(1) end
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
    -- авто-удаление через 10 мин
    timer.Simple(600, function()
        if IsValid(self) then self:Remove() end
    end)
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not GRM or not GRM.Inventory then return end
    local id = self:GetItemID()
    local count = math.max(1, self:GetItemCount())
    local data = self.ItemData

    if isstring(id) and string.StartWith(id, "weapon:") then
        local class = (data and data.class) or string.sub(id, 8)
        if ply:HasWeapon(class) then
            if GRM.Notify then GRM.Notify(ply, "У вас уже есть это оружие", 255, 180, 60) end
            return
        end
        local wep = ply:Give(class, false)
        if IsValid(wep) then
            -- Оружие подбирается с дефолтными патронами от ply:Give
            -- clip1/clip2 больше не сохраняются (баг: ply:Give уже добавляет патроны в резерв,
            -- и установка clip1 из data создавала дублирование — патроны удваивались)
        end
        if GRM.Notify then GRM.Notify(ply, "Подобрано оружие", 100, 220, 100) end
        self:Remove()
        return
    end

    if GRM.Inventory.AddItem then
        -- Код 99: данные экземпляра возвращаются в слот (включённый
        -- модулятор поднимается включённым; сейв-рестарт тоже ихдержит —
        -- дроп-энтити живёт в пределах сессии, data копируется целиком)
        local left = GRM.Inventory.AddItem(ply, id, count, data)
        -- AddItem may return notAdded count or bool depending on version
        if left == false then
            if GRM.Notify then GRM.Notify(ply, "Некуда положить", 255, 100, 100) end
            return
        end
        if isnumber(left) and left >= count then
            if GRM.Notify then GRM.Notify(ply, "Инвентарь полон", 255, 100, 100) end
            return
        end
        if isnumber(left) and left > 0 then
            self:SetItemCount(left)
            if GRM.Notify then GRM.Notify(ply, "Подобрано частично", 255, 200, 80) end
            return
        end
        if GRM.Notify then GRM.Notify(ply, "Подобрано", 100, 220, 100) end
        self:Remove()
    end
end
