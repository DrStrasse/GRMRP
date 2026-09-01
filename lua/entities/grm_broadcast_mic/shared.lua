--[[--------------------------------------------------------------------
    GRM Broadcast Mic — микрофонная стойка (Код 75)
    Журналист E → меню эфира. Модель из аддона Black Ops Interrogation
    Room (Props); при её отсутствии — фолбэк на citizenradio.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Микрофонная стойка GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/cod/bo1/interrogation_room/p_int_microphone.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
