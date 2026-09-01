--[[--------------------------------------------------------------------
    GRM Loudspeaker — уличный громкоговоритель оповещения (Код 75)
    Расставляется по районам города. Массовое оповещение /alert
    слышно возле работающих громкоговорителей.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Громкоговоритель GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_wasteland/speakercluster01a.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
