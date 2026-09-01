include("shared.lua")

surface.CreateFont("GRMRadio_T", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMRadio_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end

    local micIdx = self:GetNWInt("GRM_BC_Mic", 0)
    local on = self:GetNWBool("GRM_BC_On", false)
    local mic = IsValid(Entity(micIdx)) and Entity(micIdx) or nil
    local station = (mic and mic:GetNWString("GRM_BC_Station", "")) or ""
    local live = mic and mic:GetNWBool("GRM_BC_Live", false) or false
    local last = (mic and mic:GetNWString("GRM_BC_Last", "")) or ""
    if #last > 52 then last = string.sub(last, 1, 52) .. "…" end

    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 30) + 12)
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.07)
        draw.RoundedBox(6, -160, -56, 320, 112, Color(14, 18, 26, 225))
        surface.SetDrawColor(70, 150, 240, 220)
        surface.DrawOutlinedRect(-160, -56, 320, 112, 1)
        draw.SimpleText("Радиоприёмник", "GRMRadio_T", 0, -44, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if on and station ~= "" then
            local scol = live and Color(255, 90, 80) or Color(160, 170, 185)
            draw.SimpleText("Станция: " .. station, "GRMRadio_S", 0, -18, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(live and "● В ЭФИРЕ" or "— вещание молчит —", "GRMRadio_S", 0, 0, scol, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(last, "GRMRadio_S", 0, 18, Color(200, 208, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("выключен", "GRMRadio_S", 0, -6, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        draw.SimpleText("[E] Настроить станцию", "GRMRadio_S", 0, 38, Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
