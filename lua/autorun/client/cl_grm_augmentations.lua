--[[
    GRM Augmentations Client
    HUD overlay и визуальные эффекты аугментаций
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.Augmentations = GRM.Augmentations or {}
local AUG = GRM.Augmentations

-- GRM UI Fonts для HUD
surface.CreateFont("GRMAugHUD_Status", { font = "Roboto", size = 14, weight = 600, extended = true })
surface.CreateFont("GRMAugHUD_Info", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMAugHUD_Warning", { font = "Roboto", size = 16, weight = 800, extended = true })
surface.CreateFont("GRMAugHUD_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

-- Локальные переменные
local infraredEnabled = false
local hudEnabled = false
local nightVisionEnabled = false
local scanlineOffset = 0

-- Получение данных с сервера
net.Receive("GRM_Augmentation_Update", function()
    local augType = net.ReadString()
    local enabled = net.ReadBool()

    if augType == "InfraredVision" or augType == "infrared" then
        infraredEnabled = enabled
    elseif augType == "nightvision" or augType == "NightVision" then
        nightVisionEnabled = enabled
    elseif augType == "HUDOverlay" then
        hudEnabled = enabled
    elseif augType == "NightVision" then
        nightVisionEnabled = enabled
    end
end)

-- Инфракрасное зрение
hook.Add("RenderScreenspaceEffects", "GRM_Augmentations_Infrared", function()
    if not infraredEnabled and not LocalPlayer():GetNWBool("GRM_Accessory_artificial_eye", false) then return end

    -- Тепловизор эффект
    local tab = {
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -0.1,
        ["$pp_colour_contrast"] = 1.5,
        ["$pp_colour_colour"] = 0.3,
        ["$pp_colour_mulr"] = 0.3,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    }

    DrawColorModify(tab)
end)

-- Ночное зрение
hook.Add("RenderScreenspaceEffects", "GRM_Augmentations_NightVision", function()
    if not nightVisionEnabled and not LocalPlayer():GetNWBool("GRM_Accessory_night_vision", false) then return end

    local tab = {
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0.1,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = 0.2,
        ["$pp_colour_contrast"] = 1.3,
        ["$pp_colour_colour"] = 0.5,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0.3,
        ["$pp_colour_mulb"] = 0
    }

    DrawColorModify(tab)
end)

-- Подсветка игроков в инфракрасном режиме
hook.Add("PrePlayerDraw", "GRM_Augmentations_InfraredGlow", function(ply)
    if not infraredEnabled then return end
    if ply == LocalPlayer() then return end

    -- Тепловое свечение
    render.SetColorModulation(1, 0.3, 0.3)
    render.SuppressEngineLighting(true)
end)

hook.Add("PostPlayerDraw", "GRM_Augmentations_InfraredGlowEnd", function(ply)
    if not infraredEnabled then return end
    if ply == LocalPlayer() then return end

    render.SetColorModulation(1, 1, 1)
    render.SuppressEngineLighting(false)
end)

-- Регенерация (клиентская визуализация)
hook.Add("Think", "GRM_Augmentations_Regeneration", function()
    if GRM.Perf and not GRM.Perf.Throttle("augment.regen.client",.5)then return end;local ply=LocalPlayer();if not IsValid(ply)then return end
    local timerName="GRM_Regen_"..ply:SteamID64();local data=AUG.GetPlayerData(ply);local enabled=data and data.augmentations and data.augmentations.Regeneration
    if enabled and ply:Health()<ply:GetMaxHealth()then if not timer.Exists(timerName)then timer.Create(timerName,5,0,function()if not IsValid(ply)then timer.Remove(timerName)return end;if ply:Health()<ply:GetMaxHealth()then ply:SetHealth(math.min(ply:Health()+5,ply:GetMaxHealth()))else timer.Remove(timerName)end end)end
    elseif timer.Exists(timerName)then timer.Remove(timerName)end
end)

-- HUD Overlay (терминал перед лицом)
-- Кадровые краски HUD: константы загрузки файла (§6.1.8), «GRMAugHUD v2»
-- раньше собирал по семь Color() на каждый кадр.
local AUG_CYAN = Color(0, 255, 200, 200)
local AUG_WARN = Color(255, 100, 100, 255)
local AUG_IR = Color(255, 100, 100, 200)
local AUG_NIGHT = Color(100, 255, 100, 200)

hook.Add("HUDPaint", "GRM_Augmentations_HUD", function()
    if not hudEnabled then return end

    local scrW, scrH = ScrW(), ScrH()

    -- Обновление scanline анимации
    scanlineOffset = (scanlineOffset + 1) % 4

    -- Рамка HUD
    surface.SetDrawColor(0, 255, 200, 50)
    surface.DrawOutlinedRect(20, 20, scrW - 40, scrH - 40, 2)

    -- Углы
    local cornerSize = 30
    surface.SetDrawColor(0, 255, 200, 150)

    -- Верхний левый
    surface.DrawLine(20, 20, 20 + cornerSize, 20)
    surface.DrawLine(20, 20, 20, 20 + cornerSize)

    -- Верхний правый
    surface.DrawLine(scrW - 20, 20, scrW - 20 - cornerSize, 20)
    surface.DrawLine(scrW - 20, 20, scrW - 20, 20 + cornerSize)

    -- Нижний левый
    surface.DrawLine(20, scrH - 20, 20 + cornerSize, scrH - 20)
    surface.DrawLine(20, scrH - 20, 20, scrH - 20 - cornerSize)

    -- Нижний правый
    surface.DrawLine(scrW - 20, scrH - 20, scrW - 20 - cornerSize, scrH - 20)
    surface.DrawLine(scrW - 20, scrH - 20, scrW - 20, scrH - 20 - cornerSize)

    -- Scanlines
    surface.SetDrawColor(0, 255, 200, 20)
    for y = 20 + scanlineOffset, scrH - 20, 4 do
        surface.DrawLine(20, y, scrW - 20, y)
    end

    -- Статус система
    draw.SimpleText("GRM AUGMENTATION SYSTEM v2.0", "GRMAugHUD_Status", 30, 30, AUG_CYAN)
    draw.SimpleText("STATUS: ACTIVE", "GRMAugHUD_Status", 30, 50, AUG_CYAN)

    -- Системная информация
    local ply = LocalPlayer()
    if IsValid(ply) then
        draw.SimpleText("HP: " .. ply:Health() .. "/" .. ply:GetMaxHealth(), "GRMAugHUD_Info", 30, 80, AUG_CYAN)
        draw.SimpleText("ARMOR: " .. ply:Armor(), "GRMAugHUD_Info", 30, 100, AUG_CYAN)
    end

    -- Время
    draw.SimpleText(os.date("%H:%M:%S"), "GRMAugHUD_Info", scrW - 100, 30, AUG_CYAN)

    -- Предупреждения
    if ply:Health() < 30 then
        draw.SimpleText("WARNING: LOW HEALTH", "GRMAugHUD_Warning", scrW / 2, scrH - 100, AUG_WARN, TEXT_ALIGN_CENTER)
    end

    -- Индикатор инфракрасного режима
    if infraredEnabled then
        draw.SimpleText("INFRARED: ACTIVE", "GRMAugHUD_Small", scrW - 150, 50, AUG_IR)
    end

    -- Индикатор ночного зрения
    if nightVisionEnabled then
        draw.SimpleText("NIGHT VISION: ACTIVE", "GRMAugHUD_Small", scrW - 180, 70, AUG_NIGHT)
    end
end)

-- Звук работы аугментаций
local ambientSound = nil
hook.Add("Think", "GRM_Augmentations_Ambient", function()
    if GRM.Perf and not GRM.Perf.Throttle("augment.ambient.client",.25)then return end
    if not hudEnabled and not infraredEnabled and not nightVisionEnabled then
        if ambientSound then
            ambientSound:Stop()
            ambientSound = nil
        end
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    if not ambientSound then
        ambientSound = CreateSound(ply, "ambient/levels/citadel/field_loop1.wav")
        ambientSound:SetSoundLevel(0)
        ambientSound:Play()
    end
end)

-- Очистка при выходе
hook.Add("ShutDown", "GRM_Augmentations_Cleanup", function()
    if ambientSound then
        ambientSound:Stop()
    end
end)

print("[GRM Augmentations] Client v2.0 loaded")
