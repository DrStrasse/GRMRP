ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Предмет на земле"
ENT.Author = "GRM"
ENT.Category = "GRM"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemID")
    self:NetworkVar("Int", 0, "ItemCount")
    self:NetworkVar("String", 1, "DisplayName")
end
