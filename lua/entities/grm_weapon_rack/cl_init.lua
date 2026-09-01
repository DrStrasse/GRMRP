include("shared.lua")

surface.CreateFont("GRMRackWorld", { font = "Roboto", size = 38, weight = 700, extended = true })
surface.CreateFont("GRMRackWorldSmall", { font = "Roboto", size = 26, weight = 500, extended = true })

function ENT:Draw()
    self:DrawModel()

    --[[ Подпись над стойкой: название и организация. Рисуем только вблизи,
         иначе на базе с десятком стоек это лишняя нагрузка на кадр. ]]
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local dist = ply:GetPos():DistToSqr(self:GetPos())
    if dist > 250000 then return end   -- ~500 units

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local faction = self:GetFactionName()
    local title = "ОРУЖЕЙНАЯ СТОЙКА"

    cam.Start3D2D(self:GetPos() + self:GetUp() * 42, ang, 0.12)
        draw.SimpleText(title, "GRMRackWorld", 0, -30, Color(240, 200, 90),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if faction ~= "" then
            local display = faction
            if GRM.Factions and GRM.Factions.DisplayName then
                display = GRM.Factions.DisplayName(faction)
            end
            draw.SimpleText(display, "GRMRackWorldSmall", 0, 8, Color(200, 212, 228),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
