include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local pos = self:WorldSpaceCenter() + Vector(0, 0, 18)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)
    local txt = self:GetDeployed() and "лестница  W/прыжок вверх" or "E — выдвинуть"
    cam.Start3D2D(pos, ang, 0.07)
        draw.SimpleText(txt, "DermaDefaultBold", 0, 0, Color(255, 180, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
