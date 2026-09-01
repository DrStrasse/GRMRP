--[[--------------------------------------------------------------------
    grm_vault_cash — клиент: подпись суммы над паллетой
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRMVaultCash", { font = "Roboto", size = 11, weight = 700, extended = true })

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end
    local amt = math.floor(self:GetAmount() or 0)
    if amt <= 0 then return end
    local pos = self:GetPos() + self:GetUp() * 24
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.08)
        local txt = (GRM and GRM.Format and GRM.Format(amt)) or (tostring(amt) .. " GRM")
        surface.SetFont("GRMVaultCash")
        local tw = surface.GetTextSize(txt)
        draw.RoundedBox(4, -tw/2 - 6, -9, tw + 12, 18, Color(10, 16, 24, 200))
        draw.SimpleText(txt, "GRMVaultCash", 0, 0, Color(130, 230, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("E — подобрать", "GRMVaultCash", 0, 16, Color(160, 175, 195), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
