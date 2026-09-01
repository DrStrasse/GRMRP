--[[--------------------------------------------------------------------
    grm_money_press_terminal — терминал управления печатным станком (находка 178)
    Запуск/остановка печати, прокачка скорости, охлаждение.
    Управляет БЛИЖАЙШИМ станком (grm_money_press) в радиусе 600.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Терминал печатного станка"
ENT.Author    = "GRM"
ENT.Category  = "GRM — Банк"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/lt_c/holo_wall_unit.mdl"
ENT.ModelFallback = "models/props_lab/reciever01b.mdl"

ENT.PressSearchRadius = 600
