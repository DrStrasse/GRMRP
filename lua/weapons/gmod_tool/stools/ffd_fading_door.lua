--[[--------------------------------------------------------------------
    FFD Fading Door — Toolgun Module (Код 69)
    Надёжная переработанная система Fading Door с поддержкой Numpad,
    автоматического закрытия, инверсии и прямой интеграции с Кейпадами.

    ЛКМ: Создать / Обновить Fading Door на пропе
    ПКМ: Снять статус Fading Door с пропа
    R: Скопировать настройки с пропа
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.ffd_fading_door.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["key"] = "1"
TOOL.ClientConVar["reversed"] = "0"
TOOL.ClientConVar["toggle"] = "1"
TOOL.ClientConVar["autoclose"] = "0"
TOOL.ClientConVar["time"] = "5"

if CLIENT then
    language.Add("tool.ffd_fading_door.name", "GRM Исчезающая дверь")
    language.Add("tool.ffd_fading_door.desc", "Превращает любой проп в исчезающую дверь с нумпадом и таймером")
    language.Add("tool.ffd_fading_door.0", "ЛКМ: Применить Fading Door | ПКМ: Снять с пропа | R: Скопировать настройки")
end

-- ============================================================
-- СЕРВЕРНАЯ ЛОГИКА FADING DOOR
-- ============================================================
if SERVER then
    local function applyFadeState(ent, active)
        if not IsValid(ent) or not ent.isFadingDoor then return end

        local reverse = ent.FFD_Reversed == true
        local shouldFade = active
        if reverse then shouldFade = not active end

        if shouldFade then
            -- Скрытие и выключение коллизии
            ent:SetNotSolid(true)
            ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
            ent:SetColor(Color(255, 255, 255, 40))
            ent:DrawShadow(false)

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:EnableCollisions(false) end

            ent.FFD_IsFaded = true
            ent:SetNWBool("FFD_Faded", true)
        else
            -- Проявление и возобновление коллизии
            ent:SetNotSolid(false)
            ent:SetRenderMode(RENDERMODE_NORMAL)
            ent:SetColor(Color(255, 255, 255, 255))
            ent:DrawShadow(true)

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:EnableCollisions(true) end

            ent.FFD_IsFaded = false
            ent:SetNWBool("FFD_Faded", false)
        end
    end

local fadeOff
    local function fadeOn(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if ent.FFD_IsActive then return end

        ent.FFD_IsActive = true
        applyFadeState(ent, true)
        ent:EmitSound("doors/door1_move.wav", 65, 110, 0.6)

        -- Автозакрытие по таймеру
        if ent.FFD_AutoClose and tonumber(ent.FFD_CloseTime) and ent.FFD_CloseTime > 0 then
            timer.Create("FFD_AutoClose_" .. ent:EntIndex(), ent.FFD_CloseTime, 1, function()
                if IsValid(ent) and ent.isFadingDoor and ent.FFD_IsActive then
                    fadeOff(ply, ent)
                end
            end)
        end
    end

    fadeOff = function(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if not ent.FFD_IsActive then return end

        timer.Remove("FFD_AutoClose_" .. ent:EntIndex())
        ent.FFD_IsActive = false
        applyFadeState(ent, false)
        ent:EmitSound("doors/door_latch1.wav", 65, 100, 0.6)
    end

    local function fadeToggle(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if ent.FFD_IsActive then
            fadeOff(ply, ent)
        else
            fadeOn(ply, ent)
        end
    end

    numpad.Register("FFD_Fade_On", function(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if ent.FFD_Toggle then
            fadeToggle(ply, ent)
        else
            fadeOn(ply, ent)
        end
    end)

    numpad.Register("FFD_Fade_Off", function(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if not ent.FFD_Toggle then
            fadeOff(ply, ent)
        end
    end)

    -- ядро: применить настройки fading door (используется и тулганом, и
    -- перм-восстановлением Кода 105). skipDupe — без записи в duplicator.
    local function coreMakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, closeTime, skipDupe)
        if not IsValid(ent) then return false end

        -- Очистка старых нумпад-импульсов
        if ent.isFadingDoor and ent.FFD_NumDown then
            numpad.Remove(ent.FFD_NumDown)
            numpad.Remove(ent.FFD_NumUp)
        end

        ent.isFadingDoor = true
        ent.FFD_Reversed = reversed == true or reversed == 1
        ent.FFD_Toggle = toggle == true or toggle == 1
        ent.FFD_AutoClose = autoclose == true or autoclose == 1
        ent.FFD_CloseTime = math.max(0.5, tonumber(closeTime) or 5)
        ent.FFD_Key = key
        ent.FFD_OwnerSID64 = IsValid(ply) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or "") or tostring(ent.FFD_OwnerSID64 or "")
        -- Код 108: клиентская метка «это FFD-дверь» — подсветка цели в FFD Link
        ent:SetNWBool("FFD_IsDoor", true)

        -- Регистрация нумпад связи. Без живого плеера (перм-восстановление
        -- Кода 105 с офлайн-владельцем) бинд пропускаем — внутри
        -- numpad.OnDown движок дёргает ply:ConCommand и роняется на NULL;
        -- дверь всё равно остаётся рабочей через кейпад/взломщик.
        if IsValid(ply) then
            ent.FFD_NumDown = numpad.OnDown(ply, key, "FFD_Fade_On", ent)
            ent.FFD_NumUp = numpad.OnUp(ply, key, "FFD_Fade_Off", ent)
        end

        -- Публичные API методы для связки с Кейпадом и Отмычкой
        ent.FadeActivate = function() fadeOn(ply, ent) end
        ent.FadeDeactivate = function() fadeOff(ply, ent) end
        ent.FadeToggle = function() fadeToggle(ply, ent) end

        -- Устанавливаем начальное состояние
        ent.FFD_IsActive = false
        applyFadeState(ent, false)

        if not skipDupe then
            duplicator.StoreEntityModifier(ent, "FFD_FadingDoor", {
                key = key,
                reversed = reversed,
                toggle = toggle,
                autoclose = autoclose,
                time = closeTime,
            })
        end

        return true
    end

    function TOOL:MakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, closeTime)
        return coreMakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, closeTime, false)
    end

    duplicator.RegisterEntityModifier("FFD_FadingDoor", function(ply, ent, data)
        coreMakeFadingDoor(ply, ent, data.key, data.reversed, data.toggle, data.autoclose, data.time, true)
    end)

    -- ============================================================
    -- Код 105 (находка 122): админский ПЕРМ FFD-двери. Дверь — обычный
    -- prop_physics с флагами isFadingDoor; /permadd по такому пропу
    -- пишет ещё и конфиг двери (rec.data.ffd), после рестарта проп
    -- встаёт на место и СРАЗУ работает как fading door.
    -- ============================================================
    GRM = GRM or {}
    GRM.FFD_MakeFadingDoor = function(ply, ent, key, reversed, toggle, autoclose, closeTime)
        return coreMakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, closeTime, true)
    end
    GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
    GRM.PermData.Extract = GRM.PermData.Extract or {}
    GRM.PermData.Apply = GRM.PermData.Apply or {}
    GRM.PermData.Extract["prop_physics"] = function(ent)
        -- Находка 173: раздвижная дверь (сдвиг) — сохраняем свой конфиг
        if ent.isSlidingDoor and ent.Sliding then
            local s = ent.Sliding
            return {
                sliding = {
                    direction = tostring(s.direction or "left"),
                    distance = tonumber(s.distance) or 100,
                    speed = tonumber(s.speed) or 120,
                    smooth = tonumber(s.smooth) or 1,
                    toggle = s.toggle == true,
                    autoclose = s.autoclose == true,
                    closeTime = tonumber(s.closeTime) or 5,
                    owner = tostring(s.owner or ""),
                    soundOpen = tostring(s.soundOpen or ""),
                    soundClose = tostring(s.soundClose or ""),
                    soundMove = tostring(s.soundMove or ""),
                },
            }
        end
        if not ent.isFadingDoor then return nil end
        return {
            ffd = {
                key = tonumber(ent.FFD_Key) or 1,
                reversed = ent.FFD_Reversed == true,
                toggle = ent.FFD_Toggle == true,
                autoclose = ent.FFD_AutoClose == true,
                time = tonumber(ent.FFD_CloseTime) or 5,
                owner = tostring(ent.FFD_OwnerSID64 or ""),
            },
        }
    end
    GRM.PermData.Apply["prop_physics"] = function(ent, t)
        if not istable(t) then return end
        -- Находка 173: раздвижная дверь восстанавливается со сдвигом
        if istable(t.sliding) then
            local d = t.sliding
            local ownerPly = nil
            local want = tostring(d.owner or "")
            if want ~= "" then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == want then ownerPly = p break end
                end
            end
            if GRM.SlidingDoor and GRM.SlidingDoor.Apply then
                GRM.SlidingDoor.Apply(ownerPly, ent, {
                    direction = d.direction, distance = d.distance,
                    speed = d.speed, smooth = d.smooth,
                    toggle = d.toggle, autoclose = d.autoclose, closeTime = d.closeTime,
                    soundOpen = d.soundOpen, soundClose = d.soundClose, soundMove = d.soundMove,
                })
            end
            return
        end
        if not (istable(t) and istable(t.ffd)) then return end
        local d = t.ffd
        local ownerPly = nil
        local want = tostring(d.owner or "")
        if want ~= "" then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == want then ownerPly = p break end
            end
        end
        coreMakeFadingDoor(ownerPly, ent, tonumber(d.key) or 1, d.reversed, d.toggle, d.autoclose, tonumber(d.time) or 5, true)
        ent.FFD_OwnerSID64 = want
    end
end

function TOOL:LeftClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local key = self:GetClientNumber("key", 1)
    local reversed = self:GetClientNumber("reversed", 0) == 1
    local toggle = self:GetClientNumber("toggle", 1) == 1
    local autoclose = self:GetClientNumber("autoclose", 0) == 1
    local time = self:GetClientNumber("time", 5)

    self:MakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, time)

    if GRM and GRM.Notify then
        GRM.Notify(ply, "FFD Fading Door успешно настроен!", 100, 220, 100)
    end

    return true
end

function TOOL:RightClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or not ent.isFadingDoor then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()

    timer.Remove("FFD_AutoClose_" .. ent:EntIndex())
    if ent.FFD_NumDown then numpad.Remove(ent.FFD_NumDown) end
    if ent.FFD_NumUp then numpad.Remove(ent.FFD_NumUp) end

    ent.isFadingDoor = nil
    ent.FFD_IsActive = nil
    ent.FFD_IsFaded = nil
    ent:SetNWBool("FFD_IsDoor", false) -- Код 108: метка для FFD Link

    -- Код 108: сама дверь перестала быть дверью — вычищаем её из связей
    -- всех кейпадов/сканеров (иначе «мёртвые» записи ждали бы prune)
    local unlinked = 0
    if GRM and GRM.FFDLink and GRM.FFDLink.RemoveFromAll then
        unlinked = GRM.FFDLink.RemoveFromAll(ent)
    end

    ent:SetNotSolid(false)
    ent:SetRenderMode(RENDERMODE_NORMAL)
    ent:SetColor(Color(255, 255, 255, 255))

    duplicator.ClearEntityModifier(ent, "FFD_FadingDoor")

    if GRM and GRM.Notify then
        local extra = (unlinked > 0) and (" Отвязана от %d контроллер(ов)."):format(unlinked) or ""
        GRM.Notify(ply, "Статус Fading Door снят с объекта." .. extra, 235, 180, 60)
    end

    return true
end

function TOOL:Reload(trace)
    local ent = trace.Entity
    if not IsValid(ent) or not ent.isFadingDoor then return false end

    if SERVER then
        local ply = self:GetOwner()
        ply:ConCommand("ffd_fading_door_key " .. tostring(ent.FFD_Key or 1))
        ply:ConCommand("ffd_fading_door_reversed " .. (ent.FFD_Reversed and "1" or "0"))
        ply:ConCommand("ffd_fading_door_toggle " .. (ent.FFD_Toggle and "1" or "0"))
        ply:ConCommand("ffd_fading_door_autoclose " .. (ent.FFD_AutoClose and "1" or "0"))
        ply:ConCommand("ffd_fading_door_time " .. tostring(ent.FFD_CloseTime or 5))

        if GRM and GRM.Notify then
            GRM.Notify(ply, "Настройки Fading Door скопированы!", 100, 220, 255)
        end
    end

    return true
end

-- ============================================================
-- VGUI ПАНЕЛЬ НАСТРОЙКИ В МЕНЮ ИНСТРУМЕНТОВ
-- ============================================================
function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", { Description = "Создание исчезающей двери FFD Fading Door с нумпадом и гибокй настройкой." })

    panel:AddControl("Numpad", { Label = "Клавиша отпирания (Numpad):", Command = "ffd_fading_door_key" })

    panel:AddControl("Checkbox", { Label = "Режим переключателя (Toggle)", Command = "ffd_fading_door_toggle" })
    panel:AddControl("Checkbox", { Label = "Инверсия (Сначала открыто, нажатие закрывает)", Command = "ffd_fading_door_reversed" })
    panel:AddControl("Checkbox", { Label = "Автоматическое закрытие", Command = "ffd_fading_door_autoclose" })

    panel:AddControl("Slider", { Label = "Время задержки авто-закрытия (сек):", Command = "ffd_fading_door_time", Type = "Float", Min = 0.5, Max = 30 })
end
