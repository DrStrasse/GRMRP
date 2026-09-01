AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    if not util.IsValidModel(self.Model) then
        print("[GRM Radio] ВНИМАНИЕ: модель '" .. tostring(self.Model) .. "' не найдена!")
    end
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    self:SetNWBool("GRM_BC_On", false)
    self:SetNWInt("GRM_BC_Mic", 0)
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    if not (GRM and GRM.Broadcast and GRM.Broadcast.OpenRadioMenu) then return end
    GRM.Broadcast.OpenRadioMenu(activator, self)
end
