AddCSLuaFile()

--[[ Кусок руды: подбирается клавишей E. Раньше при каждом подборе шли
     print-ы в консоль и сообщения через PrintMessage; теперь — уведомления
     GRM, звук и подбор ВСЕЙ кучки рядом одним нажатием (после разрушения
     узла падает 4–7 кусков, и щёлкать каждый было мучением). ]]
ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Кусок руды"
ENT.Category = "GRM MINE"
ENT.Spawnable = false

ENT.Model = "models/props_mining/rock_caves01b.mdl"

local MATERIALS = {
    copper   = "models/shiny",
    gold     = "models/shiny",
    aluminum = "",
    platinum = "models/props_combine/tprings_globe",
}

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "OreTypeNW")
end

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:SetOreType(oreType)
    oreType = tostring(oreType or "")
    self.OreType = oreType
    self:SetOreTypeNW(oreType)
    self:SetNWString("GRM_OreType", oreType)
    if GRM and GRM.Mining and GRM.Mining.OreColor then self:SetColor(GRM.Mining.OreColor(oreType)) end
    local mat = MATERIALS[oreType]
    if mat and mat ~= "" then self:SetMaterial(mat) end
end

if SERVER then
    local function pickOne(ply, chunk)
        if not (IsValid(chunk) and chunk:GetClass() == "grm_ore_chunk") then return false end
        local itemID = "ore_" .. tostring(chunk.OreType or chunk:GetOreTypeNW() or "")
        if not (GRM.Inventory and GRM.Inventory.ItemDefs and GRM.Inventory.ItemDefs[itemID]) then return false, "unknown" end
        local notAdded = GRM.Inventory.AddItem(ply, itemID, 1)
        if notAdded ~= 0 then return false, "full" end
        chunk:Remove()
        return true
    end

    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if (self._grmNextUse or 0) > CurTime() then return end
        self._grmNextUse = CurTime() + 0.2

        local ok, why = pickOne(activator, self)
        if not ok then
            if why == "full" then
                if GRM.Notify then GRM.Notify(activator, "Инвентарь полон — руда не влезает.", 255, 140, 110) end
            else
                if GRM.Notify then GRM.Notify(activator, "Этот тип руды не зарегистрирован в инвентаре.", 255, 140, 110) end
            end
            return
        end

        -- Собираем и соседние куски: одна кучка = одно нажатие.
        local radius = (GRM.Mining and GRM.Mining.Config and GRM.Mining.Config.ChunkPickup) or 96
        local picked = 1
        for _, e in ipairs(ents.FindInSphere(activator:GetPos(), radius)) do
            if IsValid(e) and e ~= self and e:GetClass() == "grm_ore_chunk" then
                if pickOne(activator, e) then picked = picked + 1 else break end
            end
        end

        activator:EmitSound("items/ammo_pickup.wav", 60, math.random(95, 105))
        if GRM.Notify then
            GRM.Notify(activator, ("Подобрано руды: %d"):format(picked), 120, 220, 140)
        end
    end
end
