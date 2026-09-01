include("shared.lua")

function ENT:Draw()
    render.SetBlend(0.42)
    render.SetColorModulation(0.30, 0.78, 1)
    self:DrawModel()
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)

    local ply = LocalPlayer()
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local pos = self:WorldSpaceCenter() + Vector(0, 0, 16)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)
    local on = self:GetPumpOn()
    local agent = self:GetAgent()
    if agent == "" then agent = "water" end
    local have, maxv
    if agent == "foam" then have, maxv = self:GetFoam(), self:GetFoamMax()
    elseif agent == "powder" then have, maxv = self:GetPowder(), self:GetPowderMax()
    else have, maxv = self:GetTank(), self:GetTankMax() end
    local label = (agent == "foam" and "пена") or (agent == "powder" and "порошок") or "вода"
    local slots = tostring(self:GetHosesOut() or 0) .. "/" .. tostring(self:GetHosesMax() or 4)
    local txt = (on and "НАСОС  " or "насос выкл  ") .. label .. " " .. tostring(have) .. "/" .. tostring(maxv) .. "  " .. slots
    cam.Start3D2D(pos, ang, 0.07)
        draw.SimpleText(txt, "DermaDefaultBold", 0, 0, on and Color(80, 200, 255) or Color(180, 190, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("E — взять рукав   G — панель", "DermaDefault", 0, 14, Color(255, 170, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
