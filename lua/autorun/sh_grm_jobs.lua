-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Jobs Exchange v4.0.0 (Код 77) — Биржа труда

    v1.1.0 (заказ владельца «фракции выставляют свои работы для найма»):
      - ВАКАНСИИ фракций поверх разовых заказов: лидер ставит зарплату
        за смену, длительность смены (5/10/15/20 мин) и число смен —
        эскроу = зарплата × смены списывается с бюджета сразу, возврат
        по остатку (отзыв/просрочка/провал исполнителя).
      - /jobpost — форма публикации С ЛЮБОГО места: зона смены вакансии
        фиксируется там, где стоит лидер (встал у станка завода →
        опубликовал «рабочие на боеприпасы»). Через терминал зона —
        позиция терминала. jtype shift: зона 400 юн, не в транспорте.
      - Работодателю в сети летят уведомления: вышел на смену / смена
        отработана / заказ выполнен; в карточке — выплачено и последний
        исполнитель (payedTotal/lastWorker).

    Система подработки для жителей города + заказы от фракций:

      - Терминал биржи (энтити grm_jobcenter): E → меню вакансий.
        Вакансии генерируются сервером и обновляются каждые 5 минут:
          «Курьер»          — доставка в случайную точку (grm_depot);
          «Патруль точки»   — продержаться в зоне N сек (не в машине);
          «Грузчик»         — длинная смена на складе;
          «Инспектор»       — съездить в точку и вернуться.
        Награда зависит от дистанции, время на выполнение ограничено.
      - Точки доставки (энтити grm_depot): расставляет суперадмин
        (/jobdepot_add). Без точек вакансии-развозки выключены.
      - Заказы фракций: лидер фракции с доступом «БИРЖА» (/factions →
        «Доступы» или /job_allow) публикует собственные задания — сумма
        награды ЭСКРОУИРУЕТСЯ с бюджета фракции (GRM.FactionBudgetAdd)
        при публикации; выполнил — деньги работнику, отозвал/просрочил —
        возврат в бюджет. До 3 заказов на фракцию, срок 24 ч.
      - У игрока одна активная задача: /jobs — статус, /jobcancel — отказ.
        Прогресс не пишется в машине (для «стоячих»), дедлайн — по
        настенным часам (переживает рестарт: активные задачи сохраняются
        в data/grm_jobs_active.json МАССИВОМ записей, урок находки 65).
      - Хуки наружу: GRM_Jobs_Completed (ply, job), GRM_Jobs_Failed
        (ply, job, why) — на них вешаются ачивки (Код 78).
      - 3D-маркер цели у исполнителя; вкладка «Работа» в F4
        (хук GRM_F4_BuildTabs, F4 v1.4.0+).
      - Чат-команды через PlayerSayTransform (+fallback PlayerSay) —
        контракт находки 89 (цепочка PlayerSay сборки глотает команды).

    Спавн: /jobcenter_add, /jobcenter_remove, /jobdepot_add,
    /jobdepot_remove (суперадмин). АВТОперсистентность:
    data/grm_jobs_ents/<map>.json, /permadd не нужен (антидубль 8 юн).
    Доступ работодателей: /job_allow Фракция, /job_deny Фракция,
    вкладка /factions → «Доступы», чекбоксы в меню терминала у суперадмина.
    Данные: grm_jobs.json {allow, posts, stats}, grm_jobs_active.json.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Jobs = GRM.Jobs or {}
local JB = GRM.Jobs

JB.Version     = "4.0.0"  -- работы: курьер / мусоровоз / таксист + новый UI
JB.DataFile    = "grm_jobs.json"
JB.ActiveFile  = "grm_jobs_active.json"
JB.Rotate      = 300      -- смена вакансий, сек
JB.MaxPosts    = 3        -- одновременных заказов/вакансий на фракцию
JB.PostExpire  = 86400    -- срок жизни заказа фракции, сек
JB.MinReward   = 100
JB.MaxReward   = 10000
JB.MinSalary   = 100      -- вакансия: зарплата за смену (мин/макс)
JB.MaxSalary   = 5000
JB.MaxShifts   = 10       -- вакансия: смен на одну публикацию

local NET_OPEN      = "GRM_Jobs_Open"
local NET_ACCEPT    = "GRM_Jobs_Accept"
local NET_CANCEL    = "GRM_Jobs_Cancel"
local NET_POST      = "GRM_Jobs_Post"
local NET_UNPOST    = "GRM_Jobs_Unpost"
local NET_TAKEPOST  = "GRM_Jobs_TakePost"
local NET_ALLOW     = "GRM_Jobs_Allow"
local NET_TRACKER   = "GRM_Jobs_Tracker"
local NET_GETMY     = "GRM_Jobs_GetMy"
local NET_MYSTATE   = "GRM_Jobs_MyState"
local NET_FORM      = "GRM_Jobs_PostForm" -- S→C: открыть форму публикации (зона = где стоишь)

-- ============================================================
-- ШАБЛОНЫ ЗАДАНИЙ (можно расширять из других модулей — JB.Register)
-- ============================================================
JB.Templates = JB.Templates or {}

function JB.Register(tpl)
    if not istable(tpl) or not isstring(tpl.id) or tpl.id == "" then return end
    JB.Templates[tpl.id] = tpl
end

-- награды/сроки считаем по дистанции до точки
local function clampN(v, a, b) if v < a then return a end if v > b then return b end return v end

-- Готовый набор работ биржи (v2.1.0): курьер / мусоровоз / таксист.
-- id, title, jtype, needVehicle (требует транспорт), icon, color, desc.
JB.Register({
    id = "courier", title = "Курьер", jtype = "goto",
    icon = "icon16/package.png", color = { 90, 170, 250 },
    desc = "Доставьте посылку в точку города. На чём угодно — хоть пешком.",
    rewardFn = function(dist) return clampN(350 + dist * 0.18, 250, 950) end,
    timeFn   = function(dist) return clampN(300 + dist * 0.12, 240, 600) end,
})
JB.Register({
    id = "garbage", title = "Мусоровоз", jtype = "garbage", needVehicle = true, points = 3,
    icon = "icon16/lorry.png", color = { 130, 190, 95 },
    desc = "Соберите 3 мусорных пакета по контейнерам и сдайте полный кузов на полигон.",
    rewardFn = function(dist) return clampN(900 + dist * 0.30, 800, 2000) end,
    timeFn   = function(dist) return clampN(600 + dist * 0.30, 480, 1200) end,
})
JB.Register({
    id = "taxi", title = "Таксист", jtype = "taxi", needVehicle = true,
    icon = "icon16/car.png", color = { 250, 200, 70 },
    desc = "Заберите пассажира на точке посадки и довезите до пункта назначения (на машине).",
    rewardFn = function(dist) return clampN(450 + dist * 0.25, 400, 1300) end,
    timeFn   = function(dist) return clampN(400 + dist * 0.25, 360, 900) end,
})

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_ACCEPT)
    util.AddNetworkString(NET_CANCEL)
    util.AddNetworkString(NET_POST)
    util.AddNetworkString(NET_UNPOST)
    util.AddNetworkString(NET_TAKEPOST)
    util.AddNetworkString(NET_ALLOW)
    util.AddNetworkString(NET_TRACKER)
    util.AddNetworkString(NET_GETMY)
    util.AddNetworkString(NET_MYSTATE)
    util.AddNetworkString(NET_FORM)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    -- конфиг: доступ работодателей + заказы фракций + статистика игроков
    local function defaultCfg()
        return { allow = {}, posts = {}, stats = {}, nextId = 1 }
    end
    local function loadCfg()
        JB.Cfg = defaultCfg()
        local t = jsonT(file.Read(JB.DataFile, "DATA") or "")
        if istable(t) then
            JB.Cfg.allow = istable(t.allow) and t.allow or {}
            JB.Cfg.posts = istable(t.posts) and t.posts or {}
            JB.Cfg.stats = istable(t.stats) and t.stats or {}
            JB.Cfg.nextId = math.max(1, tonumber(t.nextId) or 1)
        end
    end
    function JB.SaveCfg(why)
        local ok, txt = pcall(util.TableToJSON, JB.Cfg or defaultCfg(), true)
        if ok and txt then file.Write(JB.DataFile, txt) end
        print("[GRM Jobs] SAVE cfg (" .. tostring(why or "-") .. "): постов " .. tostring(table.Count((JB.Cfg or {}).posts or {})))
    end
    loadCfg()

    -- статистика (массивом, урок находки 65) --------------------------
    local function statRec(sid, nick)
        for _, r in ipairs(JB.Cfg.stats) do
            if r.sid == sid then return r end
        end
        local r = { sid = sid, nick = tostring(nick or "?"), done = 0, earned = 0 }
        JB.Cfg.stats[#JB.Cfg.stats + 1] = r
        return r
    end
    function JB.StatsFor(sid)
        for _, r in ipairs(JB.Cfg.stats) do
            if r.sid == sid then return r end
        end
        return nil
    end

    -- автоперсистентность энтити ---------------------------------------
    local PERSIST_CLASSES = { grm_jobcenter = true, grm_depot = true }
    local function entsFile()
        if not file.IsDir("grm_jobs_ents", "DATA") then file.CreateDir("grm_jobs_ents") end
        return "grm_jobs_ents/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end
    JB.Persist = {}
    local function loadPersist()
        local t = jsonT(file.Read(entsFile(), "DATA") or "")
        JB.Persist = istable(t) and t or {}
    end
    local function savePersist()
        local ok, txt = pcall(util.TableToJSON, JB.Persist, true)
        if ok and txt then file.Write(entsFile(), txt) end
    end
    loadPersist()
    local function persistKey(class, pos)
        return tostring(class) .. "|" .. string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
    end
    function JB.PersistAdd(ent)
        if not IsValid(ent) or JB._restoring then return end
        local class = ent:GetClass()
        if not PERSIST_CLASSES[class] then return end
        local pos, ang = ent:GetPos(), ent:GetAngles()
        JB.Persist[persistKey(class, pos)] = {
            class = class,
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { p = ang.p or 0, y = ang.y or 0, r = ang.r or 0 },
        }
        savePersist()
    end
    function JB.PersistRemove(ent)
        if not IsValid(ent) then return end
        local k = persistKey(ent:GetClass(), ent:GetPos())
        if JB.Persist[k] then JB.Persist[k] = nil savePersist() end
    end

    function JB.RestoreMap()
        JB._restoring = true
        local restored = 0
        for k, rec in pairs(JB.Persist or {}) do
            if PERSIST_CLASSES[rec.class] and istable(rec.pos) then
                local pos = Vector(tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0, tonumber(rec.pos.z) or 0)
                local dup = false
                for _, e in ipairs(ents.FindByClass(rec.class)) do
                    if IsValid(e) and e:GetPos():DistToSqr(pos) < 64 then dup = true end
                end
                if not dup then
                    local ent = ents.Create(rec.class)
                    if IsValid(ent) then
                        ent:SetPos(pos)
                        local a = istable(rec.ang) and rec.ang or {}
                        ent:SetAngles(Angle(tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0))
                        ent:Spawn() ent:Activate()
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then phys:EnableMotion(false) end
                        restored = restored + 1
                    end
                end
            end
        end
        JB._restoring = false
        print("[GRM Jobs] Персистент: записей " .. tostring(table.Count(JB.Persist or {})) .. ", восстановлено " .. tostring(restored))
    end

    grmBootStart("GRM_Jobs_Restore", "normal", function()
        timer.Simple(3, function() JB.RestoreMap() end)
    end)

    hook.Add("PostCleanupMap", "GRM_Jobs_Cleanup", function()
        timer.Simple(0.5, function() JB.RestoreMap() end)
    end)

    -- помощники ---------------------------------------------------------
    local function rpName(ply)
        local n = ply:GetNWString("GRM_RPName", "")
        return (n ~= "" and n) or ply:Nick()
    end
    local function sid64(ply)
        if IsValid(ply) and ply:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
            return ply:SteamID64() or ply:SteamID()
        end
        local raw = tostring(ply or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        if util.SteamIDTo64 then
            local s64 = util.SteamIDTo64(raw)
            if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
        end
        return raw
    end
    JB.CharacterKey=sid64

    local function factionOfPly(ply)
        if not IsValid(ply) then return nil end
        if _G.FactionsAPI and _G.FactionsAPI.GetFactionOf then
            local found = _G.FactionsAPI.GetFactionOf(ply)
            if found then return found end
            found = _G.FactionsAPI.GetFactionOf(ply:SteamID()) or _G.FactionsAPI.GetFactionOf(ply:SteamID64())
            if found then return found end
        end
        if istable(Factions) then
            local sid, s64 = ply:SteamID(), ply:SteamID64()
            local ck = sid64(ply)
            for name, f in pairs(Factions) do
                local member
                if GRM.Identity and GRM.Identity.FactionMember then member = GRM.Identity.FactionMember(f, ply)
                else member = istable(f) and f.Members and (f.Members[sid] or f.Members[s64]) end
                if istable(f) and member then return name end
            end
        end
        return nil
    end
    local function isLeader(ply, fname)
        if not fname then return false end
        if _G.FactionsAPI and _G.FactionsAPI.IsLeader then
            return (_G.FactionsAPI.IsLeader(ply, fname)
                or _G.FactionsAPI.IsLeader(ply:SteamID(), fname)
                or _G.FactionsAPI.IsLeader(ply:SteamID64(), fname)) and true or false
        end
        return false
    end
    local function canPost(ply)
        local fname = factionOfPly(ply)
        return fname ~= nil and (JB.Cfg.allow[fname] == true) and isLeader(ply, fname), fname
    end

    local function depots(kind)
        if JB.GetRoutePoints then
            local custom = JB.GetRoutePoints(kind)
            if istable(custom) and #custom > 0 then return custom end
            if kind=="garbage"or kind=="dump"then return{}end
        end
        local out = {}
        for _, e in ipairs(ents.FindByClass("grm_depot")) do
            if IsValid(e) then out[#out + 1] = e end
        end
        return out
    end

    -- Готовый набор вакансий: фиксированный список, награды по реальным
    -- дистанциям до точек. garbage/taxi — маршрутные, требуют транспорт.
    local TPL_ORDER = { "courier", "garbage", "taxi" }

    -- детерминированная выборка count разных точек из списка (без повторов)
    local function seededPick(seed, dps, count)
        local n = #dps
        if n < count then return nil end
        local order = {}
        for i = 1, n do order[i] = i end
        local st = (seed % 100000) + 1
        for i = n, 2, -1 do
            st = (st * 48271) % 2147483647
            local j = (st % i) + 1
            order[i], order[j] = order[j], order[i]
        end
        local out = {}
        for i = 1, count do out[#out + 1] = dps[order[i]] end
        return out
    end

    local function vecTbl(v) return { x = v.x, y = v.y, z = v.z } end

    local function buildOffers(center)
        local dps = depots("all")
        if #dps == 0 then return nil, "В городе не настроены точки работ. Обратитесь к администрации (/jobs_admin)." end
        local cpos = center:GetPos()
        local seed = math.floor(CurTime() / JB.Rotate) * 7919 + center:EntIndex() * 31
        local out = {}
        for idx, tid in ipairs(TPL_ORDER) do
            local tpl = JB.Templates[tid]
            if tpl then
                local s = seed + idx * 104729
                local offer
                if tid == "garbage" then
                    -- Контейнеры и свалка теперь имеют разные типы точек.
                    local bins = depots("garbage")
                    local dumps = depots("dump")
                    local requested = (JB.WorkConfig and tonumber(JB.WorkConfig.garbageStops)) or tonumber(tpl.points) or 3
                    local count = math.min(math.max(1,math.floor(requested)),#bins)
                    local picked = count>0 and seededPick(s, bins, count)or nil
                    local dump = dumps[(s % math.max(1, #dumps)) + 1]
                    local pk = picked -- только связанные garbage-точки; чужие depot не подмешиваются
                    if pk and dump and dump.GetPos then
                        pk[#pk + 1] = dump
                        local need = #pk
                        local routeDist, prev = 0, cpos
                        for _, e in ipairs(pk) do routeDist = routeDist + prev:Distance(e:GetPos()); prev = e:GetPos() end
                        local pts, names, pointIDs = {}, {}, {}
                        for i = 1, need do
                            pts[#pts + 1] = vecTbl(pk[i]:GetPos())
                            local rec=pk[i]._grmJobPoint
                            names[#names + 1] = (i == need) and tostring(rec and rec.name or "Свалка") or tostring(rec and rec.name or ("Контейнер " .. tostring(i)))
                            if i<need then pointIDs[#pointIDs+1]=tostring(rec and rec.id or "") end
                        end
                        local dumpRec=pk[need]and pk[need]._grmJobPoint
                        offer = {
                            tplId = tid, title = tpl.title, desc = tpl.desc, jtype = tpl.jtype,
                            needVehicle = true, dist = math.floor(routeDist),
                            reward = clampN(math.floor(tpl.rewardFn(routeDist) / 5) * 5, JB.MinReward, JB.MaxReward),
                            timeSec = math.floor(tpl.timeFn(routeDist)),
                            target = pk[1]:GetPos(), points = pts, pointNames = names,
                            garbagePointIDs=pointIDs,garbageDumpID=tostring(dumpRec and dumpRec.id or ""),
                            zoneRadius = 170, zoneName = "Маршрут вывоза отходов",
                        }
                    else
                        local reason=#bins==0 and"Не установлено ни одной точки маршрута мусоровоза (/jobs_admin)."or(#dumps==0 and"Не установлена отдельная точка свалки."or"Маршрут мусоровоза ещё не готов.")
                        offer={tplId=tid,title=tpl.title,desc=reason,jtype=tpl.jtype,needVehicle=true,dist=0,reward=0,timeSec=0,target=cpos,zoneRadius=170,zoneName="Требуется настройка маршрута",blockedReason=reason}
                    end
                elseif tid=="taxi"then
                    offer={tplId=tid,title=tpl.title,desc="Выйдите на линию, ожидайте живые заказы игроков и принимайте их через /taxi.",jtype=tpl.jtype,needVehicle=true,dist=0,reward=0,timeSec=8*3600,target=cpos,center=cpos,zoneRadius=180,zoneName="Ожидание заказов",taxiStandby=true}
                else
                    local courier = depots("courier")
                    if #courier == 0 then courier = dps end
                    local dep = courier[(s % #courier) + 1]
                    local d = math.floor(cpos:Distance(dep:GetPos()))
                    offer = {
                        tplId = tid, title = tpl.title, desc = tpl.desc, jtype = tpl.jtype,
                            needVehicle=JB.WorkConfig and#(JB.WorkConfig.courierVehicles or{})>0 or false,dist=d,
                        reward = clampN(math.floor(tpl.rewardFn(d) / 5) * 5, JB.MinReward, JB.MaxReward),
                        timeSec = math.floor(tpl.timeFn(d)),
                        staySec = tpl.stay or 0,
                        target = dep:GetPos(),
                        zoneRadius = tonumber(tpl.radius or 180),
                        zoneName = dep.GetNWString and dep:GetNWString("GRM_JobZoneName", "Точка работы") or "Точка работы",
                    }
                end
                if offer then
                    offer.idx = #out + 1
                    offer.icon = tpl.icon
                    offer.color = tpl.color
                    out[#out + 1] = offer
                end
            end
        end
        if #out == 0 then return nil, "Недостаточно точек доставки для вакансий. Обратитесь к администрации." end
        return out
    end

    -- активные задачи ----------------------------------------------------
    JB.Active = JB.Active or {}     -- [sid64] = job
    JB._lastOffers = JB._lastOffers or {} -- [sid64] = {list=t, at=os.time()}

    local function saveActive(why)
        local arr = {}
        for sid, j in pairs(JB.Active) do
            if istable(j) and istable(j.target) then
                arr[#arr + 1] = {
                    sid = sid,
                    title = j.title, desc = j.desc, jtype = j.jtype,
                    stage = j.stage or 1, stayLeft = j.stayLeft or 0,
                    remain = math.max(0, (j.deadline or os.time()) - os.time()),
                    reward = j.reward or 0, started = j.started or os.time(),
                    tx = j.target.x, ty = j.target.y, tz = j.target.z,
                    cx = j.center and j.center.x or 0, cy = j.center and j.center.y or 0, cz = j.center and j.center.z or 0,
                    zoneRadius = j.zoneRadius or 180, zoneName = j.zoneName or "Точка работы",
                    needVehicle = j.needVehicle == true,
                    pointIndex = j.pointIndex or 1,
                    points = j.points, pointNames = j.pointNames,
                    garbagePointIDs=j.garbagePointIDs,garbageDumpID=j.garbageDumpID,
                    tplId = j.tplId, budgetEscrow = tonumber(j.budgetEscrow) or 0,
                    fromPost = j.fromPost and true or false,
                    postFac=j.postFac,postId=j.postId,postKind=j.postKind,
                    taxiStandby=j.taxiStandby==true,taxiRequestID=j.taxiRequestID,
                    garbageCollected=tonumber(j.garbageCollected)or 0,
                }
            end
        end
        local ok, txt = pcall(util.TableToJSON, arr, true)
        if ok and txt then file.Write(JB.ActiveFile, txt) end
        print("[GRM Jobs] SAVE active ("..tostring(why or"-").."): "..tostring(#arr).." зап.")
    end
    JB.SaveActive=saveActive
    function JB.GetActiveJob(ply)return JB.Active[sid64(ply)]end

    local function loadActive()
        local t = jsonT(file.Read(JB.ActiveFile, "DATA") or "")
        if not istable(t) then return end
        local n = 0
        for _, r in ipairs(t) do
            if istable(r) and isstring(r.sid) then
                JB.Active[sid64(r.sid)] = {
                    title = tostring(r.title or "Задача"), desc = tostring(r.desc or ""),
                    jtype = tostring(r.jtype or "goto"), stage = tonumber(r.stage) or 1,
                    stayLeft = tonumber(r.stayLeft) or 0, reward = tonumber(r.reward) or 0,
                    deadline = os.time() + math.max(30, tonumber(r.remain) or 300),
                    started = tonumber(r.started) or os.time(),
                    target = Vector(tonumber(r.tx) or 0, tonumber(r.ty) or 0, tonumber(r.tz) or 0),
                    center = Vector(tonumber(r.cx) or 0, tonumber(r.cy) or 0, tonumber(r.cz) or 0),
                    zoneRadius = tonumber(r.zoneRadius) or 180, zoneName = tostring(r.zoneName or "Точка работы"),
                    needVehicle = r.needVehicle == true,
                    pointIndex = tonumber(r.pointIndex) or 1,
                    points = r.points, pointNames = r.pointNames,
                    garbagePointIDs=r.garbagePointIDs,garbageDumpID=r.garbageDumpID,
                    tplId = r.tplId, budgetEscrow = tonumber(r.budgetEscrow) or 0,
                    fromPost = r.fromPost == true, postFac = r.postFac, postId = r.postId,
                    postKind=r.postKind,taxiStandby=r.taxiStandby==true,taxiRequestID=r.taxiRequestID,garbageCollected=tonumber(r.garbageCollected)or 0,
                }
                n = n + 1
            end
        end
        if n > 0 then print("[GRM Jobs] LOAD active: восстановлено " .. tostring(n) .. " задач") end
    end
    loadActive()

    function JB.PushTracker(ply)
        if not IsValid(ply) then return end
        local j = JB.Active[sid64(ply)]
        net.Start(NET_TRACKER)
        if istable(j)and not(j.taxiStandby and(not j.taxiRequestID or j.stage==2))then
            local goal = (j.stage == 2) and j.center or j.target
            local stageName = ""
            if j.jtype == "garbage" then
                local pts = j.points or {}
                local idx = tonumber(j.pointIndex) or 1
                local g = pts[idx]
                if istable(g) then goal = Vector(tonumber(g.x) or 0, tonumber(g.y) or 0, tonumber(g.z) or 0) end
                stageName = "точка " .. tostring(idx) .. "/" .. tostring(#pts)
            elseif j.jtype=="taxi"then
                stageName=j.taxiStandby and((j.stage==2)and"ожидание посадки"or"к клиенту")or((j.stage==2)and"к назначению"or"на посадку")
            end
            net.WriteBool(true)
            net.WriteVector(goal or j.target)
            net.WriteString(tostring(j.title or ""))
            net.WriteUInt(math.max(0, (j.deadline or os.time()) - os.time()), 20)
            net.WriteUInt(math.max(0, j.stayLeft or 0), 12)
            net.WriteUInt(j.stage or 1, 3)
            local zoneRadius = math.floor(tonumber(j.zoneRadius) or 180)
            if zoneRadius < 1 then zoneRadius = 1 elseif zoneRadius > 4095 then zoneRadius = 4095 end
            net.WriteUInt(zoneRadius, 12)
            net.WriteString(tostring(j.zoneName or "Точка работы"))
            net.WriteString(stageName)
            net.WriteBool(j.needVehicle == true)

            -- Полный маршрут (мусоровоз: точки сбора + свалка) — чтобы клиент
            -- рисовал GPS-метку на КАЖДУЮ точку, а не только текущую.
            local routePts = j.points or {}
            local routeNames = j.pointNames or {}
            net.WriteUInt(#routePts, 8)
            for _, p in ipairs(routePts) do
                local v = istable(p) and Vector(tonumber(p.x) or 0, tonumber(p.y) or 0, tonumber(p.z) or 0) or Vector(0, 0, 0)
                net.WriteVector(v)
            end
            net.WriteUInt(#routeNames, 8)
            for _, n in ipairs(routeNames) do net.WriteString(tostring(n)) end
            net.WriteUInt(math.max(1, tonumber(j.pointIndex) or 1), 8)
        else
            net.WriteBool(false)
        end
        net.Send(ply)
    end

    function JB.PushMyState(ply)
        if not IsValid(ply) then return end
        local sd = sid64(ply)
        local j = JB.Active[sd]
        local st = JB.StatsFor(sd) or { done = 0, earned = 0 }
        -- Флаг для клавиши G на клиенте: у мусоровоза G собирает пакет даже
        -- там, где физического контейнера на точке нет.
        local isGarbage = (istable(j) and (j.tplId == "garbage" or j.jtype == "garbage")) and true or false
        if ply.SetNWBool and ply:GetNWBool("GRM_GarbageJob", false) ~= isGarbage then ply:SetNWBool("GRM_GarbageJob", isGarbage) end
        net.Start(NET_MYSTATE)
            net.WriteBool(istable(j))
            if istable(j) then
                local stageName = ""
                if j.jtype == "garbage" then
                    -- Стадия мусоровоза: «собрано X/Y» пока едем по контейнерам,
                    -- «на полигон» — когда кузов набран полностью.
                    local total = #(j.points or {})
                    local stops = math.max(1, total - 1)
                    local idx = tonumber(j.pointIndex) or 1
                    if idx < 1 then idx = 1 elseif idx > math.max(1, total) then idx = math.max(1, total) end
                    if idx >= total then
                        stageName = ("на полигон • %d/%d"):format(stops, stops)
                    else
                        stageName = ("собрано %d/%d"):format(idx - 1, stops)
                    end
                elseif j.jtype=="taxi"then stageName=j.taxiStandby and((not j.taxiRequestID and"ожидание заказов")or(j.stage==2 and"такси прибыло"or"к клиенту"))or(j.stage==2 and"к назначению"or"на посадку")end
                net.WriteTable({
                    title = j.title, desc = j.desc, jtype = j.jtype,
                    stage = j.stage or 1, stayLeft = j.stayLeft or 0,
                    remain = math.max(0, (j.deadline or os.time()) - os.time()),
                    reward = j.reward or 0,
                    zoneName = j.zoneName or "Точка работы",
                    zoneRadius = j.zoneRadius or 180,
                    needVehicle = j.needVehicle == true,
                    stageName = stageName,
                    pointsTotal = #(j.points or {}),
                    pointIndex = tonumber(j.pointIndex) or 1,
                    tplId = j.tplId, budgetEscrow = tonumber(j.budgetEscrow) or 0,
                    fromPost = j.fromPost and true or false,
                    postFac = tostring(j.postFac or ""),
                })
            else
                net.WriteTable({})
            end
            net.WriteTable({ done = tonumber(st.done) or 0, earned = tonumber(st.earned) or 0 })
        net.Send(ply)
    end

    function JB.StartJob(ply, fields)
        local sd = sid64(ply)
        if istable(JB.Active[sd]) then
            if GRM.Notify then GRM.Notify(ply, "У вас уже есть активная задача. /jobcancel — отказаться.", 255, 190, 90) end
            return false
        end
        -- Член фракции может брать гражданскую подработку только вне службы.
        -- Без модуля Duty сохраняем строгое безопасное правило: фракционные
        -- сотрудники не смешивают службу с такси/курьером/мусоровозом.
        if not fields.fromPost then
            local fac = factionOfPly(ply)
            local canCivil = not fac
            if fac and GRM.FactionDuty and GRM.FactionDuty.CanTakeCivilJob then canCivil = GRM.FactionDuty.CanTakeCivilJob(ply) end
            if not canCivil then
                if GRM.Notify then GRM.Notify(ply, "Сотрудник фракции не может брать городскую работу, пока находится на службе. Завершите службу у служебного NPC.", 255, 150, 90) end
                return false
            end
        end
        local reserved = 0
        if not fields.fromPost and JB.ReserveSystemReward then
            local ok, amountOrWhy = JB.ReserveSystemReward(ply, fields.tplId or fields.jtype, fields.reward)
            if not ok then
                if GRM.Notify then GRM.Notify(ply, tostring(amountOrWhy or "В городской казне недостаточно средств."), 255, 130, 110) end
                return false
            end
            reserved = tonumber(amountOrWhy) or 0
        end
        JB.Active[sd] = {
            tplId = fields.tplId, budgetEscrow = reserved,
            title = fields.title, desc = fields.desc or "",
            jtype=fields.jtype or"goto",stage=fields.taxiStandby and 0 or 1,
            stayLeft = fields.staySec or 0,
            reward = fields.reward, deadline = os.time() + (fields.timeSec or 300),
            started = os.time(),
            target = fields.target, center = fields.center or (IsValid(ply) and ply:GetPos() or Vector(0, 0, 0)),
            zoneRadius = tonumber(fields.zoneRadius) or 180, zoneName = tostring(fields.zoneName or "Точка работы"),
            needVehicle = fields.needVehicle == true,
            points = fields.points, pointNames = fields.pointNames, pointIndex = 1,
            garbagePointIDs=fields.garbagePointIDs,garbageDumpID=fields.garbageDumpID,
            fromPost = fields.fromPost and true or false,
            postFac = fields.postFac, postId = fields.postId,
            postKind=fields.postKind,taxiStandby=fields.taxiStandby==true,garbageCollected=tonumber(fields.garbageCollected)or 0,
        }
        saveActive("старт")
        JB.PushTracker(ply)
        JB.PushMyState(ply)
        if GRM.Notify then local msg=fields.taxiStandby and("Смена такси начата. Ожидайте живые заказы и открывайте /taxi. Время: ")or("Задача принята: "..tostring(fields.title)..". Маркер цели появился на экране. Время: ");GRM.Notify(ply,msg..string.format("%d:%02d",math.floor((fields.timeSec or 300)/60),(fields.timeSec or 300)%60),120,220,255)end
        hook.Run("GRM_Jobs_Started", ply, JB.Active[sd])
        return true
    end

    -- остаток эскроу по посту (вакансия = зарплата×остаток смен)
    local function postEscrow(p)
        if not istable(p) then return 0 end
        if tostring(p.kind or "order") == "vacancy" then
            return (tonumber(p.salary) or 0) * (tonumber(p.shiftsLeft) or 0)
        end
        return tonumber(p.reward) or 0
    end

    local function releasePost(job, refundWhy)
        -- снять бронь с публикации фракции и вернуть эскроу в бюджет
        if not (istable(job) and job.fromPost) then return end
        local fac = JB.Cfg.posts and JB.Cfg.posts[tostring(job.postFac or "")]
        if istable(fac) then
            for i, p in ipairs(fac) do
                if tostring(p.id) == tostring(job.postId) then
                    if tostring(p.kind or "order") == "vacancy" and tostring(job.postKind or "") ~= "order" then
                        -- вакансия МНОГОРАЗОВАЯ: провал исполнителя снимает только его бронь,
                        -- смены и эскроу остаются (ни одна смена не оплачена — возвращать нечего)
                        p.takenBy = nil
                        JB.SaveCfg("бронь вакансии снята: " .. tostring(refundWhy or "-"))
                        if JB.NotifyEmployer then JB.NotifyEmployer(tostring(job.postFac), "Смена «" .. tostring(p.title) .. "» прервана (" .. tostring(refundWhy or "-") .. "). Вакансия снова доступна, осталось смен: " .. tostring(tonumber(p.shiftsLeft) or 0) .. ".") end
                    else
                        local esc = postEscrow(p)
                        if esc > 0 and GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(tostring(job.postFac), esc, "Биржа труда: возврат эскроу (" .. tostring(refundWhy or "-") .. ")") end
                        table.remove(fac, i)
                        JB.SaveCfg("возврат эскроу: " .. tostring(refundWhy or "-"))
                    end
                    break
                end
            end
        end
    end

    function JB.Complete(ply)
        local sd = sid64(ply)
        local j = JB.Active[sd]
        if not istable(j) then return end
        JB.Active[sd] = nil
        if j.fromPost then
            -- оплата уже в эскроу: с заказа снимаем с витрины, вакансию уменьшаем на смену
            local facName = tostring(j.postFac or "")
            local fac = JB.Cfg.posts and JB.Cfg.posts[facName]
            if istable(fac) then
                for i, p in ipairs(fac) do
                    if tostring(p.id) == tostring(j.postId) then
                        if tostring(p.kind or "order") == "vacancy" and j.postKind ~= "order" then
                            p.shiftsLeft = math.max(0, (tonumber(p.shiftsLeft) or 1) - 1)
                            p.payedTotal = (tonumber(p.payedTotal) or 0) + (tonumber(j.reward) or 0)
                            p.lastWorker = rpName(ply)
                            p.takenBy = nil
                            if p.shiftsLeft <= 0 then table.remove(fac, i) end
                            JB.NotifyEmployer(facName, "Смена «" .. tostring(p.title) .. "» отработана: " .. rpName(ply) .. " +" .. (GRM.Format and GRM.Format(j.reward) or tostring(j.reward)) .. ". Осталось смен: " .. tostring(p.shiftsLeft) .. ".")
                        else
                            table.remove(fac, i)
                            JB.NotifyEmployer(facName, "Заказ «" .. tostring(p.title) .. "» выполнен: " .. rpName(ply) .. " +" .. (GRM.Format and GRM.Format(j.reward) or tostring(j.reward)) .. ".")
                        end
                        break
                    end
                end
                JB.SaveCfg("публикация выполнена")
            end
        end
        local st = statRec(sd, rpName(ply))
        st.nick = rpName(ply)
        st.done = (tonumber(st.done) or 0) + 1
        st.earned = (tonumber(st.earned) or 0) + (tonumber(j.reward) or 0)
        if JB.NoteJobFinished then JB.NoteJobFinished(ply, j.tplId) end
        if GRM.GiveMoney then GRM.GiveMoney(ply, j.reward, "Биржа труда: " .. tostring(j.title)) end
        if GRM.Notify then GRM.Notify(ply, "Задача выполнена: " .. tostring(j.title) .. " (+" .. (GRM.Format and GRM.Format(j.reward) or tostring(j.reward)) .. ")", 120, 255, 150) end
        saveActive("выполнено")
        JB.SaveCfg("статистика")
        JB.PushTracker(ply)
        JB.PushMyState(ply)
        hook.Run("GRM_Jobs_Completed", ply, j)
    end

    function JB.Fail(ply, why, opts)
        local sd = isstring(ply) and ply or sid64(ply)
        local j = JB.Active[sd]
        if not istable(j) then return end
        JB.Active[sd] = nil
        if not j.fromPost and (tonumber(j.budgetEscrow) or 0) > 0 and JB.RefundSystemReward then
            JB.RefundSystemReward(j.budgetEscrow, tostring(why or "провал"))
        end
        releasePost(j, why)
        -- Провал даёт паузу, но НЕ съедает часовой лимит: иначе неудача
        -- наказывала бы дважды — и без денег, и без работы до конца часа.
        if JB.NoteJobFailed and not isstring(ply) then JB.NoteJobFailed(ply, j.tplId) end
        saveActive("провал: " .. tostring(why))
        local p = isstring(ply) and nil or ply
        if IsValid(p) then
            if GRM.Notify then GRM.Notify(p, "Задача провалена: " .. tostring(j.title) .. " (" .. tostring(why) .. ")", 255, 130, 110) end
            JB.PushTracker(p)
            JB.PushMyState(p)
            hook.Run("GRM_Jobs_Failed", p, j, tostring(why))
        end
    end

    -- движок прогресса ---------------------------------------------------
    function JB.TickJobs()
        local now = os.time()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local j = JB.Active[sid64(ply)]
                if istable(j) then
                    if (j.deadline or 0) < now then
                        JB.Fail(ply, "время вышло")
                    elseif ply:Alive() then
                        local pp = ply:GetPos()
                        local inVeh = ply:InVehicle() == true
                        local needVeh = j.needVehicle == true
                        local vehicleOK = inVeh and (not JB.IsWorkVehicleAllowed or JB.IsWorkVehicleAllowed(ply, j.tplId or j.jtype))
                        -- Загруженный сервером мусор является авторитетным доказательством
                        -- правильного мусоровоза, даже если LVS/simfphys отдал нестандартный pod.
                        if not vehicleOK and inVeh and j.tplId=="garbage"and JB.GetGarbageLoad then local cargoVeh=JB.GetPlayerGarbageTruck and JB.GetPlayerGarbageTruck(ply)or ply:GetVehicle();if IsValid(cargoVeh)and JB.GetGarbageLoad(cargoVeh)>0 then vehicleOK=true end end
                        -- Работа на транспорте: прогресс идёт только за рулём разрешённой машины.
                        if needVeh and not vehicleOK then
                            if (j._hintT or 0) < CurTime() then
                                j._hintT = CurTime() + 10
                                if GRM.Notify then GRM.Notify(ply, "Для этой работы нужен разрешённый транспорт — сядьте за руль подходящей машины.", 255, 190, 90) end
                            end
                        elseif j.jtype=="garbage"then
                            local pts=j.points or{};local idx=tonumber(j.pointIndex)or 1;local goal=pts[idx]
                            if not istable(goal)then JB.Complete(ply)
                            elseif idx>=#pts then
                                local gv=Vector(tonumber(goal.x)or 0,tonumber(goal.y)or 0,tonumber(goal.z)or 0);local rad=tonumber(j.zoneRadius)or 170;local veh=ply:GetVehicle()
                                if JB.TickGarbageDump then JB.TickGarbageDump(ply,j,veh,gv,rad)
                                elseif pp:DistToSqr(gv)<rad*rad and IsValid(veh)and(tonumber(veh.GRM_GarbageLoad)or 0)>0 then
                                    j.garbageDelivered=tonumber(veh.GRM_GarbageLoad)or 0;veh.GRM_GarbageLoad=0;veh:SetNWInt("GRM_GarbageLoad",0);JB.Complete(ply)
                                end
                            elseif(j._hintT or 0)<CurTime()then j._hintT=CurTime()+12;if GRM.Notify then GRM.Notify(ply,"Остановитесь у отмеченной точки, выйдите и нажмите E на мусорке (или G прямо на точке, если контейнера нет), затем загрузите пакет клавишей G сзади мусоровоза.",255,210,100)end end
                        elseif j.jtype=="taxi"and j.taxiStandby and JB.TickTaxiJob then
                            JB.TickTaxiJob(ply,j)
                        elseif j.jtype == "taxi" then
                            local rad = tonumber(j.zoneRadius) or 170
                            if (j.stage or 1) == 1 then
                                if pp:DistToSqr(j.target) < rad * rad then
                                    j.stage = 2
                                    saveActive("такси: посадка")
                                    JB.PushTracker(ply) JB.PushMyState(ply)
                                    if GRM.Notify then GRM.Notify(ply, "Пассажир на борту — везите к пункту назначения.", 120, 220, 255) end
                                end
                            else
                                if pp:DistToSqr(j.center) < rad * rad then JB.Complete(ply) end
                            end
                        elseif j.jtype == "stay" or j.jtype == "shift" then
                            local rad = tonumber(j.zoneRadius) or ((j.jtype == "shift") and 400 or 300)
                            if pp:DistToSqr(j.target) < rad * rad then
                                if ply:InVehicle() then
                                    if (j._hintT or 0) < CurTime() then
                                        j._hintT = CurTime() + 10
                                        if GRM.Notify then GRM.Notify(ply, "Выйдите из транспорта — смена засчитывается только на своих двоих.", 255, 190, 90) end
                                    end
                                else
                                    j.stayLeft = (j.stayLeft or 0) - 1
                                    if (j.stayLeft or 0) <= 0 then JB.Complete(ply)
                                    elseif (j.stayLeft % 15) == 0 then JB.PushMyState(ply) end
                                end
                            elseif (j._hintT or 0) < CurTime() then
                                j._hintT = CurTime() + 20
                                if GRM.Notify then GRM.Notify(ply, tostring(j.title) .. ": вы вне рабочей зоны — вернитесь к маркеру (" .. tostring(math.floor(math.sqrt(pp:DistToSqr(j.target)))) .. " юн).", 255, 190, 90) end
                            end
                        elseif j.jtype == "roundtrip" and (j.stage or 1) == 1 then
                            local targetRadius = tonumber(j.zoneRadius) or 170
                            if pp:DistToSqr(j.target) < targetRadius * targetRadius then
                                j.stage = 2
                                saveActive("этап 2")
                                JB.PushTracker(ply)
                                JB.PushMyState(ply)
                                if GRM.Notify then GRM.Notify(ply, "Точка проверена. Возвращайтесь к терминалу биржи.", 120, 220, 255) end
                            end
                        elseif j.jtype == "roundtrip" then
                            local returnRadius = tonumber(j.zoneRadius) or 220
                            if pp:DistToSqr(j.center) < returnRadius * returnRadius then JB.Complete(ply) end
                        else -- goto
                            local targetRadius = tonumber(j.zoneRadius) or 170
                            if pp:DistToSqr(j.target) < targetRadius * targetRadius then
                                --[[ У КУРЬЕРА ДОСТАВКА = ДОСТАВКА ГРУЗА.
                                     Дойти до адреса мало: посылку могли
                                     отнять, уронить при смерти или увести.
                                     Без неё точка не засчитывается — иначе
                                     физический предмет был бы декорацией. ]]
                                if j.tplId == "courier" and JB.HasParcel then
                                    if JB.HasParcel(ply) then
                                        if JB.DeliverParcel then JB.DeliverParcel(ply, j) else JB.Complete(ply) end
                                    elseif (j._parcelHintAt or 0) < CurTime() then
                                        j._parcelHintAt = CurTime() + 8
                                        if GRM.Notify then GRM.Notify(ply, "Вы на месте, но посылки нет. Найдите её и вернитесь.", 255, 150, 110) end
                                    end
                                else
                                    JB.Complete(ply)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    timer.Create("GRM_Jobs_Tick", 1, 0, function() JB.TickJobs() end)
    timer.Create("GRM_Jobs_Save", 30, 0, function() saveActive("авто 30с") end)
    hook.Add("PlayerDisconnected", "GRM_Jobs_Disc", function() saveActive("дисконнект") end)
    hook.Add("ShutDown", "GRM_Jobs_Shut", function() saveActive("shutdown") JB.SaveCfg("shutdown") end)

    -- просроченные заказы фракций (возврат эскроу) ------------------------
    timer.Create("GRM_Jobs_PostSweep", 600, 0, function()
        local now, dropped = os.time(), 0
        for fac, list in pairs(JB.Cfg.posts or {}) do
            if istable(list) then
                for i = #list, 1, -1 do
                    local p = list[i]
                    if tonumber(p.exp or 0) > 0 and p.exp < now and p.takenBy == nil then
                        local esc = postEscrow(p)
                        if esc > 0 and GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fac, esc, "Биржа труда: публикация просрочена") end
                        table.remove(list, i)
                        dropped = dropped + 1
                    end
                end
            end
        end
        if dropped > 0 then JB.SaveCfg("зачистка просроченных заказов") print("[GRM Jobs] Просрочено заказов: " .. tostring(dropped)) end
    end)

    -- открытие меню -------------------------------------------------------
    function JB.OpenMenu(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return end
        local offers, err = buildOffers(ent)
        JB._lastOffers[sid64(ply)] = { list = offers or {}, at = os.time(), center = ent:GetPos() }
        local wire = {}
        for _, o in ipairs(offers or {}) do
            local shownReward=o.reward
            wire[#wire + 1] = { idx = o.idx, tplId = o.tplId, title = o.title, desc = o.desc, jtype = o.jtype, reward = shownReward, timeSec = o.timeSec, staySec = o.staySec, dist = o.dist, zoneRadius = o.zoneRadius, zoneName = o.zoneName, needVehicle = o.needVehicle == true, blockedReason=tostring(o.blockedReason or""), icon = o.icon, color = o.color }
        end
        local sd = sid64(ply)
        local j = JB.Active[sd]
        local activeWire = {}
        if istable(j) then
            activeWire = {
                title = j.title, desc = j.desc, jtype = j.jtype, stage = j.stage or 1,
                stayLeft = j.stayLeft or 0, remain = math.max(0, (j.deadline or os.time()) - os.time()),
                reward = j.reward or 0, zoneRadius = j.zoneRadius or 180, zoneName = j.zoneName or "Точка работы", fromPost = j.fromPost and true or false, postFac = tostring(j.postFac or ""),
            }
        end
        local postsWire = {}
        for fac, list in pairs(JB.Cfg.posts or {}) do
            if istable(list) then
                for _, p in ipairs(list) do
                    postsWire[#postsWire + 1] = {
                        id = tonumber(p.id) or 0, faction = fac, title = tostring(p.title or ""),
                        desc = tostring(p.desc or ""), jtype = tostring(p.jtype or "goto"),
                        kind = tostring(p.kind or "order"),
                        reward = tonumber(p.reward) or 0, salary = tonumber(p.salary) or 0,
                        shiftSec = tonumber(p.shiftSec) or 0, shiftsLeft = tonumber(p.shiftsLeft) or 0,
                        payedTotal = tonumber(p.payedTotal) or 0, lastWorker = tostring(p.lastWorker or ""),
                        author = tostring(p.author or ""),
                        taken = p.takenBy ~= nil, mine = (tostring(p.authorSid or "") == sd),
                    }
                end
            end
        end
        table.sort(postsWire, function(a, b) return a.id > b.id end)
        local allowWire = {}
        if istable(Factions) then
            for name in pairs(Factions) do
                allowWire[#allowWire + 1] = { name = name, allowed = JB.Cfg.allow[name] == true }
            end
        end
        table.sort(allowWire, function(a, b) return a.name:lower() < b.name:lower() end)
        local st = JB.StatsFor(sd) or { done = 0, earned = 0 }
        local canP, myFac = canPost(ply)

        net.Start(NET_OPEN)
            net.WriteBool(ply:IsSuperAdmin())
            net.WriteBool(canP and true or false)
            net.WriteString(tostring(myFac or ""))
            net.WriteString(tostring(err or ""))
            net.WriteTable(wire)
            net.WriteTable(activeWire)
            net.WriteTable(postsWire)
            net.WriteTable(allowWire)
            net.WriteTable({ done = tonumber(st.done) or 0, earned = tonumber(st.earned) or 0 })
        net.Send(ply)
    end

    -- цель для заказа фракции назначается при взятии ----------------------
    local function assignTarget()
        local dps = depots()
        if #dps == 0 then return nil end
        return dps[math.random(1, #dps)]:GetPos()
    end

    -- сеть: приём команд клиента ------------------------------------------
    net.Receive(NET_ACCEPT, function(_, ply)
        if not IsValid(ply) then return end
        local idx = tonumber(net.ReadUInt(8)) or 0
        local rec = JB._lastOffers[sid64(ply)]
        if not istable(rec) or (os.time() - (rec.at or 0)) > 600 then
            if GRM.Notify then GRM.Notify(ply, "Список вакансий устарел — откройте терминал заново.", 255, 190, 90) end
            return
        end
        local offer = istable(rec.list) and rec.list[idx] or nil
        if not istable(offer) then
            if GRM.Notify then GRM.Notify(ply, "Вакансия не найдена (список обновился).", 255, 190, 90) end
            return
        end
        if tostring(offer.blockedReason or"")~=""then if GRM.Notify then GRM.Notify(ply,tostring(offer.blockedReason),255,150,95)end return end
        --[[ ТЕМП РАБОТ. Раньше ограничителем служила только казна: пока в
             ней есть деньги, одну и ту же короткую задачу можно было
             брать без остановки. Пауза и часовой потолок живут в
             sh_grm_jobs_limits.lua. ]]
        if JB.CanTakeJob then
            local allowed, why = JB.CanTakeJob(ply)
            if not allowed then
                if GRM.Notify then GRM.Notify(ply, tostring(why or "Сейчас работу взять нельзя."), 255, 190, 110) end
                return
            end
        end
        local reward=offer.reward
        JB.StartJob(ply, {
            tplId = offer.tplId, title = offer.title, desc = offer.desc, jtype = offer.jtype,
            reward = reward, timeSec = offer.timeSec, staySec = offer.staySec,
            target = offer.target, center = offer.center or rec.center,
            zoneRadius = offer.zoneRadius, zoneName = offer.zoneName,
            needVehicle = offer.needVehicle == true,
            points=offer.points,pointNames=offer.pointNames,garbagePointIDs=offer.garbagePointIDs,garbageDumpID=offer.garbageDumpID,taxiStandby=offer.taxiStandby==true,
        })
    end)

    net.Receive(NET_CANCEL, function(_, ply)
        if not IsValid(ply) then return end
        if istable(JB.Active[sid64(ply)]) then
            JB.Fail(ply, "отказ работника")
        else
            if GRM.Notify then GRM.Notify(ply, "Активной задачи нет.", 200, 200, 210) end
        end
    end)

    -- уведомить лидера фракции-заказчика (если он в сети)
    local function notifyEmployer(fac, text)
        local lsid = (_G.FactionsAPI and _G.FactionsAPI.GetLeader) and _G.FactionsAPI.GetLeader(fac) or nil
        if not lsid and istable(Factions) and istable(Factions[fac]) then lsid = Factions[fac].Leader end
        if not lsid then return end
        local leader = player.GetBySteamID(tostring(lsid))
        if IsValid(leader) then
            leader:PrintMessage(HUD_PRINTTALK, "[Биржа • " .. fac .. "] " .. tostring(text))
            if GRM.Notify then GRM.Notify(leader, text, 160, 200, 255) end
        end
    end
    JB.NotifyEmployer = notifyEmployer
    JB.PostEscrow = postEscrow -- (объявлен выше, рядом с releasePost)

    net.Receive(NET_POST, function(_, ply)
        if not IsValid(ply) then return end
        local canP, myFac = canPost(ply)
        if not (canP or ply:IsSuperAdmin()) then
            if GRM.Notify then GRM.Notify(ply, "Публиковать заказы может лидер фракции с доступом «БИРЖА» (/job_allow).", 255, 130, 110) end
            return
        end
        if not myFac then
            if GRM.Notify then GRM.Notify(ply, "Вы не состоите во фракции.", 255, 130, 110) end
            return
        end
        local kind  = tostring(net.ReadString() or "order")
        local title = string.Trim(net.ReadString() or "")
        local desc  = string.Trim(net.ReadString() or "")
        local jtype = tostring(net.ReadString() or "goto")
        local money = math.floor(tonumber(net.ReadUInt(20)) or 0)   -- разовая награда / зарплата за смену
        local shiftSec = tonumber(net.ReadUInt(12)) or 600           -- вакансия: длительность смены
        local shifts   = tonumber(net.ReadUInt(8))  or 1             -- вакансия: число смен
        local zoneMode = tostring(net.ReadString() or "term")        -- "term" — точка терминала, "here" — где стою
        if kind ~= "vacancy" then kind = "order" end
        if jtype ~= "goto" and jtype ~= "stay" and jtype ~= "roundtrip" then jtype = "goto" end
        local SHIFT_SET = { [300] = true, [600] = true, [900] = true, [1200] = true }
        if not SHIFT_SET[shiftSec] then shiftSec = 600 end
        shifts = math.floor(shifts)
        if shifts < 1 then shifts = 1 end
        if shifts > JB.MaxShifts then shifts = JB.MaxShifts end
        if #title < 4 or #title > 40 then
            if GRM.Notify then GRM.Notify(ply, "Название: 4–40 символов.", 255, 190, 90) end
            return
        end
        desc = string.sub(desc, 1, 120)
        if kind == "order" and (money < JB.MinReward or money > JB.MaxReward) then
            if GRM.Notify then GRM.Notify(ply, "Награда разового заказа: " .. tostring(JB.MinReward) .. "–" .. tostring(JB.MaxReward) .. ".", 255, 190, 90) end
            return
        end
        if kind == "vacancy" and (money < JB.MinSalary or money > JB.MaxSalary) then
            if GRM.Notify then GRM.Notify(ply, "Зарплата за смену: " .. tostring(JB.MinSalary) .. "–" .. tostring(JB.MaxSalary) .. ".", 255, 190, 90) end
            return
        end
        local escrow = (kind == "vacancy") and (money * shifts) or money
        JB.Cfg.posts[myFac] = JB.Cfg.posts[myFac] or {}
        if #JB.Cfg.posts[myFac] >= JB.MaxPosts then
            if GRM.Notify then GRM.Notify(ply, "Лимит: " .. tostring(JB.MaxPosts) .. " заказа(ов) одновременно на фракцию.", 255, 190, 90) end
            return
        end
        if GRM.FactionBudgetGet and (GRM.FactionBudgetGet(myFac) or 0) < escrow then
            if GRM.Notify then GRM.Notify(ply, "В бюджете недостаточно средств для эскроу " .. tostring(escrow) .. ".", 255, 130, 110) end
            return
        end
        -- зона смены: от точки терминала или с текущей позиции лидера (/jobpost у станка)
        local zone = nil
        if kind == "vacancy" then
            if zoneMode == "here" then
                zone = ply:GetPos()
            else
                local rec = JB._lastOffers and JB._lastOffers[sid64(ply)]
                zone = (istable(rec) and rec.center) or ply:GetPos()
            end
        end
        local id = tonumber(JB.Cfg.nextId) or 1
        JB.Cfg.nextId = id + 1
        if GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(myFac, -escrow, "Биржа труда: эскроу «" .. title .. "»") end
        local staySec = (kind == "vacancy") and shiftSec or ((jtype == "stay") and 90 or 0)
        local timeSec = (kind == "vacancy") and (shiftSec + 300) or ((jtype == "stay") and 420 or ((jtype == "roundtrip") and 900 or 600))
        JB.Cfg.posts[myFac][#JB.Cfg.posts[myFac] + 1] = {
            id = id, kind = kind, title = title, desc = desc, jtype = jtype,
            reward = (kind == "order") and money or nil,
            salary = (kind == "vacancy") and money or nil,
            shiftSec = (kind == "vacancy") and shiftSec or nil,
            shiftsLeft = (kind == "vacancy") and shifts or nil,
            zone = zone and { x = zone.x, y = zone.y, z = zone.z } or nil,
            author = rpName(ply), authorSid = sid64(ply), time = os.time(),
            exp = os.time() + JB.PostExpire, staySec = staySec, timeSec = timeSec,
            payedTotal = 0, lastWorker = "",
        }
        JB.SaveCfg("новый " .. kind .. " " .. myFac)
        if GRM.Notify then GRM.Notify(ply, "«" .. title .. "» опубликовано (" .. (GRM.Format and GRM.Format(escrow) or tostring(escrow)) .. " эскроу с бюджета " .. myFac .. ").", 120, 255, 150) end
        ply:PrintMessage(HUD_PRINTTALK, (kind == "vacancy") and
            ("[Биржа] Вакансия «" .. title .. "»: " .. tostring(shifts) .. " смен × " .. (GRM.Format and GRM.Format(money) or tostring(money)) .. ". Исполнителей ждём у терминалов биржи.") or
            ("[Биржа] Заказ «" .. title .. "» опубликован. Исполнителей ждём у терминалов биржи труда."))
    end)

    net.Receive(NET_UNPOST, function(_, ply)
        if not IsValid(ply) then return end
        local fac = tostring(net.ReadString() or "")
        local id = tostring(net.ReadUInt(32) or 0)
        local canP, myFac = canPost(ply)
        if not (ply:IsSuperAdmin() or (canP and myFac == fac)) then return end
        local list = JB.Cfg.posts and JB.Cfg.posts[fac]
        if not istable(list) then return end
        for i, p in ipairs(list) do
            if tostring(p.id) == id then
                if p.takenBy ~= nil then
                    -- исполнитель уже в пути: проваливаем его задачу
                    -- (разовый заказ удалится сам в releasePost, вакансия останется со снятой бронью)
                    for _, pl in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                        if IsValid(pl) then
                            local j = JB.Active[sid64(pl)]
                            if istable(j) and j.fromPost and tostring(j.postId) == tostring(p.id) then
                                JB.Fail(pl, "публикация отозвана заказчиком")
                            end
                        end
                    end
                end
                -- пост ещё на витрине (не удалён releasePost)? вернуть остаток эскроу и снять
                local idx = nil
                for k, q in ipairs(list) do if tostring(q.id) == id then idx = k break end end
                local refund = 0
                if idx then
                    refund = postEscrow(p)
                    if refund > 0 and GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fac, refund, "Биржа труда: публикация отозвана") end
                    table.remove(list, idx)
                    JB.SaveCfg("отзыв публикации")
                end
                if GRM.Notify then GRM.Notify(ply, "«" .. tostring(p.title) .. "» отозвано" .. (refund > 0 and (", остаток эскроу " .. (GRM.Format and GRM.Format(refund) or tostring(refund)) .. " возвращён в бюджет.") or "."), 255, 190, 90) end
                return
            end
        end
    end)

    net.Receive(NET_TAKEPOST, function(_, ply)
        if not IsValid(ply) then return end
        local fac = tostring(net.ReadString() or "")
        local id = tostring(net.ReadUInt(32) or 0)
        local list = JB.Cfg.posts and JB.Cfg.posts[fac]
        if not istable(list) then return end
        for _, p in ipairs(list) do
            if tostring(p.id) == id then
                local isVac = tostring(p.kind or "order") == "vacancy"
                if p.takenBy ~= nil then
                    if GRM.Notify then GRM.Notify(ply, "Уже выполняется другим исполнителем.", 255, 190, 90) end
                    return
                end
                if tostring(p.authorSid or "") == sid64(ply) then
                    if GRM.Notify then GRM.Notify(ply, "Свою собственную публикацию выполнять нельзя.", 255, 190, 90) end
                    return
                end
                if isVac and (tonumber(p.shiftsLeft) or 0) <= 0 then
                    if GRM.Notify then GRM.Notify(ply, "Смены по вакансии исчерпаны.", 255, 190, 90) end
                    return
                end
                local target
                if isVac and istable(p.zone) then
                    target = Vector(tonumber(p.zone.x) or 0, tonumber(p.zone.y) or 0, tonumber(p.zone.z) or 0)
                else
                    target = assignTarget()
                end
                if not target then
                    if GRM.Notify then GRM.Notify(ply, "В городе нет точек доставки — администрации: /jobdepot_add.", 255, 130, 110) end
                    return
                end
                local ok = JB.StartJob(ply, {
                    title = tostring(p.title) .. (isVac and (" [вакансия " .. fac .. "]") or (" [заказ " .. fac .. "]")),
                    desc = tostring(p.desc or ""),
                    jtype = isVac and "shift" or p.jtype,
                    reward = isVac and (tonumber(p.salary) or 0) or (tonumber(p.reward) or 0),
                    timeSec = tonumber(p.timeSec) or 600,
                    staySec = tonumber(p.staySec) or 0,
                    target = target, center = target, zoneRadius = isVac and 400 or 180,
                    zoneName = tostring(p.title or "Рабочая зона"),
                    fromPost = true, postFac = fac, postId = p.id,
                    postKind = isVac and "vacancy" or "order",
                })
                if ok then
                    p.takenBy = sid64(ply)
                    JB.SaveCfg(isVac and "смена начата" or "заказ взят")
                    if isVac then JB.NotifyEmployer(fac, "На смену «" .. tostring(p.title) .. "» вышел " .. rpName(ply) .. " (осталось смен: " .. tostring(p.shiftsLeft) .. ").") end
                end
                return
            end
        end
        if GRM.Notify then GRM.Notify(ply, "Публикация не найдена (уже закрыта).", 255, 190, 90) end
    end)

    net.Receive(NET_ALLOW, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local fname = tostring(net.ReadString() or "")
        local allow = net.ReadBool()
        if not (istable(Factions) and istable(Factions[fname])) then return end
        JB.Cfg.allow[fname] = allow and true or nil
        JB.SaveCfg("доступ БИРЖА " .. fname .. " = " .. tostring(allow))
        ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Доступ работодателя — «" .. fname .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН"))
    end)

    net.Receive(NET_GETMY, function(_, ply)
        if IsValid(ply) then JB.PushMyState(ply) end
    end)

    hook.Add("PlayerInitialSpawn", "GRM_Jobs_Join", function(ply)
        timer.Simple(4, function()
            if IsValid(ply) then JB.PushTracker(ply) JB.PushMyState(ply) end
        end)
    end)

    -- спавн энтити --------------------------------------------------------
    local function spawnAtAim(ply, class, label)
        if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Только суперадмин.") return true end
        local tr = ply:GetEyeTrace()
        local pos = (tr and tr.HitPos) and (tr.HitPos + Vector(0, 0, 2)) or (ply:GetPos() + ply:GetForward() * 60)
        local ent = ents.Create(class)
        if not IsValid(ent) then ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Не удалось создать " .. tostring(class)) return true end
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        ent:Spawn() ent:Activate()
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        JB.PersistAdd(ent)
        ply:PrintMessage(HUD_PRINTTALK, "[Биржа] " .. label .. " установлен и СОХРАНЁН автоматически (grm_jobs_ents). Снятие — наведитесь и повторите remove-команду.")
        return true
    end
    local function removeAtAim(ply, class, label)
        if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Только суперадмин.") return true end
        local tr = ply:GetEyeTrace()
        local ent = tr and tr.Entity or nil
        if IsValid(ent) and ent:GetClass() == class then
            JB.PersistRemove(ent)
            ent:Remove()
            ply:PrintMessage(HUD_PRINTTALK, "[Биржа] " .. label .. " снят (запись персиста удалена).")
        else
            ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Наведите прицел на объект (" .. tostring(class) .. ").")
        end
        return true
    end

    local function editAccess(fname, allow, ply)
        if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Только суперадмин.") return true end
        fname = string.Trim(fname or "")
        if not (istable(Factions) and istable(Factions[fname])) then
            ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Фракция «" .. fname .. "» не найдена.")
            return true
        end
        JB.Cfg.allow[fname] = allow and true or nil
        JB.SaveCfg("job_allow " .. fname)
        ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Доступ работодателя — «" .. fname .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН"))
        return true
    end

    function JB.HandleChat(ply, text)
        if not IsValid(ply) then return false end
        local t = string.Trim(tostring(text or ""))
        local low = string.lower(t)
        if low == "/jobs" or low == "/job" then
            local j = JB.Active[sid64(ply)]
            if istable(j) then
                local left = math.max(0, (j.deadline or os.time()) - os.time())
                ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Текущая задача: " .. tostring(j.title) ..
                    " | осталось " .. string.format("%d:%02d", math.floor(left / 60), left % 60) ..
                    (j.jtype == "stay" and (" | ещё " .. tostring(j.stayLeft) .. " с в зоне") or "") ..
                    (j.jtype == "roundtrip" and (j.stage == 2 and " | этап: возврат" or " | этап: к точке") or "") ..
                    " | награда " .. (GRM.Format and GRM.Format(j.reward) or tostring(j.reward)))
            else
                ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Активной задачи нет. Вакансии — у терминала биржи (иконка в Q-меню: «Биржа труда GRM»).")
            end
            return true
        end
        if low == "/jobcancel" then
            if istable(JB.Active[sid64(ply)]) then JB.Fail(ply, "отказ работника")
            else ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Активной задачи нет.") end
            return true
        end
        if low == "/jobpost" then
            -- публикация заказа/вакансии С ЛЮБОГО места (лидер с доступом «БИРЖА»);
            -- зона смены вакансии = текущая позиция лидера (у станка, на заводе)
            local canP, myFac = canPost(ply)
            if not (canP or ply:IsSuperAdmin()) then
                ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Публиковать может лидер фракции с доступом «БИРЖА» (/job_allow у суперадмина или /factions → «Доступы»).")
                return true
            end
            net.Start(NET_FORM)
                net.WriteString(tostring(myFac or ""))
            net.Send(ply)
            return true
        end
        if low == "/jobcenter_add" then return spawnAtAim(ply, "grm_jobcenter", "Терминал биржи труда") end
        if low == "/jobcenter_remove" then return removeAtAim(ply, "grm_jobcenter", "Терминал биржи труда") end
        if low == "/jobdepot_add" then return spawnAtAim(ply, "grm_depot", "Точка доставки") end
        if low == "/jobdepot_remove" then return removeAtAim(ply, "grm_depot", "Точка доставки") end
        if string.sub(low, 1, 11) == "/job_allow " then return editAccess(string.sub(t, 12), true, ply) end
        if string.sub(low, 1, 10) == "/job_deny " then return editAccess(string.sub(t, 11), false, ply) end
        if low == "/job_list" then
            if ply:IsSuperAdmin() then
                local n = 0
                for sd, j in pairs(JB.Active) do
                    n = n + 1
                    ply:PrintMessage(HUD_PRINTTALK, "[Биржа] " .. tostring(sd) .. ": " .. tostring(j.title) .. " (" .. tostring(j.jtype) .. ")")
                end
                ply:PrintMessage(HUD_PRINTTALK, "[Биржа] Активных задач: " .. tostring(n))
            end
            return true
        end
        return false
    end

    hook.Add("PlayerSayTransform", "GRM_Jobs_TransformCmds", function(ply, datapack)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        if JB.HandleChat and JB.HandleChat(ply, msg) then
            datapack[1] = ""
            datapack.SkipPlayerSay = true
        end
    end)

    hook.Add("PlayerSay", "GRM_Jobs_ChatCmds", function(ply, text)
        if JB.HandleChat and JB.HandleChat(ply, text) then return "" end
    end)

    print("[GRM Jobs] Биржа труда v" .. JB.Version .. " загружена (Код 77)")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMJobs_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
    surface.CreateFont("GRMJobs_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMJobs_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMJobs_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })
    surface.CreateFont("GRMJobs_3D",     { font = "Roboto", size = 26, weight = 800, extended = true })

    local C = {
        bg    = Color(24, 28, 38, 240),
        head  = Color(18, 22, 30, 255),
        panel = Color(32, 38, 50, 245),
        panel2= Color(26, 32, 42, 235),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        red   = Color(220, 75, 70),
        yellow= Color(230, 180, 60),
        teal  = Color(80, 200, 170),
        text  = Color(240, 245, 250),
        dim   = Color(170, 180, 195),
    }

    local function fmtMoney(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end
    local function fmtTime(s)
        s = math.max(0, math.floor(tonumber(s) or 0))
        return string.format("%d:%02d", math.floor(s / 60), s % 60)
    end

    -- 3D-маркер цели -------------------------------------------------------
    local tracker = nil
    net.Receive(NET_TRACKER, function()
        local active = net.ReadBool()
        if active then
            tracker = {
                target = net.ReadVector(),
                title = net.ReadString() or "",
                remain = net.ReadUInt(20),
                stayLeft = net.ReadUInt(12),
                stage = net.ReadUInt(3),
                radius = net.ReadUInt(12),
                zoneName = net.ReadString() or "Точка работы",
                stageName = net.ReadString() or "",
                needVehicle = net.ReadBool(),
                at = CurTime(),
            }
            -- Полный маршрут (мусоровоз): точки сбора + свалка.
            local nPts = net.ReadUInt(8)
            tracker.points = {}
            for i = 1, nPts do tracker.points[i] = net.ReadVector() end
            local nNames = net.ReadUInt(8)
            tracker.pointNames = {}
            for i = 1, nNames do tracker.pointNames[i] = net.ReadString() end
            tracker.pointIndex = net.ReadUInt(8)
        else
            tracker = nil
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "GRM_Jobs_Marker", function()
        if not istable(tracker) then return end
        -- Если это маршрут мусоровоза (есть точки сбора + свалка), их рисует
        -- GRM_Jobs_GarbageRouteMarkers сквозь браши — не дублируем текущую сферу.
        if istable(tracker.points) and #tracker.points > 0 then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local radius = math.max(40, tonumber(tracker.radius) or 180)
        render.SetColorMaterial()
        -- 32x12 строило сотни линий каждый кадр и давало клиентские spikes.
        render.DrawWireframeSphere(tracker.target, radius, 16, 8, Color(70, 180, 255, 90), true)
        local pos = tracker.target + Vector(0, 0, 46 + math.sin(CurTime() * 2.5) * 6)
        local dist = math.floor(lp:GetPos():Distance(tracker.target))
        local ang = Angle(0, EyeAngles().y - 90, 90)
        cam.Start3D2D(pos, ang, 0.14)
            draw.RoundedBox(8, -130, -46, 260, 66, Color(16, 20, 28, 215))
            surface.SetDrawColor(C.yellow.r, C.yellow.g, C.yellow.b, 220)
            surface.DrawOutlinedRect(-130, -46, 260, 66, 2)
            draw.SimpleText("◎ " .. tostring(tracker.title), "GRMJobs_Sub", 0, -40, C.yellow, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(tostring(tracker.zoneName or "Рабочая зона") .. " • " .. tostring(dist) .. " юн.", "GRMJobs_Normal", 0, -16, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        cam.End3D2D()
    end)

    -- Экранная GPS-метка точки (как в модуле GPS-меток): рисуется на 2D-экране,
    -- поэтому ВИДНА СКВОЗЬ любые браши — «три здания» между игроком и точкой не
    -- мешают. Если точка вне поля зрения — стрелка-указатель по краю экрана.
    local function drawScreenMarker(target, name, dist, col, sw, sh)
        local screen = target:ToScreen()
        local visible = screen.visible == true and screen.x > 0 and screen.x < sw and screen.y > 0 and screen.y < sh
        local x, y = screen.x or sw / 2, screen.y or sh / 2
        local radius = math.Clamp(9 + dist / 450, 10, 22)

        if not visible then
            -- Стрелка-указатель направления по краю экрана.
            local dx, dy = x - sw / 2, y - sh / 2
            local len = math.max(1, math.sqrt(dx * dx + dy * dy))
            dx, dy = dx / len, dy / len
            x = math.Clamp(sw / 2 + dx * (sw / 2 - 40), 30, sw - 30)
            y = math.Clamp(sh / 2 + dy * (sh / 2 - 40), 30, sh - 30)
            surface.SetDrawColor(col.r, col.g, col.b, 255)
            surface.DrawPoly({
                { x = x + dx * 20, y = y + dy * 20 },
                { x = x - dx * 11 - dy * 11, y = y - dy * 11 + dx * 11 },
                { x = x - dx * 11 + dy * 11, y = y - dy * 11 - dx * 11 },
            })
        end

        local pulse = math.sin(CurTime() * 4) * 3
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        surface.DrawCircle(x, y, radius + pulse, col.r, col.g, col.b, 255)
        surface.SetDrawColor(8, 14, 23, 240)
        surface.DrawCircle(x, y, math.max(3, radius - 4), 8, 14, 23, 240)

        local textX = math.Clamp(x + radius + 14, 14, sw - 14)
        local align = textX > sw - 220 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT
        draw.SimpleTextOutlined(tostring(name), "GRMJobs_Sub", textX, y - 11, color_white, align, TEXT_ALIGN_CENTER, 2, Color(8, 14, 23, 235))
        draw.SimpleTextOutlined(dist .. " юн.", "GRMJobs_Small", textX, y + 9, Color(col.r, col.g, col.b), align, TEXT_ALIGN_CENTER, 2, Color(8, 14, 23, 235))
    end

    -- GPS-метки маршрута мусоровоза: СТРОГО ПО ОЧЕРЕДИ (заказ владельца).
    -- Одновременно на экране ровно ОДНА метка — текущая цель:
    --   * пока собираем мусор — метка контейнера №N; она гаснет ТОЛЬКО когда
    --     игрок реально загрузил пакет в кузов (сервер двигает pointIndex
    --     в loadGarbage, см. sh_grm_jobs_v4.lua) — не по приближению;
    --   * когда собрано 3/3 — вместо контейнера появляется метка полигона.
    -- Раньше рисовались все точки сразу, и «мусорка + свалка» висели вместе.
    hook.Add("HUDPaint", "GRM_Jobs_GarbageRouteMarkers", function()
        if not istable(tracker) or not istable(tracker.points) or #tracker.points == 0 then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local sw, sh = ScrW(), ScrH()
        local total = #tracker.points
        local current = math.Clamp(tonumber(tracker.pointIndex) or 1, 1, total)
        local p = tracker.points[current]
        if not p then return end

        local isDump = (current == total)
        local collected = math.max(0, current - 1)
        local stops = math.max(1, total - 1)
        local col = isDump and Color(90, 220, 120) or Color(255, 210, 70)
        local dist = math.floor(lp:GetPos():Distance(p))
        local name = tracker.pointNames[current]
        if name == nil or name == "" then name = isDump and "Полигон (свалка)" or ("Контейнер " .. current) end

        local head
        if isDump then
            head = ("ПОЛИГОН • мусор собран %d/%d"):format(collected, stops)
        else
            head = ("СОБРАТЬ МУСОР %d/%d"):format(collected, stops)
        end
        drawScreenMarker(p, head .. " — " .. name, dist, col, sw, sh)
    end)


    hook.Add("HUDPaint", "GRM_Jobs_HudLine", function()
        if not istable(tracker) then return end
        local left = math.max(0, (tracker.remain or 0) - (CurTime() - (tracker.at or CurTime())))
        local txt = "Работа: " .. tostring(tracker.title) ..
            "  •  " .. fmtTime(left) ..
            ((tracker.stageName ~= nil and tracker.stageName ~= "") and ("  •  " .. tostring(tracker.stageName)) or "") ..
            (tracker.needVehicle and "  •  нужен транспорт" or "") ..
            ((tracker.stayLeft or 0) > 0 and ("  •  в зоне: " .. tostring(tracker.stayLeft) .. " с") or "")
        local w, h = ScrW(), ScrH()
        draw.RoundedBox(6, w / 2 - 300, h - 52, 600, 26, Color(14, 18, 26, 190))
        draw.SimpleText(txt, "GRMJobs_Normal", w / 2, h - 39, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    -- Экранная GPS-метка одиночной точки работы (курьер/такси). Маршрут
    -- мусоровоза рисует отдельный хук GRM_Jobs_GarbageRouteMarkers.
    hook.Add("HUDPaint", "GRM_Jobs_GPSMarker", function()
        if not istable(tracker) or not tracker.target then return end
        if istable(tracker.points) and #tracker.points > 0 then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local target = tracker.target
        local distance = math.floor(lp:GetPos():Distance(target))
        local sw, sh = ScrW(), ScrH()
        local name = tracker.stageName
        if name == nil or name == "" then name = tracker.zoneName or tracker.title or "Точка работы" end
        drawScreenMarker(target, name, distance, Color(80, 200, 240), sw, sh)
    end)

    -- Меню терминала --------------------------------------------------------
    -- Кнопка — общая фабрика GRM.UI (§5.4): копии в четырёх модулях
    -- различались только шрифтом и создавали по два Color() на кадр.
    local function mkBtn(p, txt, col)
        return GRM.UI.Button(p, txt, "GRMJobs_Sub", col or C.acc)
    end

    -- NB: «goto» — ключевое слово Lua 5.2+/LuaJIT, поэтому ключ закавычен.
    local JTYPE_NAMES = { ["goto"] = "Доставка", stay = "Дежурство", roundtrip = "Туда-обратно", shift = "Смена", garbage = "Мусоровоз", taxi = "Такси" }

    -- общая форма публикации заказа/вакансии (терминал + /jobpost)
    function JB.OpenPostForm(zoneMode, myFac)
        if IsValid(JB._postForm) then JB._postForm:Remove() end
        local f = vgui.Create("DFrame")
        JB._postForm = f
        f:SetTitle("")
        f:SetSize(520, 372)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 42, C.head, true, true, false, false)
            draw.SimpleText("Публикация от «" .. tostring(myFac) .. "»", "GRMJobs_Title", 14, 21, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(zoneMode == "here" and "Зона смены: где вы стоите" or "Зона смены: точка терминала", "GRMJobs_Small", 410, 21, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMJobs_Title") x:SetTextColor(color_white)
        x:SetPos(476, 7) x:SetSize(32, 28)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end

        local eTitle = vgui.Create("DTextEntry", f)
        eTitle:SetPos(14, 52) eTitle:SetSize(300, 26) eTitle:SetPlaceholderText("Название (4–40): «Рабочие на завод»") eTitle:SetFont("GRMJobs_Normal")
        local eDesc = vgui.Create("DTextEntry", f)
        eDesc:SetPos(14, 84) eDesc:SetSize(492, 26) eDesc:SetPlaceholderText("Описание (до 120 симв.): «Производство боеприпасов и оружия, смена у станков»") eDesc:SetFont("GRMJobs_Normal")

        local cb = vgui.Create("DComboBox", f)
        cb:SetPos(14, 120) cb:SetSize(240, 26) cb:SetFont("GRMJobs_Normal")
        cb:AddChoice("Вакансия: смены за зарплату", "vacancy", true)
        cb:AddChoice("Разовый заказ: доставка", "order|goto")
        cb:AddChoice("Разовый заказ: дежурство 90 с", "order|stay")
        cb:AddChoice("Разовый заказ: туда-обратно", "order|roundtrip")

        local slPay = vgui.Create("DNumSlider", f)
        slPay:SetPos(14, 152) slPay:SetSize(480, 30)
        slPay:SetText("Зарплата за смену (или награда заказа)") slPay:SetMin(100) slPay:SetMax(5000) slPay:SetDecimals(0) slPay:SetValue(1000)

        local cbShift = vgui.Create("DComboBox", f)
        cbShift:SetPos(14, 192) cbShift:SetSize(240, 26) cbShift:SetFont("GRMJobs_Normal")
        cbShift:AddChoice("Смена 5 минут", 300)
        cbShift:AddChoice("Смена 10 минут", 600, true)
        cbShift:AddChoice("Смена 15 минут", 900)
        cbShift:AddChoice("Смена 20 минут", 1200)

        local slShifts = vgui.Create("DNumSlider", f)
        slShifts:SetPos(14, 226) slShifts:SetSize(480, 30)
        slShifts:SetText("Смен на вакансию (эскроу = зарплата × смены)") slShifts:SetMin(1) slShifts:SetMax(JB.MaxShifts) slShifts:SetDecimals(0) slShifts:SetValue(3)

        local hint = vgui.Create("DLabel", f)
        hint:SetPos(14, 262) hint:SetSize(492, 56) hint:SetFont("GRMJobs_Small") hint:SetTextColor(C.dim)
        hint:SetText("Вакансия: работник встаёт в зону смены и отрабатывает время — зарплата после каждой смены из эскроу. Разовый заказ: цель назначается из точек доставки города. Деньги резервируются с бюджета при публикации; отзыв/срок — возврат. Лимит: " .. tostring(JB.MaxPosts) .. " публикации(й) на фракцию, срок 24 ч.")
        hint:SetWrap(true) hint:SetAutoStretchVertical(true)

        local bPub = vgui.Create("DButton", f)
        bPub:SetPos(14, 324) bPub:SetSize(492, 34) bPub:SetText("Опубликовать (эскроу с бюджета фракции)")
        bPub:SetFont("GRMJobs_Sub") bPub:SetTextColor(color_white)
        bPub.Paint = function(self, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, self:IsHovered() and Color(80, 210, 130) or C.green) end
        bPub.DoClick = function()
            local _, data = cb:GetSelected()
            data = tostring(data or "vacancy")
            local kind, jtype = "vacancy", "goto"
            if string.sub(data, 1, 6) == "order|" then
                kind = "order"
                jtype = string.sub(data, 7)
            end
            local _, shiftSec = cbShift:GetSelected()
            net.Start(NET_POST)
                net.WriteString(kind)
                net.WriteString(eTitle:GetValue() or "")
                net.WriteString(eDesc:GetValue() or "")
                net.WriteString(jtype)
                net.WriteUInt(math.floor(tonumber(slPay:GetValue()) or 0), 20)
                net.WriteUInt(tonumber(shiftSec) or 600, 12)
                net.WriteUInt(math.floor(tonumber(slShifts:GetValue()) or 1), 8)
                net.WriteString(zoneMode or "term")
            net.SendToServer()
            timer.Simple(0.4, function() if IsValid(f) then f:Close() end end)
        end
    end

    net.Receive(NET_FORM, function()
        local fac = net.ReadString() or ""
        JB.OpenPostForm("here", fac ~= "" and fac or "фракция")
    end)

    net.Receive(NET_OPEN, function()
        local isSuper = net.ReadBool()
        local canP = net.ReadBool()
        local myFac = net.ReadString() or ""
        local err = net.ReadString() or ""
        local offers = net.ReadTable() or {}
        local active = net.ReadTable() or {}
        local posts = net.ReadTable() or {}
        local allow = net.ReadTable() or {}
        local st = net.ReadTable() or { done = 0, earned = 0 }
        local hasActive = istable(active) and active.title ~= nil

        if IsValid(JB._frame) then JB._frame:Remove() end
        local f = vgui.Create("DFrame")
        JB._frame = f
        f:SetTitle("")
        f:SetSize(940, 680)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f:SetDeleteOnClose(true)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(10, 0, 0, pw, 66, C.head, true, true, false, false)
            draw.SimpleText("БИРЖА ТРУДА", "GRMJobs_Title", 18, 13, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Городская подработка — выбирайте дело по душе", "GRMJobs_Small", 18, 42, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Выполнено: " .. tostring(st.done or 0) .. "   •   Заработано: " .. fmtMoney(st.earned or 0), "GRMJobs_Normal", pw - 18, 24, C.teal, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            if hasActive then
                draw.SimpleText("Активная работа: " .. tostring(active.title), "GRMJobs_Small", pw - 18, 46, C.yellow, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        local btnClose = vgui.Create("DButton", f)
        btnClose:SetText("✕") btnClose:SetFont("GRMJobs_Sub") btnClose:SetTextColor(color_white)
        btnClose:SetPos(898, 10) btnClose:SetSize(30, 28)
        btnClose.Paint = function(self, pw, ph) draw.RoundedBox(5, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end
        btnClose.DoClick = function() f:Close() end

        -- Контент + вкладки
        local content = vgui.Create("DPanel", f)
        content:SetPos(12, 108) content:SetSize(916, 560)
        content.Paint = function() end

        local currentTab = "work"
        local tabBtns = {}
        local renderTabs
        local function tabButton(id, label, icon)
            local b = vgui.Create("DButton", f)
            b:SetText("") b:SetFont("GRMJobs_Small") b:SetTextColor(color_white)
            tabBtns[id] = b
            b.Paint = function(self, pw, ph)
                local act = (currentTab == id)
                draw.RoundedBox(6, 0, 0, pw, ph, act and C.acc or C.panel2)
                if icon then surface.SetMaterial(Material(icon, "smooth")) surface.SetDrawColor(255, 255, 255, 255) surface.DrawTexturedRect(10, ph / 2 - 8, 16, 16) end
                draw.SimpleText(label, "GRMJobs_Small", icon and 32 or 12, ph / 2, act and color_white or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() surface.PlaySound("buttons/button15.wav") currentTab = id renderTabs() end
            return b
        end

        local function cardButton(parent, text, col, enabled, onClick)
            local b = vgui.Create("DButton", parent)
            b:SetText(text) b:SetFont("GRMJobs_Normal") b:SetTextColor(color_white)
            b:SetEnabled(enabled ~= false)
            b.Paint = function(self, pw, ph)
                local cc = col or C.acc
                if not self:IsEnabled() then cc = Color(60, 65, 75)
                elseif self:IsHovered() then cc = Color(math.min(255, cc.r + 22), math.min(255, cc.g + 22), math.min(255, cc.b + 22)) end
                draw.RoundedBox(6, 0, 0, pw, ph, cc)
                surface.SetDrawColor(255, 255, 255, 46) surface.DrawOutlinedRect(0, 0, pw, ph)
                draw.SimpleText(text, "GRMJobs_Normal", pw / 2, ph / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() surface.PlaySound("buttons/button15.wav") if onClick then onClick() end end
            return b
        end

        -- Вкладка «Работы»: карточки готового набора
        local function buildWorkTab()
            local scroll = vgui.Create("DScrollPanel", content)
            scroll:Dock(FILL)
            local canvas = vgui.Create("DPanel", scroll)
            canvas:SetWide(900)
            canvas.Paint = function() end

            if err ~= "" or #offers == 0 then
                local none = vgui.Create("DLabel", canvas)
                none:SetPos(14, 10) none:SetSize(870, 60) none:SetFont("GRMJobs_Normal") none:SetTextColor(C.red)
                none:SetText((err ~= "" and err) or "Сейчас вакансий нет — загляните позже.")
                none:SetWrap(true) none:SetAutoStretchVertical(true)
                canvas:SetTall(90)
                scroll:AddItem(canvas)
                return
            end

            local cols, cw, ch, gap = 2, 440, 150, 20
            for i, o in ipairs(offers) do
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                local cx = col * (cw + gap)
                local cy = row * (ch + 10)
                local colR, colG, colB = 90, 170, 250
                if istable(o.color) then colR, colG, colB = tonumber(o.color[1]) or 90, tonumber(o.color[2]) or 170, tonumber(o.color[3]) or 250 end
                local icon = tostring(o.icon or "icon16/package.png")

                local card = vgui.Create("DPanel", canvas)
                card:SetPos(cx, cy) card:SetSize(cw, ch)
                card.Paint = function(_, pw, ph)
                    draw.RoundedBox(8, 0, 0, pw, ph, C.panel)
                    surface.SetDrawColor(colR, colG, colB, 150) surface.DrawOutlinedRect(0, 0, pw, ph, 1)
                    draw.RoundedBox(8, 12, 12, 62, 62, Color(colR, colG, colB, 40))
                    surface.SetMaterial(Material(icon, "smooth")) surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(24, 24, 38, 38)
                    draw.SimpleText(tostring(o.title), "GRMJobs_Sub", 88, 10, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText(JTYPE_NAMES[o.jtype] or o.jtype, "GRMJobs_Small", 88, 30, Color(colR, colG, colB), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    if o.needVehicle then
                        local w2 = 92
                        draw.RoundedBox(4, pw - w2 - 12, 12, w2, 18, Color(colR, colG, colB, 36))
                        draw.SimpleText("нужен транспорт", "GRMJobs_Small", pw - 12 - w2 / 2, 21, Color(colR, colG, colB), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end

                local desc = vgui.Create("DLabel", card)
                desc:SetPos(88, 50) desc:SetSize(cw - 100, 34) desc:SetFont("GRMJobs_Small") desc:SetTextColor(C.dim)
                desc:SetText(tostring(o.desc or "")) desc:SetWrap(true)

                local info = vgui.Create("DLabel", card)
                info:SetPos(12, 96) info:SetSize(cw - 24, 18) info:SetFont("GRMJobs_Normal") info:SetTextColor(C.yellow)
                info:SetText(tostring(o.blockedReason or"")~=""and"ТРЕБУЕТСЯ НАСТРОЙКА АДМИНИСТРАТОРОМ"or(o.tplId=="taxi"and("Живые заказы игроков   •   смена "..fmtTime(o.timeSec or 0))or(fmtMoney(o.reward or 0).."   •   до "..fmtTime(o.timeSec or 0))))

                local zone = vgui.Create("DLabel", card)
                zone:SetPos(12, 120) zone:SetSize(cw - 160, 18) zone:SetFont("GRMJobs_Small") zone:SetTextColor(C.dim)
                zone:SetText(tostring(o.zoneName or ""))

                local blocked=tostring(o.blockedReason or"")~=""
                local take = cardButton(card, hasActive and "Занято" or(blocked and"НЕТ МАРШРУТА"or"ВЗЯТЬ"), (hasActive or blocked)and Color(70,78,92)or C.green, not hasActive and not blocked, function()
                    net.Start(NET_ACCEPT) net.WriteUInt(o.idx, 8) net.SendToServer()
                    timer.Simple(0.5, function() if IsValid(f) then f:Close() end end)
                end)
                take:SetPos(cw - 138, 116) take:SetSize(126, 28)
            end
            local rows = math.ceil(#offers / cols)
            canvas:SetTall(rows * (ch + 10) + 10)
            scroll:AddItem(canvas)
        end

        -- Вкладка «Моя работа»
        local function buildMineTab()
            local panel = vgui.Create("DPanel", content)
            panel:Dock(FILL) panel:DockMargin(0, 0, 0, 0)
            panel.Paint = function() end
            if not hasActive then
                local none = vgui.Create("DLabel", panel)
                none:Dock(TOP) none:SetTall(60) none:SetFont("GRMJobs_Normal") none:SetTextColor(C.dim)
                none:SetText("Активной работы нет.\nВыберите дело во вкладке «Работы» — маркер цели появится на экране.")
                none:SetWrap(true) none:SetAutoStretchVertical(true)
                return
            end
            local card = vgui.Create("DPanel", panel)
            card:Dock(TOP) card:SetTall(150)
            card.Paint = function(_, pw, ph)
                draw.RoundedBox(8, 0, 0, pw, ph, C.panel)
                draw.RoundedBoxEx(8, 0, 0, pw, 40, Color(30, 40, 56), true, true, false, false)
                draw.SimpleText("МОЯ РАБОТА", "GRMJobs_Sub", 14, 20, C.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local title = vgui.Create("DLabel", card)
            title:SetPos(14, 48) title:SetSize(880, 22) title:SetFont("GRMJobs_Sub") title:SetTextColor(C.text)
            title:SetText(active.jtype=="taxi"and(tostring(active.title).."   —   оплата за живые заказы")or(tostring(active.title).."   —   "..fmtMoney(active.reward or 0)))
            local info = vgui.Create("DLabel", card)
            info:SetPos(14, 74) info:SetSize(880, 20) info:SetFont("GRMJobs_Normal") info:SetTextColor(C.yellow)
            local note = JTYPE_NAMES[active.jtype] or active.jtype
            if active.needVehicle then note = note .. " • нужен транспорт" end
            if (active.stageName or "") ~= "" then note = note .. " • " .. tostring(active.stageName) end
            if (active.stayLeft or 0) > 0 then note = note .. " • в зоне: " .. tostring(active.stayLeft) .. " с" end
            note = note .. " • осталось: " .. fmtTime(active.remain or 0)
            info:SetText(note)
            local zone = vgui.Create("DLabel", card)
            zone:SetPos(14, 98) zone:SetSize(700, 18) zone:SetFont("GRMJobs_Small") zone:SetTextColor(C.dim)
            zone:SetText("Зона: " .. tostring(active.zoneName or "—") .. " • радиус " .. tostring(active.zoneRadius or 180) .. (active.fromPost and (" • заказ " .. tostring(active.postFac)) or ""))
            local cancel = cardButton(card, "Отказаться", C.red, true, function()
                net.Start(NET_CANCEL) net.SendToServer()
                timer.Simple(0.5, function() if IsValid(f) then f:Close() end end)
            end)
            cancel:SetPos(760, 106) cancel:SetSize(140, 30)
        end

        -- Вкладка «Заказы фракций»
        local function buildPostsTab()
            local scroll = vgui.Create("DScrollPanel", content)
            scroll:Dock(FILL)
            local canvas = vgui.Create("DPanel", scroll)
            canvas:SetWide(900)
            canvas.Paint = function() end
            if #posts == 0 then
                local none = vgui.Create("DLabel", canvas)
                none:SetPos(14, 10) none:SetSize(870, 40) none:SetFont("GRMJobs_Normal") none:SetTextColor(C.dim)
                none:SetText("Пока ни одна фракция не опубликовала заказ.")
                canvas:SetTall(60) scroll:AddItem(canvas)
                return
            end
            for i, p in ipairs(posts) do
                local isVac = p.kind == "vacancy"
                local cy = (i - 1) * 96
                local row = vgui.Create("DPanel", canvas)
                row:SetPos(0, cy) row:SetSize(900, 88)
                row.Paint = function(_, pw, ph)
                    draw.RoundedBox(8, 0, 0, pw, ph, C.panel)
                    if isVac then surface.SetDrawColor(80, 200, 170, 120) else surface.SetDrawColor(80, 170, 250, 120) end
                    surface.DrawOutlinedRect(0, 0, pw, ph, 1)
                end
                local t = vgui.Create("DLabel", row)
                t:SetPos(12, 10) t:SetSize(700, 20) t:SetFont("GRMJobs_Sub") t:SetTextColor(isVac and C.green or C.text)
                t:SetText((isVac and "ВАКАНСИЯ «" or "Заказ «") .. tostring(p.title) .. "» — " .. tostring(p.faction))
                local d = vgui.Create("DLabel", row)
                d:SetPos(12, 32) d:SetSize(700, 18) d:SetFont("GRMJobs_Small") d:SetTextColor(C.dim)
                d:SetText(tostring(p.desc or "") .. " • автор: " .. tostring(p.author))
                local s2 = vgui.Create("DLabel", row)
                s2:SetPos(12, 54) s2:SetSize(700, 20) s2:SetFont("GRMJobs_Normal") s2:SetTextColor(p.taken and C.red or (isVac and C.green or C.teal))
                if isVac then
                    s2:SetText((p.taken and "СМЕНА ИДЁТ • " or "") .. "зарплата " .. fmtMoney(p.salary or 0) .. " × смен: " .. tostring(p.shiftsLeft or 0) .. ((tonumber(p.payedTotal) or 0) > 0 and (" • выплачено " .. fmtMoney(p.payedTotal) .. " (" .. tostring(p.lastWorker) .. ")") or ""))
                else
                    s2:SetText(p.taken and "ВЗЯТ исполнителем" or (fmtMoney(p.reward or 0) .. " • свободен"))
                end
                if canP and p.mine then
                    local un = cardButton(row, "Отозвать", C.red, true, function()
                        net.Start(NET_UNPOST) net.WriteString(p.faction) net.WriteUInt(tonumber(p.id) or 0, 32) net.SendToServer()
                        timer.Simple(0.4, function() if IsValid(f) then f:Close() end end)
                    end)
                    un:SetPos(720, 26) un:SetSize(160, 32)
                else
                    local canTake = (not hasActive) and (not p.taken) and (not p.mine)
                    local tk = cardButton(row, p.taken and "Занят" or (p.mine and "Ваш заказ" or "Взять"), canTake and C.teal or Color(70, 78, 92), canTake, function()
                        net.Start(NET_TAKEPOST) net.WriteString(p.faction) net.WriteUInt(tonumber(p.id) or 0, 32) net.SendToServer()
                        timer.Simple(0.5, function() if IsValid(f) then f:Close() end end)
                    end)
                    tk:SetPos(720, 26) tk:SetSize(160, 32)
                end
            end
            canvas:SetTall(#posts * 96 + 10)
            scroll:AddItem(canvas)
        end

        -- Вкладка «Публикация» (лидер с доступом БИРЖА)
        local function buildPublishTab()
            local panel = vgui.Create("DPanel", content)
            panel:Dock(FILL) panel.Paint = function() end
            local head = vgui.Create("DLabel", panel)
            head:Dock(TOP) head:SetTall(24) head:SetFont("GRMJobs_Sub") head:SetTextColor(C.green)
            head:SetText("Публикация работ от «" .. myFac .. "» (эскроу с бюджета фракции)")
            local btn = cardButton(panel, "Опубликовать заказ / вакансию", C.green, true, function() JB.OpenPostForm("term", myFac) end)
            btn:Dock(TOP) btn:DockMargin(0, 8, 0, 8) btn:SetTall(36)
            local hint = vgui.Create("DLabel", panel)
            hint:Dock(TOP) hint:SetTall(60) hint:SetFont("GRMJobs_Small") hint:SetTextColor(C.dim)
            hint:SetText("Вакансия у станка/завода: встаньте на место и используйте /jobpost — зона смены будет там, где вы стоите. Деньги резервируются с бюджета при публикации; отзыв/срок — возврат.")
            hint:SetWrap(true) hint:SetAutoStretchVertical(true)
        end

        -- Вкладка «Доступы» (суперадмин)
        local function buildAccessTab()
            local scroll = vgui.Create("DScrollPanel", content)
            scroll:Dock(FILL)
            local canvas = vgui.Create("DPanel", scroll)
            canvas:SetWide(900)
            canvas.Paint = function() end
            for i, a in ipairs(allow) do
                local chk = vgui.Create("DCheckBoxLabel", canvas)
                chk:SetPos(14, 10 + (i - 1) * 30) chk:SetSize(600, 26)
                chk:SetText(a.name) chk:SetFont("GRMJobs_Normal")
                chk:SetTextColor(a.allowed and C.green or C.dim)
                chk:SetValue(a.allowed and 1 or 0)
                chk.OnChange = function(_, v)
                    net.Start(NET_ALLOW) net.WriteString(a.name) net.WriteBool(v) net.SendToServer()
                    chk:SetTextColor(v and C.green or C.dim)
                end
            end
            local hint = vgui.Create("DLabel", canvas)
            hint:SetPos(14, 10 + #allow * 30 + 6) hint:SetSize(860, 40) hint:SetFont("GRMJobs_Small") hint:SetTextColor(C.dim)
            hint:SetText("Кто публикует заказы от фракций. Те же галочки: /factions → «Доступы» (колонка БИРЖА) и команды /job_allow Фракция, /job_deny Фракция.")
            hint:SetWrap(true) hint:SetAutoStretchVertical(true)
            canvas:SetTall(40 + #allow * 30 + 60)
            scroll:AddItem(canvas)
        end

        renderTabs = function()
            content:Clear()
            -- раскладка кнопок вкладок
            local defs = {
                { id = "work",    label = "Работы",          icon = "icon16/briefcase.png" },
                { id = "mine",    label = "Моя работа",      icon = "icon16/user_go.png" },
                { id = "posts",   label = "Заказы фракций",  icon = "icon16/group.png" },
            }
            if canP then defs[#defs + 1] = { id = "publish", label = "Публикация", icon = "icon16/report_edit.png" } end
            if isSuper then defs[#defs + 1] = { id = "access", label = "Доступы", icon = "icon16/key.png" } end
            local x = 12
            for _, d in ipairs(defs) do
                local b = tabBtns[d.id]
                if not IsValid(b) then b = tabButton(d.id, d.label, d.icon) end
                b:SetPos(x, 72) b:SetSize(150, 32)
                b._tabId = d.id
                x = x + 158
            end
            if currentTab == "work" then buildWorkTab()
            elseif currentTab == "mine" then buildMineTab()
            elseif currentTab == "posts" then buildPostsTab()
            elseif currentTab == "publish" then buildPublishTab()
            elseif currentTab == "access" then buildAccessTab()
            end
        end

        renderTabs()
    end)

    -- вкладка «Работа» в F4 (хук из sh_grm_f4menu v1.4.0) -------------------
    hook.Add("GRM_F4_BuildTabs", "GRM_Jobs_Tab", function(sheet)
        if not IsValid(sheet) then return end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        panel:DockPadding(8, 8, 8, 8)

        local head = vgui.Create("DLabel", panel)
        head:Dock(TOP) head:SetTall(24) head:SetFont("GRMJobs_Sub") head:SetTextColor(C.yellow)
        head:SetText("Биржа труда: текущая задача и статистика")

        local info = vgui.Create("DPanel", panel)
        info:Dock(FILL) info:DockMargin(0, 6, 0, 6)
        info.Paint = function(_, pw, ph)
            draw.RoundedBox(6, 0, 0, pw, ph, C.panel)
        end

        local function renderState(my, st)
            info.Paint = function(_, pw, ph)
                draw.RoundedBox(6, 0, 0, pw, ph, C.panel)
                local y = 14
                if istable(my) and my.title then
                    local left = math.max(0, (my.remain or 0))
                    draw.SimpleText("Текущая задача: " .. tostring(my.title), "GRMJobs_Sub", 12, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) y = y + 24
                    draw.SimpleText(tostring(my.desc or ""), "GRMJobs_Small", 12, y, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) y = y + 20
                    local note = "Осталось: " .. fmtTime(left) .. " • награда: " .. fmtMoney(my.reward or 0)
                    if my.jtype == "stay" then note = note .. " • в зоне: " .. tostring(my.stayLeft or 0) .. " с" end
                    if my.jtype == "shift" then note = note .. " • СМЕНА: " .. tostring(my.stayLeft or 0) .. " с" end
                    if my.jtype == "roundtrip" then note = note .. ((my.stage == 2) and " • этап: возврат" or " • этап: к точке") end
                    if my.fromPost then note = note .. " • заказ " .. tostring(my.postFac) end
                    draw.SimpleText(note, "GRMJobs_Normal", 12, y, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) y = y + 24
                    draw.SimpleText("Отказаться: /jobcancel • маркер цели показан над точкой в мире", "GRMJobs_Small", 12, y, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                else
                    draw.SimpleText("Активной задачи нет.", "GRMJobs_Sub", 12, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) y = y + 22
                    draw.SimpleText("Вакансии: подойдите к терминалу «Биржа труда» и нажмите E. Курьер, мусоровоз, таксист. Фракции-работодатели публикуют свои заказы с оплатой из бюджета.", "GRMJobs_Small", 12, y, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
                draw.SimpleText("Ваш счётчик: выполнено " .. tostring((st and st.done) or 0) .. " задач • заработано " .. fmtMoney((st and st.earned) or 0), "GRMJobs_Normal", 12, ph - 26, C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
        renderState(nil, { done = 0, earned = 0 })

        net.Receive(NET_MYSTATE, function()
            if not IsValid(info) then return end
            local has = net.ReadBool()
            local my = net.ReadTable() or {}
            local st = net.ReadTable() or {}
            renderState(has and my or nil, st)
        end)

        local bRef = vgui.Create("DButton", panel)
        bRef:Dock(BOTTOM) bRef:SetTall(28) bRef:SetText("Обновить")
        bRef:SetFont("GRMJobs_Sub") bRef:SetTextColor(color_white)
        bRef.Paint = function(self, w, h) draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(90, 170, 250) or C.acc) end
        bRef.DoClick = function() net.Start(NET_GETMY) net.SendToServer() end

        timer.Simple(0.2, function()
            if IsValid(panel) then net.Start(NET_GETMY) net.SendToServer() end
        end)
        timer.Create("GRM_Jobs_F4Poll", 2, 0, function()
            if IsValid(panel) then net.Start(NET_GETMY) net.SendToServer()
            else timer.Remove("GRM_Jobs_F4Poll") end
        end)

        sheet:AddSheet("Работа", panel, "icon16/bricks.png")
    end)

    print("[GRM Jobs] Клиент биржи труда v" .. JB.Version .. " загружен")
end
