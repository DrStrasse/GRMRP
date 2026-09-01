include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    if not (GRM and GRM.CCTV and GRM.CCTV.Config and GRM.CCTV.Config.DrawLabels) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local dist = ply:GetPos():DistToSqr(self:GetPos())
    local maxd = (GRM.CCTV.Config.LabelDistance or 420)
    if dist > maxd * maxd then return end

    local pos = self:GetPos() + self:GetUp() * 40
    local ang = Angle(0, EyeAngles().y - 90, 90)
    local on = self:GetActive()
    local col = on and Color(100, 220, 140) or Color(220, 90, 90)
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined(
            self:GetLabel() ~= "" and self:GetLabel() or "CCTV Server",
            "DermaDefaultBold", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200)
        )
        draw.SimpleTextOutlined(
            (on and "ONLINE" or "OFFLINE") .. " · " .. tostring(self:GetNetworkID() or "?"),
            "DermaDefault", 0, 14, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200)
        )
    cam.End3D2D()
end
