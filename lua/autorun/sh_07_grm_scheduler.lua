--[[--------------------------------------------------------------------
    GRM Scheduler v1.0.0 — единый планировщик ПЕРИОДИЧЕСКИХ задач.

    ЗАПРОС ВЛАДЕЛЬЦА (28.08): «вопрос оптимизации всех новых и всех в
    целом модулей — поэтапность, порционность, выполнение кода по
    приоритету».

    ЧТО УЖЕ БЫЛО И ПОЧЕМУ ЭТОГО МАЛО.
      • GRM.Boot   — приоритеты и бюджет, но только для СТАРТА карты.
      • GRM.Perf   — Queue/Spread с бюджетом кадра, но только для РАЗОВЫХ
                     задач и обходов больших списков.
      • timer.Create — 129 штук по сборке, суммарно ~129 срабатываний в
                     секунду. Каждый живёт сам по себе.

    В ЧЁМ БЕДА ОБЫЧНЫХ ТАЙМЕРОВ.

      1) СОВПАДЕНИЕ ФАЗ. Десяток таймеров с интервалом 1 с, созданных на
         старте карты, срабатывают В ОДНОМ И ТОМ ЖЕ тике — каждую секунду
         сервер получает пик работы вместо ровной нагрузки. У нас таких
         совпадений много: 12 таймеров по 0.5 с, 25 по 1 с, 19 по 2 с.

      2) НЕТ ПРИОРИТЕТА. Сохранение журнала и подсчёт голода одинаково
         важны для timer.Create. При просадке тикрейта выполняется всё
         подряд, включая то, что спокойно подождало бы секунду.

      3) НЕТ БЮДЖЕТА. Если в одном тике совпали пять тяжёлых задач, они
         все отработают целиком — и кадр провалится.

    ЧТО ДЕЛАЕТ ЭТОТ МОДУЛЬ.

      • ОДИН диспетчер вместо россыпи таймеров.
      • РАЗВОДИТ ФАЗЫ: задачи с одинаковым интервалом автоматически
        получают разное смещение старта, поэтому не сходятся в один тик.
      • ПРИОРИТЕТЫ: critical выполняется всегда, low — только когда
        сервер свободен.
      • БЮДЖЕТ ТИКА: за проход тратим не больше отведённого времени,
        остальное переносим на следующий тик. Бюджет сам сжимается при
        просадке кадра (переиспользуем GRM.Perf.BudgetScale).
      • ПОРЦИОННОСТЬ: задача может обрабатывать список по кусочкам,
        сохраняя позицию между тиками.
      • НЕ ЛОМАЕТ СУЩЕСТВУЮЩЕЕ: старые timer.Create продолжают работать.
        Модули переводятся по одному, а не «большим взрывом».

    API:
        GRM.Sched.Every(id, interval, fn, opts)  — периодическая задача
        GRM.Sched.EverySpread(id, interval, listFn, fn, opts) — порционный
                                                    обход списка по кругу
        GRM.Sched.Remove(id) / Pause(id) / Resume(id)
        GRM.Sched.Run(id)     — выполнить немедленно, вне очереди
        GRM.Sched.Status()    — консоль grm_sched
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Sched = GRM.Sched or {}
local S = GRM.Sched

S.Version = "1.0.0"

--[[ ПРИОРИТЕТЫ.

     critical — состояние игроков и безопасность: пропуск виден игроку
                сразу (конвейер входа, лимб, арест). Выполняется даже
                при просадке.
     normal   — обычная игровая логика: голод, биллинг, синхронизация.
     low      — обслуживание: автосейвы, чистки, статистика. Может
                подождать хоть секунду, никто не заметит. ]]
S.PRIO = { critical = 0, normal = 1, low = 2 }
S.PRIO_NAMES = { [0] = "critical", [1] = "normal", [2] = "low" }

S.Tasks = S.Tasks or {}
S.Order = S.Order or {}
S._seq  = S._seq or 0
S._running = false

--[[ Сколько миллисекунд за тик планировщик тратит на периодику. Значение
     небольшое намеренно: задача не обязана уложиться сразу, она просто
     подождёт следующего тика. Лучше ровная нагрузка, чем разовый пик. ]]
local BUDGET = CreateConVar("grm_sched_budget_ms", SERVER and "1.5" or "1",
    bit.bor(FCVAR_ARCHIVE), "Бюджет планировщика периодики GRM в миллисекундах на тик")

local VERBOSE = CreateConVar("grm_sched_verbose", "0", bit.bor(FCVAR_ARCHIVE),
    "Печатать медленные задачи планировщика GRM")

--- Задача считается медленной, если съела больше этого (мс) за раз.
S.SlowMs = 2

-----------------------------------------------------------------------
-- ЧИСТАЯ ЧАСТЬ (проверяется стендом без движка)
-----------------------------------------------------------------------

local function prioOf(v)
    if isnumber(v) then return math.Clamp(math.floor(v), 0, 2) end
    return S.PRIO[tostring(v or "normal")] or S.PRIO.normal
end
S.PrioOf = prioOf

--[[ РАЗВЕДЕНИЕ ФАЗ — ядро всей идеи.

     Задачи с одинаковым интервалом не должны срабатывать в одном тике.
     Раскидываем их равномерно внутри периода по порядковому номеру:
     первая с интервалом 1 с идёт в 0.0, вторая в 0.5, третья в 0.33...

     Используем «золотое сечение» вместо простого деления: при любом
     числе задач точки ложатся равномерно и не собираются в кучки, даже
     когда задачи добавляются по одной в разное время. ]]
local GOLDEN = 0.6180339887498949

function S.PhaseFor(index, interval)
    interval = math.max(0.01, tonumber(interval) or 1)
    index = math.max(0, math.floor(tonumber(index) or 0))
    return ((index * GOLDEN) % 1) * interval
end

--[[ Пора ли выполнять задачу. Отдельной чистой функцией, чтобы стенд мог
     прогнать расписание без движка и таймеров. ]]
function S.IsDue(task, now)
    if not istable(task) then return false end
    if task.paused then return false end
    return (tonumber(task.nextAt) or 0) <= (tonumber(now) or 0)
end

--[[ Можно ли выполнять задачу такого приоритета при текущей загрузке.

     scale — множитель бюджета из GRM.Perf.BudgetScale:
        1.5  сервер свободен       — можно всё
        1.0  норма                 — можно всё
        0.5  затяжка               — только critical и normal
        0.15 провал кадра          — только critical

     Смысл: при перегрузке сервер сначала перестаёт делать уборку, потом
     обычную логику, и только критическое продолжает идти всегда. ]]
function S.AllowedAt(prio, scale)
    prio = prioOf(prio)
    scale = tonumber(scale) or 1
    if prio == S.PRIO.critical then return true end
    if scale <= 0.2 then return false end
    if prio == S.PRIO.low and scale <= 0.6 then return false end
    return true
end

--[[ Следующее время запуска. Если задача сильно отстала (лаг сервера,
     смена карты), НЕ навёрстываем пропущенные циклы — иначе после
     фриза получим шквал вызовов подряд. Просто идём от «сейчас». ]]
function S.NextAt(task, now)
    --[[ Порционный обход не закончил круг — возвращаемся немедленно,
         иначе список из сотни элементов по 8 за раз обходился бы
         десяток периодов. Бюджет тика при этом всё равно соблюдается:
         диспетчер просто не пустит задачу, если время вышло. ]]
    if task.continueNow then return now end
    local interval = math.max(0.01, tonumber(task.interval) or 1)
    local nextAt = (tonumber(task.nextAt) or 0) + interval
    if nextAt <= now then nextAt = now + interval end
    return nextAt
end

-----------------------------------------------------------------------
-- РЕГИСТРАЦИЯ
-----------------------------------------------------------------------
local ensureRunning

--[[ Периодическая задача.

     opts:
       prio    — "critical" / "normal" / "low"
       phase   — своё смещение первого запуска (иначе считаем сами)
       first   — через сколько выполнить в первый раз
       when    — функция-условие: пока false, задача не тратит время ]]
function S.Every(id, interval, fn, opts)
    id = tostring(id or "")
    if id == "" or not isfunction(fn) then return false end
    opts = istable(opts) and opts or {}
    interval = math.max(0.01, tonumber(interval) or 1)

    local now = S.Now()
    local existing = S.Tasks[id]
    local index = existing and existing.index or S._seq
    if not existing then S._seq = S._seq + 1 end

    local phase = tonumber(opts.phase)
    if not phase then phase = S.PhaseFor(index, interval) end

    local task = existing or { id = id, index = index }
    task.interval = interval
    task.fn = fn
    task.prio = prioOf(opts.prio)
    task.when = isfunction(opts.when) and opts.when or nil
    task.paused = false
    task.runs = task.runs or 0
    task.ms = task.ms or 0
    task.peak = task.peak or 0
    -- Первый запуск: со смещением, чтобы не совпасть с соседями.
    local first = tonumber(opts.first)
    task.nextAt = now + (first or phase)

    if not existing then
        S.Tasks[id] = task
        S.Order[#S.Order + 1] = id
    end
    ensureRunning()
    return true
end

--[[ Периодический ПОРЦИОННЫЙ обход.

     Вместо «раз в N секунд пройти весь список» обходим его по кусочкам,
     сохраняя позицию между тиками. Для списков игроков это неважно, а
     вот для сотен entity — разница между ровной нагрузкой и пиком.

     listFn возвращает актуальный список, fn вызывается для элемента. ]]
function S.EverySpread(id, interval, listFn, fn, opts)
    if not (isfunction(listFn) and isfunction(fn)) then return false end
    opts = istable(opts) and opts or {}
    local chunk = math.max(1, math.floor(tonumber(opts.chunk) or 8))

    local state = { list = nil, index = 1 }

    return S.Every(id, interval, function()
        -- Начало нового круга: берём свежий список.
        if not state.list or state.index > #state.list then
            state.list = listFn() or {}
            state.index = 1
            if #state.list == 0 then state.list = nil return end
        end
        local last = math.min(state.index + chunk - 1, #state.list)
        for i = state.index, last do
            fn(state.list[i], i)
        end
        state.index = last + 1
        --[[ Круг не закончен — просим планировщик вернуться в следующем
             же тике, не дожидаясь полного интервала: иначе обход из 20
             элементов по 5 растянулся бы на четыре периода.

             Флаг ставим на самой задаче, а не через nextAt: диспетчер
             перезаписывает nextAt ПОСЛЕ вызова fn, и прямое присваивание
             тут же затиралось бы (обход замирал после первой порции). ]]
        local t = S.Tasks[id]
        if t then t.continueNow = (state.index <= #state.list) or nil end
    end, opts)
end

function S.Remove(id)
    id = tostring(id or "")
    if not S.Tasks[id] then return false end
    S.Tasks[id] = nil
    for i = #S.Order, 1, -1 do
        if S.Order[i] == id then table.remove(S.Order, i) end
    end
    return true
end

function S.Pause(id)
    local t = S.Tasks[tostring(id or "")]
    if not t then return false end
    t.paused = true
    return true
end

function S.Resume(id)
    local t = S.Tasks[tostring(id or "")]
    if not t then return false end
    t.paused = false
    t.nextAt = S.Now()
    return true
end

--- Выполнить немедленно, вне расписания.
function S.Run(id)
    local t = S.Tasks[tostring(id or "")]
    if not (t and isfunction(t.fn)) then return false end
    local ok, err = pcall(t.fn)
    if not ok then
        ErrorNoHalt("[GRM Sched] задача '" .. tostring(id) .. "': " .. tostring(err) .. "\n")
    end
    t.nextAt = S.Now() + t.interval
    return ok
end

-----------------------------------------------------------------------
-- ДИСПЕТЧЕР
-----------------------------------------------------------------------
function S.Now()
    return CurTime and CurTime() or 0
end

--- Текущий множитель бюджета (переиспользуем расчёт из GRM.Perf).
function S.Scale()
    if GRM.Perf and GRM.Perf.BudgetScale and GRM.Perf.FrameNorm then
        return GRM.Perf.BudgetScale(GRM.Perf.FrameAvg or 0, GRM.Perf.FrameNorm())
    end
    return 1
end

--[[ Один проход диспетчера. Вынесен отдельно и принимает время/бюджет
     аргументами — так стенд гоняет его без движка. ]]
function S.Tick(now, budgetSec, scale)
    now = tonumber(now) or S.Now()
    budgetSec = tonumber(budgetSec) or 0.0015
    scale = tonumber(scale) or 1

    local deadline = (SysTime and SysTime() or 0) + budgetSec
    local ran, skipped = 0, 0

    --[[ Собираем готовые задачи и сортируем по приоритету, а внутри
         приоритета — по «насколько опоздала». Так самое просроченное
         выполняется первым и задачи не голодают. ]]
    local due = {}
    for i = 1, #S.Order do
        local task = S.Tasks[S.Order[i]]
        if task and S.IsDue(task, now) then
            if not S.AllowedAt(task.prio, scale) then
                --[[ Не сейчас: сдвигаем срок, но НЕ теряем задачу.
                     Сдвиг небольшой, чтобы вернуться, как только
                     сервер выдохнет. ]]
                task.nextAt = now + math.min(task.interval, 0.5)
                skipped = skipped + 1
            elseif task.when and not task.when() then
                -- Условие не выполнено — задача ничего не стоит.
                task.nextAt = S.NextAt(task, now)
            else
                due[#due + 1] = task
            end
        end
    end

    if #due == 0 then return 0, skipped end

    table.sort(due, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return (now - a.nextAt) > (now - b.nextAt)
    end)

    for i = 1, #due do
        local task = due[i]
        --[[ Бюджет проверяем ПЕРЕД задачей, но critical выполняем всегда:
             пропустить конвейер входа хуже, чем немного превысить бюджет. ]]
        if SysTime and SysTime() >= deadline and task.prio ~= S.PRIO.critical then
            break
        end
        local t0 = SysTime and SysTime() or 0
        local ok, err = pcall(task.fn)
        local dt = (SysTime and SysTime() or 0) - t0

        task.runs = task.runs + 1
        task.ms = task.ms + dt * 1000
        if dt * 1000 > task.peak then task.peak = dt * 1000 end
        task.nextAt = S.NextAt(task, now)
        ran = ran + 1

        if not ok then
            ErrorNoHalt("[GRM Sched] задача '" .. tostring(task.id) .. "': " .. tostring(err) .. "\n")
        elseif VERBOSE:GetBool() and dt * 1000 > S.SlowMs then
            print(("[GRM Sched] медленно: %s — %.2f мс"):format(task.id, dt * 1000))
        end
    end

    return ran, skipped
end

ensureRunning = function()
    if S._running then return end
    if not next(S.Tasks) then return end
    S._running = true
    hook.Add("Think", "GRM_Sched_Tick", function()
        if not next(S.Tasks) then
            hook.Remove("Think", "GRM_Sched_Tick")
            S._running = false
            return
        end
        -- Средняя длина кадра нужна для сжатия бюджета при просадке.
        if GRM.Perf and GRM.Perf.TrackFrame and SysTime then
            GRM.Perf.TrackFrame(SysTime())
        end
        local scale = S.Scale()
        S.Tick(S.Now(), (math.max(0.1, BUDGET:GetFloat()) / 1000) * scale, scale)
    end)
end

-----------------------------------------------------------------------
-- ДИАГНОСТИКА
-----------------------------------------------------------------------
function S.Status()
    local rows = {}
    local now = S.Now()
    for i = 1, #S.Order do
        local t = S.Tasks[S.Order[i]]
        if t then
            rows[#rows + 1] = {
                id = t.id,
                prio = S.PRIO_NAMES[t.prio] or "?",
                interval = t.interval,
                runs = t.runs,
                avgMs = t.runs > 0 and (t.ms / t.runs) or 0,
                peakMs = t.peak,
                inMs = (t.nextAt - now) * 1000,
                paused = t.paused == true,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.avgMs > b.avgMs
    end)
    return rows
end

concommand.Add("grm_sched", function(ply)
    local function out(t)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, t) else print(t) end
    end
    local rows = S.Status()
    out(("[GRM Sched] задач: %d · бюджет %.1f мс/тик · множитель %.2f"):format(
        #rows, BUDGET:GetFloat(), S.Scale()))
    out(string.format("%-34s %-9s %6s %7s %8s %8s", "ЗАДАЧА", "ПРИОР.", "ИНТ.", "ВЫЗ.", "СРЕД.мс", "ПИК.мс"))
    local total = 0
    for _, r in ipairs(rows) do
        total = total + r.avgMs
        out(string.format("%-34s %-9s %5.1fs %7d %8.3f %8.3f%s",
            string.sub(r.id, 1, 34), r.prio, r.interval, r.runs, r.avgMs, r.peakMs,
            r.paused and "  [пауза]" or ""))
    end
    out(("Суммарно среднее за проход: %.3f мс"):format(total))
end)

if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("scheduler", {
        label = "Планировщик периодики",
        version = S.Version,
        Status = function()
            local n = 0
            for _ in pairs(S.Tasks) do n = n + 1 end
            return "задач: " .. n
        end,
    })
end
