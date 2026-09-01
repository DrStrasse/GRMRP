include("shared.lua")

surface.CreateFont("GRMBed_Title", { font = "Roboto", size = 26, weight = 800, extended = true, antialias = true })
surface.CreateFont("GRMBed_Sub",   { font = "Roboto", size = 17, weight = 600, extended = true, antialias = true })

--[[ Подпись плашкой НА КОРПУСЕ, тем же приёмом, что у терминалов,
     торгового автомата и домашнего шкафа: висящий в воздухе текст
     владелец уже просил убрать. ]]
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

    --[[ Кровать низкая и лежит горизонтально: плашку ставим над изголовьем,
         иначе она утонула бы в матрасе. ]]
    local pos = self:LocalToWorld(Vector(
        (mins.x + maxs.x) * 0.5,
        (mins.y + maxs.y) * 0.5,
        maxs.z + 14))

    local near = dist <= 150 * 150
    local sleeper = self:GetSleeper()
    local linked = self:GetLinked()

    local sub, subCol
    if IsValid(sleeper) then
        if sleeper == lp then
            sub, subCol = "НАЖМИТЕ  E  ЧТОБЫ ВСТАТЬ", Color(120, 220, 150)
        else
            sub, subCol = "занято", Color(255, 170, 90)
        end
    elseif not linked then
        -- Поставили мимо квартиры: админу видно, что это ошибка установки.
        sub, subCol = "ВНЕ ЗОНЫ ЖИЛЬЯ", Color(255, 150, 90)
    elseif near then
        sub, subCol = "НАЖМИТЕ  E", Color(120, 220, 150)
    else
        local name = self:GetHomeName()
        sub, subCol = name ~= "" and name or "точка входа", Color(150, 168, 190)
    end

    cam.Start3D2D(pos, ang, 0.09)
        draw.RoundedBox(6, -130, -32, 260, 64, Color(10, 14, 22, 238))
        draw.RoundedBox(0, -130, -32, 260, 3, linked and Color(90, 175, 255) or Color(255, 150, 90))
        draw.SimpleText("КРОВАТЬ", "GRMBed_Title", 0, -11,
            Color(235, 243, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, "GRMBed_Sub", 0, 15, subCol,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

--[[ Пока игрок лежит, показываем его самого: иначе он смотрел бы из
     головы модели, лежащей лицом в подушку. Вид от третьего лица
     включается только для того, кто в кровати. ]]
hook.Add("ShouldDrawLocalPlayer", "GRM_HomeBed_ThirdPerson", function(ply)
    local bed = ply and ply.GRMBedEnt
    if IsValid(bed) and bed:GetSleeper() == ply then return true end
end)

hook.Add("CalcView", "GRM_HomeBed_View", function(ply, pos, ang, fov)
    local bed = ply and ply.GRMBedEnt
    if not (IsValid(bed) and bed:GetSleeper() == ply) then return end
    --[[ Камера чуть выше и позади кровати: игрок видит себя лежащим и
         понимает, что происходит. Угол оставляем игроку — крутить
         головой лёжа не запрещено. ]]
    local eye = bed:GetPos() + Vector(0, 0, 70) - ang:Forward() * 60
    return { origin = eye, angles = ang, fov = fov, drawviewer = true }
end)
