ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Компьютер мониторинга связи"
ENT.Category = "GRM Phone"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TerminalName")
end
