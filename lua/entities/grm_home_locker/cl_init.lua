include("shared.lua")

surface.CreateFont("GRMLockerEnt_Title", { font = "Roboto", size = 26, weight = 800, extended = true, antialias = true })
surface.CreateFont("GRMLockerEnt_Sub",   { font = "Roboto", size = 17, weight = 600, extended = true, antialias = true })

--[[ Подпись рисуем ПЛАШКОЙ НА КОРПУСЕ, как у терминалов и торгового
     автомата (замечание владельца 27.08: висящий в воздухе текст плохо
     читается и слишком высоко). Плоскость 3D2D разворачивается в углах
     самого шкафа, поэтому надпись выглядит наклейкой на дверце. ]]
function ENT:Draw()
    self:DrawModel()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local dist = lp:EyePos():DistToSqr(self:GetPos())
    if dist > 320 * 320 then return end

    local mins, maxs = self:OBBMins(), self:OBBMaxs()
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local pos = self:LocalToWorld(Vector(maxs.x + 0.6,
        (mins.y + maxs.y) * 0.5,
        mins.z + (maxs.z - mins.z) * 0.82))

    -- Сзади наклейки нет — не рисуем.
    if (lp:EyePos() - pos):Dot(self:GetForward()) < 0 then return end

    local used = self:GetUsedSlots()
    local total = math.max(1, self:GetTotalSlots())
    local near = dist <= 150 * 150

    local sub, subCol
    if used < 0 then
        -- Шкаф поставлен вне зоны жилья: админу видно, что это ошибка.
        sub, subCol = "ВНЕ ЗОНЫ ЖИЛЬЯ", Color(255, 150, 90)
    elseif near then
        sub, subCol = "НАЖМИТЕ  E", Color(120, 220, 150)
    else
        sub, subCol = ("занято %d из %d"):format(used, total), Color(150, 168, 190)
    end

    cam.Start3D2D(pos, ang, 0.09)
        draw.RoundedBox(6, -120, -32, 240, 64, Color(10, 14, 22, 238))
        draw.RoundedBox(0, -120, -32, 240, 3, Color(90, 175, 255))
        draw.SimpleText("ДОМАШНИЙ ШКАФ", "GRMLockerEnt_Title", 0, -11,
            Color(235, 243, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, "GRMLockerEnt_Sub", 0, 15, subCol,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
