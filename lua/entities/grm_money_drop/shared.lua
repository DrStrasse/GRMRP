--[[--------------------------------------------------------------------
    GRM — деньги на земле (Код 81)
    Дроп наличных: /dropmoney <сумма> — пачка падает перед игроком,
    E → подобрать в кошелёк. Модель задана заказом владельца.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Деньги"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model          = "models/props/cs_assault/money.mdl"
ENT.ModelFallback  = "models/props_junk/cardboard_box004a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Amount")
end
