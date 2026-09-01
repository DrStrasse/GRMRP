ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM Шкаф (огнетушитель)"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Stock")
end
