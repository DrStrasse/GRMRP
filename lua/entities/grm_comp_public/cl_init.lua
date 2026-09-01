include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)
    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -150, -50, 300, 100, Color(14, 20, 28, 240))
        draw.SimpleText("ДЛЯ ГРАЖДАН", "DermaDefaultBold", 0, -24, Color(80, 200, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(self:GetComputerName() ~= "" and self:GetComputerName() or "Самообслуживание",
            "DermaDefault", 0, -4, Color(220, 230, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] — любой житель", "DermaDefault", 0, 20, Color(150, 170, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
