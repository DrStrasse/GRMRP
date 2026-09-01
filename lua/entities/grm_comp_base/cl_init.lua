--[[--------------------------------------------------------------------
    grm_comp_base — клиентская часть: табличка над станцией.
----------------------------------------------------------------------]]
include("shared.lua")

-- Геометрия таблички одинакова у всех станций; держим константами,
-- чтобы в кадре не считалось ничего лишнего.
local PANEL_X, PANEL_Y = -150, -50
local PANEL_W, PANEL_H = 300, 100
local FONT_TITLE, FONT_TEXT = "DermaDefaultBold", "DermaDefault"

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local colors = self.CompColors
    local title, subtitle, hint = self:CompLabels()

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, colors.bg)
        draw.SimpleText(title, FONT_TITLE, 0, -25, colors.title,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if subtitle ~= "" then
            draw.SimpleText(subtitle, FONT_TEXT, 0, -5, colors.sub,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(hint, FONT_TEXT, 0, 20, colors.hint,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
