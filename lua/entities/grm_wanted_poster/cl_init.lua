include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local pos = self:GetPos() + self:GetUp() * 8
    local ang = LocalPlayer():EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)
    cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.08)
        draw.SimpleText(self:GetHeadline() ~= "" and self:GetHeadline() or "РОЗЫСК", "DermaDefaultBold", 0, 0, Color(220, 40, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if self:GetSubjectName() ~= "" then
            draw.SimpleText(self:GetSubjectName(), "DermaDefault", 0, 16, Color(240, 230, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
