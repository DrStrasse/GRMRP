include("shared.lua")

surface.CreateFont("GRMRS_T", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMRS_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end

    local on = self:GetNWBool("GRM_RN_Online", false)
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 50) + 14)
    local blink = on and ((math.sin(CurTime() * 4) + 1) * 0.5) or 0
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
        draw.RoundedBox(6, -160, -46, 320, 92, Color(14, 18, 26, 225))
        surface.SetDrawColor(on and 70 or 210, on and 150 or 140, on and 240 or 60, 190)
        surface.DrawOutlinedRect(-160, -46, 320, 92, 2)
        draw.SimpleText("Радиопередатчик", "GRMRS_T", 0, -40, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(on and "● СВЯЗАН С СЕТЬЮ" or "○ ВНЕ СЕТИ (нужна активная стойка)", "GRMRS_S", 0, -14,
            on and Color(120 + blink * 120, 190, 255) or Color(255, 140, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("микрофоны рядом вещают через него", "GRMRS_S", 0, 12, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
