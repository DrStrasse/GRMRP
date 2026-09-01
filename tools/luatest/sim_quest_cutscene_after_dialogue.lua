--[[ Живой прогон: кат-сцена после диалога.

     Жалоба владельца 29.08: «кат-сцена срабатывает ещё до момента пока
     не прошёл диалог, сделай для неё настройку срабатывать после
     диалога».

     ПРИЧИНА. Эффекты графа запускались в момент ПОКАЗА реплики. Ролик
     перехватывал камеру поверх текста, который игрок ещё не прочитал.

     РЕШЕНИЕ. У связи появился момент запуска:
       now   — сразу, как реплика появилась (прежнее поведение);
       after — когда игрок закончит разговор.

     РИСКИ, которые тут проверяются:
       • отложенный эффект обязан сработать при ЛЮБОМ выходе из
         разговора, иначе ролик не сыграет вовсе — хуже, чем было;
       • и обязан сработать РОВНО ОДИН раз;
       • старые квесты не должны поменять поведение молча.

     Запуск: luajit tools/luatest/sim_quest_cutscene_after_dialogue.lua ]]

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
local dialogue = readf("lua/autorun/sh_grm_quest_dialogue.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

local function istable(v) return type(v) == "table" end

-----------------------------------------------------------------------
-- Воспроизводим движок графа так, как он написан на сервере.
-----------------------------------------------------------------------
local LOG

local function graphTargets(def, uid, mode)
    local out = {}
    if not (istable(def) and istable(def.graph) and istable(def.graph.links)) then return out end
    uid = tostring(uid or "")
    for _, l in ipairs(def.graph.links) do
        if tostring(l.from or "") == uid then
            local w = (l.when == "after") and "after" or "now"
            if not mode or w == mode then out[#out + 1] = tostring(l.to or "") end
        end
    end
    return out
end

local function runEffect(uid)
    local known = { cut_accept = true, cut_complete = true, music = true,
                    reward = true, achieve = true }
    if known[uid] then LOG[#LOG + 1] = uid return true end
    return false
end

local function runGraphFrom(def, fromUID, mode)
    local seen, queue, guard, first = {}, { tostring(fromUID or "") }, 0, true
    while #queue > 0 do
        guard = guard + 1
        if guard > 64 then break end
        local cur = table.remove(queue, 1)
        local useMode = first and mode or nil
        first = false
        for _, nxt in ipairs(graphTargets(def, cur, useMode)) do
            if not seen[nxt] then
                seen[nxt] = true
                runEffect(nxt)
                queue[#queue + 1] = nxt
            end
        end
    end
end

local function countIn(uid)
    local n = 0
    for _, v in ipairs(LOG) do if v == uid then n = n + 1 end end
    return n
end

--- Квест: реплика запускает ролик ПОСЛЕ разговора, музыку — сразу.
local DEF = { graph = { links = {
    { from = "offer_1", to = "cut_accept", port = 0, when = "after" },
    { from = "offer_1", to = "music", port = 0, when = "now" },
} } }

-----------------------------------------------------------------------
print("\n=== 1. БАГ ВОСПРОИЗВЕДЁН: РОЛИК ПОВЕРХ ТЕКСТА ===")
-----------------------------------------------------------------------
--[[ Прежнее поведение: режима нет, всё срабатывает при показе. ]]
local OLD = { graph = { links = {
    { from = "offer_1", to = "cut_accept", port = 0 },
} } }
LOG = {}
runGraphFrom(OLD, "offer_1", "now")
ok(countIn("cut_accept") == 1,
   "БАГ: без настройки ролик запускался в момент показа реплики")

-----------------------------------------------------------------------
print("\n=== 2. РЕЖИМ РАЗДЕЛЯЕТ МОМЕНТ ЗАПУСКА ===")
-----------------------------------------------------------------------
LOG = {}
runGraphFrom(DEF, "offer_1", "now")
ok(countIn("music") == 1, "при показе реплики срабатывает «сразу»")
ok(countIn("cut_accept") == 0,
   "ИСПРАВЛЕНО: ролик с пометкой «после» при показе НЕ запускается")

LOG = {}
runGraphFrom(DEF, "offer_1", "after")
ok(countIn("cut_accept") == 1, "в конце разговора ролик срабатывает")
ok(countIn("music") == 0, "а «сразу» второй раз не повторяется")

--[[ Суммарно за разговор каждый эффект должен прозвучать один раз. ]]
LOG = {}
runGraphFrom(DEF, "offer_1", "now")
runGraphFrom(DEF, "offer_1", "after")
ok(countIn("cut_accept") == 1 and countIn("music") == 1,
   "за весь разговор каждый эффект ровно один раз",
   #LOG)

-----------------------------------------------------------------------
print("\n=== 3. СТАРЫЕ КВЕСТЫ НЕ ЛОМАЮТСЯ ===")
-----------------------------------------------------------------------
--[[ Связь без указанного режима обязана вести себя как раньше: иначе
     у всех существующих квестов ролики молча переехали бы в конец. ]]
local legacy = { graph = { links = { { from = "offer_1", to = "cut_accept", port = 0 } } } }
LOG = {}
runGraphFrom(legacy, "offer_1", "now")
ok(countIn("cut_accept") == 1, "связь без режима считается «сразу»")
LOG = {}
runGraphFrom(legacy, "offer_1", "after")
ok(countIn("cut_accept") == 0, "и в отложенные не попадает")

ok(server:find('when=(l.when=="after")and"after"or"now"', 1, true) ~= nil,
   "нормализация проставляет режим по умолчанию «сразу»")

-----------------------------------------------------------------------
print("\n=== 4. ЦЕПОЧКА ЭФФЕКТОВ НЕ ФИЛЬТРУЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Режим касается только первой связи — от триггера. Внутри цепочки
     фильтр применять нельзя: раз она запущена, отрабатывает целиком. ]]
local chain = { graph = { links = {
    { from = "offer_1", to = "cut_accept", when = "after" },
    { from = "cut_accept", to = "music" },      -- звено без режима
    { from = "music", to = "reward" },
} } }
LOG = {}
runGraphFrom(chain, "offer_1", "after")
ok(#LOG == 3, "вся цепочка отработала после разговора", #LOG)
ok(LOG[1] == "cut_accept" and LOG[2] == "music" and LOG[3] == "reward",
   "и в правильном порядке", table.concat(LOG, " -> "))

ok(server:find("local useMode=first and mode or nil", 1, true) ~= nil,
   "фильтр применяется только к первому шагу обхода")

-----------------------------------------------------------------------
print("\n=== 5. ОТЛОЖЕННОЕ СРАБАТЫВАЕТ ПРИ ЛЮБОМ ВЫХОДЕ ===")
-----------------------------------------------------------------------
--[[ Самый опасный сценарий: разговор закончился не тем путём, что
     ожидали, и ролик не сыграл вовсе. Это хуже прежнего поведения. ]]
ok(dialogue:find("local function flushPending", 1, true) ~= nil,
   "ИСПРАВЛЕНО: есть выпуск отложенных эффектов")

local flushCalls = select(2, dialogue:gsub("flushPending%(ply%)", ""))
ok(flushCalls >= 3, "он вызывается во всех точках выхода из разговора", flushCalls)

--[[ Проверяем поимённо: закрытие действием, конец веток, уход от NPC. ]]
local closeBranch = dialogue:match('if result == "close" then.-\n            return\n        end') or ""
ok(closeBranch:find("flushPending(ply)", 1, true) ~= nil,
   "закрытие действием выпускает отложенное")

local endBranch = dialogue:match("if not nxt then.-\n            return\n        end") or ""
ok(endBranch:find("flushPending(ply)", 1, true) ~= nil,
   "конец веток диалога тоже")

local farBranch = dialogue:match("if ply:GetPos%(%):DistToSqr.-\n            return\n        end") or ""
ok(farBranch:find("flushPending(ply)", 1, true) ~= nil,
   "уход от NPC тоже — иначе ролик завис бы навсегда")

--[[ Порядок важен: выпускаем ДО обнуления сессии, иначе список
     отложенного уже потерян. ]]
local flushPos = closeBranch:find("flushPending", 1, true)
local nilPos = closeBranch:find("ply.GRMQuestDlg = nil", 1, true)
ok(flushPos and nilPos and flushPos < nilPos,
   "выпуск идёт до обнуления сессии")

-----------------------------------------------------------------------
print("\n=== 6. ОТЛОЖЕННОЕ НЕ ДУБЛИРУЕТСЯ ===")
-----------------------------------------------------------------------
local flushFn = dialogue:match("local function flushPending%(ply%).-\n    end") or ""
ok(flushFn ~= "", "функция выпуска найдена")
ok(flushFn:find("sess.pending = nil", 1, true) ~= nil,
   "список чистится сразу — повторный вызов не запустит ролик дважды")

-- Моделируем двойной вызов.
local pending = { "offer_1" }
local fired = 0
local function flush()
    if not pending then return end
    local list = pending
    pending = nil
    for _ in ipairs(list) do fired = fired + 1 end
end
flush() flush()
ok(fired == 1, "двойной выход из разговора запускает эффект один раз", fired)

--[[ Копим ID реплик, а не готовые эффекты: к концу разговора квест
     могли пересохранить, и список эффектов устарел бы. ]]
ok(dialogue:find("sess.pending[#sess.pending + 1] = uid", 1, true) ~= nil,
   "копятся ID реплик, а не снимок эффектов")

--[[ КЛЮЧЕВОЕ. Показ реплики обязан запускать ТОЛЬКО «сразу». Без
     режима в вызове вернулось бы прежнее поведение: ролик поверх
     нечитанного текста — ровно то, на что жаловался владелец.

     Проверяем сам вызов, а не только наличие flushPending: первая
     версия стенда этого не делала и откат пропустила. ]]
local sendFn = dialogue:match("local function sendNode.-\n        local choices") or ""
ok(sendFn ~= "", "функция показа реплики найдена")
ok(sendFn:find('Q.RunGraphFrom(ply, def, uid, nil, "now")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: при показе реплики запускается только режим «сразу»")
ok(sendFn:find("Q.RunGraphFrom(ply, def, uid, nil)", 1, true) == nil,
   "БАГ УБРАН: безрежимного вызова при показе больше нет")

-----------------------------------------------------------------------
print("\n=== 7. РЕЖИМ ПЕРЕЖИВАЕТ СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
ok(studio:find('when = (l.when == "after") and "after" or "now",', 1, true) ~= nil,
   "студия сохраняет режим связи")
ok(studio:find('ex.when = (l.when == "after") and "after" or ex.when', 1, true) ~= nil,
   "и переносит его на уже восстановленную диалоговую связь")

--[[ Диалоговые связи поднимаются из next/choices раньше, чем читается
     раскладка. Без переноса режим «после» терялся бы при переоткрытии —
     самая вероятная поломка этой правки. ]]
local function restore(existing, saved)
    for _, ex in ipairs(existing) do
        if ex.port == saved.port then
            ex.when = (saved.when == "after") and "after" or ex.when
            return existing
        end
    end
    existing[#existing + 1] = { port = saved.port, when = saved.when }
    return existing
end
local links = { { port = 0, when = "now" } }
restore(links, { port = 0, when = "after" })
ok(links[1].when == "after", "режим подхватывается на существующую связь", links[1].when)

local links2 = { { port = 0, when = "after" } }
restore(links2, { port = 0, when = "now" })
ok(links2[1].when == "after",
   "и не сбрасывается обратно, если в раскладке пусто", links2[1].when)

-----------------------------------------------------------------------
print("\n=== 8. НАСТРОЙКА ВИДНА В РЕДАКТОРЕ ===")
-----------------------------------------------------------------------
ok(studio:find("КОГДА ЗАПУСКАТЬ ПОДКЛЮЧЁННОЕ", 1, true) ~= nil,
   "в панели реплики есть переключатель момента")
ok(studio:find("после разговора", 1, true) ~= nil, "видно состояние «после разговора»")
ok(studio:find("сразу при показе реплики", 1, true) ~= nil, "и «сразу»")
ok(studio:find('l.when = (l.when == "after") and "now" or "after"', 1, true) ~= nil,
   "клик переключает момент")
ok(studio:find("◀ после диалога", 1, true) ~= nil,
   "на карточке блока тоже видно, что запуск отложен")

--[[ Настройка на СВЯЗИ, а не на кат-сцене: один ролик может быть
     подключён к нескольким репликам с разным моментом. ]]
ok(studio:find("for _, l in ipairs(b.links or {}) do outLinks[#outLinks + 1] = l end", 1, true) ~= nil,
   "переключатель строится по связям реплики, а не по блоку эффекта")

-----------------------------------------------------------------------
print("\n=== 9. ПЕРЕКЛЮЧАТЕЛЬ ЕСТЬ В ПАНЕЛИ САМОЙ КАТ-СЦЕНЫ ===")
-----------------------------------------------------------------------
--[[ Владелец не нашёл настройку: она была только в панели реплики.
     Искать её логично там, где настраивают сам ролик. ]]
--[[ Берём ветку ИЗ ПАНЕЛИ СВОЙСТВ: «elseif b.kind == "cutscene"»
     встречается ещё в BlocksToQuest выше по файлу, и шаблон цеплялся за
     неё — проверки падали, хотя код на месте. На эту ловушку я уже
     наступал с веткой диалога. ]]
local propsFn = studio:match("rebuildProps = function%(%).-\n    end") or ""
ok(propsFn ~= "", "панель свойств найдена")
local cutBranch = propsFn:match('elseif b%.kind == "cutscene" then.-elseif b%.kind == "music" then') or ""
ok(cutBranch ~= "", "панель кат-сцены найдена")
ok(cutBranch:find("КОГДА ЗАПУСКАТЬ ЭТОТ РОЛИК", 1, true) ~= nil,
   "ИСПРАВЛЕНО: переключатель момента есть в панели кат-сцены")
ok(cutBranch:find("ПОСЛЕ диалога", 1, true) ~= nil, "видно состояние «после диалога»")
ok(cutBranch:find("СРАЗУ при показе реплики", 1, true) ~= nil, "и «сразу»")
ok(cutBranch:find('l.when = (l.when == "after") and "now" or "after"', 1, true) ~= nil,
   "клик переключает момент прямо отсюда")

--[[ Панель показывает ВХОДЯЩИЕ связи: именно они решают, когда ролик
     сыграет. Список исходящих был бы бесполезен. ]]
ok(cutBranch:find("if l.to == b.uid then", 1, true) ~= nil,
   "собираются входящие связи ролика")

--[[ У этапа и старта разговора нет — «после диалога» там ничего не
     изменит. Честно говорим об этом, а не даём бесполезный тумблер. ]]
ok(cutBranch:find('fromBlock.kind == "dialogue"', 1, true) ~= nil,
   "различается, от реплики связь или нет")
ok(cutBranch:find("у этого блока нет диалога", 1, true) ~= nil,
   "для связи не от реплики сказано, что момент не применим")

-- Переключатель в панели реплики тоже остался: настройка живёт на связи.
ok(studio:find("КОГДА ЗАПУСКАТЬ ПОДКЛЮЧЁННОЕ", 1, true) ~= nil,
   "переключатель в панели реплики сохранён — это одна и та же связь")

-----------------------------------------------------------------------
print("\n=== 10. СВЯЗЬ ОТ ЭТАПА НЕ ЗАВИСАЕТ ===")
-----------------------------------------------------------------------
--[[ Найдено при разборе скриншота: у владельца ролик подключён ОТ
     ЭТАПА. Триггеры этапа, старта и финиша зовут граф без режима.
     Если бы они уважали пометку «после диалога», такая связь не
     сработала бы никогда — эффект молча пропал бы. ]]
local stepDef = { graph = { links = {
    { from = "step_1", to = "cut_accept", port = 0, when = "after" },
} } }
LOG = {}
runGraphFrom(stepDef, "step_1", nil)
ok(countIn("cut_accept") == 1,
   "ИСПРАВЛЕНО: связь «после» от ЭТАПА срабатывает, а не виснет", #LOG)

LOG = {}
runGraphFrom(stepDef, "step_1", "after")
ok(countIn("cut_accept") == 1, "и при явном режиме «после» тоже")

--[[ Проверяем, что триггеры не-диалоговых блоков действительно зовут
     граф без фильтра. ]]
ok(server:find('Q.RunGraphFrom(ply,def,"start",all[def.id])', 1, true) ~= nil,
   "старт зовёт граф без режима — запускает все связи")
ok(server:find('Q.RunGraphFrom(ply,def,"finish",p)', 1, true) ~= nil,
   "финиш тоже")
local stepCalls = select(2, server:gsub('Q%.RunGraphFrom%(ply,def,"step_"[^\n]-%),p%)', ""))
ok(stepCalls == 4, "и все четыре точки завершения этапа", stepCalls)

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
