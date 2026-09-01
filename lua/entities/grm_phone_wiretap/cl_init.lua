include("entities/grm_phone_wiretap/shared.lua")

function ENT:Draw()
    self:DrawModel()
    local pos = self:GetPos() + Vector(0,0,30)
    local ang = EyeAngles(); ang:RotateAroundAxis(ang:Forward(),90); ang:RotateAroundAxis(ang:Right(),90)

    cam.Start3D2D(pos, Angle(0,ang.y,90), 0.08)
        draw.SimpleTextOutlined("Прослушка", "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined((self:GetActive() and "ON" or "OFF") .. " №" .. self:GetTargetNumber(), "DermaDefaultBold", 0, 30, self:GetActive() and Color(255,180,80) or Color(180,180,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
