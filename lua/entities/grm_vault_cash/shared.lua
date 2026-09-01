--[[--------------------------------------------------------------------
    grm_vault_cash — паллета денег банка (находка 178)
    Дропается в хранилище при пополнении/изъятии гос.бюджета и печати
    станка. E — подобрать (деньги в кошелёк).
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Паллета денег"
ENT.Author    = "GRM"
ENT.Category  = "GRM — Банк"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_assault/moneypalleta.mdl"
ENT.ModelFallback = "models/props/cs_assault/money.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Amount")
end
