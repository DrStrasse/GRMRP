--[[--------------------------------------------------------------------
    GRM Wanted Commands v1.0.0 — чат- и консольные команды розыска
    и штрафов.

    Закрывает Д14: F4-меню рекламировало /wanted_set, которой не
    существовало. Здесь она реализована вместе с остальным набором.

    Чат-команды
      /wanted_set <игрок> <0-5> [причина]  — выставить уровень розыска
      /wanted_info <игрок>                  — карточка розыска
      /wanted_list [civil|military]         — сводка по базе
      /fine_issue <игрок> <сумма> [причина] — выписать штраф
      /my_fines                             — свои штрафы и долг
      /fines_of <игрок>                     — штрафы персонажа
      /fine_pay [номер|all]                 — оплатить
      /fine_cancel <номер> [причина]        — аннулировать

    Консольные команды (те же действия, для биндов и RCON)
      grm_wanted_set, grm_wanted_info, grm_fine_issue,
      grm_fine_pay, grm_fine_cancel, grm_fines_of, grm_my_fines
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}

local CMD = {}
GRM.Wanted.Commands = CMD
CMD.Version = "1.0.0"

-----------------------------------------------------------------------
-- Хелперы
-----------------------------------------------------------------------
local function msg(ply, text, r, g, b)
    if not IsValid(ply) then print("[GRM] " .. text) return end
    if GRM.Notify then GRM.Notify(ply, text, r or 120, g or 200, b or 255)
    else ply:ChatPrint("[Розыск] " .. text) end
end

local function ok(ply, text)  msg(ply, text, 110, 220, 150) end
local function err(ply, text) msg(ply, text, 250, 110, 110) end
local function hint(ply, text) msg(ply, text, 250, 190, 90) end

local function money(v)
    local F = GRM.Wanted.Fines
    if F and isfunction(F.Money) then return F.Money(v) end
    return tostring(math.floor(tonumber(v) or 0)) .. " GRM"
end

-- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана:
-- делегировал в Fines.CharKey, а тот теперь сам канон.
local charKey = GRM.CharKey

--- Поиск цели: ник, часть ника, RP-имя, SteamID64 или CharacterKey.
-- Д11: цель может быть офлайн, поэтому если среди игроков не нашли,
-- пробуем интерпретировать аргумент как ключ базы.
local function resolveTarget(arg)
    arg = string.Trim(tostring(arg or ""))
    if arg == "" then return nil, nil, "Не указан игрок" end

    local low = string.lower(arg)
    local exact, partial
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local nick = string.lower(p:Nick())
            local rp   = string.lower(p:GetNWString("GRM_RPName", ""))
            if nick == low or rp == low or p:SteamID64() == arg or p:SteamID() == arg then
                exact = p break
            end
            if not partial and (string.find(nick, low, 1, true) or (rp ~= "" and string.find(rp, low, 1, true))) then
                partial = p
            end
        end
    end

    local p = exact or partial
    if IsValid(p) then return charKey(p), p end

    -- офлайн-цель: SteamID64 или полный ключ персонажа
    if arg:match("^%d+$") or arg:match(":char[1-3]$") then
        local k = charKey(arg)
        local W = GRM.Wanted
        if (W.Records and W.Records[k]) or true then return k, nil end
    end
    return nil, nil, "Игрок не найден: " .. arg
end
CMD.ResolveTarget = resolveTarget

local function nameOfKey(k)
    local W = GRM.Wanted
    local F = W.Fines
    local p = F and isfunction(F.FindPlayer) and F.FindPlayer(k)
    if IsValid(p) then
        local rp = p:GetNWString("GRM_RPName", "")
        return rp ~= "" and rp or p:Nick()
    end
    local r = W.Records and W.Records[k]
    return (r and r.name) or k
end

local function statusRu(s)
    if s == "paid" then return "оплачен" end
    if s == "cancelled" then return "аннулирован" end
    return "не оплачен"
end

-----------------------------------------------------------------------
-- Действия
-----------------------------------------------------------------------

--- /wanted_set <игрок> <0-5> [причина]  (Д14)
function CMD.WantedSet(ply, args)
    local W = GRM.Wanted
    if not isfunction(W.SetLevel) then return err(ply, "Модуль розыска не загружен") end
    if not (isfunction(W.CanEdit) and W.CanEdit(ply)) then
        return err(ply, "У вас нет прав на изменение базы розыска")
    end

    local key, _, why = resolveTarget(args[1])
    if not key then return err(ply, why) end

    local level = tonumber(args[2])
    if not level then
        return hint(ply, "Использование: /wanted_set <игрок> <0-5> [причина]")
    end
    level = math.Clamp(math.floor(level), 0, (W.Config and W.Config.MaxLevel) or 5)

    local reason = table.concat(args, " ", 3)
    if reason == "" then reason = level > 0 and "Решение органа" or "Снят с розыска" end

    local success, res = W.SetLevel(ply, key, level, reason)
    if not success then return err(ply, tostring(res)) end

    if level == 0 then
        ok(ply, ("%s снят с розыска"):format(nameOfKey(key)))
    else
        local lv = W.Levels and W.Levels[level]
        ok(ply, ("%s: уровень розыска %d%s"):format(nameOfKey(key), level,
            lv and (" — " .. (lv.name or lv[1] or "")) or ""))
    end
end

--- /wanted_info <игрок>
function CMD.WantedInfo(ply, args)
    local W = GRM.Wanted
    if not (isfunction(W.CanView) and W.CanView(ply)) then
        return err(ply, "У вас нет доступа к базе розыска")
    end
    local key, _, why = resolveTarget(args[1])
    if not key then return err(ply, why) end

    local r = W.Records and W.Records[key]
    if not r or (r.level or 0) <= 0 and #(r.reasons or {}) == 0 then
        return msg(ply, ("%s: в розыске не значится"):format(nameOfKey(key)), 160, 200, 160)
    end

    local jurRu = (r.jurisdiction == "military") and "военная" or "гражданская"
    msg(ply, ("── %s • уровень %d • юрисдикция: %s"):format(r.name or key, r.level or 0, jurRu), 250, 200, 120)

    local total = 0
    for i, c in ipairs(r.reasons or {}) do
        total = total + (tonumber(c.fine) or 0)
        if i <= 8 then
            msg(ply, ("  %d) %s %s (ур.%d)"):format(i, c.code or "—", c.title or "—", c.level or 0), 210, 220, 235)
        end
    end
    if #(r.reasons or {}) > 8 then
        msg(ply, ("  … и ещё %d статей"):format(#r.reasons - 8), 160, 175, 195)
    end

    local F = W.Fines
    local debt = (F and isfunction(F.DebtOf)) and F.DebtOf(key) or 0
    msg(ply, ("  Штрафы по статьям: %s • непогашенный долг: %s"):format(money(total), money(debt)), 250, 200, 120)
end

--- /wanted_list [civil|military]
function CMD.WantedList(ply, args)
    local W = GRM.Wanted
    if not (isfunction(W.CanView) and W.CanView(ply)) then
        return err(ply, "У вас нет доступа к базе розыска")
    end
    local filter = string.lower(tostring(args[1] or ""))
    if filter ~= "civil" and filter ~= "military" then filter = "all" end

    local rows = {}
    for k, r in pairs(W.Records or {}) do
        if istable(r) and (r.level or 0) > 0 then
            local j = r.jurisdiction == "military" and "military" or "civil"
            if filter == "all" or j == filter then
                rows[#rows + 1] = { key = k, name = r.name or k, level = r.level, j = j }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return tostring(a.name) < tostring(b.name)
    end)

    if #rows == 0 then return msg(ply, "В розыске никто не значится", 160, 200, 160) end
    msg(ply, ("── В розыске: %d"):format(#rows), 250, 200, 120)
    for i = 1, math.min(#rows, 15) do
        local r = rows[i]
        msg(ply, ("  [%d] %s (%s)"):format(r.level, r.name, r.j == "military" and "воен." or "гражд."), 210, 220, 235)
    end
    if #rows > 15 then msg(ply, ("  … и ещё %d"):format(#rows - 15), 160, 175, 195) end
end

--- /fine_issue <игрок> <сумма> [причина]
function CMD.FineIssue(ply, args)
    local F = GRM.Wanted.Fines
    if not (F and isfunction(F.Issue)) then return err(ply, "Реестр штрафов не загружен") end

    local key, _, why = resolveTarget(args[1])
    if not key then return err(ply, why) end

    local amount = math.floor(tonumber(args[2]) or 0)
    if amount <= 0 then
        return hint(ply, "Использование: /fine_issue <игрок> <сумма> [причина]")
    end

    local reason = table.concat(args, " ", 3)
    if reason == "" then reason = "Нарушение общественного порядка" end

    local rec, e = F.Issue(ply, key, amount, reason)
    if not rec then return err(ply, tostring(e)) end
    ok(ply, ("Штраф №%d выписан: %s — %s"):format(rec.id, rec.targetName or nameOfKey(key), money(rec.amount)))
end

--- /my_fines
function CMD.MyFines(ply)
    local F = GRM.Wanted.Fines
    if not (F and isfunction(F.For)) then return err(ply, "Реестр штрафов не загружен") end
    if not IsValid(ply) then return end

    local key = charKey(ply)
    local list = F.For(key, false)
    if #list == 0 then return msg(ply, "У вас нет штрафов", 110, 220, 150) end

    local debt = F.DebtOf(key)
    msg(ply, ("── Ваши штрафы: %d, к оплате %s"):format(#list, money(debt)), 250, 200, 120)
    local shown = 0
    for i = #list, 1, -1 do
        local r = list[i]
        shown = shown + 1
        if shown > 10 then break end
        local left = math.max(0, (r.amount or 0) - (r.paid or 0))
        msg(ply, ("  №%d • %s • %s • %s%s"):format(
            r.id, money(r.amount), statusRu(r.status), r.reason or "—",
            (r.status == "unpaid" and left ~= r.amount) and (" (осталось " .. money(left) .. ")") or ""
        ), r.status == "unpaid" and 245 or 170, r.status == "unpaid" and 180 or 190, r.status == "unpaid" and 110 or 180)
    end
    if debt > 0 then
        msg(ply, "Оплатить: /fine_pay <номер> либо /fine_pay all", 140, 200, 250)
    end
end

--- /fines_of <игрок>
function CMD.FinesOf(ply, args)
    local F = GRM.Wanted.Fines
    if not (F and isfunction(F.For)) then return err(ply, "Реестр штрафов не загружен") end
    local W = GRM.Wanted
    if not (isfunction(W.CanView) and W.CanView(ply)) then
        return err(ply, "У вас нет доступа к реестру штрафов")
    end

    local key, _, why = resolveTarget(args[1])
    if not key then return err(ply, why) end

    local list = F.For(key, false)
    if #list == 0 then return msg(ply, ("%s: штрафов нет"):format(nameOfKey(key)), 160, 200, 160) end

    msg(ply, ("── %s: штрафов %d, долг %s"):format(nameOfKey(key), #list, money(F.DebtOf(key))), 250, 200, 120)
    local shown = 0
    for i = #list, 1, -1 do
        local r = list[i]
        shown = shown + 1
        if shown > 12 then break end
        msg(ply, ("  №%d • %s • %s • %s (выписал %s)"):format(
            r.id, money(r.amount), statusRu(r.status), r.reason or "—", r.issuerName or "—"), 210, 220, 235)
    end
end

--- /fine_pay [номер|all]
function CMD.FinePay(ply, args)
    local F = GRM.Wanted.Fines
    if not (F and isfunction(F.Pay)) then return err(ply, "Реестр штрафов не загружен") end
    if not IsValid(ply) then return end

    local a = string.lower(string.Trim(tostring(args[1] or "")))
    local key = charKey(ply)

    if a == "" or a == "all" or a == "все" then
        local list = F.For(key, true)
        if #list == 0 then return msg(ply, "У вас нет неоплаченных штрафов", 110, 220, 150) end
        local paidCount, paidSum = 0, 0
        for _, r in ipairs(list) do
            local success, res = F.Pay(ply, r.id)
            if success then
                paidCount = paidCount + 1
                paidSum = paidSum + (tonumber(res) or 0)
            else
                -- денег не хватило — прекращаем, сообщение уже отправлено модулем
                if paidCount == 0 then return err(ply, tostring(res)) end
                break
            end
        end
        return ok(ply, ("Оплачено штрафов: %d на сумму %s"):format(paidCount, money(paidSum)))
    end

    local id = math.floor(tonumber(a) or 0)
    if id <= 0 then return hint(ply, "Использование: /fine_pay <номер> либо /fine_pay all") end

    local success, res = F.Pay(ply, id)
    if not success then return err(ply, tostring(res)) end
    ok(ply, ("Штраф №%d оплачен: %s"):format(id, money(res)))
end

--- /fine_cancel <номер> [причина]
function CMD.FineCancel(ply, args)
    local F = GRM.Wanted.Fines
    if not (F and isfunction(F.Cancel)) then return err(ply, "Реестр штрафов не загружен") end

    local id = math.floor(tonumber(args[1]) or 0)
    if id <= 0 then return hint(ply, "Использование: /fine_cancel <номер> [причина]") end

    local reason = table.concat(args, " ", 2)
    if reason == "" then reason = "решение органа" end

    local success, res = F.Cancel(ply, id, reason)
    if not success then return err(ply, tostring(res)) end
    ok(ply, ("Штраф №%d аннулирован"):format(id))
end

-----------------------------------------------------------------------
-- Регистрация чат-команд
-----------------------------------------------------------------------
local HANDLERS = {
    ["/wanted_set"]   = CMD.WantedSet,
    ["!wanted_set"]   = CMD.WantedSet,
    ["/розыск_уровень"] = CMD.WantedSet,
    ["/wanted_info"]  = CMD.WantedInfo,
    ["/wanted_list"]  = CMD.WantedList,
    ["/fine_issue"]   = CMD.FineIssue,
    ["/my_fines"]     = CMD.MyFines,
    ["/мои_штрафы"]   = CMD.MyFines,
    ["/fines_of"]     = CMD.FinesOf,
    ["/fine_pay"]     = CMD.FinePay,
    ["/оплатить_штраф"] = CMD.FinePay,
    ["/fine_cancel"]  = CMD.FineCancel,
}
CMD.Handlers = HANDLERS

local function dispatch(ply, text)
    if not isstring(text) then return false end
    local args = string.Explode(" ", string.Trim(text))
    local c = string.lower(args[1] or "")
    local fn = HANDLERS[c]
    if not fn then return false end
    table.remove(args, 1)
    local success, e = pcall(fn, ply, args)
    if not success then
        ErrorNoHalt("[GRM Wanted Commands] " .. tostring(e) .. "\n")
        err(ply, "Внутренняя ошибка команды")
    end
    return true
end
CMD.Dispatch = dispatch

-- Тот же двойной хук, что и в ядре розыска: PlayerSayTransform гасит
-- сообщение до чата, PlayerSay остаётся фолбэком.
hook.Add("PlayerSay", "GRM_WantedCmd_Transform", function(ply, text, teamSays)
    local pack = { tostring(text or ""), SkipPlayerSay = false }
        if not istable(pack) or not isstring(pack[1]) then return end
        if dispatch(ply, pack[1]) then
            pack[1] = ""
            pack.SkipPlayerSay = true
        end

    if pack.SkipPlayerSay == true then return "" end
end)

hook.Add("PlayerSay", "GRM_WantedCmd_Fallback", function(ply, text)
    if dispatch(ply, text) then return "" end
end)

-----------------------------------------------------------------------
-- Консольные команды
-----------------------------------------------------------------------
local function con(name, fn)
    concommand.Add(name, function(ply, _, args) fn(ply, args or {}) end)
end

con("grm_wanted_set",   CMD.WantedSet)
con("grm_wanted_info",  CMD.WantedInfo)
con("grm_wanted_list",  CMD.WantedList)
con("grm_fine_issue",   CMD.FineIssue)
con("grm_fine_pay",     CMD.FinePay)
con("grm_fine_cancel",  CMD.FineCancel)
con("grm_fines_of",     CMD.FinesOf)
con("grm_my_fines",     function(ply) CMD.MyFines(ply) end)

print("[GRM Wanted Commands] v" .. CMD.Version .. " загружен")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/fine_cancel", "/fine_issue", "/fine_pay", "/fines_of", "/my_fines", "/wanted_info", "/wanted_list", "/wanted_set", "/мои_штрафы", "/оплатить_штраф", "/розыск_уровень" })
end
