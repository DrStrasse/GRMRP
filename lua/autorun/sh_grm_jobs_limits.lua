--[[--------------------------------------------------------------------
    GRM Jobs — ограничитель темпа работ.

    ЧТО БЫЛО. Ни паузы между задачами, ни лимита за час. Единственным
    регулятором служила городская казна: пока в ней есть деньги, можно
    брать одну и ту же короткую задачу без остановки. Это плохо с двух
    сторон — и фарм ничем не ограничен, и казна в какой-то момент
    внезапно пустеет сразу для всех.

    ЧТО СТАЛО. Две мягкие рамки:

      ПАУЗА между задачами (cooldownSec). Дыхание между рейсами; она же
      не даёт бесконечно перебирать предложения, беря и тут же бросая.

      ПОТОЛОК за час (perHour). Ограничивает именно конвейер, считает
      только УСПЕШНО сданные задачи.

    ПОЧЕМУ ПРОВАЛ НЕ СЪЕДАЕТ ПОТОЛОК. Иначе игрок, у которого не
    получилось (отняли посылку, не успел по времени), наказывался бы
    дважды: и без денег, и без работы до конца часа. Провал даёт только
    паузу.

    Всё считается по КЛЮЧУ ПЕРСОНАЖА, а не по аккаунту: смена персонажа
    не должна обнулять лимит, но и чужой лимит на себя не тянет.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Jobs = GRM.Jobs or {}
local JB = GRM.Jobs
JB.LimitsVersion = "1.0.0"

--[[ Значения подобраны под короткие городские задачи (курьер ~5 минут):
     пауза заметна, но не раздражает, а потолок оставляет запас на
     полноценную смену. Меняются в конфиге работ. ]]
JB.Limits = JB.Limits or {
    cooldownSec = 45,        -- пауза после завершения любой задачи
    failCooldownSec = 60,    -- после провала чуть дольше: не поощряем «перебор»
    perHour = 12,            -- сколько УСПЕШНЫХ задач можно сдать за час
}

-- История сдач по персонажу: { [charKey] = { last = ts, done = { ts, ts, ... } } }
JB.LimitState = JB.LimitState or {}

local function charKey(ply)
    if JB.CharacterKey then return JB.CharacterKey(ply) end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    if type(ply) == "table" and ply.SteamID64 then return tostring(ply:SteamID64()) .. ":char1" end
    return tostring(ply or "")
end

local function stateFor(key)
    local st = JB.LimitState[key]
    if not st then st = { last = 0, done = {} } JB.LimitState[key] = st end
    return st
end

--- Выбросить из истории всё старше часа. Заодно не даём таблице расти.
local function trim(st, now)
    local keep = {}
    for _, ts in ipairs(st.done) do
        if (now - ts) < 3600 then keep[#keep + 1] = ts end
    end
    st.done = keep
    return #keep
end

local function plural(sec)
    sec = math.max(1, math.floor(sec))
    local n10, n100 = sec % 10, sec % 100
    if n10 == 1 and n100 ~= 11 then return sec .. " секунду" end
    if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14) then return sec .. " секунды" end
    return sec .. " секунд"
end

--- Можно ли игроку взять новую задачу. Возвращает (true) или (false, причина).
function JB.CanTakeJob(ply)
    local key = charKey(ply)
    if key == "" then return true end
    local st = stateFor(key)
    local now = os.time()

    local waited = now - (st.last or 0)
    local need = tonumber(st.lastWasFail and JB.Limits.failCooldownSec or JB.Limits.cooldownSec) or 0
    if (st.last or 0) > 0 and waited < need then
        return false, "Передохните " .. plural(need - waited) .. " перед следующим заказом."
    end

    local doneInHour = trim(st, now)
    local cap = math.max(1, math.floor(tonumber(JB.Limits.perHour) or 12))
    if doneInHour >= cap then
        -- Считаем, когда освободится место: по самой старой записи в окне.
        local oldest = st.done[1] or now
        local left = math.max(60, 3600 - (now - oldest))
        return false, ("Часовой лимит заказов исчерпан (%d/%d). Следующий — через %d мин."):format(
            doneInHour, cap, math.ceil(left / 60))
    end
    return true
end

--- Отметить успешно сданную задачу: тратит и паузу, и часовой лимит.
function JB.NoteJobFinished(ply, tplId)
    local key = charKey(ply)
    if key == "" then return end
    local st = stateFor(key)
    local now = os.time()
    st.last = now
    st.lastWasFail = false
    st.done[#st.done + 1] = now
    trim(st, now)
    st.lastTpl = tostring(tplId or "")
end

--- Отметить провал: только пауза, часовой лимит не трогаем.
function JB.NoteJobFailed(ply, tplId)
    local key = charKey(ply)
    if key == "" then return end
    local st = stateFor(key)
    st.last = os.time()
    st.lastWasFail = true
    st.lastTpl = tostring(tplId or "")
end

--- Сколько задач сдано за последний час (для интерфейса и статистики).
function JB.JobsDoneThisHour(ply)
    local key = charKey(ply)
    if key == "" then return 0 end
    return trim(stateFor(key), os.time())
end

if SERVER then
    -- Игрок ушёл — историю не держим вечно. Лимит всё равно временный.
    hook.Add("PlayerDisconnected", "GRM_JobsLimits_Forget", function(ply)
        local key = charKey(ply)
        local st = JB.LimitState[key]
        if not st then return end
        -- Если за час ничего не сдавал, запись бесполезна.
        if trim(st, os.time()) == 0 then JB.LimitState[key] = nil end
    end)
end
