AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetComputerName() == "" then
        self:SetComputerName("ГРАЖДАНСКИЙ ТЕРМИНАЛ • САМООБСЛУЖИВАНИЕ")
    end
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if GRM.PublicKiosk and isfunction(GRM.PublicKiosk.Open) then
        GRM.PublicKiosk.Open(ply, self)
    elseif GRM.ATM and isfunction(GRM.ATM.Open) then
        GRM.ATM.Open(ply, self)
    end
end
