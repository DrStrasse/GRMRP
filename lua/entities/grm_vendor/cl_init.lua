--[[--------------------------------------------------------------------
    GRM Vendor Entity — вывеска торговца в стиле GRM.

    Было: HUDPaint каждый кадр обходил ВСЕХ торговцев на карте и рисовал
    плоский чёрный прямоугольник с текстом (плюс эмодзи, которые часть
    шрифтов не тянет). Стало: 3D2D-вывеска в палитре GRM рисуется самим
    энтити (ENT:Draw), то есть только когда торговец в кадре.
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRM_VendorSign",  { font = "Roboto", size = 26, weight = 800, extended = true })
surface.CreateFont("GRM_VendorLabel", { font = "Roboto", size = 17, weight = 700, extended = true })
surface.CreateFont("GRM_VendorHint",  { font = "Roboto", size = 14, weight = 600, extended = true })

local LABELS = {
    weapon    = "ТОРГОВЕЦ ОРУЖИЕМ",
    ore       = "СКУПЩИК РУДЫ",
    food      = "ЛАРЁК ЕДЫ",
    rare      = "ТОРГОВЕЦ РЕДКОСТЯМИ",
    accessory = "ТОРГОВЕЦ АКСЕССУАРАМИ",
    phone     = "САЛОН СВЯЗИ",
}

local COLORS = {
    weapon    = Color(225, 110, 90),
    ore       = Color(245, 195, 65),
    food      = Color(120, 210, 130),
    rare      = Color(190, 140, 245),
    accessory = Color(75, 195, 170),
    phone     = Color(90, 165, 245),
}

--[[ Вывеска рисуется ОДИН раз за кадр, в прозрачном проходе, через общий
     слой GRM.Sign: у энтити RenderGroup = BOTH, поэтому рисование прямо в
     ENT:Draw давало второй проход, который затирал уже нарисованный
     заголовок подложкой (та самая «плашка без букв»). ]]
function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local vtype = self:GetNWString("VendorType", self.VendorType or "weapon")
    if not GRM.Sign then return end
    GRM.Sign.Draw(self, {
        title    = LABELS[vtype] or "ТОРГОВЕЦ GRM",
        subtitle = self:GetNWString("GRMVendorName", "") ~= "" and self:GetNWString("GRMVendorName", "")
            or "Товары и услуги",
        hint     = "E — открыть магазин",
        accent   = COLORS[vtype] or Color(245, 195, 65),
        height   = 82,
    })
end
