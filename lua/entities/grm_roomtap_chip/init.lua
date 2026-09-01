AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local config = GRM and GRM.RoomTap and GRM.RoomTap.Config or {}

    self:SetModel(config.ChipModel or "models/jaanus/wiretool/wiretool_controlchip.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetDeviceID() == "" then self:SetDeviceID("chip_" .. os.time() .. "_" .. math.random(1000, 9999)) end
    if self:GetLabel() == "" then self:SetLabel("Чип прослушки") end
    if self:GetChannel() == "" then self:SetChannel("main") end
    if self:GetRadius() <= 0 then self:SetRadius(config.DefaultChipRadius or 350) end
    self:SetActive(true)

    local physics = self:GetPhysicsObject()
    if IsValid(physics) then
        physics:Wake()
        physics:EnableMotion(false)
    end
end

function ENT:Use(ply)
    if GRM and GRM.RoomTap and GRM.RoomTap.OpenChipMenu then
        GRM.RoomTap.OpenChipMenu(ply, self)
    end
end
