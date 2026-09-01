ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "АТС станция"
ENT.Category = "GRM Phone"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ExchangeID")
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Int", 0, "MaxLines")
end
