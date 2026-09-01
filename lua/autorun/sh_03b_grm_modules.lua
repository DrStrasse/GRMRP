--[[--------------------------------------------------------------------
    GRM Modules v1.0.0 — реестр модулей и общая шина обновлений
    (заказ владельца 22.08: «все модули должны знать друг друга»).

    ПРОБЛЕМА, КОТОРУЮ ЭТО ЗАКРЫВАЕТ. Модулей на сервере под сотню, и каждый
    жил сам по себе: свои проверки прав, свои снимки для окон, своё
    представление о том, когда что-то изменилось. Отсюда классика: право
    выдали — компьютер об этом не узнал; сменил должность — терминал
    показывает старое; поменял настройку — обновилось в одном окне из трёх.

    ЧТО ЗДЕСЬ ЕСТЬ.
      1. РЕЕСТР. Модуль объявляет себя один раз:
             GRM.Modules.Register("plates", {
                 label = "Номерные знаки", version = "1.2.0",
                 Refresh = function(ply) ... end,      -- переслать снимок
                 Status  = function() return "..." end,-- строка для отчёта
                 Depends = { "access", "factions" },
             })
         Другой модуль может спросить: GRM.Modules.Get("plates"),
         GRM.Modules.Has("fleet") — и не гадать, загружено ли соседнее.

      2. ШИНА ОБНОВЛЕНИЙ. Любое изменение прав, состава организаций,
         должности или персонажа поднимает ОДНО событие, и реестр сам
         зовёт Refresh у всех, кто на него подписан. Модулю больше не нужно
         знать про чужие хуки: он объявляет, как обновляться, и всё.
         Пачка событий схлопывается (GRM.Perf.Coalesce), обход идёт
         порционно (GRM.Perf.Spread) — правило порционности соблюдено.

      3. ДИАГНОСТИКА. `grm_modules` — что зарегистрировано, версии, статус,
         кто чего ждёт. `grm_modules_refresh [ник]` — принудительно
         разослать снимки. `grm_access_check <право> [ник]` — почему право
         есть или нет (см. sh_03_grm_access.lua).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Modules = GRM.Modules or {}
local M = GRM.Modules
M.Version = "1.0.0"

M.List = M.List or {}       -- id -> { label, version, Refresh, Status, Depends }
M.Order = M.Order or {}

-----------------------------------------------------------------------
-- РЕЕСТР
-----------------------------------------------------------------------

--- Объявить модуль. Повторный вызов обновляет запись (перезагрузка кода).
function M.Register(id, def)
    id = string.lower(string.Trim(tostring(id or "")))
    if id == "" or not istable(def) then return false, "bad_args" end
    if not M.List[id] then M.Order[#M.Order + 1] = id end
    local row = M.List[id] or {}
    row.id = id
    row.label = tostring(def.label or row.label or id)
    row.version = tostring(def.version or row.version or "1.0.0")
    row.Refresh = isfunction(def.Refresh) and def.Refresh or row.Refresh
    row.Status = isfunction(def.Status) and def.Status or row.Status
    row.Depends = istable(def.Depends) and def.Depends or (row.Depends or {})
    row.side = SERVER and "server" or "client"
    M.List[id] = row
    return true
end

function M.Get(id) return M.List[string.lower(tostring(id or ""))] end
function M.Has(id) return M.Get(id) ~= nil end

--- Чего не хватает модулю из объявленных зависимостей (чистая функция).
function M.MissingDeps(id, list)
    list = istable(list) and list or M.List
    local row = istable(list[id]) and list[id] or nil
    if not row then return { id } end
    local out = {}
    for _, dep in ipairs(row.Depends or {}) do
        if not list[string.lower(tostring(dep))] then out[#out + 1] = tostring(dep) end
    end
    return out
end

--- Полный отчёт по реестру (используется командой и стендом).
function M.Report()
    local rows = {}
    for _, id in ipairs(M.Order) do
        local row = M.List[id]
        if row then
            local status = ""
            if isfunction(row.Status) then
                local ok, text = pcall(row.Status)
                status = ok and tostring(text or "") or ("ошибка: " .. tostring(text))
            end
            rows[#rows + 1] = {
                id = id, label = row.label, version = row.version,
                refresh = isfunction(row.Refresh),
                status = status, missing = M.MissingDeps(id),
            }
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

-----------------------------------------------------------------------
-- ШИНА ОБНОВЛЕНИЙ
-----------------------------------------------------------------------

--- Обновить снимки всех модулей (или одного игрока).
--  Порционно: обход реестра идёт через GRM.Perf.Spread.
function M.RefreshAll(ply, reason)
    local ids = {}
    for _, id in ipairs(M.Order) do
        if M.List[id] and isfunction(M.List[id].Refresh) then ids[#ids + 1] = id end
    end
    if #ids == 0 then return 0 end

    local function run(id)
        local row = M.List[id]
        if not row or not isfunction(row.Refresh) then return end
        local ok, err = pcall(row.Refresh, ply, reason)
        if not ok then
            ErrorNoHalt("[GRM Modules] обновление '" .. id .. "': " .. tostring(err) .. "\n")
        end
    end

    if GRM.Perf and GRM.Perf.Spread then
        GRM.Perf.Spread("modules.refresh", ids, run, { chunk = 4, priority = -2 })
    else
        for _, id in ipairs(ids) do run(id) end
    end
    return #ids
end

--[[ Одно событие на все источники изменений. Схлопываем: смена должности
     тянет за собой смену прав и состава, и обновляться трижды незачем. ]]
local function busTick(reason, ply)
    if GRM.Perf and GRM.Perf.Coalesce then
        GRM.Perf.Coalesce("modules.bus", 0.4, function()
            M.RefreshAll(nil, reason)
        end)
    else
        M.RefreshAll(ply, reason)
    end
end
M.Bus = busTick

--- Модули и другие подсистемы могут поднять шину сами.
function M.Changed(reason, ply) busTick(tostring(reason or "manual"), ply) end

for _, event in ipairs({
    "GRM_AccessChanged",          -- права: платформа и организации
    "GRM_AdminDataUpdated",       -- группы и назначения
    "GRM_FPermDataUpdated",       -- доступы организаций
    "GRM_FactionRoleChanged",     -- должность/отдел
    "GRM_FactionsUpdated",        -- состав организаций
    "GRM_CharacterChanged",       -- смена персонажа
    "GRM_DutyChanged",            -- выход на службу и обратно
}) do
    hook.Add(event, "GRM_Modules_Bus", function(...)
        local first = select(1, ...)
        busTick(event, IsValid(first) and first or nil)
    end)
end

-----------------------------------------------------------------------
-- КОМАНДЫ
-----------------------------------------------------------------------
if concommand then
concommand.Add("grm_modules", function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    local function say(t) if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, t) else print(t) end end
    local rows = M.Report()
    say(("[GRM Модули] зарегистрировано: %d (%s)"):format(#rows, SERVER and "сервер" or "клиент"))
    for _, row in ipairs(rows) do
        say(("  %-18s v%-8s %s%s%s"):format(row.id, row.version,
            row.label,
            row.refresh and "  · умеет обновляться" or "",
            #row.missing > 0 and ("  · НЕТ ЗАВИСИМОСТЕЙ: " .. table.concat(row.missing, ", ")) or ""))
        if row.status ~= "" then say("        " .. row.status) end
    end
end)

concommand.Add("grm_modules_refresh", function(ply, _, args)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    local target = nil
    if SERVER and args and args[1] then
        local needle = string.lower(args[1])
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), needle, 1, true) then target = p break end
        end
    end
    local n = M.RefreshAll(target, "command")
    local text = ("[GRM Модули] обновление запрошено у %d модулей%s"):format(n,
        IsValid(target) and (" для " .. target:Nick()) or "")
    if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end)
end

print("[GRM Modules] v" .. M.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")
