--[[--------------------------------------------------------------------
    grm_comp_traffic — Экзаменационный ПК Автоинспекции (Автошкола / ВАИ / Дорожная Инспекция ПП)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Экзаменационный ПК Автоинспекции"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base. ]]
ENT.DefaultComputerName = "АВТОИНСПЕКЦИЯ • АВТОШКОЛА / ВАИ / ДОРОЖНАЯ ИНСПЕКЦИЯ ПП"
ENT.CompTitle    = "АВТОИНСПЕКЦИЯ"
ENT.CompSubtitle = "Автошкола / ВАИ / Дорожная Инспекция"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(14, 18, 26, 240),
    title = Color(80, 180, 255),
    sub   = Color(220, 235, 245),
    hint  = Color(150, 175, 200),
}
