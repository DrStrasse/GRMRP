--[[--------------------------------------------------------------------
    GRM Vendor Entity v2.0 — shared (Код 111)
----------------------------------------------------------------------]]

ENT.Type      = "anim"
ENT.Base      = "base_anim"
ENT.PrintName = "GRM Торгаш"
ENT.Category  = "GRM Vendors"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_BOTH -- вывеска 3D2D рисуется поверх модели

-- Тип задаётся при спавне: weapon / ore / food / rare
ENT.VendorType    = "weapon"
ENT.CustomPrices  = nil
ENT.CustomLimits  = nil
ENT.EnabledItems = nil
ENT.DisplayName = ""
ENT.VendorModel = ""
