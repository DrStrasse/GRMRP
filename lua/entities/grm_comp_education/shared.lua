--[[--------------------------------------------------------------------
    grm_comp_education — Компьютер учреждения образования (деканат)

    Рабочее место для выписки государственных дипломов. Логика интерфейса
    общая с вкладкой «Учреждение образования» в меню фракций и живёт в
    lua/autorun/sh_grm_education.lua.
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер учреждения образования"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base. ]]
ENT.DefaultComputerName = "УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ"
ENT.CompTitle    = "УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ"
ENT.CompSubtitle = "Выписка государственных дипломов"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(18, 20, 28, 240),
    title = Color(245, 200, 70),
    sub   = Color(235, 238, 245),
    hint  = Color(150, 158, 175),
}

--[[ Заголовок школы задаётся инструментом «GRM Служебное оборудование»:
     на карте может стоять и «ГИМНАЗИЯ №1», и «ВОЕННАЯ АКАДЕМИЯ». ]]
function ENT:CompLabels()
    local title = self:GetComputerName()
    if title == "" then title = self.CompTitle end
    return title, self.CompSubtitle, self.CompHint
end
