--[[--------------------------------------------------------------------
    sim_quest_graph_frame — каркасные блоки графа и видимость чекпоинтов.

    ДВЕ ЖАЛОБЫ ВЛАДЕЛЬЦА (30.08):

    1. «Финиш всё ещё нельзя вынести в граф, не показывается.»

       ПРИЧИНА. У блоков СТАРТ и ФИНИШ, в отличие от всех остальных, НЕТ
       ветки в BlocksToQuest — их координаты никуда не сохранялись. При
       каждом открытии QuestToBlocks ставил их заново по умолчанию:
       ФИНИШ уезжал в колонку 5, то есть на x=1240 при ширине окна ~874.
       Блок физически был, но лежал за краем видимой области, и добавить
       второй мешал флаг once. Со стороны это выглядит как «блока нет».

    2. «Чекпоинт показывается только когда активен какой-либо
       квест/этап.»

       Маркеры расставлялись на карте один раз для всех включённых
       квестов и висели постоянно, у всех игроков сразу. Красные круги
       по всему городу — мусор: игрок видит цель задания, которого не
       брал.

    ЧТО ПРОВЕРЯЕМ:
      * координаты СТАРТ/ФИНИШ переживают сохранение и переоткрытие;
      * при первом открытии они попадают в видимую область холста;
      * маркер чекпоинта виден только тому, у кого квест активен;
      * пройденный чекпоинт скрывается, если он одноразовый.

    Запуск: luajit tools/luatest/sim_quest_graph_frame.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")
local quests = read("lua/autorun/sh_grm_quests.lua")

print("\n=== 1. КООРДИНАТЫ КАРКАСНЫХ БЛОКОВ СОХРАНЯЮТСЯ ===")
--[[ Классическая ловушка этой студии: BlocksToQuest пересобирает квест с
     нуля, и всё, что не перенесли явно, теряется. Так уже пропадали
     graph.links, music, map и флаг момента кат-сцены. У start/finish
     ветки не было вовсе. ]]
local b2q = studio:match("function Q%.BlocksToQuest.-\n    return out\nend") or ""
ok(b2q ~= "", "BlocksToQuest найдена")
ok(b2q:find('b.kind == "finish"', 1, true) ~= nil or b2q:find("out.graph.frame", 1, true) ~= nil,
    "координаты ФИНИША сохраняются")
ok(b2q:find('b.kind == "start"', 1, true) ~= nil or b2q:find("out.graph.frame", 1, true) ~= nil,
    "координаты СТАРТА сохраняются")

print("\n=== 2. НОРМАЛИЗАЦИЯ НА СЕРВЕРЕ ИХ НЕ ТЕРЯЕТ ===")
ok(quests:find("frame", 1, true) ~= nil, "в графе есть место под каркасные блоки")
local ng = quests:match("local function normalizeGraph.-\n    end") or ""
ok(ng:find("frame", 1, true) ~= nil, "нормализация графа переносит их координаты")

print("\n=== 3. ПРИ ПЕРВОМ ОТКРЫТИИ БЛОКИ В ВИДИМОЙ ОБЛАСТИ ===")
--[[ Холст 3000px, но окно студии ~874px по ширине. Колонка 5 это
     x = 40 + 4*300 = 1240 — далеко за краем. Блок есть, а найти его
     нельзя: ровно то, что владелец описал как «не показывается». ]]
local VISIBLE_W = 874
local function colX(col) return 40 + (col - 1) * 300 end
ok(colX(5) > VISIBLE_W, "колонка 5 действительно вне видимой области (это и был баг)",
    ("x=%d при ширине %d"):format(colX(5), VISIBLE_W))

local q2b = studio:match("function Q%.QuestToBlocks.-\n    return blocks") or
            studio:match("function Q%.QuestToBlocks.-\nend") or ""
--[[ Берём и строку ПЕРЕД add("finish"): позиция вычисляется там, а сам
     вызов лишь подставляет переменные. Без этого не видно, откуда взялись
     координаты. ]]
local finishAdd = q2b:match("(local fx, fy[^\n]*\n%s*add%(\"finish\"[^\n]*)") or
                  q2b:match('add%("finish".-\n') or ""
ok(finishAdd ~= "", "блок ФИНИШ создаётся при открытии квеста")
ok(finishAdd:find("frame", 1, true) ~= nil or finishAdd:find("fx", 1, true) ~= nil,
    "у него есть своя позиция")
--[[ Позиция по умолчанию должна попадать в окно: иначе автор при первом
     открытии квеста снова не увидит блок. ]]
ok(q2b:find("FRAME_START_X", 1, true) ~= nil or q2b:find("frameDefault", 1, true) ~= nil,
    "позиция по умолчанию задана явно, а не колонкой за краем экрана")
--[[ Мало объявить константу — ФИНИШ обязан её ИСПОЛЬЗОВАТЬ. Проверяем
     саму строку создания блока: откат на place(5) объявление константы
     не трогает, и проверка выше осталась бы зелёной на сломанном коде
     (поймано откатом). ]]
ok(finishAdd:find("place(5)", 1, true) == nil,
    "ФИНИШ не ставится колонкой за краем холста", finishAdd)
ok(q2b:find('framePos("finish"', 1, true) ~= nil,
    "ФИНИШ берёт сохранённую позицию или заданную по умолчанию")
ok(q2b:find('framePos("start"', 1, true) ~= nil, "СТАРТ тоже")

--[[ Мало объявить константу — она обязана попадать в окно ВМЕСТЕ с
     шириной карточки, иначе блок окажется наполовину срезан. ]]
local CARD_W = tonumber(studio:match("local CARD_W[^=]*=%s*(%d+)")) or 236
local finX = tonumber(studio:match("FRAME_FINISH_X[^=]*=%s*(%d+)")) or 0
ok(finX > 0, "позиция ФИНИША по умолчанию задана", finX)
ok(finX + CARD_W <= VISIBLE_W,
    "ФИНИШ целиком помещается в видимую область при первом открытии",
    ("x=%d + карточка %d = %d, окно %d"):format(finX, CARD_W, finX + CARD_W, VISIBLE_W))

--[[ И не должен перекрывать СТАРТ: два блока в одной точке выглядят как
     один, и владелец снова «не увидит» финиш. ]]
local staX = tonumber(studio:match("FRAME_START_X[^=]*=%s*(%d+)")) or 0
ok(finX >= staX + CARD_W, "ФИНИШ не наезжает на СТАРТ",
    ("старт=%d финиш=%d"):format(staX, finX))

print("\n=== 4. МАРКЕР ЧЕКПОИНТА — ТОЛЬКО ПРИ АКТИВНОМ КВЕСТЕ ===")
--[[ Заказ: «чекпоинт показывается только когда активен какой-либо
     квест/этап». Значит видимость решает КЛИЕНТ по своему прогрессу:
     сервер один на всех, а квест у каждого свой. ]]
local cl = read("lua/entities/grm_quest_checkpoint/cl_init.lua")
ok(cl:find("GRM.Quests", 1, true) ~= nil or cl:find("Q.ClientRows", 1, true) ~= nil,
    "клиент сверяется со своим списком квестов")
ok(cl:find("shouldShow", 1, true) ~= nil, "есть проверка «мой ли это активный квест»")
ok(cl:find('p.status == "active"', 1, true) ~= nil,
    "видимость завязана именно на активный статус квеста")

--[[ Отрисовка обязана прекращаться ЦЕЛИКОМ: и модель, и подпись. Если
     погасить только текст, в мире останется висеть красный круг. ]]
--[[ Берём тело ENT:Draw ЦЕЛИКОМ, до закрывающего end на нулевом отступе.
     Ленивый шаблон обрывался на первом вложенном end (внутри цикла), и
     проверка порядка сравнивала обрывок — давала ложный провал. ]]
local drawFn = cl:match("function ENT:Draw%(%)\n(.-)\nend\n") or ""
ok(drawFn ~= "", "ENT:Draw найдена")
--[[ Ищем по КОДУ, а не по всему тексту: слова return и DrawModel есть и
     в пояснительных комментариях, из-за них порядок считался неверно —
     проверка краснела на правильном коде. Комментарии срезаем. ]]
local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", " ")
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line:gsub("%-%-.*$", "")
    end
    return table.concat(out, "\n")
end
local drawCode = stripComments(drawFn)
ok(drawCode:find("return", 1, true) ~= nil, "есть ранний выход без отрисовки")
local firstReturn = drawCode:find("return", 1, true) or math.huge
local firstDraw = drawCode:find("DrawModel", 1, true) or math.huge
ok(firstReturn < firstDraw,
    "выход стоит ДО DrawModel — иначе круг остался бы висеть без подписи",
    ("return=%s draw=%s"):format(tostring(firstReturn), tostring(firstDraw)))
ok(drawCode:find("shouldShow", 1, true) ~= nil
   and drawCode:find("shouldShow", 1, true) < firstDraw,
    "проверка видимости вызывается до отрисовки модели")

print("\n=== 5. ЖИВОЙ ПРОГОН ВИДИМОСТИ ===")
--[[ Модель повторяет боевое правило: показываем точку, только если у
     игрока есть этот квест в статусе active и точка ещё не пройдена
     (для одноразовых). ]]
local function shouldShow(rows, questID, cpID, reached, once)
    local row = rows[questID]
    if not row or row.status ~= "active" then return false end
    if once ~= false and reached then return false end
    return true
end

local rows = { q_active = { status = "active" }, q_done = { status = "completed" } }
ok(shouldShow(rows, "q_active", "cp1", false, true) == true,
    "квест активен — точка видна")
ok(shouldShow(rows, "q_done", "cp1", false, true) == false,
    "квест завершён — точки нет")
ok(shouldShow(rows, "q_none", "cp1", false, true) == false,
    "квест не взят — точки нет")
ok(shouldShow(rows, "q_active", "cp1", true, true) == false,
    "одноразовая точка пройдена — скрыта")
ok(shouldShow(rows, "q_active", "cp1", true, false) == true,
    "многоразовая остаётся видимой после прохода")

print("\n=== 6. СЕРВЕР НЕ ЗАСОРЯЕТ КАРТУ ===")
--[[ Маркеры существуют как энтити для всех, но раз видимость решает
     клиент, сервер обязан хотя бы не спавнить их для черновиков и
     чужих карт — иначе они копятся молча. ]]
local refresh = quests:match("function Q%.RefreshCheckpointMarkers.-\n    end") or ""
ok(refresh ~= "", "пересборка маркеров на месте")
ok(refresh:find("def.draft", 1, true) ~= nil, "черновики маркеров не получают")
ok(refresh:find("ent:Remove()", 1, true) ~= nil, "старые снимаются перед расстановкой")

print(("\nQUEST GRAPH FRAME: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
