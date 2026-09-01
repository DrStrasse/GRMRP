include("shared.lua")

surface.CreateFont("GRMSpk_T", { font = "Roboto", size = 19, weight = 800, extended = true })
surface.CreateFont("GRMSpk_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end

    local alerting = self:GetNWBool("GRM_BC_Alert", false)
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 60) + 14)
    local blink = alerting and ((math.sin(CurTime() * 8) + 1) * 0.5) or 0
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.08)
        draw.RoundedBox(6, -150, -40, 300, 80, Color(14, 18, 26, 225))
        surface.SetDrawColor(alerting and 255 or 230, alerting and 60 or 180, alerting and 50 or 60, 150 + blink * 105)
        surface.DrawOutlinedRect(-150, -40, 300, 80, 2)
        draw.SimpleText("Громкоговоритель", "GRMSpk_T", 0, -34, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(alerting and "!!! ОПОВЕЩЕНИЕ !!!" or "городская сеть оповещения", "GRMSpk_S", 0, -4,
            alerting and Color(255, 120 + blink * 120, 110) or Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
