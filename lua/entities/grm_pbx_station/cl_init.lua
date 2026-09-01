include("entities/grm_pbx_station/shared.lua")

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0,0,34)
    local ang = EyeAngles(); ang:RotateAroundAxis(ang:Forward(),90); ang:RotateAroundAxis(ang:Right(),90)

    cam.Start3D2D(pos, Angle(0,ang.y,90), 0.08)
        draw.SimpleTextOutlined("АТС: " .. self:GetExchangeID(), "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined(self:GetActive() and "АКТИВНА" or "ОТКЛЮЧЕНА", "DermaDefaultBold", 0, 30, self:GetActive() and Color(100,255,100) or Color(255,80,80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined("Линий: " .. tostring(self:GetMaxLines()), "DermaDefaultBold", 0, 52, Color(180,220,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
