AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local config = GRM and GRM.RoomTap and GRM.RoomTap.Config or {}

    self:SetModel(config.TerminalModel or "models/props/cs_office/computer.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetDeviceID() == "" then self:SetDeviceID("terminal_" .. os.time() .. "_" .. math.random(1000, 9999)) end
    if self:GetLabel() == "" then self:SetLabel("Компьютер мониторинга") end

    local physics = self:GetPhysicsObject()
    if IsValid(physics) then
        physics:Wake()
        physics:EnableMotion(false)
    end
end

function ENT:Use(ply)
    if GRM and GRM.RoomTap and GRM.RoomTap.OpenTerminalMenu then
        GRM.RoomTap.OpenTerminalMenu(ply, self)
    end
end
