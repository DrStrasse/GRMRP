--[[ Живой прогон: линии графа УПРАВЛЯЮТ квестом.

     Заказ владельца 29.08: «делай чтобы линия управляла связями, чтобы
     графы не были бесполезными».

     БЫЛО. Связи — просто картинка. Ролик играл по своей фазе, награда
     выдавалась в конце квеста, музыка по выбранному в панели моменту.
     Протянутая линия ни на что не влияла.

     СТАЛО. Блоки делятся на триггеры и эффекты:
       триггеры: start, <id реплики>, step_N, finish
       эффекты:  cut_accept, cut_complete, music, reward, achieve
     Сработал триггер — выполняются подключённые к нему эффекты.

     ГЛАВНЫЕ РИСКИ, которые тут проверяются:
       • двойной запуск: эффект по линии И по своей фазе;
       • зацикливание, если автор свёл линии в кольцо;
       • разъезд uid между «создал блок» и «сохранил-открыл».

     Запуск: luajit tools/luatest/sim_quest_graph_drives.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local server = readf("lua/autorun/sh_grm_quests.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local dialogue = readf("lua/autorun/sh_grm_quest_dialogue.lua")

-----------------------------------------------------------------------
-- Воспроизводим движок графа ровно так, как он написан на сервере.
-----------------------------------------------------------------------
local function istable(v) return type(v) == "table" end

local function graphTargets(def, uid)
    local out = {}
    if not (istable(def) and istable(def.graph) and istable(def.graph.links)) then return out end
    uid = tostring(uid or "")
    for _, l in ipairs(def.graph.links) do
        if tostring(l.from or "") == uid then out[#out + 1] = tostring(l.to or "") end
    end
    return out
end

local function graphDrives(def, uid)
    if not (istable(def) and istable(def.graph) and istable(def.graph.links)) then return false end
    uid = tostring(uid or "")
    for _, l in ipairs(def.graph.links) do
        if tostring(l.to or "") == uid then return true end
    end
    return false
end

--- Журнал выполненных эффектов — по нему судим, что реально сработало.
local LOG
local function runEffect(def, uid)
    local known = { cut_accept = true, cut_complete = true, music = true,
                    reward = true, achieve = true }
    if known[uid] then LOG[#LOG + 1] = uid return true end
    return false
end

local function runGraphFrom(def, fromUID)
    local seen, queue, fired, guard = {}, { tostring(fromUID or "") }, 0, 0
    while #queue > 0 do
        guard = guard + 1
        if guard > 64 then break end
        local cur = table.remove(queue, 1)
        for _, nxt in ipairs(graphTargets(def, cur)) do
            if not seen[nxt] then
                seen[nxt] = true
                if runEffect(def, nxt) then fired = fired + 1 end
                queue[#queue + 1] = nxt
            end
        end
    end
    return fired
end

local function countIn(log, uid)
    local n = 0
    for _, v in ipairs(log) do if v == uid then n = n + 1 end end
    return n
end

-----------------------------------------------------------------------
print("\n=== 1. ЯДРО ГРАФА ЕСТЬ НА СЕРВЕРЕ ===")
-----------------------------------------------------------------------
ok(server:find("function Q.RunGraphFrom", 1, true) ~= nil,
   "ИСПРАВЛЕНО: появился запуск эффектов по связям")
ok(server:find("function Q.GraphDrives", 1, true) ~= nil,
   "и проверка «этим блоком управляет граф»")
ok(server:find("local function runEffect", 1, true) ~= nil, "есть исполнитель эффектов")
ok(server:find("local function graphTargets", 1, true) ~= nil, "и обход связей")

--[[ Защита от кольца обязательна: без неё сервер уходит в бесконечный
     цикл и вешает карту. ]]
ok(server:find("if guard>64 then break end", 1, true) ~= nil,
   "есть защита от зацикливания по числу шагов")
ok(server:find("if not seen[nxt] then", 1, true) ~= nil,
   "и по уже посещённым блокам")

-----------------------------------------------------------------------
print("\n=== 2. ЛИНИЯ ЗАПУСКАЕТ ЭФФЕКТ ===")
-----------------------------------------------------------------------
local def = {
    id = "q", title = "Q",
    graph = { links = {
        { from = "offer_1", to = "cut_accept", port = 0 },
        { from = "step_1", to = "reward", port = 0 },
        { from = "finish", to = "achieve", port = 0 },
    } },
}

LOG = {}
runGraphFrom(def, "offer_1")
ok(countIn(LOG, "cut_accept") == 1,
   "реплика запускает подключённый ролик", table.concat(LOG, ","))
ok(#LOG == 1, "и только его — лишнего не срабатывает", #LOG)

LOG = {}
runGraphFrom(def, "step_1")
ok(countIn(LOG, "reward") == 1, "закрытый этап выдаёт подключённую награду")

LOG = {}
runGraphFrom(def, "finish")
ok(countIn(LOG, "achieve") == 1, "финиш выдаёт подключённую ачивку")

LOG = {}
runGraphFrom(def, "step_2")
ok(#LOG == 0, "триггер без связей ничего не запускает", #LOG)

LOG = {}
runGraphFrom({ id = "empty" }, "start")
ok(#LOG == 0, "квест без графа не падает и ничего не делает")

-----------------------------------------------------------------------
print("\n=== 3. ЦЕПОЧКА ЭФФЕКТОВ ===")
-----------------------------------------------------------------------
--[[ Эффект может вести к следующему: ролик → музыка → награда. ]]
local chain = { graph = { links = {
    { from = "start", to = "cut_accept" },
    { from = "cut_accept", to = "music" },
    { from = "music", to = "reward" },
} } }
LOG = {}
local fired = runGraphFrom(chain, "start")
ok(fired == 3, "сработали все три звена цепочки", fired)
ok(LOG[1] == "cut_accept" and LOG[2] == "music" and LOG[3] == "reward",
   "и в правильном порядке", table.concat(LOG, " -> "))

-- Одна линия — несколько эффектов от одного триггера.
local fan = { graph = { links = {
    { from = "finish", to = "reward" },
    { from = "finish", to = "achieve" },
    { from = "finish", to = "music" },
} } }
LOG = {}
runGraphFrom(fan, "finish")
ok(#LOG == 3, "от одного триггера можно запустить несколько эффектов", #LOG)

-----------------------------------------------------------------------
print("\n=== 4. КОЛЬЦО НЕ ВЕШАЕТ СЕРВЕР ===")
-----------------------------------------------------------------------
--[[ Автор легко может свести линии в кольцо. Без защиты это
     бесконечный цикл на сервере — карта зависнет для всех. ]]
local loopDef = { graph = { links = {
    { from = "start", to = "cut_accept" },
    { from = "cut_accept", to = "music" },
    { from = "music", to = "cut_accept" },   -- кольцо
} } }
LOG = {}
local okRun = pcall(runGraphFrom, loopDef, "start")
ok(okRun, "кольцо не роняет обход")
ok(countIn(LOG, "cut_accept") == 1, "и каждый эффект выполняется один раз",
   countIn(LOG, "cut_accept"))

local selfLoop = { graph = { links = { { from = "music", to = "music" } } } }
LOG = {}
ok(pcall(runGraphFrom, selfLoop, "music"), "петля блока на себя не зацикливает")

-----------------------------------------------------------------------
print("\n=== 5. НЕТ ДВОЙНОГО ЗАПУСКА ===")
-----------------------------------------------------------------------
--[[ Самый вероятный баг такой правки: ролик подключён линией И играет
     по своей фазе — зритель видит его дважды. ]]
ok(graphDrives(def, "cut_accept") == true, "ролик помечен как управляемый линией")
ok(graphDrives(def, "music") == false, "музыка без линии — не управляемая")

ok(server:find('if not Q.GraphDrives(def,"reward") then reward(ply,def) end', 1, true) ~= nil,
   "ИСПРАВЛЕНО: награда по линии не выдаётся повторно в конце квеста")
ok(server:find('if not Q.GraphDrives(def,"achieve") then unlockQuestAchievement(ply,def) end', 1, true) ~= nil,
   "ачивка тоже")
--[[ Ролики проверяем по СМЫСЛУ, а не по точной однострочной записи.
     Внутри ветки GraphDrives теперь есть развилка «сразу / ждать конца
     диалога» (флаг acceptAfterDialogue), поэтому строка в одну линию
     больше не совпадает. Важно ровно одно: показ ролика по фазе стоит
     ПОД защитой GraphDrives, иначе линия графа и фаза сыграют его
     дважды. ]]
local function guardedCutscene(src, guard, call)
    local at = src:find('if not Q.GraphDrives(def,"' .. guard .. '")', 1, true)
    if not at then return false end
    -- тело ветки: до конца блока (следующая строка того же отступа)
    local chunk = src:sub(at, at + 700)
    return chunk:find(call, 1, true) ~= nil
end
-- Вызов ищем по началу: аргументы (флаг «ждать конца диалога», тег)
-- добавляются и меняются, а важна сама обёртка GraphDrives.
ok(guardedCutscene(server, "cut_complete", "cutscene(ply,def.cutscene.complete"),
   "ролик завершения тоже")
ok(guardedCutscene(server, "cut_accept", "cutscene(ply,def.cutscene.accept"),
   "ролик принятия тоже")
ok(server:find('if not Q.GraphDrives(def,"music") then questMusic(ply,"start",def) end', 1, true) ~= nil,
   "музыка при старте тоже")

--[[ Моделируем оба пути СРАЗУ ИЗ КОДА сервера, а не по своей копии:
     сверка текста ловит откат, но не доказывает, что суммарно эффект
     срабатывает один раз. Читаем реальную строку finishQuest и смотрим,
     обёрнута ли выдача награды проверкой. ]]
local finishFn = server:match("local function finishQuest.-\n    end") or ""
ok(finishFn ~= "", "функция завершения квеста найдена")

local rewardGuarded = finishFn:find('Q.GraphDrives(def,"reward")', 1, true) ~= nil
local function finishQuest(d)
    local n = 0
    -- Штатная выдача происходит, только если она обёрнута проверкой.
    if (not rewardGuarded) or (not graphDrives(d, "reward")) then n = n + 1 end
    LOG = {}
    runGraphFrom(d, "finish")
    return n + countIn(LOG, "reward")
end
local viaGraph = { graph = { links = { { from = "finish", to = "reward" } } } }
ok(finishQuest(viaGraph) == 1, "награда по линии выдаётся один раз", finishQuest(viaGraph))
local viaDefault = { graph = { links = {} } }
ok(finishQuest(viaDefault) == 1, "без линии — тоже один раз, по-старому",
   finishQuest(viaDefault))

-----------------------------------------------------------------------
print("\n=== 6. ТРИГГЕРЫ ПОДКЛЮЧЕНЫ К ЖИЗНЕННОМУ ЦИКЛУ ===")
-----------------------------------------------------------------------
ok(server:find('Q.RunGraphFrom(ply,def,"start",all[def.id])', 1, true) ~= nil,
   "принятие квеста запускает граф")
ok(server:find('Q.RunGraphFrom(ply,def,"finish",p)', 1, true) ~= nil,
   "завершение квеста тоже")
local stepCalls = select(2, server:gsub('Q%.RunGraphFrom%(ply,def,"step_"', ""))
ok(stepCalls == 4, "все четыре точки завершения этапа подключены", stepCalls)

--[[ Номер этапа: p.step уже увеличен, значит закрыт предыдущий. Ошибка
     на единицу означала бы, что эффект висит не на том этапе. ]]
ok(server:find('"step_"..tostring((tonumber(p.step) or 1)-1)', 1, true) ~= nil,
   "номер закрытого этапа считается как p.step-1")
local function closedStep(pstep) return "step_" .. (pstep - 1) end
ok(closedStep(2) == "step_1", "после первого этапа триггер step_1", closedStep(2))
ok(closedStep(3) == "step_2", "после второго — step_2", closedStep(3))

-- Реплика как триггер.
--[[ С 29.08 у связи есть момент запуска, и показ реплики поднимает
     только режим «сразу»: отложенные ждут конца разговора. Раньше здесь
     проверялся безрежимный вызов — он больше не должен существовать.
     Подробности — в sim_quest_cutscene_after_dialogue. ]]
ok(dialogue:find('Q.RunGraphFrom(ply, def, uid, nil, "now")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: показ реплики запускает подключённые эффекты режима «сразу»")
ok(dialogue:find("local function flushPending", 1, true) ~= nil,
   "а отложенные выпускаются в конце разговора")
local sendFn = dialogue:match("local function sendNode.-\n        local choices") or ""
ok(sendFn:find("Q.RunGraphFrom", 1, true) ~= nil,
   "и делает это ДО отправки реплики — ролик стартует вместе с ней")

-----------------------------------------------------------------------
print("\n=== 7. UID НЕ РАЗЪЕЗЖАЮТСЯ ПОСЛЕ СОХРАНЕНИЯ ===")
-----------------------------------------------------------------------
--[[ Движок ищет блоки по uid. Если созданный блок называется
     «step_48231_3», а после перезагрузки становится «step_1», связь
     теряет цель и эффект молчит. ]]
ok(studio:find('uid = kind .. "_" .. (os.time() % 100000)', 1, true) == nil,
   "БАГ УБРАН: случайный uid больше не используется")
ok(studio:find('uid = "step_" .. (n + 1)', 1, true) ~= nil,
   "ИСПРАВЛЕНО: новый этап сразу получает uid как при загрузке")
ok(studio:find('uid = "cut_" .. (data.phase == "complete" and "complete" or "accept")', 1, true) ~= nil,
   "кат-сцена тоже")
ok(studio:find('uid = kind == "achieve" and "achieve" or kind', 1, true) ~= nil,
   "музыка, награда и ачивка — постоянные имена")

-- Воспроизводим правило именования.
local function newUID(kind, blocks, data)
    if kind == "step" then
        local n = 0
        for _, b in ipairs(blocks) do if b.kind == "step" then n = n + 1 end end
        return "step_" .. (n + 1)
    elseif kind == "cutscene" then
        return "cut_" .. ((data.phase == "complete") and "complete" or "accept")
    end
    return kind
end
ok(newUID("step", {}, {}) == "step_1", "первый этап — step_1")
ok(newUID("step", { { kind = "step" } }, {}) == "step_2", "второй — step_2")
ok(newUID("cutscene", {}, { phase = "complete" }) == "cut_complete",
   "кат-сцена завершения — cut_complete")
ok(newUID("reward", {}, {}) == "reward", "награда — reward")

--[[ Смена фазы меняет uid: без переписывания ссылок связь указывала бы
     на исчезнувший «cut_accept». ]]
ok(studio:find("if l.to == oldUID then l.to = newUID end", 1, true) ~= nil,
   "смена фазы кат-сцены переписывает связи на новый uid")

-----------------------------------------------------------------------
print("\n=== 8. В РЕДАКТОРЕ ВИДНО, ЧТО СВЯЗЬ РАБОТАЕТ ===")
-----------------------------------------------------------------------
ok(studio:find("◀ по линии", 1, true) ~= nil,
   "на карточке помечено, что блок запускается линией")
ok(studio:find("Запускается ЛИНИЕЙ", 1, true) ~= nil,
   "и в панели свойств сказано прямо")
ok(studio:find("Сейчас играет по своей фазе", 1, true) ~= nil,
   "а без линии объяснено, как задать точный момент")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
