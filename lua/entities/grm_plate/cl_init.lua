include("shared.lua")

--[[ НОМЕР НА ЗНАКЕ — АВТОМАТИЧЕСКОЕ ЧТЕНИЕ ПОВЕРХНОСТИ (заказ 22.08).

     Что было не так:
       • надпись рисовалась отдельной плашкой, вынесенной ВПЕРЁД от знака
         на ручной «вынос», и её приходилось подгонять командами;
       • ориентация строки бралась из общей настройки (ось/поворот/зеркало),
         одной на все знаки сервера: повернул знак на другой машине — и
         номер лёг боком;
       • ENT:Draw вызывался дважды за кадр (RenderGroup = BOTH, а
         DrawTranslucent просто звал Draw), поэтому вторая отрисовка
         накрывала первую и текст «дрожал».

     Как теперь:
       • плоскость знака читается из габаритов модели: самая тонкая ось —
         нормаль лицевой стороны, две другие — плоскость надписи;
       • какая из осей плоскости идёт ВДОЛЬ СТРОКИ, решается по тому, как
         знак реально стоит в мире: строка кладётся на более горизонтальную
         ось, «вверх» выбирается тот, что смотрит вверх. Знак можно вешать
         как угодно — номер всегда читается ровно;
       • надпись лежит НА поверхности (полсотой юнита над ней), а не висит
         впереди, и автоматически вписывается в размер знака по ширине и по
         высоте — никакой ручной подгонки масштаба;
       • рисуется одна сторона — та, что обращена к игроку;
       • отрисовка ровно одна за кадр: модель в ENT:Draw, надпись в
         ENT:DrawTranslucent.
     Ручные доводки (наклон/сдвиг из /номер_настройки) по-прежнему
     применяются поверх автоматики — если владелец захочет их задать.
----------------------------------------------------------------------]]

function ENT:Initialize()
    self:SetModelScale(self.VisualScale or 0.70, 0)
    self:SetMaterial(self.Material)
end

--- Геометрия лицевой стороны: считает общий слой, здесь только кэш.
local function faceGeometry(ent)
    if ent.GRMFace then return ent.GRMFace end
    local PL = GRM and GRM.Plates
    if not (PL and PL.FaceGeometry) then return nil end
    ent.GRMFace = PL.FaceGeometry(ent:OBBMins(), ent:OBBMaxs(), PL.Render)
    return ent.GRMFace
end

--- Локальное направление → мировое.
local function worldDir(ent, localVec)
    return (ent:LocalToWorld(localVec) - ent:GetPos()):GetNormalized()
end

--[[ Автоматический выбор осей строки.
     Возвращает: right (вдоль строки), up (вверх по знаку), длину и высоту
     поля надписи в юнитах. Ничего не спрашивает у настроек: смотрит, как
     знак стоит в мире. ]]
local function planeAxes(ent, face)
    local dLong  = worldDir(ent, face.unitLong or face.right)
    local dShort = worldDir(ent, face.unitShort or face.up)
    local sLong  = face.sizeLong or 1
    local sShort = face.sizeShort or 1

    local right, up, w, h
    if math.abs(dLong.z) <= math.abs(dShort.z) then
        right, up, w, h = dLong, dShort, sLong, sShort
    else
        right, up, w, h = dShort, dLong, sShort, sLong
    end
    if up.z < 0 then up = up * -1 end
    return right, up, w, h
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local PL = GRM and GRM.Plates
    if not PL then return end
    local number = self:GetNWString("GRM_Plate", "")
    if number == "" then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if lp:EyePos():DistToSqr(self:GetPos()) > 700 * 700 then return end

    local face = faceGeometry(self)
    if not face then return end

    local kind   = self:GetNWString("GRM_PlateType", "civil")
    local status = self:GetNWString("GRM_PlateStatus", "active")
    local def    = PL.TypeDef(kind)
    local text   = PL.FormatNumber(number, kind)

    local right, up, faceW, faceH = planeAxes(self, face)
    local center = self:LocalToWorld(face.center)
    local nrm = right:Cross(up)
    if nrm:Length() < 0.001 then nrm = worldDir(self, face.normal) end
    nrm:Normalize()

    -- У plate025x075 локальная рассчитанная грань оказывается обращена к
    -- кузову после Attach. Рендерим фиксированно ПРОТИВОПОЛОЖНУЮ сторону:
    -- номер лежит снаружи, а не вдавливается в бампер. Взгляд игрока на
    -- выбор стороны не влияет.
    nrm = nrm * -1
    right = right * -1

    -- Не отсекаем сторону по позиции камеры: из водительского кресла камера
    -- оказывается «за» лицевой гранью и старый cull полностью убирал номер.
    -- Ориентация при этом остаётся фиксированной, не разворачивается за игроком.

    -- надпись лежит на самой поверхности знака, а не висит перед ним
    local lift = (face.thickness or 1) * 0.5 + 0.06 + (tonumber(face.offset) or 0) * 0.0
    local pos = center + nrm * lift
        + right * (face.moveX or 0) + up * (face.moveY or 0)

    -- Facepunch cam.Start3D2D: +X идёт по Forward угла, +Y — по -Right.
    -- Для поля знака dx=right, dy=-up, значит угол строится строго как
    -- dx:AngleEx(dx:Cross(-dy)) = right:AngleEx(right:Cross(up)).
    -- Раньше в Up передавался up вместо нормали, и вся 3D2D-плашка
    -- вставала ребром: белая модель и зелёное поле разъезжались.
    local ang = right:AngleEx(nrm)
    if (face.tiltR or 0) ~= 0 then ang:RotateAroundAxis(ang:Forward(), face.tiltR) end
    if (face.tiltP or 0) ~= 0 then ang:RotateAroundAxis(ang:Right(), face.tiltP) end
    if (face.tiltY or 0) ~= 0 then ang:RotateAroundAxis(ang:Up(), face.tiltY) end

    -- масштаб 3D2D: поле знака в пикселях
    local scale = 0.05
    -- Поле чуть меньше физической основы: остаётся аккуратная белая кромка,
    -- знак не выглядит огромной наклейкой на бампере.
    local renderScale = 0.60
    local w, h = (faceW * renderScale) / scale, (faceH * renderScale) / scale

    local plateCol = Color(def.plate[1], def.plate[2], def.plate[3])
    local bandCol  = Color(def.band[1], def.band[2], def.band[3])
    local textCol  = Color(def.text[1], def.text[2], def.text[3])
    if status ~= "active" then textCol = Color(200, 40, 40) end

    local bandW = w * 0.13

    cam.Start3D2D(pos, ang, scale)
        draw.RoundedBox(0, -w / 2, -h / 2, w, h, plateCol)
        draw.RoundedBox(0, -w / 2, -h / 2, bandW, h, bandCol)
        if status ~= "active" then
            draw.SimpleText(string.upper(PL.Statuses[status] or status), "GRMPlate_Small",
                -w / 2 + bandW * 0.5, h / 2 - 9, Color(220, 60, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()

    --[[ Автовписывание строки: считаем её размер шрифтом и подбираем
         масштаб так, чтобы номер занимал поле знака и по ширине, и по
         высоте, с полями. Никаких ручных «масштабов» больше не нужно. ]]
    surface.SetFont("GRMPlate_Number")
    local tw, th = surface.GetTextSize(text)
    local room = w - bandW
    local fit = math.min((room * 0.88) / math.max(1, tw), (h * 0.72) / math.max(1, th))
    fit = math.Clamp(fit, 0.05, 8)

    cam.Start3D2D(pos, ang, scale * fit)
        draw.SimpleText(text, "GRMPlate_Number", (bandW * 0.5) / fit, 0, textCol,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
