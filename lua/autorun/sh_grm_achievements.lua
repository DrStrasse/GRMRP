--[[--------------------------------------------------------------------
    GRM Achievements v1.0.0 (Код 78) — Ачивки и вознаграждения

    Единая внутриигровая витрина прогресса: достижения с денежными
    наградами + ежедневный бонус за вход (растущий стрик).

      - 21 достижение: экономика (заработано/баланс — тикет Кодов 42/43),
        биржа труда (Код 77), радио и оповещение (Код 75), доска и
        фракции (Код 76), прожитое время, пешие дистанции, стрик входа.
      - Прогресс считается сервером из хуков сборки (GRM_MoneyChanged,
        GRM_Jobs_Completed, GRM_BC_BroadcastStart, GRM_BC_Alert,
        GRM_Board_Joined) и тик-поллинга (время игры 30 с, пешком 2 с
        с анти-телепорт-капой 4000 юн/тик, состоит ли во фракции).
      - Разблокировка: автоначисление награды (GRM.GiveMoney,
        причина «Ачивка: …»), экранный тост «★», звук, запись в чат.
      - Ежедневный бонус: вход нового дня → стрик (не прерывается, если
        заходил вчера), +500 GRM база, +250 за каждый день стрика, потолок
        2000. Дата по серверным настенным часам (os.date).
      - Хранение: data/grm_achievements.json МАССИВОМ записей
        {sid, c{counters}, u{unlocked}, earned, streak, lastDaily} —
        ключей-SteamID64 в JSON нет в принципе (урок находки 65),
        read-back с печатью, дебаунс 10 с + автосейв 60 с + Disconnect/
        ShutDown.
      - /ach — сводка в чат (счёт, сумма, ближайшие), /ach_reset ник —
        суперадмин. Вкладка «Ачивки» в F4 (хук GRM_F4_BuildTabs).
      - Скрытые (hidden) достижения до открытия показываются как «???».

    Чат-контракт: PlayerSayTransform (+fallback PlayerSay) — находка 89.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Ach = GRM.Ach or {}
local AC = GRM.Ach

AC.Version   = "1.1.0"   -- +API AC.SaveNow/AdminReset для единой админ-панели (Код 79)
AC.DataFile  = "grm_achievements.json"

-- ежедневный бонус
AC.DailyBase = 500
AC.DailyStep = 250
AC.DailyCap  = 2000

local NET_GET      = "GRM_Ach_Get"
local NET_DATA     = "GRM_Ach_Data"
local NET_UNLOCKED = "GRM_Ach_Unlocked"

-- ============================================================
-- РЕЕСТР ДОСТИЖЕНИЙ (расширяемо: AC.Register из других модулей)
-- ============================================================
AC.Defs = AC.Defs or {}
AC.Order = AC.Order or {}

function AC.Register(def)
    if not istable(def) or not isstring(def.id) or def.id == "" then return end
    if AC.Defs[def.id] then AC.Defs[def.id] = def return end
    AC.Defs[def.id] = def
    AC.Order[#AC.Order + 1] = def.id
end
function AC.Unregister(id)
    id=tostring(id or"");if id==""or not AC.Defs[id]then return false end;AC.Defs[id]=nil;for i=#AC.Order,1,-1 do if AC.Order[i]==id then table.remove(AC.Order,i)end end;return true
end

-- экономика
AC.Register({ id = "first_pay", name = "Первая выплата",        desc = "Заработать первые 1 000 GRM честным трудом",            metric = "moneyEarned", goal = 1000,    reward = 500 })
AC.Register({ id = "ear50k",    name = "Рабочая копейка",       desc = "Заработать суммарно 50 000 GRM",                        metric = "moneyEarned", goal = 50000,   reward = 1500 })
AC.Register({ id = "ear500k",   name = "Промышленный магнат",   desc = "Заработать суммарно 500 000 GRM",                       metric = "moneyEarned", goal = 500000,  reward = 5000 })
AC.Register({ id = "rich250k",  name = "Состоятельный",         desc = "Держать на руках 250 000 GRM разом",                    metric = "balancePeak", goal = 250000,  reward = 2500 })
AC.Register({ id = "million",   name = "Миллионер",             desc = "Держать на руках 1 000 000 GRM разом",                  metric = "balancePeak", goal = 1000000, reward = 10000 })
-- биржа труда
AC.Register({ id = "job1",      name = "Первый выход",          desc = "Выполнить первую задачу биржи труда",                   metric = "jobsDone",    goal = 1,  reward = 500 })
AC.Register({ id = "job10",     name = "Работяга",              desc = "Выполнить 10 задач биржи труда",                        metric = "jobsDone",    goal = 10, reward = 2000 })
AC.Register({ id = "job50",     name = "Ветеран биржи",         desc = "Выполнить 50 задач биржи труда",                        metric = "jobsDone",    goal = 50, reward = 8000, hidden = true })
AC.Register({ id = "jobfac",    name = "Доверенный подрядчик",  desc = "Выполнить 5 заказов фракций",                           metric = "jobsFaction", goal = 5,  reward = 3000 })
-- радио и оповещение
AC.Register({ id = "bc1",       name = "Голос эфира",           desc = "Провести первый радиоэфир у микрофона",                 metric = "bcLive",      goal = 1,  reward = 1000 })
AC.Register({ id = "bc10",      name = "Медийная персона",      desc = "Провести 10 радиоэфиров",                               metric = "bcLive",      goal = 10, reward = 4000 })
AC.Register({ id = "alerter",   name = "Голос города",          desc = "Подать массовое оповещение (/alert, /alertall)",        metric = "bcAlert",     goal = 1,  reward = 1500 })
-- фракции и доска
AC.Register({ id = "recruit",   name = "Рекрут",                desc = "Вступить во фракцию через доску объявлений",            metric = "boardJoin",   goal = 1,  reward = 1000 })
AC.Register({ id = "party",     name = "Партийный билет",       desc = "Числиться во фракции",                                  metric = "factionNow",  goal = 1,  reward = 500 })
-- житель города
AC.Register({ id = "citizen",   name = "Житель города",         desc = "Провести в городе 1 час суммарно",                      metric = "playSec",     goal = 3600,   reward = 1000 })
AC.Register({ id = "oldtimer",  name = "Старожил",              desc = "Провести в городе 5 часов суммарно",                    metric = "playSec",     goal = 18000,  reward = 3000 })
AC.Register({ id = "legend",    name = "Легенда района",        desc = "Провести в городе 20 часов суммарно",                   metric = "playSec",     goal = 72000,  reward = 15000, hidden = true })
AC.Register({ id = "walker",    name = "Пешеход",               desc = "Пройти пешком 250 000 юн. (~5 км)",                     metric = "walkUnits",   goal = 250000,  reward = 1000 })
AC.Register({ id = "marathon",  name = "Марафонец",             desc = "Пройти пешком 1 300 000 юн. (~25 км)",                  metric = "walkUnits",   goal = 1300000, reward = 3500, hidden = true })
-- постоянство
AC.Register({ id = "daily3",    name = "Постоянство",           desc = "Стрик ежедневных входов: 3 дня подряд",                 metric = "dailyStreak", goal = 3, reward = 1000 })
AC.Register({ id = "daily7",    name = "Привычка приходить",    desc = "Стрик ежедневных входов: 7 дней подряд",                metric = "dailyStreak", goal = 7, reward = 3000 })

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_GET)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_UNLOCKED)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    -- Хранилище МАССИВОМ (никаких ключей-SteamID64 в JSON)
    AC.Records = AC.Records or {}
    local dirty = false
    local function loadAll()
        AC.Records = {}
        local t = jsonT(file.Read(AC.DataFile, "DATA") or "")
        if istable(t) then
            for _, r in ipairs(t) do
                if istable(r) and isstring(r.sid) then
                    AC.Records[r.sid] = {
                        sid = r.sid,
                        c = istable(r.c) and r.c or {},
                        u = istable(r.u) and r.u or {},
                        earned = tonumber(r.earned) or 0,
                        streak = tonumber(r.streak) or 0,
                        lastDaily = tostring(r.lastDaily or ""),
                    }
                end
            end
        end
        print("[GRM Ach] LOAD: записей " .. tostring(table.Count(AC.Records)))
    end
    local function saveAll(why)
        local arr = {}
        for sid, r in pairs(AC.Records) do arr[#arr + 1] = r end
        table.sort(arr, function(a, b) return tostring(a.sid) < tostring(b.sid) end)
        local ok, txt = pcall(util.TableToJSON, arr, true)
        if ok and txt then
            file.Write(AC.DataFile, txt)
            local back = file.Read(AC.DataFile, "DATA")
            print("[GRM Ach] SAVE ok (" .. tostring(why or "-") .. "): " .. tostring(#arr) .. " зап., " .. tostring(string.len(back or "") or 0) .. " байт")
        end
        dirty = false
    end
    loadAll()
    local function markDirty()
        dirty = true
        timer.Remove("GRM_Ach_Debounce")
        timer.Create("GRM_Ach_Debounce", 10, 1, function() if dirty then saveAll("дебаунс 10с") end end)
    end

    local function achievementKey(value)
        if IsValid(value) and value:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(value) end
            return value:SteamID64() or value:SteamID()
        end
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        return raw
    end

    local function recOf(ply)
        local sid = achievementKey(ply)
        if not AC.Records[sid] then
            AC.Records[sid] = { sid = sid, c = {}, u = {}, earned = 0, streak = 0, lastDaily = "" }
            markDirty()
        end
        return AC.Records[sid]
    end
    AC.RecOf = recOf

    -- разблокировка -------------------------------------------------------
    function AC.Unlock(ply, def, rec)
        rec = rec or recOf(ply)
        if rec.u[def.id] then return end
        rec.u[def.id] = true
        rec.earned = (tonumber(rec.earned) or 0) + (tonumber(def.reward) or 0)
        markDirty()
        if (tonumber(def.reward) or 0) > 0 and GRM.GiveMoney then
            GRM.GiveMoney(ply, def.reward, "Ачивка: " .. tostring(def.name))
        end
        if GRM.Notify then GRM.Notify(ply, "★ Достижение: " .. tostring(def.name) .. " (+" .. (GRM.Format and GRM.Format(def.reward) or (tostring(def.reward) .. " GRM")) .. ")", 255, 220, 110) end
        ply:PrintMessage(HUD_PRINTTALK, "[Ачивка] Разблокировано: «" .. tostring(def.name) .. "» — " .. tostring(def.desc or "") .. ". Награда: " .. (GRM.Format and GRM.Format(def.reward) or tostring(def.reward)))
        net.Start(NET_UNLOCKED)
            net.WriteString(tostring(def.name or ""))
            net.WriteString(tostring(def.desc or ""))
            net.WriteUInt(math.max(0, tonumber(def.reward) or 0), 24)
        net.Send(ply)
        hook.Run("GRM_Ach_Unlock", ply, def)
    end

    -- метрики: add (счётчик) / max (пиковое значение) ---------------------
    function AC.AddMetric(ply, metric, amount, mode)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local rec = recOf(ply)
        local cur = tonumber(rec.c[metric]) or 0
        if mode == "max" then
            if amount and amount > cur then rec.c[metric] = math.floor(amount) else return end
        else
            rec.c[metric] = math.floor(cur + (tonumber(amount) or 0))
        end
        markDirty()
        for _, id in ipairs(AC.Order) do
            local def = AC.Defs[id]
            if def and def.metric == metric and not rec.u[id] then
                if (tonumber(rec.c[metric]) or 0) >= (tonumber(def.goal) or 1) then
                    AC.Unlock(ply, def, rec)
                end
            end
        end
    end

    -- источники метрик ------------------------------------------------------
    hook.Add("GRM_MoneyChanged", "GRM_Ach_Money", function(ply, newBalance, delta, reason)
        -- экономика иногда шлёт sid-строкой: резолвим в онлайн-игрока
        local p = ply
        if isstring(ply) then
            p = player.GetBySteamID64(ply) or player.GetBySteamID(ply)
        end
        if not (IsValid(p) and p.IsPlayer and p:IsPlayer()) then return end
        if (tonumber(delta) or 0) > 0 then AC.AddMetric(p, "moneyEarned", delta) end
        if (tonumber(newBalance) or 0) > 0 then AC.AddMetric(p, "balancePeak", newBalance, "max") end
    end)

    hook.Add("GRM_Jobs_Completed", "GRM_Ach_Jobs", function(ply, job)
        if not IsValid(ply) then return end
        AC.AddMetric(ply, "jobsDone", 1)
        if istable(job) and job.fromPost then AC.AddMetric(ply, "jobsFaction", 1) end
    end)

    hook.Add("GRM_BC_BroadcastStart", "GRM_Ach_BC", function(ply)
        if IsValid(ply) then AC.AddMetric(ply, "bcLive", 1) end
    end)
    hook.Add("GRM_BC_Alert", "GRM_Ach_Alert", function(ply)
        if IsValid(ply) then AC.AddMetric(ply, "bcAlert", 1) end
    end)
    hook.Add("GRM_Board_Joined", "GRM_Ach_Board", function(ply)
        if not IsValid(ply) then return end
        AC.AddMetric(ply, "boardJoin", 1)
        AC.AddMetric(ply, "factionNow", 1, "max")
    end)

    -- поллинг: время игры + состоит ли во фракции (30 с) --------------------
    timer.Create("GRM_Ach_Poll30", 30, 0, function()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                AC.AddMetric(p, "playSec", 30)
                local fac = nil
                if _G.FactionsAPI and _G.FactionsAPI.GetFactionOf then
                    fac = _G.FactionsAPI.GetFactionOf(p)
                elseif istable(Factions) then
                    local sid, s64 = p:SteamID(), p:SteamID64()
                    for name, f in pairs(Factions) do
                        if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then fac = name end
                    end
                end
                if fac ~= nil then AC.AddMetric(p, "factionNow", 1, "max") end
            end
        end
    end)

    -- поллинг: пешая дистанция (2 с, анти-телепорт капа) ---------------------
    local lastPos = {}
    timer.Create("GRM_Ach_Walk", 2, 0, function()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                    local k = achievementKey(p)
                if p:Alive() and (not p.InVehicle or not p:InVehicle()) and p:IsOnGround() then
                    local pos = p:GetPos()
                    local lp = lastPos[k]
                    if lp then
                        local dx, dy = pos.x - lp.x, pos.y - lp.y
                        local d = math.sqrt(dx * dx + dy * dy)
                        if d > 1 and d < 4000 then AC.AddMetric(p, "walkUnits", d) end
                    end
                    lastPos[k] = pos
                else
                    lastPos[k] = p:GetPos()
                end
            end
        end
    end)

    -- ежедневный бонус за вход ----------------------------------------------
    hook.Add("PlayerInitialSpawn", "GRM_Ach_Daily", function(ply)
        timer.Simple(6, function()
            if not IsValid(ply) then return end
            local rec = recOf(ply)
            local today = os.date("%Y-%m-%d")
            if rec.lastDaily == today then return end
            local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
            if rec.lastDaily == yesterday then
                rec.streak = (tonumber(rec.streak) or 0) + 1
            else
                rec.streak = 1
            end
            rec.lastDaily = today
            markDirty()
            local bonus = math.min(AC.DailyCap, AC.DailyBase + AC.DailyStep * (rec.streak - 1))
            if GRM.GiveMoney then GRM.GiveMoney(ply, bonus, "Ежедневный бонус (стрик " .. tostring(rec.streak) .. ")") end
            if GRM.Notify then GRM.Notify(ply, "Ежедневный бонус: +" .. (GRM.Format and GRM.Format(bonus) or tostring(bonus)) .. " • стрик " .. tostring(rec.streak) .. " дн.", 255, 220, 110) end
            ply:PrintMessage(HUD_PRINTTALK, "[Бонус] Ежедневный бонус начислен. Заходите завтра — стрик вырастет (макс. " .. (GRM.Format and GRM.Format(AC.DailyCap) or tostring(AC.DailyCap)) .. ").")
            AC.AddMetric(ply, "dailyStreak", rec.streak, "max")
        end)
    end)

    -- персистентность --------------------------------------------------------
    timer.Create("GRM_Ach_AutoSave", 60, 0, function() if dirty then saveAll("автосейв 60с") end end)
    hook.Add("PlayerDisconnected", "GRM_Ach_Disc", function() if dirty then saveAll("дисконнект") end end)
    hook.Add("ShutDown", "GRM_Ach_Shut", function() saveAll("shutdown") end)

    -- снапшот для клиента -----------------------------------------------------
    local function pushData(ply)
        if not IsValid(ply) then return end
        local rec = recOf(ply)
        local rows = {}
        local done = 0
        for _, id in ipairs(AC.Order) do
            local def = AC.Defs[id]
            if def then
                local un = rec.u[id] == true
                if un then done = done + 1 end
                local hiddenMask = def.hidden and not un
                rows[#rows + 1] = {
                    id = id,
                    name = hiddenMask and "???" or tostring(def.name),
                    desc = hiddenMask and "Скрытое достижение — откроется само, когда условие выполнено" or tostring(def.desc),
                    reward = tonumber(def.reward) or 0,
                    goal = tonumber(def.goal) or 1,
                    cur = math.min(tonumber(rec.c[def.metric]) or 0, tonumber(def.goal) or 1),
                    unlocked = un,
                    hidden = def.hidden and true or false,
                }
            end
        end
        net.Start(NET_DATA)
            net.WriteUInt(done, 8)
            net.WriteUInt(#AC.Order, 8)
            net.WriteUInt(math.max(0, tonumber(rec.earned) or 0), 24)
            net.WriteUInt(math.max(0, tonumber(rec.streak) or 0), 8)
            net.WriteTable(rows)
        net.Send(ply)
    end

    net.Receive(NET_GET, function(_, ply) pushData(ply) end)

    -- API для внешних админ-инструментов (единая панель Код 79)
    function AC.SaveNow(why) saveAll(why or "admin") end
    function AC.AdminReset(plyOrSid)
        local sid = achievementKey(plyOrSid)
        if not sid then return false end
        AC.Records[sid] = { sid = sid, c = {}, u = {}, earned = 0, streak = 0, lastDaily = "" }
        saveAll("admin reset " .. tostring(sid))
        return true
    end
    function AC.ResetUnlock(plyOrSid, achievementID, deferSave)
        local sid = achievementKey(plyOrSid)
        local id = tostring(achievementID or "")
        local rec = sid and AC.Records[sid] or nil
        if not rec or id == "" or not rec.u[id] then return false end
        rec.u[id] = nil
        local def = AC.Defs[id]
        rec.earned = math.max(0, (tonumber(rec.earned) or 0) - (tonumber(def and def.reward) or 0))
        if not deferSave then saveAll("reset unlock " .. id .. " / " .. tostring(sid)) else dirty=true end
        if IsValid(plyOrSid) and plyOrSid:IsPlayer() then pushData(plyOrSid) end
        return true
    end

    -- чат -------------------------------------------------------------------
    local function nearestLines(ply, count)
        local rec = recOf(ply)
        local todo = {}
        for _, id in ipairs(AC.Order) do
            local def = AC.Defs[id]
            if def and not rec.u[id] and not def.hidden then
                local cur = tonumber(rec.c[def.metric]) or 0
                todo[#todo + 1] = { def = def, frac = cur / math.max(1, tonumber(def.goal) or 1), cur = cur }
            end
        end
        table.sort(todo, function(a, b) return a.frac > b.frac end)
        local out = {}
        for i = 1, math.min(count, #todo) do
            local t = todo[i]
            out[#out + 1] = "«" .. t.def.name .. "» " .. tostring(math.floor(t.cur)) .. "/" .. tostring(t.def.goal)
        end
        return out
    end

    function AC.HandleChat(ply, text)
        if not IsValid(ply) then return false end
        local t = string.Trim(tostring(text or ""))
        local low = string.lower(t)
        if low == "/ach" or low == "/achievements" then
            local rec = recOf(ply)
            local done = 0
            for id in pairs(rec.u) do if rec.u[id] then done = done + 1 end end
            ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Разблокировано: " .. tostring(done) .. "/" .. tostring(#AC.Order) ..
                " • получено наград: " .. (GRM.Format and GRM.Format(rec.earned) or tostring(rec.earned)) ..
                " • стрик входа: " .. tostring(rec.streak) .. " дн.")
            local near = nearestLines(ply, 3)
            for _, line in ipairs(near) do
                ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Близко: " .. line)
            end
            ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Полный список и прогресс — F4 → вкладка «Ачивки».")
            return true
        end
        if string.sub(low, 1, 11) == "/ach_reset " then
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Только суперадмин.") return true end
            local who = string.lower(string.Trim(string.sub(t, 12)))
            local target = nil
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and string.find(string.lower(p:Nick()), who, 1, true) then target = p break end
            end
            if not IsValid(target) then ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Игрок «" .. who .. "» не найден в онлайне.") return true end
            local sid = achievementKey(target)
            AC.Records[sid] = { sid = sid, c = {}, u = {}, earned = 0, streak = 0, lastDaily = "" }
            saveAll("ach_reset " .. target:Nick())
            ply:PrintMessage(HUD_PRINTTALK, "[Ачивки] Прогресс обнулён: " .. target:Nick())
            if GRM.Notify then GRM.Notify(target, "Ваш прогресс достижений обнулён администрацией.", 255, 130, 110) end
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_Ach_TransformCmds", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) then return end
            local msg = datapack[1]
            if not isstring(msg) then return end
            if AC.HandleChat and AC.HandleChat(ply, msg) then
                datapack[1] = ""
                datapack.SkipPlayerSay = true
            end

        if datapack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "GRM_Ach_ChatCmds", function(ply, text)
        if AC.HandleChat and AC.HandleChat(ply, text) then return "" end
    end)

    print("[GRM Ach] Достижения и награды v" .. AC.Version .. " загружены (Код 78, реестр: " .. tostring(#AC.Order) .. ")")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMAch_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
    surface.CreateFont("GRMAch_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMAch_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMAch_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })
    surface.CreateFont("GRMAch_Big",    { font = "Roboto", size = 24, weight = 800, extended = true })

    local C = {
        bg    = Color(24, 28, 38, 240),
        panel = Color(32, 38, 50, 245),
        panel2= Color(26, 32, 42, 235),
        gold  = Color(255, 214, 100),
        green = Color(60, 190, 110),
        acc   = Color(70, 150, 240),
        dim   = Color(170, 180, 195),
        text  = Color(240, 245, 250),
    }

    local function fmtMoney(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

    -- тост разблокировки -------------------------------------------------------
    local toast = nil
    net.Receive(NET_UNLOCKED, function()
        local name = net.ReadString() or ""
        local desc = net.ReadString() or ""
        local reward = net.ReadUInt(24) or 0
        toast = { name = name, desc = desc, reward = reward, untilT = CurTime() + 6, at = CurTime() }
        surface.PlaySound("buttons/button9.wav")
        timer.Simple(0.35, function() surface.PlaySound("garrysmod/save_load" .. tostring(math.random(1, 4)) .. ".wav") end)
    end)

    -- Тост гаснет по альфе — цвет не константа, а скретч с записью полей
    -- перед каждой отрисовкой (все потребление немедленное; §6.1.8)
    local ACH_C = Color(0, 0, 0, 255)
    local function achCol(r, g, b, a)
        ACH_C.r = r
        ACH_C.g = g
        ACH_C.b = b
        ACH_C.a = a
        return ACH_C
    end

    hook.Add("HUDPaint", "GRM_Ach_Toast", function()
        if not istable(toast) then return end
        local now = CurTime()
        if now > toast.untilT then toast = nil return end
        local a = 255
        local left = toast.untilT - now
        if left < 1 then a = math.floor(255 * left) end
        local slide = math.max(0, 0.35 - (now - toast.at)) / 0.35 -- 1 → 0 въезд
        local w, h = 460, 74
        local x = ScrW() / 2 - w / 2
        local y = 70 - slide * 60
        draw.RoundedBox(8, x, y, w, h, achCol(20, 24, 32, math.min(235, a)))
        surface.SetDrawColor(C.gold.r, C.gold.g, C.gold.b, a)
        surface.DrawOutlinedRect(x, y, w, h, 2)
        draw.SimpleText("★ ДОСТИЖЕНИЕ РАЗБЛОКИРОВАНО", "GRMAch_Small", ScrW() / 2, y + 12, achCol(C.gold.r, C.gold.g, C.gold.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(tostring(toast.name) .. "  (+" .. fmtMoney(toast.reward) .. ")", "GRMAch_Big", ScrW() / 2, y + 30, achCol(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(tostring(toast.desc), "GRMAch_Small", ScrW() / 2, y + 56, achCol(C.dim.r, C.dim.g, C.dim.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end)

    -- вкладка «Ачивки» в F4 -----------------------------------------------------
    hook.Add("GRM_F4_BuildTabs", "GRM_Ach_Tab", function(sheet)
        if not IsValid(sheet) then return end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        panel:DockPadding(8, 8, 8, 8)

        local head = vgui.Create("DPanel", panel)
        head:Dock(TOP) head:SetTall(46)
        head.Paint = function(_, pw, ph)
            draw.RoundedBox(6, 0, 0, pw, ph, C.panel)
            draw.SimpleText("Ачивки и ежедневный бонус", "GRMAch_Sub", 10, 12, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local cnt = panel._cnt or "…"
            draw.SimpleText(cnt, "GRMAch_Normal", 10, 29, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        local sc = vgui.Create("DScrollPanel", panel)
        sc:Dock(FILL) sc:DockMargin(0, 6, 0, 6)

        local function buildRows(rows)
            sc:Clear()
            for i, r in ipairs(rows) do
                local row = vgui.Create("DPanel", sc)
                row:Dock(TOP) row:SetTall(52) row:DockMargin(0, 0, 0, 4)
                row.Paint = function(_, pw, ph)
                    draw.RoundedBox(5, 0, 0, pw, ph, r.unlocked and Color(30, 42, 34, 245) or C.panel2)
                    local frac = math.Clamp((tonumber(r.cur) or 0) / math.max(1, tonumber(r.goal) or 1), 0, 1)
                    local glyph = r.unlocked and "★" or (r.hidden and "?" or "•")
                    local gcol = r.unlocked and C.gold or C.dim
                    draw.SimpleText(glyph, "GRMAch_Big", 20, ph / 2, gcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText(tostring(r.name), "GRMAch_Sub", 44, 8, r.unlocked and C.gold or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText(tostring(r.desc), "GRMAch_Small", 44, 27, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    -- прогресс-бар
                    local bw = pw - 320
                    draw.RoundedBox(3, 44, ph - 12, bw, 6, Color(18, 22, 30))
                    if r.unlocked then
                        draw.RoundedBox(3, 44, ph - 12, bw, 6, C.gold)
                    elseif frac > 0 then
                        draw.RoundedBox(3, 44, ph - 12, math.max(4, bw * frac), 6, C.acc)
                    end
                    draw.SimpleText((r.unlocked and "ПОЛУЧЕНО" or (tostring(math.floor(r.cur)) .. " / " .. tostring(r.goal))) .. "   •   +" .. fmtMoney(r.reward), "GRMAch_Small", pw - 14, ph / 2, r.unlocked and C.gold or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end

        net.Receive(NET_DATA, function()
            if not IsValid(panel) then return end
            local done = net.ReadUInt(8) or 0
            local total = net.ReadUInt(8) or 0
            local earned = net.ReadUInt(24) or 0
            local streak = net.ReadUInt(8) or 0
            local rows = net.ReadTable() or {}
            panel._cnt = "Разблокировано: " .. tostring(done) .. "/" .. tostring(total) ..
                "  •  наград получено: " .. fmtMoney(earned) ..
                "  •  стрик входа: " .. tostring(streak) .. " дн."
            buildRows(rows)
        end)

        local bRef = vgui.Create("DButton", panel)
        bRef:Dock(BOTTOM) bRef:SetTall(28) bRef:SetText("Обновить")
        bRef:SetFont("GRMAch_Sub") bRef:SetTextColor(color_white)
        bRef.Paint = function(self, w, h) draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(90, 170, 250) or C.acc) end
        bRef.DoClick = function() net.Start(NET_GET) net.SendToServer() end

        timer.Simple(0.2, function()
            if IsValid(panel) then net.Start(NET_GET) net.SendToServer() end
        end)

        sheet:AddSheet("Ачивки", panel, "icon16/medal_gold_1.png")
    end)

    print("[GRM Ach] Клиент достижений v" .. AC.Version .. " загружен")
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/ach", "/achievements" })
end
