include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    if not (GRM and GRM.CCTV and GRM.CCTV.Config and GRM.CCTV.Config.DrawLabels) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local dist = ply:GetPos():DistToSqr(self:GetPos())
    local maxd = (GRM.CCTV.Config.LabelDistance or 420)
    if dist > maxd * maxd then return end

    local pos = self:GetPos() + self:GetUp() * 12
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.08)
        local active = self:GetActive()
        local col = active and Color(80, 220, 120) or Color(220, 80, 80)
        draw.SimpleTextOutlined(
            (self:GetLabel() ~= "" and self:GetLabel() or "Камера") .. " [" .. (self:GetNetworkID() or "?") .. "]",
            "DermaDefaultBold", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200)
        )
        draw.SimpleTextOutlined(
            active and "● ONLINE" or "○ OFFLINE",
            "DermaDefault", 0, 14, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200)
        )
    cam.End3D2D()
end
