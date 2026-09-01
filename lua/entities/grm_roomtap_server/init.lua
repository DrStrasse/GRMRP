AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local config = GRM and GRM.RoomTap and GRM.RoomTap.Config or {}

    self:SetModel(config.ServerModel or "models/props_silo/silo_server_d.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetDeviceID() == "" then self:SetDeviceID("server_" .. os.time() .. "_" .. math.random(1000, 9999)) end
    if self:GetLabel() == "" then self:SetLabel("Серверная стойка") end
    if self:GetChannel() == "" then self:SetChannel("main") end
    self:SetActive(true)

    local physics = self:GetPhysicsObject()
    if IsValid(physics) then
        physics:Wake()
        physics:EnableMotion(false)
    end
end

function ENT:Use(ply)
    if GRM and GRM.RoomTap and GRM.RoomTap.OpenServerMenu then
        GRM.RoomTap.OpenServerMenu(ply, self)
    end
end
