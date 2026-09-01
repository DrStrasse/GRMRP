ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Заправка"
ENT.Category = "GRM Vehicles"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "FuelKind")
    self:NetworkVar("Entity", 0, "User")
    self:NetworkVar("Entity", 1, "HoseCar")   -- машина, в чьём баке шланг
    self:NetworkVar("Bool", 0, "Busy")
    self:NetworkVar("String", 1, "OwnerKey")
    self:NetworkVar("String", 2, "StationID")
    self:NetworkVar("Float", 0, "PriceL")
    self:NetworkVar("Int", 0, "Cash")
    self:NetworkVar("Float", 1, "SessionL")
    self:NetworkVar("Float", 2, "SessionPay")
    self:NetworkVar("Float", 3, "TankNow")
    self:NetworkVar("Float", 4, "TankMax")
end
