--[[--------------------------------------------------------------------
    grm_comp_court — Компьютер юстиции (суд / прокуратура)

    Профильная станция судебной ветви (гражданская юрисдикция):
      • Законы и статьи (каталог GRM.Wanted, гражданские статьи);
      • Розыск (список разыскиваемых — справочно);
      • Реестр штрафов: выписка судебного штрафа и аннулирование.
    Всё идёт через ядро розыска/штрафов (GRM.Wanted / GRM.Wanted.Fines),
    военные дела остаются за Feldgendarmerie (grm_comp_military_police).
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер юстиции (суд)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "ЮСТИЦИЯ • СУД И ПРОКУРАТУРА"
ENT.CompTitle    = "ЮСТИЦИЯ"
ENT.CompSubtitle = "Суд и прокуратура"
ENT.CompHint     = "Нажмите [E] для входа"
ENT.CompColors = {
    bg    = Color(20, 20, 32, 240),
    title = Color(200, 170, 255),
    sub   = Color(225, 230, 235),
    hint  = Color(165, 175, 185),
}
