--[[--------------------------------------------------------------------
    GRM Wanted Exchange v1.0.0 — межведомственный обмен сведениями.

    Требование: «возможность передачи сведений о розыске из одной
    структуры в другую и обратно».

    Реализовано три операции:
      • TRANSFER — передать дело соседнему ведомству. Юрисдикция записи
        меняется (civil ↔ military), в деле остаётся отметка о передаче;
        обратная передача возможна тем же способом.
      • SHARE    — поделиться копией сведений без смены юрисдикции: дело
        остаётся у хозяина, но становится видимым второй структуре
        (список record.shared).
      • REQUEST  — запросить дело у соседей: заявка ложится в очередь,
        сотрудник другой структуры её принимает или отклоняет.

    Данные: data/grm_wanted/exchange.json
        {
          version = 1,
          requests = { {id, from, fromName, fromJur, targetKey, targetName,
                        toJur, kind, note, status, created, closed,
                        closedBy, closedName} },
          log      = { {t, kind, actor, actorName, targetKey, detail, note} }
        }
      status: "pending" | "accepted" | "declined" | "cancelled"
      kind:   "transfer" | "share" | "request"

    Миграция: файла может не быть (новая установка) — создаётся пустой.
    Записи розыска старого формата не имеют полей jurisdictionHistory и
    shared; они дописываются лениво, при первой же операции.
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
GRM.Wanted.Exchange = GRM.Wanted.Exchange or {}

local X = GRM.Wanted.Exchange
X.Version = "1.0.0"

local DIR  = "grm_wanted"
local FILE = "grm_wanted/exchange.json"

X.Requests = X.Requests or {}
X.Journal  = X.Journal or {}
X._nextID  = X._nextID or 1

X.Config = X.Config or {
    MaxRequests = 300,   -- потолок заявок в файле
    MaxLog      = 400,   -- потолок журнала
    Cooldown    = 2,     -- сек между операциями одного сотрудника
}

-----------------------------------------------------------------------
-- Утилиты (те же безопасные обёртки, что и в остальных модулях)
-----------------------------------------------------------------------
local function ensure()
    if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
end

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt or "", false, true)
    return (ok and istable(t)) and t or nil
end

--- Атомарная по смыслу запись: результат сверяется чтением.
local function write(path, data)
    local ok, s = pcall(util.TableToJSON, data, true)
    if not ok or not isstring(s) then
        ErrorNoHalt("[GRM Exchange] не удалось сериализовать " .. tostring(path) .. "\n")
        return false
    end
    file.Write(path, s)
    return file.Read(path, "DATA") == s
end

-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
X.CharKey = charKey

local function notify(ply, msg, r, g, b)
    if not IsValid(ply) then return end
    if GRM.Notify then GRM.Notify(ply, msg, r or 110, g or 220, b or 150)
    else ply:ChatPrint("[Обмен] " .. tostring(msg)) end
end

local function otherJur(j) return j == "military" and "civil" or "military" end
X.Other = otherJur

local function jurName(j) return j == "military" and "Полевая жандармерия" or "Полиция Порядка" end
X.JurName = jurName

-----------------------------------------------------------------------
-- Хранение
-----------------------------------------------------------------------
local function normalizeRequest(r, index)
    if not istable(r) then return end
    local key = charKey(r.targetKey)
    if key == "" then return end
    local kind = r.kind
    if kind ~= "transfer" and kind ~= "share" and kind ~= "request" then kind = "request" end
    local status = r.status
    if status ~= "pending" and status ~= "accepted" and status ~= "declined" and status ~= "cancelled" then
        status = "pending"
    end
    return {
        id         = math.floor(tonumber(r.id) or index or 0),
        from       = tostring(r.from or ""),
        fromName   = tostring(r.fromName or "?"):sub(1, 64),
        fromJur    = r.fromJur == "military" and "military" or "civil",
        targetKey  = key,
        targetName = tostring(r.targetName or key):sub(1, 64),
        toJur      = r.toJur == "military" and "military" or "civil",
        kind       = kind,
        note       = tostring(r.note or ""):sub(1, 200),
        status     = status,
        created    = math.floor(tonumber(r.created) or os.time()),
        closed     = math.floor(tonumber(r.closed) or 0),
        closedBy   = tostring(r.closedBy or ""),
        closedName = tostring(r.closedName or ""):sub(1, 64),
    }
end

function X.Load()
    ensure()
    X.Requests, X.Journal, X._nextID = {}, {}, 1
    if not file.Exists(FILE, "DATA") then return true end

    local raw = file.Read(FILE, "DATA")
    local t = jsonT(raw)
    if not t then
        -- повреждённый файл не затираем: сохраняем копию
        local bak = FILE .. ".corrupt." .. os.time()
        if raw then file.Write(bak, raw) end
        ErrorNoHalt("[GRM Exchange] exchange.json повреждён, копия: " .. bak .. "\n")
        return false
    end

    local maxID = 0
    for i, r in ipairs(istable(t.requests) and t.requests or {}) do
        local n = normalizeRequest(r, i)
        if n then
            X.Requests[#X.Requests + 1] = n
            if n.id > maxID then maxID = n.id end
        end
    end
    for _, e in ipairs(istable(t.log) and t.log or {}) do
        if istable(e) then X.Journal[#X.Journal + 1] = e end
    end
    X._nextID = maxID + 1
    return true
end

function X.Save()
    ensure()
    while #X.Requests > (X.Config.MaxRequests or 300) do table.remove(X.Requests, 1) end
    while #X.Journal > (X.Config.MaxLog or 400) do table.remove(X.Journal, 1) end
    return write(FILE, { version = 1, requests = X.Requests, log = X.Journal })
end

--- Журнал операций (вызывается и из модуля ориентировок).
function X.Log(kind, actor, targetKey, detail, note)
    X.Journal[#X.Journal + 1] = {
        t          = os.time(),
        kind       = tostring(kind or "?"),
        actor      = IsValid(actor) and charKey(actor) or "system",
        actorName  = IsValid(actor) and actor:Nick() or "Система",
        targetKey  = charKey(targetKey),
        detail     = tostring(detail or ""):sub(1, 96),
        note       = tostring(note or ""):sub(1, 160),
    }
    while #X.Journal > (X.Config.MaxLog or 400) do table.remove(X.Journal, 1) end
end
-----------------------------------------------------------------------
-- Права
-----------------------------------------------------------------------
--- Юрисдикция сотрудника (по его собственной фракции).
function X.JurisdictionOf(ply)
    local W = GRM.Wanted
    if W and isfunction(W.JurisdictionOfPlayer) then return W.JurisdictionOfPlayer(ply) end
    return "civil"
end

--- Может ли сотрудник инициировать операции обмена.
function X.CanOperate(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false, "Нет игрока" end
    if ply:IsSuperAdmin() then return true end
    local W = GRM.Wanted
    if W and isfunction(W.CanEdit) and W.CanEdit(ply) then return true end
    local T = GRM.CompTerminal
    if T and isfunction(T.CanEdit) then
        if T.CanEdit(ply, "civil") or T.CanEdit(ply, "military") then return true end
    end
    return false, "У вас нет прав на работу с базой розыска"
end

--- Может ли сотрудник принимать решение по заявке к своей структуре.
function X.CanResolve(ply, req)
    if not istable(req) then return false end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    local SS = GRM.SpecialService
    if SS and isfunction(SS.IsAgent) and SS.IsAgent(ply) then return true end

    local ok = X.CanOperate(ply)
    if not ok then return false end

    local W = GRM.Wanted
    if W and isfunction(W.CanUseJurisdiction) then
        return W.CanUseJurisdiction(ply, req.toJur)
    end
    return X.JurisdictionOf(ply) == req.toJur
end

local lastAct = {}
local function throttled(ply)
    local k = IsValid(ply) and ply:SteamID64() or "?"
    local now = CurTime()
    if now - (lastAct[k] or -1000) < (X.Config.Cooldown or 2) then return true end
    lastAct[k] = now
    return false
end

-----------------------------------------------------------------------
-- Операции
-----------------------------------------------------------------------
local function findRecord(key)
    local W = GRM.Wanted
    if not (W and istable(W.Records)) then return nil end
    return W.Records[charKey(key)]
end

--- Немедленная передача дела соседнему ведомству.
-- Юрисдикция записи и всех её статей меняется; в деле остаётся след.
-- @return успех, сообщение
function X.Transfer(actor, key, toJur, note)
    local okOp, why = X.CanOperate(actor)
    if not okOp then return false, why end
    if throttled(actor) then return false, "Слишком часто" end

    key = charKey(key)
    local rec = findRecord(key)
    if not rec then return false, "Запись розыска не найдена" end

    toJur = toJur == "military" and "military" or "civil"
    local fromJur = rec.jurisdiction == "military" and "military" or "civil"
    if fromJur == toJur then return false, "Дело уже ведёт " .. jurName(toJur) end

    -- Передавать может только та структура, которая ведёт дело
    -- (или тот, кому разрешены обе ветки).
    local W = GRM.Wanted
    if not (IsValid(actor) and actor:IsSuperAdmin()) then
        if W and isfunction(W.CanUseJurisdiction) and not W.CanUseJurisdiction(actor, fromJur) then
            return false, "Дело ведёт " .. jurName(fromJur) .. " — передать его может только оно"
        end
    end

    rec.jurisdiction = toJur
    for _, c in ipairs(rec.reasons or {}) do
        if istable(c) then c.jurisdiction = toJur end
    end

    rec.transfers = istable(rec.transfers) and rec.transfers or {}
    rec.transfers[#rec.transfers + 1] = {
        t = os.time(),
        from = fromJur, to = toJur,
        by = IsValid(actor) and charKey(actor) or "system",
        byNick = IsValid(actor) and actor:Nick() or "Система",
        note = tostring(note or ""):sub(1, 160),
    }
    while #rec.transfers > 20 do table.remove(rec.transfers, 1) end

    -- бывший хозяин сохраняет доступ к сведениям
    rec.shared = istable(rec.shared) and rec.shared or {}
    rec.shared[fromJur] = true
    rec.shared[toJur] = nil
    rec.updated = os.time()

    if W and isfunction(W.Save) then W.Save() end
    X.Log("transfer", actor, key, fromJur .. "→" .. toJur, note)
    X.Save()

    hook.Run("GRM_WantedTransferred", actor, key, fromJur, toJur, note)

    -- Уведомляем эфир: соседи должны узнать о новом деле.
    local BL = GRM.Wanted.Bulletins
    if BL and isfunction(BL.Raw) then
        local who = IsValid(actor) and actor:Nick() or "Система"
        BL.Raw("dep", actor, ("ПЕРЕДАЧА ДЕЛА: %s — из «%s» в «%s» (%s)%s")
            :format(tostring(rec.name or key), jurName(fromJur), jurName(toJur), who,
                    (note and note ~= "") and (" • " .. note) or ""), toJur)
    end

    return true, ("Дело «%s» передано: %s → %s"):format(tostring(rec.name or key), jurName(fromJur), jurName(toJur))
end

--- Поделиться сведениями без смены юрисдикции.
function X.Share(actor, key, toJur, note)
    local okOp, why = X.CanOperate(actor)
    if not okOp then return false, why end
    if throttled(actor) then return false, "Слишком часто" end

    key = charKey(key)
    local rec = findRecord(key)
    if not rec then return false, "Запись розыска не найдена" end

    toJur = toJur == "military" and "military" or "civil"
    local own = rec.jurisdiction == "military" and "military" or "civil"
    if toJur == own then return false, "Это и есть ведущая структура" end

    rec.shared = istable(rec.shared) and rec.shared or {}
    if rec.shared[toJur] then return false, "Сведения уже переданы " .. jurName(toJur) end
    rec.shared[toJur] = true
    rec.updated = os.time()

    local W = GRM.Wanted
    if W and isfunction(W.Save) then W.Save() end
    X.Log("share", actor, key, own .. "→" .. toJur, note)
    X.Save()

    hook.Run("GRM_WantedShared", actor, key, own, toJur, note)

    local BL = GRM.Wanted.Bulletins
    if BL and isfunction(BL.Raw) then
        BL.Raw("dep", actor, ("СВЕДЕНИЯ ПЕРЕДАНЫ: дело «%s» доступно структуре «%s»")
            :format(tostring(rec.name or key), jurName(toJur)), own)
    end

    return true, ("Сведения по «%s» переданы: %s"):format(tostring(rec.name or key), jurName(toJur))
end

--- Отозвать доступ, выданный через Share.
function X.Unshare(actor, key, toJur)
    local okOp, why = X.CanOperate(actor)
    if not okOp then return false, why end
    key = charKey(key)
    local rec = findRecord(key)
    if not rec then return false, "Запись розыска не найдена" end
    toJur = toJur == "military" and "military" or "civil"
    if not (istable(rec.shared) and rec.shared[toJur]) then return false, "Доступ и так не выдан" end
    rec.shared[toJur] = nil
    rec.updated = os.time()
    local W = GRM.Wanted
    if W and isfunction(W.Save) then W.Save() end
    X.Log("unshare", actor, key, toJur)
    X.Save()
    return true, "Доступ отозван: " .. jurName(toJur)
end

--- Заявка соседнему ведомству (передать дело нам / поделиться).
-- @param kind "transfer" (просим передать) | "share" (просим копию)
function X.Request(actor, key, kind, note)
    local okOp, why = X.CanOperate(actor)
    if not okOp then return false, why end
    if throttled(actor) then return false, "Слишком часто" end

    key = charKey(key)
    local rec = findRecord(key)
    if not rec then return false, "Запись розыска не найдена" end

    kind = kind == "share" and "share" or "transfer"
    local myJur  = X.JurisdictionOf(actor)
    local ownJur = rec.jurisdiction == "military" and "military" or "civil"
    if ownJur == myJur then return false, "Дело и так ведёт ваша структура" end

    for _, r in ipairs(X.Requests) do
        if r.status == "pending" and r.targetKey == key and r.toJur == myJur and r.kind == kind then
            return false, ("Заявка №%d по этому делу уже подана"):format(r.id)
        end
    end

    local req = {
        id         = X._nextID,
        from       = IsValid(actor) and charKey(actor) or "system",
        fromName   = IsValid(actor) and actor:Nick() or "Система",
        fromJur    = myJur,
        targetKey  = key,
        targetName = tostring(rec.name or key):sub(1, 64),
        toJur      = myJur,          -- куда просим передать дело
        kind       = kind,
        note       = tostring(note or ""):sub(1, 200),
        status     = "pending",
        created    = os.time(),
        closed     = 0, closedBy = "", closedName = "",
    }
    X._nextID = X._nextID + 1
    X.Requests[#X.Requests + 1] = req
    X.Log("request", actor, key, kind .. " ← " .. ownJur, note)
    X.Save()

    hook.Run("GRM_WantedExchangeRequested", actor, req)

    -- Заявка должна быть услышана: сообщаем на волну департаментов.
    local BL = GRM.Wanted.Bulletins
    if BL and isfunction(BL.Raw) then
        BL.Raw("dep", actor, ("ЗАПРОС №%d: %s просит %s по делу «%s» (ведёт %s)%s")
            :format(req.id, jurName(myJur),
                    kind == "share" and "копию сведений" or "передачу дела",
                    req.targetName, jurName(ownJur),
                    note and note ~= "" and (" • " .. note) or ""), ownJur)
    end

    return true, ("Заявка №%d подана"):format(req.id)
end

function X.ByID(id)
    id = math.floor(tonumber(id) or 0)
    for _, r in ipairs(X.Requests) do
        if r.id == id then return r end
    end
end

--- Список заявок: pending для указанной юрисдикции-владельца.
function X.Pending(jurisdiction)
    local out = {}
    for _, r in ipairs(X.Requests) do
        if r.status == "pending" then
            -- заявка адресована той структуре, которая ведёт дело
            local rec = findRecord(r.targetKey)
            local ownJur = rec and (rec.jurisdiction == "military" and "military" or "civil") or otherJur(r.toJur)
            if jurisdiction == "all" or ownJur == jurisdiction then
                out[#out + 1] = r
            end
        end
    end
    table.sort(out, function(a, b) return a.created > b.created end)
    return out
end

--- Принять заявку: выполняется передача или расшаривание.
function X.Accept(actor, id, note)
    local req = X.ByID(id)
    if not req then return false, "Заявка не найдена" end
    if req.status ~= "pending" then return false, "Заявка уже закрыта" end

    local rec = findRecord(req.targetKey)
    if not rec then return false, "Запись розыска больше не существует" end
    local ownJur = rec.jurisdiction == "military" and "military" or "civil"

    -- решает та структура, которая ведёт дело
    if not (IsValid(actor) and actor:IsSuperAdmin()) then
        local W = GRM.Wanted
        if W and isfunction(W.CanUseJurisdiction) and not W.CanUseJurisdiction(actor, ownJur) then
            return false, "Решение по заявке принимает " .. jurName(ownJur)
        end
        local okOp, why = X.CanOperate(actor)
        if not okOp then return false, why end
    end

    local ok, msg
    if req.kind == "share" then
        ok, msg = X.Share(actor, req.targetKey, req.toJur, "по заявке №" .. req.id)
    else
        ok, msg = X.Transfer(actor, req.targetKey, req.toJur, "по заявке №" .. req.id)
    end
    if not ok then return false, msg end

    req.status = "accepted"
    req.closed = os.time()
    req.closedBy = IsValid(actor) and charKey(actor) or "system"
    req.closedName = IsValid(actor) and actor:Nick() or "Система"
    if note and note ~= "" then req.note = (req.note ~= "" and (req.note .. " | ") or "") .. tostring(note):sub(1, 120) end
    X.Log("accept", actor, req.targetKey, "заявка №" .. req.id, note)
    X.Save()

    -- уведомляем заявителя, если он в сети
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and charKey(p) == req.from then
            notify(p, ("Заявка №%d удовлетворена: %s"):format(req.id, msg), 110, 220, 150)
        end
    end

    hook.Run("GRM_WantedExchangeResolved", actor, req, true)
    return true, ("Заявка №%d удовлетворена"):format(req.id)
end

--- Отклонить заявку.
function X.Decline(actor, id, note)
    local req = X.ByID(id)
    if not req then return false, "Заявка не найдена" end
    if req.status ~= "pending" then return false, "Заявка уже закрыта" end

    local rec = findRecord(req.targetKey)
    local ownJur = rec and (rec.jurisdiction == "military" and "military" or "civil") or otherJur(req.toJur)

    if not (IsValid(actor) and actor:IsSuperAdmin()) then
        local W = GRM.Wanted
        if W and isfunction(W.CanUseJurisdiction) and not W.CanUseJurisdiction(actor, ownJur) then
            return false, "Решение по заявке принимает " .. jurName(ownJur)
        end
        local okOp, why = X.CanOperate(actor)
        if not okOp then return false, why end
    end

    req.status = "declined"
    req.closed = os.time()
    req.closedBy = IsValid(actor) and charKey(actor) or "system"
    req.closedName = IsValid(actor) and actor:Nick() or "Система"
    if note and note ~= "" then req.note = (req.note ~= "" and (req.note .. " | ") or "") .. tostring(note):sub(1, 120) end
    X.Log("decline", actor, req.targetKey, "заявка №" .. req.id, note)
    X.Save()

    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and charKey(p) == req.from then
            notify(p, ("Заявка №%d отклонена%s"):format(req.id, note and note ~= "" and (": " .. note) or ""), 250, 170, 110)
        end
    end

    hook.Run("GRM_WantedExchangeResolved", actor, req, false)
    return true, ("Заявка №%d отклонена"):format(req.id)
end

--- Отозвать собственную заявку.
function X.Cancel(actor, id)
    local req = X.ByID(id)
    if not req then return false, "Заявка не найдена" end
    if req.status ~= "pending" then return false, "Заявка уже закрыта" end
    if not (IsValid(actor) and (actor:IsSuperAdmin() or charKey(actor) == req.from)) then
        return false, "Отозвать заявку может только её автор"
    end
    req.status = "cancelled"
    req.closed = os.time()
    req.closedBy = IsValid(actor) and charKey(actor) or "system"
    req.closedName = IsValid(actor) and actor:Nick() or "Система"
    X.Log("cancel", actor, req.targetKey, "заявка №" .. req.id)
    X.Save()
    return true, ("Заявка №%d отозвана"):format(req.id)
end

--- Видна ли запись указанной структуре: своя юрисдикция либо
-- переданная копия (record.shared).
function X.VisibleTo(rec, jurisdiction)
    if not istable(rec) then return false end
    if jurisdiction == "all" then return true end
    local own = rec.jurisdiction == "military" and "military" or "civil"
    if own == jurisdiction then return true end
    return istable(rec.shared) and rec.shared[jurisdiction] == true
end

-----------------------------------------------------------------------
-- Чат-команды
-----------------------------------------------------------------------
local function resolveTarget(arg)
    local BL = GRM.Wanted.Bulletins
    if BL and isfunction(BL.ResolveTarget) then return BL.ResolveTarget(arg) end
    return charKey(arg)
end

local function reply(ply, ok, text)
    notify(ply, tostring(text), ok and 110 or 250, ok and 220 or 110, ok and 150 or 110)
end

--- /case_transfer <цель> [примечание]
function X.CmdTransfer(ply, args)
    local key = resolveTarget(args[1])
    if key == "" then return reply(ply, false, "Использование: /case_transfer <игрок> [примечание]") end
    local rec = findRecord(key)
    if not rec then return reply(ply, false, "Запись розыска не найдена") end
    local to = otherJur(rec.jurisdiction == "military" and "military" or "civil")
    local ok, msg = X.Transfer(ply, key, to, table.concat(args, " ", 2))
    reply(ply, ok, msg)
end

--- /case_share <цель> [примечание]
function X.CmdShare(ply, args)
    local key = resolveTarget(args[1])
    if key == "" then return reply(ply, false, "Использование: /case_share <игрок> [примечание]") end
    local rec = findRecord(key)
    if not rec then return reply(ply, false, "Запись розыска не найдена") end
    local to = otherJur(rec.jurisdiction == "military" and "military" or "civil")
    local ok, msg = X.Share(ply, key, to, table.concat(args, " ", 2))
    reply(ply, ok, msg)
end

--- /case_request <цель> [transfer|share] [примечание]
function X.CmdRequest(ply, args)
    local key = resolveTarget(args[1])
    if key == "" then return reply(ply, false, "Использование: /case_request <игрок> [transfer|share] [примечание]") end
    local kind = string.lower(tostring(args[2] or "transfer"))
    local noteStart = (kind == "transfer" or kind == "share") and 3 or 2
    local ok, msg = X.Request(ply, key, kind, table.concat(args, " ", noteStart))
    reply(ply, ok, msg)
end

--- /case_requests — список открытых заявок для моей структуры.
function X.CmdList(ply)
    local okOp, why = X.CanOperate(ply)
    if not okOp then return reply(ply, false, why) end
    local myJur = X.JurisdictionOf(ply)
    if IsValid(ply) and ply:IsSuperAdmin() then myJur = "all" end

    local list = X.Pending(myJur)
    if #list == 0 then return reply(ply, true, "Открытых заявок нет") end

    ply:ChatPrint("── Заявки на передачу сведений ──")
    for _, r in ipairs(list) do
        ply:ChatPrint(("#%d  %s  ←  %s  [%s]  %s")
            :format(r.id, r.targetName, jurName(r.fromJur),
                    r.kind == "share" and "копия" or "передача",
                    r.note ~= "" and r.note or ""))
    end
    ply:ChatPrint("Принять: /case_accept <номер>   •   Отклонить: /case_decline <номер> [причина]")
end

--- /case_accept <номер> [примечание]
function X.CmdAccept(ply, args)
    local id = tonumber(args[1])
    if not id then return reply(ply, false, "Использование: /case_accept <номер заявки>") end
    local ok, msg = X.Accept(ply, id, table.concat(args, " ", 2))
    reply(ply, ok, msg)
end

--- /case_decline <номер> [причина]
function X.CmdDecline(ply, args)
    local id = tonumber(args[1])
    if not id then return reply(ply, false, "Использование: /case_decline <номер заявки> [причина]") end
    local ok, msg = X.Decline(ply, id, table.concat(args, " ", 2))
    reply(ply, ok, msg)
end

--- /case_cancel <номер>
function X.CmdCancel(ply, args)
    local id = tonumber(args[1])
    if not id then return reply(ply, false, "Использование: /case_cancel <номер заявки>") end
    local ok, msg = X.Cancel(ply, id)
    reply(ply, ok, msg)
end

local HANDLERS = {
    ["/case_transfer"] = X.CmdTransfer,
    ["/передать_дело"] = X.CmdTransfer,
    ["/case_share"]    = X.CmdShare,
    ["/case_request"]  = X.CmdRequest,
    ["/case_requests"] = function(ply) X.CmdList(ply) end,
    ["/case_accept"]   = X.CmdAccept,
    ["/case_decline"]  = X.CmdDecline,
    ["/case_cancel"]   = X.CmdCancel,
}
X.Handlers = HANDLERS

local function dispatch(ply, text)
    if not isstring(text) then return false end
    local args = string.Explode(" ", string.Trim(text))
    local fn = HANDLERS[string.lower(args[1] or "")]
    if not fn then return false end
    table.remove(args, 1)
    local ok, e = pcall(fn, ply, args)
    if not ok then
        ErrorNoHalt("[GRM Exchange] " .. tostring(e) .. "\n")
        reply(ply, false, "Внутренняя ошибка команды")
    end
    return true
end
X.Dispatch = dispatch

hook.Add("PlayerSayTransform", "GRM_Exchange_Transform", function(ply, pack)
    if not istable(pack) or not isstring(pack[1]) then return end
    if dispatch(ply, pack[1]) then
        pack[1] = ""
        pack.SkipPlayerSay = true
    end
end)

hook.Add("PlayerSay", "GRM_Exchange_Fallback", function(ply, text)
    if dispatch(ply, text) then return "" end
end)

local function con(name, fn)
    concommand.Add(name, function(ply, _, args) if IsValid(ply) then fn(ply, args or {}) end end)
end
con("grm_case_transfer", X.CmdTransfer)
con("grm_case_share",    X.CmdShare)
con("grm_case_request",  X.CmdRequest)
con("grm_case_requests", function(ply) X.CmdList(ply) end)
con("grm_case_accept",   X.CmdAccept)
con("grm_case_decline",  X.CmdDecline)
con("grm_case_cancel",   X.CmdCancel)

X.Load()
print("[GRM Wanted Exchange] v" .. X.Version .. " загружен, заявок: " .. #X.Requests)
