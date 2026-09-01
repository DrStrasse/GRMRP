--[[--------------------------------------------------------------------
    grm_comp_education — Компьютер учреждения образования (деканат)

    Рабочее место для выписки государственных дипломов. Логика интерфейса
    общая с вкладкой «Учреждение образования» в меню фракций и живёт в
    lua/autorun/sh_grm_education.lua.
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер учреждения образования"
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
