AddCSLuaFile("entities/grm_pbx_station/shared.lua")
AddCSLuaFile("entities/grm_pbx_station/cl_init.lua")
include("entities/grm_pbx_station/shared.lua")

function ENT:Initialize()
    self:SetModel(GRM.Phone.Config.PBXModel or "models/props_lab/servers.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetExchangeID() == "" then self:SetExchangeID("main") end
    if self:GetActive() == false then self:SetActive(true) end
    if self:GetMaxLines() <= 0 then self:SetMaxLines(GRM.Phone.Config.PBXDefaultMaxLines or 60) end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake(); phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if GRM and GRM.Phone then GRM.Phone.OpenPBXMenu(ply, self) end
end
