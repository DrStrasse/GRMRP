include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    local pos = self:GetPos() + Vector(0, 0, 12)
    local ang = Angle(0, EyeAngles().y - 90, 90)
    local name = self:GetDisplayName()
    if name == "" then name = self:GetItemID() end
    cam.Start3D2D(pos, ang, 0.08)
        draw.SimpleTextOutlined(name .. " x" .. tostring(self:GetItemCount()),
            "DermaDefaultBold", 0, 0, Color(220, 220, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined("[E] подобрать", "DermaDefault", 0, 14, Color(180, 220, 180),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
