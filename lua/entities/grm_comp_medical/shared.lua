--[[--------------------------------------------------------------------
    grm_comp_medical — Медицинский Компьютер Госпиталя (Медицинская служба / ВВК)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Медицинский Компьютер Госпиталя"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "МЕДИЦИНСКАЯ СЛУЖБА • ГОСПИТАЛЬ И ВВК"
ENT.CompTitle    = "МЕДИЦИНСКАЯ СЛУЖБА"
ENT.CompSubtitle = "Госпиталь и Военно-врачебная комиссия"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(12, 20, 16, 240),
    title = Color(90, 220, 150),
    sub   = Color(225, 245, 235),
    hint  = Color(150, 190, 170),
}
