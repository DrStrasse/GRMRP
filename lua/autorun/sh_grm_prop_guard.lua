--[[--------------------------------------------------------------------
    GRM Prop Guard v1.1.0 — призрачные пропы и антиабуз стройки
    (заказы владельца 21.08 и 22.08).

    ЧЕТЫРЕ ЗАДАЧИ, ОДИН МОДУЛЬ.

    1. ПРИЗРАК ПРИ СПАВНЕ. Только что созданный проп не должен «взрываться»
       физикой, толкать игроков и застревать в геометрии. Поэтому он
       появляется полупрозрачным, без коллизии и без движения — его видно,
       но он никому не мешает. Как только игрок поставил его физганом и
       ЗАМОРОЗИЛ, проп становится обычным: сплошной, с физикой и коллизией.
       Снял с заморозки физганом — снова призрак, можно спокойно двигать.

    2. ЗАЩИТА ОТ СПАМА. Если игрок сыплет пропами очередью, спавн ему
       закрывается на минуту: об этом ему пишут прямо в чат с обратным
       отсчётом, а событие уходит в аудит. Ограничение считается по окну
       времени, а не по общему числу пропов, поэтому спокойная стройка
       никогда под него не попадает.

    Настройки (конвары, все с сохранением):
      grm_prop_ghost        1    — включить призрачный режим
      grm_prop_ghost_alpha  140  — прозрачность призрака (0…255)
      grm_prop_spam_count   10   — сколько пропов подряд считать спамом
      grm_prop_spam_window  8    — за сколько секунд
      grm_prop_spam_block   60   — на сколько секунд закрывать спавн
      grm_prop_spam_admins  0    — 1: правило действует и на суперадминов
      grm_prop_zone_guard   1    — не твердеть, пока в габаритах чужой игрок
      grm_prop_zone_margin  6    — запас вокруг габаритов, юниты
      grm_prop_antisurf     1    — сбрасывать стоящих на пропе, когда его берут
      grm_prop_antipush     1    — проп в физгане не толкает игроков

    3. ЗОНА ПОСТАНОВКИ. Проп не станет твёрдым, пока в его габаритах стоит
       другой игрок: иначе им давят, выталкивают сквозь стены и запирают.
       Ждёт освобождения и встаёт сам.

    4. АНТИАБУЗ ДВИЖЕНИЯ. Пропом нельзя толкать людей и нельзя на нём
       кататься: пока проп в физгане, он проходит сквозь игроков, а тех,
       кто стоит сверху, снимает с него в момент захвата. Подсказка о
       заморозке приходит ЛИЧНО игроку, а не висит над пропом.
       Проталкивать пропы сквозь браши карты РАЗРЕШЕНО (решение владельца).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.PropGuard = GRM.PropGuard or {}
local PG = GRM.PropGuard
PG.Version = "1.1.0"

-----------------------------------------------------------------------
-- ЧИСТАЯ ЛОГИКА ОКНА СПАМА (гоняется в стенде без игры)
-----------------------------------------------------------------------

--- Отсечь из списка времён всё, что старше окна.
function PG.Trim(times, now, window)
    local out = {}
    for _, t in ipairs(istable(times) and times or {}) do
        if (now - t) <= window then out[#out + 1] = t end
    end
    return out
end

--- Учесть новый спавн. Возвращает: список времён, сработал ли лимит.
function PG.Register(times, now, window, limit)
    local out = PG.Trim(times, now, window)
    out[#out + 1] = now
    return out, #out >= limit
end

--- Сколько секунд осталось до конца блокировки (0 — не заблокирован).
function PG.BlockLeft(blockedUntil, now)
    local left = (tonumber(blockedUntil) or 0) - now
    if left <= 0 then return 0 end
    return math.ceil(left)
end

-----------------------------------------------------------------------
-- ЧИСТАЯ ЛОГИКА ЗОНЫ ПОСТАНОВКИ (гоняется в стенде без игры)
--
-- Пока в габаритах пропа стоит другой игрок, проп НЕ имеет права стать
-- твёрдым: иначе им давят, выталкивают сквозь стены и запирают.
-- Коробки — обычные таблицы {x=,y=,z=}, чтобы логику можно было
-- проверить стендом, а не только в игре.
-----------------------------------------------------------------------

--- Пересекаются ли два AABB с запасом margin по каждой оси.
function PG.BoxesOverlap(aMin, aMax, bMin, bMax, margin)
    if not (istable(aMin) and istable(aMax) and istable(bMin) and istable(bMax)) then return false end
    margin = tonumber(margin) or 0
    for _, ax in ipairs({ "x", "y", "z" }) do
        local a1, a2 = (tonumber(aMin[ax]) or 0) - margin, (tonumber(aMax[ax]) or 0) + margin
        local b1, b2 = tonumber(bMin[ax]) or 0, tonumber(bMax[ax]) or 0
        if a1 > b2 or b1 > a2 then return false end
    end
    return true
end

--- Кто мешает пропу застыть.
--  actors — список { id=, name=, mins=, maxs=, ignore=bool }.
--  Возвращает список имён (пустой = зона свободна).
function PG.ZoneBlockers(mins, maxs, actors, margin, ignoreID)
    local names = {}
    for _, a in ipairs(istable(actors) and actors or {}) do
        local skip = a.ignore == true or (ignoreID ~= nil and a.id == ignoreID)
        if not skip and PG.BoxesOverlap(mins, maxs, a.mins, a.maxs, margin) then
            names[#names + 1] = tostring(a.name or a.id or "?")
        end
    end
    return names
end

--- Утоплен ли проп в геометрию карты. samples — глубины проникновения
--  (числа), allowed — сколько юнитов считается «прижат к стене», а не
--  «в стене». Чистая функция: гоняется стендом.
function PG.WorldVerdict(samples, allowed)
    allowed = tonumber(allowed) or 0
    local deepest = 0
    for _, d in ipairs(istable(samples) and samples or {}) do
        local n = tonumber(d) or 0
        if n > deepest then deepest = n end
    end
    return deepest > allowed, deepest
end

--- Кто стоит на пропе. actors — список { id=, ground=, ignore= }.
--  Чистая функция: гоняется стендом без игры.
function PG.RidersOf(propID, actors)
    local out = {}
    for _, a in ipairs(istable(actors) and actors or {}) do
        if a.ignore ~= true and a.ground ~= nil and a.ground == propID then
            out[#out + 1] = a.id
        end
    end
    return out
end

--- Свободна ли зона (обёртка над ZoneBlockers для читаемости).
function PG.ZoneFree(mins, maxs, actors, margin, ignoreID)
    return #PG.ZoneBlockers(mins, maxs, actors, margin, ignoreID) == 0
end

if SERVER then

    local cvGhost = CreateConVar("grm_prop_ghost", "1", FCVAR_ARCHIVE,
        "Новые пропы появляются призраком: без коллизии и физики, до заморозки физганом")
    local cvAlpha = CreateConVar("grm_prop_ghost_alpha", "140", FCVAR_ARCHIVE,
        "Прозрачность призрачного пропа (0…255)")
    local cvCount = CreateConVar("grm_prop_spam_count", "10", FCVAR_ARCHIVE,
        "Сколько пропов подряд считается спамом")
    local cvWindow = CreateConVar("grm_prop_spam_window", "8", FCVAR_ARCHIVE,
        "За сколько секунд считаются пропы для защиты от спама")
    local cvBlock = CreateConVar("grm_prop_spam_block", "60", FCVAR_ARCHIVE,
        "На сколько секунд закрывается спавн после спама")
    local cvAdmins = CreateConVar("grm_prop_spam_admins", "0", FCVAR_ARCHIVE,
        "1 — защита от спама действует и на суперадминов")
    local cvZone = CreateConVar("grm_prop_zone_guard", "1", FCVAR_ARCHIVE,
        "Не давать пропу коллизию, пока в его габаритах стоит другой игрок")
    local cvZoneMargin = CreateConVar("grm_prop_zone_margin", "6", FCVAR_ARCHIVE,
        "Запас вокруг габаритов пропа при проверке зоны (юниты)")
    local cvSurf = CreateConVar("grm_prop_antisurf", "1", FCVAR_ARCHIVE,
        "Не давать кататься на пропе: стоящих сверху сбрасывает, когда проп берут физганом")
    local cvPush = CreateConVar("grm_prop_antipush", "1", FCVAR_ARCHIVE,
        "Проп в физгане не толкает игроков (проходит сквозь них)")

    PG.Times = PG.Times or {}      -- ply -> массив времён спавна
    PG.Blocked = PG.Blocked or {}  -- ply -> до какого времени закрыт спавн

    local function notify(ply, text, good)
        if not IsValid(ply) then return end
        if GRM.Notify then
            GRM.Notify(ply, text, good and 100 or 255, good and 220 or 150, good and 130 or 100)
        else
            ply:ChatPrint("[Пропы] " .. tostring(text))
        end
    end

    function PG.Window() return math.Clamp(cvWindow:GetInt(), 1, 120) end
    function PG.Limit() return math.Clamp(cvCount:GetInt(), 2, 200) end
    function PG.BlockTime() return math.Clamp(cvBlock:GetInt(), 5, 3600) end
    function PG.GhostEnabled() return cvGhost:GetBool() end

    --- Действует ли на игрока защита (суперадмины по умолчанию свободны).
    function PG.Guarded(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() and not cvAdmins:GetBool() then return false end
        return true
    end

    --- Заблокирован ли спавн прямо сейчас.
    function PG.IsBlocked(ply)
        if not IsValid(ply) then return false, 0 end
        local left = PG.BlockLeft(PG.Blocked[ply], CurTime())
        return left > 0, left
    end

    function PG.Block(ply, seconds)
        if not IsValid(ply) then return end
        seconds = math.max(1, math.floor(tonumber(seconds) or PG.BlockTime()))
        PG.Blocked[ply] = CurTime() + seconds
        PG.Times[ply] = {}
        notify(ply, ("Слишком много пропов подряд. Спавн закрыт на %d секунд."):format(seconds))
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("props", "spam_block", ply, {}, { seconds = seconds })
        end
        print(("[GRM PropGuard] %s превысил лимит пропов — спавн закрыт на %d c")
            :format(ply:Nick(), seconds))
        hook.Run("GRM_PropSpamBlocked", ply, seconds)
    end

    function PG.Unblock(ply)
        if not IsValid(ply) then return end
        PG.Blocked[ply] = nil
        PG.Times[ply] = {}
    end

    --- Учёт спавна: true — можно, false — сработал лимит.
    function PG.Account(ply)
        if not PG.Guarded(ply) then return true end
        local blocked = select(1, PG.IsBlocked(ply))
        if blocked then return false end
        local times, hit = PG.Register(PG.Times[ply], CurTime(), PG.Window(), PG.Limit())
        PG.Times[ply] = times
        if hit then
            PG.Block(ply, PG.BlockTime())
            return false
        end
        return true
    end

    -- ── ПРИЗРАЧНЫЙ ПРОП ─────────────────────────────────────────────

    --[[ ПЕРСОНАЛЬНОЕ УВЕДОМЛЕНИЕ.
         Заказ владельца 22.08: подсказка про заморозку не должна висеть в
         мире над пропом — её видят все вокруг, она мешает и выдаёт чужие
         постройки. Пишем лично хозяину, с антиспамом. ]]
    PG.Told = PG.Told or {}
    function PG.Tell(ply, text, good)
        if not IsValid(ply) then return end
        local key = tostring(text)
        PG.Told[ply] = PG.Told[ply] or {}
        if (PG.Told[ply][key] or 0) > CurTime() then return end
        PG.Told[ply][key] = CurTime() + 3
        notify(ply, text, good)
    end

    --- Перевести проп в призрак: видно, но никому не мешает.
    function PG.MakeGhost(ent)
        if not IsValid(ent) then return false end
        ent.GRMGhost = true
        ent.GRMGhostGroup = ent.GRMGhostGroup or ent:GetCollisionGroup()
        ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
        ent:SetRenderMode(RENDERMODE_TRANSALPHA)
        local a = math.Clamp(cvAlpha:GetInt(), 40, 255)
        local col = ent:GetColor()
        ent.GRMGhostAlpha = col and col.a or 255
        ent:SetColor(Color(col and col.r or 255, col and col.g or 255, col and col.b or 255, a))
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        ent:SetNWBool("GRM_PropGhost", true)
        if IsValid(ent.GRMGhostOwner) then ent:SetNWEntity("GRM_PropGhostOwner", ent.GRMGhostOwner) end
        if PG.Unpend then PG.Unpend(ent) end
        return true
    end

    --- Вернуть пропу физику и коллизию (после заморозки физганом).
    --  Пока в габаритах пропа стоит другой игрок — переход откладывается:
    --  проп остаётся призраком и встаёт сам, как только зона освободится.
    function PG.Materialize(ent, ply, force)
        if not IsValid(ent) or not ent.GRMGhost then return false end
        if force ~= true then
            local busy, who = PG.ZoneBusy(ent, ply)
            if busy then
                PG.Pend(ent, ply, who)
                return false, "zone"
            end
        end
        PG.Unpend(ent)
        ent.GRMGhost = nil
        ent:SetCollisionGroup(ent.GRMGhostGroup or COLLISION_GROUP_NONE)
        ent:SetRenderMode(RENDERMODE_NORMAL)
        local col = ent:GetColor()
        ent:SetColor(Color(col and col.r or 255, col and col.g or 255, col and col.b or 255,
            ent.GRMGhostAlpha or 255))
        ent:SetNWBool("GRM_PropGhost", false)
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
        hook.Run("GRM_PropMaterialized", ent, ply)
        return true
    end

    -- ── ЗОНА ПОСТАНОВКИ ─────────────────────────────────────────────
    --[[ Абуз, который закрываем: игрок ставит проп прямо в другого
         игрока и замораживает — тот получает коллизию в лицо, его
         выталкивает, запирает или убивает. Поэтому переход «призрак →
         твёрдый» разрешён только по свободной зоне. ]]

    function PG.ZoneMargin() return math.Clamp(cvZoneMargin:GetInt(), 0, 64) end

    --- Игроки в габаритах пропа (кроме самого хозяина и тех, кто в ноклипе:
    --  им коллизия не мешает и абузить ей нельзя).
    function PG.ActorsAround(ent, margin)
        local out = {}
        if not IsValid(ent) then return out end
        local mins, maxs = ent:WorldSpaceAABB()
        margin = margin or PG.ZoneMargin()
        local lo = Vector(mins.x - margin - 32, mins.y - margin - 32, mins.z - margin - 32)
        local hi = Vector(maxs.x + margin + 32, maxs.y + margin + 32, maxs.z + margin + 32)
        for _, e in ipairs(ents.FindInBox(lo, hi) or {}) do
            if IsValid(e) and e:IsPlayer() then
                local pmin, pmax = e:WorldSpaceAABB()
                out[#out + 1] = {
                    id = e,
                    name = e:Nick(),
                    mins = { x = pmin.x, y = pmin.y, z = pmin.z },
                    maxs = { x = pmax.x, y = pmax.y, z = pmax.z },
                    ignore = (e:GetMoveType() == MOVETYPE_NOCLIP) or not e:Alive(),
                }
            end
        end
        return out
    end

    --- Занята ли зона пропа. Возвращает: занята ли, список ников.
    function PG.ZoneBusy(ent, ignorePly)
        if not cvZone:GetBool() then return false, {} end
        if not IsValid(ent) then return false, {} end
        local margin = PG.ZoneMargin()
        local mins, maxs = ent:WorldSpaceAABB()
        local box1 = { x = mins.x, y = mins.y, z = mins.z }
        local box2 = { x = maxs.x, y = maxs.y, z = maxs.z }
        local who = PG.ZoneBlockers(box1, box2, PG.ActorsAround(ent, margin), margin,
            IsValid(ignorePly) and ignorePly or nil)
        return #who > 0, who
    end

    PG.Pending = PG.Pending or {}   -- ent -> { ply = , told = , since = }

    local function pendingTick()
        local alive = 0
        for ent, info in pairs(PG.Pending) do
            if not IsValid(ent) or not ent.GRMGhost then
                PG.Pending[ent] = nil
            else
                local phys = ent:GetPhysicsObject()
                local held = IsValid(phys) and phys:IsMoveable()
                if held then
                    -- игрок снова взял проп физганом: ждать нечего
                    PG.Pending[ent] = nil
                    ent:SetNWBool("GRM_PropGhostWait", false)
                else
                    local busy, who = PG.ZoneBusy(ent, info.ply)
                    if not busy then
                        PG.Materialize(ent, info.ply, true)
                        if IsValid(info.ply) then
                            PG.Tell(info.ply, "Зона освободилась — проп закреплён.", true)
                        end
                    else
                        alive = alive + 1
                        if CurTime() - (info.told or 0) > 5 then
                            info.told = CurTime()
                            if IsValid(info.ply) then
                                PG.Tell(info.ply, ("В зоне пропа игрок: %s. Проп станет твёрдым, когда зона освободится.")
                                    :format(table.concat(who, ", ")))
                            end
                        end
                    end
                end
            end
        end
        if alive == 0 and table.Count(PG.Pending) == 0 then
            timer.Remove("GRM_PropGuard_Pending")
        end
    end

    --- Поставить проп в очередь ожидания свободной зоны.
    function PG.Pend(ent, ply, who)
        if not IsValid(ent) then return end
        local first = PG.Pending[ent] == nil
        PG.Pending[ent] = PG.Pending[ent] or { since = CurTime(), told = 0 }
        PG.Pending[ent].ply = IsValid(ply) and ply or PG.Pending[ent].ply
        ent:SetNWBool("GRM_PropGhostWait", true)
        if first then
            PG.Pending[ent].told = CurTime()
            if IsValid(ply) then
                PG.Tell(ply, ("Зона пропа занята (%s) — он останется призраком, пока она не освободится.")
                    :format(table.concat(who or {}, ", ")))
            end
            hook.Run("GRM_PropZoneBusy", ent, ply, who or {})
        end
        if not timer.Exists("GRM_PropGuard_Pending") then
            timer.Create("GRM_PropGuard_Pending", 0.5, 0, pendingTick)
        end
    end

    function PG.Unpend(ent)
        if not IsValid(ent) then return end
        if PG.Pending[ent] then
            PG.Pending[ent] = nil
            ent:SetNWBool("GRM_PropGhostWait", false)
        end
    end

    -- ── АНТИСЁРФ И АНТИТОЛКАНИЕ ─────────────────────────────────────
    --[[ Два абуза одной природы: проп используют как таран и как лифт.
         Пока проп в физгане, он проходит сквозь игроков — толкать им
         никого нельзя. А тех, кто успел встать сверху, снимаем с пропа
         в момент захвата: иначе игрока катают по карте и закидывают
         туда, куда ногами не дойти. Пропы сквозь браши карты
         проталкивать МОЖНО — это решение владельца. ]]

    function PG.AntiSurf() return cvSurf:GetBool() end
    function PG.AntiPush() return cvPush:GetBool() end

    --- Снять с пропа всех, кто на нём стоит.
    function PG.ClearRiders(ent, holder)
        if not IsValid(ent) or not PG.AntiSurf() then return 0 end
        local list = (GRM.Perf and GRM.Perf.Players and GRM.Perf.Players()) or player.GetAll()
        local actors = {}
        for _, ply in ipairs(list) do
            if IsValid(ply) and ply:Alive() then
                actors[#actors + 1] = { id = ply, ground = ply:GetGroundEntity() }
            end
        end
        local riders = PG.RidersOf(ent, actors)
        for _, ply in ipairs(riders) do
            ply:SetGroundEntity(NULL)
            -- лёгкий толчок вниз, чтобы движок не «приклеил» игрока обратно
            ply:SetVelocity(Vector(0, 0, -8))
            if ply ~= holder then
                PG.Tell(ply, "Проп под вами взяли физганом — кататься на пропах нельзя.")
            end
        end
        return #riders
    end

    --- Пока проп в руках — он не толкает людей.
    function PG.HoldNoPush(ent)
        if not IsValid(ent) or not PG.AntiPush() then return end
        if ent.GRMGhost then return end -- призрак и так проходит сквозь всех
        ent.GRMPushGroup = ent.GRMPushGroup or ent:GetCollisionGroup()
        ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
    end

    function PG.ReleaseNoPush(ent)
        if not IsValid(ent) then return end
        if ent.GRMPushGroup == nil then return end
        if not ent.GRMGhost then ent:SetCollisionGroup(ent.GRMPushGroup) end
        ent.GRMPushGroup = nil
    end

    -- новый проп — сразу призрак
    hook.Add("PlayerSpawnedProp", "GRM_PropGuard_Ghost", function(ply, model, ent)
        if not PG.GhostEnabled() then return end
        if not IsValid(ent) then return end
        ent.GRMGhostOwner = ply
        PG.MakeGhost(ent)
        if IsValid(ply) then
            ent:SetNWEntity("GRM_PropGhostOwner", ply)
            PG.Tell(ply, "Проп поставлен призраком: закрепите физганом и заморозьте (ПКМ), чтобы он стал твёрдым.", true)
        end
    end)

    -- заморозил физганом → проп «встал» по-настоящему
    hook.Add("PhysgunFreeze", "GRM_PropGuard_Freeze", function(wep, phys, ent, ply)
        if IsValid(ent) and ent.GRMGhost then
            timer.Simple(0, function()
                if IsValid(ent) and IsValid(phys) and not phys:IsMoveable() then
                    PG.Materialize(ent, ply)
                end
            end)
        end
    end)

    hook.Add("OnPhysgunFreeze", "GRM_PropGuard_FreezeAlt", function(wep, phys, ent, ply)
        if IsValid(ent) and ent.GRMGhost then PG.Materialize(ent, ply) end
    end)

    -- снял с заморозки физганом → снова призрак, чтобы двигать без помех
    hook.Add("PhysgunPickup", "GRM_PropGuard_Pickup", function(ply, ent)
        if IsValid(ent) then
            PG.ClearRiders(ent, ply)
            PG.HoldNoPush(ent)
            ent.GRMHeldBy = ply
        end
        if not PG.GhostEnabled() then return end
        if IsValid(ent) and ent:GetClass() == "prop_physics" and not ent.GRMGhost then
            -- призраком делаем только пропы, которые не защищены чужим владельцем
            local owner = ent.GRMOwner or ent.CPPIGetOwner and ent:CPPIGetOwner() or nil
            if owner == nil or owner == ply then PG.MakeGhost(ent) end
        end
    end)

    -- ── ЗАЩИТА ОТ СПАМА ─────────────────────────────────────────────
    local function guardSpawn(ply)
        if not IsValid(ply) then return end
        local blocked, left = PG.IsBlocked(ply)
        if blocked then
            notify(ply, ("Спавн закрыт ещё %d с — слишком много пропов подряд."):format(left))
            return false
        end
        if not PG.Account(ply) then return false end
    end

    hook.Add("PlayerSpawnProp", "GRM_PropGuard_Limit", guardSpawn)
    hook.Add("PlayerSpawnRagdoll", "GRM_PropGuard_LimitRagdoll", guardSpawn)
    hook.Add("PlayerSpawnEffect", "GRM_PropGuard_LimitEffect", guardSpawn)
    hook.Add("PlayerSpawnSENT", "GRM_PropGuard_LimitSENT", guardSpawn)

    hook.Add("PhysgunDrop", "GRM_PropGuard_Drop", function(ply, ent)
        if not IsValid(ent) then return end
        ent.GRMHeldBy = nil
        PG.ReleaseNoPush(ent)
    end)

    hook.Add("PlayerDisconnected", "GRM_PropGuard_Clear", function(ply)
        PG.Times[ply], PG.Blocked[ply], PG.Told[ply] = nil, nil, nil
    end)

    hook.Add("EntityRemoved", "GRM_PropGuard_Pending", function(ent)
        if PG.Pending and PG.Pending[ent] then PG.Pending[ent] = nil end
    end)

    -- ── команды ─────────────────────────────────────────────────────
    concommand.Add("grm_prop_unblock", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local nick = string.lower(tostring(args and args[1] or ""))
        local n = 0
        for _, target in ipairs(player.GetAll()) do
            if nick == "" or string.lower(target:Nick()):find(nick, 1, true) then
                PG.Unblock(target)
                n = n + 1
            end
        end
        local text = ("[Пропы] снята блокировка спавна: %d игрок(ов)"):format(n)
        if IsValid(ply) then ply:ChatPrint(text) else print(text) end
    end)

    concommand.Add("grm_prop_status", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function say(t) if IsValid(ply) then ply:ChatPrint(t) else print(t) end end
        say(("[Пропы] лимит %d за %d c, блокировка %d c, призрак %s"):format(
            PG.Limit(), PG.Window(), PG.BlockTime(), PG.GhostEnabled() and "вкл" or "выкл"))
        say(("[Пропы] сторож зоны %s, запас %d юнитов, ждут освобождения: %d"):format(
            cvZone:GetBool() and "вкл" or "выкл", PG.ZoneMargin(), table.Count(PG.Pending or {})))
        say(("[Пропы] антисёрф %s, антитолкание %s"):format(
            cvSurf:GetBool() and "вкл" or "выкл", cvPush:GetBool() and "вкл" or "выкл"))
        for _, target in ipairs(player.GetAll()) do
            local blocked, left = PG.IsBlocked(target)
            local recent = #PG.Trim(PG.Times[target] or {}, CurTime(), PG.Window())
            if blocked or recent > 0 then
                say(("   %s — за окно %d, %s"):format(target:Nick(), recent,
                    blocked and ("заблокирован ещё " .. left .. " c") or "норма"))
            end
        end
    end)
end

if CLIENT then
    --[[ ЛИЧНАЯ ПОДСКАЗКА ВМЕСТО НАДПИСИ В МИРЕ (заказ владельца 22.08).

         Было: над каждым призрачным пропом висела 3D2D-табличка «ЗАМОРОЗЬТЕ
         ФИЗГАНОМ». Её видели все вокруг — она захламляла стройку и выдавала
         чужие незакреплённые пропы. Стало: строка внизу СВОЕГО экрана и
         только тогда, когда она к месту — игрок держит призрак физганом или
         смотрит на свой призрак. Чужие пропы молчат. ]]
    surface.CreateFont("GRMPropGuard_Hint", { font = "Roboto", size = 19, weight = 700, extended = true })

    local lookProp, lookAt = nil, 0

    local function myGhost(ent)
        if not IsValid(ent) then return false end
        if not ent:GetNWBool("GRM_PropGhost", false) then return false end
        local owner = ent:GetNWEntity("GRM_PropGhostOwner", NULL)
        return (not IsValid(owner)) or owner == LocalPlayer()
    end

    local PG_WARN = Color(255, 120, 110)
    local PG_WAIT = Color(255, 205, 120)
    local PG_BG = Color(12, 16, 24, 215)

    hook.Add("HUDPaint", "GRM_PropGuard_Hint", function()
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end

        -- трассировка не каждый кадр: строке хватает пяти обновлений в секунду
        if CurTime() - lookAt > 0.2 then
            lookAt = CurTime()
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp) or lp:GetEyeTrace()
            local ent = tr and tr.Entity or nil
            lookProp = myGhost(ent) and ent or nil
        end

        local ent = lookProp
        if not IsValid(ent) then return end
        if lp:GetPos():DistToSqr(ent:GetPos()) > 400 * 400 then return end

        local waiting = ent:GetNWBool("GRM_PropGhostWait", false)
        local text = waiting and "ЗОНА ПРОПА ЗАНЯТА — ОН ЗАКРЕПИТСЯ, КОГДА ИГРОК ОТОЙДЁТ"
            or "ПРОП НЕ ЗАКРЕПЛЁН — ЗАМОРОЗЬТЕ ЕГО ФИЗГАНОМ (ПКМ)"
        local col = waiting and PG_WARN or PG_WAIT

        surface.SetFont("GRMPropGuard_Hint")
        local w, h = surface.GetTextSize(text)
        local x, y = ScrW() / 2, ScrH() - 150
        draw.RoundedBox(6, x - w / 2 - 14, y - h / 2 - 6, w + 28, h + 12, PG_BG)
        draw.SimpleText(text, "GRMPropGuard_Hint", x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)
end

print("[GRM PropGuard] v" .. PG.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")
