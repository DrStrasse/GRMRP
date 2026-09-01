ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Серверная стойка записи"
ENT.Category = "GRM RoomTap"
-- Spawnable=true требуется Sandbox для показа entity в меню Entities.
-- AdminSpawnable ограничивает спавн администраторами.
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DeviceID")
    self:NetworkVar("String", 1, "Label")
    self:NetworkVar("String", 2, "Channel")
    self:NetworkVar("String", 3, "OwnerSteam")
    self:NetworkVar("String", 4, "OwnerName")
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Permanent")
end
