AddCSLuaFile("entities/grm_phone_terminal/shared.lua")
AddCSLuaFile("entities/grm_phone_terminal/cl_init.lua")
include("entities/grm_phone_terminal/shared.lua")

function ENT:Initialize()
    self:SetModel(GRM.Phone.Config.TerminalModel or "models/props_lab/monitor01b.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetTerminalName() == "" then self:SetTerminalName("Мониторинг связи") end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake(); phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if GRM and GRM.Phone then GRM.Phone.OpenTerminalMenu(ply, self) end
end
