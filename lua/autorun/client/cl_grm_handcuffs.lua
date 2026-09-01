--[[--------------------------------------------------------------------
    GRM Handcuffs - Client HUD/Render
--------------------------------------------------------------------]]

if not CLIENT then return end

include("autorun/sh_grm_handcuffs_config.lua")

GRM = GRM or {}
GRM.Handcuffs = GRM.Handcuffs or {}

local mats = {
    rope = Material("cable/rope"),
    gradL = Material("vgui/gradient-l"),
    gradR = Material("vgui/gradient-r"),
}

surface.CreateFont("GRM_Cuffs_Title", {
    font = "Roboto",
    size = 24,
    weight = 800,
    extended = true,
})

surface.CreateFont("GRM_Cuffs_Text", {
    font = "Roboto",
    size = 16,
    weight = 600,
    extended = true,
})

local function isCuffed(ply)
    return IsValid(ply) and ply:GetNWBool("GRM_Cuffed", false)
end

local function cfg()
    return GRM and GRM.Handcuffs and GRM.Handcuffs.Config or {}
end

local function localHasCuffsOut()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end

    local wep = lp:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() == (cfg().WeaponClass or "grm_handcuffs")
end

local function keyName(bind, fallback)
    local b = input.LookupBinding(bind or "")
    if b and b ~= "" then return string.upper(b) end
    return fallback or bind or "?"
end

local function drawHintLine(text, x, y, color)
    draw.SimpleTextOutlined(text, "GRM_Cuffs_Text", x, y, color or Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 230))
end

local function isVehicleLike(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end

    local class = string.lower(ent:GetClass() or "")
    if string.find(class, "sim_fphys", 1, true) then return true end
    if string.find(class, "lvs", 1, true) then return true end
    if string.find(class, "gmod_sent_vehicle", 1, true) then return true end

    for _, child in ipairs(ent:GetChildren()) do
        if IsValid(child) and child:IsVehicle() then return true end
    end

    return false
end

local function hasDraggedCaptive()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end

    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and isCuffed(ply) and ply:GetNWEntity("GRM_CuffDragger") == lp then
            return true
        end
    end

    return false
end

local function hasCuffedPassengerNear(ent)
    if not IsValid(ent) then return false end

    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and isCuffed(ply) and ply:InVehicle() then
            local veh = ply:GetVehicle()
            if IsValid(veh) then
                if veh == ent or veh:GetParent() == ent or ent:GetParent() == veh:GetParent() then return true end
                if veh:GetPos():DistToSqr(ent:GetPos()) <= 360 * 360 then return true end
            end
        end
    end

    return false
end

local function handPos(ply, right)
    if not IsValid(ply) then return Vector(0, 0, 0) end

    local boneName = right and "ValveBiped.Bip01_R_Hand" or "ValveBiped.Bip01_L_Hand"
    local bone = ply:LookupBone(boneName)

    if bone then
        local pos = ply:GetBonePosition(bone)
        if pos then return pos end
    end

    return ply:GetPos() + Vector(0, 0, 45)
end

hook.Add("HUDPaint", "GRM_Handcuffs_HUD", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end

    local sw, sh = ScrW(), ScrH()

    if isCuffed(lp) then
        local y = sh - 170

        draw.RoundedBox(8, sw / 2 - 190, y, 380, 76, Color(10, 10, 14, 210))
        draw.SimpleText("ВЫ В НАРУЧНИКАХ", "GRM_Cuffs_Title", sw / 2, y + 18, Color(255, 190, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local extra = "Самостоятельно освободиться нельзя"
        if lp:GetNWBool("GRM_CuffGagged", false) then extra = extra .. " | Кляп" end
        if lp:GetNWBool("GRM_CuffBlindfolded", false) then extra = extra .. " | Повязка" end

        draw.SimpleText(extra, "GRM_Cuffs_Text", sw / 2, y + 50, Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Сам задержанный не получает подсказок освобождения/ведения,
        -- потому что самостоятельно развязаться нельзя.
        return
    end

    -- Общий кэш трейса (GRM.Perf): один GetEyeTrace на кадр на все HUD-модули.
    local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp, 0.05) or lp:GetEyeTrace()
    if not tr then return end
    local target = tr.Entity
    if not IsValid(target) or target == lp then return end

    local hasCuffsOut = localHasCuffsOut()
    local cx = sw / 2
    local cy = sh / 2 + 34

    -- Подсказки для транспорта: обычный транспорт, simfphys, LVS.
    if hasCuffsOut and isVehicleLike(target) and lp:GetPos():DistToSqr(target:GetPos()) <= 220 * 220 then
        local y = cy
        local shown = false

        if hasDraggedCaptive() then
            drawHintLine("E — посадить задержанного на пассажирское место", cx, y, Color(200, 230, 255))
            drawHintLine("Водительское место не используется", cx, y + 22, Color(220, 220, 220))
            y = y + 48
            shown = true
        end

        if hasCuffedPassengerNear(target) then
            drawHintLine("E — вытащить задержанного из транспорта", cx, y, Color(255, 235, 170))
            shown = true
        end

        if shown then return end
    end

    if not target:IsPlayer() then return end

    local distOK = lp:GetPos():DistToSqr(target:GetPos()) <= 150 * 150
    if not distOK then return end

    local targetCuffed = isCuffed(target)

    -- Подсказки для оружия наручников.
    if hasCuffsOut then
        if targetCuffed then
            local dragging = target:GetNWEntity("GRM_CuffDragger") == lp
            drawHintLine("ЛКМ — снять наручники", cx, cy, Color(255, 235, 170))
            drawHintLine(dragging and "ПКМ — отпустить задержанного" or "ПКМ — взять и вести", cx, cy + 22, Color(200, 230, 255))
            drawHintLine("R — кляп | ALT + R — повязка на глаза", cx, cy + 44, Color(220, 220, 220))
        else
            drawHintLine("ЛКМ — надеть наручники", cx, cy, Color(255, 235, 170))
            drawHintLine("Подойдите ближе и удерживайте прицел на игроке", cx, cy + 22, Color(220, 220, 220))
        end
    end

    -- Подсказка снятия через E, если игрок смотрит на задержанного.
    if targetCuffed then
        local progress = math.Clamp(target:GetNWFloat("GRM_CuffReleaseProgress", 0) / 100, 0, 1)
        local useKey = keyName("+use", "E")
        local y = hasCuffsOut and (cy + 78) or cy

        drawHintLine("Удерживайте " .. useKey .. ", чтобы снять наручники", cx, y, Color(255, 255, 255))

        draw.RoundedBox(4, cx - 105, y + 20, 210, 18, Color(0, 0, 0, 200))
        draw.RoundedBox(4, cx - 103, y + 22, 206 * progress, 14, Color(255, 190, 70, 240))
    end
end)

local wasBlind = false
hook.Add("RenderScreenspaceEffects", "GRM_Handcuffs_Blindfold", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    if lp:GetNWBool("GRM_CuffBlindfolded", false) then
        wasBlind = true
        DrawColorModify({
            ["$pp_colour_addr"] = 0,
            ["$pp_colour_addg"] = 0,
            ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = -1.4,
            ["$pp_colour_contrast"] = 0,
            ["$pp_colour_colour"] = 0,
            ["$pp_colour_mulr"] = 0,
            ["$pp_colour_mulg"] = 0,
            ["$pp_colour_mulb"] = 0,
        })
    elseif wasBlind then
        wasBlind = false
        DrawColorModify({
            ["$pp_colour_brightness"] = 0,
            ["$pp_colour_contrast"] = 1,
            ["$pp_colour_colour"] = 1,
        })
    end
end)

hook.Add("PostDrawOpaqueRenderables", "GRM_Handcuffs_DrawDragRope", function()
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if isCuffed(ply) then
            local dragger = ply:GetNWEntity("GRM_CuffDragger")
            if IsValid(dragger) then
                local p1 = handPos(dragger, true)
                local p2 = handPos(ply, true)
                local light = render.GetLightColor(p2) * 255
                local col = Color(math.max(light.x, 80), math.max(light.y, 80), math.max(light.z, 80), 255)

                render.SetMaterial(mats.rope)
                render.StartBeam(2)
                    render.AddBeam(p1, 2, 0, col)
                    render.AddBeam(p2, 2, 1, col)
                render.EndBeam()
            end
        end
    end
end)

hook.Add("PostPlayerDraw", "GRM_Handcuffs_DrawGagBlind", function(ply)
    if not IsValid(ply) then return end
    if not ply:GetNWBool("GRM_CuffGagged", false) and not ply:GetNWBool("GRM_CuffBlindfolded", false) then return end

    local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
    if not bone then return end

    local headPos, headAng = ply:GetBonePosition(bone)
    if not headPos or not headAng then return end

    local col = Color(120, 120, 120, 255)
    render.SetMaterial(mats.rope)

    local function ring(offsetForward)
        local center = headPos + headAng:Forward() * offsetForward + headAng:Right() * 2
        local radius = 4
        local segs = 12

        render.StartBeam(segs + 1)
        for i = 0, segs do
            local a = math.pi * 2 * (i / segs)
            local pos = center + headAng:Right() * math.cos(a) * radius + headAng:Up() * math.sin(a) * radius
            render.AddBeam(pos, 2, i / segs, col)
        end
        render.EndBeam()
    end

    if ply:GetNWBool("GRM_CuffGagged", false) then ring(2) end
    if ply:GetNWBool("GRM_CuffBlindfolded", false) then ring(-2) end
end)

-- Дополнительная визуальная фиксация рук: рисуем короткую стяжку за спиной.
-- Даже если конкретная модель плохо принимает bone-pose, игрок визуально выглядит связанным сзади.
hook.Add("PostPlayerDraw", "GRM_Handcuffs_DrawBehindBackCuffs", function(ply)
    if not IsValid(ply) or not isCuffed(ply) then return end

    local pos = ply:GetPos() + Vector(0, 0, 45) - ply:GetForward() * 9
    local right = ply:GetRight()
    local p1 = pos + right * 4
    local p2 = pos - right * 4

    render.SetMaterial(mats.rope)
    render.StartBeam(2)
        render.AddBeam(p1, 3, 0, Color(90, 90, 90, 255))
        render.AddBeam(p2, 3, 1, Color(90, 90, 90, 255))
    render.EndBeam()
end)


-- ============================================================
-- ПОЗА РУК ЗА СПИНОЙ ДЛЯ ЗАДЕРЖАННЫХ
-- ============================================================

-- Новый режим позы v3: снова используем ManipulateBoneAngles, но без SetBoneMatrix.
-- BuildBonePositions на разных моделях давал руку вверх/в сторону, потому что ломал bone hierarchy.
-- Здесь поза задаётся локальными углами костей, плюс есть несколько пресетов для быстрой подстройки.

local posePresets = {
    -- DEFAULT: мягкое заведение предплечий за поясницу, плечи почти не трогаем.
    [1] = {
        ["ValveBiped.Bip01_R_UpperArm"] = Angle(8, 0, -28),
        ["ValveBiped.Bip01_R_Forearm"]  = Angle(0, -92, 0),
        ["ValveBiped.Bip01_R_Hand"]     = Angle(0, 0, 18),

        ["ValveBiped.Bip01_L_UpperArm"] = Angle(-8, 0, 28),
        ["ValveBiped.Bip01_L_Forearm"]  = Angle(0, 92, 0),
        ["ValveBiped.Bip01_L_Hand"]     = Angle(0, 0, -18),
    },

    -- Сильнее заводит руки назад.
    [2] = {
        ["ValveBiped.Bip01_R_UpperArm"] = Angle(12, 0, -38),
        ["ValveBiped.Bip01_R_Forearm"]  = Angle(0, -112, 0),
        ["ValveBiped.Bip01_R_Hand"]     = Angle(0, 0, 24),

        ["ValveBiped.Bip01_L_UpperArm"] = Angle(-12, 0, 38),
        ["ValveBiped.Bip01_L_Forearm"]  = Angle(0, 112, 0),
        ["ValveBiped.Bip01_L_Hand"]     = Angle(0, 0, -24),
    },

    -- Альтернативные оси: если на вашей модели пресет 1/2 выглядит зеркально или криво.
    [3] = {
        ["ValveBiped.Bip01_R_UpperArm"] = Angle(0, 18, -28),
        ["ValveBiped.Bip01_R_Forearm"]  = Angle(-70, 0, 0),
        ["ValveBiped.Bip01_R_Hand"]     = Angle(0, 0, 18),

        ["ValveBiped.Bip01_L_UpperArm"] = Angle(0, -18, 28),
        ["ValveBiped.Bip01_L_Forearm"]  = Angle(70, 0, 0),
        ["ValveBiped.Bip01_L_Hand"]     = Angle(0, 0, -18),
    },

    -- Ещё один вариант под модели, где Pitch/Yaw костей поменяны местами.
    [4] = {
        ["ValveBiped.Bip01_R_UpperArm"] = Angle(0, 0, -30),
        ["ValveBiped.Bip01_R_Forearm"]  = Angle(0, 0, -95),
        ["ValveBiped.Bip01_R_Hand"]     = Angle(0, 20, 0),

        ["ValveBiped.Bip01_L_UpperArm"] = Angle(0, 0, 30),
        ["ValveBiped.Bip01_L_Forearm"]  = Angle(0, 0, 95),
        ["ValveBiped.Bip01_L_Hand"]     = Angle(0, -20, 0),
    },
}

-- Если конкретная модель всё ещё выглядит криво, можно в клиентской консоли сменить пресет:
-- grm_cuffs_pose_preset 1
-- grm_cuffs_pose_preset 2
-- grm_cuffs_pose_preset 3
-- grm_cuffs_pose_preset 4
-- После выбора пресет применяется сразу.
CreateClientConVar("grm_cuffs_pose_preset", "1", true, false, "GRM cuffs behind-back pose preset", 1, 4)

local posedPlayers = {}
local allPoseBones = {
    "ValveBiped.Bip01_R_UpperArm",
    "ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_R_Hand",
    "ValveBiped.Bip01_L_UpperArm",
    "ValveBiped.Bip01_L_Forearm",
    "ValveBiped.Bip01_L_Hand",
}

local function resetCuffPose(ply)
    if not IsValid(ply) then return end

    for _, boneName in ipairs(allPoseBones) do
        local bone = ply:LookupBone(boneName)
        if bone then
            ply:ManipulateBoneAngles(bone, Angle(0, 0, 0))
            ply:ManipulateBonePosition(bone, Vector(0, 0, 0))
            ply:ManipulateBoneScale(bone, Vector(1, 1, 1))
        end
    end

    if ply.InvalidateBoneCache then ply:InvalidateBoneCache() end
    if ply.SetupBones then ply:SetupBones() end
    posedPlayers[ply] = nil
end

-- Behind-back bone manipulation is intentionally disabled: player models use
-- incompatible bone axes. Сбрасываем возможный след старой версии один раз,
-- вместо LookupBone/ManipulateBone для каждого игрока в каждом кадре.
timer.Simple(0, function()
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if IsValid(ply) then resetCuffPose(ply) end end
end)

hook.Add("EntityNetworkedVarChanged", "GRM_Handcuffs_ResetPoseOnUncuff", function(ent, name, _, value)
    if IsValid(ent) and name == "GRM_Cuffed" and value == false then
        timer.Simple(0, function() if IsValid(ent) then resetCuffPose(ent) end end)
    end
end)

hook.Add("EntityRemoved", "GRM_Handcuffs_ResetPoseOnRemove", function(ent)
    if posedPlayers[ent] then
        resetCuffPose(ent)
    end
end)

concommand.Add("grm_cuffs_pose_reset", function()
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        resetCuffPose(ply)
    end
end)

print("[GRM Handcuffs] Client loaded.")
