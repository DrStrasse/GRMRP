--[[--------------------------------------------------------------------
    grm_scanner — cl_init.lua (клиентская 3D2D-панель сканера, Код 107)
    Панель БЕЗ кнопок ввода: статус, подсказка, имя и фракция
    просканированного. Геометрия — shared-хелперы ScannerScreen* (базис
    AngleEx + OBB-масштаб, доказано на кейпаде, находка 122). Статусы:
    0 idle / 1 допущен (зелёный) / 2 отказ (красный) / 3 сканирование
    (синяя бегущая полоса).
----------------------------------------------------------------------]]

include("shared.lua")

surface.CreateFont("Scanner_Title", { font = "Roboto", size = 17, weight = 800, extended = true })
surface.CreateFont("Scanner_Big",   { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("Scanner_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local function lerpColor(cur, target, rate)
    local f = math.min(1, rate)
    cur.r = cur.r + (target.r - cur.r) * f
    cur.g = cur.g + (target.g - cur.g) * f
    cur.b = cur.b + (target.b - cur.b) * f
    cur.a = cur.a + (target.a - cur.a) * f
    return cur
end

local function drawMultiline(text, font, cx, y, col, maxW)
    -- простое оборачивание подписи белого списка по словам
    surface.SetFont(font)
    maxW = tonumber(maxW) or 134
    local line, lines = "", {}
    for word in string.gmatch(tostring(text or ""), "%S+") do
        local probe = line == "" and word or (line .. " " .. word)
        if select(1, surface.GetTextSize(probe)) > maxW and line ~= "" then
            lines[#lines + 1] = line
            line = word
            if #lines >= 3 then break end
        else
            line = probe
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    for i = 1, math.min(#lines, 4) do
        draw.SimpleText(lines[i], font, cx, y + (i - 1) * 12, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return math.min(#lines, 4) * 12
end

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local dist = ply:GetPos():DistToSqr(self:GetPos())
    if dist > 350 * 350 then return end

    local S = self:ScannerScreenScale()
    local W = self.ScreenW or 150
    local H = self.ScreenH or 118

    local status = self:GetStatus()

    cam.Start3D2D(self:ScannerScreenOrigin(), self:ScannerScreenAngles(), S)
        -- фон панели
        draw.RoundedBox(6, 0, 0, W, H, Color(14, 18, 26, 250))
        surface.SetDrawColor(45, 60, 85)
        surface.DrawOutlinedRect(0, 0, W, H, 2)

        -- шапка со статусом (плавный переход цвета)
        local headerTarget = Color(24, 44, 66)  -- idle — стальной синий
        local statusText = "СКАНЕР ДОСТУПА"
        local statusColor = Color(120, 190, 255)
        if status == 1 then
            headerTarget = Color(30, 140, 70)
            statusText = "ДОПУЩЁН"
            statusColor = Color(255, 255, 255)
        elseif status == 2 then
            headerTarget = Color(180, 50, 50)
            statusText = "ОТКАЗАНО"
            statusColor = Color(255, 255, 255)
        elseif status == 3 then
            headerTarget = Color(40, 80, 140)
            statusText = "СКАНИРОВАНИЕ"
            statusColor = Color(255, 255, 255)
        end
        self.__hdrCol = self.__hdrCol or Color(headerTarget.r, headerTarget.g, headerTarget.b)
        lerpColor(self.__hdrCol, headerTarget, FrameTime() * 10)
        draw.RoundedBoxEx(4, 4, 4, W - 8, 24, self.__hdrCol, true, true, false, false)
        draw.SimpleText(statusText, "Scanner_Title", W / 2, 16, statusColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local name = tostring(self:GetScannedName() or "")
        local fac = tostring(self:GetScannedFac() or "")

        if status == 3 then
            -- бегущая полоса сканирования
            if name ~= "" then
                draw.SimpleText(name, "Scanner_Big", W / 2, 46, Color(235, 240, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            local t = CurTime()
            local sx = 12 + (W - 24 - 26) * (0.5 + 0.5 * math.sin(t * 6))
            draw.RoundedBox(3, 12, 62, W - 24, 10, Color(24, 38, 56))
            draw.RoundedBox(3, sx, 62, 26, 10, Color(90, 170, 255))
            local dots = string.rep(".", 1 + math.floor(t * 3) % 3)
            draw.SimpleText("анализ подписи" .. dots, "Scanner_Small", W / 2, 86, Color(140, 170, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif status == 1 then
            draw.SimpleText(name, "Scanner_Big", W / 2, 50, Color(230, 245, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if fac ~= "" then
                draw.SimpleText("фракция: " .. fac, "Scanner_Small", W / 2, 72, Color(140, 230, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText("доступ подтверждён", "Scanner_Small", W / 2, 92, Color(120, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif status == 2 then
            draw.SimpleText(name ~= "" and name or "сигнатура не определена", "Scanner_Big", W / 2, 50, Color(245, 225, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("фракционный доступ не найден", "Scanner_Small", W / 2, 74, Color(230, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            -- idle: призыв и белый список фракций мелким текстом
            draw.SimpleText("Подойдите и нажмите [E]", "Scanner_Big", W / 2, 48, Color(225, 235, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("сканирование подписи фракции", "Scanner_Small", W / 2, 66, Color(140, 165, 195), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            local white = string.Trim(tostring(self:GetFaction() or ""))
            if white ~= "" then
                draw.SimpleText("допуск:", "Scanner_Small", W / 2, 88, Color(90, 130, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                drawMultiline(white, "Scanner_Small", W / 2, 101, Color(120, 180, 240), W - 16)
            end
        end
    cam.End3D2D()
end
