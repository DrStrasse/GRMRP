ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Камера видеонаблюдения"
ENT.Author = "GRM"
ENT.Category = "GRM CCTV"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DeviceID")
    self:NetworkVar("String", 1, "Label")
    self:NetworkVar("String", 2, "NetworkID")
    self:NetworkVar("String", 3, "OwnerSteam")
    self:NetworkVar("String", 4, "OwnerName")
    self:NetworkVar("Int", 0, "CamFOV")
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Permanent")
end
