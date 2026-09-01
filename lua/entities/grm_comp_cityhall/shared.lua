--[[--------------------------------------------------------------------
    grm_comp_cityhall — Компьютер мэрии / городской администрации

    Профильная станция городской администрации:
      • выдача/отзыв лицензий на ведение бизнеса (госпошлина + теория-экзамен,
        ядро — GRM.Documents);
      • обзор городской казны и госуслуг (бюджет, счета, каталог услуг).
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер мэрии (городская администрация)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "МЭРИЯ • ГОРОДСКАЯ АДМИНИСТРАЦИЯ"
ENT.CompTitle    = "ГОРОДСКАЯ АДМИНИСТРАЦИЯ"
ENT.CompSubtitle = "Компьютер мэрии"
ENT.CompHint     = "Нажмите [E] для входа"
ENT.CompColors = {
    bg    = Color(16, 28, 30, 240),
    title = Color(80, 200, 200),
    sub   = Color(225, 230, 235),
    hint  = Color(165, 175, 185),
}
