--[[--------------------------------------------------------------------
    grm_comp_traffic — Экзаменационный ПК Автоинспекции (Автошкола / ВАИ / Дорожная Инспекция ПП)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Экзаменационный ПК Автоинспекции"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ComputerName")
end
