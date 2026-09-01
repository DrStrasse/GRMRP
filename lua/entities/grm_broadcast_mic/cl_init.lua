include("shared.lua")

surface.CreateFont("GRMMic_T", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMMic_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 350 * 350 then return end

    local station = self:GetNWString("GRM_BC_Station", "ГРМ-Радио")
    local live = self:GetNWBool("GRM_BC_Live", false)
    local speaker = self:GetNWString("GRM_BC_Speaker", "")
    local pa = self:GetNWBool("GRM_BC_PA", false)
    local rnLink = self:GetNWInt("GRM_RN_Link", -1)

    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 40) + 14)
    local blink = live and ((math.sin(CurTime() * 6) + 1) * 0.5) or 0
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
        draw.RoundedBox(6, -150, -60, 300, 120, Color(14, 18, 26, 225))
        surface.SetDrawColor(live and 255 or 70, live and 60 or 150, live and 55 or 240, 150 + blink * 105)
        surface.DrawOutlinedRect(-150, -60, 300, 120, pa and 3 or 2)
        draw.SimpleText(station, "GRMMic_T", 0, -54, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if live then
            draw.SimpleText(pa and ("● ГРОМКАЯ СВЯЗЬ — " .. speaker) or ("● В ЭФИРЕ — " .. speaker), "GRMMic_S", 0, -28, Color(255, 120 + blink * 120, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("микрофон молчит", "GRMMic_S", 0, -28, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        if rnLink >= 0 then
            local ln, lc = "сеть: подключён", Color(120, 230, 130)
            if rnLink == 1 then ln, lc = "ПЕРЕДАТЧИК ВНЕ СЕТИ!", Color(255, 190, 90) end
            if rnLink == 0 then ln, lc = "НЕТ СЕТИ — эфир локальный", Color(255, 120, 110) end
            draw.SimpleText(ln, "GRMMic_S", 0, -6, lc, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        draw.SimpleText("[E] Пульт эфира (СМИ)", "GRMMic_S", 0, 34, Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
