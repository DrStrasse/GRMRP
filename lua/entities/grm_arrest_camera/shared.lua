ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Камера для арестованных"
ENT.Category = "GRM — Арест"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "CameraID")
    self:NetworkVar("String", 1, "CameraName")
    self:NetworkVar("String", 2, "ArrestGroup")
end
