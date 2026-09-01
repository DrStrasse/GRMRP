ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Category = "GRM — Аугментации"
ENT.PrintName = "Станция аугментаций"
ENT.Author = "GRM Team"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "StationName")
    self:NetworkVar("Bool", 0, "Active")
end
