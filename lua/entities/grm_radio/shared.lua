--[[--------------------------------------------------------------------
    GRM Radio — домашний радиоприёмник (Код 75)
    E → меню настройки станции. Слушатели возле приёмника слышат эфир.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Радиоприёмник GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "BCOn")
    self:NetworkVar("Int", 0, "BCMic")
end
