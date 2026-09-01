ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Лист розыска"
ENT.Author = "GRM"
ENT.Category = "GRM"
ENT.Spawnable = true
ENT.AdminOnly = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PhotoID")
    self:NetworkVar("String", 1, "Headline")
    self:NetworkVar("String", 2, "Body")
    self:NetworkVar("String", 3, "SubjectName")
end
