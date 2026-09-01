include("shared.lua")

local COL_LABEL = Color(240, 226, 180)
local COL_HINT = Color(150, 200, 160)

function ENT:Draw()
    self:DrawModel()

    -- Подпись рисуем только у лежащей посылки: у той, что в руках, она
    -- болталась бы перед лицом носильщика и мешала.
    if IsValid(self:GetCarrier()) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local pos = self:GetPos()
    if ply:GetPos():DistToSqr(pos) > 400 * 400 then return end

    local ang = (ply:EyeAngles() or Angle(0, 0, 0))
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    cam.Start3D2D(pos + Vector(0, 0, 22), Angle(0, ang.y, 90), 0.12)
        local label = self:GetLabel()
        if label == "" then label = "ПОСЫЛКА" end
        draw.SimpleText(label, "Trebuchet24", 0, -18, COL_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("E — поднять", "Trebuchet24", 0, 8, COL_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
