-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Wanted Fines v1.0.0 — реестр штрафов и взысканий

    Связывает систему розыска (GRM.Wanted) с экономикой (GRM.Economy):
      • статья каталога с полем fine > 0 порождает НЕОПЛАЧЕННЫЙ штраф;
      • оплата проходит через GRM.TakeMoney + доли фракции/государства,
        то есть повторяет денежную логику E.Fine;
      • штрафы, выписанные через /fine, тоже попадают в реестр (хук
        GRM_FineIssued) уже со статусом "paid" — единая история.

    Данные: data/grm_wanted/fines.json  { version = 1, fines = {...} }
    Запись: {
        id, target, targetName, issuer, issuerName,
        amount, paid, reason, article, jurisdiction,
        status = "unpaid" | "paid" | "cancelled",
        issued, closed
    }
    Ключ цели — GRM.Identity.CharacterKey (SteamID64:charN).

    Загружается алфавитно после sh_grm_wanted_config.lua и до
    server/sv_grm_wanted.lua не зависит: обращения к GRM.Wanted ленивые.
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
GRM.Wanted.Fines = GRM.Wanted.Fines or {}

local F = GRM.Wanted.Fines
F.Version = "1.0.0"

local DIR  = "grm_wanted"
local FILE = "grm_wanted/fines.json"

F.List = F.List or {}   -- массив записей (порядок = хронология)
F._nextID = F._nextID or 1

-----------------------------------------------------------------------
-- Конфигурация
-----------------------------------------------------------------------
F.Config = F.Config or {
    -- максимум записей в реестре (старые оплаченные вытесняются)
    MaxRecords     = 2000,
    -- максимум неоплаченных штрафов на персонажа
    MaxUnpaidPerChar = 24,
    -- потолок суммы одного штрафа
    MaxAmount      = 10000000,
    -- автоматически создавать штраф при вменении статьи с fine > 0
    AutoFromCharge = true,
    -- писать штрафы из /fine (E.Fine) в реестр как оплаченные
    MirrorEconomyFines = true,
    -- суперадмин всегда может всё
    SuperAdminBypass = true,
}

-----------------------------------------------------------------------
-- Утилиты
-----------------------------------------------------------------------
local function ensure()
    if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
end

local function jsonT(s)
    -- ВАЖНО: третий аргумент true — ключи SteamID64 не должны стать числами
    local ok, t = pcall(util.JSONToTable, s or "", false, true)
    return ok and istable(t) and t or nil
end

local function write(path, data)
    local ok, s = pcall(util.TableToJSON, data, true)
    if not ok or not isstring(s) then return false end
    file.Write(path, s)
    return file.Read(path, "DATA") == s
end

--- Приводит игрока / SteamID64 / ключ к CharacterKey.
-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
F.CharKey = charKey

local function findPlayerByKey(k)
    k = tostring(k or "")
    if k == "" then return nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and (charKey(p) == k or p:SteamID64() == k) then return p end
    end
end
F.FindPlayer = findPlayerByKey

local function notify(p, msg, r, g, b)
    if not IsValid(p) then return end
    if GRM.Notify then GRM.Notify(p, msg, r or 120, g or 200, b or 255)
    else p:ChatPrint("[Штрафы] " .. msg) end
end

local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end
F.Money = money

--- Юрисдикция персонажа: военные фракции → "military", иначе "civil".
function F.JurisdictionOf(ply)
    if GRM.Wanted and isfunction(GRM.Wanted.JurisdictionOfPlayer) then
        return GRM.Wanted.JurisdictionOfPlayer(ply)
    end
    return "civil"
end

-----------------------------------------------------------------------
-- Загрузка / сохранение
-----------------------------------------------------------------------
local function normalize(rec, index)
    if not istable(rec) then return nil end
    local target = charKey(rec.target or rec.sid or "")
    if target == "" then return nil end

    local status = tostring(rec.status or "unpaid")
    if status ~= "paid" and status ~= "cancelled" then status = "unpaid" end

    local amount = math.Clamp(math.floor(tonumber(rec.amount) or 0), 0, F.Config.MaxAmount)
    if amount <= 0 then return nil end

    local id = math.floor(tonumber(rec.id) or 0)
    if id <= 0 then id = index end

    return {
        id           = id,
        target       = target,
        targetName   = tostring(rec.targetName or rec.name or "?"):sub(1, 64),
        issuer       = tostring(rec.issuer or "system"),
        issuerName   = tostring(rec.issuerName or "Система"):sub(1, 64),
        amount       = amount,
        paid         = math.Clamp(math.floor(tonumber(rec.paid) or 0), 0, amount),
        reason       = tostring(rec.reason or ""):sub(1, 240),
        article      = tostring(rec.article or ""):sub(1, 48),
        jurisdiction = rec.jurisdiction == "military" and "military" or "civil",
        status       = status,
        issued       = math.floor(tonumber(rec.issued) or os.time()),
        closed       = rec.closed and math.floor(tonumber(rec.closed)) or nil,
    }
end

function F.Load()
    ensure()
    F.List = {}
    F._nextID = 1

    if not file.Exists(FILE, "DATA") then return true end
    local t = jsonT(file.Read(FILE, "DATA"))
    if not t then
        -- Не затираем повреждённый файл: делаем резервную копию.
        local bak = FILE .. ".corrupt." .. os.time()
        local raw = file.Read(FILE, "DATA")
        if raw then file.Write(bak, raw) end
        ErrorNoHalt("[GRM Wanted Fines] fines.json повреждён, копия: " .. bak .. "\n")
        return false
    end

    local src = t.fines or t
    for i, rec in ipairs(istable(src) and src or {}) do
        local n = normalize(rec, i)
        if n then
            F.List[#F.List + 1] = n
            if n.id >= F._nextID then F._nextID = n.id + 1 end
        end
    end
    return true
end

function F.Save()
    ensure()
    -- вытеснение: сначала закрытые (оплаченные/аннулированные) записи
    local maxRec = F.Config.MaxRecords or 2000
    while #F.List > maxRec do
        local removed = false
        for i = 1, #F.List do
            if F.List[i].status ~= "unpaid" then
                table.remove(F.List, i)
                removed = true
                break
            end
        end
        if not removed then table.remove(F.List, 1) end
    end
    return write(FILE, { version = 1, fines = F.List })
end

-----------------------------------------------------------------------
-- Выборки
-----------------------------------------------------------------------
--- Все штрафы персонажа (по CharacterKey / игроку / SteamID64).
function F.For(target, onlyUnpaid)
    local k = charKey(target)
    local out = {}
    for _, rec in ipairs(F.List) do
        if rec.target == k and (not onlyUnpaid or rec.status == "unpaid") then
            out[#out + 1] = rec
        end
    end
    return out
end

--- Суммарный долг персонажа.
function F.DebtOf(target)
    local sum = 0
    for _, rec in ipairs(F.For(target, true)) do
        sum = sum + (rec.amount - rec.paid)
    end
    return sum
end

function F.ByID(id)
    id = math.floor(tonumber(id) or 0)
    for _, rec in ipairs(F.List) do
        if rec.id == id then return rec end
    end
end

--- Постраничная выборка для терминалов: только своя юрисдикция.
-- @param jurisdiction "civil" | "military" | "all"
-- @param filter { status = ..., query = ... }
function F.Page(jurisdiction, filter, offset, limit)
    filter = istable(filter) and filter or {}
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    limit  = math.Clamp(math.floor(tonumber(limit) or 50), 1, 200)

    local q = string.lower(tostring(filter.query or ""))
    local want = tostring(filter.status or "")

    local matched, out = 0, {}
    for i = #F.List, 1, -1 do  -- новые сверху
        local rec = F.List[i]
        local okJ = (jurisdiction == "all") or (rec.jurisdiction == jurisdiction)
        local okS = (want == "" or want == "all") or (rec.status == want)
        local okQ = (q == "")
            or string.find(string.lower(rec.targetName), q, 1, true)
            or string.find(string.lower(rec.target), q, 1, true)
            or string.find(string.lower(rec.reason), q, 1, true)
        if okJ and okS and okQ then
            matched = matched + 1
            if matched > offset and #out < limit then
                out[#out + 1] = rec
            end
        end
    end
    return out, matched
end

-----------------------------------------------------------------------
-- Выписка штрафа
-----------------------------------------------------------------------
--- Создаёт штраф. Деньги НЕ списываются — создаётся долг.
-- @return record | nil, error
function F.Issue(issuer, target, amount, reason, opts)
    opts = istable(opts) and opts or {}
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return nil, "Сумма должна быть больше нуля" end
    amount = math.min(amount, F.Config.MaxAmount)

    local tKey = charKey(target)
    if tKey == "" then return nil, "Не указан нарушитель" end

    -- лимит неоплаченных
    local unpaid = F.For(tKey, true)
    if #unpaid >= (F.Config.MaxUnpaidPerChar or 24) then
        return nil, "У нарушителя слишком много неоплаченных штрафов (" .. #unpaid .. ")"
    end

    local tPly = IsValid(target) and target:IsPlayer() and target or findPlayerByKey(tKey)
    local tName = opts.targetName
    if not tName or tName == "" then
        if IsValid(tPly) then
            tName = tPly:GetNWString("GRM_RPName", "")
            if tName == "" then tName = tPly:Nick() end
        else
            tName = tKey
        end
    end

    local rec = {
        id           = F._nextID,
        target       = tKey,
        targetName   = tostring(tName):sub(1, 64),
        issuer       = IsValid(issuer) and charKey(issuer) or "system",
        issuerName   = IsValid(issuer) and issuer:Nick() or "Система",
        amount       = amount,
        paid         = 0,
        reason       = tostring(reason or "Без указания причины"):sub(1, 240),
        article      = tostring(opts.article or ""):sub(1, 48),
        jurisdiction = opts.jurisdiction == "military" and "military" or "civil",
        status       = tostring(opts.status or "unpaid") == "paid" and "paid" or "unpaid",
        issued       = os.time(),
        issuerFaction = tostring(opts.issuerFaction or (IsValid(issuer) and issuer:GetNWString("GRM_Faction", "") or "")),
    }
    if rec.status == "paid" then
        rec.paid = amount
        rec.closed = os.time()
    end

    F._nextID = F._nextID + 1
    F.List[#F.List + 1] = rec
    F.Save()

    if IsValid(tPly) and rec.status == "unpaid" then
        notify(tPly, ("ШТРАФ №%d: %s — %s. Оплата: /fine_pay %d")
            :format(rec.id, money(rec.amount), rec.reason, rec.id), 255, 150, 70)
    end

    hook.Run("GRM_WantedFineIssued", issuer, tPly or tKey, rec)
    return rec
end

-----------------------------------------------------------------------
-- Оплата
-----------------------------------------------------------------------
--- Распределяет оплаченную сумму: доля фракции-получателя и государства.
-- Повторяет логику E.Fine, чтобы деньги ходили одинаково.
local function distribute(rec, sum, payerName)
    local E = GRM.Economy
    local cfg = (E and E.Config) or {}
    local facName = rec.issuerFaction

    if not facName or facName == "" then
        -- определяем фракцию по выписавшему, если он онлайн
        local ip = findPlayerByKey(rec.issuer)
        if IsValid(ip) then facName = ip:GetNWString("GRM_Faction", "") end
    end

    if facName and facName ~= "" and cfg.FineToBudget and GRM.FactionBudgetAdd then
        local pct = 0
        if E and isfunction(E.FinePercentFor) then
            pct = math.Clamp(tonumber(E.FinePercentFor(facName)) or 0, 0, 100)
        end
        local stateShare = math.floor(sum * pct / 100)
        local toFac = sum - stateShare
        if toFac > 0 then
            GRM.FactionBudgetAdd(facName, toFac,
                ("Оплата штрафа №%d (%s): %s"):format(rec.id, payerName, money(toFac)))
        end
        if stateShare > 0 and E and isfunction(E.StateAdd) then
            E.StateAdd(stateShare, ("Оплата штрафа №%d (%s), доля государства"):format(rec.id, payerName))
        end
    elseif cfg.FinesToState and E and isfunction(E.StateAdd) then
        E.StateAdd(sum, ("Оплата штрафа №%d (%s)"):format(rec.id, payerName))
    end
end

--- Оплата штрафа игроком (полностью или частично).
-- @return true, оплаченная сумма | false, причина
function F.Pay(ply, id, amount)
    if not (IsValid(ply) and ply:IsPlayer()) then return false, "Нет игрока" end
    local rec = F.ByID(id)
    if not rec then return false, "Штраф №" .. tostring(id) .. " не найден" end
    if rec.status ~= "unpaid" then return false, "Этот штраф уже закрыт" end
    if rec.target ~= charKey(ply) then return false, "Это не ваш штраф" end

    local due = rec.amount - rec.paid
    amount = math.floor(tonumber(amount) or due)
    if amount <= 0 then return false, "Сумма должна быть больше нуля" end
    amount = math.min(amount, due)

    local balance = GRM.GetBalance and GRM.GetBalance(ply) or 0
    if balance < amount then
        return false, ("Недостаточно средств: нужно %s, у вас %s"):format(money(amount), money(balance))
    end

    if not (GRM.TakeMoney and GRM.TakeMoney(ply, amount, ("Оплата штрафа №%d"):format(rec.id))) then
        return false, "Не удалось списать средства"
    end

    rec.paid = rec.paid + amount
    if rec.paid >= rec.amount then
        rec.status = "paid"
        rec.closed = os.time()
    end
    F.Save()

    distribute(rec, amount, ply:Nick())

    if rec.status == "paid" then
        notify(ply, ("Штраф №%d оплачен полностью (%s)."):format(rec.id, money(rec.amount)), 120, 220, 140)
    else
        notify(ply, ("Внесено %s по штрафу №%d. Остаток: %s")
            :format(money(amount), rec.id, money(rec.amount - rec.paid)), 200, 220, 140)
    end

    hook.Run("GRM_WantedFinePaid", ply, rec, amount)
    return true, amount
end

--- Аннулирование штрафа сотрудником (по правам розыска).
function F.Cancel(actor, id, reason)
    local rec = F.ByID(id)
    if not rec then return false, "Штраф не найден" end
    if rec.status == "cancelled" then return false, "Штраф уже аннулирован" end

    rec.status = "cancelled"
    rec.closed = os.time()
    rec.reason = rec.reason .. " | Аннулирован: " .. tostring(reason or "без причины"):sub(1, 120)
    F.Save()

    local tPly = findPlayerByKey(rec.target)
    if IsValid(tPly) then
        notify(tPly, ("Штраф №%d аннулирован (%s)."):format(rec.id, tostring(reason or "решение органа")), 120, 220, 140)
    end

    hook.Run("GRM_WantedFineCancelled", actor, rec)
    return true
end

-----------------------------------------------------------------------
-- Интеграция: статья каталога → штраф
-----------------------------------------------------------------------
hook.Add("GRM_WantedChargeAdded", "GRM_WantedFines_AutoIssue", function(issuer, target, charge, record)
    if not F.Config.AutoFromCharge then return end
    if not istable(charge) then return end
    local fine = math.floor(tonumber(charge.fine) or 0)
    if fine <= 0 then return end

    local tKey = charKey(target ~= nil and target or (record and record.sid))
    if tKey == "" and record then tKey = charKey(record.sid or "") end
    if tKey == "" then return end

    F.Issue(issuer, tKey, fine,
        ("Статья %s — %s"):format(tostring(charge.code or "?"), tostring(charge.title or "?")), {
            article      = charge.id,
            jurisdiction = charge.jurisdiction or (record and record.jurisdiction) or "civil",
            targetName   = record and record.name or nil,
        })
end)

-----------------------------------------------------------------------
-- Интеграция: /fine (E.Fine) → зеркало в реестре
-----------------------------------------------------------------------
hook.Add("GRM_FineIssued", "GRM_WantedFines_Mirror", function(issuer, target, issued, reason)
    if not F.Config.MirrorEconomyFines then return end
    if not (IsValid(target) and target:IsPlayer()) then return end
    if (tonumber(issued) or 0) <= 0 then return end

    F.Issue(issuer, target, issued, reason ~= "" and reason or "Штраф на месте", {
        status       = "paid",          -- деньги уже списаны экономикой
        jurisdiction = F.JurisdictionOf(target),
    })
end)

-----------------------------------------------------------------------
-- Старт
-----------------------------------------------------------------------
grmBootStart("GRM_WantedFines_Load", "normal", function() F.Load() end)
if GRM and GRM.Wanted then F.Load() end

print("[GRM Wanted Fines] v" .. F.Version .. " загружен, записей: " .. #F.List)
