ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Терминал контроля чипов"
ENT.Author = "GRM"
ENT.Category = "GRM — Аугментации"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TerminalName")
end
