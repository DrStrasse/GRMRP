--[[--------------------------------------------------------------------
    grm_plate — регистрационный номерной знак (GRM Plates)

    Модель — models/hunter/plates/plate025x075.mdl, материал —
    models/debug/debugwhite (белая заготовка, поверх которой рисуется
    сам номер). Знак ставится руками физганом и закрепляется на
    транспорте нажатием [E].
----------------------------------------------------------------------]]

ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Номерной знак"
ENT.Author        = "GRM"
ENT.Purpose       = "Регистрационный знак транспортного средства"
ENT.Instructions  = "Поставьте знак физганом на бампер и нажмите [E]"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = false
ENT.AdminSpawnable = false
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model    = "models/hunter/plates/plate025x075.mdl"
ENT.Material = "models/debug/debugwhite"
-- Визуальный масштаб бланка: компактнее стандартной hunter plate.
ENT.VisualScale = 0.70
