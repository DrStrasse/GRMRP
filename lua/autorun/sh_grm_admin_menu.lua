--[[--------------------------------------------------------------------

    GRM Admin Menu v1.1 — Суперадмин меню экономики

    Открыть: !grmmenu в чате / grm_adminmenu в консоли (только superadmin)

    Вкладки:
      Обзор      — общая статистика, топ балансов, бюджеты фракций
      Игроки     — выдать/снять/установить баланс, персональный налог
      Фракции    — бюджеты, налоги, выплаты, пополнение/вывод
      Переводы   — перевод между игроком/фракцией
      Журнал     — последние 50 действий администраторов

    ИСПРАВЛЕНИЯ v1.1:
      - Убраны цепочки :SetPos():SetSize() — SetPos() возвращает nil в GMod,
        что вызывало "attempt to index a nil value" при переключении вкладок
      - Добавлена вспомогательная функция mkBtn(parent,label,col,cb,x,y,w,h)
      - Исправлены отрицательные/>255 значения цветов в Paint через math.Clamp
      - IsDown() вместо устаревшего IsDepressed()

--------------------------------------------------------------------]]

GRM = GRM or {}

-- ================================================================
--  КОНФИГ ДОСТУПА
--  "superadmin" — только superadmin (стандартно)
--  "admin"      — любой admin+ (если IsSuperAdmin не работает)
--  Можно также добавить SteamID64 в таблицу GRM.AdminWhitelist ниже
-- ================================================================

GRM.AdminAccessLevel = "superadmin"   -- "superadmin" | "admin"

GRM.AdminWhitelist   = {
    -- ["76561198000000000"] = true,   -- добавь свой SteamID64 сюда если нужно
}

local function hasAdminAccess(ply)
    if not IsValid(ply) then return false end
    if GRM.AdminWhitelist[ply:SteamID64()] then return true end
    if GRM.AdminAccessLevel == "admin" then
        return ply:IsAdmin()
    end
    return ply:IsSuperAdmin()
end

-- ================================================================
--  ОБЩЕЕ: сетевые строки
-- ================================================================

if SERVER then
    util.AddNetworkString("grm_admin_request")
    util.AddNetworkString("grm_admin_data")
    util.AddNetworkString("grm_admin_action")
    util.AddNetworkString("grm_admin_result")
    util.AddNetworkString("grm_admin_open")
end

-- ================================================================
--  СЕРВЕРНАЯ ЧАСТЬ
-- ================================================================

if SERVER then

    local LOG_FILE    = "grm_admin_log.json"
    local PTAX_FILE   = "grm_player_taxes.json"
    local adminLog    = {}        -- кольцевой буфер 50 записей
    local playerTaxes = {}        -- [SteamID64] = number (0–0.5), переопределяет налог фракции

    -- ── Загрузка / сохранение журнала ────────────────────────

    local function loadLog()
        if not file.Exists(LOG_FILE, "DATA") then return end
        local ok, t = pcall(util.JSONToTable, file.Read(LOG_FILE, "DATA") or "")
        if ok and istable(t) then adminLog = t end
    end

    local function saveLog()
        local ok, enc = pcall(util.TableToJSON, adminLog, true)
        if ok then file.Write(LOG_FILE, enc) end
    end

    local function addLog(adminNick, action)
        table.insert(adminLog, { t = os.time(), admin = adminNick, action = action })
        while #adminLog > 50 do table.remove(adminLog, 1) end
        saveLog()
    end

    -- ── Загрузка / сохранение персональных налогов ───────────

    local function loadPTax()
        if not file.Exists(PTAX_FILE, "DATA") then return end
        local ok, t = pcall(util.JSONToTable, file.Read(PTAX_FILE, "DATA") or "")
        if ok and istable(t) then playerTaxes = t end
    end

    local function savePTax()
        local ok, enc = pcall(util.TableToJSON, playerTaxes, true)
        if ok then file.Write(PTAX_FILE, enc) end
    end

    loadLog()
    loadPTax()

    -- ── Публичный геттер персонального налога ─────────────────

    function GRM.GetPlayerTaxRate(ply)
        if not IsValid(ply) then return nil end
        return playerTaxes[ply:SteamID64()]
    end

    -- ── Вспомогательные ──────────────────────────────────────

    local function guard(ply)
        if not hasAdminAccess(ply) then
            net.Start("grm_admin_result")
                net.WriteBool(false)
                net.WriteString("Нет прав доступа")
            net.Send(ply)
            return false
        end
        return true
    end

    local function ok(ply, msg)
        net.Start("grm_admin_result")
            net.WriteBool(true)
            net.WriteString(msg or "Выполнено")
        net.Send(ply)
    end

    local function fail(ply, msg)
        net.Start("grm_admin_result")
            net.WriteBool(false)
            net.WriteString(msg or "Ошибка")
        net.Send(ply)
    end

    local function findBySID64(sid64)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if p:SteamID64() == sid64 then return p end
        end
        return nil
    end

    local function getPlayerFaction(ply)
        if not Factions then return nil end
        local sid = ply:SteamID()
        for name, f in pairs(Factions) do
            if istable(f) and istable(f.Members) and f.Members[sid] then
                return name, f
            end
        end
        return nil
    end

    -- ── Сборка пакета данных ──────────────────────────────────

    local function buildData()
        local players = {}
        local total   = 0

        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                local bal     = GRM.GetBalance(p)
                local fName   = getPlayerFaction(p)
                local ptax    = playerTaxes[p:SteamID64()]
                total         = total + bal
                table.insert(players, {
                    nick    = p:Nick(),
                    sid64   = p:SteamID64(),
                    balance = bal,
                    faction = fName or "",
                    ptax    = ptax,   -- nil = не задан
                })
            end
        end

        -- Сортировка по балансу (убывание)
        table.sort(players, function(a, b) return a.balance > b.balance end)

        local factions = {}
        if Factions then
            for name, f in pairs(Factions) do
                if istable(f) then
                    local online = 0
                    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                        if IsValid(p) and getPlayerFaction(p) == name then
                            online = online + 1
                        end
                    end
                    local totalMembers = table.Count(f.Members or {})
                    factions[name] = {
                        online  = online,
                        total   = totalMembers,
                        budget  = (GRM.FactionBudgetGet and GRM.FactionBudgetGet(name)) or 0,
                        taxRate = (GRM.FactionTaxGet and GRM.FactionTaxGet(name)) or 0,
                        leader  = f.Leader or "",
                    }
                end
            end
        end

        local fTotal = 0
        for _, fd in pairs(factions) do fTotal = fTotal + (fd.budget or 0) end

        return {
            playerCount  = #players,
            factionCount = table.Count(factions),
            circulation  = total,
            fTotal       = fTotal,
            grandTotal   = total + fTotal,
            players      = players,
            factions     = factions,
            log          = adminLog,
        }
    end

    -- ── Запрос данных ─────────────────────────────────────────

    net.Receive("grm_admin_request", function(_, ply)
        if not guard(ply) then return end
        -- GRM-FIX: pcall вокруг buildData — раньше любая ошибка сборки
        -- молча оставляла клиент с вечно пустым списком игроков.
        local okData, pack = pcall(buildData)
        if not okData then
            ErrorNoHalt("[GRM Admin] buildData error: " .. tostring(pack) .. "\n")
            fail(ply, "Ошибка сборки данных: " .. tostring(pack))
            return
        end
        net.Start("grm_admin_data")
            net.WriteTable(pack)
        net.Send(ply)
    end)

    -- ── Выполнение действия ───────────────────────────────────

    net.Receive("grm_admin_action", function(_, ply)
        if not guard(ply) then return end

        local a = net.ReadTable()
        if not a or not a.type then fail(ply, "Пустое действие"); return end

        local atype = a.type

        -- ── Игрок: выдать ────────────────────────────────────

        if atype == "give_player" then
            local target = findBySID64(a.sid64)
            local amount = math.floor(tonumber(a.amount) or 0)
            if not IsValid(target) then fail(ply, "Игрок не в сети"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            GRM.GiveMoney(target, amount)
            GRM.Notify(target, "[Админ] " .. ply:Nick() .. " выдал вам " .. GRM.Format(amount), 100, 220, 255)
            addLog(ply:Nick(), "GIVE " .. target:Nick() .. " +" .. GRM.Format(amount))
            ok(ply, "Выдано " .. GRM.Format(amount) .. " → " .. target:Nick())

        -- ── Игрок: снять ─────────────────────────────────────

        elseif atype == "take_player" then
            local target = findBySID64(a.sid64)
            local amount = math.floor(tonumber(a.amount) or 0)
            if not IsValid(target) then fail(ply, "Игрок не в сети"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            GRM.TakeMoney(target, amount)
            GRM.Notify(target, "[Админ] " .. ply:Nick() .. " снял у вас " .. GRM.Format(amount), 255, 120, 80)
            addLog(ply:Nick(), "TAKE " .. target:Nick() .. " -" .. GRM.Format(amount))
            ok(ply, "Снято " .. GRM.Format(amount) .. " у " .. target:Nick())

        -- ── Игрок: установить баланс ──────────────────────────

        elseif atype == "set_player" then
            local target = findBySID64(a.sid64)
            local amount = math.max(0, math.floor(tonumber(a.amount) or 0))
            if not IsValid(target) then fail(ply, "Игрок не в сети"); return end
            GRM.SetBalance(target, amount)
            GRM.Notify(target, "[Админ] Ваш баланс установлен: " .. GRM.Format(amount), 100, 220, 255)
            addLog(ply:Nick(), "SET " .. target:Nick() .. " = " .. GRM.Format(amount))
            ok(ply, "Баланс " .. target:Nick() .. " → " .. GRM.Format(amount))

        -- ── Игрок: обнулить ───────────────────────────────────

        elseif atype == "reset_player" then
            local target = findBySID64(a.sid64)
            if not IsValid(target) then fail(ply, "Игрок не в сети"); return end
            GRM.SetBalance(target, GRM.StartBalance or 1000)
            GRM.Notify(target, "[Админ] Ваш баланс сброшен до начального значения", 255, 220, 80)
            addLog(ply:Nick(), "RESET " .. target:Nick())
            ok(ply, "Баланс " .. target:Nick() .. " сброшен")

        -- ── Игрок: персональный налог ─────────────────────────

        elseif atype == "set_player_tax" then
            local target = findBySID64(a.sid64)
            local pct    = math.Clamp(math.floor(tonumber(a.rate) or 0), 0, 50)
            if not IsValid(target) then fail(ply, "Игрок не в сети"); return end
            if a.clear then
                playerTaxes[target:SteamID64()] = nil
                savePTax()
                GRM.Notify(target, "[Админ] Ваш персональный налог сброшен (фракционный)", 100, 220, 255)
                addLog(ply:Nick(), "PTAX_CLEAR " .. target:Nick())
                ok(ply, "Персональный налог " .. target:Nick() .. " сброшен")
            else
                playerTaxes[target:SteamID64()] = pct / 100
                savePTax()
                GRM.Notify(target, "[Админ] Ваш персональный налог установлен: " .. pct .. "%", 255, 200, 80)
                addLog(ply:Nick(), "PTAX " .. target:Nick() .. " = " .. pct .. "%")
                ok(ply, "Налог " .. target:Nick() .. " → " .. pct .. "%")
            end

        -- ── Фракция: пополнить бюджет ─────────────────────────

        elseif atype == "give_faction" then
            local fname  = a.faction
            local amount = math.floor(tonumber(a.amount) or 0)
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            if GRM.FactionBudgetAdd then
                GRM.FactionBudgetAdd(fname, amount)
            end
            addLog(ply:Nick(), "FACTION_GIVE [" .. fname .. "] +" .. GRM.Format(amount))
            ok(ply, "Пополнен бюджет [" .. fname .. "]: +" .. GRM.Format(amount))

        -- ── Фракция: снять с бюджета ──────────────────────────

        elseif atype == "take_faction" then
            local fname  = a.faction
            local amount = math.floor(tonumber(a.amount) or 0)
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            local cur = (GRM.FactionBudgetGet and GRM.FactionBudgetGet(fname)) or 0
            if cur < amount then fail(ply, "В бюджете только " .. GRM.Format(cur)); return end
            if GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fname, -amount) end
            addLog(ply:Nick(), "FACTION_TAKE [" .. fname .. "] -" .. GRM.Format(amount))
            ok(ply, "Снято с бюджета [" .. fname .. "]: -" .. GRM.Format(amount))

        -- ── Фракция: налог ────────────────────────────────────

        elseif atype == "set_faction_tax" then
            local fname = a.faction
            local pct   = math.Clamp(math.floor(tonumber(a.rate) or 0), 0, 50)
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if GRM.FactionTaxSet then GRM.FactionTaxSet(fname, pct / 100) end
            addLog(ply:Nick(), "FACTION_TAX [" .. fname .. "] = " .. pct .. "%")
            ok(ply, "Налог [" .. fname .. "] → " .. pct .. "%")

        -- ── Фракция: выплатить всем онлайн-участникам ─────────

        elseif atype == "faction_payall" then
            local fname  = a.faction
            local amount = math.floor(tonumber(a.amount) or 0)
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end

            local members, total = {}, 0
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and getPlayerFaction(p) == fname then
                    table.insert(members, p); total = total + amount
                end
            end
            if #members == 0 then fail(ply, "Нет онлайн участников"); return end

            local cur = (GRM.FactionBudgetGet and GRM.FactionBudgetGet(fname)) or 0
            if cur < total then
                fail(ply, "В бюджете " .. GRM.Format(cur) .. ", нужно " .. GRM.Format(total)); return
            end

            if GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fname, -total) end
            for _, p in ipairs(members) do
                GRM.GiveMoney(p, amount)
                GRM.Notify(p, "[Фракция] Зарплата от [" .. fname .. "]: " .. GRM.Format(amount), 100, 220, 255)
            end

            addLog(ply:Nick(), "FACTION_PAYALL [" .. fname .. "] " .. GRM.Format(amount) .. " x" .. #members)
            ok(ply, "Выплачено " .. #members .. " участникам")

        -- ── Перевод: игрок → игрок ────────────────────────────

        elseif atype == "transfer_pp" then
            local src    = findBySID64(a.from)
            local dst    = findBySID64(a.to)
            local amount = math.floor(tonumber(a.amount) or 0)
            if not IsValid(src) then fail(ply, "Отправитель не в сети"); return end
            if not IsValid(dst) then fail(ply, "Получатель не в сети"); return end
            if src == dst then fail(ply, "Отправитель и получатель одинаковы"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            if not GRM.HasMoney(src, amount) then
                fail(ply, "У " .. src:Nick() .. " только " .. GRM.Format(GRM.GetBalance(src))); return
            end
            GRM.TakeMoney(src, amount)
            GRM.GiveMoney(dst, amount)
            GRM.Notify(src, "[Админ] Переведено " .. GRM.Format(amount) .. " → " .. dst:Nick(), 255, 180, 80)
            GRM.Notify(dst, "[Админ] Получено " .. GRM.Format(amount) .. " от " .. src:Nick(), 100, 220, 100)
            addLog(ply:Nick(), "TRANSFER " .. src:Nick() .. " → " .. dst:Nick() .. " " .. GRM.Format(amount))
            ok(ply, "Переведено " .. GRM.Format(amount) .. ": " .. src:Nick() .. " → " .. dst:Nick())

        -- ── Перевод: игрок → фракция ──────────────────────────

        elseif atype == "transfer_pf" then
            local src    = findBySID64(a.from)
            local fname  = a.to
            local amount = math.floor(tonumber(a.amount) or 0)
            if not IsValid(src) then fail(ply, "Игрок не в сети"); return end
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            if not GRM.HasMoney(src, amount) then
                fail(ply, "У " .. src:Nick() .. " только " .. GRM.Format(GRM.GetBalance(src))); return
            end
            GRM.TakeMoney(src, amount)
            if GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fname, amount) end
            GRM.Notify(src, "[Админ] " .. GRM.Format(amount) .. " переведено в бюджет [" .. fname .. "]", 255, 180, 80)
            addLog(ply:Nick(), "TRANSFER " .. src:Nick() .. " → [" .. fname .. "] " .. GRM.Format(amount))
            ok(ply, "Переведено")

        -- ── Перевод: фракция → игрок ──────────────────────────

        elseif atype == "transfer_fp" then
            local fname  = a.from
            local dst    = findBySID64(a.to)
            local amount = math.floor(tonumber(a.amount) or 0)
            if not Factions or not Factions[fname] then fail(ply, "Фракция не найдена"); return end
            if not IsValid(dst) then fail(ply, "Игрок не в сети"); return end
            if amount <= 0 then fail(ply, "Сумма должна быть > 0"); return end
            local cur = (GRM.FactionBudgetGet and GRM.FactionBudgetGet(fname)) or 0
            if cur < amount then fail(ply, "В бюджете только " .. GRM.Format(cur)); return end
            if GRM.FactionBudgetAdd then GRM.FactionBudgetAdd(fname, -amount) end
            GRM.GiveMoney(dst, amount)
            GRM.Notify(dst, "[Админ] Получено " .. GRM.Format(amount) .. " из бюджета [" .. fname .. "]", 100, 220, 100)
            addLog(ply:Nick(), "TRANSFER [" .. fname .. "] → " .. dst:Nick() .. " " .. GRM.Format(amount))
            ok(ply, "Переведено")

        else
            fail(ply, "Неизвестное действие: " .. tostring(atype))
        end
    end)

    -- ── Чат-команда для открытия меню ────────────────────────

    hook.Add("PlayerSay", "GRM_AdminMenuCmd", function(ply, text)
        local cmd = text:Trim():lower()
        if cmd == "!grmmenu" or cmd == "!grmadmin" or cmd == "!econadmin" or cmd == "/econadmin" then
            if not hasAdminAccess(ply) then
                GRM.Notify(ply, "Нет прав доступа к GRM Admin Menu", 255, 100, 100)
            else
                net.Start("grm_admin_open")
                net.Send(ply)
            end
            return ""
        end
    end)

    -- ── Конкоманда для открытия меню ─────────────────────────

    concommand.Add("grm_adminmenu", function(ply)
        if not hasAdminAccess(ply) then return end
        net.Start("grm_admin_open")
        net.Send(ply)
    end)

    -- GRM-FIX: короткий алиас econadmin → то же меню, тот же guard.
    concommand.Add("econadmin", function(ply)
        if not hasAdminAccess(ply) then return end
        net.Start("grm_admin_open")
        net.Send(ply)
    end)

    -- ── Публичные API для grm_economy_factions ────────────────

    GRM.FactionBudgetGet = GRM.FactionBudgetGet or function(name) return 0 end
    GRM.FactionBudgetAdd = GRM.FactionBudgetAdd or function(name, delta) end
    GRM.FactionTaxGet    = GRM.FactionTaxGet    or function(name) return 0.05 end
    GRM.FactionTaxSet    = GRM.FactionTaxSet    or function(name, rate) end

    print("[GRM] Admin Menu v1.1 — сервер загружен")

end

-- ================================================================
--  КЛИЕНТСКАЯ ЧАСТЬ
-- ================================================================

if CLIENT then

    -- ── Шрифты ───────────────────────────────────────────────

    surface.CreateFont("GRM_Admin_Title",  { font = "Roboto", size = 18, weight = 700 })
    surface.CreateFont("GRM_Admin_Head",   { font = "Roboto", size = 14, weight = 700 })
    surface.CreateFont("GRM_Admin_Body",   { font = "Roboto", size = 13, weight = 400 })
    surface.CreateFont("GRM_Admin_Small",  { font = "Roboto", size = 11, weight = 400 })
    surface.CreateFont("GRM_Admin_Stat",   { font = "Roboto", size = 22, weight = 700 })

    -- ── Цвета ────────────────────────────────────────────────

    local COL_BG      = Color(18,  20,  28,  252)
    local COL_PANEL   = Color(26,  29,  40,  255)
    local COL_DARK    = Color(14,  16,  22,  255)
    local COL_BORDER  = Color(45,  50,  70,  255)
    local COL_GREEN   = Color(60,  190, 90)
    local COL_RED     = Color(210, 70,  60)
    local COL_BLUE    = Color(70,  140, 220)
    local COL_GOLD    = Color(220, 180, 50)
    local COL_GREY    = Color(130, 135, 150)
    local COL_WHITE   = Color(220, 224, 235)
    local COL_TAB_ACT = Color(55,  130, 220)

    local _data    = nil   -- последний пакет с сервера
    local _frame   = nil
    local _selPly  = nil   -- выбранный SteamID64 в вкладке Игроки
    local _selFac  = nil   -- выбранная фракция

    -- ── Хелперы UI ───────────────────────────────────────────

    --[[ Заглушка: если vgui.Create вернул nil — цепочка методов не падает.
         Форвард-декларация обязательна: внутри __index имя _nullPanel
         должно ссылаться на ЭТУ переменную. Пока объявление и присвоение
         стояли одной строкой, тело замыкания компилировалось до появления
         локала и читало глобал nil — заглушка возвращала nil, и первая же
         цепочка btn:SetText():SetPos() всё равно падала, то есть защита не
         работала вовсе. ]]
    local _nullPanel
    _nullPanel = setmetatable({}, {
        __index = function() return function() return _nullPanel end end
    })

    -- ── makeBtn: создаёт кнопку с кастомным Paint ─────────────
    -- ВНИМАНИЕ: НЕ возвращает self из SetPos/SetSize (GMod ограничение),
    -- поэтому для позиционирования используй mkBtn() ниже.

    local function makeBtn(parent, label, col, callback)
        local btn = vgui.Create("DButton", parent)
        if not IsValid(btn) then return _nullPanel end
        btn:SetText(label)
        btn:SetFont("GRM_Admin_Body")
        btn:SetTextColor(COL_WHITE)
        btn.Paint = function(s, w, h)
            local c
            if s:IsDown() then
                -- FIX: math.Clamp предотвращает выход за пределы 0-255
                c = Color(
                    math.Clamp(col.r - 20, 0, 255),
                    math.Clamp(col.g - 20, 0, 255),
                    math.Clamp(col.b - 20, 0, 255)
                )
            elseif s:IsHovered() then
                c = Color(
                    math.Clamp(col.r + 30, 0, 255),
                    math.Clamp(col.g + 30, 0, 255),
                    math.Clamp(col.b + 30, 0, 255)
                )
            else
                c = col
            end
            draw.RoundedBox(5, 0, 0, w, h, c)
        end
        btn.DoClick = callback
        return btn
    end

    -- ── mkBtn: создаёт кнопку И сразу устанавливает позицию/размер ──
    -- FIX: В GMod Panel:SetPos() возвращает nil, поэтому цепочка
    -- makeBtn(...):SetPos():SetSize() вызывала "attempt to index a nil value".
    -- Эта функция решает проблему — выставляем позицию внутри.

    local function mkBtn(parent, label, col, callback, x, y, w, h)
        local btn = makeBtn(parent, label, col, callback)
        if IsValid(btn) then
            btn:SetPos(x, y)
            btn:SetSize(w, h)
        end
        return btn
    end

    local function makeEntry(parent, placeholder, numeric)
        local e = vgui.Create("DTextEntry", parent)
        if not IsValid(e) then return _nullPanel end
        e:SetFont("GRM_Admin_Body")
        e:SetPlaceholderText(placeholder or "")
        e:SetNumeric(numeric or false)
        e:SetTextColor(COL_WHITE)
        e.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
            surface.SetDrawColor(COL_BORDER)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            s:DrawTextEntryText(COL_WHITE, Color(70,140,220,150), COL_WHITE)
        end
        return e
    end

    local function makeLabel(parent, text, font, col)
        local l = vgui.Create("DLabel", parent)
        if not IsValid(l) then return _nullPanel end
        l:SetText(text or "")
        l:SetFont(font or "GRM_Admin_Body")
        l:SetTextColor(col or COL_WHITE)
        l:SizeToContents()
        return l
    end

    local function statCard(parent, x, y, w, h, title, value, col)
        local p = vgui.Create("DPanel", parent)
        p:SetPos(x, y); p:SetSize(w, h)
        p.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, COL_PANEL)
            surface.SetDrawColor(col or COL_BLUE)
            surface.DrawRect(0, ph - 3, pw, 3)
        end

        local lbl = vgui.Create("DLabel", p)
        lbl:SetPos(10, 8); lbl:SetSize(w-20, 16)
        lbl:SetText(title); lbl:SetFont("GRM_Admin_Small"); lbl:SetTextColor(COL_GREY)

        local val = vgui.Create("DLabel", p)
        val:SetPos(10, 26); val:SetSize(w-20, 28)
        val:SetText(value); val:SetFont("GRM_Admin_Stat"); val:SetTextColor(col or COL_WHITE)

        return p
    end

    -- ── Сеть ─────────────────────────────────────────────────

    local function requestData()
        net.Start("grm_admin_request")
        net.SendToServer()
    end

    local function sendAction(tbl)
        net.Start("grm_admin_action")
            net.WriteTable(tbl)
        net.SendToServer()
    end

    net.Receive("grm_admin_result", function()
        local success = net.ReadBool()
        local msg     = net.ReadString()

        if IsValid(_frame) then
            if _frame._notify then _frame._notify:Remove() end
            local nw = 340
            local n  = vgui.Create("DPanel", _frame)
            n:SetSize(nw, 36)
            n:SetPos((_frame:GetWide() - nw) / 2, _frame:GetTall() - 56)
            n.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h,
                    success and Color(40,140,60,240) or Color(160,40,40,240))
            end

            local lbl = vgui.Create("DLabel", n)
            lbl:SetPos(12, 0); lbl:SetSize(nw-24, 36)
            lbl:SetText((success and "✔ " or "✖ ") .. msg)
            lbl:SetFont("GRM_Admin_Body"); lbl:SetTextColor(COL_WHITE)

            _frame._notify = n
            timer.Simple(3, function() if IsValid(n) then n:Remove() end end)
            -- GRM-FIX: авто-рефреш только при УСПЕХЕ. Раньше requestData
            -- слался и на отказ доступа → бесконечный цикл уведомлений
            -- «Нет прав доступа» каждые 0.3с и вечно пустой список.
            if success then timer.Simple(0.3, requestData) end
        end
    end)

    net.Receive("grm_admin_data", function()
        _data = net.ReadTable()
        if IsValid(_frame) and _frame._refresh then
            _frame._refresh()
        end
    end)

    net.Receive("grm_admin_open", function()
        GRM.OpenAdminMenu()
    end)

    -- ── Быстрые суммы ─────────────────────────────────────────

    local QUICK = {100, 500, 1000, 5000, 10000, 50000}

    local function quickRow(parent, entry, y, btnW)
        for i, amt in ipairs(QUICK) do
            local qb = vgui.Create("DButton", parent)
            qb:SetPos(12 + (i-1)*(btnW+4), y)
            qb:SetSize(btnW, 22)
            qb:SetText(tostring(amt))
            qb:SetFont("GRM_Admin_Small")
            qb:SetTextColor(COL_WHITE)
            qb.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h,
                    s:IsHovered() and Color(50,60,90) or Color(35,40,60))
            end
            qb.DoClick = function()
                if IsValid(entry) then entry:SetValue(tostring(amt)) end
            end
        end
    end

    -- ================================================================
    --  ВКЛ. 1: ОБЗОР
    -- ================================================================

    local function buildOverview(sheet)
        local p = sheet
        p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BG) end

        local function refresh()
            p:Clear()
            if not _data then
                makeLabel(p, "Загрузка...", "GRM_Admin_Head", COL_GREY):SetPos(20, 20)
                return
            end

            local d = _data
            local cw = (p:GetWide() - 48) / 4

            statCard(p, 12,      10, cw, 68, "ИГРОКОВ ОНЛАЙН",  tostring(d.playerCount),  COL_BLUE)
            statCard(p, 16+cw,   10, cw, 68, "ФРАКЦИЙ",          tostring(d.factionCount), COL_GOLD)
            statCard(p, 20+cw*2, 10, cw, 68, "ДЕНЬГИ ИГРОКОВ",   GRM.Format(d.circulation), COL_GREEN)
            statCard(p, 24+cw*3, 10, cw, 68, "В БЮДЖЕТАХ",       GRM.Format(d.fTotal),      COL_RED)

            -- Широкая карточка: Общий оборот
            local full = vgui.Create("DPanel", p)
            full:SetPos(12, 88); full:SetSize(p:GetWide() - 24, 44)
            full.Paint = function(_, w, h)
                draw.RoundedBox(7, 0, 0, w, h, COL_PANEL)
                draw.SimpleText("ОБЩИЙ ОБОРОТ В ЭКОНОМИКЕ:", "GRM_Admin_Head", 14, 13, COL_GREY)
                draw.SimpleText(GRM.Format(d.grandTotal), "GRM_Admin_Stat", w - 14, 10, COL_WHITE, TEXT_ALIGN_RIGHT)
            end

            -- Список фракций
            makeLabel(p, "Бюджеты фракций", "GRM_Admin_Head", COL_GREY):SetPos(12, 144)

            local scroll = vgui.Create("DScrollPanel", p)
            scroll:SetPos(12, 164); scroll:SetSize(p:GetWide() - 24, p:GetTall() - 172)
            scroll.Paint = function() end

            local fNames = {}
            for n in pairs(d.factions or {}) do table.insert(fNames, n) end
            table.sort(fNames)

            for _, fname in ipairs(fNames) do
                local fd = d.factions[fname]
                local row = vgui.Create("DPanel", scroll)
                row:SetSize(scroll:GetWide(), 46)
                row:Dock(TOP); row:DockMargin(0, 0, 0, 4)
                row.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, COL_PANEL)
                    draw.SimpleText("[" .. fname .. "]", "GRM_Admin_Head", 12, 7, COL_GOLD)
                    draw.SimpleText(
                        fd.online .. "/" .. fd.total .. " онлайн",
                        "GRM_Admin_Small", 12, 27, COL_GREY)
                    draw.SimpleText("Бюджет: " .. GRM.Format(fd.budget), "GRM_Admin_Body",
                        w/2, 7, COL_GREEN)
                    draw.SimpleText(
                        "Налог: " .. math.floor((fd.taxRate or 0)*100) .. "%",
                        "GRM_Admin_Body", w/2, 27, COL_GOLD)
                end
            end

            if table.Count(d.factions or {}) == 0 then
                makeLabel(scroll, "Нет фракций", "GRM_Admin_Body", COL_GREY):SetPos(0, 4)
            end
        end

        p._refresh = refresh
        p._tab     = "overview"

        refresh()
        return p
    end

    -- ================================================================
    --  ВКЛ. 2: ИГРОКИ
    -- ================================================================

    local function buildPlayers(sheet)
        local p = sheet
        p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BG) end

        local listW = 260
        local list  = vgui.Create("DListView", p)
        list:SetPos(12, 10); list:SetSize(listW, p:GetTall() - 20)
        list:AddColumn("Игрок"):SetWidth(140)
        list:AddColumn("Баланс"):SetWidth(90)
        list:AddColumn("Нал."):SetWidth(36)
        list.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, COL_DARK) end

        -- Правая панель
        local rp = vgui.Create("DPanel", p)
        rp:SetPos(listW + 20, 10)
        rp:SetSize(p:GetWide() - listW - 32, p:GetTall() - 20)
        rp.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, COL_PANEL) end

        local rw = rp:GetWide()

        local infoLbl = vgui.Create("DLabel", rp)
        infoLbl:SetPos(12, 10); infoLbl:SetSize(rw - 24, 48)
        infoLbl:SetFont("GRM_Admin_Body"); infoLbl:SetTextColor(COL_GREY)
        infoLbl:SetText("Выберите игрока из списка")
        infoLbl:SetWrap(true)

        local yOff = 68

        -- Поле суммы
        makeLabel(rp, "Сумма:", "GRM_Admin_Small", COL_GREY):SetPos(12, yOff)
        local amtEntry = makeEntry(rp, "Введите сумму...", true)
        amtEntry:SetPos(12, yOff + 16); amtEntry:SetSize(rw - 24, 28)

        -- Быстрые суммы
        local qbW = math.floor((rw - 24 - 5*4) / 6)
        quickRow(rp, amtEntry, yOff + 50, qbW)

        local function doAction(atype)
            if not _selPly then return end
            local amt = math.floor(tonumber(amtEntry:GetValue()) or 0)
            sendAction({ type = atype, sid64 = _selPly, amount = amt })
        end

        local btnY = yOff + 78
        local btnH = 30
        local bw   = (rw - 24 - 8) / 3

        -- FIX: используем mkBtn вместо makeBtn():SetPos():SetSize()
        -- SetPos() в GMod возвращает nil, поэтому цепочка вызывала краш
        mkBtn(rp, "✚ Выдать",    COL_GREEN, function() doAction("give_player") end, 12,      btnY, bw, btnH)
        mkBtn(rp, "✖ Снять",     COL_RED,   function() doAction("take_player") end, 16+bw,   btnY, bw, btnH)
        mkBtn(rp, "= Установить", COL_BLUE,  function() doAction("set_player")  end, 20+bw*2, btnY, bw, btnH)

        mkBtn(rp, "↺ Сбросить до стартового", Color(80, 80, 100),
            function()
                if not _selPly then return end
                sendAction({ type = "reset_player", sid64 = _selPly })
            end,
            12, btnY + 38, rw - 24, btnH)

        -- Персональный налог
        local sep = vgui.Create("DPanel", rp)
        sep:SetPos(12, btnY + 78); sep:SetSize(rw - 24, 1)
        sep.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BORDER) end

        makeLabel(rp, "Персональный налог (%)", "GRM_Admin_Small", COL_GREY)
            :SetPos(12, btnY + 90)

        local taxEntry = makeEntry(rp, "0–50", true)
        taxEntry:SetPos(12, btnY + 106); taxEntry:SetSize(rw - 24 - 100 - 8, 28)

        mkBtn(rp, "Применить", Color(180, 140, 30),
            function()
                if not _selPly then return end
                sendAction({ type = "set_player_tax", sid64 = _selPly,
                             rate = tonumber(taxEntry:GetValue()) or 0 })
            end,
            rw - 24 - 100, btnY + 106, 100, 28)

        mkBtn(rp, "Сбросить (по фракции)", Color(60, 60, 80),
            function()
                if not _selPly then return end
                sendAction({ type = "set_player_tax", sid64 = _selPly, clear = true })
            end,
            12, btnY + 142, rw - 24, 26)

        -- Обновление списка
        local function refreshList()
            list:Clear()
            if not _data then return end
            for _, pd in ipairs(_data.players or {}) do
                local taxStr = pd.ptax and (math.floor(pd.ptax*100) .. "%") or "—"
                local ln = list:AddLine(pd.nick, GRM.Format(pd.balance), taxStr)
                ln._sid64 = pd.sid64
                ln._nick  = pd.nick
                ln._bal   = pd.balance
                ln._ptax  = pd.ptax
            end
        end

        list.OnRowSelected = function(_, _, ln)
            _selPly = ln._sid64
            local taxStr = ln._ptax and (math.floor(ln._ptax*100) .. "%") or "нет (фракц.)"
            infoLbl:SetText(ln._nick .. "\n" .. GRM.Format(ln._bal) .. "  |  Налог: " .. taxStr)
        end

        p._refresh = refreshList
        p._tab     = "players"

        refreshList()
        return p
    end

    -- ================================================================
    --  ВКЛ. 3: ФРАКЦИИ
    -- ================================================================

    local function buildFactions(sheet)
        local p = sheet
        p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BG) end

        local listW = 210
        local list  = vgui.Create("DListView", p)
        list:SetPos(12, 10); list:SetSize(listW, p:GetTall() - 20)
        list:AddColumn("Фракция"):SetWidth(120)
        list:AddColumn("Бюджет"):SetWidth(80)
        list.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, COL_DARK) end

        local rp = vgui.Create("DPanel", p)
        rp:SetPos(listW + 20, 10)
        rp:SetSize(p:GetWide() - listW - 32, p:GetTall() - 20)
        rp.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, COL_PANEL) end

        local rw = rp:GetWide()

        local infoLbl = vgui.Create("DLabel", rp)
        infoLbl:SetPos(12, 10); infoLbl:SetSize(rw-24, 48)
        infoLbl:SetFont("GRM_Admin_Body"); infoLbl:SetTextColor(COL_GREY)
        infoLbl:SetText("Выберите фракцию из списка"); infoLbl:SetWrap(true)

        local yOff = 68

        makeLabel(rp, "Сумма:", "GRM_Admin_Small", COL_GREY):SetPos(12, yOff)
        local amtEntry = makeEntry(rp, "Введите сумму...", true)
        amtEntry:SetPos(12, yOff+16); amtEntry:SetSize(rw-24, 28)

        local qbW = math.floor((rw - 24 - 5*4) / 6)
        quickRow(rp, amtEntry, yOff + 50, qbW)

        local btnY = yOff + 78
        local btnH = 30
        local bw   = (rw - 24 - 4) / 2

        local function doFac(atype)
            if not _selFac then return end
            local amt = math.floor(tonumber(amtEntry:GetValue()) or 0)
            sendAction({ type = atype, faction = _selFac, amount = amt })
        end

        -- FIX: mkBtn вместо makeBtn():SetPos():SetSize()
        mkBtn(rp, "✚ Пополнить бюджет", COL_GREEN, function() doFac("give_faction") end, 12,    btnY, bw, btnH)
        mkBtn(rp, "✖ Снять с бюджета",  COL_RED,   function() doFac("take_faction") end, 16+bw, btnY, bw, btnH)

        mkBtn(rp, "💰 Выплатить всем онлайн-участникам (из бюджета)", Color(60, 120, 60),
            function() doFac("faction_payall") end,
            12, btnY + 38, rw-24, btnH)

        -- Налог фракции
        local sep = vgui.Create("DPanel", rp)
        sep:SetPos(12, btnY + 78); sep:SetSize(rw-24, 1)
        sep.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BORDER) end

        makeLabel(rp, "Налог фракции (0–50%)", "GRM_Admin_Small", COL_GREY)
            :SetPos(12, btnY + 90)

        local taxEntry = makeEntry(rp, "0–50", true)
        taxEntry:SetPos(12, btnY + 106); taxEntry:SetSize(rw - 24 - 100 - 8, 28)

        mkBtn(rp, "Установить", Color(180, 140, 30),
            function()
                if not _selFac then return end
                sendAction({ type = "set_faction_tax", faction = _selFac,
                             rate = tonumber(taxEntry:GetValue()) or 0 })
            end,
            rw - 24 - 100, btnY + 106, 100, 28)

        local function refreshList()
            list:Clear()
            if not _data then return end

            local names = {}
            for n in pairs(_data.factions or {}) do table.insert(names, n) end
            table.sort(names)

            for _, name in ipairs(names) do
                local fd = _data.factions[name]
                local ln = list:AddLine(name, GRM.Format(fd.budget))
                ln._name = name
                ln._fd   = fd
            end
        end

        list.OnRowSelected = function(_, _, ln)
            _selFac = ln._name
            local fd = ln._fd
            infoLbl:SetText(
                "[" .. ln._name .. "]\n" ..
                "Бюджет: " .. GRM.Format(fd.budget) ..
                "  |  Налог: " .. math.floor((fd.taxRate or 0)*100) .. "%" ..
                "  |  " .. fd.online .. "/" .. fd.total .. " онлайн"
            )
        end

        p._refresh = refreshList
        p._tab     = "factions"

        refreshList()
        return p
    end

    -- ================================================================
    --  ВКЛ. 4: ПЕРЕВОДЫ
    -- ================================================================

    local function buildTransfers(sheet)
        local p = sheet
        p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BG) end

        local pw = p:GetWide()

        local function makeCombo(parent, x, y, w)
            local c = vgui.Create("DComboBox", parent)
            c:SetPos(x, y); c:SetSize(w, 26)
            c:SetFont("GRM_Admin_Body")
            c.Paint = function(s, cw, ch)
                draw.RoundedBox(4, 0, 0, cw, ch, COL_DARK)
                surface.SetDrawColor(COL_BORDER)
                surface.DrawOutlinedRect(0, 0, cw, ch, 1)
                draw.SimpleText(s:GetValue(), "GRM_Admin_Body", 8, ch/2, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            return c
        end

        local cx = 20
        local cw = pw - 40

        makeLabel(p, "Откуда (тип):", "GRM_Admin_Small", COL_GREY):SetPos(cx, 16)
        local fromType = makeCombo(p, cx, 32, cw/2 - 8)
        fromType:AddChoice("Игрок",   "player")
        fromType:AddChoice("Фракция", "faction")
        fromType:ChooseOptionID(1)

        makeLabel(p, "Кому (тип):", "GRM_Admin_Small", COL_GREY):SetPos(cx + cw/2 + 8, 16)
        local toType = makeCombo(p, cx + cw/2 + 8, 32, cw/2 - 8)
        toType:AddChoice("Игрок",   "player")
        toType:AddChoice("Фракция", "faction")
        toType:ChooseOptionID(1)

        makeLabel(p, "Откуда (выбор):", "GRM_Admin_Small", COL_GREY):SetPos(cx, 72)
        local fromSel = makeCombo(p, cx, 88, cw/2 - 8)

        makeLabel(p, "Кому (выбор):", "GRM_Admin_Small", COL_GREY):SetPos(cx + cw/2 + 8, 72)
        local toSel = makeCombo(p, cx + cw/2 + 8, 88, cw/2 - 8)

        local function fillCombos()
            if not _data then return end
            local ftxt = fromType:GetSelected()   -- первый возврат — текст
            local ttxt = toType:GetSelected()

            fromSel:Clear(); toSel:Clear()

            if ftxt == "Игрок" then
                for _, pd in ipairs(_data.players or {}) do
                    fromSel:AddChoice(pd.nick, pd.sid64)
                end
            else
                local names = {}
                for n in pairs(_data.factions or {}) do table.insert(names, n) end
                table.sort(names)
                for _, n in ipairs(names) do fromSel:AddChoice(n, n) end
            end

            if ttxt == "Игрок" then
                for _, pd in ipairs(_data.players or {}) do
                    toSel:AddChoice(pd.nick, pd.sid64)
                end
            else
                local names = {}
                for n in pairs(_data.factions or {}) do table.insert(names, n) end
                table.sort(names)
                for _, n in ipairs(names) do toSel:AddChoice(n, n) end
            end
        end

        fromType.OnSelect = function() fillCombos() end
        toType.OnSelect   = function() fillCombos() end

        makeLabel(p, "Сумма:", "GRM_Admin_Small", COL_GREY):SetPos(cx, 130)
        local amtE = makeEntry(p, "Сумма перевода...", true)
        amtE:SetPos(cx, 146); amtE:SetSize(cw, 28)

        local qbW = math.floor((cw - 5*4) / 6)
        quickRow(p, amtE, 180, qbW)

        -- FIX: mkBtn вместо makeBtn():SetPos():SetSize()
        mkBtn(p, "➜  Выполнить перевод", COL_BLUE,
            function()
                if not _data then return end
                local _, fromV = fromSel:GetSelected()
                local _, toV   = toSel:GetSelected()
                local amt      = math.floor(tonumber(amtE:GetValue()) or 0)
                local _, fval  = fromType:GetSelected()
                local _, tval  = toType:GetSelected()

                if not fromV or fromV == "" then return end
                if not toV   or toV   == "" then return end
                if amt <= 0 then return end

                local atype
                if fval == "player"  and tval == "player"  then
                    atype = "transfer_pp"
                elseif fval == "player"  and tval == "faction" then
                    atype = "transfer_pf"
                elseif fval == "faction" and tval == "player"  then
                    atype = "transfer_fp"
                else
                    -- faction → faction: снимаем и пополняем
                    sendAction({ type = "take_faction", faction = fromV, amount = amt })
                    sendAction({ type = "give_faction", faction = toV,   amount = amt })
                    return
                end
                sendAction({ type = atype, from = fromV, to = toV, amount = amt })
            end,
            cx, 210, cw, 34)

        p._refresh = fillCombos
        p._tab     = "transfers"

        fillCombos()
        return p
    end

    -- ================================================================
    --  ВКЛ. 5: ЖУРНАЛ
    -- ================================================================

    local function buildLog(sheet)
        local p = sheet
        p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, COL_BG) end

        local scroll = vgui.Create("DScrollPanel", p)
        scroll:SetPos(12, 10); scroll:SetSize(p:GetWide()-24, p:GetTall()-20)
        scroll.Paint = function() end

        local function refreshLog()
            scroll:Clear()
            if not _data or not _data.log then return end

            for i = #_data.log, 1, -1 do
                local entry = _data.log[i]
                local row   = vgui.Create("DPanel", scroll)
                row:SetSize(scroll:GetWide(), 30)
                row:Dock(TOP); row:DockMargin(0, 0, 0, 2)

                local timeStr = os.date("%H:%M:%S", entry.t or 0)
                local even    = (i % 2 == 0)

                row.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, even and COL_DARK or COL_PANEL)
                    draw.SimpleText(timeStr,      "GRM_Admin_Small", 10,  h/2, COL_GREY,  TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(entry.admin,  "GRM_Admin_Small", 80,  h/2, COL_GOLD,  TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(entry.action, "GRM_Admin_Body",  200, h/2, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end

            if #_data.log == 0 then
                makeLabel(scroll, "Журнал пуст", "GRM_Admin_Body", COL_GREY):SetPos(0, 8)
            end
        end

        p._refresh = refreshLog
        p._tab     = "log"

        refreshLog()
        return p
    end

    -- ================================================================
    --  ГЛАВНОЕ ОКНО
    -- ================================================================

    function GRM.OpenAdminMenu()
        if IsValid(_frame) then _frame:Remove() end

        local W, H = 860, 580
        local f = vgui.Create("DFrame")
        f:SetTitle("")
        f:SetSize(W, H)
        f:Center()
        f:MakePopup()
        f:SetDraggable(true)
        _frame = f

        f.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, COL_BG)
            draw.RoundedBox(10, 0, 0, w, 36, COL_DARK)
            draw.SimpleText("GRM Admin  —  Управление экономикой", "GRM_Admin_Title", 14, 18, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(COL_BORDER)
            surface.DrawRect(0, 36, w, 1)
        end

        -- Кнопка закрыть
        local closeBtn = vgui.Create("DButton", f)
        closeBtn:SetSize(28, 28); closeBtn:SetPos(W - 36, 4)
        closeBtn:SetText("✕"); closeBtn:SetFont("GRM_Admin_Head"); closeBtn:SetTextColor(COL_GREY)
        closeBtn.Paint = function(s, w, h)
            if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, Color(180, 40, 40)) end
        end
        closeBtn.DoClick = function() f:Remove() end

        -- Кнопка обновить
        local refBtn = vgui.Create("DButton", f)
        refBtn:SetSize(90, 22); refBtn:SetPos(W - 134, 7)
        refBtn:SetText("⟳ Обновить"); refBtn:SetFont("GRM_Admin_Small"); refBtn:SetTextColor(COL_WHITE)
        refBtn.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(50,70,100) or Color(35,50,75))
        end
        refBtn.DoClick = requestData

        -- ── Вкладки (самодельные) ────────────────────────────

        local TABS = {
            { name = "📊 Обзор",    build = buildOverview  },
            { name = "👤 Игроки",   build = buildPlayers   },
            { name = "🏛 Фракции",  build = buildFactions  },
            { name = "↔ Переводы",  build = buildTransfers },
            { name = "📋 Журнал",   build = buildLog       },
        }

        local tabBarH  = 34
        local tabBarY  = 38
        local bodyY    = tabBarY + tabBarH + 2
        local bodyH    = H - bodyY - 8
        local tabW     = math.floor((W - 16) / #TABS)
        local tabBtns  = {}
        local curBody  = nil

        local function switchTab(idx)
            if IsValid(curBody) then curBody:Remove() end

            for i, tb in ipairs(tabBtns) do
                if IsValid(tb) then tb._active = (i == idx) end
            end

            local body = vgui.Create("DPanel", f)
            body:SetPos(8, bodyY); body:SetSize(W - 16, bodyH)
            body.Paint = function() end

            TABS[idx].build(body)
            curBody = body

            f._refresh = function()
                if IsValid(body) and body._refresh then body._refresh() end
            end
        end

        for i, tab in ipairs(TABS) do
            local tb = vgui.Create("DButton", f)
            tb:SetPos(8 + (i-1)*tabW, tabBarY)
            tb:SetSize(tabW - 2, tabBarH)
            tb:SetText(tab.name)
            tb:SetFont("GRM_Admin_Body")
            tb:SetTextColor(COL_WHITE)
            tb._active = false
            tb.Paint = function(s, w, h)
                local bg = s._active and COL_TAB_ACT
                    or (s:IsHovered() and Color(40,50,70) or Color(30,35,55))
                draw.RoundedBox(6, 0, 0, w, h, bg)
            end
            tb.DoClick = function() switchTab(i) end
            tabBtns[i] = tb
        end

        switchTab(1)
        requestData()

        -- GRM-FIX: сторожевые повторы. Если первый пакет данных потерялся
        -- (меню открыто сразу после захода, переполненный net-буфер),
        -- пере-запрашиваем до 3 раз, пока _data не появится.
        local tag = "GRM_Admin_DataWatchdog_" .. tostring(f)
        timer.Create(tag, 1.2, 3, function()
            if not IsValid(_frame) or _frame ~= f then timer.Remove(tag) return end
            if _data then timer.Remove(tag) return end
            requestData()
        end)
    end

    -- GRM-FIX: клиентская регистрация grm_adminmenu УДАЛЕНА.
    -- Команда была зарегистрирована на обеих сторонах: меню открывалось
    -- локально И тут же второй раз по ответу сервера (мерцание,
    -- пересоздание элементов, двойные requestData). Теперь единственный
    -- открыватель — серверная concommand (grm_adminmenu / econadmin)
    -- и чат: !grmmenu / !econadmin.

end -- CLIENT

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/econadmin" })
end
