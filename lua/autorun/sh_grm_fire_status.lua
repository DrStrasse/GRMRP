-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Fire — учёт тушения v1.4.1
    Кластер vFire = один пожар. Уведомления:
      «Пожар локализован» — очаг сжат и больше не растёт (после работы ствола).
      «Пожар потушен» — клеток не осталось.
    v1.4.1: мягче локализован (2.5с без роста, peak>=1), всегда шлёт потушен,
    оба события при тушении после ствола, toast+ChatPrint, SuperAdmin+Dispatch+FightPro+бойцы+рядом 1500,
    скан живых vfire на boot, peak=min 1 если видели vfire, журнал /fire_log.
    Журнал data/grm_fire/log.json (массив). Не трогает Q / factions / FFD.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire
F.StatusVersion = "1.5.0"

F.Incidents = F.Incidents or {}
F._nextInc = F._nextInc or 1

if not F.ChatDupeCvar then
    F.ChatDupeCvar = CreateConVar("grm_fire_chat_dupe", "0",
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "1 — дублировать сообщения о пожаре строкой в чат (по умолчанию только уведомление)")
end

local CLUSTER = 480
local LOG_FILE = "grm_fire/log.json"
local LOG_CAP = 80

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function plyKey(ply)
    if not IsValid(ply) then return nil end
    if GRM.Identity and isfunction(GRM.Identity.CharacterKey) then
        local k = GRM.Identity.CharacterKey(ply)
        if isstring(k) and k ~= "" then return k end
    end
    if ply.SteamID64 then return tostring(ply:SteamID64() or "") end
    return tostring(ply:SteamID() or "")
end

local function plyNick(ply)
    if not IsValid(ply) then return "?" end
    return tostring(ply:Nick() or "?")
end

-- Уведомление: тост + чат, широкие получатели
function F.NotifyFire(text, r, g, b, pos, inc)
    r = tonumber(r) or 255
    g = tonumber(g) or 160
    b = tonumber(b) or 80

    local notified = {}

    --[[ Раньше каждое событие приходило ДВАЖДЫ: тостом и строкой в чат.
         На пожаре событий много, и половина «спама» была именно этим
         дублированием. Теперь дубль в чат — по конвару (по умолчанию
         выключен), а без модуля уведомлений чат остаётся как фолбэк. ]]
    local dupe = GetConVar and GetConVar("grm_fire_chat_dupe")
    local wantChat = (dupe and dupe:GetBool()) or not GRM.Notify

    local function tellPlayer(p)
        if not IsValid(p) then return end
        if notified[p] then return end
        notified[p] = true
        if GRM.Notify then GRM.Notify(p, text, r, g, b) end
        if wantChat then p:ChatPrint("[Пожар] " .. tostring(text)) end
    end

    -- фракции из /grm_fire_notify (legacy, но теперь с ChatPrint доп.)
    if F.NotifyFactions then
        -- старый метод шлёт только Notify; мы дублируем чатPrint отдельно для тех же фракций
        F.NotifyFactions(text, pos, r, g, b)
        -- доп-дубль в чат для них же соберём через общий проход ниже
    end

    -- 1. SuperAdmin + диспетчер + FightPro (галочка Control)
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            if p:IsSuperAdmin() or (F.CanDispatch and F.CanDispatch(p)) or (F.CanFightPro and F.CanFightPro(p)) then
                tellPlayer(p)
            end
        end
    end

    -- 2. Участники тушения (записаны через NoteFight)
    if inc and istable(inc.fighters) then
        for _, rec in ipairs(inc.fighters) do
            if rec and rec.key then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and plyKey(p) == rec.key then
                        tellPlayer(p)
                    end
                end
            end
        end
    end

    -- 3. Рядом с очагом ~1500 юнитов (видели дым, должны знать)
    if isvector(pos) then
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and not notified[p] then
                if p:GetPos():DistToSqr(pos) <= 1500 * 1500 then
                    tellPlayer(p)
                end
            end
        end
    end

    print("[GRM Fire] " .. tostring(text))
end

if SERVER then
    util.AddNetworkString("GRM_FireLog_Req")
    util.AddNetworkString("GRM_FireLog_Data")

    local function ensureDir()
        if not file.IsDir("grm_fire", "DATA") then file.CreateDir("grm_fire") end
    end

    function F.LoadFireLog()
        ensureDir()
        if not file.Exists(LOG_FILE, "DATA") then return {} end
        local t = jsonT(file.Read(LOG_FILE, "DATA") or "")
        if not istable(t) then return {} end
        local out = {}
        for _, rec in ipairs(t) do
            if istable(rec) then out[#out + 1] = rec end
        end
        return out
    end

    --[[ Журнал держим в памяти и пишем через общую очередь GRM.Save:
         раньше каждое событие пожара читало файл целиком и тут же писало его
         обратно — синхронный диск в момент, когда на карте и так жарко. ]]
    F.FireLog = F.FireLog or nil

    local function fireLog()
        if not F.FireLog then F.FireLog = F.LoadFireLog() end
        return F.FireLog
    end

    if GRM.Save and GRM.Save.Register then
        GRM.Save.Register("fire.log", { file = LOG_FILE, label = "Журнал пожаров", delay = 10,
            build = function()
                ensureDir()
                return fireLog()
            end })
    end

    function F.AppendFireLog(rec)
        if not istable(rec) then return false end
        local list = fireLog()
        table.insert(list, 1, rec)
        while #list > LOG_CAP do list[#list] = nil end
        if GRM.Save and GRM.Save.Mark then return GRM.Save.Mark("fire.log", "событие пожара") end
        ensureDir()
        local ok, txt = pcall(util.TableToJSON, list, true)
        if not ok or not isstring(txt) then return false end
        file.Write(LOG_FILE, txt)
        return true
    end

    -- Кэшированный список живых vfire (event-реестр GRM.Perf вместо покадрового
    -- ents.FindByClass, который каждый раз сканирует ВСЕ энтити карты).
    local function liveVfire()
        if GRM.Perf and GRM.Perf.Entities then
            return GRM.Perf.Entities("vfire")
        end
        return ents.FindByClass("vfire")
    end

    local function countAround(origin)
        if not origin then return 0 end
        local n, r2 = 0, CLUSTER * CLUSTER
        for _, e in ipairs(liveVfire()) do
            if IsValid(e) and e.GetPos and e:GetPos():DistToSqr(origin) <= r2 then
                n = n + 1
            end
        end
        return n
    end

    local function findInc(pos)
        if not pos then return nil end
        local best, bestD
        local r2 = CLUSTER * CLUSTER
        for _, inc in ipairs(F.Incidents) do
            if inc and not inc.out and inc.origin then
                local d = pos:DistToSqr(inc.origin)
                if d <= r2 and (not best or d < bestD) then best, bestD = inc, d end
            end
        end
        return best
    end

    --[[ ПОВТОРНОЕ ЗАГОРАНИЕ И ЛОЖНЫЕ ИНЦИДЕНТЫ (фикс 21.08 по жалобе
         владельца: «при тушении сыпятся сообщения о том, что потушили, и
         генерируются новые вызовы»).

         Причина была здесь: `RefreshIncidents(pos)` на КАЖДУЮ погашенную
         ячейку vFire звал OpenIncident. Инцидент рядом уже помечен `out`,
         значит findInc его не видит — открывался НОВЫЙ инцидент с peak=1 и
         cells=0, тут же признавался потушенным («Пожар потушен» ещё раз) и
         по пути дёргал GRM_FireIncidentOpened, из-за чего диспетчер плодил
         новые вызовы прямо во время тушения.

         Теперь: инцидент открывается только там, где РЕАЛЬНО горит, а очаг,
         потушенный только что, при повторной вспышке оживает тем же
         инцидентом (без нового вызова и без новых объявлений). ]]
    local REIGNITE_WINDOW = 45

    local function findRecentOut(pos)
        if not pos then return nil end
        local now, r2 = CurTime(), CLUSTER * CLUSTER
        local best, bestD
        for _, inc in ipairs(F.Incidents) do
            if inc and inc.out and inc.origin and (now - (inc.outAt or 0)) <= REIGNITE_WINDOW then
                local d = pos:DistToSqr(inc.origin)
                if d <= r2 and (not best or d < bestD) then best, bestD = inc, d end
            end
        end
        return best
    end

    function F.OpenIncident(pos, source, opts)
        if not pos then return nil end
        opts = istable(opts) and opts or {}

        local exist = findInc(pos)
        if exist then
            -- если уже есть, но peak был 0 (баг старых версий при open на remove) — чиним
            if (exist.peak or 0) < 1 then exist.peak = 1 end
            return exist
        end

        -- Нет живого огня рядом — нет и инцидента. Это отсекает «инциденты
        -- от погашенной ячейки», из-за которых шёл весь спам.
        if not opts.force and countAround(pos) < 1 then return nil end

        -- Вспышка на месте только что потушенного очага — тот же инцидент.
        local revived = findRecentOut(pos)
        if revived then
            revived.out = false
            revived.outAt = nil
            revived.cells = countAround(revived.origin)
            revived.peak = math.max(revived.peak or 1, revived.cells, 1)
            revived.lastNew = CurTime()
            revived.localized = false
            return revived
        end

        local id = F._nextInc
        F._nextInc = F._nextInc + 1
        -- peak = сколько ячеек реально видели. Принудительно открытый очаг без
        -- живого огня получает 0: такой «призрак» никогда не объявит себя
        -- потушенным (иначе на пустом месте всплывает лишнее сообщение).
        local seen = countAround(pos)
        local inc = {
            id = id,
            origin = Vector(pos.x, pos.y, pos.z),
            source = tostring(source or "fire"),
            peak = math.max(seen, opts.force and 0 or 1),
            cells = 0,
            started = CurTime(),
            lastNew = CurTime(),
            lastKill = 0,
            fought = false,
            localized = false,
            out = false,
            fighters = {},
        }
        F.Incidents[#F.Incidents + 1] = inc
        -- Диспетчеризация (v1.5.0): по открытию очага создаётся вызов, который
        -- пожарные должны ПРИНЯТЬ. Слушатель — sh_grm_fire_dispatch.lua.
        hook.Run("GRM_FireIncidentOpened", inc)
        return inc
    end

    function F.NoteFight(ply, pos)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        pos = pos or (ply.GetEyeTrace and ply:GetEyeTrace().HitPos) or ply:GetPos()
        local inc = findInc(pos)
        if not inc then
            -- Если тушат рядом, а инцидент ещё не открыт (скан пропустил) —
            -- откроем, но только когда рядом действительно горит.
            inc = F.OpenIncident(pos, "fire")
        end
        if not inc then return end
        inc.fought = true
        inc.lastFight = CurTime()
        local key = plyKey(ply)
        if not key or key == "" then return end
        for _, f in ipairs(inc.fighters) do
            if f.key == key then f.nick = plyNick(ply) return end
        end
        inc.fighters[#inc.fighters + 1] = { key = key, nick = plyNick(ply) }
    end

    local function notifyCrew(inc, text, r, g, b)
        F.NotifyFire(text, r, g, b, inc and inc.origin, inc)
    end

    local function logEvent(inc, event)
        local fighters = {}
        for _, f in ipairs(inc.fighters or {}) do
            fighters[#fighters + 1] = { key = tostring(f.key or ""), nick = tostring(f.nick or "") }
        end
        local o = inc.origin or Vector(0, 0, 0)
        F.AppendFireLog({
            t = os.time(),
            map = tostring(game.GetMap() or ""),
            event = event,
            peak = math.floor(tonumber(inc.peak) or 0),
            cells = math.floor(tonumber(inc.cells) or 0),
            source = tostring(inc.source or ""),
            x = math.floor(o.x or 0),
            y = math.floor(o.y or 0),
            z = math.floor(o.z or 0),
            fighters = fighters,
            sec = math.floor(CurTime() - (inc.started or CurTime())),
        })
    end

    function F.MarkLocalized(inc)
        if not inc or inc.localized or inc.out then return false end
        inc.localized = true
        inc.localizedAt = CurTime()
        logEvent(inc, "localized")
        hook.Run("GRM_FireLocalized", inc.origin, inc)
        notifyCrew(inc, "Пожар локализован", 255, 190, 70)
        return true
    end

    function F.MarkExtinguished(inc)
        if not inc or inc.out then return false end
        -- Пустышка (инцидент без единой живой ячейки за всё время) не должна
        -- объявляться потушенной — это была вторая половина спама.
        if (inc.peak or 0) < 1 then inc.out = true return false end
        -- v1.4.1: если тушили стволом, но локализован ещё не слали — шлём оба, сначала локализован
        if not inc.localized and inc.fought and (inc.peak or 0) >= 1 then
            -- попытка локализовать перед тушением, но без выхода если не получилось (например out уже)
            F.MarkLocalized(inc)
        end
        inc.out = true
        inc.cells = 0
        inc.outAt = CurTime()
        logEvent(inc, "out")
        hook.Run("GRM_FireExtinguished", inc.origin, inc)
        notifyCrew(inc, "Пожар потушен", 100, 220, 130)
        local live = #liveVfire()
        if live == 0 and GRM.Minimap and GRM.Minimap.RemoveTempPoint then
            GRM.Minimap.RemoveTempPoint("ПОЖАР")
        end
        return true
    end

    function F.RefreshIncidents(hintPos)
        --[[ Обновление НЕ создаёт инцидентов: сюда приходят в том числе
             события «ячейка погасла», и открытие очага отсюда давало
             бесконечные «потушен» и новые вызовы. Открывает только
             vFireCreated (там огонь точно есть). ]]
        if hintPos then
            local inc = findInc(hintPos)
            if inc then inc.peak = math.max(inc.peak or 0, 1) end
        end
        local now = CurTime()
        for _, inc in ipairs(F.Incidents) do
            if inc and not inc.out then
                local n = countAround(inc.origin)
                if n > (inc.cells or 0) then inc.lastNew = now end
                if n < (inc.cells or 0) then inc.lastKill = now end
                inc.cells = n
                if n > (inc.peak or 0) then inc.peak = n end
                if (inc.peak or 0) < 1 and n >= 1 then inc.peak = 1 end

                if n == 0 and (inc.peak or 0) >= 1 then
                    F.MarkExtinguished(inc)
                elseif not inc.localized and inc.fought
                    and (inc.peak or 0) >= 1
                    and n <= math.max(1, math.floor((inc.peak or 0) * 0.5))
                    and (now - (inc.lastNew or now)) >= 2.5 then
                    F.MarkLocalized(inc)
                end
            end
        end
        -- вычистить старые закрытые
        if #F.Incidents > 24 then
            local keep = {}
            for _, inc in ipairs(F.Incidents) do
                if inc and (not inc.out or (now - (inc.outAt or 0)) < 180) then
                    keep[#keep + 1] = inc
                end
            end
            F.Incidents = keep
        end
    end

    -- Скан уже живущих vfire на буте / первом тике
    function F.BuildFromExisting()
        local found = 0
        for _, fire in ipairs(liveVfire()) do
            if IsValid(fire) then
                local pos = fire.GetPos and fire:GetPos() or nil
                if pos then
                    local inc = findInc(pos) or F.OpenIncident(pos, fire._grmSource or "fire", { force = true })
                    if inc then
                        inc.peak = math.max(inc.peak or 0, 1)
                        found = found + 1
                    end
                end
            end
        end
        if found > 0 then F.RefreshIncidents() end
        return found
    end

    hook.Add("vFireCreated", "GRM_Fire_Status", function(fire)
        if not IsValid(fire) then return end
        local pos = fire.GetPos and fire:GetPos() or nil
        if not pos then return end
        local src = fire._grmSource or "fire"
        local inc = F.OpenIncident(pos, src)
        if inc then
            inc.cells = countAround(inc.origin)
            if inc.cells > (inc.peak or 0) then inc.peak = inc.cells end
            inc.peak = math.max(inc.peak or 0, 1)
            inc.lastNew = CurTime()
        end
    end)

    hook.Add("vFireRemoved", "GRM_Fire_Status", function(fire)
        local pos
        if IsValid(fire) and fire.GetPos then pos = fire:GetPos() end
        if pos then
            -- записать бойца рядом если держит ствол
            for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(ply) and ply:GetPos():DistToSqr(pos) <= 320 * 320 then
                    local w = ply:GetActiveWeapon()
                    local cls = IsValid(w) and w:GetClass() or ""
                    if cls == "weapon_grm_hose" or cls == "weapon_extinguisher" or cls == "weapon_firehose" then
                        F.NoteFight(ply, pos)
                    end
                end
            end
        end
        timer.Simple(0, function() F.RefreshIncidents(pos) end)
    end)

    local scanDone = false
    hook.Add("Think", "GRM_Fire_StatusTick", function()
        if (F._statusAt or 0) > CurTime() then return end
        F._statusAt = CurTime() + 0.8
        -- первый тик после загрузки: скан живых vfire если есть
        if not scanDone then
            scanDone = true
            F.BuildFromExisting()
        end
        if #F.Incidents == 0 then
            -- если инцидентов нет, но vfire появились (ранний спавн карты) — подберём
            if #liveVfire() > 0 then F.BuildFromExisting() end
            return
        end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:KeyDown(IN_ATTACK) then
                local w = ply:GetActiveWeapon()
                local cls = IsValid(w) and w:GetClass() or ""
                if cls == "weapon_grm_hose" or cls == "weapon_extinguisher" or cls == "weapon_firehose" then
                    local tr = ply:GetEyeTrace()
                    F.NoteFight(ply, tr and tr.HitPos or ply:GetPos())
                end
            end
        end
        F.RefreshIncidents()
    end)

    grmBootStart("GRM_Fire_StatusBoot", "normal", function()
        timer.Simple(1, function() F.BuildFromExisting() end)
        timer.Simple(2, function() F.BuildFromExisting() end)
    end)
    hook.Add("PostCleanupMap", "GRM_Fire_StatusCleanup", function()
        timer.Simple(1, function() F.BuildFromExisting() end)
    end)

    -- Журнал: сеть
    local function canViewLog(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if F.CanDispatch and F.CanDispatch(ply) then return true end
        if F.CanFightPro and F.CanFightPro(ply) then return true end
        return false
    end

    local function sendLog(ply)
        local list = F.LoadFireLog()
        -- ограничим 80 уже, но шлём не более 50 чтобы не упереться в лимит
        local out = {}
        for i = 1, math.min(#list, 50) do out[i] = list[i] end
        net.Start("GRM_FireLog_Data")
            net.WriteTable(out)
        net.Send(ply)
    end

    net.Receive("GRM_FireLog_Req", function(_, ply)
        if not IsValid(ply) then return end
        if not canViewLog(ply) then
            if GRM.Notify then GRM.Notify(ply, "Нет доступа к журналу тушения.", 255, 100, 100) end
            return
        end
        sendLog(ply)
    end)

    local function handleLogChat(ply, low)
        if not isstring(low) then return false end
        low = string.lower(string.Trim(low))
        if low == "/fire_log" or low == "!fire_log" or low == "/firelog" or low == "!firelog"
            or low == "/журнал_пожаров" or low == "!журнал_пожаров" or low == "/журналпожаров" or low == "/пожары_лог" then
            if canViewLog(ply) then sendLog(ply) else
                if GRM.Notify then GRM.Notify(ply, "Нет доступа к журналу тушения.", 255, 100, 100) end
            end
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_Fire_LogChat", function(ply, text)
        local low = string.lower(string.Trim(tostring(text or "")))
        if handleLogChat(ply, low) then return "" end
    end)
    -- поддержка EasyChat PlayerSayTransform
    hook.Add("PlayerSayTransform", "GRM_Fire_LogChatTr", function(ply, pack)
        if not istable(pack) then return end
        local txt = tostring(pack[1] or "")
        if handleLogChat(ply, txt) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    concommand.Add("grm_fire_log", function(ply)
        if not IsValid(ply) then return end
        if canViewLog(ply) then sendLog(ply) end
    end)

    print("[GRM Fire] Status v" .. F.StatusVersion .. " загружен")
end

if CLIENT then
    local function formatTime(ts)
        if not ts or ts == 0 then return "--:--" end
        return os.date("%d.%m %H:%M", ts)
    end
    local function eventName(ev)
        if ev == "localized" then return "ЛОКАЛИЗОВАН"
        elseif ev == "out" then return "ПОТУШЕН"
        elseif ev == "started" then return "ВОЗГОРАНИЕ"
        else return tostring(ev or "?") end
    end

    function GRM.Fire.OpenLogPanel(list)
        list = istable(list) and list or {}
        if IsValid(GRM.Fire._logFrame) then GRM.Fire._logFrame:Remove() end
        local frame = vgui.Create("DFrame")
        GRM.Fire._logFrame = frame
        frame:SetTitle("")
        frame:SetSize(820, 520)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, Color(18, 22, 32, 252))
            draw.RoundedBoxEx(10, 0, 0, w, 36, Color(28, 36, 52), true, true, false, false)
            draw.SimpleText("ЖУРНАЛ ТУШЕНИЯ ПОЖАРОВ", "DermaLarge", 18, 18, Color(230, 235, 245))
            draw.SimpleText("Всего записей: " .. #list, "DermaDefault", w - 18, 18, Color(140, 150, 170), TEXT_ALIGN_RIGHT)
        end

        local lv = vgui.Create("DListView", frame)
        lv:Dock(FILL)
        lv:DockMargin(10, 44, 10, 10)
        lv:AddColumn("Время"):SetFixedWidth(110)
        lv:AddColumn("Событие"):SetFixedWidth(110)
        lv:AddColumn("Источник"):SetFixedWidth(80)
        lv:AddColumn("Пик"):SetFixedWidth(50)
        lv:AddColumn("Клеток"):SetFixedWidth(60)
        lv:AddColumn("Длит."):SetFixedWidth(60)
        lv:AddColumn("Коорд."):SetFixedWidth(120)
        lv:AddColumn("Бойцы")

        for _, rec in ipairs(list) do
            local fighters = ""
            if istable(rec.fighters) then
                local names = {}
                for _, f in ipairs(rec.fighters) do
                    if f.nick and f.nick ~= "" then names[#names+1] = f.nick end
                end
                fighters = table.concat(names, ", ")
            end
            local coord = string.format("%d %d %d", rec.x or 0, rec.y or 0, rec.z or 0)
            local dur = rec.sec and tostring(rec.sec) .. "с" or ""
            lv:AddLine(formatTime(rec.t), eventName(rec.event), tostring(rec.source or ""), tostring(rec.peak or 0), tostring(rec.cells or 0), dur, coord, fighters)
        end

        local bot = vgui.Create("DPanel", frame)
        bot:Dock(BOTTOM)
        bot:SetTall(36)
        bot:SetPaintBackground(false)
        local btn = vgui.Create("DButton", bot)
        btn:Dock(RIGHT)
        btn:SetWide(140)
        btn:DockMargin(6, 6, 10, 6)
        btn:SetText("Обновить")
        btn.DoClick = function()
            net.Start("GRM_FireLog_Req") net.SendToServer()
        end
    end

    net.Receive("GRM_FireLog_Data", function()
        local list = net.ReadTable() or {}
        GRM.Fire.OpenLogPanel(list)
    end)

    concommand.Add("grm_fire_log", function()
        net.Start("GRM_FireLog_Req") net.SendToServer()
    end)
end
