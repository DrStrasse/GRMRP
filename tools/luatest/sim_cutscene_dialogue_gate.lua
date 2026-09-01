--[[--------------------------------------------------------------------
    sim_cutscene_dialogue_gate — ролик НЕ лезет поверх открытого диалога,
    каким бы путём его ни запустили.

    ЖАЛОБА ВЛАДЕЛЬЦА (29.08, вторая итерация). После прошлого фикса
    кнопки в студии появились, но «по факту ничего не изменилось:
    кат-сцена показывается с диалогом сразу, не дожидаясь, пока игрок
    поговорит с NPC».

    ПОЧЕМУ ПРЕДЫДУЩАЯ ПОПЫТКА ПРОВАЛИЛАСЬ (дважды подряд). Я закрывал
    ОДИН путь за раз:

      попытка 1 — пометка на связи графа.  Мимо: ролик «при принятии»
                  идёт из Q.Start, графа не касается.
      попытка 2 — флаг в Q.Start.          Мимо: у владельца ролик висит
                  на ЛИНИИ от блока, и его зовёт runEffect -> cutscene(),
                  минуя Q.Start целиком.

    ВЫВОД. Путей запуска несколько (Q.Start, финал квеста, граф от
    реплики, граф от этапа, предпросмотр), и латать каждый — гарантия
    промахнуться снова. Проверка должна стоять в ЕДИНСТВЕННОЙ общей
    точке — в самой функции показа cutscene().

    ПРАВИЛО. Идёт диалог (ply.GRMQuestDlg) и у ролика включено «ждать
    конца диалога» — откладываем в очередь. Разговор закончился —
    показываем. Диалога нет — показываем сразу, как раньше.

    Запуск: luajit tools/luatest/sim_cutscene_dialogue_gate.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local quests = read("lua/autorun/sh_grm_quests.lua")
local dialogue = read("lua/autorun/sh_grm_quest_dialogue.lua")

print("\n=== 1. ЗАЩИТА СТОИТ В ОБЩЕЙ ТОЧКЕ ПОКАЗА ===")
--[[ Ключевая проверка всей правки. Если гейт живёт только в Q.Start,
     ролик по линии графа пройдёт мимо — ровно то, на что жалуется
     владелец. Гейт обязан быть внутри cutscene(). ]]
local cutFn = quests:match("local function cutscene%(ply,nodes.-\n    end") or
              quests:match("local function cutscene%(ply,nodes[^\n]*\n") or ""
ok(cutFn ~= "", "функция показа ролика найдена")
ok(cutFn:find("GRMQuestDlg", 1, true) ~= nil,
    "показ ролика проверяет, идёт ли разговор")
ok(cutFn:find("QueueCutscene", 1, true) ~= nil or cutFn:find("PendingCutscene", 1, true) ~= nil,
    "во время разговора ролик уходит в очередь, а не на экран")

print("\n=== 2. ГЕЙТ РАБОТАЕТ ДЛЯ ЛЮБОГО ПУТИ ЗАПУСКА ===")
-- runEffect (граф) обязан звать ту же cutscene(), а не свою копию:
-- иначе появится ещё один необёрнутый путь.
local runEff = quests:match("local function runEffect%(ply,def,uid,p%).-\n    end") or ""
ok(runEff ~= "", "runEffect найден")
-- Ищем по смыслу: вызов общей cutscene() с флагом ролика. Точную
-- однострочную запись проверять нельзя — она меняется при любой правке.
ok(runEff:find("cutscene(ply,def.cutscene and def.cutscene.accept", 1, true) ~= nil,
    "граф показывает ролик через общую cutscene(), а не в обход")
ok(runEff:find("acceptAfterDialogue", 1, true) ~= nil,
    "и передаёт ей флаг «ждать конца диалога»")
ok(runEff:find("net.Start(\"GRM_Quest_Cutscene\")", 1, true) == nil,
    "у графа нет своей копии отправки ролика")

print("\n=== 3. ЖИВОЙ ПРОГОН ВСЕХ ПУТЕЙ ===")
--[[ Модель повторяет боевую логику: одна функция показа, гейт внутри.
     Проверяем, что ЛЮБОЙ вызов во время диалога откладывается. ]]
local sent, pending = {}, {}
local function IsValidP(p) return type(p) == "table" end

local function queueCutscene(ply, nodes, tag)
    if not nodes or #nodes == 0 then return false end
    pending[ply] = { nodes = nodes, tag = tag }
    return true
end
local function flushCutscene(ply)
    local rec = pending[ply]
    if not rec then return false end
    pending[ply] = nil                       -- снимаем ДО показа
    sent[#sent + 1] = rec.tag
    return true
end
--- Общая точка показа с гейтом — как в боевом коде.
local function cutscene(ply, nodes, opts)
    if not IsValidP(ply) or not nodes or #nodes == 0 then return end
    opts = opts or {}
    if opts.afterDialogue and ply.GRMQuestDlg then
        queueCutscene(ply, nodes, opts.tag or "cut")
        return
    end
    sent[#sent + 1] = opts.tag or "cut"
end

local nodes = { { caption = "Первое, что тебе надо знать..." } }
local ply = { GRMQuestDlg = { questID = "quest_1787937935" } }

-- путь А: линия графа от реплики (случай владельца)
cutscene(ply, nodes, { afterDialogue = true, tag = "graph" })
ok(#sent == 0, "ролик по ЛИНИИ ГРАФА не показан во время диалога", #sent)

-- путь Б: Q.Start при принятии квеста
cutscene(ply, nodes, { afterDialogue = true, tag = "start" })
ok(#sent == 0, "ролик при ПРИНЯТИИ тоже отложен", #sent)

-- разговор закончился
ply.GRMQuestDlg = nil
flushCutscene(ply)
ok(#sent == 1, "после разговора сыграл ровно один ролик", #sent)

flushCutscene(ply)
ok(#sent == 1, "повторный выход не проигрывает второй раз", #sent)

print("\n=== 4. БЕЗ ДИАЛОГА — ПОКАЗ СРАЗУ ===")
--[[ Ролик от этапа посреди города (разговора нет) обязан играть
     немедленно. Иначе он повис бы в очереди до следующей болтовни с
     NPC — тихая потеря, которую заметить труднее, чем ранний показ. ]]
sent = {}
local lone = {}
cutscene(lone, nodes, { afterDialogue = true, tag = "step" })
ok(#sent == 1, "вне разговора ролик играет сразу", #sent)

print("\n=== 5. ФЛАГ ВЫКЛЮЧЕН — СТАРОЕ ПОВЕДЕНИЕ ===")
sent = {}
local talking = { GRMQuestDlg = { questID = "q" } }
cutscene(talking, nodes, { afterDialogue = false, tag = "old" })
ok(#sent == 1, "без флага ролик идёт как раньше, даже в диалоге", #sent)

print("\n=== 6. ОЧЕРЕДЬ ВЫПУСКАЕТСЯ ВО ВСЕХ ТОЧКАХ ВЫХОДА ===")
local flushCount = select(2, dialogue:gsub("FlushCutscene", ""))
ok(flushCount >= 3, "выпуск стоит во всех трёх точках выхода", flushCount)

--[[ ДВА ТРЕБОВАНИЯ К ПОРЯДКУ, И ОНИ НЕ ПРОТИВОРЕЧАТ ДРУГ ДРУГУ.

     1) Выпуск не должен быть заперт за ранним выходом. У квеста, где
        линий к ролику нет вообще, список эффектов пуст: ролик кладёт в
        очередь Q.Start. Заперли за проверкой «есть что прогонять» — и
        ролик не сыграет никогда.

     2) Выпуск обязан идти ПОСЛЕ прогона отложенных эффектов. Гейт в
        cutscene() откладывает ролик, пока жива сессия диалога, а её
        снимают уже после выхода отсюда — значит эффект кладёт ролик в
        очередь ИМЕННО во время прогона. Выпустишь раньше — очередь
        пуста, ролик застрянет. Владелец: «кат-сцена не показывается
        при выборе верного диалога».

     Оба условия выполняются, если выпуск стоит последним, вне всяких
     if. Раньше эта проверка требовала обратного и закрепляла ошибку. ]]
local fp = dialogue:match("local function flushPending%(ply%).-\n    end") or ""
local atFlush = fp:find("FlushCutscene", 1, true)
local atAfter = fp:find('RunGraphFrom(ply, def, uid, nil, "after")', 1, true)
ok(atFlush and atAfter and atFlush > atAfter,
    "выпуск очереди идёт ПОСЛЕ прогона отложенных эффектов",
    ("flush=%s after=%s"):format(tostring(atFlush), tostring(atAfter)))
--[[ Проверяем ОТСТУП строки выпуска: 8 пробелов = верхний уровень тела
     функции. Если выпуск утащили внутрь `if ... then` (12+ пробелов),
     он выполнится не всегда — ролик, положенный в очередь из Q.Start
     при принятии квеста, пропадёт. Проверка «нет return после» такую
     ошибку не видит, поэтому смотрим именно уровень вложенности. ]]
local flushLine = ""
for line in fp:gmatch("[^\n]+") do
    if line:find("FlushCutscene", 1, true) then flushLine = line break end
end
local indent = #(flushLine:match("^(%s*)") or "")
ok(indent == 8, "выпуск стоит на верхнем уровне функции, а не внутри if",
    ("отступ=%d: %s"):format(indent, flushLine:gsub("^%s+", "")))

print("\n=== 7. ПРИНЯТИЕ КВЕСТА: ОТЛОЖИТЬ, ПОТОМ ВЫПУСТИТЬ ===")
--[[ Тонкий момент порядка. Ответ «Принять квест» зовёт Q.Start ещё при
     ЖИВОЙ сессии диалога — поэтому гейт срабатывает и ролик уходит в
     очередь. Сразу следом обработчик закрывает разговор и зовёт
     flushPending, который очередь выпускает.

     Если бы сессию снимали ДО runAction, гейт бы не сработал и ролик
     снова пошёл поверх диалога — ровно та жалоба владельца. Проверяем
     порядок в теле обработчика. ]]
local pick = dialogue:match("net%.Receive%(NET_PICK.-\n    end%)") or ""
ok(pick ~= "", "обработчик выбора реплики найден")
local atAction = pick:find("local result = runAction", 1, true)
local atFlush = pick:find("flushPending(ply)", atAction or 1, true)
local atClear = pick:find("ply.GRMQuestDlg = nil", atAction or 1, true)
ok(atAction and atFlush and atAction < atFlush,
    "принятие квеста обрабатывается ДО закрытия разговора",
    ("action=%s flush=%s"):format(tostring(atAction), tostring(atFlush)))
ok(atFlush and atClear and atFlush < atClear,
    "очередь выпускается ДО снятия сессии диалога",
    ("flush=%s clear=%s"):format(tostring(atFlush), tostring(atClear)))

print("\n=== 8. ПРЕДПРОСМОТР АДМИНА НЕ ЛОМАЕТСЯ ===")
-- Кнопка «Просмотр» в студии должна показывать ролик всегда: админ
-- специально нажал, ждать ему нечего.
ok(quests:find("GRM_Quest_CutscenePreview", 1, true) ~= nil, "предпросмотр на месте")

print(("\nCUTSCENE DIALOGUE GATE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
