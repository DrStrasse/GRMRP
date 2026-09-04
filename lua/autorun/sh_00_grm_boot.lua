--[[--------------------------------------------------------------------
    GRM Boot v1.0.0 — приоритетная загрузка и ленивое исполнение

    ЗАЧЕМ. Раньше вся сборка «просыпалась» одновременно: 42 хука
    InitPostEntity и больше сотни timer.Simple стреляли в первые секунды
    после загрузки карты — чтение десятков JSON с диска, спавн entity,
    сканы карты. Всё это ложилось в несколько тиков и давало провал tickrate
    на старте (и повтор при каждом PostCleanupMap).

    ЧТО ДЕЛАЕТ.
      * Очередь задач с ПРИОРИТЕТАМИ. Планировщик выполняет их не разом, а
        порциями, укладываясь в бюджет времени на тик (grm_boot_budget_ms).
      * ЗАВИСИМОСТИ: задача ждёт, пока выполнятся те, что ей нужны.
      * ЛЕНИВЫЕ задачи (tier "idle") не выполняются вообще, пока их не
        потребуют: по чат-команде, по использованию entity, по первому
        игроку или вручную через GRM.Boot.Ensure.
      * УСЛОВНОЕ ожидание: GRM.Boot.When("имя", проверка, действие) —
        «если условие выполнено, делаем; иначе ждём», дёшево и без спама
        таймеров.

    ПРИОРИТЕТЫ (tier):
        critical  0  — ядро: без него не работает ничего. Выполняется сразу.
        early     1  — то, что должно быть готово ДО входа игроков
                       (двери, перм-энтити, точки спавна).
        normal    2  — обычная игровая логика (экономика, телефоны, ТС).
        late      3  — то, что может подождать (журналы, каталоги, чистки).
        idle      4  — только по требованию (меню, редкие подсистемы).

    API:
        GRM.Boot.Task(id, tier, fn[, opts])   — зарегистрировать задачу
        GRM.Boot.Lazy(id, fn[, opts])         — задача только «по требованию»
        GRM.Boot.Ensure(id)                   — выполнить сейчас (один раз)
        GRM.Boot.Done(id)                     — выполнена ли
        GRM.Boot.When(id, checkFn, fn[, opts])— ждать условия
        GRM.Boot.OnChat(cmds, id)             — команда в чате запускает задачу
        GRM.Boot.OnUseClass(class, id)        — использование entity запускает
        GRM.Boot.OnFirstPlayer(id)            — первый вошедший игрок запускает
        GRM.Boot.Defer(fn[, tier])            — разовое отложенное действие
        GRM.Boot.Status()  / консоль grm_boot_status
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Boot = GRM.Boot or {}
local B = GRM.Boot

B.Version = "1.1.0"

B.TIERS = { critical = 0, early = 1, normal = 2, late = 3, idle = 4 }
B.TIER_NAMES = { [0] = "critical", [1] = "early", [2] = "normal", [3] = "late", [4] = "idle" }

B.Tasks    = B.Tasks or {}      -- id -> task
B.Order    = B.Order or {}      -- порядок регистрации (для стабильной сортировки)
B._running = B._running or false
B._started = B._started or false
B._stats   = B._stats or { total = 0, ran = 0, ms = 0 }

local BUDGET = CreateConVar("grm_boot_budget_ms", SERVER and "2" or "3",
    bit.bor(FCVAR_ARCHIVE), "Сколько миллисекунд за тик GRM тратит на отложенную загрузку")
local VERBOSE = CreateConVar("grm_boot_verbose", "0", bit.bor(FCVAR_ARCHIVE),
    "Печатать каждую выполненную задачу загрузки GRM")

local function tierOf(tier)
    if isnumber(tier) then return math.Clamp(math.floor(tier), 0, 4) end
    return B.TIERS[tostring(tier or "normal")] or B.TIERS.normal
end

local function log(fmt, ...)
    if not VERBOSE:GetBool() then return end
    print("[GRM Boot] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

-----------------------------------------------------------------------
-- Регистрация
-----------------------------------------------------------------------
-- Объявлена заранее: планировщик определяется ниже, но регистрация задач
-- должна уметь его будить.
local ensureRunning

function B.Task(id, tier, fn, opts)
    id = tostring(id or "")
    if id == "" or not isfunction(fn) then return false end
    opts = istable(opts) and opts or {}

    if B.Tasks[id] then
        -- Повторная регистрация (перезагрузка файла) не должна плодить дубли.
        local t = B.Tasks[id]
        t.fn = fn
        t.tier = tierOf(tier)
        t.needs = opts.needs or t.needs
        return true
    end

    local task = {
        id = id,
        tier = tierOf(tier),
        fn = fn,
        needs = istable(opts.needs) and opts.needs or nil,
        realm = opts.realm,          -- "server" / "client" / nil (обе стороны)
        label = opts.label or id,
        state = "waiting",           -- waiting | done | failed | skipped
        ms = 0,
        lazy = tierOf(tier) == B.TIERS.idle,
    }
    B.Tasks[id] = task
    B.Order[#B.Order + 1] = id
    B._stats.total = B._stats.total + 1
    if ensureRunning then ensureRunning() end
    return true
end

function B.Lazy(id, fn, opts)
    opts = istable(opts) and opts or {}
    return B.Task(id, "idle", fn, opts)
end

function B.Done(id)
    local t = B.Tasks[tostring(id or "")]
    return t ~= nil and t.state == "done"
end

local function realmOK(task)
    if not task.realm then return true end
    if task.realm == "server" then return SERVER end
    if task.realm == "client" then return CLIENT end
    return true
end

local function needsReady(task)
    if not task.needs then return true end
    for _, dep in ipairs(task.needs) do
        if not B.Done(dep) then return false end
    end
    return true
end

-- Выполнить задачу немедленно (используется и планировщиком, и Ensure).
local function runTask(task, reason)
    if task.state == "done" or task.state == "skipped" then return false end
    if not realmOK(task) then task.state = "skipped" return false end

    --[[ ЗАЩИТА ОТ ПОВТОРНОГО ВХОДА (найдено стендом 31.08).

         state выставляется ПОСЛЕ выполнения, поэтому пока задача
         работает, она числится "waiting". Если её тело прямо или
         косвенно дёрнет Ensure на саму себя — а так и происходит,
         когда загрузка данных обращается к коду, который эти данные
         запрашивает, — задача запустится второй раз, третий и так до
         переполнения стека.

         Флаг ставим ДО вызова и снимаем в любом исходе: повторный
         вход просто возвращает false, вместо того чтобы уронить
         сервер на старте карты. ]]
    if task.running then return false end
    task.running = true

    local started = SysTime()
    local ok, err = pcall(task.fn)
    local ms = (SysTime() - started) * 1000
    task.running = nil

    task.ms = ms
    task.state = ok and "done" or "failed"
    task.reason = reason
    B._stats.ran = B._stats.ran + 1
    B._stats.ms = B._stats.ms + ms

    if not ok then
        ErrorNoHalt("[GRM Boot] задача '" .. task.id .. "' упала: " .. tostring(err) .. "\n")
    else
        log("%s [%s] %.2f мс (%s)", task.id, B.TIER_NAMES[task.tier], ms, tostring(reason or "очередь"))
    end
    return ok
end

--[[ Выполнить задачу по требованию: «игрок прописал А — выполняем Б».
     Если задача уже выполнена, вызов бесплатный. ]]
function B.Ensure(id, reason)
    local task = B.Tasks[tostring(id or "")]
    if not task then return false end
    if task.state == "done" then return true end
    if not needsReady(task) then
        -- Сначала поднимаем зависимости — тоже по требованию.
        for _, dep in ipairs(task.needs or {}) do B.Ensure(dep, "зависимость " .. id) end
    end
    return runTask(task, reason or "по требованию")
end

-----------------------------------------------------------------------
-- Планировщик: порциями, с бюджетом на тик
-----------------------------------------------------------------------
local function pickNext()
    local best, bestTier = nil, 99
    for i = 1, #B.Order do
        local task = B.Tasks[B.Order[i]]
        if task and task.state == "waiting" and not task.lazy and realmOK(task) and needsReady(task) then
            if task.tier < bestTier then
                best, bestTier = task, task.tier
                if bestTier == 0 then break end
            end
        end
    end
    return best
end

local function pending()
    for i = 1, #B.Order do
        local task = B.Tasks[B.Order[i]]
        if task and task.state == "waiting" and not task.lazy and realmOK(task) then return true end
    end
    return false
end

-- Разбудить планировщик: задачи могут регистрироваться и ПОСЛЕ того, как
-- стартовая очередь была пройдена (перезагрузка модуля, PostCleanupMap,
-- новая подсистема). Без этого они молча оставались бы в состоянии waiting.
local function tick()
    if not B._started then return end
    local budget = math.max(0.25, BUDGET:GetFloat()) / 1000
    local deadline = SysTime() + budget
    local guard = 0
    repeat
        local task = pickNext()
        if not task then break end
        runTask(task, "очередь")
        guard = guard + 1
    until SysTime() >= deadline or guard >= 32

    if not pending() then
        hook.Remove("Think", "GRM_Boot_Tick")
        B._running = false
        local n, ms = B._stats.ran, B._stats.ms
        print(("[GRM Boot] стартовая очередь пройдена: задач %d, суммарно %.1f мс (по %.1f мс/тик)")
            :format(n, ms, BUDGET:GetFloat()))
        hook.Run("GRM_BootFinished")
    end
end

ensureRunning = function()
    if not B._started then return end
    if B._running then return end
    if not pending() then return end
    B._running = true
    hook.Add("Think", "GRM_Boot_Tick", tick)
end
B.EnsureRunning = function() ensureRunning() end

function B.Start()
    if B._started then return end
    B._started = true

    -- critical выполняем сразу, не размазывая: без него остальное бессмысленно.
    for i = 1, #B.Order do
        local task = B.Tasks[B.Order[i]]
        if task and task.tier == B.TIERS.critical and task.state == "waiting" then
            if needsReady(task) then runTask(task, "critical") end
        end
    end

    if pending() then
        B._running = true
        hook.Add("Think", "GRM_Boot_Tick", tick)
    end
end

hook.Add("InitPostEntity", "GRM_Boot_Start", function() timer.Simple(0.1, B.Start) end)
hook.Add("PostCleanupMap", "GRM_Boot_Restart", function()
    -- После очистки карты часть задач нужно выполнить заново — их владельцы
    -- сами помечают себя через GRM.Boot.Reset.
    timer.Simple(0.2, B.Start)
end)
-- Страховка: если InitPostEntity уже прошёл к моменту загрузки файла.
timer.Simple(3, B.Start)

-- v1.1.0: единая точка «сделать на старте карты». Заменяет прямые
-- hook.Add("InitPostEntity"/"Initialize", ...) в модулях: задача попадает в
-- очередь с приоритетом и не бьёт по тикрейту в первые секунды карты.
-- Порядок: critical → early → normal → late; idle — только по требованию.
function B.OnMapStart(id, tier, fn, opts)
    id = "start." .. tostring(id or "")
    if not isfunction(fn) then return false end
    return B.Task(id, tier or "normal", fn, opts)
end

-- Пометить задачу как «нужно выполнить снова» (например, после очистки карты).
function B.Reset(id)
    local task = B.Tasks[tostring(id or "")]
    if not task then return false end
    task.state = "waiting"
    if not task.lazy then ensureRunning() end
    return true
end

-- Разовое отложенное действие без отдельного id.
B._deferSeq = B._deferSeq or 0
function B.Defer(fn, tier)
    if not isfunction(fn) then return false end
    B._deferSeq = B._deferSeq + 1
    local id = "defer." .. B._deferSeq
    B.Task(id, tier or "late", fn, { label = "отложенное действие" })
    ensureRunning()
    return id
end

-----------------------------------------------------------------------
-- Ожидание условия: «если А — делаем Б, иначе ждём»
-----------------------------------------------------------------------
B._waiters = B._waiters or {}

function B.When(id, checkFn, fn, opts)
    id = tostring(id or "")
    if id == "" or not isfunction(checkFn) or not isfunction(fn) then return false end
    opts = istable(opts) and opts or {}
    local interval = math.max(0.1, tonumber(opts.interval) or 0.5)
    local timeout = tonumber(opts.timeout) or 0     -- 0 = ждать бесконечно

    if checkFn() then fn() return true end          -- условие уже выполнено

    local waiter = { id = id, check = checkFn, run = fn, at = 0, started = CurTime(), timeout = timeout, interval = interval }
    B._waiters[id] = waiter

    if not B._waiterHook then
        B._waiterHook = true
        hook.Add("Think", "GRM_Boot_Waiters", function()
            local now = CurTime()
            local any = false
            for wid, w in pairs(B._waiters) do
                any = true
                if now >= w.at then
                    w.at = now + w.interval
                    local okCheck, res = pcall(w.check)
                    if okCheck and res then
                        B._waiters[wid] = nil
                        local okRun, err = pcall(w.run)
                        if not okRun then ErrorNoHalt("[GRM Boot] ожидание '" .. wid .. "': " .. tostring(err) .. "\n") end
                    elseif w.timeout > 0 and (now - w.started) > w.timeout then
                        B._waiters[wid] = nil
                        log("ожидание '%s' истекло по таймауту", wid)
                    end
                end
            end
            if not any then
                hook.Remove("Think", "GRM_Boot_Waiters")
                B._waiterHook = nil
            end
        end)
    end
    return false
end

-----------------------------------------------------------------------
-- Триггеры «по требованию»
-----------------------------------------------------------------------
B._chatTriggers = B._chatTriggers or {}

-- Чат-команда поднимает ленивую подсистему ПЕРЕД тем, как её обработают
-- собственные хуки модуля (наш хук вешается с высоким приоритетом).
function B.OnChat(cmds, id)
    if isstring(cmds) then cmds = { cmds } end
    for _, cmd in ipairs(cmds or {}) do
        B._chatTriggers[string.lower(cmd)] = id
    end
    if not B._chatHook and SERVER then
        B._chatHook = true
        local function check(ply, text)
            local first = string.lower(string.Trim(tostring(text or "")):match("^(%S+)") or "")
            local taskID = B._chatTriggers[first]
            if taskID then B.Ensure(taskID, "команда " .. first) end
        end
        hook.Add("PlayerSay", "GRM_Boot_ChatTrigger", function(ply, text) check(ply, text) end)
        hook.Add("PlayerSay", "GRM_Boot_ChatTriggerEC", function(ply, text, teamSays)
            local pack = { tostring(text or ""), SkipPlayerSay = false }
                if istable(pack) and isstring(pack[1]) then check(ply, pack[1]) end

            if pack.SkipPlayerSay == true then return "" end
        end)
    end
    return true
end

B._useTriggers = B._useTriggers or {}

-- Первое использование entity этого класса поднимает подсистему.
function B.OnUseClass(class, id)
    B._useTriggers[tostring(class)] = id
    if not B._useHook then
        B._useHook = true
        hook.Add("PlayerUse", "GRM_Boot_UseTrigger", function(ply, ent)
            if not IsValid(ent) then return end
            local taskID = B._useTriggers[ent:GetClass()]
            if taskID and not B.Done(taskID) then B.Ensure(taskID, "использование " .. ent:GetClass()) end
        end)
    end
    return true
end

-- Первый вошедший игрок. На пустом сервере такие задачи не выполняются вообще.
B._firstPlayerTasks = B._firstPlayerTasks or {}
function B.OnFirstPlayer(id)
    B._firstPlayerTasks[#B._firstPlayerTasks + 1] = id
    if not B._firstPlayerHook and SERVER then
        B._firstPlayerHook = true
        hook.Add("PlayerInitialSpawn", "GRM_Boot_FirstPlayer", function()
            for _, taskID in ipairs(B._firstPlayerTasks) do B.Ensure(taskID, "первый игрок") end
            B._firstPlayerTasks = {}
            hook.Remove("PlayerInitialSpawn", "GRM_Boot_FirstPlayer")
            B._firstPlayerHook = nil
        end)
    end
    return true
end

-----------------------------------------------------------------------
-- Диагностика
-----------------------------------------------------------------------
function B.Status()
    local rows = {}
    for i = 1, #B.Order do
        local t = B.Tasks[B.Order[i]]
        if t then
            rows[#rows + 1] = {
                id = t.id, tier = B.TIER_NAMES[t.tier], state = t.state,
                ms = t.ms, lazy = t.lazy, reason = t.reason,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.id < b.id
    end)
    return rows, B._stats
end

concommand.Add("grm_boot_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local rows, stats = B.Status()
    local lines = {
        ("[GRM Boot] задач %d, выполнено %d, суммарное время %.1f мс, бюджет %.1f мс/тик")
            :format(stats.total, stats.ran, stats.ms, BUDGET:GetFloat()),
    }
    for _, r in ipairs(rows) do
        lines[#lines + 1] = ("  %-34s %-8s %-9s %6.2f мс%s")
            :format(r.id, r.tier, r.state, r.ms, r.lazy and "  (по требованию)" or "")
    end
    for _, l in ipairs(lines) do
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, l) else print(l) end
    end
    if IsValid(ply) then ply:ChatPrint(lines[1] .. " — подробности в консоли (~)") end
end)

print("[GRM Boot] v" .. B.Version .. ": приоритетная очередь, ленивые задачи, ожидание условий")
