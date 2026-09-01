AddCSLuaFile("entities/grm_phone_wiretap/shared.lua")
AddCSLuaFile("entities/grm_phone_wiretap/cl_init.lua")
include("entities/grm_phone_wiretap/shared.lua")

function ENT:Initialize()
    self:SetModel(GRM.Phone.Config.WiretapModel or "models/props_lab/reciever01a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetExchangeID() == "" then self:SetExchangeID("main") end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake(); phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if GRM and GRM.Phone then GRM.Phone.OpenWiretapMenu(ply, self) end
end
