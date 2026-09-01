include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    if not (GRM and GRM.Alarm and GRM.Alarm.Config and GRM.Alarm.Config.DrawLabels) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local maxd = GRM.Alarm.Config.LabelDistance or 420
    if ply:GetPos():DistToSqr(self:GetPos()) > maxd * maxd then return end
    local mode = self:GetMode()
    local col = (GRM.Alarm.ModeColors and GRM.Alarm.ModeColors[mode]) or Color(200, 200, 200)
    if self:GetAlarmActive() then col = Color(255, 60, 60) end
    local pos = self:GetPos() + self:GetUp() * 40
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.09)
        draw.SimpleTextOutlined(self:GetLabel() ~= "" and self:GetLabel() or "Коммутация",
            "DermaDefaultBold", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        local modeName = GRM.Alarm.ModeName and GRM.Alarm.ModeName(mode) or tostring(mode)
        if self:GetAlarmActive() then modeName = "ТРЕВОГА!" end
        draw.SimpleTextOutlined("net " .. tostring(self:GetNetworkID()) .. " · " .. modeName,
            "DermaDefault", 0, 16, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
