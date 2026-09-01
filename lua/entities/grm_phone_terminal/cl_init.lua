include("entities/grm_phone_terminal/shared.lua")

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0,0,24)
    local ang = EyeAngles(); ang:RotateAroundAxis(ang:Forward(),90); ang:RotateAroundAxis(ang:Right(),90)

    cam.Start3D2D(pos, Angle(0,ang.y,90), 0.08)
        draw.SimpleTextOutlined("Мониторинг связи", "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
