include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    if not (GRM and GRM.Alarm and GRM.Alarm.Config and GRM.Alarm.Config.DrawLabels) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local maxd = GRM.Alarm.Config.LabelDistance or 420
    if ply:GetPos():DistToSqr(self:GetPos()) > maxd * maxd then return end
    local pos = self:GetPos() + self:GetUp() * 28
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.09)
        draw.SimpleTextOutlined(self:GetLabel() ~= "" and self:GetLabel() or "Терминал охраны",
            "DermaDefaultBold", 0, 0, Color(120, 190, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined("net " .. tostring(self:GetNetworkID()),
            "DermaDefault", 0, 14, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
