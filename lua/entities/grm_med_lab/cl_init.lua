include("shared.lua")

surface.CreateFont("GRM_Lab_Label", {font = "Roboto", size = 16, weight = 700, extended = true})

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0, 0, 20)
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined(
            self:GetNWString("LabType", self.LabType or "narc") == "narc" and "Лаборатория наркотиков" or "Мед.лаборатория",
            "GRM_Lab_Label",
            0, 0,
            Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )
        draw.SimpleTextOutlined(
            "[E] — Открыть меню",
            "GRM_Lab_Label",
            0, 20,
            Color(100, 220, 100),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )
    cam.End3D2D()
end
