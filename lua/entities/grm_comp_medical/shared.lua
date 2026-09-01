--[[--------------------------------------------------------------------
    grm_comp_medical — Медицинский Компьютер Госпиталя (Медицинская служба / ВВК)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Медицинский Компьютер Госпиталя"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ComputerName")
end
