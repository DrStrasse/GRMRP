--[[--------------------------------------------------------------------
    GRM Save v1.0.0 — отложенная и порционная запись на диск

    ЗАЧЕМ. `file.Write` в Garry's Mod синхронный: пока файл пишется, сервер
    стоит. Реестры сборки (документы, розыск, реестр номеров, знакомства,
    журнал госбазы, гаражи) сохранялись «на каждое изменение» — вход игрока,
    выдача номера, каждый запрос по базе. Десяток мелких записей подряд —
    это десяток микрофризов там, где хватило бы одной записи через секунду.

    ЧТО ДЕЛАЕТ.
      • модуль РЕГИСТРИРУЕТ файл и функцию сборки данных один раз;
      • вместо `file.Write` код зовёт `GRM.Save.Mark(id)` — это просто флаг,
        стоит наносекунды;
      • писатель раз в тик берёт ОДИН грязный файл, у которого истекла
        задержка, сериализует и пишет. Больше одной записи за тик не делает;
      • сериализация тоже считается: если она дороже бюджета, файл получает
        увеличенную задержку и пишется реже (крупные реестры);
      • при выключении карты и при смене карты всё сбрасывается на диск.

    API:
        GRM.Save.Register(id, { file = "путь.json", build = fn,
                                delay = 5, priority = 0, backup = "путь.bak" })
        GRM.Save.Mark(id, why)      — пометить «нужно сохранить»
        GRM.Save.Flush(id)          — записать немедленно
        GRM.Save.FlushAll(reason)   — записать всё немедленно
        GRM.Save.Status()           — статистика; консоль grm_save_status
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Save = GRM.Save or {}
local S = GRM.Save
S.Version = "1.0.0"

S.Entries = S.Entries or {}
S.Order = S.Order or {}
S.Stats = S.Stats or { marks = 0, writes = 0, coalesced = 0, ms = 0, maxMs = 0, failures = 0 }

if not CLIENT then
    S.BudgetCvar = S.BudgetCvar or CreateConVar("grm_save_budget_ms", "2", bit.bor(FCVAR_ARCHIVE),
        "Сколько миллисекунд за тик GRM тратит на запись реестров на диск")
    S.VerboseCvar = S.VerboseCvar or CreateConVar("grm_save_verbose", "0", bit.bor(FCVAR_ARCHIVE),
        "Печатать каждую запись реестра на диск")
end

local function budgetMs()
    return S.BudgetCvar and math.max(0.5, S.BudgetCvar:GetFloat()) or 2
end

local function verbose()
    return S.VerboseCvar and S.VerboseCvar:GetBool() or false
end

--- Регистрация файла. Повторный вызов обновляет сборщик, не теряя флаг
--  «грязный» — иначе перезагрузка модуля стирала бы несохранённые правки.
function S.Register(id, def)
    id = tostring(id or "")
    if id == "" or not istable(def) or not isfunction(def.build) then return false end

    local entry = S.Entries[id]
    if not entry then
        entry = { id = id, dirty = false, nextAt = 0, writes = 0, ms = 0 }
        S.Entries[id] = entry
        S.Order[#S.Order + 1] = id
    end
    entry.file = tostring(def.file or entry.file or "")
    entry.build = def.build
    entry.delay = math.Clamp(tonumber(def.delay) or 5, 0, 300)
    entry.priority = tonumber(def.priority) or 0
    entry.backup = def.backup
    entry.label = tostring(def.label or entry.label or id)
    return entry.file ~= ""
end

--- Пометить «нужно сохранить». Дешёвая операция: ни сериализации, ни диска.
function S.Mark(id, why)
    local entry = S.Entries[tostring(id or "")]
    if not entry then return false end
    S.Stats.marks = S.Stats.marks + 1
    if entry.dirty then
        -- Пометили повторно до записи — ровно та экономия, ради которой слой.
        S.Stats.coalesced = S.Stats.coalesced + 1
        entry.why = why or entry.why
        return true
    end
    entry.dirty = true
    entry.why = why
    entry.nextAt = (CurTime and CurTime() or 0) + entry.delay
    return true
end

local function writeEntry(entry, reason)
    if not (entry and isfunction(entry.build)) then return false end
    local started = SysTime and SysTime() or 0

    local okBuild, data = pcall(entry.build)
    if not okBuild or data == nil then
        S.Stats.failures = S.Stats.failures + 1
        ErrorNoHalt("[GRM Save] сборка данных '" .. tostring(entry.id) .. "' упала: " .. tostring(data) .. "\n")
        entry.dirty = false
        return false
    end

    local raw = data
    if istable(data) then
        local okJson, encoded = pcall(util.TableToJSON, data, true)
        if not okJson or not isstring(encoded) then
            S.Stats.failures = S.Stats.failures + 1
            ErrorNoHalt("[GRM Save] сериализация '" .. tostring(entry.id) .. "' упала\n")
            entry.dirty = false
            return false
        end
        raw = encoded
    end

    file.Write(entry.file, raw)
    if isstring(entry.backup) and entry.backup ~= "" then file.Write(entry.backup, raw) end

    -- Проверка чтением обратно: молча потерянные данные хуже фриза.
    local back = file.Read(entry.file, "DATA")
    if not back or back == "" then
        S.Stats.failures = S.Stats.failures + 1
        print("[GRM Save] ВНИМАНИЕ: файл " .. tostring(entry.file) .. " прочитался пустым — проверьте права data/")
    end

    local ms = ((SysTime and SysTime() or 0) - started) * 1000
    entry.dirty = false
    entry.writes = entry.writes + 1
    entry.ms = ms
    entry.lastAt = os.time()
    S.Stats.writes = S.Stats.writes + 1
    S.Stats.ms = S.Stats.ms + ms
    if ms > S.Stats.maxMs then S.Stats.maxMs = ms end

    -- Дорогой реестр не должен писаться часто: увеличиваем его задержку сам,
    -- без правки вызывающего кода.
    if ms > budgetMs() then
        entry.delay = math.min(60, math.max(entry.delay, math.ceil(ms / budgetMs()) * 2))
    end

    if verbose() then
        print(("[GRM Save] %s -> %s за %.2f мс (%s)"):format(entry.id, entry.file, ms, tostring(reason or entry.why or "")))
    end
    return true
end

function S.Flush(id, reason)
    local entry = S.Entries[tostring(id or "")]
    if not entry then return false end
    return writeEntry(entry, reason or "вручную")
end

function S.FlushAll(reason)
    local n = 0
    for _, id in ipairs(S.Order) do
        local entry = S.Entries[id]
        if entry and entry.dirty then
            if writeEntry(entry, reason or "сброс") then n = n + 1 end
        end
    end
    return n
end

--- Кто следующий на запись: самый «просроченный» с учётом приоритета.
local function pickEntry(now)
    local best
    for _, id in ipairs(S.Order) do
        local entry = S.Entries[id]
        if entry and entry.dirty and now >= (entry.nextAt or 0) then
            if not best then
                best = entry
            elseif (entry.priority or 0) > (best.priority or 0) then
                best = entry
            elseif (entry.priority or 0) == (best.priority or 0) and (entry.nextAt or 0) < (best.nextAt or 0) then
                best = entry
            end
        end
    end
    return best
end

--- Писатель. Одна запись за тик — этого хватает (реестров единицы), зато
--  сервер никогда не пишет два файла подряд в одном кадре.
function S.Tick(now)
    now = now or (CurTime and CurTime() or 0)
    local entry = pickEntry(now)
    if not entry then return false end
    writeEntry(entry, "очередь")
    return true
end

function S.Status()
    local rows = {}
    for _, id in ipairs(S.Order) do
        local entry = S.Entries[id]
        if entry then
            rows[#rows + 1] = { id = id, file = entry.file, dirty = entry.dirty == true,
                delay = entry.delay, writes = entry.writes, ms = entry.ms, label = entry.label }
        end
    end
    return rows, S.Stats
end

--[[ ВНЕШНИЕ ХРАНИЛИЩА (заказ владельца 22.08: «чтобы ничего не исчезало»).
     Часть модулей пишет на диск напрямую, а не через GRM.Save — но у них
     есть публичные Save*-функции. Здесь на выключение/смену карты мы
     вызываем их через pcall В ДОПОЛНЕНИЕ к очереди GRM.Save. Если модуль
     не загружен или функция изменилась — pcall молча пропустит. ]]
function S.FlushExternal(reason)
    local calls = {
        { "GRM.VehicleDealer.SaveAllDealers", {} },
        { "GRM.VehicleDealer.SaveGarages", {} },
        { "GRM.Garage.Save", { reason or "страховка" } },
        { "GRM.Documents.SaveRegistry", { reason or "страховка" } },
        { "GRM.Documents.SaveTemplates", { reason or "страховка" } },
        { "GRM.Services.SaveServices", {} },
        { "GRM.Services.SaveInvoices", {} },
        { "GRM.Vendor.SaveMapVendors", {} },
        { "GRM.Wanted.Fines.Save", {} },
        { "GRM.Mining.SavePrices", { reason or "страховка" } },
        { "GRM.Broadcast.SaveCfg", {} },
        { "GRM.News.SaveData", {} },
    }
    local n = 0
    for _, call in ipairs(calls) do
        local path, args = call[1], call[2]
        local fn = nil
        local cur = _G
        for part in string.gmatch(path, "[^.]+") do
            cur = istable(cur) and cur[part] or nil
            if cur == nil then break end
        end
        fn = isfunction(cur) and cur or nil
        if fn then
            local ok = pcall(fn, unpack(args or {}))
            if ok then n = n + 1 end
        end
    end
    return n
end

if SERVER then
    timer.Create("GRM_Save_Tick", 1, 0, function() S.Tick(CurTime()) end)

    hook.Add("ShutDown", "GRM_Save_FlushAll", function()
        S.FlushAll("выключение")
        S.FlushExternal("выключение")
    end)
    hook.Add("PreCleanupMap", "GRM_Save_FlushMap", function()
        S.FlushAll("очистка карты")
        S.FlushExternal("очистка карты")
    end)

    concommand.Add("grm_save_status", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        local rows, stats = S.Status()
        out(("[GRM Save] реестров: %d · записей: %d · сэкономлено записей: %d · пик %.2f мс")
            :format(#rows, stats.writes, stats.coalesced, stats.maxMs))
        for _, row in ipairs(rows) do
            out(("  %-26s %-38s %s задержка %ds, записей %d, последняя %.2f мс")
                :format(row.id, row.file, row.dirty and "ГРЯЗНЫЙ" or "чистый", row.delay, row.writes, row.ms))
        end
    end)

    concommand.Add("grm_save_flush", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local n = S.FlushAll("команда")
        local msg = "[GRM Save] записано файлов: " .. n
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end)

    print("[GRM Save] v" .. S.Version .. " loaded")
end
