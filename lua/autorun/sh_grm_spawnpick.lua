--[[--------------------------------------------------------------------
    GRM Spawn Pick v1.0.0 — выбор точки входа в мир.

    ЗАЧЕМ. Раньше после выбора персонажа игрока просто ставили на
    фракционную точку (или на общую, если фракции нет). Дом не давал
    ничего, кроме расходов, а вернуться туда, где вышел, было нельзя.

    ЧТО ЭТО. Экран после подтверждения персонажа: тёмный фон, по центру
    крупные квадратные слоты со значками и подписями:

              ВЫБЕРИТЕ ТОЧКУ ВХОДА
        [ ФРАКЦИЯ ]  [ ДОМ ]  [ ГДЕ ВЫШЕЛ ]

    ТРИ ИСТОЧНИКА:
      faction — GetSpawnPointForPlayer: должность → подотдел → отдел →
                звание → организация (порядок уже задан осями v5);
      home    — жильё из GRM.Property, где игрок владелец или жилец;
      last    — место, где игрок вышел из игры в прошлый раз.

    ПРАВИЛА, КОТОРЫЕ ДЕЛАЮТ ЭТО ЧЕСТНЫМ:
      • один доступный вариант — экран не показывается вовсе;
      • точка выхода не сохраняется после смерти, в аресте и в лимбе:
        иначе это телепорт в тюрьму;
      • опечатанное жильё и просроченная аренда убирают вариант «Дом»;
      • вне службы фракционная точка недоступна.

    ДАННЫЕ: data/grm_spawnpick.json — ключ CharacterKey.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.SpawnPick = GRM.SpawnPick or {}
local SP = GRM.SpawnPick

SP.Version = "1.0.0"
SP.File = "grm_spawnpick.json"
SP.Data = SP.Data or {}      -- [CharacterKey] = { pos, ang, at, map }

SP.NET = {
    OPEN = "GRM_SpawnPick_Open",
    PICK = "GRM_SpawnPick_Pick",
}

--- Сколько живёт запомненная точка выхода (сутки).
SP.LastLifetime = 86400

-----------------------------------------------------------------------
-- ОБЩАЯ ЧАСТЬ
-----------------------------------------------------------------------

SP.Kinds = {
    { id = "faction", title = "ФРАКЦИЯ", icon = "icon16/shield.png" },
    { id = "home",    title = "ДОМ",     icon = "icon16/house.png" },
    { id = "last",    title = "ГДЕ ВЫШЕЛ", icon = "icon16/flag_blue.png" },
}

local function charKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then
        return tostring(GRM.Identity.CharacterKey(ply) or "")
    end
    if GRM.Char and GRM.Char.GetActiveKey then
        return tostring(GRM.Char.GetActiveKey(ply) or "")
    end
    return IsValid(ply) and (ply:SteamID64() .. ":char1") or ""
end
SP.CharKey = charKey

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(SP.NET.OPEN)
    util.AddNetworkString(SP.NET.PICK)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function SP.Load()
        SP.Data = {}
        if not file.Exists(SP.File, "DATA") then return end
        local t = jsonT(file.Read(SP.File, "DATA") or "")
        if not istable(t) then return end
        -- Протухшие записи не тянем в память: файл не должен расти вечно.
        local now, kept = os.time(), {}
        for key, rec in pairs(t) do
            if istable(rec) and istable(rec.pos)
                and (now - (tonumber(rec.at) or 0)) <= SP.LastLifetime then
                kept[key] = rec
            end
        end
        SP.Data = kept
    end

    --[[ БАГ (жалоба владельца 27.08): «где вышел — не запоминает».
         Сохранение всегда шло через Coalesce с задержкой в секунду. На
         выходе одного игрока это работало, а вот на ShutDown и смене
         карты — нет: сервер умирал раньше, чем срабатывал отложенный
         таймер, и весь накопленный список точек терялся.
         Теперь есть режим immediate: критичные моменты (дисконнект,
         выключение сервера, смена персонажа) пишут файл сразу, а частые
         автоснимки позиции по-прежнему коалесцируются. ]]
    function SP.Save(reason, immediate)
        local function write()
            local ok, txt = pcall(util.TableToJSON, SP.Data or {}, true)
            if ok and txt then file.Write(SP.File, txt)
            else ErrorNoHalt("[GRM SpawnPick] не удалось сохранить (" .. tostring(reason) .. ")\n") end
        end
        if immediate == true then write() return end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_spawnpick_save", 5, write)
        else write() end
    end

    SP.Load()

    -----------------------------------------------------------------
    -- ИСТОЧНИК 1: ФРАКЦИЯ
    -----------------------------------------------------------------
    function SP.FactionPoint(ply)
        if not IsValid(ply) then return nil end
        -- Вне службы сотрудник не появляется в штабе.
        if ply:GetNWBool("GRM_FactionOffDuty", false) then return nil end
        local faction = ply:GetNWString("GRM_Faction", "")
        if faction == "" then return nil end
        if not _G.GetSpawnPointForPlayer then return nil end
        local pos, ang = _G.GetSpawnPointForPlayer(ply)
        if not pos then return nil end

        local label = faction
        if GRM.Factions and GRM.Factions.DisplayName then
            label = GRM.Factions.DisplayName(faction)
        end
        --[[ Подпись уточняем по подразделению: игрок должен понимать,
             куда именно его поставят — в штаб или в свой отдел. ]]
        local dept = ply:GetNWString("GRM_DepartmentDisplay", "")
        if dept ~= "" then label = label .. " · " .. dept end
        return { pos = pos, ang = ang, label = label }
    end

    -----------------------------------------------------------------
    -- ИСТОЧНИК 2: ДОМ
    -----------------------------------------------------------------
    --[[ Жильё игрока из GRM.Property. Берём объект, где он владелец или
         вписан жильцом, с живой арендой и не опечатанный. ]]
    function SP.HomePoint(ply)
        if not IsValid(ply) then return nil end

        --[[ Решение владельца 27.08 (вариант «А»): жильё — это реальные
             квартиры с дверями, и спавн должен быть ВНУТРИ квартиры.

             Раньше точка бралась как центр зоны на mins.z + 8. Зона
             обводится тулом снаружи дома, поэтому центр регулярно
             попадал в стену, на лестничную клетку или под пол. Теперь
             точку ищет модуль жилья: сначала заданную админом, затем пол
             у двери со стороны комнаты, и только в крайнем случае центр
             зоны. ]]
        local HS = GRM.Housing
        if HS and HS.HomeOf and HS.SpawnPoint then
            local rec = HS.HomeOf(ply)
            if rec then
                local pos, ang = HS.SpawnPoint(rec)
                if pos then
                    local name = tostring(rec.name or "")
                    return {
                        pos = pos,
                        ang = ang or Angle(0, 0, 0),
                        label = name ~= "" and name or "Ваше жильё",
                    }
                end
            end
            return nil
        end

        --[[ Запасной путь: модуль жилья почему-то не загрузился. Работаем
             по-старому, чтобы вариант «Дом» не пропал совсем. ]]
        local P = GRM.Property
        if not (P and istable(P.Records)) then return nil end
        local key = charKey(ply)
        if key == "" then return nil end

        for _, rec in pairs(P.Records) do
            local r = P.Normalize and P.Normalize(rec) or rec
            if istable(r) and istable(r.zone) then
                local isHome = r.type == "apartment"
                local mine = (r.ownerType == "character" and r.ownerKey == key)
                if not mine and P.HasAccess then
                    -- Жилец с ключом тоже вправе появляться дома.
                    mine = P.HasAccess(ply, r) == true and r.ownerType ~= "none"
                end
                -- Опечатанный объект и просроченная аренда домом не считаются.
                local sealed = r.sealed == true
                local rentDead = r.tenure == "rent" and (tonumber(r.rentUntil) or 0) > 0
                    and (tonumber(r.rentUntil) or 0) < os.time()
                if isHome and mine and not sealed and not rentDead then
                    local mins, maxs = r.zone.mins, r.zone.maxs
                    if mins and maxs then
                        local center = Vector(
                            (mins.x + maxs.x) * 0.5,
                            (mins.y + maxs.y) * 0.5,
                            mins.z + 8)
                        return { pos = center, ang = Angle(0, 0, 0),
                            label = r.name ~= "" and r.name or "Ваше жильё" }
                    end
                end
            end
        end
        return nil
    end

    -----------------------------------------------------------------
    -- ИСТОЧНИК 3: ГДЕ ВЫШЕЛ
    -----------------------------------------------------------------
    --[[ Запоминать позицию можно не всегда: мёртвый, арестованный или
         сидящий в лимбе игрок не должен «сохранять» это состояние. ]]
    function SP.CanRemember(ply)
        if not IsValid(ply) then return false end
        if ply.GRMCharLimbo then return false end
        if ply.Alive and not ply:Alive() then return false end
        if ply:GetNWBool("GRM_Arrested", false) then return false end
        if ply:GetNWBool("GRM_CharacterPending", false) then return false end
        --[[ Раньше сидящий в машине игрок пропускался целиком — и вся
             поездка не запоминалась. Но позиция машины это ровно то место,
             где человек «вышел»; запоминаем её, просто ставим на землю. ]]
        return true
    end

    --[[ Где именно стоит игрок для целей «где вышел». В транспорте берём
         позицию самой машины и приподнимаем, чтобы не воткнуть в кузов. ]]
    function SP.RememberPos(ply)
        local pos = ply:GetPos()
        if ply.InVehicle and ply:InVehicle() then
            local veh = ply:GetVehicle()
            if IsValid(veh) then
                if GRM.Fuel and GRM.Fuel.RootVehicle then
                    veh = GRM.Fuel.RootVehicle(veh) or veh
                end
                pos = veh:GetPos() + Vector(0, 0, 16)
            end
        end
        return pos
    end

    function SP.Remember(ply, immediate)
        if not SP.CanRemember(ply) then return false end
        local key = charKey(ply)
        if key == "" then return false end
        local pos, ang = SP.RememberPos(ply), ply:EyeAngles()
        SP.Data[key] = {
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { y = ang.y or 0 },
            at = os.time(),
            map = string.lower(game.GetMap() or ""),
        }
        SP.Save("remember", immediate)
        return true
    end

    --[[ Не даём вернуться в чужое закрытое помещение: игрок мог выйти
         в чужом доме или на закрытой территории, и точка выхода стала бы
         способом попасть туда в обход дверей. ]]
    function SP.PointAllowed(ply, pos)
        local P = GRM.Property
        if not (P and istable(P.Records) and P.IsInside) then return true end
        for _, rec in pairs(P.Records) do
            local r = P.Normalize and P.Normalize(rec) or rec
            if istable(r) and istable(r.zone) and P.IsInside(r, pos) then
                if r.sealed == true then return false end
                if r.ownerType ~= "none" and P.HasAccess and not P.HasAccess(ply, r) then
                    return false
                end
            end
        end
        return true
    end

    --[[ Почему точка выхода недоступна. Возвращает точку ИЛИ причину
         отказа — чтобы «где вышел не работает» можно было диагностировать
         командой, а не гаданием (жалоба владельца 28.08). ]]
    function SP.LastPointWhy(ply)
        local key = charKey(ply)
        if key == "" then return nil, "нет ключа персонажа" end
        local rec = SP.Data[key]
        if not istable(rec) then
            return nil, "нет записи для " .. key .. " (всего записей: "
                .. table.Count(SP.Data or {}) .. ")"
        end
        if not istable(rec.pos) then return nil, "запись без координат" end

        --[[ Карту сравниваем в нижнем регистре С ОБЕИХ сторон. Записи,
             сделанные до этой правки, могли лечь с исходным регистром
             имени карты, и тогда точка молча отбраковывалась. ]]
        local recMap = string.lower(tostring(rec.map or ""))
        local curMap = string.lower(game.GetMap() or "")
        if recMap ~= "" and recMap ~= curMap then
            return nil, "точка с другой карты (" .. recMap .. " вместо " .. curMap .. ")"
        end

        local age = os.time() - (tonumber(rec.at) or 0)
        if age > SP.LastLifetime then
            return nil, "точка протухла (" .. math.floor(age / 3600) .. " ч назад)"
        end

        local pos = Vector(tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0,
            tonumber(rec.pos.z) or 0)
        if not SP.PointAllowed(ply, pos) then
            return nil, "точка внутри чужого закрытого помещения"
        end
        return {
            pos = pos,
            ang = Angle(0, (rec.ang and tonumber(rec.ang.y)) or 0, 0),
            label = "Последнее место",
        }
    end

    function SP.LastPoint(ply)
        return (SP.LastPointWhy(ply))
    end

    -----------------------------------------------------------------
    -- ВАРИАНТЫ И ВЫДАЧА
    -----------------------------------------------------------------
    function SP.Options(ply)
        local out = {}
        local faction = SP.FactionPoint(ply)
        if faction then out[#out + 1] = { id = "faction", title = "ФРАКЦИЯ", label = faction.label } end
        local home = SP.HomePoint(ply)
        if home then out[#out + 1] = { id = "home", title = "ДОМ", label = home.label } end
        local last = SP.LastPoint(ply)
        if last then out[#out + 1] = { id = "last", title = "ГДЕ ВЫШЕЛ", label = last.label } end
        return out
    end

    function SP.Resolve(ply, kind)
        kind = tostring(kind or "")
        if kind == "faction" then return SP.FactionPoint(ply) end
        if kind == "home" then return SP.HomePoint(ply) end
        if kind == "last" then return SP.LastPoint(ply) end
        return nil
    end

    --[[ Применить выбор точки.

         ГЛАВНОЕ ИЗМЕНЕНИЕ (жалоба владельца 27.08 «нажми любую — ничего
         не происходит»): раньше здесь просто делался SetPos игроку,
         который УЖЕ стоял в мире. Следом отрабатывали хуки PlayerSpawn
         (SpawnAtFactionPoint, GRM_Char_PlaceAfterSelect) и возвращали
         его обратно — выбор визуально не срабатывал.

         Теперь при первичном входе точка не применяется напрямую, а
         передаётся конвейеру: он сам заспавнит игрока и поставит его
         куда надо ПОСЛЕДНИМ действием, так что перетирать уже некому. ]]
    function SP.Apply(ply, kind)
        local point = SP.Resolve(ply, kind)
        if not point then return false end

        ply.GRMSpawnPickDone = true

        local E = GRM.Entry
        if E and E.InProgress and E.InProgress(ply) then
            -- Первичный вход: мир игрок увидит только сейчас.
            E.ToWorld(ply, point)
            hook.Run("GRM_SpawnPicked", ply, kind, point.pos)
            return true
        end

        -- Игрок уже в мире (смена персонажа, админ-телепорт) — ставим сразу.
        ply:SetPos(point.pos)
        if point.ang then ply:SetEyeAngles(Angle(0, point.ang.y or 0, 0)) end
        hook.Run("GRM_SpawnPicked", ply, kind, point.pos)
        return true
    end

    --[[ Кому экран выбора не положен вообще.

         НАЙДЕНО ПРИ РАЗБОРЕ (смежный баг того же класса): арестованного
         игрока модуль ареста ставит в камеру на спавне, а следом мы
         предлагали ему «выберите точку входа» — и он спокойно уходил из
         камеры домой или в штаб. Побег в один клик. ]]
    function SP.Blocked(ply)
        if not IsValid(ply) then return true end
        if ply:GetNWBool("GRM_Arrested", false) then return true end
        if ply:GetNWBool("GRM_911_Downed", false) then return true end

        --[[ ВАЖНО. На стадии выбора точки игрок ПО ЗАМЫСЛУ ещё сидит в
             лимбе и формально «не подтверждён» для остальных модулей —
             мира он не видит. Поэтому лимб и pending здесь не считаются
             блокировкой: иначе экран точек не показался бы никогда, а
             это ровно то, ради чего вся стадия и существует. ]]
        local E = GRM.Entry
        if E and E.StageOf(ply) == E.Stages.spawnpoint then return false end

        if ply:GetNWBool("GRM_CharacterPending", false) then return true end
        if ply.GRMCharLimbo == true then return true end
        return false
    end

    --[[ Показать экран выбора. Возвращает true, если экран действительно
         нужен: при одном варианте выбирать нечего, ставим сразу. ]]
    function SP.Offer(ply)
        if not IsValid(ply) then return false end
        if SP.Blocked(ply) then return false end
        local options = SP.Options(ply)
        if #options == 0 then return false end
        if #options == 1 then
            SP.Apply(ply, options[1].id)
            return false
        end
        ply.GRMSpawnPickPending = true
        net.Start(SP.NET.OPEN)
            net.WriteTable(options)
        net.Send(ply)
        return true
    end

    net.Receive(SP.NET.PICK, function(_, ply)
        if not IsValid(ply) then return end
        if not ply.GRMSpawnPickPending then return end
        -- Состояние могло измениться, пока экран висел (успели арестовать).
        if SP.Blocked(ply) then ply.GRMSpawnPickPending = nil return end
        local kind = net.ReadString()
        -- Выбрать можно только реально доступный вариант.
        local allowed = false
        for _, opt in ipairs(SP.Options(ply)) do
            if opt.id == kind then allowed = true break end
        end
        if not allowed then return end
        ply.GRMSpawnPickPending = nil
        SP.Apply(ply, kind)
    end)

    -----------------------------------------------------------------
    -- ВСТРАИВАНИЕ В ЖИЗНЕННЫЙ ЦИКЛ
    -----------------------------------------------------------------
    --[[ Экран точек показывает конвейер входа (GRM.Entry.ToSpawnPoint),
         строго между выбором персонажа и появлением в мире. Свой хук на
         GRM_CharacterConfirmed здесь БЫЛ и убран: он открывал экран уже
         после того, как игрок стоял на карте, и его выбор перетирался.

         Оставлен только запасной путь: если конвейер почему-то не
         загрузился, экран всё равно предложим — но с задержкой, чтобы
         не спорить с чужим спавном. ]]
    hook.Add("GRM_CharacterConfirmed", "GRM_SpawnPick_Fallback", function(ply)
        if GRM.Entry and GRM.Entry.ToSpawnPoint then return end
        timer.Simple(0.4, function()
            if IsValid(ply) then SP.Offer(ply) end
        end)
    end)

    -- Запоминаем место выхода. Дисконнект — пишем на диск немедленно.
    hook.Add("PlayerDisconnected", "GRM_SpawnPick_Remember", function(ply)
        SP.Remember(ply, true)
    end)

    --[[ АВТОСНИМОК ПОЗИЦИИ.

         Одного PlayerDisconnected мало: при падении сервера, вылете
         игрока по таймауту или жёсткой смене карты хук может не успеть
         отработать, и точка выхода теряется — ровно то, на что жаловался
         владелец («где вышел — не запоминает»). Поэтому раз в 30 секунд
         тихо запоминаем, где игрок сейчас. В худшем случае вернётся туда,
         где был полминуты назад, а не «никуда». Запись на диск при этом
         коалесцируется, так что на 30 игроков это один file.Write. ]]
    SP.SnapshotInterval = 30
    --[[ Снимок позиций — low и порционно. Раньше раз в 30 секунд разом
         обходились ВСЕ игроки: на большом онлайне это заметный пик в
         одном тике. Теперь тот же круг размазан по кадрам. ]]
    local function snapshotList()
        return (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
    end
    if GRM.Sched then
        GRM.Sched.EverySpread("spawnpick.snapshot", SP.SnapshotInterval, snapshotList,
            function(ply) SP.Remember(ply, false) end, { prio = "low", chunk = 6 })
    else
        timer.Create("GRM_SpawnPick_Snapshot", SP.SnapshotInterval, 0, function()
            for _, ply in ipairs(snapshotList()) do SP.Remember(ply, false) end
        end)
    end

    --[[ ЗАПОМИНАНИЕ ПЕРЕД СМЕРТЬЮ.

         Мёртвый игрок точку не сохраняет (иначе спавн на собственном
         трупе). Но и терять место гибели нельзя: человек умер, вышел, а
         при возвращении «где вышел» указывало бы на позицию получасовой
         давности либо не существовало вовсе. Запоминаем ПОСЛЕДНЕЕ живое
         положение прямо перед смертью. ]]
    hook.Add("PlayerDeath", "GRM_SpawnPick_RememberBeforeDeath", function(ply)
        if not IsValid(ply) then return end
        if ply.GRMCharLimbo or ply:GetNWBool("GRM_Arrested", false) then return end
        local key = charKey(ply)
        if key == "" then return end
        local pos = SP.RememberPos(ply)
        SP.Data[key] = {
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { y = (ply:EyeAngles().y) or 0 },
            at = os.time(),
            map = string.lower(game.GetMap() or ""),
        }
        SP.Save("death", false)
    end)
    -- И при смене персонажа: у каждого своё место.
    hook.Add("GRM_CharacterChanged", "GRM_SpawnPick_RememberSwap", function(ply, oldKey)
        if not (IsValid(ply) and isstring(oldKey) and oldKey ~= "") then return end
        if not SP.CanRemember(ply) then return end
        local pos, ang = ply:GetPos(), ply:EyeAngles()
        SP.Data[oldKey] = {
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { y = ang.y or 0 },
            at = os.time(),
            map = string.lower(game.GetMap() or ""),
        }
        SP.Save("swap", true)
    end)

    --[[ Выключение сервера: собираем всех и пишем ОДИН раз напрямую.
         Отложенная запись здесь не работает — процесс уже умирает. ]]
    hook.Add("ShutDown", "GRM_SpawnPick_SaveAll", function()
        for _, ply in ipairs(player.GetAll()) do SP.Remember(ply, false) end
        SP.Save("shutdown", true)
    end)

    --- Диагностика: grm_spawnpick
    concommand.Add("grm_spawnpick", function(ply)
        if not IsValid(ply) then return end
        local function say(t) ply:PrintMessage(HUD_PRINTTALK, t) end
        local options = SP.Options(ply)
        say("[Точка входа] доступно вариантов: " .. #options)
        for _, opt in ipairs(options) do
            say("  " .. opt.title .. " — " .. tostring(opt.label))
        end

        --[[ Разбор именно «где вышел»: владелец жаловался, что вариант не
             работает, а по одному списку вариантов причину не понять. ]]
        local key = charKey(ply)
        say("  ключ персонажа: " .. (key ~= "" and key or "ПУСТОЙ"))
        say("  записей в базе: " .. table.Count(SP.Data or {})
            .. " · карта: " .. string.lower(game.GetMap() or ""))
        local pt, why = SP.LastPointWhy(ply)
        if pt then
            say(("  «где вышел»: %.0f %.0f %.0f"):format(pt.pos.x, pt.pos.y, pt.pos.z))
        else
            say("  «где вышел» НЕДОСТУПНО: " .. tostring(why))
        end
        local mine = SP.Data[key]
        if istable(mine) then
            say(("  запись: карта %s, возраст %d мин"):format(
                tostring(mine.map), math.floor((os.time() - (tonumber(mine.at) or 0)) / 60)))
        end
    end)

    --- Принудительно запомнить текущую позицию (проверка на живом сервере).
    concommand.Add("grm_spawnpick_save", function(ply)
        if not IsValid(ply) then return end
        local okSave = SP.Remember(ply, true)
        ply:PrintMessage(HUD_PRINTTALK, okSave
            and "[Точка входа] Текущее место запомнено."
            or "[Точка входа] Сейчас запоминать нельзя (лимб, смерть или арест).")
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("spawnpick", {
            label = "Точки входа",
            version = SP.Version,
            Status = function() return "запомнено мест: " .. tostring(table.Count(SP.Data or {})) end,
            Depends = { "factions" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMSpawn_Title", { font = "Roboto", size = 30, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMSpawn_Slot",  { font = "Roboto", size = 18, weight = 700, extended = true, antialias = true })
    surface.CreateFont("GRMSpawn_Sub",   { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })

    local C = {
        text   = Color(238, 243, 250),
        dim    = Color(150, 163, 180),
        gold   = Color(245, 198, 70),
        slot   = Color(26, 33, 45, 250),
        slotH  = Color(38, 50, 68, 250),
        border = Color(60, 74, 96),
    }

    local frame

    local function openPick(options)
        if IsValid(frame) then frame:Remove() end

        local f = vgui.Create("DFrame")
        frame = f
        f:SetSize(ScrW(), ScrH())
        f:SetPos(0, 0)
        f:MakePopup()
        f:SetTitle("")
        f:ShowCloseButton(false)
        f:SetDraggable(false)
        -- Экран обязательный: закрыть его нельзя, пока точка не выбрана.
        f.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then return true end end
        f.Paint = function(_, w, h)
            -- Тёмный фон, как просил владелец.
            draw.RoundedBox(0, 0, 0, w, h, Color(6, 8, 13, 245))
            draw.SimpleText("ВЫБЕРИТЕ ТОЧКУ ВХОДА", "GRMSpawn_Title", w / 2, h / 2 - 170,
                C.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Откуда ваш персонаж начнёт эту смену", "GRMSpawn_Sub",
                w / 2, h / 2 - 138, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Крупные квадратные слоты по центру.
        local size, gap = 190, 26
        local total = #options * size + (#options - 1) * gap
        local startX = ScrW() / 2 - total / 2
        local y = ScrH() / 2 - size / 2 + 10

        for i, opt in ipairs(options) do
            local x = startX + (i - 1) * (size + gap)
            local btn = vgui.Create("DButton", f)
            btn:SetText("")
            btn:SetPos(x, y)
            btn:SetSize(size, size)

            local mat
            for _, kind in ipairs(GRM.SpawnPick.Kinds) do
                if kind.id == opt.id then mat = Material(kind.icon, "smooth") break end
            end

            btn.Paint = function(self, w, h)
                local hovered = self:IsHovered()
                draw.RoundedBox(10, 0, 0, w, h, hovered and C.slotH or C.slot)
                surface.SetDrawColor(hovered and C.gold or C.border)
                surface.DrawOutlinedRect(0, 0, w, h, hovered and 2 or 1)
                if mat then
                    surface.SetMaterial(mat)
                    surface.SetDrawColor(hovered and C.gold or C.text)
                    surface.DrawTexturedRect(w / 2 - 24, 42, 48, 48)
                end
                draw.SimpleText(opt.title, "GRMSpawn_Slot", w / 2, h - 62,
                    hovered and C.gold or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                -- Подпись поясняет, куда именно поставят.
                draw.SimpleText(tostring(opt.label or ""), "GRMSpawn_Sub", w / 2, h - 36,
                    C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            btn.DoClick = function()
                surface.PlaySound("buttons/button14.wav")
                net.Start(GRM.SpawnPick.NET.PICK)
                    net.WriteString(opt.id)
                net.SendToServer()
                f:Remove()
            end
        end
    end

    net.Receive(GRM.SpawnPick.NET.OPEN, function()
        local options = net.ReadTable() or {}
        if #options == 0 then return end
        openPick(options)
    end)
end
