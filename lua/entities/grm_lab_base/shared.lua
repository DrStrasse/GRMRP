--[[--------------------------------------------------------------------
    grm_lab_base — база лабораторий GRM.

    Мед- и нарко-лаборатории были двумя копиями одних и тех же трёх
    файлов: Initialize, Use и табличка Draw; отличались PrintName и
    фолбэком LabType (§5.4 п.12). Как заводится новая лаборатория:
        ENT.Base      = "grm_lab_base"
        ENT.PrintName = "…"
        ENT.LabType   = "med" | "narc" | …
----------------------------------------------------------------------]]
ENT.Type           = "anim"
ENT.Base           = "base_gmodentity"
ENT.PrintName      = "GRM — лаборатория (база)"
ENT.Author         = "GRM"
ENT.Category       = "GRM — RP"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

ENT.LabType  = "narc"
ENT.LabModel = "models/props_wasteland/laundry_washer003.mdl"
