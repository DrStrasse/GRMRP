include("shared.lua")

surface.CreateFont("GRMRack_T", { font = "Roboto", size = 19, weight = 800, extended = true })
surface.CreateFont("GRMRack_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end

    local on = self:GetNWBool("GRM_RN_On", true)
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 60) + 14)
    local blink = on and ((math.sin(CurTime() * 4) + 1) * 0.5) or 0
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
        draw.RoundedBox(6, -150, -46, 300, 92, Color(14, 18, 26, 225))
        surface.SetDrawColor(on and 80 or 200, on and (160 + blink * 80) or 70, on and 255 or 70, 190)
        surface.DrawOutlinedRect(-150, -46, 300, 92, 2)
        draw.SimpleText("Серверная стойка", "GRMRack_T", 0, -40, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(on and "● СЕТЬ АКТИВНА" or "○ ПИТАНИЕ ВЫКЛЮЧЕНО", "GRMRack_S", 0, -14,
            on and Color(120 + blink * 120, 220, 255) or Color(255, 120, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("[E] Питание вкл/выкл", "GRMRack_S", 0, 12, Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
