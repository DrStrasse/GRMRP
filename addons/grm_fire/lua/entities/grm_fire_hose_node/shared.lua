ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM Узел рукава"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Hose")
    self:NetworkVar("Entity", 1, "NextNode")
    self:NetworkVar("Int", 0, "NodeType")
end
