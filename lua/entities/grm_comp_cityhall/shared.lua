--[[--------------------------------------------------------------------
    grm_comp_cityhall — Компьютер мэрии / городской администрации

    Профильная станция городской администрации:
      • выдача/отзыв лицензий на ведение бизнеса (госпошлина + теория-экзамен,
        ядро — GRM.Documents);
      • обзор городской казны и госуслуг (бюджет, счета, каталог услуг).
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер мэрии (городская администрация)"
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
