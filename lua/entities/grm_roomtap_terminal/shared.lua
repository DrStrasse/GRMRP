ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Компьютер мониторинга прослушки"
ENT.Category = "GRM RoomTap"
-- Spawnable=true требуется Sandbox для показа entity в меню Entities.
-- AdminSpawnable ограничивает спавн администраторами.
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DeviceID")
    self:NetworkVar("String", 1, "Label")
    self:NetworkVar("String", 2, "OwnerSteam")
    self:NetworkVar("String", 3, "OwnerName")
    self:NetworkVar("Bool", 0, "Permanent")
end
