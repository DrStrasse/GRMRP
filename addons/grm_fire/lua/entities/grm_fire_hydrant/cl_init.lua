include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local pos = self:WorldSpaceCenter() + Vector(0, 0, 22)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)
    local open = self:GetOpen()
    local txt = (open and "ГИДРАНТ ОТКРЫТ" or "гидрант закрыт") .. "  E взять/стык"
    cam.Start3D2D(pos, ang, 0.07)
        draw.SimpleText(txt, "DermaDefaultBold", 0, 0, open and Color(80, 200, 255) or Color(180, 190, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
