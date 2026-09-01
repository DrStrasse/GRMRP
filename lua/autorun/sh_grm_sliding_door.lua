--[[--------------------------------------------------------------------
    GRM Sliding Door (находка 173) — раздвижные двери из пропов

    Инструмент grm_sliding_door: ЛКМ по prop_physics → проп становится
    раздвижной дверью: плавно смещается на заданное число юнитов в
    выбранном направлении (влево/вправо/вперёд/назад/вверх) с настройкой
    скорости и плавности (ease in/out).

    СОВМЕСТИМОСТЬ С FFD:
      • проп получает isSlidingDoor=true и методы FadeActivate/
        FadeDeactivate/FadeToggle — те же, что у FFD Fading Door, поэтому
        Keypad/Scanner и FFD Link управляют раздвижной дверью без изменений;
      • GRM.FFDLink.Fade расширен: считает и sliding-двери.

    СОХРАНЕНИЕ:
      • duplicator-модификатор "GRM_SlidingDoor" (копия/сохранение карты);
      • перм-система: GRM.PermData.Extract/Apply["prop_physics"] дополнены
        sliding-веткой — /permadd сохраняет конфиг, после рестарта проп
        встаёт на место и работает как раздвижная дверь.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.SlidingDoor = GRM.SlidingDoor or {}
local SD = GRM.SlidingDoor
SD.Version = "1.1.0"

SD.Doors = SD.Doors or {}   -- [ent] = data

-- Направления (локальные оси пропа)
SD.Directions = {
    left   = "Влево",
    right  = "Вправо",
    forward = "Вперёд",
    back   = "Назад",
    up     = "Вверх",
}

local function charKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return tostring(ply:SteamID64()) .. ":char1"
end

-- Применить механизм раздвижной двери к пропу
function SD.Apply(ply, ent, opts)
    if not IsValid(ent) then return false, "Нет энтити" end
    local cls = ent:GetClass()
    if cls ~= "prop_physics" and cls ~= "prop_dynamic" then
        return false, "Работает только с пропами (prop_physics/prop_dynamic)"
    end

    -- если уже раздвижная — просто перенастраиваем
    if not SD.IsSliding(ent) then
        ent:PhysicsInit(SOLID_VPHYSICS)
        ent:SetMoveType(MOVETYPE_VPHYSICS)
        ent:SetSolid(SOLID_VPHYSICS)
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end

    local data = {
        direction  = tostring(opts.direction or "left"),
        distance   = math.Clamp(tonumber(opts.distance) or 100, 10, 1000),
        speed      = math.Clamp(tonumber(opts.speed) or 120, 10, 2000),
        smooth     = math.Clamp(tonumber(opts.smooth) or 1.0, 0.1, 4.0),
        toggle     = opts.toggle == true or opts.toggle == 1,
        autoclose  = opts.autoclose == true or opts.autoclose == 1,
        closeTime  = math.max(0.5, tonumber(opts.closeTime) or 5),
        owner      = IsValid(ply) and charKey(ply) or "",
        -- Звуки (находка 173d): пусто = нет звука; "открытие/закрытие" —
        -- когда дверь достигла конца/начала, "движение" — во время движения.
        soundOpen   = tostring(opts.soundOpen or ""),
        soundClose  = tostring(opts.soundClose or ""),
        soundMove   = tostring(opts.soundMove or ""),
    }

    ent.isSlidingDoor = true
    ent.Sliding = data
    ent.Sliding_BasePos = ent:GetPos()
    ent.Sliding_OpenPos = ent:GetPos() + SD.OffsetFor(ent, data)
    ent.Sliding_Open = false
    ent.Sliding_Progress = 0          -- 0..1 (0 = закрыто, 1 = открыто)
    ent.Sliding_CloseAt = 0

    -- Методы, совместимые с FFD (Keypad/Scanner/FFD Link зовут их)
    ent.FadeActivate = function() SD.SetOpen(ent, true) end
    ent.FadeDeactivate = function() SD.SetOpen(ent, false) end
    ent.FadeToggle = function() SD.SetOpen(ent, not ent.Sliding_Open) end

    ent:SetNWBool("FFD_IsDoor", true)  -- подсветка в FFD Link

    SD.Doors[ent] = data

    if not opts.skipDupe then
        duplicator.StoreEntityModifier(ent, "GRM_SlidingDoor", {
            direction = data.direction, distance = data.distance,
            speed = data.speed, smooth = data.smooth,
            toggle = data.toggle, autoclose = data.autoclose, closeTime = data.closeTime,
            soundOpen = data.soundOpen, soundClose = data.soundClose, soundMove = data.soundMove,
        })
    end

    return true, "Раздвижная дверь настроена"
end

-- Смещение для конфигурации (локальные оси пропа)
function SD.OffsetFor(ent, data)
    local dir = tostring(data.direction or "left")
    local d = tonumber(data.distance) or 100
    local ang = IsValid(ent) and ent:GetAngles() or Angle(0, 0, 0)
    if dir == "left" then return ang:Right() * -d
    elseif dir == "right" then return ang:Right() * d
    elseif dir == "forward" then return ang:Forward() * d
    elseif dir == "back" then return ang:Forward() * -d
    elseif dir == "up" then return Vector(0, 0, d)
    end
    return ang:Right() * -d
end

function SD.IsSliding(ent)
    return IsValid(ent) and ent.isSlidingDoor == true
end

-- Entity:SetPos у замороженного VPhysics-пропа может сдвинуть только
-- визуальную оболочку. Двигаем одновременно entity и PhysicsObject — тогда
-- collision box реально освобождает проезд для игроков и транспорта.
function SD.MovePhysical(ent,pos)
    if not IsValid(ent) or not pos then return false end
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetPos(pos,true)
        phys:SetAngles(ent:GetAngles())
        if phys.SetVelocityInstantaneous then phys:SetVelocityInstantaneous(vector_origin) end
    end
    ent:SetPos(pos)
    ent:CollisionRulesChanged()
    return true
end

-- Снять механизм (проп возвращается в исходную позицию)
function SD.Remove(ent)
    if not SD.IsSliding(ent) then return false end
    SD.MovePhysical(ent,ent.Sliding_BasePos or ent:GetPos())
    ent.isSlidingDoor = nil
    ent.Sliding = nil
    ent.Sliding_Open = nil
    ent.Sliding_Progress = nil
    ent.Sliding_BasePos = nil
    ent.Sliding_OpenPos = nil
    ent.FadeActivate = nil
    ent.FadeDeactivate = nil
    ent.FadeToggle = nil
    ent:SetNWBool("FFD_IsDoor", false)
    SD.Doors[ent] = nil
    return true
end

-- Открыть/закрыть (вызывается FadeActivate/FadeDeactivate и FFD Link)
function SD.SetOpen(ent, open)
    if not SD.IsSliding(ent) then return end
    ent.Sliding_Open = open == true
    if open then
        ent.Sliding_CloseAt = 0
    elseif ent.Sliding and ent.Sliding.autoclose then
        ent.Sliding_CloseAt = 0 -- автозакрытие управляется таймером Think
    end
end

-- ============================================================
-- СЕРВЕР: единый Think-хук анимации
-- ============================================================
if SERVER then
    -- Плавность: ease in/out (smooth=1 — линейно, больше — мягче)
    local function ease(t, s)
        s = tonumber(s) or 1
        if s <= 0.1 then return t end
        -- smoothstep с настраиваемой кривизной
        local x = math.Clamp(t, 0, 1)
        local k = math.max(0.1, s)
        return (x ^ (1 / k)) / ((x ^ (1 / k)) + ((1 - x) ^ (1 / k)))
    end

    local lastThink = 0
    -- Счётчик анимирующихся дверей: пока ничего не едет, покадровый обход
    -- реестра не нужен вообще. Раньше Think каждый кадр перебирал ВСЕ
    -- раздвижные двери карты и на каждую делал tostring() трёх звуковых
    -- полей — работа на пустом месте при полностью статичных дверях.
    function SD.HasMoving()
        for ent, _ in pairs(SD.Doors) do
            if IsValid(ent) then
                local target = ent.Sliding_Open and 1 or 0
                if math.abs((ent.Sliding_Progress or 0) - target) > 0.0001 then return true end
            end
        end
        return false
    end

    hook.Add("Think", "GRM_SlidingDoor_Think", function()
        local now = CurTime()
        local dt = math.min(0.1, now - lastThink)
        lastThink = now
        if dt <= 0 then return end

        -- Ленивая проверка «есть ли вообще движение» не чаще 4 раз в секунду.
        if (SD._idleCheckAt or 0) < now then
            SD._idleCheckAt = now + 0.25
            SD._anyMoving = SD.HasMoving()
        end
        if not SD._anyMoving then return end

        for ent, data in pairs(SD.Doors) do
            if not IsValid(ent) then
                SD.Doors[ent] = nil
            else
                local base = ent.Sliding_BasePos
                local openPos = ent.Sliding_OpenPos
                if base and openPos then
                    local target = ent.Sliding_Open and 1 or 0
                    local cur = ent.Sliding_Progress or 0
                    -- скорость в юнитах/сек → приращение прогресса
                    local dist = base:Distance(openPos)
                    local rate = dist > 0 and ((tonumber(data.speed) or 120) / dist) or 1
                    local step = rate * dt
                    local next = cur
                    if cur < target then next = math.min(target, cur + step)
                    elseif cur > target then next = math.max(target, cur - step) end
                    local moving = math.abs(next - cur) > 0.0001
                    if moving then ent.Sliding_Progress = next;local e=ease(next,data.smooth);SD.MovePhysical(ent,base+(openPos-base)*e)end

                    -- Звуки (находка 173d): в движении, при открытии, при закрытии.
                    -- tostring() трёх полей вынесен под условие: у стоящей двери
                    -- звуковые строки в кадре больше не собираются.
                    local soundOpen, soundClose, soundMove = "", "", ""
                    if moving or next >= 1 or next <= 0 then
                        soundOpen = tostring(data.soundOpen or "")
                        soundClose = tostring(data.soundClose or "")
                        soundMove = tostring(data.soundMove or "")
                    end
                    if moving and soundMove ~= "" then
                        if (ent.Sliding_SndMove or 0) <= now then
                            ent.Sliding_SndMove = now + 0.6  -- не чаще 1.6/сек
                            if GRM.Sound and GRM.Sound.Emit then GRM.Sound.Emit(ent, soundMove, 70, 100) else ent:EmitSound(soundMove, 70, 100) end
                        end
                    end
                    -- Открытие: один раз при достижении конца (переход 0→1)
                    if next >= 1 and not ent.Sliding_WasOpen and soundOpen ~= "" then
                        if GRM.Sound and GRM.Sound.Emit then GRM.Sound.Emit(ent, soundOpen, 75, 100) else ent:EmitSound(soundOpen, 75, 100) end
                    end
                    -- Закрытие: один раз при достижении начала (переход 1→0),
                    -- флаг «был открыт» держим до самого конца, чтобы не потерять момент
                    if next <= 0 and ent.Sliding_WasEverOpen and soundClose ~= "" then
                        if GRM.Sound and GRM.Sound.Emit then GRM.Sound.Emit(ent, soundClose, 75, 100) else ent:EmitSound(soundClose, 75, 100) end
                    end
                    if next >= 1 then ent.Sliding_WasOpen = true ent.Sliding_WasEverOpen = true
                    elseif next <= 0 then ent.Sliding_WasOpen = false ent.Sliding_WasEverOpen = false end

                    -- автозакрытие
                    if ent.Sliding_Open and data.autoclose then
                        if ent.Sliding_CloseAt == 0 and next >= 1 then
                            ent.Sliding_CloseAt = now + (tonumber(data.closeTime) or 5)
                        elseif ent.Sliding_CloseAt > 0 and now >= ent.Sliding_CloseAt then
                            SD.SetOpen(ent, false)
                        end
                    end
                end
            end
        end
    end)

    -- Очистка реестра при удалении
    hook.Add("EntityRemoved", "GRM_SlidingDoor_Cleanup", function(ent)
        if ent and ent.isSlidingDoor then
            SD.Doors[ent] = nil
        end
    end)

    -- Duplicator: восстановление
    duplicator.RegisterEntityModifier("GRM_SlidingDoor", function(ply, ent, data)
        if IsValid(ent) then
            SD.Apply(ply, ent, {
                direction = data.direction, distance = data.distance,
                speed = data.speed, smooth = data.smooth,
                toggle = data.toggle, autoclose = data.autoclose, closeTime = data.closeTime,
                soundOpen = data.soundOpen, soundClose = data.soundClose, soundMove = data.soundMove,
            })
        end
    end)

    print("[GRM SlidingDoor] server v" .. SD.Version .. " loaded")
end
