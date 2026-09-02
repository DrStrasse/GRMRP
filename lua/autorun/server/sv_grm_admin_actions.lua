--[[--------------------------------------------------------------------
    GRM Admin Actions v1.0.0 — модерация и служебные возможности

    Работает поверх GRM Admin Core: каждое действие проверяет право
    (GRM.Admin.Can) и иммунитет цели (GRM.Admin.CanTarget), пишет запись в
    аудит и уведомляет обе стороны. Все состояния обратимы и снимаются при
    выходе игрока/смерти, чтобы никто не «завис» замученным или в клетке.

    Действия модерации:
      goto / bring / return / tppos     — перемещения
      freeze / unfreeze                 — заморозка
      mute / gag                        — текстовый и голосовой чат
      jail / unjail                     — клетка на месте (с возвратом)
      ragdoll / unragdoll               — рагдоллинг
      slay / respawn / heal / armor     — состояние игрока
      strip                             — забрать оружие
      spectate                          — наблюдение
      kick / ban / warn                 — санкции (свои: Kick + banid/writeid)

    Возможности суперадмина («читерские»):
      god, cloak, speed, buildmode, freezeall, money, item, cleanup

    Санкции исполняет сам GRM штатными средствами движка (banid + writeid,
    kick) плюс своя книга HWID-банов: внешние админ-моды не касаются нашей
    базы вовсе (заказ владельца 03.09 — зависимость ликвидирована).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Admin = GRM.Admin or {}
local AD = GRM.Admin
AD.Actions = AD.Actions or {}
AD.ActionsVersion = "1.0.0"

if not SERVER then return end

local JAIL_MODEL = "models/props_building_details/Storefront_Template001a_Bars.mdl"

local function rpNameOf(ply)
    if not IsValid(ply) then return "?" end
    local rp = ply:GetNWString("GRM_RPName", "")
    return rp ~= "" and rp or ply:Nick()
end

local function audit(actor, action, target, details)
    if GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("admin", "mod." .. tostring(action), actor,
            { nick = IsValid(target) and target:Nick() or "", steamid64 = IsValid(target) and tostring(target:SteamID64() or "") or "" },
            istable(details) and details or {})
    end
end

local function tell(ply, text, ok)
    if not IsValid(ply) then return end
    if GRM.Notify then
        GRM.Notify(ply, tostring(text), ok and 100 or 255, ok and 220 or 150, ok and 130 or 90)
    else
        ply:ChatPrint("[Админ] " .. tostring(text))
    end
end

-- Безопасное место рядом с точкой (чтобы телепорт не заталкивал в стену).
local function safeSpot(pos, from)
    local tr = util.TraceHull({
        start = pos + Vector(0, 0, 16),
        endpos = pos + Vector(0, 0, 16),
        mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72),
        filter = from, mask = MASK_PLAYERSOLID,
    })
    if not tr.Hit then return pos end
    for _, offset in ipairs({ Vector(64, 0, 0), Vector(-64, 0, 0), Vector(0, 64, 0), Vector(0, -64, 0) }) do
        local candidate = pos + offset
        local check = util.TraceHull({
            start = candidate + Vector(0, 0, 16), endpos = candidate + Vector(0, 0, 16),
            mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72),
            filter = from, mask = MASK_PLAYERSOLID,
        })
        if not check.Hit then return candidate end
    end
    return pos + Vector(0, 0, 8)
end

local function rememberPos(ply)
    if not IsValid(ply) then return end
    ply.GRM_AdminReturn = { pos = ply:GetPos(), ang = ply:EyeAngles() }
end

-----------------------------------------------------------------------
-- РЕЕСТР ДЕЙСТВИЙ
-- Каждое: perm, needsTarget, fn(actor, target, args) → ok, message
-----------------------------------------------------------------------
local A = {}

A.goto_player = { perm = "mod.goto", target = true, label = "Телепорт к игроку",
    fn = function(actor, target)
        rememberPos(actor)
        actor:SetPos(safeSpot(target:GetPos() + target:GetForward() * 64, actor))
        return true, "Перемещение к " .. rpNameOf(target)
    end }

A.bring = { perm = "mod.bring", target = true, label = "Притянуть игрока",
    fn = function(actor, target)
        rememberPos(target)
        target:SetPos(safeSpot(actor:GetPos() + actor:GetForward() * 64, target))
        tell(target, "Вас переместил администратор", true)
        return true, rpNameOf(target) .. " перемещён к вам"
    end }

A["return"] = { perm = "mod.return", target = true, label = "Вернуть игрока",
    fn = function(_, target)
        local saved = target.GRM_AdminReturn
        if not istable(saved) then return false, "Нет сохранённой точки возврата" end
        target:SetPos(saved.pos)
        target.GRM_AdminReturn = nil
        return true, rpNameOf(target) .. " возвращён на прежнее место"
    end }

A.tppos = { perm = "cheat.teleport_pos", target = false, label = "Телепорт в точку прицела",
    fn = function(actor)
        local tr = actor:GetEyeTrace()
        if not tr or not tr.Hit then return false, "Нет точки прицела" end
        rememberPos(actor)
        actor:SetPos(safeSpot(tr.HitPos + tr.HitNormal * 24, actor))
        return true, "Телепорт выполнен"
    end }

A.freeze = { perm = "mod.freeze", target = true, label = "Заморозить / разморозить",
    fn = function(_, target)
        local frozen = target.GRM_AdminFrozen == true
        if frozen then
            target:Freeze(false)
            target.GRM_AdminFrozen = nil
            return true, rpNameOf(target) .. " разморожен"
        end
        target:Freeze(true)
        target.GRM_AdminFrozen = true
        tell(target, "Вы заморожены администратором", false)
        return true, rpNameOf(target) .. " заморожен"
    end }

A.mute = { perm = "mod.mute", target = true, label = "Мут чата",
    fn = function(_, target)
        target.GRM_AdminMuted = not (target.GRM_AdminMuted == true)
        tell(target, target.GRM_AdminMuted and "Вам закрыт текстовый чат" or "Текстовый чат снова открыт", not target.GRM_AdminMuted)
        return true, rpNameOf(target) .. (target.GRM_AdminMuted and " замучен" or " размучен")
    end }

A.gag = { perm = "mod.gag", target = true, label = "Мут голоса",
    fn = function(_, target)
        target.GRM_AdminGagged = not (target.GRM_AdminGagged == true)
        tell(target, target.GRM_AdminGagged and "Вам закрыт голосовой чат" or "Голосовой чат снова открыт", not target.GRM_AdminGagged)
        return true, rpNameOf(target) .. (target.GRM_AdminGagged and " лишён голоса" or " вернул голос")
    end }

--[[ КЛЕТКА (переписано 21.08 по жалобе владельца «клетка криво работает»).

     Что было не так на самом деле:
       • четыре решётки ставились на ФИКСИРОВАННЫЕ 48 юнитов от игрока, а
         размер модели другой — стенки не сходились, в углах оставались щели,
         и человек просто выходил боком;
       • клетка строилась вокруг текущей точки без выравнивания по земле:
         на склоне и на лестнице решётки висели в воздухе или тонули в полу;
       • ничто не удерживало внутри: ни потолка, ни «поводка», ноклип не
         запрещался, а сами решётки — обычные prop_physics: их можно поднять
         физганом и растащить;
       • на каждое посаживание заводился отдельный timer.Simple.

     Как сделано теперь:
       • ширина стенки берётся из ГАБАРИТОВ модели (OBB), стенки стыкуются;
       • центр клетки выравнивается по земле трейсом вниз, игрок ставится в
         центр, прежняя позиция запоминается и возвращается при выходе;
       • «поводок»: раз в полсекунды проверяем, не вышел ли человек за радиус
         клетки, и возвращаем в центр — это работает при любой геометрии;
       • ноклип, физган, тулган и урон по решёткам заблокированы;
       • сроки ведёт ОДИН общий таймер на всех, а не таймер на каждого. ]]
local JAIL_RADIUS = 52

local function jailBounds(ent)
    if not IsValid(ent) then return 64, 96 end
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local width = math.max(math.abs(maxs.x - mins.x), math.abs(maxs.y - mins.y))
    local height = math.abs(maxs.z - mins.z)
    return width, height
end

local function releaseJail(target)
    if not IsValid(target) then return end
    if IsValid(target.GRM_AdminJailEnt) then target.GRM_AdminJailEnt:Remove() end
    for _, bar in ipairs(target.GRM_AdminJailBars or {}) do
        if IsValid(bar) then bar:Remove() end
    end
    target.GRM_AdminJailBars = nil
    target.GRM_AdminJailed = nil
    target.GRM_AdminJailUntil = nil
    target.GRM_AdminJailCenter = nil
    target:Freeze(false)
    if istable(target.GRM_AdminJailReturn) or isvector(target.GRM_AdminJailReturn) then
        target:SetPos(target.GRM_AdminJailReturn)
        target.GRM_AdminJailReturn = nil
    end
end
AD.ReleaseJail = releaseJail

--- Точка пола под игроком: клетка должна стоять на земле, а не в воздухе.
local function groundPos(pos)
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 16),
        endpos = pos - Vector(0, 0, 128),
        mask = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit and tr.HitPos or pos
end

local function buildJail(target, center)
    local bars = {}
    local width
    for i = 0, 3 do
        local bar = ents.Create("prop_physics")
        if IsValid(bar) then
            bar:SetModel(JAIL_MODEL)
            bar:Spawn()
            if not width then width = select(1, jailBounds(bar)) end
            local offset = math.max(JAIL_RADIUS, width * 0.5)
            local ang = Angle(0, i * 90, 0)
            bar:SetPos(center + ang:Forward() * offset)
            bar:SetAngles(Angle(0, i * 90 + 90, 0))
            bar:SetMoveType(MOVETYPE_NONE)
            bar:SetSolid(SOLID_VPHYSICS)
            bar:SetCollisionGroup(COLLISION_GROUP_NONE)
            bar.GRMAdminJail = true
            bar.PhysgunDisabled = true
            local phys = bar:GetPhysicsObject()
            if IsValid(phys) then phys:EnableMotion(false) end
            bars[#bars + 1] = bar
        end
    end
    return bars
end

A.jail = { perm = "mod.jail", target = true, label = "Клетка",
    fn = function(actor, target, args)
        if target.GRM_AdminJailed then
            releaseJail(target)
            tell(target, "Вас выпустили из клетки", true)
            return true, rpNameOf(target) .. " выпущен"
        end

        local seconds = math.Clamp(math.floor(tonumber(args and args.seconds) or 120), 10, 3600)
        local center = groundPos(target:GetPos()) + Vector(0, 0, 2)

        target.GRM_AdminJailReturn = target:GetPos()
        target.GRM_AdminJailed = true
        target.GRM_AdminJailUntil = CurTime() + seconds
        target.GRM_AdminJailCenter = center
        target.GRM_AdminJailBars = buildJail(target, center)

        -- Ставим человека в центр: иначе он оказывается внутри стенки и его
        -- выталкивает физикой наружу — ровно то, что выглядело как «клетка
        -- не работает».
        target:SetPos(center)
        target:SetVelocity(-target:GetVelocity())

        tell(target, ("Вы помещены в клетку на %d секунд"):format(seconds), false)
        return true, ("%s в клетке на %d с"):format(rpNameOf(target), seconds)
    end }

--[[ Один общий надзор вместо таймера на каждого арестанта: срок, «поводок»
     и уборка решёток после смерти или респавна. ]]
timer.Create("GRM_Admin_JailWatch", 0.5, 0, function()
    local now = CurTime()
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and ply.GRM_AdminJailed then
            if now >= (ply.GRM_AdminJailUntil or 0) then
                releaseJail(ply)
                tell(ply, "Срок в клетке истёк", true)
            else
                local center = ply.GRM_AdminJailCenter
                if center and ply:GetPos():DistToSqr(center) > (JAIL_RADIUS + 24) ^ 2 then
                    ply:SetPos(center)
                    ply:SetVelocity(-ply:GetVelocity())
                end
            end
        end
    end
end)

-- Из клетки не выйти ноклипом и не разобрать её инструментами.
hook.Add("PlayerNoClip", "GRM_Admin_JailNoClip", function(ply)
    if IsValid(ply) and ply.GRM_AdminJailed then return false end
end)
hook.Add("PhysgunPickup", "GRM_Admin_JailPhysgun", function(_, ent)
    if IsValid(ent) and ent.GRMAdminJail then return false end
end)
hook.Add("CanTool", "GRM_Admin_JailTool", function(_, tr)
    if tr and IsValid(tr.Entity) and tr.Entity.GRMAdminJail then return false end
end)
hook.Add("EntityTakeDamage", "GRM_Admin_JailDamage", function(ent, _)
    if IsValid(ent) and ent.GRMAdminJail then return true end
end)

A.ragdoll = { perm = "mod.ragdoll", target = true, label = "Рагдолл",
    fn = function(_, target, args)
        if IsValid(target.GRM_AdminRagdoll) then
            local rag = target.GRM_AdminRagdoll
            target:SetPos(rag:GetPos() + Vector(0, 0, 16))
            target:UnSpectate()
            target:Spawn()
            rag:Remove()
            target.GRM_AdminRagdoll = nil
            return true, rpNameOf(target) .. " поднят"
        end

        local seconds = math.Clamp(math.floor(tonumber(args and args.seconds) or 20), 3, 600)
        local rag = ents.Create("prop_ragdoll")
        if not IsValid(rag) then return false, "Не удалось создать рагдолл" end
        rag:SetModel(target:GetModel())
        rag:SetPos(target:GetPos())
        rag:SetAngles(target:GetAngles())
        rag:Spawn()
        rag:Activate()
        rag.GRMAdminRagdoll = true

        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                local bone = target:GetBonePosition(rag:TranslatePhysBoneToBone(i))
                if bone then phys:SetPos(bone) end
                phys:SetVelocity(target:GetVelocity())
            end
        end

        target.GRM_AdminRagdoll = rag
        target:Spectate(OBS_MODE_CHASE)
        target:SpectateEntity(rag)
        target:StripWeapons()
        tell(target, ("Вы обездвижены на %d секунд"):format(seconds), false)

        timer.Simple(seconds, function()
            if IsValid(target) and IsValid(target.GRM_AdminRagdoll) then
                local body = target.GRM_AdminRagdoll
                target:UnSpectate()
                target:Spawn()
                target:SetPos(body:GetPos() + Vector(0, 0, 16))
                body:Remove()
                target.GRM_AdminRagdoll = nil
            end
        end)
        return true, ("%s в рагдолле на %d с"):format(rpNameOf(target), seconds)
    end }

A.slay = { perm = "mod.slay", target = true, label = "Убить",
    fn = function(_, target)
        target:Kill()
        return true, rpNameOf(target) .. " убит"
    end }

A.respawn = { perm = "mod.respawn", target = true, label = "Воскресить",
    fn = function(_, target)
        target:Spawn()
        return true, rpNameOf(target) .. " возрождён"
    end }

A.heal = { perm = "mod.heal", target = true, label = "Лечение и броня",
    fn = function(_, target, args)
        local hp = math.Clamp(math.floor(tonumber(args and args.hp) or 100), 1, 1000)
        local armor = math.Clamp(math.floor(tonumber(args and args.armor) or 0), 0, 255)
        target:SetHealth(hp)
        if armor > 0 then target:SetArmor(armor) end
        return true, ("%s: здоровье %d, броня %d"):format(rpNameOf(target), hp, armor)
    end }

A.strip = { perm = "mod.strip", target = true, label = "Забрать оружие",
    fn = function(_, target)
        target:StripWeapons()
        return true, "Оружие у " .. rpNameOf(target) .. " изъято"
    end }

A.spectate = { perm = "mod.spectate", target = true, label = "Наблюдение",
    fn = function(actor, target)
        if actor.GRM_AdminSpectating then
            actor:UnSpectate()
            actor:Spawn()
            if istable(actor.GRM_AdminReturn) then actor:SetPos(actor.GRM_AdminReturn.pos) end
            actor.GRM_AdminSpectating = nil
            return true, "Наблюдение выключено"
        end
        rememberPos(actor)
        actor:Spectate(OBS_MODE_CHASE)
        actor:SpectateEntity(target)
        actor.GRM_AdminSpectating = target
        return true, "Наблюдение за " .. rpNameOf(target)
    end }

A.kick = { perm = "mod.kick", target = true, label = "Кик",
    fn = function(actor, target, args)
        local reason = string.sub(tostring(args and args.reason or "Нарушение правил"), 1, 120)
        target:Kick(reason)
        return true, rpNameOf(target) .. " кикнут: " .. reason
    end }

A.ban = { perm = "mod.ban", target = true, label = "Бан",
    fn = function(actor, target, args)
        local minutes = math.Clamp(math.floor(tonumber(args and args.minutes) or 60), 0, 525600)
        local reason = string.sub(tostring(args and args.reason or "Нарушение правил"), 1, 120)
        --[[ Глобальный бан по железу (заказ владельца 02.09): снимок машины
             и IP цели записываются ДО кика — после спрашивать не с кого.
             По умолчанию включён; args.hwid = false — только SteamID. ]]
        local hwidNote
        local sb = GRM.ServerBan
        if sb and sb.GlobalBan and not (args and args.hwid == false) then
            local okH, msgH = sb.GlobalBan(tostring(target:SteamID64() or ""), rpNameOf(target),
                minutes, reason, actor, target.GRM_MachineRep,
                target.IPAddress and target:IPAddress() or "")
            hwidNote = okH and tostring(msgH) or ("запись не заведена: " .. tostring(msgH))
        end
        -- Штатный бан движка: минуты, 0 = навсегда; запись закрепляем.
        game.ConsoleCommand(("banid %d %s kick\n"):format(minutes, target:SteamID()))
        game.ConsoleCommand("writeid\n")
        target:Kick(reason)
        return true, ("%s забанен на %d мин: %s"):format(rpNameOf(target), minutes, reason)
            .. (hwidNote and (" · " .. hwidNote) or "")
    end }

--[[ БАН НА СЕРВЕРЕ (заказ владельца 21.08). Человек остаётся в игре, но
     отбывает наказание в отведённой зоне: скелет, белый материал, красная
     подсветка, ни оружия, ни меню. Логика — в sh_grm_ban.lua. ]]
A.serverban = { perm = "mod.ban", target = true, label = "Бан на сервере",
    fn = function(actor, target, args)
        if not (GRM.ServerBan and GRM.ServerBan.Ban) then return false, "Модуль банов не загружен" end
        return GRM.ServerBan.Ban(actor, target,
            tonumber(args and args.minutes) or 60,
            tostring(args and args.reason or "Нарушение правил"))
    end }

A.unserverban = { perm = "mod.ban", target = true, label = "Снять бан на сервере",
    fn = function(actor, target)
        if not (GRM.ServerBan and GRM.ServerBan.Unban) then return false, "Модуль банов не загружен" end
        return GRM.ServerBan.Unban(actor, tostring(target:SteamID64() or ""))
    end }

--- Точку отбывания ставит суперадмин по своей позиции.
A.ban_point = { perm = "server.settings", target = false, label = "Точка отбывания бана",
    fn = function(actor, _, args)
        if not IsValid(actor) then return false, "Только из игры" end
        if not (GRM.ServerBan and GRM.ServerBan.SetZone) then return false, "Модуль банов не загружен" end
        return GRM.ServerBan.SetZone(actor, actor:GetPos(), tonumber(args and args.radius) or 600)
    end }

--- Снятие ГЛОБАЛЬНОГО бана: по SteamID64, работает и по офлайн-игроку.
A.unban = { perm = "mod.ban", target = false, label = "Снять глобальный бан",
    fn = function(actor, _, args)
        local query = string.Trim(tostring(args and args.query or ""))
        if query == "" then return false, "Укажите SteamID64 или номер ИГ-####" end
        local sid64 = query
        if GRM.Registry and GRM.Registry.Resolve then
            local _, _, acc = GRM.Registry.Resolve(query)
            if acc and tostring(acc):match("^%d+$") then sid64 = tostring(acc) end
        end
        if not sid64:match("^%d+$") then return false, "Не удалось определить SteamID64" end
        local steamid = util.SteamIDFrom64 and util.SteamIDFrom64(sid64) or nil
        game.ConsoleCommand(("removeid %s\n"):format(steamid or sid64))
        game.ConsoleCommand("writeid\n")
        if GRM.ServerBan and GRM.ServerBan.Unban then GRM.ServerBan.Unban(actor, sid64) end
        -- Глобальная книга: снимки машины/IP тоже снимаются, иначе новый
        -- аккаунт человека остался бы под молчаливым добаном.
        local lifted = GRM.ServerBan and GRM.ServerBan.GlobalLift and GRM.ServerBan.GlobalLift(sid64)
        return true, "Бан снят: " .. tostring(steamid or sid64)
            .. (lifted and " · запись по железу удалена" or "")
    end }

--[[ СНИМОК МАШИНЫ (заказ 02.09). Читает отпечаток клиента: в сети — свежий
     запрос через GRM.ServerBan, иначе кэш последнего отчёта. ]]
A.machine = { perm = "mod.ban", target = true, label = "Снимок машины",
    fn = function(actor, target)
        local sb = GRM.ServerBan
        if not (sb and sb.RequestMachine) then return false, "Модуль банов не загружен" end
        return sb.RequestMachine(actor, target)
    end }

--[[ Бан по НОМЕРУ ИГРОКА (заказ владельца 19.08). Работает и по офлайн-
     игроку: номер ИГ-#### живёт в реестре, значит забанить можно того, кто
     уже вышел с сервера. Персонажный номер ГР-#### тоже принимается — он
     приводится к аккаунту, потому что банят ИГРОКА, а не персонажа. ]]
A.ban_id = { perm = "mod.ban", target = false, label = "Бан по ID игрока",
    fn = function(actor, _, args)
        local query = string.Trim(tostring(args and args.query or ""))
        if query == "" then return false, "Укажите номер: ИГ-1042 или ГР-4821" end
        if not (GRM.Registry and GRM.Registry.Resolve) then return false, "Реестр номеров не загружен" end

        local charKey, charRec, account = GRM.Registry.Resolve(query)
        if not account or account == "" then return false, "Номер не найден в реестре: " .. query end

        local minutes = math.Clamp(math.floor(tonumber(args and args.minutes) or 60), 0, 525600)
        local reason = string.sub(tostring(args and args.reason or "Нарушение правил"), 1, 120)

        -- Игрок в сети — обычный путь с проверкой иммунитета.
        local target
        for _, p in ipairs(player.GetAll()) do
            if tostring(p:SteamID64() or "") == account then target = p break end
        end
        local sb = GRM.ServerBan
        local function globalRow(rep, ip)
            if not (sb and sb.GlobalBan and not (args and args.hwid == false)) then return end
            sb.GlobalBan(account, charRec and charRec.name or account, minutes, reason, actor, rep, ip)
        end
        if IsValid(target) then
            local okTarget, why = AD.CanTarget(actor, target)
            if not okTarget then return false, why end
            -- Снимок машины — до кика (онлайн-путь, заказ 02.09).
            globalRow(target.GRM_MachineRep, target.IPAddress and target:IPAddress() or "")
            game.ConsoleCommand(("banid %d %s kick\n"):format(minutes, target:SteamID()))
            game.ConsoleCommand("writeid\n")
            target:Kick(reason)
        else
            -- Офлайн: считать железо не с кого — запись по одному SteamID;
            -- отпечаток добавится, если человек всплывёт в сети и админ
            -- перепишет бан с живого снимка (или нажмёт «Снимок машины»).
            globalRow(nil, "")
            local steamID = util.SteamIDFrom64 and util.SteamIDFrom64(account) or account
            game.ConsoleCommand(("banid %d %s\n"):format(minutes, steamID))
            game.ConsoleCommand("writeid\n")
        end

        local who = charRec and charRec.name ~= "" and charRec.name or (charKey or account)
        return true, ("Забанен игрок %s (%s) на %d мин: %s"):format(
            GRM.Registry.PID(account), tostring(who), minutes, reason)
    end }

--- Поиск по реестру: кто это за номером (без санкций).
A.id_lookup = { perm = "mod.kick", target = false, label = "Поиск по ID",
    fn = function(actor, _, args)
        local query = string.Trim(tostring(args and args.query or ""))
        if query == "" then return false, "Укажите номер, имя или SteamID64" end
        if not (GRM.Registry and GRM.Registry.Resolve) then return false, "Реестр номеров не загружен" end
        local charKey, _, account = GRM.Registry.Resolve(query)
        if charKey then
            return true, GRM.Registry.Describe(charKey) .. " • SteamID64 " .. tostring(account or "?")
        end
        if account then
            return true, ("Игрок %s • SteamID64 %s"):format(GRM.Registry.PID(account), account)
        end
        return false, "Ничего не найдено: " .. query
    end }

A.warn = { perm = "mod.warn", target = true, label = "Предупреждение",
    fn = function(actor, target, args)
        local text = string.sub(tostring(args and args.reason or "Соблюдайте правила"), 1, 200)
        target.GRM_AdminWarns = (target.GRM_AdminWarns or 0) + 1
        tell(target, "ПРЕДУПРЕЖДЕНИЕ (" .. target.GRM_AdminWarns .. "): " .. text, false)
        return true, ("Предупреждение выдано (%d): %s"):format(target.GRM_AdminWarns, rpNameOf(target))
    end }

-----------------------------------------------------------------------
-- ВОЗМОЖНОСТИ СУПЕРАДМИНА
-----------------------------------------------------------------------
A.god = { perm = "cheat.god", target = true, label = "Режим бога",
    fn = function(_, target)
        if target.GRM_AdminGod then
            target:GodDisable()
            target.GRM_AdminGod = nil
            return true, "Режим бога выключен: " .. rpNameOf(target)
        end
        target:GodEnable()
        target.GRM_AdminGod = true
        return true, "Режим бога включён: " .. rpNameOf(target)
    end }

A.cloak = { perm = "cheat.cloak", target = true, label = "Невидимость",
    fn = function(_, target)
        if target.GRM_AdminCloak then
            target:SetRenderMode(RENDERMODE_NORMAL)
            target:SetColor(Color(255, 255, 255, 255))
            target.GRM_AdminCloak = nil
            return true, "Видимость восстановлена: " .. rpNameOf(target)
        end
        target:SetRenderMode(RENDERMODE_TRANSALPHA)
        target:SetColor(Color(255, 255, 255, 0))
        target.GRM_AdminCloak = true
        return true, "Невидимость включена: " .. rpNameOf(target)
    end }

A.speed = { perm = "cheat.speed", target = true, label = "Скорость",
    fn = function(_, target, args)
        local mult = math.Clamp(tonumber(args and args.value) or 1, 0.25, 6)
        local walk = math.floor(200 * mult)
        local run = math.floor(400 * mult)
        target:SetWalkSpeed(walk)
        target:SetRunSpeed(run)
        return true, ("Скорость %s: x%.2f"):format(rpNameOf(target), mult)
    end }

A.buildmode = { perm = "cheat.buildmode", target = true, label = "Строительный режим",
    fn = function(_, target)
        if target.GRM_AdminBuild then
            target:GodDisable()
            target:SetMoveType(MOVETYPE_WALK)
            target.GRM_AdminBuild = nil
            target.GRM_AdminGod = nil
            return true, "Строительный режим выключен"
        end
        target:GodEnable()
        target:SetMoveType(MOVETYPE_NOCLIP)
        target.GRM_AdminBuild = true
        target.GRM_AdminGod = true
        return true, "Строительный режим включён"
    end }

A.freezeall = { perm = "cheat.freezeall", target = false, label = "Заморозить всех",
    fn = function(actor)
        local n = 0
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply ~= actor and not AD.IsSuper(ply) then
                ply:Freeze(true)
                ply.GRM_AdminFrozen = true
                n = n + 1
            end
        end
        return true, ("Заморожено игроков: %d"):format(n)
    end }

A.unfreezeall = { perm = "cheat.freezeall", target = false, label = "Разморозить всех",
    fn = function()
        local n = 0
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply.GRM_AdminFrozen then
                ply:Freeze(false)
                ply.GRM_AdminFrozen = nil
                n = n + 1
            end
        end
        return true, ("Разморожено игроков: %d"):format(n)
    end }

A.money = { perm = "cheat.money", target = true, label = "Деньги",
    fn = function(actor, target, args)
        local amount = math.floor(tonumber(args and args.value) or 0)
        if amount == 0 then return false, "Сумма не указана" end
        if amount > 0 then
            if GRM.GiveMoney then GRM.GiveMoney(target, amount, "админ: выдача") else return false, "Модуль валюты не загружен" end
        else
            if GRM.TakeMoney then GRM.TakeMoney(target, -amount, "админ: списание") else return false, "Модуль валюты не загружен" end
        end
        return true, ("%s: %s%s"):format(rpNameOf(target), amount > 0 and "+" or "", tostring(amount))
    end }

A.item = { perm = "cheat.items", target = true, label = "Выдать предмет/оружие",
    fn = function(_, target, args)
        local id = string.sub(tostring(args and args.text or ""), 1, 64)
        if id == "" then return false, "Не указан класс предмета" end
        if weapons.Get(id) or list.Get("Weapon")[id] then
            target:Give(id)
            return true, ("Выдано оружие %s игроку %s"):format(id, rpNameOf(target))
        end
        if GRM.Inventory and GRM.Inventory.AddItem then
            local left = tonumber(GRM.Inventory.AddItem(target, id, 1)) or 1
            if left == 0 then return true, ("Выдан предмет %s игроку %s"):format(id, rpNameOf(target)) end
            return false, "Инвентарь полон или предмет неизвестен"
        end
        return false, "Не удалось выдать: неизвестный класс"
    end }

A.char_search = { perm = "char.manage", target = false, label = "Поиск персонажей",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminSendRoster) then return false, "Ядро персонажей не загружено" end
        GRM.Char.AdminSendRoster(actor, args and args.query or "")
        return true, "Список персонажей обновлён"
    end }

A.char_rename = { perm = "char.manage", target = false, label = "Сменить РП-имя",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminSetName) then return false, "Ядро персонажей не загружено" end
        local ok, msg = GRM.Char.AdminSetName(args and args.sid, args and args.slot, args and args.name)
        if ok and GRM.Char.AdminSendRoster then GRM.Char.AdminSendRoster(actor, args and args.query or "") end
        return ok, ok and ("Имя слота " .. tostring(args.slot) .. ": " .. tostring(msg)) or msg
    end }

A.char_delete = { perm = "char.manage", target = false, label = "Удалить персонажа",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminDeleteSlot) then return false, "Ядро персонажей не загружено" end
        local ok, msg = GRM.Char.AdminDeleteSlot(args and args.sid, args and args.slot)
        if ok and GRM.Char.AdminSendRoster then GRM.Char.AdminSendRoster(actor, args and args.query or "") end
        return ok, msg
    end }

A.char_model = { perm = "char.manage", target = false, label = "Сменить модель",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminSetAppearance) then return false, "Ядро персонажей не загружено" end
        local ok, msg = GRM.Char.AdminSetAppearance(args and args.sid, args and args.slot,
            { model = args and args.model, skin = args and args.skin, bodygroups = args and args.bodygroups })
        if ok and GRM.Char.AdminSendRoster then GRM.Char.AdminSendRoster(actor, args and args.query or "") end
        return ok, msg
    end }

A.char_faction = { perm = "char.manage", target = false, label = "Сменить фракцию",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminSetFaction) then return false, "Ядро персонажей не загружено" end
        local ok, msg = GRM.Char.AdminSetFaction(args and args.sid, args and args.slot,
            args and args.faction or "", args and args.role, args and args.department)
        if ok and GRM.Char.AdminSendRoster then GRM.Char.AdminSendRoster(actor, args and args.query or "") end
        return ok, msg
    end }

A.char_access = { perm = "char.manage", target = false, label = "Персональный доступ",
    fn = function(actor, _, args)
        if not (GRM.Char and GRM.Char.AdminSetAccess) then return false, "Ядро персонажей не загружено" end
        local ok, msg = GRM.Char.AdminSetAccess(args and args.sid, args and args.slot,
            args and args.capability, args and args.allow ~= false)
        if ok and GRM.Char.AdminSendRoster then GRM.Char.AdminSendRoster(actor, args and args.query or "") end
        return ok, msg
    end }

A.docs_wipe = { perm = "docs.wipe", target = true, label = "Стереть документы",
    fn = function(actor, target, args)
        local DOC = GRM.Documents
        if not (DOC and isfunction(DOC.WipeDocuments)) then return false, "Модуль документов не загружен" end
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(target))
            or (tostring(target:SteamID64() or "") .. ":char1")
        local ok, removed, details = DOC.WipeDocuments(charKey, { account = args and args.account == true })
        if not ok then return false, tostring(removed) end
        tell(target, "Все ваши документы аннулированы администрацией", false)
        return true, ("Документы %s удалены: %d записей%s"):format(rpNameOf(target), removed,
            (details and details ~= "") and (" (" .. details .. ")") or "")
    end }

A.docs_restore = { perm = "docs.restore", target = true, label = "Восстановить документы",
    fn = function(actor, target, args)
        local DOC = GRM.Documents
        if not (DOC and isfunction(DOC.AdminRestoreDocuments)) then return false, "Модуль документов не загружен" end
        local ok, restored, given, notes = DOC.AdminRestoreDocuments(target, {
            unlosable = args and args.unlosable,
        })
        if not ok then return false, tostring(restored) end
        tell(target, "Администрация восстановила ваши документы", true)
        local extra = (notes and notes ~= "") and (" · " .. notes) or ""
        return true, ("Документы %s: записей %s, бланков %s%s"):format(rpNameOf(target), tostring(restored), tostring(given), extra)
    end }

A.docs_unlosable = { perm = "docs.restore", target = true, label = "Нетеряемые документы",
    fn = function(actor, target, args)
        local DOC = GRM.Documents
        if not (DOC and isfunction(DOC.SetUnlosable)) then return false, "Модуль документов не загружен" end
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(target))
            or (tostring(target:SteamID64() or "") .. ":char1")
        local flag = not (args and args.off == true)
        local ok, n = DOC.SetUnlosable(charKey, flag)
        if not ok then return false, tostring(n) end
        tell(target, flag and "Документы помечены как нетеряемые" or "Нетеряемость документов снята", true)
        return true, (flag and "Нетеряемые" or "Обычные") .. " документы: " .. rpNameOf(target) .. " (" .. tostring(n) .. ")"
    end }

A.cleanup = { perm = "server.cleanup", target = false, label = "Очистка мусора",
    fn = function(actor)
        local removed = 0
        for _, ent in ipairs(ents.FindByClass("prop_physics")) do
            if IsValid(ent) and not ent.GRMPermanent and not ent.GRMAdminJail then
                ent:Remove()
                removed = removed + 1
            end
        end
        return true, ("Убрано пропов: %d"):format(removed)
    end }

AD.Actions = A

-----------------------------------------------------------------------
-- ПРИЁМ ДЕЙСТВИЙ
-----------------------------------------------------------------------
--[[ ОБЪЯВЛЕНИЯ О НАКАЗАНИЯХ (заказ владельца 21.08).
     Раньше о муте, клетке, кике и бане знали только двое: тот, кто выдал,
     и тот, кто получил. Теперь любое наказание — событие сервера: красная
     строка всем. Формулировки лежат ОДНОЙ таблицей рядом с действиями, а не
     размазаны по два ChatPrint внутри каждой функции. ]]
local PUNISH = {
    jail      = { verb = "посадил в клетку", release = "выпустил из клетки", toggle = "GRM_AdminJailed", seconds = true },
    mute      = { verb = "закрыл текстовый чат", release = "вернул текстовый чат", toggle = "GRM_AdminMuted" },
    gag       = { verb = "закрыл голосовой чат", release = "вернул голос", toggle = "GRM_AdminGagged" },
    freeze    = { verb = "заморозил", release = "разморозил", toggle = "GRM_AdminFrozen" },
    ragdoll   = { verb = "уронил в рагдолл", release = "поднял из рагдолла", toggle = "GRM_AdminRagdoll" },
    slay      = { verb = "убил" },
    strip     = { verb = "забрал оружие у" },
    kick      = { verb = "кикнул", reason = true },
    ban       = { verb = "забанил глобально", reason = true, minutes = true },
    serverban = { verb = "забанил на сервере", reason = true, minutes = true },
    unserverban = { verb = "снял бан на сервере с" },
    unban     = { verb = "снял глобальный бан" },
    ban_id    = { verb = "забанил по ID", reason = true, minutes = true },
    warn      = { verb = "вынес предупреждение", reason = true },
    respawn   = { verb = "возродил" },
}

--- Текст объявления по действию. targetWas — состояние ДО выполнения:
--  по нему видно, посадили человека или выпустили.
local function punishText(actorName, targetName, op, args, targetWas)
    local row = PUNISH[op]
    if not row then return nil end
    local verb = row.verb
    if row.toggle and targetWas then verb = row.release or row.verb end

    local tail = ""
    if row.seconds and not targetWas then
        local seconds = math.floor(tonumber(args and args.seconds) or 0)
        if seconds > 0 then tail = (" на %d с"):format(seconds) end
    end
    if row.minutes then
        local minutes = math.floor(tonumber(args and args.minutes) or 0)
        tail = tail .. (minutes > 0 and (" на %d мин."):format(minutes) or " навсегда")
    end
    if row.reason then
        local reason = string.Trim(tostring((args and args.reason) or ""))
        if reason ~= "" then tail = tail .. " · причина: " .. string.sub(reason, 1, 120) end
    end
    return ("%s %s %s%s"):format(actorName, verb, targetName, tail)
end

AD.PunishText = punishText
AD.PunishActions = PUNISH

net.Receive(AD.Net.ACT, function(_, ply)
    if not IsValid(ply) then return end
    if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "admin.action", { rate = 0.25, burst = 6 }, {}) then return end

    local op = net.ReadString()
    local sid = net.ReadString()
    local args = net.ReadTable() or {}

    local action = AD.Actions[op]
    if not action then AD.Result(ply, false, "Неизвестное действие") return end
    if not AD.Can(ply, action.perm) then
        AD.Result(ply, false, "Нет права: " .. tostring(action.label or op))
        return
    end

    local target
    if action.target then
        for _, p in ipairs(player.GetAll()) do
            if tostring(p:SteamID64() or "") == sid then target = p break end
        end
        if not IsValid(target) then AD.Result(ply, false, "Игрок не в сети") return end
        local okTarget, why = AD.CanTarget(ply, target)
        if not okTarget then AD.Result(ply, false, why) return end
    end

    -- Состояние ДО действия: по нему объявление отличит «посадил» от
    -- «выпустил» (кнопка одна и та же, действие переключающее).
    local row = PUNISH[op]
    local was = false
    if row and row.toggle and IsValid(target) then was = target[row.toggle] ~= nil and target[row.toggle] ~= false end

    local ok, message = action.fn(ply, target, args)
    audit(ply, op, target, { args = args, ok = ok == true })
    AD.Result(ply, ok == true, message or (ok and "Готово" or "Не выполнено"))
    AD.PushPlayers(nil)

    if ok and AD.Announce then
        local actorName = ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick()
        local targetName = IsValid(target) and rpNameOf(target) or tostring(args.name or args.query or "игрок")
        local text = punishText(actorName, targetName, op, args, was)
        if text then AD.Announce(text, "mod") end
    end
end)

-----------------------------------------------------------------------
-- ЭФФЕКТЫ СОСТОЯНИЙ
-----------------------------------------------------------------------
-- Мут текстового чата.
hook.Add("PlayerSay", "GRM_Admin_Mute", function(ply, text)
    if IsValid(ply) and ply.GRM_AdminMuted then
        tell(ply, "Вам закрыт текстовый чат администрацией", false)
        return ""
    end
end)

-- Мут голосового чата.
hook.Add("PlayerCanHearPlayersVoice", "GRM_Admin_Gag", function(listener, talker)
    if IsValid(talker) and talker.GRM_AdminGagged then return false end
end)

-- Замороженный/в клетке игрок не должен «уезжать».
hook.Add("PlayerSpawn", "GRM_Admin_ClearStates", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        if ply.GRM_AdminFrozen then ply:Freeze(true) end
        if ply.GRM_AdminGod then ply:GodEnable() end
        if ply.GRM_AdminCloak then
            ply:SetRenderMode(RENDERMODE_TRANSALPHA)
            ply:SetColor(Color(255, 255, 255, 0))
        end
    end)
end)

-- Уборка при выходе: не оставляем клетки и рагдоллы на карте.
hook.Add("PlayerDisconnected", "GRM_Admin_Cleanup", function(ply)
    if IsValid(ply) then
        if ply.GRM_AdminJailed then AD.ReleaseJail(ply) end
        if IsValid(ply.GRM_AdminRagdoll) then ply.GRM_AdminRagdoll:Remove() end
    end
end)

-- Смерть в клетке не должна оставлять решётки.
hook.Add("PlayerDeath", "GRM_Admin_JailDeath", function(ply)
    if IsValid(ply) and ply.GRM_AdminJailed then AD.ReleaseJail(ply) end
end)

print("[GRM Admin Actions] v" .. AD.ActionsVersion .. " loaded")
