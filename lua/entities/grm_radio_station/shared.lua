--[[--------------------------------------------------------------------
    GRM Radio Station — радиопередатчик / аппаратура передачи (Код 85)
    Микрофонная стойка подключается к передатчику (радиус связи),
    передатчик — к активной серверной стойке. Только тогда эфир уходит
    в городскую радиосеть.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Радиопередатчик GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_lab/reciever01a.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
