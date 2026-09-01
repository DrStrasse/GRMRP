--[[--------------------------------------------------------------------
    ds_lockpick — «Взломщик» (QTE-взлом дверей/кейпадов/сканеров, Код 174)

    Заказ владельца: вместо отмычки-монтировки — взломщик в виде бомбы
    (models/weapons/w_c4.mdl). Взламывает:
      • двери (prop_door_rotating/func_door — GRM.Doors),
      • FFD-двери и раздвижные двери (isFadingDoor/isSlidingDoor),
      • кейпады grm_keypad,
      • сканеры grm_scanner.
    Взлом НЕ мгновенный: QTE-мини-игра с прогресс-баром (5 пинов защёлки,
    ошибки, ускоряющаяся игла). Успех — доступ/открытие цели.
----------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Взломщик"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ: начать QTE-взлом двери, кейпада или сканера (зафиксируйте иглу в зелёной зоне ПРОБЕЛОМ/ЛКМ)"
SWEP.Category = "GRM"
SWEP.Spawnable = true
SWEP.AdminSpawnable = true
SWEP.DrawWeaponSelection = true
SWEP.ViewModel = "models/weapons/cstrike/c_c4.mdl"
SWEP.WorldModel = "models/weapons/w_c4.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local AIM_RANGE   = 120    -- дальность прицеливания на цель
local HACK_RANGE  = 190    -- серверная дистанция применения взлома
local MIN_HACK    = 2.0    -- минимальное время QTE (анти-чит: мгновенно не взломать)

SWEP.AimRange = AIM_RANGE
SWEP.HackRange = HACK_RANGE
SWEP.MinHackTime = MIN_HACK

if SERVER then
    util.AddNetworkString("GRM_Breaker_StartQTE")
    util.AddNetworkString("GRM_Breaker_FinishQTE")
end

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:Deploy()
    self:SetHoldType("slam")
    return true
end

-- Цель взлома под прицелом: кейпад, сканер, FFD/раздвижная дверь или обычная дверь
function SWEP:GetAimedTarget()
    local ply = self:GetOwner()
    if not IsValid(ply) then return nil end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * self.AimRange,
        filter = ply,
        mask = MASK_SHOT,
    })

    local ent = tr.Entity
    if IsValid(ent) then
        local cls = ent:GetClass()
        if cls == "grm_keypad" or cls == "grm_scanner" then
            return ent
        end
        if ent.isFadingDoor or ent.isSlidingDoor then
            return ent
        end
        if GRM and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(ent) then
            return ent
        end
        if IsValid(ent:GetParent()) then
            local par = ent:GetParent()
            local pcls = par:GetClass()
            if pcls == "grm_keypad" or pcls == "grm_scanner" then
                return par
            end
            if par.isFadingDoor or par.isSlidingDoor then
                return par
            end
            if GRM and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(par) then
                return par
            end
        end
    end
    return nil
end

function SWEP:PrimaryAttack()
    if CurTime() < (self._nextAction or 0) then return end
    self._nextAction = CurTime() + 0.8
    self:SetNextPrimaryFire(self._nextAction)

    local target = self:GetAimedTarget()
    local ply = self:GetOwner()
    if not IsValid(target) or not IsValid(ply) then return end

    -- клиент уже в мини-игре — повторный запуск не нужен
    if self.__qteActive then return end

    if SERVER then
        ply.__grmBreakerStart = CurTime()
        net.Start("GRM_Breaker_StartQTE")
            net.WriteEntity(target)
        net.Send(ply)
    end
end

function SWEP:SecondaryAttack()
    self:PrimaryAttack()
end

-- ============================================================
-- СЕРВЕРНАЯ ОБРАБОТКА РЕЗУЛЬТАТА QTE
-- ============================================================
if SERVER then
    -- применить успешный взлом к цели
    local function applyBreakerHack(ply, target)
        local cls = target:GetClass()

        if cls == "grm_keypad" then
            if target:IsKeypadLocked() then
                if GRM.Notify then
                    GRM.Notify(ply, "Кейпад уже открыт или занят.", 255, 200, 90)
                end
                return false
            end
            if target.ProcessGrant then target:ProcessGrant(ply) end
            if GRM.Notify then
                GRM.Notify(ply, "Кейпад успешно взломан! Доступ разрешён.", 100, 220, 100)
            end
            return true
        end

        if cls == "grm_scanner" then
            if target.ProcessGrant then target:ProcessGrant(ply, "ВЗЛОМ") end
            if GRM.Notify then
                GRM.Notify(ply, "Сканер успешно взломан! Доступ разрешён.", 100, 220, 100)
            end
            return true
        end

        if target.isFadingDoor or target.isSlidingDoor then
            if target.FadeActivate then target:FadeActivate() end
            ply:EmitSound("buttons/button14.wav", 75, 100)
            if GRM.Notify then
                GRM.Notify(ply, "Электроника двери успешно взломана!", 100, 220, 100)
            end
            return true
        end

        if GRM and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(target) then
            GRM.Doors.LockDoor(target, false, { noAutoLock = true })
            target:Fire("Open", "", 0.1)

            local partner = GRM.Doors.GetPartnerDoor and GRM.Doors.GetPartnerDoor(target)
            if IsValid(partner) then partner:Fire("Open", "", 0.1) end

            ply:EmitSound("buttons/button14.wav", 75, 100)
            hook.Run("GRM_OnDoorLockpicked", ply, target)

            if GRM.Notify then
                GRM.Notify(ply, "Замок двери успешно взломан!", 100, 220, 100)
            end
            return true
        end

        return false
    end

    net.Receive("GRM_Breaker_FinishQTE", function(_, ply)
        if not IsValid(ply) then return end
        local target = net.ReadEntity()
        local success = net.ReadBool()

        if not IsValid(target) then return end
        if ply:GetPos():DistToSqr(target:GetPos()) > HACK_RANGE * HACK_RANGE then return end

        -- взломщик должен быть в руках
        local wep = ply:GetActiveWeapon()
        if not (IsValid(wep) and wep:GetClass() == "ds_lockpick") then return end

        -- анти-спам и анти-чит: успех требует минимального времени QTE
        local now = CurTime()
        if (ply.__grmBreakerNext or 0) > now then return end
        ply.__grmBreakerNext = now + 1.0

        if success then
            if now - (ply.__grmBreakerStart or 0) < MIN_HACK then
                if GRM.Notify then
                    GRM.Notify(ply, "Взлом сорван: сигнатура не подтверждена.", 255, 100, 100)
                end
                return
            end
            applyBreakerHack(ply, target)
            hook.Run("GRM_OnDeviceHacked", ply, target)
        else
            ply:EmitSound("buttons/button10.wav", 75, 90)
            if GRM.Notify then
                GRM.Notify(ply, "Взлом не удался! Попробуйте снова.", 255, 100, 100)
            end
        end
    end)

    -- метка начала QTE (для минимального времени взлома)
    hook.Add("PlayerSwitchWeapon", "GRM_Breaker_CancelQTE", function(ply, old, new)
        if not IsValid(ply) then return end
        ply.__grmBreakerStart = nil
    end)
end

-- ============================================================
-- КЛИЕНТСКАЯ QTE МИНИ-ИГРА ВЗЛОМА (прогресс-бар)
-- ============================================================
if CLIENT then
    surface.CreateFont("QTE_Title", { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("QTE_Sub",   { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("QTE_Big",   { font = "Roboto", size = 26, weight = 800, extended = true })

    local function targetLabel(target)
        if not IsValid(target) then return "ЦЕЛЬ ПОТЕРЯНА" end
        local cls = target:GetClass()
        if cls == "grm_keypad" then return "ВЗЛОМ КЕЙПАДА"
        elseif cls == "grm_scanner" then return "ВЗЛОМ СКАНЕРА"
        elseif target.isFadingDoor or target.isSlidingDoor then return "ВЗЛОМ ЭЛЕКТРОНИКИ ДВЕРИ"
        else return "ВЗЛОМ ЗАМКА ДВЕРИ" end
    end

    -- Находка 176b: глобального LerpColor в GMod НЕТ (его добавляют только
    -- сторонние аддоны) — на чистом клиенте QTE падала с nil. Своя версия.
    local function lerpColor(t, a, b)
        t = math.Clamp(tonumber(t) or 0, 0, 1)
        return Color(
            math.floor((a.r or 0) + ((b.r or 0) - (a.r or 0)) * t + 0.5),
            math.floor((a.g or 0) + ((b.g or 0) - (a.g or 0)) * t + 0.5),
            math.floor((a.b or 0) + ((b.b or 0) - (a.b or 0)) * t + 0.5),
            math.floor((a.a or 255) + ((b.a or 255) - (a.a or 255)) * t + 0.5)
        )
    end

    local activeFrame = nil -- активное окно QTE (индексировать функцию нельзя — GLua!)

    local function startBreakerQTE(target)
        if not IsValid(target) then return end
        -- уже идёт мини-игра — не плодим окна
        if IsValid(activeFrame) then return end

        local pinCurrent = 1
        local maxPins = 5
        local mistakes = 0
        local maxMistakes = 3
        local active = true

        local targetMin = math.random(15, 60)
        local targetWidth = 22
        local speed = 1.6

        local wep = LocalPlayer():GetActiveWeapon()
        if IsValid(wep) then wep.__qteActive = true end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(500, 320)
        frame:Center()
        frame:MakePopup()
        frame:ShowCloseButton(false)
        activeFrame = frame

        local title = targetLabel(target)

        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(16, 20, 28, 252))
            draw.RoundedBoxEx(8, 0, 0, w, 42, Color(28, 34, 46), true, true, false, false)
            draw.SimpleText("ВЗЛОМЩИК — QTE МИНИ-ИГРА", "QTE_Title", 14, 12, Color(240, 245, 250), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(title, "QTE_Sub", w - 14, 21, Color(255, 190, 90), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            -- === ПРОГРЕСС-БАР ВЗЛОМА ===
            local pbX, pbY, pbW, pbH = 20, 58, 460, 20
            draw.RoundedBox(5, pbX, pbY, pbW, pbH, Color(24, 30, 42))
            local t = CurTime() * speed
            local posPct = (math.sin(t) + 1) / 2
            -- заполнение: завершённые пины + доля текущего пина (по приближению к зоне)
            local partial = math.Clamp((posPct * 100 - (targetMin - 8)) / (targetWidth + 16), 0, 1)
            local fillPct = ((pinCurrent - 1) + partial) / maxPins
            local fillCol = lerpColor(fillPct, Color(60, 200, 110), Color(255, 190, 60))
            draw.RoundedBox(4, pbX + 2, pbY + 2, (pbW - 4) * fillPct, pbH - 4, fillCol)
            -- деления по пинам
            surface.SetDrawColor(16, 20, 28, 160)
            for i = 1, maxPins - 1 do
                local sx = pbX + (pbW * i / maxPins)
                surface.DrawRect(sx - 1, pbY + 2, 2, pbH - 4)
            end
            draw.SimpleText(string.format("ПРОГРЕСС ВЗЛОМА: %d%%", math.floor(fillPct * 100 + 0.5)), "QTE_Sub", w / 2, pbY + 10, Color(235, 240, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- === СТРОКА ПИНОВ/ОШИБОК ===
            draw.SimpleText("Пин: " .. pinCurrent .. " / " .. maxPins, "QTE_Sub", 22, 94, Color(80, 180, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Ошибки: " .. mistakes .. " / " .. maxMistakes, "QTE_Sub", w - 22, 94, mistakes > 0 and Color(255, 90, 90) or Color(160, 170, 185), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            -- === ИГЛА И ЗЕЛЁНАЯ ЗОНА ===
            local barX, barY = 20, 118
            local barW, barH = 460, 42
            draw.RoundedBox(6, barX, barY, barW, barH, Color(28, 34, 46))

            local zoneX = barX + (barW * (targetMin / 100))
            local zoneW = barW * (targetWidth / 100)
            draw.RoundedBox(4, zoneX, barY + 3, zoneW, barH - 6, Color(60, 200, 110, 220))
            surface.SetDrawColor(80, 230, 130)
            surface.DrawOutlinedRect(zoneX, barY + 3, zoneW, barH - 6, 2)

            local pinX = barX + (barW * posPct)
            surface.SetDrawColor(255, 220, 80)
            surface.DrawRect(pinX - 2, barY - 5, 5, barH + 10)

            -- === ПОДСКАЗКИ ===
            draw.SimpleText("ПРОБЕЛ / ЛКМ — зафиксировать иглу в зелёной зоне", "QTE_Sub", w / 2, 190, Color(200, 210, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("ESC — отменить взлом", "QTE_Sub", w / 2, 226, Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local function endQTE(success)
            if not active then return end
            active = false
            activeFrame = nil
            frame:Close()
            local wep = LocalPlayer():GetActiveWeapon()
            if IsValid(wep) then wep.__qteActive = nil end
            net.Start("GRM_Breaker_FinishQTE")
                net.WriteEntity(target)
                net.WriteBool(success)
            net.SendToServer()
        end

        local function cancelQTE()
            if not active then return end
            active = false
            activeFrame = nil
            frame:Close()
            local wep = LocalPlayer():GetActiveWeapon()
            if IsValid(wep) then wep.__qteActive = nil end
        end

        local function checkPin()
            if not active then return end

            local t = CurTime() * speed
            local posPct = ((math.sin(t) + 1) / 2) * 100

            if posPct >= targetMin and posPct <= (targetMin + targetWidth) then
                surface.PlaySound("buttons/button14.wav")
                pinCurrent = pinCurrent + 1

                if pinCurrent > maxPins then
                    surface.PlaySound("weapons/c4/c4_disarm.wav")
                    endQTE(true)
                    return
                end

                targetMin = math.random(15, 68)
                targetWidth = math.max(10, targetWidth - 2)
                speed = speed + 0.55
            else
                surface.PlaySound("buttons/button10.wav")
                mistakes = mistakes + 1

                if mistakes >= maxMistakes then
                    endQTE(false)
                end
            end
        end

        frame.OnKeyCodePressed = function(_, key)
            if key == KEY_SPACE or key == KEY_ENTER or key == MOUSE_LEFT then
                checkPin()
            elseif key == KEY_ESCAPE then
                cancelQTE()
            end
        end

        -- отмена при потере цели/смерти/смене оружия/выходе
        frame.Think = function(self)
            if not active then return end
            local lp = LocalPlayer()
            local ok = IsValid(target) and IsValid(lp) and lp:Alive() and lp:Health() > 0
            if ok then
                local cur = lp:GetActiveWeapon()
                ok = IsValid(cur) and cur:GetClass() == "ds_lockpick"
            end
            if not ok then cancelQTE() end
        end

        local bgBtn = vgui.Create("DButton", frame)
        bgBtn:SetSize(500, 320)
        bgBtn:SetText("")
        bgBtn:SetPaintBackground(false)
        bgBtn.DoClick = function()
            checkPin()
        end
    end

    net.Receive("GRM_Breaker_StartQTE", function()
        local ent = net.ReadEntity()
        if not IsValid(ent) then return end
        -- отметка старта на клиенте для сервера не нужна; сервер сам ставит метку
        startBreakerQTE(ent)
    end)
end
