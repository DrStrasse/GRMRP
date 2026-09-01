AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_wasteland/laundry_washer003.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    -- Устанавливаем тип если не установлен (по умолчанию med)
    if not self.LabType then
        self.LabType = "med"
    end
    self:SetNWString("LabType", self.LabType)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local labType = self.LabType or "med"
    if GRM and GRM.NarcCraft and GRM.NarcCraft.OpenLab then
        GRM.NarcCraft.OpenLab(ply, labType, self)
    else
        ply:ChatPrint("[Лаборатория] Модуль крафта ещё не загружен")
    end
end
