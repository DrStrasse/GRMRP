include("shared.lua")

surface.CreateFont("GRMAnt_T", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMAnt_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 450 * 450 then return end

    local linked = self:GetNWBool("GRM_RN_Linked", false)
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 90) + 14)
    local blink = linked and ((math.sin(CurTime() * 5) + 1) * 0.5) or 0
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.08)
        draw.RoundedBox(6, -150, -44, 300, 88, Color(14, 18, 26, 225))
        surface.SetDrawColor(linked and 70 or 210, linked and 220 or 140, linked and 120 or 60, 190)
        surface.DrawOutlinedRect(-150, -44, 300, 88, 2)
        draw.SimpleText("Антенна", "GRMAnt_T", 0, -38, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if linked then
            draw.SimpleText("● УСИЛЕНИЕ АКТИВНО", "GRMAnt_S", 0, -12, Color(120 + blink * 120, 230, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("покрытие сети расширено", "GRMAnt_S", 0, 12, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("○ НЕТ СВЯЗИ СО СТОЙКОЙ", "GRMAnt_S", 0, -12, Color(255, 150, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("нужна активная стойка рядом", "GRMAnt_S", 0, 12, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    cam.End3D2D()
end
