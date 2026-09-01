AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local cfg = GRM and GRM.Alarm and GRM.Alarm.Config or {}
    self:SetModel(cfg.SensorModel or "models/bull/various/gyroscope.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetDeviceID() == "" then
        self:SetDeviceID("sns_" .. os.time() .. "_" .. math.random(1000, 9999))
    end
    if self:GetLabel() == "" then self:SetLabel("Датчик движения") end
    if self:GetNetworkID() == "" then
        self:SetNetworkID((GRM.Alarm and GRM.Alarm.NormalizeNetwork and GRM.Alarm.NormalizeNetwork(cfg.DefaultNetwork)) or "main")
    end
    if self:GetRadius() <= 0 then
        self:SetRadius(tonumber(cfg.DefaultSensorRadius) or 220)
    end
    self:SetActive(true)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
    if GRM.Alarm and GRM.Alarm.RegisterDevice then GRM.Alarm.RegisterDevice(self) end
end

function ENT:OnRemove()
    if GRM.Alarm and GRM.Alarm.UnregisterDevice then GRM.Alarm.UnregisterDevice(self) end
end

function ENT:Use(ply)
    if GRM.Alarm and GRM.Alarm.OpenDeviceMenu then
        GRM.Alarm.OpenDeviceMenu(ply, self, "sensor")
    end
end
