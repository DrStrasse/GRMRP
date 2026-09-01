--[[--------------------------------------------------------------------
    GRM Server Rack — серверная стойка, ядро радиосети (Код 85)
    E → питание вкл/выкл. К активной стойке пристыковываются антенны,
    передатчики, микрофоны и громкоговорители (радиус связи
    GRM.RadioNet.LinkDist). Модель — та, что у АТС телефонии
    (models/props_lab/servers.mdl), фолбэк — citizenradio.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Серверная стойка GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_lab/servers.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
