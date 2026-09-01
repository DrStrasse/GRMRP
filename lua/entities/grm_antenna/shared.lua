--[[--------------------------------------------------------------------
    GRM Antenna — антенна-усилитель частоты сигнала (Код 85)
    Работает, только если в радиусе связи есть АКТИВНАЯ серверная
    стойка. Каждая связанная антенна даёт круг покрытия
    GRM.RadioNet.AntennaRange — в нём ловят рации и радиоприёмники,
    а громкоговорители района подключены к сети.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Антенна GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_rooftop/antenna01a.mdl"
ENT.ModelFallback = "models/props_rooftop/antennaclusters01a.mdl"
ENT.ModelFallback2 = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
