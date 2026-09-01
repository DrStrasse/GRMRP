AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local cfg = GRM and GRM.CCTV and GRM.CCTV.Config or {}
    local model = cfg.CameraModel or "models/props_silo/camera.mdl"
    -- fallback, если основная модель отсутствует на клиенте/сервере
    if cfg.CameraModelAlt and (not util.IsValidModel or not util.IsValidModel(model)) then
        model = cfg.CameraModelAlt
    end
    self:SetModel(model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)

    if self:GetDeviceID() == "" then
        self:SetDeviceID("cam_" .. os.time() .. "_" .. math.random(1000, 9999))
    end
    if self:GetLabel() == "" then self:SetLabel("Камера") end
    if self:GetNetworkID() == "" then
        self:SetNetworkID((GRM.CCTV and GRM.CCTV.NormalizeNetwork and GRM.CCTV.NormalizeNetwork(cfg.DefaultNetwork)) or "main")
    end
    if self:GetCamFOV() <= 0 then
        self:SetCamFOV((GRM.CCTV and GRM.CCTV.ClampFOV and GRM.CCTV.ClampFOV(cfg.DefaultFOV)) or 75)
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
    if GRM and GRM.CCTV and GRM.CCTV.OpenCameraMenu then
        GRM.CCTV.OpenCameraMenu(ply, self)
    end
end

-- Точка «глаза» камеры: чуть впереди модели по Forward.
function ENT:GetCamViewPos()
    return self:GetPos() + self:GetForward() * 6 + self:GetUp() * 2
end

function ENT:GetCamViewAng()
    return self:GetAngles()
end
