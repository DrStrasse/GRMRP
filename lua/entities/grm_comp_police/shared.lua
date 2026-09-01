--[[--------------------------------------------------------------------
    grm_comp_police — Служебный Компьютер Полиции Порядка (OrdnungPolizei)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер Полиции Порядка (OrdnungPolizei)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "ПОЛИЦИЯ ПОРЯДКА (Ordnungspolizei)"
ENT.CompTitle    = "ПОЛИЦИЯ ПОРЯДКА"
ENT.CompSubtitle = "OrdnungPolizei Terminal"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(12, 18, 30, 240),
    title = Color(80, 160, 255),
    sub   = Color(220, 230, 245),
    hint  = Color(150, 170, 200),
}
