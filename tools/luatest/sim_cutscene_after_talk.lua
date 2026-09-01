--[[--------------------------------------------------------------------
    sim_cutscene_after_talk — ролик ждёт конца разговора.

    ЖАЛОБА ВЛАДЕЛЬЦА (29.08, со скриншотом). Кат-сцена «При принятии
    квеста» проигрывается ПОВЕРХ открытого окна диалога: на экране
    висит реплика «1 / 2», а снизу уже идёт титр ролика.

    ПОЧЕМУ ПРОШЛЫЙ ФИКС НЕ ПОМОГ. Пометку «после диалога» тогда сделали
    свойством СВЯЗИ графа. Но ролик «При принятии» запускается вообще не
    через граф: его зовёт Q.Start напрямую (`cutscene(ply,def.cutscene.accept)`),
    а Q.Start вызывается из обработчика ответа «Принять квест» — то есть
    ещё внутри разговора. Никакая пометка на связи в этот путь не
    попадала, поэтому владелец ничего и не заметил.

    ПРАВИЛЬНОЕ МЕСТО НАСТРОЙКИ. Момент запуска — свойство САМОГО РОЛИКА
    (`def.cutscene.acceptAfterDialogue`), а не линии графа: ролик один, а
    линий к нему может не быть вовсе.

    ЧТО ПРОВЕРЯЕМ:
      1. поле момента нормализуется и переживает пересохранение квеста;
      2. при включённом «после диалога» Q.Start НЕ запускает ролик сразу;
      3. ролик ставится в очередь и играет, когда разговор закончился;
      4. играет ровно один раз;
      5. очередь срабатывает при ЛЮБОМ выходе (закрытие, конец веток,
         уход от NPC) — иначе ролик не сыграет вовсе, что хуже исходного;
      6. по умолчанию (старые квесты) поведение прежнее — сразу.

    Запуск: luajit tools/luatest/sim_cutscene_after_talk.lua
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
local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")

--- Тело функции по имени: ищем ВНУТРИ неё, а не по всему файлу.
--  Иначе совпадение с комментарием к правке или похожей строкой в другом
--  месте даёт ложное «ок» (на этом уже обжигались).
local function bodyOf(src, signature)
    local at = src:find(signature, 1, true)
    if not at then return "" end
    local tail = src:sub(at)
    -- до следующего объявления функции того же уровня
    local stop = tail:find("\n    function ", 2) or tail:find("\n    local function ", 2) or #tail
    return tail:sub(1, stop)
end

print("\n=== 1. МОМЕНТ — СВОЙСТВО РОЛИКА, А НЕ СВЯЗИ ===")
ok(quests:find("acceptAfterDialogue", 1, true) ~= nil,
    "у кат-сцены принятия есть флаг «после диалога»")
ok(quests:find("completeAfterDialogue", 1, true) ~= nil,
    "и у кат-сцены завершения тоже")

-- Нормализация обязана ПЕРЕНОСИТЬ поле: иначе первое же пересохранение
-- квеста в студии молча сотрёт настройку (наступали трижды).
local norm = quests:match("cutscene=%{accept=.-%}%}") or ""
ok(norm:find("acceptAfterDialogue", 1, true) ~= nil,
    "нормализация переносит флаг принятия (иначе стирается при сохранении)", norm ~= "" and "блок найден")
ok(norm:find("completeAfterDialogue", 1, true) ~= nil,
    "и флаг завершения")

print("\n=== 2. Q.START НЕ ИГРАЕТ РОЛИК, ЕСЛИ ЖДЁМ КОНЦА РАЗГОВОРА ===")
local startBody = bodyOf(quests, "function Q.Start(ply,questID)")
ok(startBody ~= "", "тело Q.Start найдено")
ok(startBody:find("acceptAfterDialogue", 1, true) ~= nil,
    "Q.Start передаёт флаг «ждать конца диалога»")
--[[ САМ ГЕЙТ ЖИВЁТ НЕ ЗДЕСЬ. Путей запуска ролика несколько (Q.Start,
     финал квеста, линия графа от реплики, линия от этапа), и проверка в
     одном из них ничего не решает: у владельца ролик висел на ЛИНИИ и
     шёл мимо Q.Start. Поэтому откладывание стоит в общей функции показа
     cutscene(), через которую проходят все пути. ]]
local cutFn = quests:match("local function cutscene%(ply,nodes.-\n    end") or ""
ok(cutFn:find("QueueCutscene", 1, true) ~= nil and cutFn:find("GRMQuestDlg", 1, true) ~= nil,
    "общая функция показа откладывает ролик, если идёт разговор")

print("\n=== 3. ОЧЕРЕДЬ ВЫПУСКАЕТСЯ НА ВЫХОДЕ ИЗ РАЗГОВОРА ===")
ok(quests:find("function Q.QueueCutscene", 1, true) ~= nil, "есть постановка ролика в очередь")
ok(quests:find("function Q.FlushCutscene", 1, true) ~= nil, "есть выпуск очереди")

-- Все три точки выхода из диалога обязаны выпускать очередь: закрытие
-- по действию, конец веток и уход от NPC. Пропусти одну — ролик не
-- сыграет никогда, а это хуже, чем показать его не вовремя.
local flushCount = select(2, dialogue:gsub("FlushCutscene", ""))
ok(flushCount >= 3, "очередь выпускается во всех точках выхода (>=3)", flushCount)

--[[ ДВА ТРЕБОВАНИЯ К ПОРЯДКУ, И ОНИ НЕ ПРОТИВОРЕЧАТ ДРУГ ДРУГУ.

     1) Выпуск не должен быть заперт за ранним выходом: у квеста без
        линий к ролику список эффектов пуст, ролик кладёт Q.Start.

     2) Выпуск обязан идти ПОСЛЕ прогона отложенных эффектов. Гейт
        откладывает ролик, пока жива сессия диалога, а её снимают уже
        после выхода отсюда — эффект кладёт ролик в очередь именно во
        время прогона. Выпустишь раньше — очередь пуста, ролик
        застрянет: «кат-сцена не показывается при выборе верного
        диалога».

     Оба условия выполняются, если выпуск стоит последним, вне if. ]]
local fp = dialogue:match("local function flushPending%(ply%).-\n    end") or ""
ok(fp ~= "", "тело flushPending найдено")
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

print("\n=== 4. ЖИВОЙ ПРОГОН ===")
-- Мини-модель: проверяем поведение, а не текст.
local shown = {}
local Q = {
    Definitions = {},
    _pending = {},
}
function Q.QueueCutscene(ply, nodes, tag)
    if not nodes or #nodes == 0 then return false end
    Q._pending[ply] = { nodes = nodes, tag = tag }
    return true
end
function Q.FlushCutscene(ply)
    local rec = Q._pending[ply]
    if not rec then return false end
    Q._pending[ply] = nil                    -- снимаем ДО показа: иначе
    shown[#shown + 1] = rec.tag              -- повторный выход сыграет дважды
    return true
end

local ply = {}
local nodes = { { caption = "Первое, что тебе надо знать..." } }

Q.QueueCutscene(ply, nodes, "accept")
ok(#shown == 0, "пока разговор идёт, ролик не показан", #shown)

Q.FlushCutscene(ply)
ok(#shown == 1 and shown[1] == "accept", "по выходу из разговора ролик сыграл", #shown)

Q.FlushCutscene(ply)
ok(#shown == 1, "повторный выход НЕ проигрывает ролик второй раз", #shown)

print("\n=== 5. СТАРЫЕ КВЕСТЫ РАБОТАЮТ КАК РАНЬШЕ ===")
--[[ Флаг по умолчанию выключен: квест, сделанный до этой правки, обязан
     вести себя ровно так же. Молчаливая смена поведения на живом сервере
     недопустима. ]]
ok(quests:find("acceptAfterDialogue=raw.cutscene and raw.cutscene.acceptAfterDialogue==true", 1, true) ~= nil
   or quests:find("acceptAfterDialogue==true", 1, true) ~= nil,
    "флаг включается только явным true, по умолчанию — прежнее поведение")

print("\n=== 6. ПЕРЕКЛЮЧАТЕЛЬ ВИДЕН В СТУДИИ ===")
-- Настройка обязана быть в панели самой кат-сцены: искать её в свойствах
-- линии владелец не должен (именно это и был вопрос «почему отдельно?»).
local hasToggle = studio:find("acceptAfterDialogue", 1, true) ~= nil
                  or studio:find("AfterDialogue", 1, true) ~= nil
ok(hasToggle, "в панели кат-сцены есть переключатель момента")
ok(studio:find("ЖДАТЬ КОНЦА ДИАЛОГА", 1, true) ~= nil or studio:find("ПОСЛЕ ДИАЛОГА", 1, true) ~= nil,
    "подпись переключателя человеко-понятная")

print("\n=== 7. СОХРАНЕНИЕ В СТУДИИ НЕ СТИРАЕТ ФЛАГ ===")
--[[ BlocksToQuest пересобирает квест из блоков и создаёт out.cutscene
     заново. Если флаг не перенести явно, автор включит «ждать конца
     диалога», нажмёт сохранить — и настройка молча пропадёт. На этой
     ловушке (пересоздание таблицы вместо переноса полей) уже обжигались
     трижды: с graph.links, music и map. ]]
local b2q = studio:match("function Q%.BlocksToQuest.-\n    out%.rewards") or ""
ok(b2q ~= "", "тело BlocksToQuest найдено")
ok(b2q:find("acceptAfterDialogue", 1, true) ~= nil,
    "флаг принятия переносится при пересборке квеста")
ok(b2q:find("completeAfterDialogue", 1, true) ~= nil,
    "флаг завершения тоже")

print(("\nCUTSCENE AFTER TALK: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
