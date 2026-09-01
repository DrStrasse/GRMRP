--[[--------------------------------------------------------------------
    grm_keypad — cl_init.lua (Клиентская 3D2D-панель, Код 104)

    Геометрия — только через shared-хелперы (KeypadScreenOrigin/Angles).
    Код 105 (находка 122): угол плоскости строится напрямую из базиса
    модели одним AngleEx (пара RotateAroundAxis давала ролл 180°), масштаб
    — по реальной морде модели через OBBMins/OBBMaxs (KeypadScreenScale),
    без жёстких констант. Кнопка под прицелом подсвечивается и жмётся по E; нажатие
    подсвечивается вспышкой у ВСЕХ клиентов (net GRM_KeypadPress),
    цвет шапки плавно лерпается, курсор поля ввода мигает.
----------------------------------------------------------------------]]

include("shared.lua")

surface.CreateFont("Keypad_Screen", { font = "Roboto", size = 22, weight = 800, extended = true })
surface.CreateFont("Keypad_Btn",    { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("Keypad_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })

net.Receive("GRM_KeypadPress", function()
    local ent = net.ReadEntity()
    local idx = net.ReadUInt(8)
    if not IsValid(ent) then return end
    ent.__btnFlash = ent.__btnFlash or {}
    ent.__btnFlash[idx] = CurTime() + 0.25
end)

local function sendPin(ent, pin, isSet)
    if not IsValid(ent) then return end
    net.Start("GRM_KeypadPIN")
        net.WriteEntity(ent)
        net.WriteString(tostring(pin or ""))
        net.WriteBool(isSet == true)
    net.SendToServer()
end

function ENT:OpenPinMenu()
    if IsValid(self._pinFrame) then self._pinFrame:MakePopup() return end
    local ent, typed = self, ""
    local f = vgui.Create("DFrame")
    self._pinFrame = f
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_keypad_pin", f) end
    f:SetTitle("")
    f:SetSize(280, 420)
    f:Center()
    f:MakePopup()
    f:ShowCloseButton(false)
    f.Paint = function(_, pw, ph)
        draw.RoundedBox(8, 0, 0, pw, ph, Color(20, 24, 32, 250))
        draw.RoundedBoxEx(8, 0, 0, pw, 36, Color(28, 34, 46), true, true, false, false)
        draw.SimpleText("Кодовый замок", "Keypad_Screen", 14, 18, Color(240, 245, 250), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local close = vgui.Create("DButton", f)
    close:SetText("X") close:SetPos(244, 6) close:SetSize(28, 24) close:SetTextColor(color_white)
    close.Paint = function(s, pw, ph)
        draw.RoundedBox(4, 0, 0, pw, ph, s:IsHovered() and Color(220, 75, 70) or Color(45, 52, 68))
    end
    close.DoClick = function() f:Close() end

    local disp = vgui.Create("DLabel", f)
    disp:SetPos(16, 48) disp:SetSize(248, 32)
    disp:SetFont("Keypad_Screen") disp:SetTextColor(Color(100, 200, 255))
    disp:SetContentAlignment(5)
    local function refresh()
        disp:SetText(typed == "" and "Введите PIN" or string.rep("*", #typed))
    end
    refresh()

    local layout = {
        { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "C", "0", "OK" },
    }
    for r, row in ipairs(layout) do
        for c, label in ipairs(row) do
            local b = vgui.Create("DButton", f)
            b:SetPos(20 + (c - 1) * 80, 92 + (r - 1) * 52)
            b:SetSize(72, 46)
            b:SetText(label) b:SetFont("Keypad_Btn") b:SetTextColor(color_white)
            local col = Color(38, 46, 62)
            if label == "OK" then col = Color(40, 140, 80)
            elseif label == "C" then col = Color(160, 60, 60) end
            b.Paint = function(s, pw, ph)
                local cc = col
                if s:IsHovered() then cc = Color(math.min(255, cc.r + 30), math.min(255, cc.g + 30), math.min(255, cc.b + 30)) end
                draw.RoundedBox(6, 0, 0, pw, ph, cc)
            end
            b.DoClick = function()
                if not IsValid(ent) then f:Close() return end
                if label == "C" then typed = "" refresh() return end
                if label == "OK" then sendPin(ent, typed, false) f:Close() return end
                if #typed < 10 then typed = typed .. label refresh() end
            end
        end
    end

    local lp = LocalPlayer()
    local canSet = IsValid(lp) and ((ent.IsKeypadOwner and ent:IsKeypadOwner(lp)) or lp:IsSuperAdmin())
    if canSet then
        local entry = vgui.Create("DTextEntry", f)
        entry:SetPos(20, 308) entry:SetSize(152, 28)
        entry:SetPlaceholderText("Новый PIN")
        entry:SetNumeric(true)
        local save = vgui.Create("DButton", f)
        save:SetPos(178, 308) save:SetSize(82, 28)
        save:SetText("Задать") save:SetTextColor(color_white)
        save.Paint = function(s, pw, ph)
            draw.RoundedBox(6, 0, 0, pw, ph, s:IsHovered() and Color(80, 170, 255) or Color(70, 150, 240))
        end
        save.DoClick = function()
            if not IsValid(ent) then f:Close() return end
            sendPin(ent, entry:GetValue(), true)
        end
        local hint = vgui.Create("DLabel", f)
        hint:SetPos(20, 342) hint:SetSize(240, 36)
        hint:SetFont("Keypad_Small") hint:SetTextColor(Color(160, 170, 185))
        hint:SetWrap(true)
        hint:SetText("Владелец: задайте PIN здесь, если панель инструмента его не записала.")
        f:SetTall(390)
    else
        f:SetTall(310)
    end
end

hook.Add("KeyPress", "GRM_Keypad_OpenPinUI", function(ply, key)
    if key ~= IN_USE or ply ~= LocalPlayer() then return end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_keypad") then return end
    if ply:GetShootPos():DistToSqr(ent:GetPos()) > (130 * 130) then return end
    if ent.KeypadButtonAt and ent:KeypadButtonAt(tr.HitPos) then return end
    if ent.OpenPinMenu then ent:OpenPinMenu() end
end)

local function lerpColor(cur, target, rate)
    local f = math.min(1, rate)
    cur.r = cur.r + (target.r - cur.r) * f
    cur.g = cur.g + (target.g - cur.g) * f
    cur.b = cur.b + (target.b - cur.b) * f
    cur.a = cur.a + (target.a - cur.a) * f
    return cur
end

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local dist = ply:GetPos():DistToSqr(self:GetPos())
    if dist > 350 * 350 then return end

    -- какая кнопка под прицелом (подсветка + намёк, что жать E)
    local hoverIdx = nil
    if dist < 140 * 140 then
        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) and tr.Entity == self then
            hoverIdx = self:KeypadButtonAt(tr.HitPos)
        end
    end

    local S = self:KeypadScreenScale()
    local W = self.ScreenW or 144
    local H = self.ScreenH or 220

    cam.Start3D2D(self:KeypadScreenOrigin(), self:KeypadScreenAngles(), S)
        -- фон панели
        draw.RoundedBox(6, 0, 0, W, H, Color(16, 20, 28, 250))
        surface.SetDrawColor(45, 55, 75)
        surface.DrawOutlinedRect(0, 0, W, H, 2)

        -- шапка (плавный переход цвета статуса)
        local status = self:GetStatus()
        local mode = self:GetMode()
        local headerTarget = Color(28, 36, 48)
        local statusText = "ВВЕДИТЕ ПИН"
        local statusColor = Color(220, 230, 245)

        if status == 1 then
            headerTarget = Color(30, 140, 70)
            statusText = "ОТКРЫТО"
            statusColor = Color(255, 255, 255)
        elseif status == 2 then
            headerTarget = Color(180, 50, 50)
            statusText = "ОТКАЗАНО"
            statusColor = Color(255, 255, 255)
        elseif mode == 1 then
            statusText = "ФРАКЦИЯ"
            statusColor = Color(80, 180, 255)
        elseif mode == 2 then
            statusText = tostring(self:GetCost()) .. " GRM"
            statusColor = Color(235, 180, 60)
        elseif hoverIdx == nil and dist < 140 * 140 then
            statusText = "E — ВВОД PIN"
        end

        self.__hdrCol = self.__hdrCol or Color(headerTarget.r, headerTarget.g, headerTarget.b)
        lerpColor(self.__hdrCol, headerTarget, FrameTime() * 10)
        draw.RoundedBoxEx(4, 4, 4, W - 8, 32, self.__hdrCol, true, true, false, false)
        draw.SimpleText(statusText, "Keypad_Screen", W / 2, 20, statusColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- поле ввода с мигающим курсором
        local typed = self:GetDisplayText()
        if status == 0 and mode == 0 then
            if typed == "" then typed = "_ _ _ _"
            elseif math.floor(CurTime() * 2) % 2 == 0 then typed = typed .. "▪" end
        end
        draw.RoundedBox(4, 4, 40, W - 8, 30, Color(24, 30, 42))
        draw.SimpleText(typed, "Keypad_Screen", W / 2, 55, Color(100, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- кнопки: подсветка под прицелом + вспышка нажатия
        local now = CurTime()
        for i, b in ipairs(self.Buttons or {}) do
            local btnCol = Color(38, 46, 62)
            if b.text == "OK" then btnCol = Color(40, 140, 80)
            elseif b.text == "CLR" then btnCol = Color(160, 60, 60) end

            if hoverIdx == i then
                btnCol = Color(math.min(255, btnCol.r + 45), math.min(255, btnCol.g + 45), math.min(255, btnCol.b + 45))
            end
            if self.__btnFlash and (self.__btnFlash[i] or 0) > now then
                btnCol = Color(240, 240, 250)
            end

            draw.RoundedBox(4, b.x, b.y, b.w, b.h, btnCol)
            draw.SimpleText(b.text, "Keypad_Btn", b.x + b.w / 2, b.y + b.h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
