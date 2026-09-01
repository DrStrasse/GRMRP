--[[--------------------------------------------------------------------
    grm_comp_security — Компьютер Спецслужб (Gestapo / Komitet)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Компьютер Спецслужб (Gestapo / Komitet)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base. ]]
ENT.DefaultComputerName = "СЛУЖБА ГОСУДАРСТВЕННОЙ БЕЗОПАСНОСТИ (Gestapo / Komitet)"
ENT.CompTitle    = "СЛУЖБА ГОСБЕЗОПАСНОСТИ"
ENT.CompSubtitle = "Gestapo / Komitet Security Console"
-- У ГБ вместо подсказки — гриф: так было и до сведения станций к базе.
ENT.CompHint     = "ГРИФ «СОВЕРШЕННО СЕКРЕТНО»"
ENT.CompColors = {
    bg    = Color(14, 10, 12, 240),
    title = Color(240, 80, 80),
    sub   = Color(240, 230, 230),
    hint  = Color(200, 120, 120),
}
