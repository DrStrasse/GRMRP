--[[--------------------------------------------------------------------
    grm_comp_public — Гражданский терминал самообслуживания
----------------------------------------------------------------------]]
ENT.Type           = "anim"
ENT.Base           = "grm_comp_base"
ENT.PrintName      = "Гражданский терминал (самообслуживание)"
ENT.Author         = "GRM"
ENT.Category       = "GRM — RP"
ENT.Spawnable      = true
ENT.AdminSpawnable = true
ENT.RenderGroup    = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base. ]]
ENT.DefaultComputerName = "ГРАЖДАНСКИЙ ТЕРМИНАЛ • САМООБСЛУЖИВАНИЕ"
ENT.CompTitle    = "ДЛЯ ГРАЖДАН"
ENT.CompSubtitle = "Самообслуживание"
ENT.CompHint     = "Нажмите [E] — любой житель"
ENT.CompColors = {
    bg    = Color(14, 20, 28, 240),
    title = Color(80, 200, 170),
    sub   = Color(220, 230, 235),
    hint  = Color(150, 170, 175),
}

--[[ Под заголовком показываем имя конкретного терминала (его задаёт
     инструмент), а не общее слово — иначе на карте все одинаковые. ]]
function ENT:CompLabels()
    local name = self:GetComputerName()
    return self.CompTitle, name ~= "" and name or self.CompSubtitle, self.CompHint
end
