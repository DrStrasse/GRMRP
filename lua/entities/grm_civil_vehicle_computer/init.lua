AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")
function ENT:Initialize()
 self:SetModel(self.Model)self:PhysicsInit(SOLID_VPHYSICS)self:SetMoveType(MOVETYPE_VPHYSICS)self:SetSolid(SOLID_VPHYSICS)self:SetUseType(SIMPLE_USE)
 if self:GetComputerName()==""then self:SetComputerName("ГРАЖДАНСКИЙ РЫНОК ТРАНСПОРТА")end
 local p=self:GetPhysicsObject()if IsValid(p)then p:Wake()p:EnableMotion(false)end
end
function ENT:Use(ply)
 if IsValid(ply)and ply:IsPlayer()and GRM.CivilVehicles and GRM.CivilVehicles.Open then GRM.CivilVehicles.Open(ply,self)end
end
