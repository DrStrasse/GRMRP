--[[--------------------------------------------------------------------
    GRM Server Ban v1.0.0 — бан НА СЕРВЕРЕ (без выкидывания) и глобальный

    Заказ владельца (21.08): бан должен делиться на два вида.

      • «Забанить на сервере» — человек остаётся в игре, но превращается в
        отбывающего наказание: модель `models/player/skeleton.mdl`, материал
        `debugwhite`, красная подсветка, плашка «ЗАБАНЕН» над головой.
        Оружие изымается, самоубийство и меню недоступны, физган и тулган
        не работают, транспорт закрыт. Он может ходить только по отведённой
        территории — точку и радиус задаёт суперадмин.

      • «Глобальный бан» — жёсткий: игрок выкидывается с сервера штатным
        баном (ULib/ULX, иначе banid).

    Хранение: data/grm_admin/serverbans.json (кто и до какого времени) и
    data/grm_admin/serverban_zone.json (точка и радиус для каждой карты).

    Команды: grm_ban_point [радиус] — поставить точку по своей позиции,
             grm_ban_zone — показать текущую настройку,
             grm_serverban_list — список отбывающих.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.ServerBan = GRM.ServerBan or {}
local SB = GRM.ServerBan
SB.Version = "1.1.0"

--[[ Звук отбывающего наказание (заказ владельца 21.08): забаненный должен
     «звучать» — от скелета идут зомби-стоны, его слышно и не спутать с
     обычным игроком. Список звуков и интервал можно менять конварами. ]]
SB.ZombieSounds = {
    "npc/zombie/zombie_voice_idle1.wav",
    "npc/zombie/zombie_voice_idle2.wav",
    "npc/zombie/zombie_voice_idle3.wav",
    "npc/zombie/zombie_voice_idle4.wav",
    "npc/zombie/zombie_voice_idle5.wav",
    "npc/zombie/zombie_voice_idle6.wav",
}

SB.Model = "models/player/skeleton.mdl"
SB.Material = "debugwhite"
SB.Net = { SYNC = "GRM_ServerBan_Sync", LIST_REQ = "GRM_ServerBan_ListReq", LIST = "GRM_ServerBan_List" }

SB.Zone = SB.Zone or { pos = nil, radius = 600, map = "" }
SB.Bans = SB.Bans or {}

--- Осталось секунд по записи бана (0 — истёк).
-- Источник истины для срочного бана — remaining. Стенные часы (until)
-- тикают ТОЛЬКО пока персонаж реально отбывает наказание в мире.
-- Рестарт / оффлайн / выбор другого слота срок не жрут.
function SB.Left(rec)
    if not istable(rec) then return 0 end
    if rec.permanent == true then return math.huge end
    if rec.paused == true or tonumber(rec["until"]) == 0 then
        local left = tonumber(rec.remaining)
        if left == nil then return 0 end
        if left < 0 then return math.huge end
        return math.max(0, left)
    end
    local until_ = tonumber(rec["until"]) or 0
    if until_ <= 0 then
        local left = tonumber(rec.remaining)
        if left == nil then return math.huge end
        if left < 0 then return math.huge end
        return math.max(0, left)
    end
    return math.max(0, until_ - os.time())
end

function SB.Describe(rec)
    if not istable(rec) then return "" end
    local left = SB.Left(rec)
    local when = left == math.huge and "бессрочно" or (math.ceil(left / 60) .. " мин.")
    return ("%s · %s"):format(tostring(rec.reason or "нарушение правил"), when)
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    --[[ Регистрируем ВСЕ имена пакетов модуля, а не только один. Ошибка
         «Calling net.Start with unpooled message name» вылезла ровно из-за
         этого: список забаненных добавили позже, а строку сети — нет.
         Проход по таблице страхует от повторения: добавил канал в SB.Net —
         он зарегистрирован. ]]
    for _, name in pairs(SB.Net) do util.AddNetworkString(name) end

    SB.SoundCvar = SB.SoundCvar or CreateConVar("grm_ban_zombie_sound", "1", FCVAR_ARCHIVE,
        "Забаненные на сервере издают зомби-звуки (0 — тишина)")
    SB.SoundMinCvar = SB.SoundMinCvar or CreateConVar("grm_ban_zombie_min", "4", FCVAR_ARCHIVE,
        "Минимальная пауза между зомби-звуками наказанного, секунд")
    SB.SoundMaxCvar = SB.SoundMaxCvar or CreateConVar("grm_ban_zombie_max", "9", FCVAR_ARCHIVE,
        "Максимальная пауза между зомби-звуками наказанного, секунд")

    local DIR = "grm_admin"
    local BANS_FILE = DIR .. "/serverbans.json"
    local ZONE_FILE = DIR .. "/serverban_zone.json"

    local function jsonT(raw)
        local ok, t = pcall(util.JSONToTable, raw or "", false, true)
        return (ok and istable(t)) and t or nil
    end
    local function ensureDir()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end
    local function mapName() return string.lower(tostring(game.GetMap() or "unknown")) end

    local function announce(text)
        if GRM.Admin and GRM.Admin.Announce then GRM.Admin.Announce(text, "mod") else print("[GRM Ban] " .. text) end
    end

    local function actorName(ply)
        if not IsValid(ply) then return "Консоль" end
        local rp = ply:GetNWString("GRM_RPName", "")
        return rp ~= "" and rp or ply:Nick()
    end

    -- Серверный бан — RP-наказание конкретного персонажа. SteamID64 нужен
    -- только для legacy-миграции и глобального аккаунтного бана.
    local function characterKey(ply)
        if not IsValid(ply) then return "" end
        if GRM.Identity and GRM.Identity.CharacterKey then return tostring(GRM.Identity.CharacterKey(ply) or "") end
        return tostring(ply:SteamID64() or "") .. ":char1"
    end
    local function accountKey(ply) return IsValid(ply) and tostring(ply:SteamID64() or "") or "" end

    -- Диск — через общую очередь: бан пишется в момент действия, а не пачкой.
    if GRM.Save and GRM.Save.Register then
        GRM.Save.Register("serverban.list", { file = BANS_FILE, label = "Баны на сервере", delay = 2, priority = 2,
            build = function() ensureDir() return { version = 1, bans = SB.Bans, history = SB.History } end })
        GRM.Save.Register("serverban.zone", { file = ZONE_FILE, label = "Точка отбывания бана", delay = 2,
            build = function() ensureDir() return { version = 1, zones = SB.Zones or {} } end })
    end

    local function saveBans(why)
        if GRM.Save and GRM.Save.Mark then return GRM.Save.Mark("serverban.list", why) end
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, { version = 1, bans = SB.Bans, history = SB.History }, true)
        if ok and isstring(raw) then file.Write(BANS_FILE, raw) return true end
        return false
    end
    local function saveZone(why)
        if GRM.Save and GRM.Save.Mark then return GRM.Save.Mark("serverban.zone", why) end
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, { version = 1, zones = SB.Zones or {} }, true)
        if ok and isstring(raw) then file.Write(ZONE_FILE, raw) return true end
        return false
    end

    SB.History = SB.History or {}
    SB.HistoryCap = 200

    local function pushHistory(kind, sid, rec, actor)
        SB.History[#SB.History + 1] = {
            t = os.time(), kind = tostring(kind), sid = tostring(sid or ""),
            name = tostring((rec and rec.name) or ""), reason = tostring((rec and rec.reason) or ""),
            by = IsValid(actor) and actor:Nick() or "консоль",
            minutes = rec and rec["until"] and rec["until"] > 0
                and math.ceil((rec["until"] - os.time()) / 60) or 0,
        }
        while #SB.History > SB.HistoryCap do table.remove(SB.History, 1) end
    end

    function SB.Load()
        SB.Bans, SB.Zones = {}, {}
        local data = jsonT(file.Read(BANS_FILE, "DATA") or "")
        if istable(data) and istable(data.bans) then
            for sid, rec in pairs(data.bans) do
                if isstring(sid) and istable(rec) then
                    local duration = tonumber(rec.duration)
                    local remaining = tonumber(rec.remaining)
                    local until_ = math.floor(tonumber(rec["until"]) or 0)
                    local at = math.floor(tonumber(rec.at) or os.time())
                    local permanent = rec.permanent == true or (until_ <= 0 and remaining == nil and rec.paused ~= true)
                    if not duration and until_ > at then duration = until_ - at end
                    -- Рестарт: стенное until уже убежало вперёд, пока сервера не было.
                    -- Берём последний записанный remaining, иначе исходный срок.
                    if not remaining then
                        remaining = duration
                    end
                    if remaining and remaining < 0 then remaining = nil permanent = true end
                    local row = {
                        ["until"] = 0,
                        reason = tostring(rec.reason or ""),
                        by = tostring(rec.by or ""),
                        at = at,
                        name = tostring(rec.name or ""),
                        characterKey = tostring(rec.characterKey or sid),
                        accountSteam = tostring(rec.accountSteam or ""),
                        legacyAccount = not tostring(sid):find(":char[1-3]$"),
                        paused = not permanent,
                        remaining = permanent and nil or math.max(0, math.floor(remaining or 0)),
                        duration = duration and math.max(0, math.floor(duration)) or nil,
                        permanent = permanent or nil,
                    }
                    -- Куда вернуть после снятия: переживает рестарт сервера.
                    if istable(rec.returnPos) then
                        local x, y, z = tonumber(rec.returnPos.x), tonumber(rec.returnPos.y), tonumber(rec.returnPos.z)
                        if x and y and z and not (x == 0 and y == 0 and z == 0) then
                            row.returnPos = { x = x, y = y, z = z }
                        end
                    end
                    SB.Bans[sid] = row
                end
            end
        end
        SB.History = {}
        if istable(data) and istable(data.history) then
            for _, row in ipairs(data.history) do
                if istable(row) then SB.History[#SB.History + 1] = row end
            end
        end
        --[[ 21.08. Точка хранится ПЛОСКОЙ таблицей {x,y,z}, а не Vector.
             Причина, по которой она «слетала» после рестарта: Vector — это
             userdata, и util.TableToJSON пишет его пустышкой. Файл на диске
             получался с `pos: {}`, при загрузке координаты читались нулями и
             зона пропадала. Теперь на диск идут числа, а Vector собирается
             при использовании. ]]
        local zones = jsonT(file.Read(ZONE_FILE, "DATA") or "")
        if istable(zones) and istable(zones.zones) then
            for map, z in pairs(zones.zones) do
                if isstring(map) and istable(z) and istable(z.pos) then
                    local x, y, zz = tonumber(z.pos.x), tonumber(z.pos.y), tonumber(z.pos.z)
                    if x and y and zz and not (x == 0 and y == 0 and zz == 0) then
                        SB.Zones[map] = {
                            pos = { x = x, y = y, z = zz },
                            radius = math.Clamp(math.floor(tonumber(z.radius) or 600), 100, 8000),
                        }
                    end
                end
            end
        end
        local mine = SB.Zones[mapName()]
        print(("[GRM Server Ban] загружено: банов %d, точка отбывания на карте %s"):format(
            table.Count(SB.Bans), mine and ("есть, радиус " .. mine.radius) or "НЕ ЗАДАНА"))
        return true
    end

    --- Зона отбывания для текущей карты (может отсутствовать — тогда наказание
    --  применяется «на месте», но без телепорта).
    function SB.CurrentZone()
        return (SB.Zones or {})[mapName()]
    end

    --- Точка как Vector: наружу отдаём готовый вектор, внутри храним числа.
    function SB.ZonePos(zone)
        zone = zone or SB.CurrentZone()
        if not (istable(zone) and istable(zone.pos)) then return nil end
        return Vector(tonumber(zone.pos.x) or 0, tonumber(zone.pos.y) or 0, tonumber(zone.pos.z) or 0)
    end

    function SB.SetZone(actor, pos, radius)
        if not isvector(pos) then return false, "Нет позиции" end
        SB.Zones = SB.Zones or {}
        SB.Zones[mapName()] = {
            pos = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) },
            radius = math.Clamp(math.floor(tonumber(radius) or 600), 100, 8000),
        }
        saveZone("точка бана " .. mapName())
        -- Точку теряют реже, чем ищут: пишем сразу, не дожидаясь очереди.
        if GRM.Save and GRM.Save.Flush then GRM.Save.Flush("serverban.zone", "точка бана") end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("admin", "ban.zone", actor, { map = mapName() },
                { radius = SB.Zones[mapName()].radius })
        end
        return true, ("Точка отбывания бана задана · радиус %d"):format(SB.Zones[mapName()].radius)
    end

    -------------------------------------------------------------------
    -- ПРИМЕНЕНИЕ НАКАЗАНИЯ
    -------------------------------------------------------------------
    function SB.IsBanned(v)
        local key = IsValid(v) and characterKey(v) or tostring(v or "")
        local rec = SB.Bans[key]
        -- Старые записи SteamID64 остаются account-wide только как legacy,
        -- новые баны никогда не попадают сюда.
        if not rec and IsValid(v) then
            local old = accountKey(v)
            if SB.Bans[old] and SB.Bans[old].legacyAccount then key, rec = old, SB.Bans[old] end
        end
        if not rec then return false end
        if SB.Left(rec) <= 0 then SB.Bans[key] = nil saveBans("истёк " .. key) return false end
        return true, rec, key
    end

    function SB.FreezeRecord(rec, why)
        if not istable(rec) or rec.permanent then return false end
        local left = SB.Left(rec)
        if left == math.huge then rec.permanent = true rec["until"] = 0 rec.paused = false return false end
        rec.remaining, rec.paused, rec["until"] = math.ceil(left), true, 0
        saveBans(why or "пауза бана")
        if GRM.Save and GRM.Save.Flush then GRM.Save.Flush("serverban.list", why or "пауза бана") end
        return true
    end

    function SB.Pause(ply)
        local banned, rec = SB.IsBanned(ply)
        if not banned or not rec or rec.paused then return false end
        return SB.FreezeRecord(rec, "пауза бана: выход персонажа")
    end

    function SB.Resume(rec)
        if not (istable(rec) and rec.paused) then return false end
        if rec.permanent then rec.paused = false rec["until"] = 0 return true end
        local left = tonumber(rec.remaining) or 0
        rec.paused = false
        rec.remaining = math.max(0, math.ceil(left))
        rec["until"] = os.time() + rec.remaining
        saveBans("продолжение бана: вход персонажа")
        return true
    end

    function SB.SyncClient(ply, rec)
        if not IsValid(ply) then return end
        rec = rec or select(2, SB.IsBanned(ply))
        if not istable(rec) then return end
        local left = SB.Left(rec)
        ply:SetNWBool("GRM_ServerBanned", true)
        ply:SetNWString("GRM_ServerBanReason", tostring(rec.reason or ""))
        ply:SetNWInt("GRM_ServerBanUntil", (rec.paused or rec.permanent or left == math.huge)
            and 0 or math.floor(tonumber(rec["until"]) or 0))
        ply:SetNWInt("GRM_ServerBanLeft", left == math.huge and -1 or math.floor(left))
        ply:SetNWInt("GRM_ServerBanSync", os.time())
    end

    --- Наложить визуал и ограничения. Зовётся при бане, при спавне и раз в
    --  полсекунды сторожем: другие модули (одежда, кастомизация) могут
    --  вернуть игроку модель, поэтому наказание надо «дожимать».
    function SB.Apply(ply, teleport)
        if not IsValid(ply) then return end
        local banned, rec = SB.IsBanned(ply)
        if not banned then return end
        -- Отсчёт продолжает идти только когда этот персонаж снова выбран
        -- и реально возвращён в мир.
        if rec.paused then SB.Resume(rec) end

        if ply:GetModel() ~= SB.Model then ply:SetModel(SB.Model) end
        if ply:GetMaterial() ~= SB.Material then ply:SetMaterial(SB.Material) end
        ply:SetColor(Color(255, 60, 60, 255))
        ply:SetRenderMode(RENDERMODE_TRANSCOLOR)
        ply.GRM_BanCharacterKey = tostring(rec.characterKey or characterKey(ply))
        SB.SyncClient(ply, rec)

        if not ply.GRM_BanReturn and istable(rec.returnPos) then
            ply.GRM_BanReturn = Vector(rec.returnPos.x, rec.returnPos.y, rec.returnPos.z)
        end

        if ply:GetActiveWeapon() ~= NULL and IsValid(ply:GetActiveWeapon()) then ply:StripWeapons() end
        if #ply:GetWeapons() > 0 then ply:StripWeapons() end
        ply:StripAmmo()

        local zonePos = SB.ZonePos()
        if teleport and zonePos then
            ply:SetPos(zonePos + Vector(0, 0, 8))
            ply:SetVelocity(-ply:GetVelocity())
        end
    end

    --[[ СНЯТИЕ НАКАЗАНИЯ (переписано 21.08 по жалобе: «разбанили — человек
         ничего не может и не пишет в чат»).

         Было два виновника:
           1) здесь вызывался `ply:Spawn()`. Принудительный респавн ломает
              РП-поток: модуль персонажей заново проводит игрока через свою
              логику, и человек оставался в «пустом» состоянии;
           2) клиентский сторож окон УДАЛЯЛ панели (см. ниже) — вместе с
              панелью чата EasyChat, которая после Remove уже не открывалась.

         Теперь: возвращаем вид и подвижность на месте, оружие выдаём штатным
         хуком загрузки снаряжения, респавн не трогаем. ]]
    function SB.Clear(ply, returnPos)
        if not IsValid(ply) then return end
        ply:SetNWBool("GRM_ServerBanned", false)
        ply:SetNWString("GRM_ServerBanReason", "")
        ply:SetNWInt("GRM_ServerBanUntil", 0)
        ply:SetNWInt("GRM_ServerBanLeft", 0)
        ply:SetNWInt("GRM_ServerBanSync", 0)
        ply:SetMaterial("")
        ply:SetColor(Color(255, 255, 255, 255))
        ply:SetRenderMode(RENDERMODE_NORMAL)

        -- Подвижность и управление возвращаем явно: мало ли что успело
        -- застрять, пока человек отбывал наказание.
        ply:Freeze(false)
        if ply.SetMoveType and MOVETYPE_WALK then ply:SetMoveType(MOVETYPE_WALK) end
        ply.GRM_BanNextMoan = nil

        -- Модель вернут модули внешности; страховкой — сохранённая.
        hook.Run("GRM_ServerBanCleared", ply)
        if ply:GetModel() == SB.Model then
            local restored = ply:GetNWString("GRM_PreBanModel", "")
            ply:SetModel(restored ~= "" and restored or "models/player/group01/male_02.mdl")
        end
        ply:SetNWString("GRM_PreBanModel", "")

        -- Снаряжение возвращаем штатным путём, а не респавном.
        if ply:Alive() then
            local ok = pcall(hook.Run, "PlayerLoadout", ply)
            if not ok then ply:Give("weapon_physcannon") end
        end

        --[[ Возврат на место. Человека забрали из мира в зону отбывания —
             значит и вернуть надо туда, откуда забрали, а не бросить в
             деморгане. Точка пережила рестарт вместе с записью бана. ]]
        local bannedCharacter = tostring(ply.GRM_BanCharacterKey or "")
        local sameCharacter = bannedCharacter ~= "" and bannedCharacter == characterKey(ply)
        local back = sameCharacter and (returnPos or ply.GRM_BanReturn) or nil
        if isvector(back) and not (back.x == 0 and back.y == 0 and back.z == 0) then
            ply:SetPos(back + Vector(0, 0, 8))
            ply:SetVelocity(-ply:GetVelocity())
            if GRM.Notify then GRM.Notify(ply, "Вы возвращены на прежнее место.", 100, 220, 130) end
        elseif not sameCharacter and GRM.Char and GRM.Char.PlaceOnSpawnPoint then
            -- Другой персонаж не наследует координаты деморгана. Он должен
            -- появиться на обычной точке своей фракции из /spawnmenu.
            timer.Simple(0, function()
                if IsValid(ply) then GRM.Char.PlaceOnSpawnPoint(ply) end
            end)
            if GRM.Notify then GRM.Notify(ply, "Выбран другой персонаж: отправлен на его точку появления.", 100, 220, 130) end
        end
        ply.GRM_BanReturn, ply.GRM_BanCharacterKey = nil, nil

        -- PlayerLoadout возвращает базовый Sandbox-набор, но штатное
        -- вооружение фракции живёт в /weapons_admin и выдаётся отдельным
        -- контуром. После снятия наказания применяем его ещё раз, уже после
        -- возврата/постановки персонажа на точку.
        timer.Simple(0.15, function()
            if not IsValid(ply) or select(1, SB.IsBanned(ply)) then return end
            if _G.ApplyWeaponsToPlayer then pcall(_G.ApplyWeaponsToPlayer, ply) end
        end)
    end

    -------------------------------------------------------------------
    -- БАН / РАЗБАН
    -------------------------------------------------------------------
    function SB.Ban(actor, target, minutes, reason)
        if not IsValid(target) or not target:IsPlayer() then return false, "Игрок не в сети" end
        minutes = math.Clamp(math.floor(tonumber(minutes) or 60), 0, 525600)
        reason = string.sub(string.Trim(tostring(reason or "Нарушение правил")), 1, 120)
        local sid = characterKey(target)
        if sid == "" then return false, "Нет активного персонажа" end

        -- Запоминаем модель ДО наказания. Если игрок уже в скелете (повторный
        -- бан, перезаход после падения сервера), прежнее значение не затираем —
        -- иначе после разбана человек так и останется скелетом.
        if target:GetModel() ~= SB.Model then
            target:SetNWString("GRM_PreBanModel", target:GetModel())
        end
        --[[ Точка, откуда человека забрали, запоминается вместе с баном
             (заказ 21.08: после разбана вернуть на исходное место). Пишем
             числами, а не Vector: userdata в JSON превращается в пустышку —
             на этом уже обжигались с точкой отбывания. ]]
        local from = target:GetPos()
        target.GRM_BanReturn = Vector(from.x, from.y, from.z)

        SB.Bans[sid] = {
            ["until"] = minutes > 0 and (os.time() + minutes * 60) or 0,
            reason = reason, by = actorName(actor), at = os.time(),
            name = target:GetNWString("GRM_RPName", target:Nick()),
            characterKey = sid, accountSteam = accountKey(target),
            returnPos = { x = math.floor(from.x), y = math.floor(from.y), z = math.floor(from.z) },
        }
        pushHistory("ban", sid, SB.Bans[sid], actor)
        saveBans("бан " .. sid)
        SB.Apply(target, true)

        target.GRM_BanNextMoan = 0
        SB.Moan(target)

        local text = ("%s забанен на сервере (%s) · %s"):format(target:Nick(),
            minutes > 0 and (minutes .. " мин.") or "бессрочно", reason)
        announce(actorName(actor) .. " выдал бан на сервере: " .. text)
        if GRM.Notify then
            GRM.Notify(target, "Вы забанены на сервере: " .. reason, 255, 90, 90)
        end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("admin", "ban.server", actor, { characterKey = sid, steamid64 = accountKey(target), nick = target:Nick() },
                { minutes = minutes, reason = reason })
        end
        return true, text
    end

    function SB.Unban(actor, query)
        local sid = tostring(query or "")
        local target
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and (characterKey(p) == sid or (SB.Bans[sid] and SB.Bans[sid].legacyAccount and accountKey(p) == sid)) then target = p break end
        end
        if not SB.Bans[sid] then return false, "Серверного бана нет" end
        local rec = SB.Bans[sid]
        local back
        if istable(rec.returnPos) then
            back = Vector(rec.returnPos.x, rec.returnPos.y, rec.returnPos.z)
        end
        pushHistory("unban", sid, rec, actor)
        SB.Bans[sid] = nil
        saveBans("разбан " .. sid)
        if IsValid(target) then
            SB.Clear(target, back)
            if GRM.Notify then GRM.Notify(target, "Серверный бан снят.", 100, 220, 130) end
        end
        announce(actorName(actor) .. " снял бан на сервере с " ..
            (IsValid(target) and target:Nick() or sid))
        return true, "Серверный бан снят"
    end

    --- Строки для админ-меню: кто отбывает, за что и сколько осталось.
    function SB.List()
        local rows = {}
        for sid, rec in pairs(SB.Bans) do
            local left = SB.Left(rec)
            rows[#rows + 1] = {
                sid = sid,
                name = tostring(rec.name or ""),
                reason = tostring(rec.reason or ""),
                by = tostring(rec.by or ""),
                at = math.floor(tonumber(rec.at) or 0),
                left = left == math.huge and -1 or math.floor(left),
                characterKey = tostring(rec.characterKey or sid),
                legacyAccount = rec.legacyAccount == true,
                online = false,
            }
        end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local key = characterKey(ply)
                for _, row in ipairs(rows) do
                    if row.sid == key or (row.legacyAccount and row.sid == accountKey(ply)) then
                        row.online = true
                        row.name = ply:GetNWString("GRM_RPName", ply:Nick())
                    end
                end
            end
        end
        table.sort(rows, function(a, b) return (a.at or 0) > (b.at or 0) end)
        return rows
    end

    net.Receive(SB.Net.LIST_REQ, function(_, ply)
        if not IsValid(ply) then return end
        local canSee = ply:IsSuperAdmin() or (GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "mod.ban"))
        if not canSee then return end
        local history = {}
        for i = #SB.History, math.max(1, #SB.History - 40), -1 do
            history[#history + 1] = SB.History[i]
        end
        net.Start(SB.Net.LIST)
        net.WriteTable({ bans = SB.List(), history = history })
        net.Send(ply)
    end)

    -------------------------------------------------------------------
    -- ОГРАНИЧЕНИЯ
    -------------------------------------------------------------------
    local function banned(ply) return IsValid(ply) and ply:GetNWBool("GRM_ServerBanned", false) end
    SB.PlayerBanned = banned

    --[[ ЕДИНЫЙ ЗАПРЕТ НА ЭФИР (заказ владельца 21.08). Волны и рации идут не
         через чат, а своими net-пакетами, поэтому блокировка чат-команд их
         не ловила. Модули зовут одну эту функцию и получают готовый текст —
         второй реализации запрета нет. ]]
    function SB.SpeechBlocked(ply, what)
        if not banned(ply) then return false end
        local rec = select(2, SB.IsBanned(ply))
        local left = rec and SB.Left(rec) or 0
        local when = left == math.huge and "бессрочно" or (math.ceil(left / 60) .. " мин.")
        return true, ("Вы отбываете административное наказание (деморган), поэтому %s недоступн%s. Осталось: %s")
            :format(tostring(what or "эфир"), tostring(what or ""):find("рация", 1, true) and "а" or "о", when)
    end

    --- Помощник для модулей: сам пишет игроку отказ и возвращает true.
    function SB.DenySpeech(ply, what)
        local blocked, text = SB.SpeechBlocked(ply, what)
        if not blocked then return false end
        if GRM.Notify then GRM.Notify(ply, text, 255, 110, 90) else ply:ChatPrint("[Бан] " .. text) end
        return true
    end

    hook.Add("CanPlayerSuicide", "GRM_ServerBan_NoSuicide", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerSwitchFlashlight", "GRM_ServerBan_NoFlash", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerCanPickupWeapon", "GRM_ServerBan_NoWeapons", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerCanPickupItem", "GRM_ServerBan_NoItems", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("CanPlayerEnterVehicle", "GRM_ServerBan_NoVehicle", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerNoClip", "GRM_ServerBan_NoClip", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PhysgunPickup", "GRM_ServerBan_NoPhysgun", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("CanTool", "GRM_ServerBan_NoTool", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerUse", "GRM_ServerBan_NoUse", function(ply)
        if banned(ply) then return false end
    end)
    hook.Add("PlayerSpawnObject", "GRM_ServerBan_NoSpawn", function(ply)
        if banned(ply) then return false end
    end)
    for _, name in ipairs({ "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnNPC", "PlayerSpawnVehicle",
        "PlayerSpawnEffect", "PlayerSpawnRagdoll", "PlayerSpawnSWEP", "PlayerGiveSWEP" }) do
        hook.Add(name, "GRM_ServerBan_NoSpawn_" .. name, function(ply)
            if banned(ply) then return false end
        end)
    end
    -- F2/F4 оставляем: это вкладки персонажа/игрового меню и не дают
    -- наказанному игрового преимущества. F1/F3 и служебные окна закрыты.
    for _, name in ipairs({ "ShowHelp", "ShowSpare1" }) do
        hook.Add(name, "GRM_ServerBan_NoMenus_" .. name, function(ply)
            if banned(ply) then return true end
        end)
    end
    -- Урон отбывающему и от него не проходит: наказание, а не арена.
    hook.Add("EntityTakeDamage", "GRM_ServerBan_NoDamage", function(ent, dmg)
        if banned(ent) then return true end
        local att = dmg and dmg:GetAttacker()
        if IsValid(att) and att:IsPlayer() and banned(att) then return true end
    end)
    --[[ Чат остаётся (человеку надо объясниться с админом), но команды —
         нет: иначе через /f4, /inv и прочее он обходит ограничения. ]]
    SB.WaveCommands = {
        ["/fr"] = "рация фракции", ["/frb"] = "рация фракции (OOC)", ["/frooc"] = "рация фракции (OOC)",
        ["/dep"] = "государственная волна", ["/d"] = "государственная волна",
        ["/depb"] = "государственная волна (OOC)", ["/db"] = "государственная волна (OOC)",
        ["/gnews"] = "государственные новости", ["/radio"] = "рация",
        ["/911"] = "экстренный вызов", ["/pcboard"] = "государственная база",
    }

    hook.Add("PlayerSay", "GRM_ServerBan_NoCommands", function(ply, text)
        if not banned(ply) then return end
        local msg = string.Trim(tostring(text or ""))
        if msg:sub(1, 1) ~= "/" and msg:sub(1, 1) ~= "!" then return end
        local cmd = string.lower(string.Explode(" ", msg)[1] or "")
        local wave = SB.WaveCommands[cmd] or SB.WaveCommands["/" .. cmd:sub(2)]
        SB.DenySpeech(ply, wave or "команды")
        return ""
    end)

    hook.Add("PlayerSpawn", "GRM_ServerBan_Respawn", function(ply)
        -- Ждём штатную постановку персонажа на его spawn point. Иначе бан
        -- и Character Core соревнуются: один ставит в зону, другой тут же
        -- переносит на точку появления фракции.
        timer.Simple(0.5, function()
            if not (IsValid(ply) and select(1, SB.IsBanned(ply))) then return end
            if ply:GetNWBool("GRM_CharacterPending", false) then
                ply.GRM_BanAwaitCharacter = true
                return
            end
            ply.GRM_BanAwaitCharacter = nil
            SB.Apply(ply, true)
        end)
    end)
    hook.Add("PlayerDisconnected", "GRM_ServerBan_PauseDisconnect", function(ply)
        SB.Pause(ply)
    end)
    local function freezeEveryone(why)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do SB.Pause(ply) end
        for _, rec in pairs(SB.Bans) do
            if istable(rec) and not rec.paused and not rec.permanent then SB.FreezeRecord(rec, why) end
        end
        if GRM.Save and GRM.Save.Flush then GRM.Save.Flush("serverban.list", why) end
    end
    hook.Add("ShutDown", "GRM_ServerBan_PauseShutdown", function() freezeEveryone("пауза банов: shutdown") end)
    hook.Add("PreCleanupMap", "GRM_ServerBan_PauseCleanup", function() freezeEveryone("пауза банов: смена карты") end)

    hook.Add("PlayerInitialSpawn", "GRM_ServerBan_Join", function(ply)
        timer.Simple(4, function()
            if not IsValid(ply) or not select(1, SB.IsBanned(ply)) then return end
            -- Пока открыт GRM Loading, не телепортируем/не применяем вид:
            -- иначе кнопка «НАЧАТЬ ИГРАТЬ» теряет фокус либо экран закрывает
            -- ban-сторож. Наказание встанет сразу после входного экрана.
            if (GRM.Loading and GRM.Loading.IsLoading and GRM.Loading.IsLoading(ply))
                or ply.GRM_BanAwaitCharacter == true or ply:GetNWBool("GRM_CharacterPending", false) then return end
            SB.Apply(ply, true)
        end)
    end)
    hook.Add("GRM_LoadingFinished", "GRM_ServerBan_AfterLoading", function(ply)
        -- После Loading Screen всегда идёт выбор персонажа. Не применяем
        -- бан между двумя обязательными экранами: Character Menu должно
        -- принять слот и только потом выпустить игрока в деморган.
        if IsValid(ply) and select(1, SB.IsBanned(ply)) then ply.GRM_BanAwaitCharacter = true end
    end)
    hook.Add("GRM_CharacterChanged", "GRM_ServerBan_AfterCharacter", function(ply)
        if IsValid(ply) and select(1, SB.IsBanned(ply)) then
            -- SetActiveSlot вызывает PlayerSpawn; именно его отложенный
            -- обработчик применит бан ПОСЛЕ точки появления персонажа.
            ply.GRM_BanAwaitCharacter = true
        end
    end)

    --[[ Один сторож на всех: держит наказанных внутри зоны, дожимает вид
         (другие модули любят вернуть модель) и снимает истёкшие баны. ]]
    timer.Create("GRM_ServerBan_Watch", 0.5, 0, function()
        local zone = SB.CurrentZone()
        local zonePos = SB.ZonePos(zone)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local isBanned, rec = SB.IsBanned(ply)
                if isBanned then
                    local loading = (GRM.Loading and GRM.Loading.IsLoading and GRM.Loading.IsLoading(ply))
                        or ply.GRM_BanAwaitCharacter == true
                        or ply:GetNWBool("GRM_CharacterPending", false)
                    if not loading then
                        SB.Apply(ply, false)
                        SB.Moan(ply)
                        if rec and not rec.paused and not rec.permanent then
                            rec.remaining = math.ceil(SB.Left(rec))
                            if (rec._persistAt or 0) + 8 <= os.time() then
                                rec._persistAt = os.time()
                                saveBans("тик срока")
                            end
                            SB.SyncClient(ply, rec)
                        end
                    end
                    if zonePos and not loading then
                        local r = zone.radius or 600
                        if ply:GetPos():DistToSqr(zonePos) > r * r then
                            ply:SetPos(zonePos + Vector(0, 0, 8))
                            ply:SetVelocity(-ply:GetVelocity())
                            if GRM.Notify then GRM.Notify(ply, "Выход за пределы зоны запрещён.", 255, 120, 90) end
                        end
                    end
                elseif ply:GetNWBool("GRM_ServerBanned", false)
                    or ply:GetMaterial() == SB.Material
                    or (ply:GetModel() == SB.Model and ply:GetNWString("GRM_PreBanModel", "") ~= "") then
                    -- Следы наказания на свободном игроке — снимаем сами.
                    -- Срок кончился, пока человек был в сети.
                    SB.Clear(ply)
                    if GRM.Notify then GRM.Notify(ply, "Срок бана истёк.", 100, 220, 130) end
                    announce(ply:Nick() .. ": срок бана на сервере истёк")
                end
            end
        end
    end)

    --[[ Стон наказанного. Своего таймера на игрока не заводим — работаем в
         общем стороже: у каждого свой момент следующего звука, поэтому
         толпа скелетов не воет в унисон. ]]
    function SB.Moan(ply)
        if not IsValid(ply) then return false end
        -- Проверка «наказан ли» живёт здесь же: вызвать Moan может кто угодно,
        -- и свободный игрок стонать не должен.
        if not ply:GetNWBool("GRM_ServerBanned", false) then return false end
        if SB.SoundCvar and not SB.SoundCvar:GetBool() then return false end
        local now = CurTime()
        if (ply.GRM_BanNextMoan or 0) > now then return false end
        local minGap = math.max(1, SB.SoundMinCvar and SB.SoundMinCvar:GetFloat() or 4)
        local maxGap = math.max(minGap + 0.5, SB.SoundMaxCvar and SB.SoundMaxCvar:GetFloat() or 9)
        ply.GRM_BanNextMoan = now + math.Rand(minGap, maxGap)

        local path = SB.ZombieSounds[math.random(#SB.ZombieSounds)]
        if GRM.Sound and GRM.Sound.Resolve then
            local resolved = GRM.Sound.Resolve(path)
            if isstring(resolved) and resolved ~= "" then path = resolved end
        end
        ply:EmitSound(path, 80, math.random(85, 105), 0.75, CHAN_VOICE)
        return true, path
    end

    --[[ Прекэш идёт через общий звуковой слой GRM (sh_07_grm_sound.lua):
         там уже есть реестр, фолбэки на отсутствующие файлы и один проход
         на старте карты. Свой прекэш в модуле — это вторая копия логики. ]]

    -------------------------------------------------------------------
    -- КОНСОЛЬ
    -------------------------------------------------------------------
    concommand.Add("grm_ban_point", function(ply, _, args)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local ok, msg = SB.SetZone(ply, ply:GetPos(), tonumber(args and args[1]) or 600)
        ply:ChatPrint("[Бан] " .. tostring(msg))
    end)

    concommand.Add("grm_ban_zone", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local zone = SB.CurrentZone()
        local line = zone and ("[Бан] Точка: " .. tostring(SB.ZonePos(zone)) .. " · радиус " .. zone.radius ..
            " · карта " .. tostring(game.GetMap()))
            or "[Бан] Точка отбывания не задана: встаньте на место и введите grm_ban_point"
        if IsValid(ply) then ply:ChatPrint(line) else print(line) end
    end)

    --[[ Аварийное восстановление: снимает следы наказания с игрока, даже
         если запись бана уже удалена (страховка после старых версий). ]]
    concommand.Add("grm_serverban_fix", function(ply, _, args)
        if IsValid(ply) then
            local can = ply:IsSuperAdmin() or (GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "mod.ban"))
            if not can then return end
        end
        local query = tostring(args and args[1] or "")
        local fixed = 0
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            local ck, ak = characterKey(p), accountKey(p)
            if IsValid(p) and (query == "" or query == "all" or ck == query or ak == query
                or (query == "me" and p == ply)) then
                SB.Bans[ck] = nil
                if SB.Bans[ak] and SB.Bans[ak].legacyAccount then SB.Bans[ak] = nil end
                SB.Clear(p)
                fixed = fixed + 1
            end
        end
        saveBans("аварийное снятие")
        local line = "[Бан] Следы наказания сняты у игроков: " .. fixed
        if IsValid(ply) then ply:ChatPrint(line) else print(line) end
    end)

    --- Разбан из списка: команда принимает SteamID64 забаненного.
    concommand.Add("grm_serverban_unban", function(ply, _, args)
        if IsValid(ply) then
            local can = ply:IsSuperAdmin() or (GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "mod.ban"))
            if not can then return end
        end
        local sid = tostring(args and args[1] or "")
        local ok, msg = SB.Unban(ply, sid)
        local line = "[Бан] " .. tostring(msg or (ok and "снят" or "не снят"))
        if IsValid(ply) then ply:ChatPrint(line) else print(line) end
    end)

    concommand.Add("grm_serverban_list", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        local n = 0
        for sid, rec in pairs(SB.Bans) do
            n = n + 1
            out(("  %s · %s · %s"):format(sid, tostring(rec.name or "?"), SB.Describe(rec)))
        end
        out("[Бан] Отбывают наказание на сервере: " .. n)
    end)

    SB.Load()
    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_ServerBan_Load", "early", function()
            SB.Load()
            for _, ply in ipairs(player.GetAll()) do
                if select(1, SB.IsBanned(ply)) then SB.Apply(ply, true) end
            end
        end, { label = "Баны на сервере" })
    end

    print("[GRM Server Ban] v" .. SB.Version .. " loaded")
end

-----------------------------------------------------------------------
-- КЛИЕНТ: подсветка и плашка «ЗАБАНЕН»
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRM_Ban_Head", { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRM_Ban_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })

    --- Плашку рисует общий слой шапки (GRM.Nameplate), если он включён —
    --- две отрисовки над головой мы уже один раз чинили.
    hook.Add("GRM_NameplateOverride", "GRM_ServerBan_Plate", function(ply, info)
        if not (IsValid(ply) and istable(info)) then return end
        if not ply:GetNWBool("GRM_ServerBanned", false) then return end
        info.name = "ЗАБАНЕН"
        info.nameKnown = false
        info.tag = ply:GetNWString("GRM_ServerBanReason", "")
        info.tagColor = Color(235, 70, 70)
        info.desc = nil
        info.cid = nil
        info.banned = true
        return info
    end)

    -- Если общий слой шапки выключен, рисуем сами — иначе метка пропадёт.
    hook.Add("HUDPaint", "GRM_ServerBan_Fallback", function()
        if GRM.Nameplate and GRM.Nameplate.Active then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply ~= lp and ply:GetNWBool("GRM_ServerBanned", false) then
                local screen = (ply:GetPos() + Vector(0, 0, 84)):ToScreen()
                if screen.visible and lp:GetPos():DistToSqr(ply:GetPos()) < 1200 * 1200 then
                    draw.SimpleText("ЗАБАНЕН", "GRM_Ban_Head", screen.x, screen.y,
                        Color(235, 70, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
                end
            end
        end
    end)

    --[[ Таймер в памятке идёт вживую, как пинг в TAB: значение считается в
         самой отрисовке (os.time() на клиенте), а не приходит с сервера
         пакетом. Раньше цифра выглядела «замороженной» между обновлениями. ]]
    local function banLeftText(lp)
        local until_ = lp:GetNWInt("GRM_ServerBanUntil", 0)
        local stored = lp:GetNWInt("GRM_ServerBanLeft", 0)
        local sync = lp:GetNWInt("GRM_ServerBanSync", 0)
        local left
        if until_ > 0 then
            left = math.max(0, until_ - os.time())
        elseif stored < 0 then
            return "бессрочно", -1
        else
            -- Пауза (рестарт / не тот персонаж): цифра с сервера, часы не тикают.
            left = math.max(0, stored)
            if sync > 0 and until_ > 0 then left = math.max(0, stored - (os.time() - sync)) end
        end
        local m, sec = math.floor(left / 60), left % 60
        if m >= 60 then
            return ("%d ч %02d мин"):format(math.floor(m / 60), m % 60), left
        end
        return ("%02d:%02d"):format(m, sec), left
    end
    SB.LeftText = banLeftText

    -- Самому наказанному — крупная памятка внизу экрана.
    hook.Add("HUDPaint", "GRM_ServerBan_Self", function()
        local lp = LocalPlayer()
        if not (IsValid(lp) and lp:GetNWBool("GRM_ServerBanned", false)) then return end
        local text, left = banLeftText(lp)
        local w, h = 560, 112
        local x, y = ScrW() * 0.5 - w * 0.5, ScrH() - h - 40
        draw.RoundedBox(8, x, y, w, h, Color(28, 10, 12, 235))
        draw.SimpleText("ВЫ ЗАБАНЕНЫ НА СЕРВЕРЕ", "GRM_Ban_Head", x + w * 0.5, y + 22,
            Color(235, 70, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(lp:GetNWString("GRM_ServerBanReason", "нарушение правил"),
            "GRM_Ban_Sub", x + w * 0.5, y + 48, Color(230, 210, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Осталось: " .. text,
            "GRM_Ban_Head", x + w * 0.5, y + 68, left >= 0 and left < 60 and Color(250, 200, 90)
                or Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Меню, инвентарь, оружие и волны недоступны. Ждите решения администрации.",
            "GRM_Ban_Sub", x + w * 0.5, y + 92, Color(170, 160, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    --[[ «Ничего не открывать»: контекстное меню и спавн-меню закрыты хуками,
         а любое окно, которое всё-таки успел открыть сторонний модуль,
         закрывается сторожем. Проверка идёт раз в полсекунды — держать это
         в кадре незачем. ]]
    hook.Add("ContextMenuOpen", "GRM_ServerBan_NoContext", function()
        local lp = LocalPlayer()
        if IsValid(lp) and lp:GetNWBool("GRM_ServerBanned", false) then return false end
    end)
    hook.Add("SpawnMenuOpen", "GRM_ServerBan_NoSpawnMenu", function()
        local lp = LocalPlayer()
        if IsValid(lp) and lp:GetNWBool("GRM_ServerBanned", false) then return false end
    end)

    local nextSweep = 0
    hook.Add("Think", "GRM_ServerBan_CloseWindows", function()
        if CurTime() < nextSweep then return end
        nextSweep = CurTime() + 0.5
        local lp = LocalPlayer()
        if not (IsValid(lp) and lp:GetNWBool("GRM_ServerBanned", false)) then return end
        local world = vgui.GetWorldPanel()
        if not IsValid(world) then return end
        for _, panel in ipairs(world:GetChildren()) do
            --[[ ВАЖНО: только прячем. Раньше здесь стоял panel:Remove(), и
                 вместе с чужими окнами сносилась панель чата (EasyChat) —
                 после снятия бана человек уже не мог ни писать, ни открывать
                 меню, потому что панели физически не существовало. ]]
            local class = IsValid(panel) and panel.GetClassName and string.lower(tostring(panel:GetClassName() or "")) or ""
            local name = IsValid(panel) and panel.GetName and string.lower(tostring(panel:GetName() or "")) or ""
            -- Чат и HUD не трогаем в принципе: наказанному оставлен обычный
            -- чат, а HUD рисует его же памятку.
            local protected = class:find("chat", 1, true) or name:find("chat", 1, true)
                or class:find("hud", 1, true) or name:find("hud", 1, true)
            if IsValid(panel) and not protected and panel:IsVisible() and panel.GetTitle and not panel.GRM_BanAllowed then
                if isfunction(panel.Close) then
                    pcall(panel.Close, panel)
                else
                    panel:SetVisible(false)
                end
                if isfunction(panel.SetMouseInputEnabled) then panel:SetMouseInputEnabled(false) end
                if isfunction(panel.SetKeyboardInputEnabled) then panel:SetKeyboardInputEnabled(false) end
            end
        end
    end)

    -------------------------------------------------------------------
    -- СПИСОК ЗАБАНЕННЫХ (для администрации)
    -------------------------------------------------------------------
    surface.CreateFont("GRM_Ban_List", { font = "Roboto", size = 14, weight = 500, extended = true })

    local function fmtLeft(left)
        if (tonumber(left) or -1) < 0 then return "бессрочно" end
        local m = math.floor(left / 60)
        if m >= 60 then return ("%d ч %02d мин"):format(math.floor(m / 60), m % 60) end
        return ("%02d:%02d"):format(m, left % 60)
    end

    net.Receive(SB.Net.LIST, function()
        local payload = net.ReadTable() or {}
        local rows = istable(payload.bans) and payload.bans or {}
        local history = istable(payload.history) and payload.history or {}

        if IsValid(SB._listFrame) then SB._listFrame:Remove() end
        local frame = vgui.Create("DFrame")
        SB._listFrame = frame
        frame.GRM_BanAllowed = true
        frame:SetSize(math.Clamp(math.floor(ScrW() * 0.55), 780, 1200), math.Clamp(math.floor(ScrH() * 0.7), 520, 900))
        frame:Center()
        frame:SetTitle("")
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(18, 22, 30, 250))
            draw.RoundedBox(8, 0, 0, w, 52, Color(28, 34, 46, 255))
            draw.SimpleText("БАНЫ НА СЕРВЕРЕ", "GRM_Ban_Head", 16, 12, Color(235, 90, 80))
            draw.SimpleText("Отбывают наказание: " .. #rows .. " · записи хранятся между перезапусками",
                "GRM_Ban_List", 16, 34, Color(160, 170, 185))
        end

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(10, 58, 10, 10)

        if #rows == 0 then
            local empty = vgui.Create("DLabel", scroll)
            empty:Dock(TOP) empty:SetTall(28) empty:SetFont("GRM_Ban_List")
            empty:SetTextColor(Color(160, 170, 185))
            empty:SetText("Сейчас никто не отбывает наказание.")
        end

        for _, row in ipairs(rows) do
            local line = vgui.Create("DPanel", scroll)
            line:Dock(TOP) line:SetTall(54) line:DockMargin(0, 0, 0, 6)
            line.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(30, 36, 48, 245))
                draw.SimpleText((row.name ~= "" and row.name or row.sid) ..
                    (row.online and "  · в сети" or "  · не в сети"),
                    "GRM_Ban_Sub", 12, 8, Color(240, 240, 245))
                draw.SimpleText("Причина: " .. (row.reason ~= "" and row.reason or "не указана") ..
                    "  ·  выдал: " .. (row.by ~= "" and row.by or "?"),
                    "GRM_Ban_List", 12, 30, Color(170, 178, 190))
                draw.SimpleText(fmtLeft(row.left), "GRM_Ban_Sub", w - 160, 18, Color(250, 200, 90),
                    TEXT_ALIGN_RIGHT)
            end
            local unban = vgui.Create("DButton", line)
            unban:Dock(RIGHT) unban:SetWide(130) unban:DockMargin(6, 10, 10, 10)
            unban:SetText("")
            unban.Paint = function(self, w, h)
                draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(110, 215, 145) or Color(92, 200, 130))
                draw.SimpleText("РАЗБАНИТЬ", "GRM_Ban_List", w * 0.5, h * 0.5, Color(20, 25, 34),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            unban.DoClick = function()
                RunConsoleCommand("grm_serverban_unban", row.sid)
                frame:Close()
            end
        end

        if #history > 0 then
            local head = vgui.Create("DLabel", scroll)
            head:Dock(TOP) head:SetTall(26) head:DockMargin(0, 10, 0, 4)
            head:SetFont("GRM_Ban_Sub") head:SetTextColor(Color(226, 184, 92))
            head:SetText("История последних наказаний")
            for _, row in ipairs(history) do
                local line = vgui.Create("DLabel", scroll)
                line:Dock(TOP) line:SetTall(20)
                line:SetFont("GRM_Ban_List") line:SetTextColor(Color(160, 170, 185))
                line:SetText(("%s · %s · %s · %s · выдал %s"):format(
                    os.date("%d.%m %H:%M", tonumber(row.t) or 0),
                    row.kind == "unban" and "снят" or "выдан",
                    tostring(row.name ~= "" and row.name or row.sid),
                    tostring(row.reason ~= "" and row.reason or "-"),
                    tostring(row.by or "?")))
            end
        end
    end)

    function SB.OpenList()
        net.Start(SB.Net.LIST_REQ)
        net.SendToServer()
    end
    concommand.Add("grm_serverban_menu", function() SB.OpenList() end)

    print("[GRM Server Ban] client v" .. SB.Version .. " loaded")
end
