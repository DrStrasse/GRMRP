include("shared.lua")

surface.CreateFont("GRMMoneyDrop_T", { font = "Roboto", size = 20, weight = 800, extended = true })

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local amt = math.max(0, tonumber(self:GetAmount()) or 0)
    local sum = (GRM and GRM.Format) and GRM.Format(amt) or tostring(amt)
    local pos = self:GetPos() + Vector(0, 0, 14)
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.09)
        draw.SimpleTextOutlined("Деньги: " .. sum, "GRMMoneyDrop_T", 0, 0,
            Color(120, 230, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined("[E] подобрать", "DermaDefault", 0, 20,
            Color(200, 220, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end
