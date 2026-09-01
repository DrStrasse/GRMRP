ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Банковский терминал GRM"
ENT.Category = "GRM Economy"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TerminalName")
end
