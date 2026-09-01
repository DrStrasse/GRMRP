include("shared.lua")

surface.CreateFont("GRMJobC_T", { font = "Roboto", size = 19, weight = 800, extended = true })
surface.CreateFont("GRMJobC_S", { font = "Roboto", size = 13, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 320 * 320 then return end
    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 60) + 14)
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.08)
        draw.RoundedBox(6, -160, -44, 320, 88, Color(14, 18, 26, 225))
        surface.SetDrawColor(230, 180, 60, 220)
        surface.DrawOutlinedRect(-160, -44, 320, 88, 2)
        draw.SimpleText("Биржа труда", "GRMJobC_T", 0, -38, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("Вакансии и заказы фракций — [E] открыть", "GRMJobC_S", 0, -8, Color(160, 170, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("Статус в чате: /jobs • отказ: /jobcancel", "GRMJobC_S", 0, 12, Color(120, 130, 145), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    cam.End3D2D()
end
