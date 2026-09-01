include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end
    local pos = self:GetPos() + Vector(0, 0, 28)
    -- метка следует за камерой рендера, а не за поворотом игрока
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.08)
        draw.RoundedBox(5, -140, -18, 280, 36, Color(8, 15, 24, 225))
        surface.SetDrawColor(80, 210, 255, 220)
        surface.DrawOutlinedRect(-140, -18, 280, 36, 1)
        draw.SimpleText("ТЕРМИНАЛ КОНТРОЛЯ ЧИПОВ", "DermaDefaultBold", 0, -12, Color(120, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] — реестр и журнал", "DermaDefault", 0, 8, Color(200, 220, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
