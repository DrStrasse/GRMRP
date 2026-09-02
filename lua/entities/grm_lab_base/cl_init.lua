--[[--------------------------------------------------------------------
    grm_lab_base — клиентская часть: табличка над лабораторией.
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRM_Lab_Label", {font = "Roboto", size = 16, weight = 700, extended = true})

-- краски таблички — константы загрузки, в кадре конструкторов нет (§6.1.8)
local LAB_POS = Vector(0, 0, 0)
local LAB_TX   = Color(255, 255, 255)
local LAB_HINT = Color(100, 220, 100)
local LAB_EDGE = Color(0, 0, 0)

function ENT:Draw()
    self:DrawModel()

    local base = self:GetPos()
    LAB_POS.x = base.x
    LAB_POS.y = base.y
    LAB_POS.z = base.z + 20
    local pos = LAB_POS
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined(
            self:GetNWString("LabType", self.LabType or "narc") == "narc" and "Лаборатория наркотиков" or "Мед.лаборатория",
            "GRM_Lab_Label",
            0, 0,
            LAB_TX,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            LAB_EDGE
        )
        draw.SimpleTextOutlined(
            "[E] — Открыть меню",
            "GRM_Lab_Label",
            0, 20,
            LAB_HINT,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            LAB_EDGE
        )
    cam.End3D2D()
end
