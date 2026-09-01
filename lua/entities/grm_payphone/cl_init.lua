include("entities/grm_payphone/shared.lua")

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0,0,92)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.09)
        draw.SimpleTextOutlined("☎ Таксофон " .. self:GetPhoneNumber(), "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined(self:GetLineState(), "DermaDefaultBold", 0, 30, Color(180,220,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
