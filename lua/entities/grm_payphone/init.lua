AddCSLuaFile("entities/grm_payphone/shared.lua")
AddCSLuaFile("entities/grm_payphone/cl_init.lua")
include("entities/grm_payphone/shared.lua")

function ENT:Initialize()
    self:SetModel(GRM.Phone.Config.PayphoneModel or "models/props_equipment/phone_booth.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetPhoneNumber() == "" then self:SetPhoneNumber(GRM.Phone.GenerateNumber()) end
    if self:GetDisplayName() == "" then self:SetDisplayName("Таксофон") end
    if self:GetExchangeID() == "" then self:SetExchangeID("main") end
    if self:GetLineState() == "" then self:SetLineState("idle") end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake(); phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if GRM and GRM.Phone then GRM.Phone.OpenPhoneMenu(ply, self) end
end
