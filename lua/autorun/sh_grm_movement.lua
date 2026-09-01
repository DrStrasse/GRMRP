-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Movement System v1.3 — Полное управление звуком дыхания
    - Используется CreateSound для точного контроля (Play/Stop)
    - Звук корректно останавливается при восстановлении стамины до 100%
    - Полоса выносливости в центре снизу
--------------------------------------------------------------------]]

if SERVER then
    util.AddNetworkString("GRM_Stamina_Sync")
end

GRM = GRM or {}
GRM.Movement = GRM.Movement or {}

-- ============================================================
-- КОНФИГУРАЦИЯ
-- ============================================================
GRM.Movement.Config = {
    WalkSpeed       = 160,
    RunSpeed        = 220,
    ExhaustedSpeed  = 80,
    StaminaMax      = 100,
    StaminaMaxMin   = 80,
    StaminaMaxCap   = 160,
    StaminaTrain    = 0.085,
    StaminaDecay    = 0.002,
    StaminaDrain    = 9,
    StaminaJumpCost = 10,
    StaminaRegen    = 11,
    -- Сидя в транспорте человек отдыхает: восстановление идёт и чуть быстрее
    -- обычного (заказ владельца 22.08 — «в машине выносливость не растёт»).
    StaminaRegenSeated = 12,
    JumpCooldown    = 0.5,
    BhopLimit       = 20,
    StaminaWarningThreshold = 30,
}

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    local playerData = {}
    local FIT_FILE = "grm_fitness.json"
    local fitness = {}

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    local function loadFitness()
        if not file.Exists(FIT_FILE, "DATA") then return end
        local t = jsonT(file.Read(FIT_FILE, "DATA") or "")
        if istable(t) then fitness = t end
    end

    local function saveFitness()
        if GRM.Perf and GRM.Perf.Coalesce then
            GRM.Perf.Coalesce("fitness.save", 4, function()
                local ok, txt = pcall(util.TableToJSON, fitness, true)
                if ok and txt then file.Write(FIT_FILE, txt) end
            end)
        else
            local ok, txt = pcall(util.TableToJSON, fitness, true)
            if ok and txt then file.Write(FIT_FILE, txt) end
        end
    end
    loadFitness()

    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана:
    -- возвращал SteamID64 БЕЗ слота; данные только в памяти, миграция не нужна.
    local charKey = GRM.CharKey

    local function clampMax(v)
        local cfg = GRM.Movement.Config
        return math.Clamp(tonumber(v) or cfg.StaminaMax, cfg.StaminaMaxMin or 80, cfg.StaminaMaxCap or 160)
    end

    -- Форвард-декларация: TrainFitness вызывает syncStamina до её
    -- построчного объявления (ловит sim_forward_locals).
    local syncStamina

    local function getPlayerData(ply)
        local sid = charKey(ply)
        if not playerData[sid] then
            local rec = istable(fitness[sid]) and fitness[sid] or {}
            local mx = clampMax(rec.max or GRM.Movement.Config.StaminaMax)
            playerData[sid] = {
                stamina = mx,
                max = mx,
                lastJump = 0,
                lastTrain = tonumber(rec.lastTrain) or 0,
            }
        end
        return playerData[sid]
    end

    local function persistMax(ply, data)
        local sid = charKey(ply)
        fitness[sid] = { max = data.max, lastTrain = data.lastTrain or os.time() }
        saveFitness()
        ply:SetNWFloat("GRM_StaminaMax", data.max)
    end

    --- Прибавка к потолку выносливости (отжимания, бег и т.п.).
    function GRM.Movement.TrainFitness(ply, gain, cost)
        if not IsValid(ply) then return false end
        local data = getPlayerData(ply)
        local cfg = GRM.Movement.Config
        cost = tonumber(cost) or 0
        gain = tonumber(gain) or 0
        if cost > 0 then
            if data.stamina < cost then return false end
            data.stamina = math.max(0, data.stamina - cost)
        end
        if gain > 0 then
            data.max = clampMax(data.max + gain)
            data.lastTrain = os.time()
            persistMax(ply, data)
        end
        syncStamina(ply, true)
        return true
    end

    function GRM.Movement.GetFitness(ply)
        if not IsValid(ply) then return 0, 0 end
        local data = getPlayerData(ply)
        return data.stamina, data.max
    end

    function syncStamina(ply, force)
        if not IsValid(ply) then return end
        local data = getPlayerData(ply);local now=CurTime()
        if not force and (data.nextSync or 0)>now then return end
        if not force and data.lastSynced~=nil and math.abs(data.lastSynced-data.stamina)<.001 then return end
        data.nextSync=now+.25;data.lastSynced=data.stamina
        net.Start("GRM_Stamina_Sync")
        net.WriteFloat(data.stamina)
        net.WriteFloat(data.max or GRM.Movement.Config.StaminaMax)
        net.Send(ply)
    end

    --[[ Раньше тик стамины крутился 10 раз в секунду и обходил всех игроков,
         хотя сама стамина уходит клиенту не чаще 4 раз в секунду. Считаем по
         РЕАЛЬНОЙ дельте времени: интервал можно менять, скорости трат и
         восстановления от этого не «поплывут». ]]
    local STAMINA_TICK = 0.25
    local staminaLast = CurTime()
    timer.Create("GRM_StaminaTick", STAMINA_TICK, 0, function()
        local now = CurTime()
        local dt = math.Clamp(now - staminaLast, 0.01, 1)
        staminaLast = now
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local data = getPlayerData(ply)
                local cfg = GRM.Movement.Config

                data.max = clampMax(data.max or cfg.StaminaMax)
                if ply:InVehicle() then
                    --[[ В машине игрок раньше выпадал из тика целиком — и
                         выносливость не восстанавливалась вообще, хотя он
                         сидит. Теперь сидение считается отдыхом. ]]
                    data.stamina = math.min(data.max,
                        data.stamina + (cfg.StaminaRegenSeated or cfg.StaminaRegen) * dt)
                else
                    local isRunning = ply:KeyDown(IN_SPEED) and ply:GetVelocity():Length2D() > 50
                    local isOnGround = ply:IsOnGround()
                    local isProne = (GRM.Prone and GRM.Prone.Is) and GRM.Prone.Is(ply)
                        or ply:GetNWBool("GRM_Prone", false)

                    -- лёжа стамина не тратится бегом и не качается отжиманиями
                    if isRunning and isOnGround and not isProne then
                        data.stamina = math.max(0, data.stamina - cfg.StaminaDrain * dt)
                        if data.stamina > 12 then
                            local before = data.max
                            data.max = clampMax(data.max + (cfg.StaminaTrain or 0.085) * dt)
                            data.lastTrain = os.time()
                            if math.abs(data.max - before) > 0.2 then persistMax(ply, data) end
                        end
                    elseif isOnGround then
                        data.stamina = math.min(data.max, data.stamina + cfg.StaminaRegen * dt)
                        if (os.time() - (data.lastTrain or 0)) > 6 * 3600 then
                            data.max = clampMax(data.max - (cfg.StaminaDecay or 0.004) * dt)
                        end
                    end
                end

                syncStamina(ply)
            end
        end
    end)

    hook.Add("Move", "GRM_Movement_Move", function(ply, mv)
        if not IsValid(ply) then return end
        -- В транспорте стамина не влияет на скорость
        if ply:InVehicle() then return end
        --[[ PRONE: пока игрок лежит (Prone Mod/system_prone), его скоростью
             управляет сам мод через SetupMove (по умолчанию 50). Наш
             ограничитель зажимал её до Walk/Run (160/220) и ломал ползание.
             Поэтому лёжа стамина не трогает скорость. ]]
        if GRM.Prone and GRM.Prone.Is and GRM.Prone.Is(ply) then return end

        local data = getPlayerData(ply)
        local isOnGround = ply:IsOnGround()
        local isRunning = ply:KeyDown(IN_SPEED)
        local vel = mv:GetVelocity()
        local speed = vel:Length2D()

        local maxSpeed
        if isOnGround and isRunning and data.stamina > 0 then
            maxSpeed = GRM.Movement.Config.RunSpeed
        elseif isOnGround and not isRunning then
            maxSpeed = GRM.Movement.Config.WalkSpeed
        else
            maxSpeed = GRM.Movement.Config.WalkSpeed * (1 + GRM.Movement.Config.BhopLimit / 100)
        end

        if isOnGround and data.stamina <= 0 then
            maxSpeed = math.min(maxSpeed, GRM.Movement.Config.ExhaustedSpeed)
        end

        if speed > maxSpeed then
            local ratio = maxSpeed / speed
            mv:SetVelocity(Vector(vel.x * ratio, vel.y * ratio, vel.z))
        end

        if ply:KeyPressed(IN_JUMP) and isOnGround then
            if CurTime() - data.lastJump < GRM.Movement.Config.JumpCooldown then
                mv:SetVelocity(Vector(vel.x, vel.y, 0))
                return
            end
            if data.stamina >= GRM.Movement.Config.StaminaJumpCost then
                data.stamina = data.stamina - GRM.Movement.Config.StaminaJumpCost
                data.lastJump = CurTime()
            else
                mv:SetVelocity(Vector(vel.x, vel.y, 0))
            end
        end
    end)

    hook.Add("PlayerInitialSpawn", "GRM_Movement_Init", function(ply)
        timer.Simple(0.5, function()
            if IsValid(ply) then
                local d = getPlayerData(ply)
                ply:SetNWFloat("GRM_StaminaMax", d.max)
                syncStamina(ply, true)
            end
        end)
    end)

    hook.Add("GRM_CharacterChanged", "GRM_Movement_SwapFit", function(ply)
        if not IsValid(ply) then return end
        playerData[charKey(ply)] = nil
        local d = getPlayerData(ply)
        persistMax(ply, d)
        syncStamina(ply, true)
    end)

    grmBootStart("GRM_Movement_ClearData", "normal", function()
        playerData = {}
    end)

    print("[GRM] Movement System (сервер) загружена")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    CreateClientConVar("grm_cl_staminahud", "1", true, false) -- F4 → Настройки
    GRM.LocalStamina = GRM.LocalStamina or GRM.Movement.Config.StaminaMax
    GRM.LocalStaminaMax = GRM.LocalStaminaMax or GRM.Movement.Config.StaminaMax

    local breathSound = nil
    local isBreathing = false

    -- Создаём звуковой объект при загрузке
    grmBootStart("GRM_Movement_InitSound", "late", function()
        breathSound = CreateSound(LocalPlayer(), "player/breathe1.wav")
        if breathSound then
            breathSound:SetSoundLevel(70) -- громкость
        end
    end)

    -- При переподключении или смене карты пересоздаём звук
    hook.Add("PlayerInitialSpawn", "GRM_Movement_ReinitSound", function(ply)
        if ply ~= LocalPlayer() then return end
        if breathSound then
            breathSound:Stop()
            breathSound = nil
        end
        timer.Simple(0.5, function()
            if IsValid(LocalPlayer()) then
                breathSound = CreateSound(LocalPlayer(), "player/breathe1.wav")
                if breathSound then
                    breathSound:SetSoundLevel(70)
                end
            end
        end)
    end)

    -- Управление звуком усталости
    hook.Add("Think", "GRM_StaminaSound", function()
        if GRM.Perf and not GRM.Perf.Throttle("movement.breath.client",.1)then return end
        local stamina = GRM.LocalStamina or 0
        local maxStamina = GRM.LocalStaminaMax or GRM.Movement.Config.StaminaMax
        local threshold = maxStamina * (GRM.Movement.Config.StaminaWarningThreshold / 100)

        -- Звук должен играть: стамина > 0 и стамина <= порога (30%)
        local shouldPlay = stamina > 0 and stamina <= threshold
        local isPlaying = isBreathing

        if shouldPlay and not isPlaying then
            -- Начинаем играть
            if breathSound then
                breathSound:Play()
                isBreathing = true
            end
        elseif not shouldPlay and isPlaying then
            -- Останавливаем звук
            if breathSound then
                breathSound:Stop()
                isBreathing = false
            end
        end

        -- Дополнительно: если стамина == 100%, гарантированно останавливаем
        if stamina >= maxStamina and isPlaying then
            if breathSound then
                breathSound:Stop()
                isBreathing = false
            end
        end
    end)

    -- Очистка при выходе или закрытии
    hook.Add("ShutDown", "GRM_Movement_CleanupSound", function()
        if breathSound then
            breathSound:Stop()
            breathSound = nil
        end
    end)

    -- Синхронизация стамины с сервера
    net.Receive("GRM_Stamina_Sync", function()
        GRM.LocalStamina = net.ReadFloat()
        GRM.LocalStaminaMax = net.ReadFloat()
        hook.Run("GRM_StaminaUpdated", GRM.LocalStamina)
    end)

    --[[ Выносливость и дыхание живут в ОБЩЕЙ панели состояния
         (GRM.HUD.RegisterBar) — заказ владельца 22.08. Своей полосы по
         центру экрана больше нет: раньше она висела отдельно от здоровья и
         брони и налезала на вес с сытостью. Если общего HUD почему-то нет
         (старая сборка), рисуем по-старому. ]]
    local function staminaColor(frac)
        if frac < 0.3 then return Color(130, 45, 200) end
        if frac < 0.6 then return Color(155, 70, 230) end
        return Color(175, 90, 255)
    end

    -- Дыхание: под водой считаем запас воздуха. Движок его не отдаёт,
    -- поэтому ведём свой отсчёт от момента погружения (по умолчанию 12 с,
    -- как стандартное утопление) — полоса нужна как предупреждение.
    local breathLeft, breathMax = 12, 12
    hook.Add("Think", "GRM_Movement_Breath", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end
        local dt = FrameTime()
        if ply:WaterLevel() >= 3 then
            breathLeft = math.max(0, breathLeft - dt)
        else
            breathLeft = math.min(breathMax, breathLeft + dt * 3)
        end
    end)

    if GRM.HUD and GRM.HUD.RegisterBar then
        GRM.HUD.RegisterBar("stamina", {
            label = "ВЫНОСЛИВОСТЬ", order = 30,
            Get = function()
                local cv = GetConVar("grm_cl_staminahud")
                if cv and cv:GetInt() == 0 then return nil end
                local stamina = GRM.LocalStamina or 0
                local maxStamina = GRM.LocalStaminaMax or GRM.Movement.Config.StaminaMax
                local frac = math.Clamp(stamina / math.max(1, maxStamina), 0, 1)
                return stamina, maxStamina, math.floor(stamina) .. " / " .. math.floor(maxStamina), staminaColor(frac)
            end,
        })

        GRM.HUD.RegisterBar("breath", {
            label = "ДЫХАНИЕ", order = 40,
            Get = function()
                -- полоса появляется только под водой и пока идёт восстановление
                if breathLeft >= breathMax - 0.05 then return nil end
                local frac = breathLeft / breathMax
                return breathLeft, breathMax, math.ceil(breathLeft) .. " с",
                    frac < 0.35 and Color(220, 80, 80) or Color(90, 175, 255)
            end,
        })
    else
        hook.Add("HUDPaint", "GRM_Movement_StaminaHUD", function()
            -- HUD мог загрузиться позже movement: тогда fallback обязан
            -- отключиться, иначе выносливость рисуется второй полосой.
            if GRM.HUD and GRM.HUD.RegisterBar then return end
            local cv = GetConVar("grm_cl_staminahud")
            if cv and cv:GetInt() == 0 then return end
            local ply = LocalPlayer()
            if not IsValid(ply) or not ply:Alive() then return end
            local stamina = GRM.LocalStamina or 0
            local maxStamina = GRM.LocalStaminaMax or GRM.Movement.Config.StaminaMax
            local sw, sh = ScrW(), ScrH()
            local barW, barH = 250, 14
            local x, y = (sw - barW) / 2, sh - 66
            draw.RoundedBox(4, x, y, barW, barH, Color(30, 32, 40, 200))
            local frac = math.Clamp(stamina / maxStamina, 0, 1)
            draw.RoundedBox(4, x, y, barW * frac, barH, staminaColor(frac))
            draw.SimpleText("Выносливость", "GRM_HUD_Label", x + 10, y - 16, Color(160, 165, 175, 255), TEXT_ALIGN_LEFT)
            draw.SimpleText(math.floor(stamina) .. "%", "GRM_HUD_Value", x + barW - 10, y + barH / 2,
                Color(255, 255, 255, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end)
    end

    hook.Remove("HUDPaint", "GRM_Movement_StatusHUD")

    print("[GRM] Movement System (клиент) загружена")
end
