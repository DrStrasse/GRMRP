ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Category = "GRM — Аугментации"
ENT.PrintName = "Чип аугментации"
ENT.Author = "GRM Team"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ChipID")
    self:NetworkVar("String", 1, "ChipName")
    self:NetworkVar("String", 2, "ChipCategory")
    self:NetworkVar("Int", 0, "ChipLevel")
    self:NetworkVar("Bool", 0, "Implanted")
    self:NetworkVar("Entity", 0, "Owner")
end
