--[[--------------------------------------------------------------------
    GRM Admin Hub v1.0.0 (Код 79) — Единая админ-панель сборки

    Одно окно для суперадмина вместо охоты по разным меню. Открытие:
    /grm_admin в чате (через чат-контракт находки 89), консоль grm_admin.

    Вкладки:
      «Сервер»   — онлайн, карта, аптайм сессии, версии модулей GRM,
                   счётчики (активные задачи/публикации/багажники/фракции);
      «Доступы»  — матрица фракция × (ДОСКА/ЭФИР/ОПОВЕЩ/БИРЖА) — те же
                   хранилища, что у /factions → «Доступы» и чат-команд,
                   но СОБСТВЕННЫЙ протокол (не воюет за receiver'ы моста);
      «Биржа»    — активные задачи игроков (с провалом), заказы и
                   вакансии фракций (с удалением и возвратом эскроу);
      «Игроки»   — онлайн: ник/RP-имя/SID64/баланс/ачивки, копия
                   SteamID, сброс ачивок (AC.AdminReset);
      «Меню»     — быстрый запуск остальных админ-меню сборки
                   (/factions, экономика, двери, модели, оружие,
                   ЗП/логистика/транспорт/телефоны/ордера).

    Протокол свой: GRM_HUB_Get {tab} → GRM_HUB_Data {tab, payload};
    GRM_HUB_Act {action, args}. Везде проверка IsSuperAdmin на сервере.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.AdminHub = GRM.AdminHub or {}
local HB = GRM.AdminHub

HB.Version = "1.4.0"

local NET_GET  = "GRM_HUB_Get"
local NET_DATA = "GRM_HUB_Data"
local NET_ACT  = "GRM_HUB_Act"
local NET_OPEN = "GRM_HUB_Open"
local NET_LAUNCH = "GRM_HUB_Launch"
local NET_LAUNCH_RESULT = "GRM_HUB_LaunchResult"

local LAUNCH_WHITELIST = {
    ["/factions"] = true, ["/salary_admin"] = true, ["/feco_admin"] = true, ["/door_access"] = true,
    ["/property_admin"] = true,
    ["/models_admin"] = true, ["/weapons_admin"] = true, ["/mask_admin"] = true,
    ["grm_bodygroups_admin"] = true, ["/bodygroups_admin"] = true,
    ["/logistics_admin"] = true, ["/vshop_admin"] = true, ["grm_racks"] = true,
    ["/scanvehicles"] = true, ["/phoneshop_admin"] = true, ["/phone_access"] = true,
    ["/grm_persistence"] = true, ["/grm_minimap_admin"] = true, ["/grm_arrest_admin"] = true,
    ["/grm_accessories_admin"] = true, ["/grm_quests_admin"] = true, ["/grm_network_admin"] = true, ["/tickets"] = true, ["/wanted"] = true, ["/wanted_access"] = true, ["/warrants"] = true,
    ["/board"] = true, ["/case_requests"] = true, ["/spec"] = true,
    ["/bcasters"] = true, ["/alert"] = true, ["/rn_status"] = true,
    ["grm_augmentations_admin"] = true,
    ["grm_chips"] = true,
    ["/doc_admin"] = true,
    ["/doccfg"] = true,
    -- Пожарная служба (заказ владельца 18.08: в хабе не было ни одной кнопки)
    ["/fire_access"] = true, ["/fire_spots"] = true, ["/fire_log"] = true,
    ["/fire_trucks"] = true,
    ["grm_fire_access"] = true, ["grm_fire_notify"] = true, ["grm_fire_spots"] = true,
    ["grm_fire_log"] = true, ["grm_fire_trucks"] = true, ["grm_fire_calls"] = true,
    -- Торговцы и транспорт
    ["grm_phone_vendor_reload"] = true, ["grm_vendor_load"] = true,
}

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_GET)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_LAUNCH)
    util.AddNetworkString(NET_LAUNCH_RESULT)

    local function sendLaunchResult(ply, ok, message)
        net.Start(NET_LAUNCH_RESULT)
            net.WriteBool(ok == true)
            net.WriteString(tostring(message or ""))
        net.Send(ply)
    end

    net.Receive(NET_LAUNCH, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local command = string.lower(string.Trim(net.ReadString() or ""))
        if not LAUNCH_WHITELIST[command] then
            sendLaunchResult(ply, false, "Команда не разрешена единым админ-меню")
            return
        end

        -- Повторяем реальный контракт EasyChat, но без `say`: сначала
        -- PlayerSayTransform, затем PlayerSay только если команда не была
        -- поглощена transform-хуком. Поэтому кнопки и ручной ввод идентичны.
        local pack = { command, false, false }
        local transformed = hook.Run("PlayerSayTransform", ply, pack, false, false)
        if transformed == false then
            sendLaunchResult(ply, false, "Команда отклонена обработчиком")
            return
        end
        local consumed = pack.SkipPlayerSay == true or not isstring(pack[1]) or string.Trim(pack[1]) == ""
        if not consumed then hook.Run("PlayerSay", ply, pack[1], false, false) end
        sendLaunchResult(ply, true, "Запущено: " .. command)
    end)

    local function accTable(kind)
        if kind == "board" then
            return (GRM.Board and GRM.Board.Cfg and GRM.Board.Cfg.allow) or {}
        elseif kind == "journ" then
            return (GRM.Broadcast and GRM.Broadcast.Cfg and GRM.Broadcast.Cfg.journalists) or {}
        elseif kind == "alert" then
            return (GRM.Broadcast and GRM.Broadcast.Cfg and GRM.Broadcast.Cfg.alerters) or {}
        elseif kind == "jobs" then
            return (GRM.Jobs and GRM.Jobs.Cfg and GRM.Jobs.Cfg.allow) or {}
        end
        return {}
    end

    local function factionsList()
        local out = {}
        if istable(Factions) then
            for name, f in pairs(Factions) do
                if istable(f) then
                    out[#out + 1] = { name = name, leader = tostring(f.Leader or "—"), members = istable(f.Members) and table.Count(f.Members) or 0 }
                end
            end
        end
        table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
        return out
    end

    local function payloadServer()
        local vers = {}
        local function v(name, val) vers[#vers + 1] = { name = name, ver = tostring(val or "—") } end
        v("Биржа труда", GRM.Jobs and GRM.Jobs.Version)
        v("Ачивки", GRM.Ach and GRM.Ach.Version)
        v("Багажник", GRM.Trunk and GRM.Trunk.Version)
        v("Q-меню/инструменты", GRM.QMenu and GRM.QMenu.Version)
        v("Радио/оповещение", GRM.Broadcast and GRM.Broadcast.Version)
        v("Доска набора", GRM.Board and GRM.Board.Version)
        v("Аугментации", GRM.Augmentations and "2.0.0")
        v("Чипы аугментаций", GRM.AugChips and "1.0.0")
        v("Торгаши", GRM.Vendor and GRM.Vendor.Version)
        v("Валюта", "2.0.3")
        v("Экономика", "3.0.4")
        local posts = 0
        if GRM.Jobs and istable(GRM.Jobs.Cfg) then
            for _, list in pairs(GRM.Jobs.Cfg.posts or {}) do posts = posts + #list end
        end
        return {
            online = #player.GetAll(), map = game.GetMap(), uptime = math.floor(CurTime() or 0),
            versions = vers,
            counters = {
                { name = "Фракций", val = istable(Factions) and table.Count(Factions) or 0 },
                { name = "Активных задач биржи", val = (GRM.Jobs and GRM.Jobs.Active) and table.Count(GRM.Jobs.Active) or 0 },
                { name = "Публикаций на бирже", val = posts },
                { name = "Багажников в базе", val = (GRM.Trunk and GRM.Trunk.Store) and table.Count(GRM.Trunk.Store) or 0 },
                { name = "Записей ачивок", val = (GRM.Ach and GRM.Ach.Records) and table.Count(GRM.Ach.Records) or 0 },
                { name = "Игроков с аугментациями", val = (GRM.Augmentations and GRM.Augmentations.PlayerData) and table.Count(GRM.Augmentations.PlayerData) or 0 },
                { name = "Созданных чипов", val = (GRM.AugChips and GRM.AugChips.PlayerChips) and (function() local count = 0 for _, chips in pairs(GRM.AugChips.PlayerChips) do count = count + #chips end return count end)() or 0 },
            },
            factions = factionsList(),
        }
    end

    local function payloadAccess()
        return {
            factions = factionsList(),
            board = accTable("board"), journ = accTable("journ"), alert = accTable("alert"), jobs = accTable("jobs"),
        }
    end

    local function payloadJobs()
        local active = {}
        if GRM.Jobs and istable(GRM.Jobs.Active) then
            for sid, j in pairs(GRM.Jobs.Active) do
                if istable(j) then
                    active[#active + 1] = {
                        sid = tostring(sid), title = tostring(j.title or ""), jtype = tostring(j.jtype or ""),
                        remain = math.max(0, (j.deadline or os.time()) - os.time()),
                        stayLeft = tonumber(j.stayLeft) or 0, reward = tonumber(j.reward) or 0,
                    }
                end
            end
        end
        local posts = {}
        if GRM.Jobs and istable(GRM.Jobs.Cfg) then
            for fac, list in pairs(GRM.Jobs.Cfg.posts or {}) do
                for _, p in ipairs(list or {}) do
                    posts[#posts + 1] = {
                        fac = fac, id = tonumber(p.id) or 0, kind = tostring(p.kind or "order"),
                        title = tostring(p.title or ""), taken = p.takenBy ~= nil,
                        escrow = (GRM.Jobs.PostEscrow and GRM.Jobs.PostEscrow(p)) or (tonumber(p.reward) or 0),
                        shiftsLeft = tonumber(p.shiftsLeft) or 0,
                    }
                end
            end
        end
        table.sort(active, function(a, b) return a.sid < b.sid end)
        table.sort(posts, function(a, b) return (a.fac == b.fac) and (a.id < b.id) or (a.fac < b.fac) end)
        return { active = active, posts = posts }
    end

    local function payloadPlayers()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                local sid = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or p:SteamID()
                local achDone, achTotal = 0, 0
                if GRM.Ach then
                    achTotal = #(GRM.Ach.Order or {})
                    local rec = GRM.Ach.Records and GRM.Ach.Records[sid]
                    if istable(rec) then for id in pairs(rec.u or {}) do achDone = achDone + 1 end end
                end
                out[#out + 1] = {
                    nick = p:Nick(), rp = p:GetNWString("GRM_RPName", ""), sid = tostring(sid),
                    bal = (GRM.GetBalance and GRM.GetBalance(p)) or 0,
                    ach = achDone, achTotal = achTotal,
                }
            end
        end
        table.sort(out, function(a, b) return a.nick:lower() < b.nick:lower() end)
        return out
    end

    -- ==== вкладка ЭКОНОМИКА (Код 82) ====
    local function payloadEcon()
        local factions = {}
        if istable(Factions) then
            for name in pairs(Factions) do
                local info = GRM.Economy and GRM.Economy.FactionInfo and GRM.Economy.FactionInfo(name)
                local f = Factions[name]
                local roles = {}
                if istable(f) and istable(f.Roles) then
                    for _, r in ipairs(f.Roles) do roles[#roles + 1] = tostring(r) end
                end
                local depts = {}
                if istable(f) and istable(f.Departments) then
                    for _, dd in ipairs(f.Departments) do depts[#depts + 1] = tostring(dd) end
                end
                factions[#factions + 1] = {
                    name = name,
                    budget = (info and info.budget) or (GRM.FactionBudgetGet and GRM.FactionBudgetGet(name)) or 0,
                    taxRate = (info and info.taxRate) or 0,
                    baseSalary = (info and info.baseSalary) or 0,
                    salaryInterval = (info and info.salaryInterval) or 0,
                    payFromBudget = (info and info.payFromBudget) == true,
                    leader = (istable(f) and tostring(f.Leader or "")) or "",
                    leaderRole = (istable(f) and tostring(f.LeaderRoleName or "")) or "",
                    roles = roles,
                    departments = depts,
                }
            end
            table.sort(factions, function(a, b) return a.name:lower() < b.name:lower() end)
        end
        local players = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                players[#players + 1] = {
                    nick = p:Nick(), sid = tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or p:SteamID()),
                    bal = (GRM.GetBalance and GRM.GetBalance(p)) or 0,
                }
            end
        end
        table.sort(players, function(a, b) return a.nick:lower() < b.nick:lower() end)
        return {
            state = (GRM.Economy and GRM.Economy.StateBudgetGet and GRM.Economy.StateBudgetGet()) or 0,
            factions = factions,
            players = players,
        }
    end

    -- ==== вкладка ИНСТРУМЕНТЫ / Q-МЕНЮ (Код 83) ====
    local function payloadTools()
        local c = (GRM.QMenu and GRM.QMenu.Cfg) or {}
        local flags = {}
        for _, k in ipairs({ "playersQ", "allowProps", "allowRagdolls", "allowEffects",
            "allowNPCs", "allowSENTs", "allowSWEPs", "allowVehiclesQ", "whitelistMode",
            "grmBuildMenu", "propsFree" }) do
            flags[#flags + 1] = { key = k, val = c[k] == true }
        end
        local tools = {}
        for _, t in ipairs((GRM.QMenu and GRM.QMenu.ToolCatalog) or {}) do
            tools[#tools + 1] = {
                id = t.id, label = t.label,
                deny = istable(c.toolDeny) and c.toolDeny[t.id] == true or false,
                allow = istable(c.toolAllow) and c.toolAllow[t.id] == true or false,
            }
        end
        return { flags = flags, tools = tools }
    end

    local function pushTab(ply, tab)
        local payload = {}
        if tab == "server" then payload = payloadServer()
        elseif tab == "access" then payload = payloadAccess()
        elseif tab == "jobs" then payload = payloadJobs()
        elseif tab == "players" then payload = payloadPlayers()
        elseif tab == "econ" then payload = payloadEcon()
        elseif tab == "tools" then payload = payloadTools()
        else tab = "server" payload = payloadServer() end
        net.Start(NET_DATA)
            net.WriteString(tab)
            net.WriteTable(payload)
        net.Send(ply)
    end

    net.Receive(NET_GET, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        pushTab(ply, tostring(net.ReadString() or "server"))
    end)

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local act = tostring(net.ReadString() or "")
        local args = net.ReadTable() or {}
        local msg = nil

        if act == "accSet" then
            local kind, fac, allow = tostring(args.kind or ""), tostring(args.fac or ""), args.allow == true
            if not (istable(Factions) and istable(Factions[fac])) then msg = "Фракция не найдена"
            elseif kind == "board" and GRM.Board and GRM.Board.Cfg then
                GRM.Board.Cfg.allow[fac] = allow and true or nil
                if not allow then GRM.Board.Cfg.open[fac] = nil end
                GRM.Board.SaveCfg()
                msg = "ДОСКА «" .. fac .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН")
            elseif (kind == "journ" or kind == "alert") and GRM.Broadcast and GRM.Broadcast.Cfg then
                accTable(kind)[fac] = allow and true or nil
                GRM.Broadcast.SaveCfg()
                msg = (kind == "journ" and "ЭФИР «" or "ОПОВЕЩ. «") .. fac .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН")
            elseif kind == "jobs" and GRM.Jobs and GRM.Jobs.Cfg then
                GRM.Jobs.Cfg.allow[fac] = allow and true or nil
                GRM.Jobs.SaveCfg("hub: БИРЖА " .. fac)
                msg = "БИРЖА «" .. fac .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН")
            else msg = "Канал недоступен" end
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Хаб] " .. tostring(msg)) end
            pushTab(ply, "access")
        elseif act == "jobFail" then
            if GRM.Jobs and GRM.Jobs.Fail then
                local sid = tostring(args.sid or "")
                local target = nil
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and (p:SteamID64() == sid or p:SteamID() == sid) then target = p break end
                end
                if IsValid(target) then GRM.Jobs.Fail(target, "снято администратором") else GRM.Jobs.Fail(sid, "снято администратором") end
                ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Задача снята: " .. sid)
            end
            pushTab(ply, "jobs")
        elseif act == "postDel" then
            local fac, id = tostring(args.fac or ""), tostring(args.id or "")
            local done, refund = false, 0
            if GRM.Jobs and istable(GRM.Jobs.Cfg) and istable(GRM.Jobs.Cfg.posts[fac]) then
                local list = GRM.Jobs.Cfg.posts[fac]
                for i, p in ipairs(list) do
                    if tostring(p.id) == id then
                        if p.takenBy ~= nil then
                            -- исполнитель в пути: проваливаем (многоразовая вакансия при этом ОСТАНЕТСЯ
                            -- на витрине со снятой бронью — урок фикса Кода 77 v1.1.0)
                            for _, pl in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                                if IsValid(pl) then
                                    local j = GRM.Jobs.Active and GRM.Jobs.Active[((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(pl)) or pl:SteamID64() or pl:SteamID())]
                                    if istable(j) and j.fromPost and tostring(j.postId) == tostring(p.id) then
                                        GRM.Jobs.Fail(pl, "публикация удалена админом")
                                    end
                                end
                            end
                        end
                        -- пост ещё на витрине? вернуть остаток эскроу и снять окончательно
                        local idx = nil
                        for k, q in ipairs(list) do if tostring(q.id) == id then idx = k break end end
                        if idx then
                            refund = (GRM.Jobs.PostEscrow and GRM.Jobs.PostEscrow(p)) or 0
                            if refund > 0 and GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fac, refund, "Хаб: публикация удалена") end
                            table.remove(list, idx)
                            GRM.Jobs.SaveCfg("hub: удаление поста")
                        end
                        done = true
                        break
                    end
                end
            end
            ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Публикация " .. (done and ("удалена" .. (refund > 0 and (", остаток эскроу " .. refund .. " возвращён") or "")) or "не найдена") .. ": " .. fac .. " #" .. id)
            pushTab(ply, "jobs")
        elseif act == "achReset" then
            if GRM.Ach and GRM.Ach.AdminReset then
                GRM.Ach.AdminReset(tostring(args.sid or ""))
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and (p:SteamID64() == tostring(args.sid or "") or p:SteamID() == tostring(args.sid or "")) then
                        if GRM.Notify then GRM.Notify(p, "Ваш прогресс ачивок сброшен администрацией.", 255, 130, 110) end
                    end
                end
                ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Ачивки сброшены: " .. tostring(args.sid))
            end
            pushTab(ply, "players")

        -- ══ ЭКОНОМИКА (Код 82) ══
        elseif act == "econState" then
            local op, v = tostring(args.op or ""), math.max(0, math.floor(tonumber(args.amount) or 0))
            if GRM.Economy then
                if op == "give" then GRM.Economy.StateBudgetAdd(v, ("Хаб: %s +%s"):format(ply:Nick(), v))
                elseif op == "take" then GRM.Economy.StateBudgetAdd(-math.min(v, GRM.Economy.StateBudgetGet()), ("Хаб: %s -%s"):format(ply:Nick(), v))
                elseif op == "set" then GRM.Economy.StateBudgetSet(v, "Хаб: установил " .. ply:Nick()) end
                ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Гос.бюджет: " .. tostring(GRM.Economy.StateBudgetGet()))
            end
            pushTab(ply, "econ")
        elseif act == "econFac" then
            local fac, op = tostring(args.fac or ""), tostring(args.op or "")
            local v = math.max(0, math.floor(tonumber(args.amount) or 0))
            if fac ~= "" and GRM.FactionBudgetAdd then
                if op == "give" then GRM.FactionBudgetAdd(fac, v, ("Хаб: %s +%s"):format(ply:Nick(), v))
                elseif op == "take" then GRM.FactionBudgetAdd(fac, -math.min(v, GRM.FactionBudgetGet(fac)), ("Хаб: %s -%s"):format(ply:Nick(), v)) end
                -- Валюта сборки — GRM: печатаем через общий форматтер, а не голым числом.
                ply:PrintMessage(HUD_PRINTTALK, ("[Хаб] Бюджет «%s»: %s"):format(fac,
                    (GRM.Format and GRM.Format(GRM.FactionBudgetGet(fac))) or (tostring(GRM.FactionBudgetGet(fac)) .. " GRM")))
            end
            pushTab(ply, "econ")
        elseif act == "econCash" then
            local sid, op = tostring(args.sid or ""), tostring(args.op or "")
            local v = math.max(0, math.floor(tonumber(args.amount) or 0))
            local target = sid
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and (tostring(p:SteamID64()) == sid or tostring(p:SteamID()) == sid) then target = p break end
            end
            if op == "give" and GRM.GiveMoney then GRM.GiveMoney(target, v, "Хаб: выдача " .. ply:Nick())
            elseif op == "take" and GRM.TakeMoney then GRM.TakeMoney(target, v, "Хаб: изъятие " .. ply:Nick())
            elseif op == "set" and GRM.SetBalance then GRM.SetBalance(target, v, "Хаб: установка " .. ply:Nick()) end
            ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Баланс " .. sid .. ": " .. tostring(GRM.GetBalance and GRM.GetBalance(target) or "?"))
            pushTab(ply, "econ")

        -- ══ ИНСТРУМЕНТЫ / Q-МЕНЮ (Код 83) ══
        elseif act == "qToggle" then
            local key = tostring(args.key or "")
            local valid = { playersQ = true, allowProps = true, allowRagdolls = true, allowEffects = true,
                allowNPCs = true, allowSENTs = true, allowSWEPs = true, allowVehiclesQ = true, whitelistMode = true,
                grmBuildMenu = true, propsFree = true }
            if valid[key] and GRM.QMenu then
                GRM.QMenu.Cfg[key] = args.val == true
                GRM.QMenu.Save("hub: " .. key)
                ply:PrintMessage(HUD_PRINTTALK, ("[Хаб] Q-меню: %s = %s"):format(key, tostring(GRM.QMenu.Cfg[key])))
            end
            pushTab(ply, "tools")
        elseif act == "qTool" then
            local tool, list = tostring(args.tool or ""), tostring(args.list or "deny")
            if tool ~= "" and GRM.QMenu then
                local tbl = (list == "allow") and GRM.QMenu.Cfg.toolAllow or GRM.QMenu.Cfg.toolDeny
                tbl[tool] = (args.val == true) and true or nil
                GRM.QMenu.Save("hub: tool " .. tool)
            end
            pushTab(ply, "tools")
        end
    end)

    local function openHub(ply)
        if not IsValid(ply) then return false end
        local isSuper = ply:IsSuperAdmin() == true
        local econAccess = isSuper or (GRM.Economy and GRM.Economy.CanManageEconomy and GRM.Economy.CanManageEconomy(ply) == true)
        if not isSuper and not econAccess then
            ply:PrintMessage(HUD_PRINTTALK, "[Хаб] Единая админ-панель — только суперадмин.")
            return true
        end
        net.Start(NET_OPEN)
            net.WriteBool(econAccess == true)  -- доступ к вкладке «Экономика» (находка 172)
            net.WriteBool(isSuper)
        net.Send(ply)
        return true
    end
    concommand.Add("grm_admin", function(ply) openHub(ply) end)

    hook.Add("PlayerSayTransform", "GRM_Hub_TransformCmds", function(ply, datapack)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        local low = string.lower(string.Trim(msg))
        if low == "/grm_admin" or low == "/admin" or low == "/админ" then
            if openHub(ply) then
                datapack[1] = ""
                datapack.SkipPlayerSay = true
            end
        end
    end)
    hook.Add("PlayerSayTransform", "GRM_Hub_ChatCmds", function(ply, datapack)
        if not istable(datapack) then return end
        local text = datapack[1]
        if not isstring(text) then return end

        local low = string.lower(string.Trim(text))
        if low == "/grm_admin" or low == "/admin" or low == "/админ" then
            if openHub(ply) then
                datapack.SkipPlayerSay = true
                datapack[1] = ""
                return
            end
        end
    end)

    print("[GRM Hub] Единая админ-панель v" .. HB.Version .. " загружена (Код 79): /grm_admin")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMHub_Title",  { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMHub_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMHub_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMHub_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })

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
        return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
    end

    local function mkBtn(p, txt, col, w, h)
        local b = vgui.Create("DButton", p)
        b:SetText(txt) b:SetFont("GRMHub_Normal") b:SetTextColor(color_white)
        if w and h then b:SetSize(w, h) end
        b.Paint = function(self, pw, ph)
            local cc = col or C.acc
            if self:IsHovered() then cc = Color(math.min(255, cc.r + 25), math.min(255, cc.g + 25), math.min(255, cc.b + 25)) end
            draw.RoundedBox(5, 0, 0, pw, ph, cc)
        end
        return b
    end

    local function askTab(tab)
        net.Start(NET_GET)
            net.WriteString(tab)
        net.SendToServer()
    end
    local function act(action, args)
        net.Start(NET_ACT)
            net.WriteString(action)
            net.WriteTable(args or {})
        net.SendToServer()
    end

    local function block(sc, h, title, accent)
        local b = vgui.Create("DPanel", sc)
        b:Dock(TOP) b:SetTall(h) b:DockMargin(0, 0, 0, 6)
        b.Paint = function(_, pw, ph)
            draw.RoundedBox(6, 0, 0, pw, ph, C.panel)
            draw.SimpleText(title, "GRMHub_Sub", 10, 13, accent or C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        return b
    end

    -- ==== вкладка СЕРВЕР ====
    local function buildServer(sc, d)
        sc:Clear()
        local b1 = block(sc, 78, "Сервер:", C.acc)
        local l = vgui.Create("DLabel", b1)
        l:SetPos(12, 26) l:SetSize(900, 46) l:SetFont("GRMHub_Normal") l:SetTextColor(C.text)
        l:SetText("Онлайн: " .. tostring(d.online or 0) .. "    Карта: " .. tostring(d.map or "?") .. "    Аптайм сессии: " .. fmtTime(d.uptime or 0) ..
            "\nПанель: /grm_admin • аудит протоколов: tools/proto_audit.py • версии модулей ниже")
        l:SetWrap(true) l:SetAutoStretchVertical(true)

        local cnt = istable(d.counters) and d.counters or {}
        local b2 = block(sc, 30 + #cnt * 22 + 8, "Счётчики сборки:", C.yellow)
        for i, cRow in ipairs(cnt) do
            local r = vgui.Create("DLabel", b2)
            r:SetPos(12, 24 + (i - 1) * 22) r:SetSize(600, 20) r:SetFont("GRMHub_Normal")
            r:SetTextColor(C.text) r:SetText(tostring(cRow.name) .. ": " .. tostring(cRow.val))
        end

        local vers = istable(d.versions) and d.versions or {}
        local b3 = block(sc, 30 + #vers * 22 + 8, "Версии модулей:", C.teal)
        for i, v in ipairs(vers) do
            local r = vgui.Create("DLabel", b3)
            r:SetPos(12, 24 + (i - 1) * 22) r:SetSize(600, 20) r:SetFont("GRMHub_Normal")
            r:SetTextColor(C.text) r:SetText(tostring(v.name) .. " — v" .. tostring(v.ver))
        end

        local fs = istable(d.factions) and d.factions or {}
        local b4 = block(sc, 30 + math.max(1, #fs) * 24 + 8, "Фракции (" .. tostring(#fs) .. "):", C.green)
        if #fs == 0 then
            local r = vgui.Create("DLabel", b4)
            r:SetPos(12, 28) r:SetSize(880, 20) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Фракций нет. Создание: /factions → вкладка «Создать».")
        end
        for i, f in ipairs(fs) do
            local r = vgui.Create("DLabel", b4)
            r:SetPos(12, 26 + (i - 1) * 24) r:SetSize(900, 22) r:SetFont("GRMHub_Normal") r:SetTextColor(C.text)
            r:SetText(tostring(f.name) .. "   •   лидер: " .. tostring(f.leader) .. "   •   состав: " .. tostring(f.members))
        end

        -- Находка 179h (в /grm_admin): настройка фракций оповещения сигнализации
        local bAlarm = block(sc, 58, "Сигнализация:", C.orange)
        local lAlarm = vgui.Create("DLabel", bAlarm)
        lAlarm:SetPos(12, 26) lAlarm:SetSize(700, 22) lAlarm:SetFont("GRMHub_Normal") lAlarm:SetTextColor(C.text)
        lAlarm:SetText("Оповещение о взломах кейпадов/сканеров/дверей — выберите фракции.")
        local bOpen = mkBtn(bAlarm, "Фракции для оповещения", C.orange, 200, 24)
        bOpen:SetPos(520, 24)
        bOpen.DoClick = function()
            net.Start("GRM_AlarmNotify_Open")
            net.SendToServer()
        end
    end

    -- ==== вкладка ДОСТУПЫ ====
    local function buildAccess(sc, d)
        sc:Clear()
        local fs = istable(d.factions) and d.factions or {}
        local core = block(sc, 74, "GRM Core • единые capability:", C.acc)
        local coreText = vgui.Create("DLabel", core)
        coreText:SetPos(12, 27); coreText:SetSize(650, 36); coreText:SetFont("GRMHub_Small"); coreText:SetTextColor(C.text)
        coreText:SetWrap(true); coreText:SetText("Общие allow/deny для фракций, ролей, отделов, аккаунтов и персонажей. Явное решение сильнее старой матрицы ниже.")
        local coreButton = mkBtn(core, "Открыть единые права", C.acc, 220, 30)
        coreButton:SetPos(700, 27); coreButton.DoClick = function() RunConsoleCommand("grm_access") end

        local note = vgui.Create("DLabel", sc)
        note:Dock(TOP) note:SetTall(34) note:SetFont("GRMHub_Small") note:SetTextColor(C.dim)
        note:SetText("Те же хранилища, что /factions → «Доступы» и /board_allow /bcast_allow /alert_allow /job_allow. Суперадмин может всё без галочек.")
        note:SetWrap(true) note:SetAutoStretchVertical(true)

        local head = vgui.Create("DPanel", sc)
        head:Dock(TOP) head:SetTall(24) head:SetPaintBackground(false)
        local function hl(x, t, col)
            local l = vgui.Create("DLabel", head)
            l:SetPos(x, 1) l:SetSize(150, 22) l:SetFont("GRMHub_Sub") l:SetTextColor(col) l:SetText(t)
        end
        hl(10, "Фракция", C.dim) hl(370, "Доска", C.teal) hl(520, "Эфир", C.acc) hl(670, "Оповещ.", C.red) hl(820, "Биржа", C.yellow)

        for _, f in ipairs(fs) do
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(28) row:DockMargin(0, 0, 0, 2)
            row.Paint = function(_, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, C.panel2) end
            local name = tostring(f.name)
            local nl = vgui.Create("DLabel", row)
            nl:SetPos(10, 3) nl:SetSize(350, 22) nl:SetFont("GRMHub_Normal") nl:SetTextColor(C.text) nl:SetText(name)
            local function chk(x, tbl, kind, col)
                local c = vgui.Create("DCheckBoxLabel", row)
                c:SetPos(x, 3) c:SetSize(140, 22)
                local cur = istable(tbl) and tbl[name] == true
                c:SetText(cur and "выдан" or "нет")
                c:SetFont("GRMHub_Normal") c:SetTextColor(cur and col or C.dim)
                c:SetValue(cur and 1 or 0)
                c.OnChange = function(_, v)
                    act("accSet", { kind = kind, fac = name, allow = v and true or false })
                    c:SetText(v and "выдан" or "нет")
                    c:SetTextColor(v and col or C.dim)
                end
            end
            chk(370, d.board, "board", C.teal)
            chk(520, d.journ, "journ", C.acc)
            chk(670, d.alert, "alert", C.red)
            chk(820, d.jobs, "jobs", C.yellow)
        end
        if #fs == 0 then
            local r = vgui.Create("DLabel", sc)
            r:Dock(TOP) r:SetTall(26) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Фракций нет — галочки появятся после создания первой.")
        end
    end

    -- ==== вкладка БИРЖА ====
    local function buildJobs(sc, d)
        sc:Clear()
        local active = istable(d.active) and d.active or {}
        local b1 = block(sc, 30 + math.max(1, #active) * 30 + 8, "Активные задачи игроков (" .. tostring(#active) .. "):", C.yellow)
        if #active == 0 then
            local r = vgui.Create("DLabel", b1)
            r:SetPos(12, 28) r:SetSize(880, 20) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Активных задач нет.")
        end
        for i, j in ipairs(active) do
            local row = vgui.Create("DPanel", b1)
            row:SetPos(8, 26 + (i - 1) * 30) row:SetSize(930, 28)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(4, 0, 0, pw, ph, C.panel2)
                draw.SimpleText(tostring(j.title) .. "  (" .. tostring(j.jtype) .. ")", "GRMHub_Normal", 8, ph / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local left = string.format("%d:%02d", math.floor((tonumber(j.remain) or 0) / 60), (tonumber(j.remain) or 0) % 60)
                local extra = ((tonumber(j.stayLeft) or 0) > 0) and (" • в зоне " .. tostring(j.stayLeft) .. " с") or ""
                draw.SimpleText(tostring(j.sid) .. " • " .. left .. extra .. " • " .. fmtMoney(j.reward or 0), "GRMHub_Small", 8, ph / 2 + 7, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bFail = mkBtn(row, "Провалить", C.red, 90, 22)
            bFail:SetPos(830, 3)
            bFail.DoClick = function() act("jobFail", { sid = j.sid }) end
        end

        local posts = istable(d.posts) and d.posts or {}
        local b2 = block(sc, 30 + math.max(1, #posts) * 30 + 8, "Публикации фракций — заказы и вакансии (" .. tostring(#posts) .. "):", C.teal)
        if #posts == 0 then
            local r = vgui.Create("DLabel", b2)
            r:SetPos(12, 28) r:SetSize(880, 20) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Публикаций нет.")
        end
        for i, p in ipairs(posts) do
            local row = vgui.Create("DPanel", b2)
            row:SetPos(8, 26 + (i - 1) * 30) row:SetSize(930, 28)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(4, 0, 0, pw, ph, C.panel2)
                draw.SimpleText((p.kind == "vacancy" and "ВАКАНСИЯ «" or "заказ «") .. tostring(p.title) .. "» — " .. tostring(p.fac), "GRMHub_Normal", 8, ph / 2, p.kind == "vacancy" and C.green or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local extra = (p.kind == "vacancy") and (" • смен осталось: " .. tostring(p.shiftsLeft or 0)) or ""
                draw.SimpleText("эскроу: " .. fmtMoney(p.escrow or 0) .. extra .. (p.taken and " • ВЗЯТ" or " • свободен"), "GRMHub_Small", 8, ph / 2 + 7, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bDel = mkBtn(row, "Удалить", C.red, 90, 22)
            bDel:SetPos(830, 3)
            bDel.DoClick = function()
                Derma_Query("Удалить публикацию «" .. tostring(p.title) .. "» (" .. tostring(p.fac) .. ")?\nСвободное эскроу вернётся в бюджет.",
                    "Хаб • Биржа", "Удалить", function() act("postDel", { fac = p.fac, id = p.id }) end, "Отмена", function() end)
            end
        end
    end

    -- ==== вкладка ИГРОКИ ====
    local function buildPlayers(sc, d)
        sc:Clear()
        local list = istable(d) and d or {}
        local b1 = block(sc, 30 + math.max(1, #list) * 32 + 8, "Онлайн (" .. tostring(#list) .. "):", C.acc)
        for i, p in ipairs(list) do
            local row = vgui.Create("DPanel", b1)
            row:SetPos(8, 26 + (i - 1) * 32) row:SetSize(930, 30)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(4, 0, 0, pw, ph, C.panel2)
                local nm = tostring(p.nick)
                if p.rp ~= "" and p.rp ~= p.nick then nm = tostring(p.rp) .. "  (Steam: " .. tostring(p.nick) .. ")" end
                draw.SimpleText(nm, "GRMHub_Normal", 8, ph / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(tostring(p.sid) .. " • " .. fmtMoney(p.bal or 0) .. " • ачивки " .. tostring(p.ach or 0) .. "/" .. tostring(p.achTotal or 0),
                    "GRMHub_Small", 8, ph / 2 + 8, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bCopy = mkBtn(row, "SteamID", C.acc, 80, 22)
            bCopy:SetPos(650, 4)
            bCopy.DoClick = function()
                SetClipboardText(tostring(p.sid))
                surface.PlaySound("buttons/button9.wav")
            end
            local bReset = mkBtn(row, "Сброс ачивок", C.red, 130, 22)
            bReset:SetPos(738, 4)
            bReset.DoClick = function()
                Derma_Query("Сбросить ВЕСЬ прогресс ачивок игрока " .. tostring(p.nick) .. " (" .. tostring(p.sid) .. ")?",
                    "Хаб • Игроки", "Сбросить", function() act("achReset", { sid = p.sid }) end, "Отмена", function() end)
            end
        end
        if #list == 0 then
            local r = vgui.Create("DLabel", b1)
            r:SetPos(12, 28) r:SetSize(880, 20) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Никого нет в сети.")
        end
    end

    -- ==== вкладка МЕНЮ (ярлыки) ====
    -- m[1] название, m[2] команда, m[3] подсказка, m[4]==true → только подпись (без нажатия)
    local MENU_LINKS = {
        { "Фракции (админ)", "/factions", "Создание, лидеры, роли, доступы, двери и ордера" },
        { "Документы и Удостоверения", "/doc_admin", "Настройка бланков паспортов, дизайна корочек, префиксов и прав доступа к Компьютеру" },
        { "Доступ служебных компьютеров", "/comp_access", "Список ПК на карте: кому из организаций можно пользоваться каждым терминалом" },
        { "Единая экономика", "/salary_admin", "Зарплаты, налоги, штрафы, банк, бюджеты и настройки экономики" },
        { "Доступ к дверям", "/door_access", "Матрица доступов дверей, категории и фракции" },
        { "Недвижимость и здания", "/property_admin", "Помещения, двери, цены, аренда, владельцы, коммунальные платежи, печати и безопасность" },
        { "Модели фракций", "/models_admin", "Фракционные модели и превью" },
        { "Бодигруппы моделей", "grm_bodygroups_admin", "Что игрок видит и может менять в «Телосложении»: скрыть, закрепить или ограничить части модели по организации, отделу и должности" },
        { "Оружие фракций", "/weapons_admin", "Выдача оружия по фракциям" },
        { "Маски", "/mask_admin", "Настройки масок" },
        { "Пожарные: доступы", "/fire_access", "Кто пользуется рукавами, гидрантами и пультом оповещения о пожаре" },
        { "Пожарные: очаги и таймеры", "grm_fire_spots", "Точки возгорания на карте, интервалы и настройки очагов" },
        { "Пожарные: журнал пожаров", "grm_fire_log", "История возгораний и тушений" },
        { "Пожарные: вызовы (принятие)", "grm_fire_calls", "Активные вызовы расчётов: кто принял, кто ждёт" },
        { "Пожарные: машины", "grm_fire_trucks", "Список пожарных ТС, насосы и рукава" },
        { "Пожарные: оповещение фракций", "grm_fire_notify", "Кому приходит сигнал о пожаре" },
        { "Логистика", "/logistics_admin", "Склады и логистика фракций" },
        { "Оружейные стойки", "grm_racks", "Список стоек на карте: ячейки, закрепление за должностями, содержимое" },
        { "Жильё: диагностика", "grm_housing", "Ваше жильё, точка входа, отдых и доступ к двери под прицелом" },
        { "Жильё: домашние шкафы", "grm_home_storage", "Хранилища квартир: заполненность и доступ к шкафу под прицелом" },
        { "Жильё: журнал входов", "grm_housing_log", "Кто заходил в жильё: ордера, взломы, гости (/housing_log)" },
        { "Жильё: окно квартиры", "grm_home", "Обзор, жильцы, журнал и шкаф одним окном (/home)" },
        { "Жильё: кровать", "grm_home_bed", "Точка входа и выхода: где стоит кровать вашего жилья" },
        { "Магазин транспорта", "/vshop_admin", "Цены доступа к транспорту" },
        { "Скан транспорта", "/scanvehicles", "Все машины на карте" },
        { "Магазин телефонов", "/phoneshop_admin", "Доступ к телефонам/АТС" },
        { "Телефонный доступ", "/phone_access", "Кто пользуется телефонией" },
        { "Единое сохранение карты", "/grm_persistence", "Сохранить/загрузить телефоны, CCTV, завод, логистику и остальные модули" },
        { "GPS и точки", "/grm_minimap_admin", "GPS-точки, подписи и навигация" },
        { "Система ареста", "/grm_arrest_admin", "Камеры, точки содержания, категории, модели и доступы" },
        { "Каталог аксессуаров", "/grm_accessories_admin", "Модели, категории, цены, слоты, кости и стандартные положения" },
        { "Quest Studio", "/grm_quests_admin", "Квесты, этапы, NPC, награды, диалоги, зоны и кат-сцены" },
        { "Студия анимаций", "grm_anim_studio", "Костные позы, категории и социальные анимации (/animstudio)" },
        { "Network Control Center", "/grm_network_admin", "Компьютеры, роутеры, кабели, аккаунты, файлы и сетевые доступы" },
        { "Тикеты", "/tickets", "Очередь обращений игроков и ответы администрации" },
        { "База розыска", "/wanted", "Дела, ручные и каталожные статьи, уровни, штрафы и история" },
        { "Доступ к розыску", "/wanted_access", "Права просмотра и редактирования базы" },
        { "Ордера", "/warrants", "Активные ордера на обыск" },
        { "Лист розыска", "/board", "Общий список разыскиваемых со статусом «гражданский / военный» — без подхода к терминалу" },
        { "Заявки на передачу дел", "/case_requests", "Открытые заявки ведомств на передачу сведений о розыске" },
        { "Оперативный терминал", "/spec", "Спецслужба: полный контроль баз розыска, штрафов и арестов, документы прикрытия, закрытый журнал" },
        { "Каналы эфира/оповещения", "/bcasters", "Печать в чат: фракции с доступами эфира и оповещения" },
        { "Оповещение: синтаксис", "/alert", "Сервер ответит подсказкой: /alert текст (район) или /alertall текст (весь город)" },
        { "Радиосеть: диагностика", "/rn_status", "Стойки/антенны/передатчики/громкоговорители — что в сети, покрытие" },
        { "Аугментации", "grm_augmentations_admin", "Настройка типов аугментаций, категорий, прав доступа и стоимости" },
        { "Программатор чипов", "grm_chips", "Создание, имплантация и управление чипами аугментаций" },
        { "Точки спавна", "/spawnmenu", "Дерево: глобальные → организация → отдел → подотдел → должность; счётчики, поиск, телепорт" },
        { "Дилеры и гаражи", "grm_garage", "Гараж персонажа: выдача/сдача транспорта. Разметка — единый тул «GRM: транспорт»" },
        { "Спавн транспорта (ТАБ)", "ТАБ → игрок", "ТАБ → клик по игроку → «Спавн транспорта»: у ближайшего дилера, без цены/лимита", true },
    }
    -- ==== вкладка ЭКОНОМИКА (Код 82) ====
    local function buildEcon(sc, d)
        sc:Clear()
        local hint = vgui.Create("DLabel", sc)
        hint:Dock(TOP) hint:SetTall(30) hint:SetFont("GRMHub_Small") hint:SetTextColor(C.dim)
        hint:SetText("Полная экономическая панель: /feco_admin. Здесь — быстрые денежные операции.")
        hint:SetWrap(true) hint:SetAutoStretchVertical(true)

        -- Доступ к экономике (находка 172): суперадмин выдаёт полномочия фракциям
        if HB._isSuper then
            local accBtn = mkBtn(sc, "Доступ к экономике (фракции/роли/отделы)", C.acc, 0, 0)
            accBtn:Dock(TOP) accBtn:SetTall(34) accBtn:DockMargin(0, 2, 0, 6)
            accBtn.DoClick = function()
                net.Start("GRM_EcoAccess_Request")
                net.SendToServer()
            end
        end

        -- ГОС.БЮДЖЕТ
        local b1 = block(sc, 118, "Гос.бюджет: " .. fmtMoney(d.state or 0), C.yellow)
        local amt0 = vgui.Create("DTextEntry", b1)
        amt0:SetPos(12, 36) amt0:SetSize(150, 26) amt0:SetNumeric(true) amt0:SetPlaceholderText("Сумма…")
        local function g0() return math.max(0, math.floor(tonumber(amt0:GetValue()) or 0)) end
        local bg1 = mkBtn(b1, "Пополнить", C.green, 110, 26) bg1:SetPos(170, 36)
        bg1.DoClick = function() act("econState", { op = "give", amount = g0() }) end
        local bt1 = mkBtn(b1, "Изъять", C.red, 100, 26) bt1:SetPos(286, 36)
        bt1.DoClick = function() act("econState", { op = "take", amount = g0() }) end
        local bs1 = mkBtn(b1, "Установить", C.acc, 110, 26) bs1:SetPos(392, 36)
        bs1.DoClick = function() act("econState", { op = "set", amount = g0() }) end
        local st = vgui.Create("DLabel", b1)
        st:SetPos(12, 72) st:SetSize(880, 40) st:SetFont("GRMHub_Small") st:SetTextColor(C.dim)
        st:SetText("Гос.бюджет наполняется налогами с ЗП и штрафами (Настройки в /feco_admin). Отсюда же идут трансферы фракциям и выплаты игрокам.")
        st:SetWrap(true) st:SetAutoStretchVertical(true)

        -- ФРАКЦИИ
        local fs = istable(d.factions) and d.factions or {}
        local b2 = block(sc, 30 + math.max(1, #fs) * 30 + 46, "Бюджеты фракций (" .. #fs .. "):", C.green)
        if #fs == 0 then
            local r = vgui.Create("DLabel", b2)
            r:SetPos(12, 28) r:SetSize(880, 20) r:SetFont("GRMHub_Normal") r:SetTextColor(C.dim)
            r:SetText("Фракций нет — создаются в /factions.")
        end
        for i, f in ipairs(fs) do
            local row = vgui.Create("DPanel", b2)
            row:SetPos(8, 24 + (i - 1) * 30) row:SetSize(932, 28)
            row.Paint = function(_, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, C.panel2) end
            local l = vgui.Create("DLabel", row)
            l:SetPos(10, 3) l:SetSize(430, 22) l:SetFont("GRMHub_Normal") l:SetTextColor(C.text)
            l:SetText(("%s — %s  •  налог %d%%  •  ЗП %s/%dс %s"):format(
                tostring(f.name), fmtMoney(f.budget or 0), math.floor((tonumber(f.taxRate) or 0) * 100),
                fmtMoney(f.baseSalary or 0), tonumber(f.salaryInterval) or 0,
                f.payFromBudget and "(из бюджета)" or "(из казны сервера)"))
            local t = vgui.Create("DTextEntry", row)
            t:SetPos(450, 3) t:SetSize(120, 22) t:SetNumeric(true) t:SetPlaceholderText("Сумма…")
            local function gv() return math.max(0, math.floor(tonumber(t:GetValue()) or 0)) end
            local bg = mkBtn(row, "+ Бюджет", C.green, 80, 22) bg:SetPos(578, 3)
            bg.DoClick = function() act("econFac", { fac = f.name, op = "give", amount = gv() }) end
            local bt = mkBtn(row, "− Бюджет", C.red, 80, 22) bt:SetPos(664, 3)
            bt.DoClick = function() act("econFac", { fac = f.name, op = "take", amount = gv() }) end
        end

        -- ИГРОКИ
        local ps = istable(d.players) and d.players or {}
        local b3 = block(sc, 30 + #ps * 30 + 8, "Наличные игроков онлайн (" .. #ps .. "):", C.acc)
        for i, pl in ipairs(ps) do
            local row = vgui.Create("DPanel", b3)
            row:SetPos(8, 24 + (i - 1) * 30) row:SetSize(932, 28)
            row.Paint = function(_, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, C.panel2) end
            local l = vgui.Create("DLabel", row)
            l:SetPos(10, 3) l:SetSize(430, 22) l:SetFont("GRMHub_Normal") l:SetTextColor(C.text)
            l:SetText(tostring(pl.nick) .. " — " .. fmtMoney(pl.bal or 0) .. "  •  " .. tostring(pl.sid))
            local t = vgui.Create("DTextEntry", row)
            t:SetPos(450, 3) t:SetSize(120, 22) t:SetNumeric(true) t:SetPlaceholderText("Сумма…")
            local function gv() return math.max(0, math.floor(tonumber(t:GetValue()) or 0)) end
            local bg = mkBtn(row, "Выдать", C.green, 74, 22) bg:SetPos(578, 3)
            bg.DoClick = function() act("econCash", { sid = pl.sid, op = "give", amount = gv() }) end
            local bt = mkBtn(row, "Снять", C.red, 66, 22) bt:SetPos(658, 3)
            bt.DoClick = function() act("econCash", { sid = pl.sid, op = "take", amount = gv() }) end
            local bs = mkBtn(row, "= Уст.", C.acc, 74, 22) bs:SetPos(730, 3)
            bs.DoClick = function() act("econCash", { sid = pl.sid, op = "set", amount = gv() }) end
        end
    end

    -- ==== вкладка ИНСТРУМЕНТЫ / Q-МЕНЮ (Код 83) ====
    local QFLAG_LABELS = {
        playersQ = "Q-меню игрокам (спавн-меню и C-песочница)",
        allowProps = "Пропы игрокам",
        allowRagdolls = "Рагдоллы игрокам",
        allowEffects = "Эффекты (взрыв/дым) игрокам",
        allowNPCs = "NPC игрокам",
        allowSENTs = "Энтити из Q игрокам",
        allowSWEPs = "Оружие из Q игрокам",
        allowVehiclesQ = "Транспорт из Q игрокам (обычно ВЫКЛ — есть дилер)",
        whitelistMode = "БЕЛЫЙ режим инструментов (разрешены только отмеченные)",
        grmBuildMenu = "Меню стройки GRM вместо ванильного Q (каталог пропов/инструменты)",
        propsFree = "Меню стройки: свободный спавн ЛЮБЫХ моделей (ВЫКЛ — только каталог)",
    }

    local function buildTools(sc, d)
        sc:Clear()
        local hint = vgui.Create("DLabel", sc)
        hint:Dock(TOP) hint:SetTall(44) hint:SetFont("GRMHub_Small") hint:SetTextColor(C.dim)
        hint:SetText("Суперадмин вне ограничений. Чёрный список режет инструменты всем остальным; белый режим — строже: игрокам доступны ТОЛЬКО отмеченные. Изменения сохраняются сразу (data/grm_qmenu.json).")
        hint:SetWrap(true) hint:SetAutoStretchVertical(true)

        local flags = istable(d.flags) and d.flags or {}
        local b1 = block(sc, 30 + #flags * 28 + 8, "Q-меню и спавн:", C.yellow)
        for i, f in ipairs(flags) do
            local cb = vgui.Create("DCheckBoxLabel", b1)
            cb:SetPos(14, 24 + (i - 1) * 28) cb:SetSize(860, 24)
            cb:SetFont("GRMHub_Normal") cb:SetTextColor(C.text)
            cb:SetText(QFLAG_LABELS[f.key] or f.key)
            cb:SetChecked(f.val == true)
            cb.key = f.key
            cb.OnChange = function(self, v) act("qToggle", { key = self.key, val = v == true }) end
        end

        local tools = istable(d.tools) and d.tools or {}
        local b2 = block(sc, 34 + #tools * 26 + 8, "Инструменты toolgun:", C.teal)
        local hl = vgui.Create("DLabel", b2)
        hl:SetPos(300, 20) hl:SetSize(400, 20) hl:SetFont("GRMHub_Small") hl:SetTextColor(C.dim)
        hl:SetText("запрещён          в белом списке")
        for i, t in ipairs(tools) do
            local row = vgui.Create("DPanel", b2)
            row:SetPos(8, 36 + (i - 1) * 26) row:SetSize(932, 24)
            row.Paint = function(_, pw, ph) draw.RoundedBox(3, 0, 0, pw, ph, C.panel2) end
            local l = vgui.Create("DLabel", row)
            l:SetPos(8, 2) l:SetSize(280, 20) l:SetFont("GRMHub_Normal") l:SetTextColor(C.text)
            l:SetText(tostring(t.label or t.id))
            local l2 = vgui.Create("DLabel", row)
            l2:SetPos(240, 2) l2:SetSize(60, 20) l2:SetFont("GRMHub_Small") l2:SetTextColor(C.dim)
            l2:SetText(tostring(t.id))
            local cbd = vgui.Create("DCheckBox", row)
            cbd:SetPos(310, 4) cbd:SetChecked(t.deny == true)
            cbd.tool = t.id
            cbd.OnChange = function(self, v) act("qTool", { tool = self.tool, list = "deny", val = v == true }) end
            local cba = vgui.Create("DCheckBox", row)
            cba:SetPos(430, 4) cba:SetChecked(t.allow == true)
            cba.tool = t.id
            cba.OnChange = function(self, v) act("qTool", { tool = self.tool, list = "allow", val = v == true }) end
        end
    end

    local function launchAdminCommand(command)
        command = string.lower(string.Trim(tostring(command or "")))
        if not LAUNCH_WHITELIST[command] then
            notification.AddLegacy("Команда недоступна в едином меню", NOTIFY_ERROR, 3)
            surface.PlaySound("buttons/button10.wav")
            return
        end

        -- Пункт может быть КОНСОЛЬНОЙ командой (grm_fire_spots и т.п.), а не
        -- чат-командой: такие запускаем локально, иначе сервер получал бы
        -- бессмысленный PlayerSay и кнопка «ничего не делала».
        if command:sub(1, 1) ~= "/" and command:sub(1, 1) ~= "!" then
            RunConsoleCommand(command)
            chat.AddText(C.acc, "[Хаб] ", C.green, "Открыто: ", C.text, command)
            surface.PlaySound("buttons/button14.wav")
            return
        end

        -- Сначала даём клиентским PlayerSayTransform-командам открыть их
        -- локальные окна (/models_admin, /weapons_admin, /mask_admin и т.п.).
        local pack = { command, false, false }
        local result = hook.Run("PlayerSayTransform", LocalPlayer(), pack, false, false)
        local consumed = result == false or pack.SkipPlayerSay == true
            or not isstring(pack[1]) or string.Trim(pack[1]) == ""
        if consumed then
            chat.AddText(C.acc, "[Хаб] ", C.green, "Открыто: ", C.text, command)
            surface.PlaySound("buttons/button14.wav")
            return
        end

        -- Серверные команды запускаются защищённым протоколом, а не say.
        net.Start(NET_LAUNCH)
            net.WriteString(command)
        net.SendToServer()
        surface.PlaySound("buttons/button15.wav")
    end

    net.Receive(NET_LAUNCH_RESULT, function()
        local ok, message = net.ReadBool(), net.ReadString()
        notification.AddLegacy(message, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 3)
        surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
    end)

    local function buildMenu(sc)
        sc:Clear()
        local b1 = block(sc, 30 + #MENU_LINKS * 36 + 8, "Быстрый запуск админ-меню сборки:", C.yellow)
        for i, m in ipairs(MENU_LINKS) do
            local row = vgui.Create("DPanel", b1)
            row:SetPos(8, 26 + (i - 1) * 36) row:SetSize(math.max(930, sc:GetWide() - 16), 32)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(4, 0, 0, pw, ph, C.panel2)
                draw.SimpleText(m[1], "GRMHub_Sub", 8, ph / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(m[3], "GRMHub_Small", pw - 8, ph / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            local b = mkBtn(row, m[2], m[4] and C.panel or C.green, 200, 24)
            b:SetPos(430, 4)
            if not m[4] then
                local cmd = m[2]
                b.DoClick = function()
                    launchAdminCommand(cmd)
                end
            end
        end
    end

    -- ==== главное окно ====
    net.Receive(NET_OPEN, function()
        -- флаги доступа (находка 172): econAccess — не-суперадмин с правом
        -- управления экономикой (лидер Нацбанка и т.п.); isSuper — суперадмин
        local econAccess = net.ReadBool()
        local isSuper = net.ReadBool()
        HB._econOnly = (econAccess == true and isSuper ~= true)
        HB._isSuper = isSuper == true
        if isSuper and GRM.Admin and GRM.Admin.OpenPanel then
            GRM.Admin.OpenPanel()
            return
        end
        if IsValid(HB._frame) then HB._frame:Remove() end
        local f = vgui.Create("DFrame")
        HB._frame = f
        f:SetTitle("")
        local fw = math.Clamp(math.floor(ScrW() * 0.88), 1180, 1480)
        local fh = math.Clamp(math.floor(ScrH() * 0.86), 720, 920)
        f:SetSize(fw, fh)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 46, C.head, true, true, false, false)
            draw.SimpleText("GRM — Единая админ-панель", "GRMHub_Title", 14, 23, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("v" .. HB.Version .. " • /grm_admin", "GRMHub_Normal", pw - 52, 23, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMHub_Title") x:SetTextColor(color_white)
        x:SetPos(fw - 42, 8) x:SetSize(32, 30)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end

        local sheet = vgui.Create("DPropertySheet", f)
        sheet:Dock(FILL) sheet:DockMargin(10, 52, 10, 10)
        sheet.Paint = function(_, w, h)
            draw.RoundedBox(7, 0, 0, w, h, C.head)
        end

        local pages = {}
        local function mkPage(tab, label, icon)
            local p = vgui.Create("DPanel")
            p:SetPaintBackground(false)
            p:DockPadding(6, 6, 6, 6)
            local sc = vgui.Create("DScrollPanel", p)
            sc:Dock(FILL) sc:DockMargin(0, 0, 0, 34)
            local bRef = mkBtn(p, "Обновить", C.acc)
            bRef:Dock(BOTTOM) bRef:SetTall(28) bRef:SetFont("GRMHub_Sub")
            bRef.DoClick = function() askTab(tab) end
            pages[tab] = sc
            sheet:AddSheet(label, p, icon)
            return sc
        end

        if HB._econOnly then
            -- не-суперадмин с доступом к экономике: только вкладка «Экономика»
            mkPage("econ", "Экономика", "icon16/money.png")
        else
            mkPage("server", "Сервер", "icon16/server.png")
            mkPage("access", "Доступы", "icon16/key.png")
            mkPage("econ", "Экономика", "icon16/money.png")
            mkPage("tools", "Инструменты", "icon16/wrench.png")
            mkPage("jobs", "Биржа", "icon16/bricks.png")
            mkPage("players", "Игроки", "icon16/group.png")
            mkPage("menu", "Меню", "icon16/application_view_tile.png")
        end

        -- Единый тёмный стиль вкладок: стандартный серый DPropertySheet
        -- выбивается из GRM-дизайна и визуально сжимает рабочую область.
        for _, item in ipairs(sheet.Items or {}) do
            local tab = item.Tab
            if IsValid(tab) then
                tab:SetFont("GRMHub_Normal")
                tab:SetTextColor(C.dim)
                tab.Paint = function(self, w, h)
                    local active = self:IsActive()
                    draw.RoundedBoxEx(5, 0, 0, w, h, active and C.panel or C.panel2, true, true, false, false)
                    if active then draw.RoundedBox(0, 0, h - 3, w, 3, C.acc) end
                end
            end
        end

        HB._activeTab = "server"
        sheet.OnActiveTabChanged = function(_, _, newPnl)
            for tab, sc in pairs(pages) do
                if IsValid(sc) and sc:GetParent() == newPnl then HB._activeTab = tab askTab(tab) end
            end
        end

        net.Receive(NET_DATA, function()
            if not IsValid(f) then return end
            local tab = net.ReadString()
            local d = net.ReadTable() or {}
            local sc = pages[tab]
            if not IsValid(sc) then return end
            if tab == "server" then buildServer(sc, d)
            elseif tab == "access" then buildAccess(sc, d)
            elseif tab == "jobs" then buildJobs(sc, d)
            elseif tab == "econ" then buildEcon(sc, d)
            elseif tab == "tools" then buildTools(sc, d)
            elseif tab == "players" then buildPlayers(sc, d) end
        end)

        if HB._econOnly then
            timer.Simple(0.15, function() if IsValid(f) then askTab("econ") end end)
        else
            buildMenu(pages["menu"])
            timer.Simple(0.15, function() if IsValid(f) then askTab("server") end end)
        end
    end)

    -- Окно настройки доступа к экономике (находка 172)
    net.Receive("GRM_EcoAccess_Data", function()
        local access = net.ReadTable() or {}
        if not (HB._isSuper == true) then return end
        local w = vgui.Create("DFrame")
        GRM.UI.Track("econ_access", w)
        w:SetTitle(""); w:SetSize(860, 620); w:Center(); w:MakePopup(); w:ShowCloseButton(false)
        w.Paint = function(self, pw, ph)
            draw.RoundedBox(9, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(9, 0, 0, pw, 52, C.head, true, true, false, false)
            draw.SimpleText("ДОСТУП К ЭКОНОМИКЕ", "GRMHub_Title", 16, 26, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("выдача полномочий фракциям (Нацбанк и др.)", "GRMHub_Small", pw - 16, 26, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local close = vgui.Create("DButton", w)
        close:SetPos(w:GetWide() - 40, 12); close:SetSize(28, 28); close:SetText("X"); close:SetTextColor(C.text)
        close.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or C.panel2) end
        close.DoClick = function() w:Close() end

        local list = vgui.Create("DScrollPanel", w)
        list:SetPos(12, 62); list:SetSize(836, 500)

        -- спросить сервер: список фракций и их ролей/отделов (из econ-данных хаба)
        local factionRows = {}
        -- заполним из последнего payload (askTab("econ") уже был вызван)
        if HB._lastEconPayload and HB._lastEconPayload.factions then
            for _, f in ipairs(HB._lastEconPayload.factions) do
                local acc = access[f.name] or { enabled = false, roles = {}, departments = {} }
                local row = vgui.Create("DPanel", list)
                row:Dock(TOP); row:SetTall(110); row:DockMargin(0, 0, 0, 8)
                row.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, C.panel) end
                local en = vgui.Create("DCheckBoxLabel", row)
                en:SetPos(12, 8); en:SetSize(280, 24); en:SetText("Выдать доступ фракции «" .. f.name .. "»"); en:SetTextColor(C.text); en:SetFont("GRMHub_Normal")
                en:SetValue(acc.enabled == true and 1 or 0)
                en.roleList = acc.roles or {}; en.deptList = acc.departments or {}
                local roleCombo = vgui.Create("DComboBox", row)
                roleCombo:SetPos(320, 8); roleCombo:SetSize(240, 26)
                local deptCombo = vgui.Create("DComboBox", row)
                deptCombo:SetPos(320, 40); deptCombo:SetSize(240, 26)
                -- чекбоксы ролей/отделов (мультивыбор через меню не сделать просто — используем список с переключателями)
                local roleScroll = vgui.Create("DScrollPanel", row)
                roleScroll:SetPos(580, 6); roleScroll:SetSize(120, 96)
                local deptScroll = vgui.Create("DScrollPanel", row)
                deptScroll:SetPos(708, 6); deptScroll:SetSize(120, 96)
                local roleChecks, deptChecks = {}, {}
                for _, r in ipairs(f.roles or {}) do
                    local c = vgui.Create("DCheckBoxLabel", roleScroll)
                    c:Dock(TOP); c:SetTall(20); c:SetText(r); c:SetTextColor(C.text); c:SetFont("GRMHub_Small")
                    c:SetValue((en.roleList or {})[r] == true and 1 or 0)
                    roleChecks[r] = c
                end
                for _, dd in ipairs(f.departments or {}) do
                    local c = vgui.Create("DCheckBoxLabel", deptScroll)
                    c:Dock(TOP); c:SetTall(20); c:SetText(dd); c:SetTextColor(C.text); c:SetFont("GRMHub_Small")
                    c:SetValue((en.deptList or {})[dd] == true and 1 or 0)
                    deptChecks[dd] = c
                end
                local save = mkBtn(row, "Сохранить", C.green, 100, 28)
                save:SetPos(12, 70)
                save.DoClick = function()
                    local rolesOut, deptsOut = {}, {}
                    for r, c in pairs(roleChecks) do if c:GetChecked() then rolesOut[r] = true end end
                    for dd, c in pairs(deptChecks) do if c:GetChecked() then deptsOut[dd] = true end end
                    net.Start("GRM_EcoAccess_Save")
                        net.WriteString(f.name)
                        net.WriteBool(en:GetChecked())
                        net.WriteTable(rolesOut)
                        net.WriteTable(deptsOut)
                    net.SendToServer()
                end
                local hint = vgui.Create("DLabel", row)
                hint:SetPos(320, 72); hint:SetSize(400, 30); hint:SetText("Роли приоритетны: если выбраны — доступ только по ним; иначе по отделам; если ничего — вся фракция."); hint:SetFont("GRMHub_Small"); hint:SetTextColor(C.dim); hint:SetWrap(true)
            end
        else
            local l = vgui.Create("DLabel", list)
            l:Dock(TOP); l:SetTall(40); l:SetText("Нет данных фракций — обновите вкладку «Экономика»."); l:SetFont("GRMHub_Normal"); l:SetTextColor(C.dim)
        end
        w:MakePopup()
    end)

    -- запоминаем payload экономики для окна доступа
    local _origEconBuild = buildEcon
    buildEcon = function(sc, d)
        HB._lastEconPayload = d
        _origEconBuild(sc, d)
    end

    HB.AskTab = askTab
    HB.MenuLinks = MENU_LINKS
    HB.Launch = launchAdminCommand

    print("[GRM Hub] Клиент единой админ-панели v" .. HB.Version .. " загружен")
end
