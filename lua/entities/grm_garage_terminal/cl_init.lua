include("shared.lua")

surface.CreateFont("GRMGarage_Sign",  { font = "Roboto", size = 26, weight = 800, extended = true })
surface.CreateFont("GRMGarage_Small", { font = "Roboto", size = 17, weight = 600, extended = true })

function ENT:Draw()
    self:DrawModel()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local dist = lp:GetPos():DistToSqr(self:GetPos())
    if dist > 600 * 600 then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(self:GetPos() + self:GetUp() * 46 + ang:Up() * 0, ang, 0.16)
        draw.RoundedBox(8, -190, -58, 380, 100, Color(12, 17, 25, 236))
        draw.RoundedBox(8, -190, -58, 380, 6, Color(245, 195, 65))
        draw.SimpleText("ГАРАЖ", "GRMGarage_Sign", 0, -34, Color(245, 195, 65), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(self:GetGarageName(), "GRMGarage_Small", 0, -2, Color(235, 240, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if dist < 240 * 240 then
            draw.SimpleText("E — меню гаража", "GRMGarage_Small", 0, 20, Color(120, 205, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    cam.End3D2D()
end
