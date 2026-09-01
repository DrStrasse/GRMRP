ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM Гидрант"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Open")
    self:NetworkVar("Int", 0, "MaxHose")
    self:NetworkVar("Int", 1, "PortsMax")
end
