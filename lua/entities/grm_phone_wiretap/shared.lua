ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Оборудование прослушки"
ENT.Category = "GRM Phone"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TargetNumber")
    self:NetworkVar("String", 1, "ExchangeID")
    self:NetworkVar("Bool", 0, "Active")
end
