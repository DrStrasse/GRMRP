include("shared.lua")

surface.CreateFont("GRMCon3D_T", { font = "Roboto", size = 19, weight = 800, extended = true })
surface.CreateFont("GRMCon3D_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end

    local on = self:GetNWBool("GRM_RN_Online", false)
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 24) + 12)
    local blink = on and ((math.sin(CurTime() * 4) + 1) * 0.5) or 0
    local id = self:GetNWString("GRM_NetID", "")
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
        draw.RoundedBox(6, -150, -46, 300, (id ~= "" and 106 or 92), Color(14, 18, 26, 225))
        surface.SetDrawColor(on and 70 or 200, on and (170 + blink * 70) or 70, on and 140 or 70, 190)
        surface.DrawOutlinedRect(-150, -46, 300, (id ~= "" and 106 or 92), 2)
        draw.SimpleText("Пульт радиосети", "GRMCon3D_T", 0, -40, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(on and "● ПОДКЛЮЧЁН К СЕТИ" or "○ НЕТ СТОЙКИ РЯДОМ", "GRMCon3D_S", 0, -14,
            on and Color(120 + blink * 120, 220, 160) or Color(255, 120, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if id ~= "" then
            draw.SimpleText("позывной: " .. id, "GRMCon3D_S", 0, 8, Color(140, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        draw.SimpleText("[E] Открыть пульт (суперадмин)", "GRMCon3D_S", 0, (id ~= "" and 28 or 14), Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
