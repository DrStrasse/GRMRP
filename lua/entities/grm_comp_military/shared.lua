--[[--------------------------------------------------------------------
    grm_comp_military — Компьютер Военного Комиссариата (Военкомат / Призыв)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер Военного Комиссариата (Военкомат)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "ВОЕННЫЙ КОМИССАРИАТ • УЧЁТ И ПРИЗЫВ"
ENT.CompTitle    = "ВОЕННЫЙ КОМИССАРИАТ"
ENT.CompSubtitle = "Учёт, призыв и военные билеты"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(14, 20, 14, 240),
    title = Color(110, 210, 120),
    sub   = Color(220, 240, 220),
    hint  = Color(150, 185, 155),
}
