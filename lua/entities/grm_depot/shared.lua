--[[--------------------------------------------------------------------
    GRM Jobs — точка доставки/дежурства (Код 77)
    Расставляется суперадмином по городу (/jobdepot_add): сюда ведут
    курьерские вакансии, зоны патруля и складская смена биржи труда.
    Сама по себе точка пассивна (без E) — цель задач.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Точка доставки GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model          = "models/props_wasteland/controlroom_filecabinet002a.mdl"
ENT.ModelFallback  = "models/props_junk/wood_crate001a.mdl"
ENT.ModelFallback2 = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
