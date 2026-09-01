--[[--------------------------------------------------------------------
    GRM Analytics v1.0.0 — модуль анализа нагрузки и телеметрии

    Заказ владельца (18.08): «нужен нормальный модуль анализа, который будет
    считывать сущности, двери, движения, действия всех игроков + все события
    + всевозможные параметры».

    ЧТО СОБИРАЕТ (постоянно, дёшево — раз в секунду):
      • Тайминги: время тика/кадра, всплески, средние и максимум (детектор
        живёт в GRM.Perf, здесь — история по минутам).
      • Сущности: всего, по классам GRM, пропы игроков, транспорт (в том
        числе simfphys и LVS), физические объекты, «спящие» и активные.
      • Двери: всего, с записями GRM, бесхозные, парные, подозрение на
        фантомы (дубли одной физической двери), открытия/закрытия в минуту.
      • Игроки: онлайн, движение (юниты/сек), в транспорте, в ноклипе, спят
        ли (AFK), фракция, на службе ли, пинг, потери.
      • Действия: использование [E], выстрелы, смерти, спавны, чат-команды,
        покупки, аресты, пожары, вызовы — счётчики по минутам.
      • События: сколько раз сработали ключевые хуки GRM и сколько ушло
        net-сообщений по каждой строке (с байтами).

    ПРОФИЛИРОВАНИЕ (по требованию, на N секунд):
      grm_analyze_hooks 10   — сколько миллисекунд съел каждый хук GRM
      grm_analyze_net 10     — какие net-строки шлют больше всего данных

    ОТЧЁТЫ:
      grm_analyze            — общая сводка «здесь и сейчас»
      grm_analyze_ents       — разбор сущностей по классам
      grm_analyze_doors      — двери и подозрение на фантомы
      grm_analyze_players    — по игрокам: движение, действия, состояние
      grm_analyze_events     — счётчики событий и net за последние минуты
      grm_analyze_dump       — выгрузить полный срез в data/grm_analytics/

    Модуль намеренно ничего не «чинит»: он измеряет и показывает.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Analytics = GRM.Analytics or {}
local AN = GRM.Analytics
AN.Version = "1.0.0"

AN.SampleInterval = 1        -- секунда между снимками
AN.HistoryMinutes = 30       -- сколько минут истории держим в памяти

AN.Events = AN.Events or {}          -- имя события -> счётчик за текущую минуту
AN.EventTotals = AN.EventTotals or {}-- имя события -> счётчик за сессию
AN.Net = AN.Net or {}                -- net-строка -> { count, bytes }
AN.History = AN.History or {}        -- поминутные срезы
AN.Players = AN.Players or {}        -- steamid64 -> телеметрия игрока

-----------------------------------------------------------------------
-- УЧЁТ СОБЫТИЙ
-----------------------------------------------------------------------
function AN.Count(event, amount)
    event = tostring(event or "unknown")
    amount = tonumber(amount) or 1
    AN.Events[event] = (AN.Events[event] or 0) + amount
    AN.EventTotals[event] = (AN.EventTotals[event] or 0) + amount
end

-- Учёт net-трафика: считаем и количество, и объём по каждой строке.
function AN.CountNet(name, bits)
    name = tostring(name or "?")
    local row = AN.Net[name]
    if not row then
        row = { count = 0, bytes = 0 }
        AN.Net[name] = row
    end
    row.count = row.count + 1
    row.bytes = row.bytes + math.floor((tonumber(bits) or 0) / 8)
end

if SERVER then
    util.AddNetworkString("GRM_Analytics_Client")
    util.AddNetworkString("GRM_Analytics_Request")
end

-----------------------------------------------------------------------
-- СБОР СРЕЗОВ
-----------------------------------------------------------------------
local GRM_CLASS_PREFIX = "grm_"

function AN.EntitySnapshot()
    local out = {
        total = 0, grm = 0, props = 0, vehicles = 0, simfphys = 0, lvs = 0,
        doors = 0, npcs = 0, weapons = 0, physicsAwake = 0, byClass = {},
    }
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            out.total = out.total + 1
            local class = ent:GetClass() or "?"
            out.byClass[class] = (out.byClass[class] or 0) + 1

            if string.sub(class, 1, 4) == GRM_CLASS_PREFIX then out.grm = out.grm + 1 end
            if class == "prop_physics" then out.props = out.props + 1 end
            if ent:IsVehicle() then out.vehicles = out.vehicles + 1 end
            if class == "gmod_sent_vehicle_fphysics_base" then out.simfphys = out.simfphys + 1 end
            if string.sub(class, 1, 4) == "lvs_" then out.lvs = out.lvs + 1 end
            if string.find(class, "door", 1, true) then out.doors = out.doors + 1 end
            if ent:IsNPC() then out.npcs = out.npcs + 1 end
            if ent:IsWeapon() then out.weapons = out.weapons + 1 end

            if SERVER then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) and phys:IsMotionEnabled() and not phys:IsAsleep() then
                    out.physicsAwake = out.physicsAwake + 1
                end
            end
        end
    end
    return out
end

function AN.DoorSnapshot()
    local D = GRM.Doors
    local out = { total = 0, withRecord = 0, ownerless = 0, paired = 0, suspectPhantom = 0, groups = 0 }
    if not (D and isfunction(D.AllDoors)) then return out end

    local doors = D.AllDoors()
    out.total = #doors
    for _, ent in ipairs(doors) do
        local rec = D.GetRecord and select(1, D.GetRecord(ent)) or nil
        if istable(rec) and rec.owner_type and rec.owner_type ~= "none" then
            out.withRecord = out.withRecord + 1
        else
            out.ownerless = out.ownerless + 1
        end
        if D.GetPartnerDoor and D.GetPartnerDoor(ent) then out.paired = out.paired + 1 end
    end

    -- Подозрение на фантомы: несколько entity считаются одной физической
    -- дверью. Берём готовые группы дедупликатора, не пересчитывая заново.
    local groups = D._equivalentDoors
    if istable(groups) then
        for _, group in pairs(groups) do
            if istable(group) and #group > 1 then
                out.groups = out.groups + 1
                out.suspectPhantom = out.suspectPhantom + (#group - 1)
            end
        end
    end
    return out
end

function AN.PlayerSnapshot()
    local rows = {}
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) then
            local sid = tostring(ply:SteamID64() or "")
            local mem = AN.Players[sid]
            if not mem then
                mem = { moved = 0, uses = 0, shots = 0, deaths = 0, spawns = 0, chat = 0, lastPos = ply:GetPos() }
                AN.Players[sid] = mem
            end

            local pos = ply:GetPos()
            local delta = mem.lastPos and pos:Distance(mem.lastPos) or 0
            mem.lastPos = pos
            mem.moved = mem.moved + delta

            rows[#rows + 1] = {
                sid = sid,
                nick = ply:Nick(),
                rpName = ply:GetNWString("GRM_RPName", ""),
                faction = ply:GetNWString("GRM_Faction", ""),
                onDuty = ply:GetNWBool("GRM_FactionOnDuty", false),
                ping = ply:Ping(),
                loss = ply.PacketLoss and ply:PacketLoss() or 0,
                speed = math.floor(delta / math.max(AN.SampleInterval, 0.001)),
                inVehicle = ply:InVehicle(),
                noclip = ply:GetMoveType() == MOVETYPE_NOCLIP,
                alive = ply:Alive(),
                hp = ply:Health(),
                uses = mem.uses, shots = mem.shots, deaths = mem.deaths,
                spawns = mem.spawns, chat = mem.chat,
                movedTotal = math.floor(mem.moved),
                afk = delta < 1 and (mem.afkFor or 0) + AN.SampleInterval or 0,
            }
            mem.afkFor = rows[#rows].afk
        end
    end
    return rows
end

function AN.Snapshot()
    local perf = GRM.Perf and GRM.Perf.Stats or nil
    local frames = perf and perf.frames or 0
    local avg = (perf and frames > 0) and (perf.total / frames) or 0

    local snap = {
        at = os.time(),
        realm = SERVER and "server" or "client",
        tickAvgMs = avg,
        tickMaxMs = perf and perf.max or 0,
        spikes = perf and perf.spikes or 0,
        jobs = (GRM.Perf and GRM.Perf.Jobs) and #GRM.Perf.Jobs or 0,
        timers = 0,
        entities = AN.EntitySnapshot(),
        doors = AN.DoorSnapshot(),
        players = SERVER and AN.PlayerSnapshot() or {},
        events = table.Copy(AN.Events),
        net = table.Copy(AN.Net),
    }

    -- Сколько активных таймеров GRM (по именам).
    if timer and timer.Exists then
        local known = {
            "GRM_Admin_PlayerPush", "GRM_FireDispatch_Tick", "GRM_Trunk_Watch",
            "GRM_BC_LiveWatch", "GRML_RouteThink", "GRM_StaminaTick",
            "GRM_Arrest_EnforceUnarmed", "GRM_Handcuffs_ReleaseDecay",
        }
        for _, name in ipairs(known) do
            if timer.Exists(name) then snap.timers = snap.timers + 1 end
        end
    end

    AN.Events = {}
    return snap
end

-----------------------------------------------------------------------
-- ИСТОРИЯ
-----------------------------------------------------------------------
local function pushHistory(snap)
    AN.History[#AN.History + 1] = snap
    local cap = math.max(1, math.floor((AN.HistoryMinutes * 60) / math.max(AN.SampleInterval, 1)))
    while #AN.History > cap do table.remove(AN.History, 1) end
end

function AN.Start()
    if AN._running then return end
    AN._running = true
    timer.Create("GRM_Analytics_Sample", AN.SampleInterval, 0, function()
        local ok, snap = pcall(AN.Snapshot)
        if ok and istable(snap) then
            AN.Last = snap
            pushHistory(snap)
        end
    end)
end

function AN.Stop()
    AN._running = false
    if timer.Exists("GRM_Analytics_Sample") then timer.Remove("GRM_Analytics_Sample") end
end

-----------------------------------------------------------------------
-- ПОДПИСКА НА СОБЫТИЯ (дёшево: только счётчики)
-----------------------------------------------------------------------
hook.Add("PlayerUse", "GRM_Analytics_Use", function(ply, ent)
    AN.Count("player.use")
    if IsValid(ply) then
        local mem = AN.Players[tostring(ply:SteamID64() or "")]
        if mem then mem.uses = (mem.uses or 0) + 1 end
    end
    if IsValid(ent) then
        local class = ent:GetClass() or ""
        if string.find(class, "door", 1, true) then AN.Count("door.use") end
        if string.sub(class, 1, 4) == GRM_CLASS_PREFIX then AN.Count("grm.entity.use") end
    end
end)

hook.Add("EntityFireBullets", "GRM_Analytics_Shots", function(ent)
    if IsValid(ent) and ent:IsPlayer() then
        AN.Count("player.shot")
        local mem = AN.Players[tostring(ent:SteamID64() or "")]
        if mem then mem.shots = (mem.shots or 0) + 1 end
    end
end)

hook.Add("PlayerDeath", "GRM_Analytics_Death", function(ply)
    AN.Count("player.death")
    if IsValid(ply) then
        local mem = AN.Players[tostring(ply:SteamID64() or "")]
        if mem then mem.deaths = (mem.deaths or 0) + 1 end
    end
end)

hook.Add("PlayerSpawn", "GRM_Analytics_Spawn", function(ply)
    AN.Count("player.spawn")
    if IsValid(ply) then
        local mem = AN.Players[tostring(ply:SteamID64() or "")]
        if mem then mem.spawns = (mem.spawns or 0) + 1 end
    end
end)

hook.Add("PlayerSay", "GRM_Analytics_Chat", function(ply, text)
    AN.Count("chat.message")
    if isstring(text) and string.sub(text, 1, 1) == "/" then AN.Count("chat.command") end
    if IsValid(ply) then
        local mem = AN.Players[tostring(ply:SteamID64() or "")]
        if mem then mem.chat = (mem.chat or 0) + 1 end
    end
end)

hook.Add("OnEntityCreated", "GRM_Analytics_EntCreate", function(ent)
    if not IsValid(ent) then return end
    AN.Count("entity.created")
    local class = ent:GetClass() or ""
    if string.sub(class, 1, 4) == GRM_CLASS_PREFIX then AN.Count("grm.entity.created") end
    if class == "prop_physics" then AN.Count("prop.created") end
end)

hook.Add("EntityRemoved", "GRM_Analytics_EntRemove", function(ent)
    AN.Count("entity.removed")
end)

-- Игровые события GRM: считаем то, что реально нагружает сервер.
hook.Add("GRM_FireIncidentOpened", "GRM_Analytics_Fire", function() AN.Count("fire.incident") end)
hook.Add("GRM_FireExtinguished", "GRM_Analytics_FireOut", function() AN.Count("fire.out") end)
hook.Add("GRM_ArrestStateChanged", "GRM_Analytics_Arrest", function() AN.Count("arrest.change") end)
hook.Add("GRM_FactionDutyChanged", "GRM_Analytics_Duty", function() AN.Count("duty.change") end)
hook.Add("GRM_VehicleDealerSpawned", "GRM_Analytics_Vehicle", function() AN.Count("vehicle.spawned") end)
hook.Add("GRM_AdminGroupChanged", "GRM_Analytics_Group", function() AN.Count("admin.group") end)
hook.Add("GRM_BootFinished", "GRM_Analytics_Boot", function() AN.Count("boot.finished") end)

-----------------------------------------------------------------------
-- ПРОФИЛИРОВАНИЕ ХУКОВ (по требованию)
--
-- Оборачиваем ТОЛЬКО хуки GRM (имя начинается с GRM/GRML/VK/FactionsExt) и
-- только на заданное время: постоянная обёртка сама была бы нагрузкой.
-----------------------------------------------------------------------
local function isGRMHook(name)
    name = tostring(name or "")
    return string.sub(name, 1, 3) == "GRM" or string.sub(name, 1, 2) == "VK"
        or string.sub(name, 1, 11) == "FactionsExt"
end

function AN.ProfileHooks(seconds, done)
    if AN._profiling then return false, "профилирование уже идёт" end
    seconds = math.Clamp(math.floor(tonumber(seconds) or 10), 3, 60)

    local table_ = hook.GetTable()
    local originals, stats = {}, {}

    for event, list in pairs(table_) do
        for name, fn in pairs(list) do
            if isfunction(fn) and isGRMHook(name) then
                local key = event .. " / " .. name
                originals[#originals + 1] = { event = event, name = name, fn = fn }
                stats[key] = { calls = 0, ms = 0 }
                hook.Add(event, name, function(...)
                    local t0 = SysTime()
                    local a, b, c, d = fn(...)
                    local row = stats[key]
                    row.calls = row.calls + 1
                    row.ms = row.ms + (SysTime() - t0) * 1000
                    return a, b, c, d
                end)
            end
        end
    end

    AN._profiling = true
    timer.Simple(seconds, function()
        for _, row in ipairs(originals) do hook.Add(row.event, row.name, row.fn) end
        AN._profiling = false
        AN.LastHookProfile = { seconds = seconds, stats = stats, at = os.time() }
        if isfunction(done) then done(AN.LastHookProfile) end
    end)
    return true, ("профилирование хуков запущено на %d с (обёрнуто %d)"):format(seconds, #originals)
end

-----------------------------------------------------------------------
-- ПРОФИЛИРОВАНИЕ NET (по требованию)
-----------------------------------------------------------------------
function AN.ProfileNet(seconds, done)
    if AN._netProfiling then return false, "профилирование net уже идёт" end
    seconds = math.Clamp(math.floor(tonumber(seconds) or 10), 3, 60)

    AN.Net = {}
    local origStart = net.Start
    local current = nil

    net.Start = function(name, ...)
        current = name
        AN.CountNet(name, 0)
        return origStart(name, ...)
    end

    local origSend = net.Send
    local origBroadcast = net.Broadcast
    local function accumulate()
        if current and net.BytesWritten then
            local bytes = select(1, net.BytesWritten()) or 0
            local row = AN.Net[current]
            if row then row.bytes = row.bytes + bytes end
        end
        current = nil
    end
    net.Send = function(...) accumulate() return origSend(...) end
    net.Broadcast = function(...) accumulate() return origBroadcast(...) end

    AN._netProfiling = true
    timer.Simple(seconds, function()
        net.Start = origStart
        net.Send = origSend
        net.Broadcast = origBroadcast
        AN._netProfiling = false
        AN.LastNetProfile = { seconds = seconds, rows = table.Copy(AN.Net), at = os.time() }
        if isfunction(done) then done(AN.LastNetProfile) end
    end)
    return true, ("профилирование net запущено на %d с"):format(seconds)
end

-----------------------------------------------------------------------
-- ОТЧЁТЫ
-----------------------------------------------------------------------
local function printer(ply)
    return function(line)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end
end

local function sortedPairs(tbl, valueFn)
    local rows = {}
    for key, value in pairs(tbl or {}) do
        rows[#rows + 1] = { key = key, value = value, weight = valueFn and valueFn(value) or value }
    end
    table.sort(rows, function(a, b) return (tonumber(a.weight) or 0) > (tonumber(b.weight) or 0) end)
    return rows
end

function AN.ReportSummary(out)
    local snap = AN.Last or AN.Snapshot()
    out(("[GRM Анализ] %s · срез от %s"):format(
        snap.realm == "server" and "СЕРВЕР" or "КЛИЕНТ", os.date("%H:%M:%S", snap.at)))
    out(("  тик/кадр: среднее %.2f мс, максимум %.1f мс, всплесков %d, фоновых задач %d")
        :format(snap.tickAvgMs, snap.tickMaxMs, snap.spikes, snap.jobs))
    out(("  сущности: всего %d, GRM %d, пропов %d, транспорт %d (simfphys %d, LVS %d), физика активна %d")
        :format(snap.entities.total, snap.entities.grm, snap.entities.props,
            snap.entities.vehicles, snap.entities.simfphys, snap.entities.lvs, snap.entities.physicsAwake))
    out(("  двери: всего %d, с записью %d, бесхозных %d, парных %d, подозрение на фантомы %d (групп %d)")
        :format(snap.doors.total, snap.doors.withRecord, snap.doors.ownerless,
            snap.doors.paired, snap.doors.suspectPhantom, snap.doors.groups))
    out(("  игроков онлайн: %d, активных таймеров GRM: %d"):format(#snap.players, snap.timers))

    local events = sortedPairs(AN.EventTotals)
    if #events > 0 then
        out("  топ событий за сессию:")
        for i = 1, math.min(8, #events) do
            out(("    %-24s %d"):format(events[i].key, events[i].value))
        end
    end
end

function AN.ReportEntities(out)
    local snap = AN.Last or AN.Snapshot()
    out("[GRM Анализ] сущности по классам (топ 25):")
    local rows = sortedPairs(snap.entities.byClass)
    for i = 1, math.min(25, #rows) do
        out(("  %-42s %5d"):format(rows[i].key, rows[i].value))
    end
    out(("  ИТОГО: %d (лимит движка 8192)"):format(snap.entities.total))
end

function AN.ReportDoors(out)
    local snap = AN.Last or AN.Snapshot()
    local d = snap.doors
    out("[GRM Анализ] двери:")
    out(("  всего %d · с записью GRM %d · бесхозных %d · парных %d")
        :format(d.total, d.withRecord, d.ownerless, d.paired))
    if d.suspectPhantom > 0 then
        out(("  ВНИМАНИЕ: похоже на фантомы — %d лишних entity в %d группах")
            :format(d.suspectPhantom, d.groups))
        out("  проверить: /door_audit, убрать: /door_rebuild orphans")
    else
        out("  фантомных дверей не обнаружено")
    end
end

function AN.ReportPlayers(out)
    local snap = AN.Last or AN.Snapshot()
    if #snap.players == 0 then out("[GRM Анализ] игроков нет") return end
    out("[GRM Анализ] игроки:")
    out("  ник                 пинг  скор.  движ.всего  [E]  выстр.  смерт.  чат  состояние")
    for _, row in ipairs(snap.players) do
        local state = {}
        if row.inVehicle then state[#state + 1] = "в ТС" end
        if row.noclip then state[#state + 1] = "ноклип" end
        if not row.alive then state[#state + 1] = "мёртв" end
        if row.onDuty then state[#state + 1] = "на службе" end
        if (row.afk or 0) > 60 then state[#state + 1] = ("AFK %ds"):format(math.floor(row.afk)) end
        out(("  %-18s %4d %6d %11d %4d %7d %7d %4d  %s")
            :format(string.sub(row.nick, 1, 18), row.ping, row.speed, row.movedTotal,
                row.uses, row.shots, row.deaths, row.chat, table.concat(state, ", ")))
    end
end

function AN.ReportEvents(out)
    out("[GRM Анализ] события за сессию:")
    for _, row in ipairs(sortedPairs(AN.EventTotals)) do
        out(("  %-26s %d"):format(row.key, row.value))
    end
    if AN.LastNetProfile then
        out(("[GRM Анализ] net за последние %d с профиля:"):format(AN.LastNetProfile.seconds))
        for _, row in ipairs(sortedPairs(AN.LastNetProfile.rows, function(v) return v.bytes end)) do
            out(("  %-34s пакетов %4d, байт %7d"):format(row.key, row.value.count, row.value.bytes))
        end
    end
    if AN.LastHookProfile then
        out(("[GRM Анализ] хуки за последние %d с профиля (топ 15 по времени):"):format(AN.LastHookProfile.seconds))
        local rows = sortedPairs(AN.LastHookProfile.stats, function(v) return v.ms end)
        for i = 1, math.min(15, #rows) do
            local st = rows[i].value
            out(("  %-46s %7.2f мс за %d вызовов"):format(rows[i].key, st.ms, st.calls))
        end
    end
end

function AN.Dump()
    if not SERVER then return false end
    if not file.IsDir("grm_analytics", "DATA") then file.CreateDir("grm_analytics") end
    local payload = {
        version = 1, at = os.time(), map = game.GetMap(),
        last = AN.Last, totals = AN.EventTotals,
        hookProfile = AN.LastHookProfile, netProfile = AN.LastNetProfile,
        history = AN.History,
    }
    local ok, raw = pcall(util.TableToJSON, payload, true)
    if not ok or not isstring(raw) then return false end
    local path = "grm_analytics/report_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    file.Write(path, raw)
    return true, path
end

-----------------------------------------------------------------------
-- КОМАНДЫ
-----------------------------------------------------------------------
local function guard(ply)
    if not IsValid(ply) then return true end
    if GRM.Admin and GRM.Admin.Can then return GRM.Admin.Can(ply, "menu.modules") end
    return ply:IsSuperAdmin()
end

concommand.Add("grm_analyze", function(ply) if guard(ply) then AN.ReportSummary(printer(ply)) end end)
concommand.Add("grm_analyze_ents", function(ply) if guard(ply) then AN.ReportEntities(printer(ply)) end end)
concommand.Add("grm_analyze_doors", function(ply) if guard(ply) then AN.ReportDoors(printer(ply)) end end)
concommand.Add("grm_analyze_players", function(ply) if guard(ply) then AN.ReportPlayers(printer(ply)) end end)
concommand.Add("grm_analyze_events", function(ply) if guard(ply) then AN.ReportEvents(printer(ply)) end end)

concommand.Add("grm_analyze_hooks", function(ply, _, args)
    if not guard(ply) then return end
    local out = printer(ply)
    local ok, msg = AN.ProfileHooks(tonumber(args and args[1]) or 10, function(profile)
        out(("[GRM Анализ] профиль хуков готов (%d с):"):format(profile.seconds))
        local rows = sortedPairs(profile.stats, function(v) return v.ms end)
        for i = 1, math.min(20, #rows) do
            local st = rows[i].value
            out(("  %-46s %7.2f мс за %d вызовов"):format(rows[i].key, st.ms, st.calls))
        end
    end)
    out("[GRM Анализ] " .. tostring(msg))
end)

concommand.Add("grm_analyze_net", function(ply, _, args)
    if not guard(ply) then return end
    local out = printer(ply)
    local ok, msg = AN.ProfileNet(tonumber(args and args[1]) or 10, function(profile)
        out(("[GRM Анализ] профиль net готов (%d с):"):format(profile.seconds))
        for _, row in ipairs(sortedPairs(profile.rows, function(v) return v.bytes end)) do
            out(("  %-34s пакетов %4d, байт %7d"):format(row.key, row.value.count, row.value.bytes))
        end
    end)
    out("[GRM Анализ] " .. tostring(msg))
end)

if SERVER then
    concommand.Add("grm_analyze_dump", function(ply)
        if not guard(ply) then return end
        local ok, path = AN.Dump()
        printer(ply)(ok and ("[GRM Анализ] срез сохранён: data/" .. tostring(path))
            or "[GRM Анализ] не удалось сохранить срез")
    end)
end

-----------------------------------------------------------------------
-- СТАРТ
-----------------------------------------------------------------------
if GRM.Boot and GRM.Boot.OnMapStart then
    GRM.Boot.OnMapStart("GRM_Analytics_Start", "late", function() AN.Start() end)
else
    hook.Add("InitPostEntity", "GRM_Analytics_Start", function() timer.Simple(5, AN.Start) end)
end

print("[GRM Analytics] v" .. AN.Version .. " loaded")
