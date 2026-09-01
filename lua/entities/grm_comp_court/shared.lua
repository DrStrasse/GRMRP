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
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер юстиции (суд)"
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
