AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local cfg = GRM and GRM.Alarm and GRM.Alarm.Config or {}
    self:SetModel(cfg.HubModel or "models/props_lab/reciever_cart.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetDeviceID() == "" then
        self:SetDeviceID("hub_" .. os.time() .. "_" .. math.random(1000, 9999))
    end
    if self:GetLabel() == "" then self:SetLabel("Блок коммутации") end
    if self:GetNetworkID() == "" then
        self:SetNetworkID((GRM.Alarm and GRM.Alarm.NormalizeNetwork and GRM.Alarm.NormalizeNetwork(cfg.DefaultNetwork)) or "main")
    end
    if self:GetMode() < 1 then self:SetMode(1) end
    self:SetAlarmActive(false)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
    if GRM.Alarm and GRM.Alarm.RegisterDevice then GRM.Alarm.RegisterDevice(self) end
end

function ENT:OnRemove()
    if GRM.Alarm and GRM.Alarm.StopSiren then GRM.Alarm.StopSiren(self) end
    if GRM.Alarm and GRM.Alarm.UnregisterDevice then GRM.Alarm.UnregisterDevice(self) end
end

function ENT:Use(ply)
    if GRM.Alarm and GRM.Alarm.OpenDeviceMenu then
        GRM.Alarm.OpenDeviceMenu(ply, self, "hub")
    end
end
