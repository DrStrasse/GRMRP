ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "GRM Рукав"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "StartEnt")
    self:NetworkVar("Entity", 1, "Holder")
    self:NetworkVar("Entity", 2, "EndNode")
    self:NetworkVar("Int", 0, "LaidLen")
    self:NetworkVar("Int", 1, "MaxLen")
    self:NetworkVar("Bool", 0, "Pressurized")
    self:NetworkVar("Bool", 1, "Docked")
    -- Живые концы: не зависят от PVS насоса. Клиент рисует отсюда.
    self:NetworkVar("Vector", 0, "SrcPos")
    self:NetworkVar("Vector", 1, "TailPos")
end
