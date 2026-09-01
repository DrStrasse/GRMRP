ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Стационарный телефон"
ENT.Category = "GRM Phone"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PhoneNumber")
    self:NetworkVar("String", 1, "DisplayName")
    self:NetworkVar("String", 2, "ExchangeID")
    self:NetworkVar("String", 3, "LineState")
    self:NetworkVar("Entity", 0, "OtherPhone")
    self:NetworkVar("Int", 0, "CallID")
end
