AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local cfg = GRM and GRM.CCTV and GRM.CCTV.Config or {}
    local model = cfg.ServerModel or "models/props_lab/servers.mdl"
    self:SetModel(model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetDeviceID() == "" then
        self:SetDeviceID("srv_" .. os.time() .. "_" .. math.random(1000, 9999))
    end
    if self:GetLabel() == "" then self:SetLabel("CCTV Server") end
    if self:GetNetworkID() == "" then
        self:SetNetworkID((GRM.CCTV and GRM.CCTV.NormalizeNetwork and GRM.CCTV.NormalizeNetwork(cfg.DefaultNetwork)) or "main")
    end
    self:SetActive(true)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end

    if GRM and GRM.CCTV and GRM.CCTV.RegisterDevice then
        GRM.CCTV.RegisterDevice(self)
    end
end

function ENT:OnRemove()
    if GRM and GRM.CCTV and GRM.CCTV.UnregisterDevice then
        GRM.CCTV.UnregisterDevice(self)
    end
end

function ENT:Use(ply)
    if GRM and GRM.CCTV and GRM.CCTV.OpenServerMenu then
        GRM.CCTV.OpenServerMenu(ply, self)
    end
end
