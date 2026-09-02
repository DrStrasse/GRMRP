--[[--------------------------------------------------------------------
    GRM Quest Studio v3 — ЕДИНЫЙ УЗЛОВОЙ РЕДАКТОР.

    ЗАКАЗ ВЛАДЕЛЬЦА (28.08):

      «Меню квестов лучше всего в единое меню сделать с одной вкладкой,
       но допустим с модульными блоками которые можно вытягивать из
       боковых вкладышей в центральный граф и соединять — кат-сцены,
       диалоги, музыка, ачивки и т.д.»

    ЧТО БЫЛО НЕ ТАК. Редактор состоял из пяти вкладок: Граф, Квест,
    Этапы, Камеры, Награды. Диалог жил на одной вкладке, камеры на
    другой, награды на третьей — и связи между ними существовали только
    в голове автора. Увидеть «после этой реплики играет ролик, потом
    выдаётся награда» было негде.

    ЧТО ТЕПЕРЬ. Одна вкладка и один холст. Слева палитра блоков, их
    вытягивают на холст и соединяют мышью:

        СТАРТ      — точка входа, откуда начинается квест у NPC
        РЕПЛИКА    — узел диалога с ответами игрока
        ЭТАП       — цель, которую выполняет игрок
        КАТ-СЦЕНА  — ролик (камеры настраиваются тулом в мире)
        МУЗЫКА     — звук или трек в точке сюжета
        НАГРАДА    — деньги и предметы
        АЧИВКА     — достижение со своей выплатой
        ФИНИШ      — конец квеста

    ПРИНЦИП ХРАНЕНИЯ. Формат квеста на сервере НЕ ломаем: блоки — это
    представление тех же самых steps / dialogue / cutscene / rewards.
    При сохранении граф разбирается обратно в штатные поля, поэтому
    старые квесты открываются, а новые понимает существующий движок.
    Координаты блоков лежат в _gx/_gy и переживают нормализацию.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Quests = GRM.Quests or {}
local Q = GRM.Quests

surface.CreateFont("GRMQS_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
surface.CreateFont("GRMQS_Head",  { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMQS_Body",  { font = "Roboto", size = 14, weight = 600, extended = true })
surface.CreateFont("GRMQS_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

local COL = {
    bg = Color(12, 16, 24, 252), side = Color(16, 22, 32), card = Color(26, 34, 46),
    node = Color(30, 42, 56), nodeSel = Color(40, 88, 124), line = Color(70, 140, 180, 180),
    accent = Color(70, 190, 200), gold = Color(245, 195, 70), text = Color(235, 240, 248),
    dim = Color(140, 155, 175), red = Color(210, 75, 75), green = Color(70, 185, 110),
}

--[[ ТИПЫ БЛОКОВ. Одна таблица описывает и палитру, и отрисовку, и
     разбор в формат сервера: добавить новый вид блока — значит дописать
     сюда строку, а не править четыре места.
     caption — заголовок блока в графе (строка или функция от данных);
     save    — перенос данных блока в формат квеста (см. Q.BlocksToQuest).
     Раньше и то, и другое жило отдельными лестницами if kind == ..., и
     новый вид блока приходилось синхронно вписывать в три места. ]]
Q.BlockTypes = {
    { id = "start",    name = "СТАРТ",     color = Color(90, 170, 250),  hint = "Точка входа. С неё NPC начинает разговор.", once = true,
      caption = "Начало квеста" },
    { id = "dialogue", name = "РЕПЛИКА",   color = Color(70, 190, 200),  hint = "Слова NPC и ответы игрока.",
      caption = function(d) return tostring(d.text or "") ~= "" and tostring(d.text) or "Новая реплика" end,
      save = function(out, b, d)
          -- фаза обязана быть одной из трёх, иначе квест проигнорирует реплику
          local phase = ({ offer = 1, active = 1, complete = 1 })[tostring(d.phase)] and d.phase or "offer"
          local list = out.dialogue[phase]
          list[#list + 1] = {
              id = tostring(d.id or b.uid), speaker = d.speaker, text = d.text,
              next = d.next, choices = table.Copy(d.choices or {}),
              _gx = math.floor(b.x or 0), _gy = math.floor(b.y or 0),
          }
      end },
    { id = "step",     name = "ЭТАП",      color = Color(245, 195, 70),  hint = "Цель: дойти, принести, убить, поговорить.",
      caption = function(d) return tostring(d.title or "") ~= "" and tostring(d.title) or "Новый этап" end,
      save = function(out, b, d)
          local s = table.Copy(d)
          s._gx, s._gy = math.floor(b.x or 0), math.floor(b.y or 0)
          out.steps[#out.steps + 1] = s
      end },
    { id = "cutscene", name = "КАТ-СЦЕНА", color = Color(180, 130, 240), hint = "Ролик с камерами. Точки ставятся тулом.",
      caption = function(d)
          local n = #(istable(d.cams) and d.cams or {})
          return n > 0 and (n .. " камер") or "Камер нет — поставьте тулом"
      end,
      save = function(out, b, d)
          local phase = d.phase == "complete" and "complete" or "accept"
          local cams = table.Copy(d.cams or {})
          -- координату графа носим первой камерой: тул ставит одну точку на блок
          if cams[1] then
              cams[1]._gx, cams[1]._gy = math.floor(b.x or 0), math.floor(b.y or 0)
          end
          out.cutscene[phase] = cams
      end },
    { id = "music",    name = "МУЗЫКА",    color = Color(240, 140, 190), hint = "Звук или трек в этой точке сюжета.",
      caption = function(d) return tostring(d.sound or "") ~= "" and tostring(d.sound) or "Звук не выбран" end,
      save = function(out, b, d)
          out.music = table.Copy(d)
          out.music._gx, out.music._gy = math.floor(b.x or 0), math.floor(b.y or 0)
      end },
    { id = "reward",   name = "НАГРАДА",   color = Color(70, 185, 110),  hint = "Деньги и предметы.",
      caption = function(d)
          local money = math.floor(tonumber(d.money) or 0)
          local items = 0
          for _ in pairs(istable(d.items) and d.items or {}) do items = items + 1 end
          if money <= 0 and items == 0 then return "Награда не задана" end
          local parts = {}
          if money > 0 then parts[#parts + 1] = money .. " GRM" end
          if items > 0 then parts[#parts + 1] = items .. " предм." end
          return table.concat(parts, " + ")
      end,
      save = function(out, b, d)
          out.rewards.money = math.max(0, math.floor(tonumber(d.money) or 0))
          out.rewards.items = table.Copy(d.items or {})
          out.rewards._gx, out.rewards._gy = math.floor(b.x or 0), math.floor(b.y or 0)
      end },
    { id = "achieve",  name = "АЧИВКА",    color = Color(250, 160, 80),  hint = "Достижение со своей выплатой.",
      caption = function(d) return tostring(d.name or "") ~= "" and tostring(d.name) or "Достижение" end,
      save = function(out, b, d)
          out.achievement = table.Copy(d)
          out.achievement.enabled = true
          out.achievement._gx, out.achievement._gy = math.floor(b.x or 0), math.floor(b.y or 0)
      end },
    { id = "checkpoint", name = "ЧЕКПОИНТ", color = Color(235, 90, 90),  hint = "Точка на карте. Дошёл — сработали связанные блоки.",
      save = function(out, b, d)
          --[[ Чекпоинтов может быть много, поэтому это СПИСОК, а не
               одиночное поле. id блока = id точки: по нему граф ищет
               связи, а прогресс помнит, что точка пройдена. ]]
          out.checkpoints = out.checkpoints or {}
          local cp = table.Copy(d)
          --[[ Пустая строка это НЕ nil: `d.id or b.uid` её не заменит,
               и точка сохранилась бы с пустым id — связи графа тут же
               потеряли бы источник. Проверяем явно. ]]
          local rawID = tostring(d.id or "")
          if rawID == "" then rawID = tostring(b.uid or "") end
          cp.id = rawID:gsub("^cp_", "")
          if cp.id == "" then cp.id = "cp" .. (#(out.checkpoints) + 1) end
          cp._gx, cp._gy = math.floor(b.x or 0), math.floor(b.y or 0)
          out.checkpoints[#out.checkpoints + 1] = cp
      end },
    { id = "finish",   name = "ФИНИШ",     color = Color(210, 75, 75),   hint = "Конец квеста.", once = true,
      caption = "Квест завершён" },
}

local Q_BY_ID = {}
for _, b in ipairs(Q.BlockTypes) do Q_BY_ID[b.id] = b end

function Q.BlockDef(kind)
    return Q_BY_ID[kind] or Q.BlockTypes[2]
end

--- Заголовок блока в графе: коротко и по делу. Формулировка — в Q.BlockTypes
--- рядом с названием и подсказкой, поэтому заголовок не может отстать от вида.
function Q.BlockCaption(block)
    if not istable(block) then return "" end
    local def = Q_BY_ID[block.kind]
    local cap = def and def.caption
    if not cap then return "" end
    if isfunction(cap) then return cap(block.data or {}) end
    return cap
end

--[[ ПЕРЕНОС ТЕКСТА. Блок показывает начало содержимого, а не обрубок на
     полуслове: владелец жаловался на «- Здравствуй, путник! Ви». ]]
function Q.WrapText(text, font, maxW, maxLines)
    surface.SetFont(font)
    local words, lines, cur = {}, {}, ""
    for w in tostring(text or ""):gmatch("%S+") do words[#words + 1] = w end
    for _, w in ipairs(words) do
        local try = cur == "" and w or (cur .. " " .. w)
        if surface.GetTextSize(try) <= maxW then
            cur = try
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            cur = w
            if #lines >= maxLines then break end
        end
    end
    if cur ~= "" and #lines < maxLines then lines[#lines + 1] = cur end
    if #lines == maxLines then
        local total = 0
        for _, l in ipairs(lines) do total = total + #l + 1 end
        if total < #tostring(text or "") then
            local last = lines[maxLines]
            while last ~= "" and surface.GetTextSize(last .. "…") > maxW do
                last = string.sub(last, 1, -2)
            end
            lines[maxLines] = last .. "…"
        end
    end
    return lines
end

-----------------------------------------------------------------------
-- КВЕСТ  <->  ГРАФ БЛОКОВ
-----------------------------------------------------------------------
--[[ Формат на сервере не меняем. Граф — это ПРЕДСТАВЛЕНИЕ квеста:
     собираем блоки из steps/dialogue/cutscene/rewards и разбираем
     обратно. Так старые квесты открываются в новом редакторе, а движок
     продолжает работать с привычными полями. ]]

local function dialogueList(work, phase)
    work.dialogue = work.dialogue or { offer = {}, active = {}, complete = {} }
    local list = work.dialogue[phase]
    if isstring(list) then
        list = list ~= "" and { { id = phase .. "_1", text = list, choices = {} } } or {}
    end
    if istable(list) and istable(list.nodes) then list = list.nodes end
    work.dialogue[phase] = istable(list) and list or {}
    return work.dialogue[phase]
end

function Q.QuestToBlocks(work)
    local blocks, seq = {}, 0
    local function add(kind, data, gx, gy, id)
        seq = seq + 1
        blocks[#blocks + 1] = {
            uid = id or (kind .. "_" .. seq),
            kind = kind, data = data or {},
            x = tonumber(gx) or 0, y = tonumber(gy) or 0,
            links = {},
        }
        return blocks[#blocks]
    end

    --[[ РАСКЛАДКА ПО УМОЛЧАНИЮ (жалоба владельца 31.08: «блоки всё ещё
         за границей графа связей и поля видимости»).

         БЫЛО: x = 40 + (col-1) * 300 и колонки до пятой. Награда и
         ачивка жили в колонке 5, то есть на x = 1240, а колонка росла
         вниз шагом 150 без всякого предела. При десятке реплик блоки
         уезжали и вправо, и вниз — за пределы видимой части холста, где
         их было не схватить и не соединить.

         СТАЛО: шаг колонки уже, а колонка переносится по высоте. Как
         только столбец упирается в нижнюю границу, следующий блок
         начинает столбец заново со сдвигом вправо — всё остаётся в
         пределах холста. ]]
    --[[ Рабочие колонки начинаются НИЖЕ полосы каркаса: сверху стоят
         СТАРТ и ФИНИШ, и без отступа первая же реплика села бы прямо
         на них. Ровно так ФИНИШ и «терялся» — его накрывало карточкой. ]]
    local LAY_X0, LAY_Y0 = 40, 372
    local LAY_COL_W, LAY_ROW_H = 268, 132
    local LAY_MAX_Y = 1700          -- ниже блок уже за краем холста (2000)
    local LAY_MAX_X = 2700          -- правее тоже

    local colY, colShift = {}, {}
    local function place(col)
        colY[col] = colY[col] or LAY_Y0
        colShift[col] = colShift[col] or 0

        local y = colY[col]
        -- Столбец кончился — начинаем рядом, а не уезжаем за нижний край.
        if y > LAY_MAX_Y then
            colShift[col] = colShift[col] + 1
            y = LAY_Y0
            colY[col] = y
        end
        colY[col] = y + LAY_ROW_H

        local x = LAY_X0 + (col - 1) * LAY_COL_W + colShift[col] * LAY_COL_W
        -- Совсем некуда — прижимаем к правому краю, но внутри холста.
        if x > LAY_MAX_X then x = LAY_MAX_X end
        return x, y
    end

    --[[ ПОЗИЦИИ КАРКАСА. Сохранённая раскладка приоритетнее, иначе блок
         прыгал бы обратно при каждом открытии.

         Значения по умолчанию подобраны так, чтобы оба блока попадали в
         ВИДИМУЮ часть холста (окно студии ~874px по ширине). Раньше
         ФИНИШ ставился в колонку 5 — это x=1240, то есть за краем: блок
         существовал, но добраться до него было нельзя. ]]
    local savedFrame = (istable(work.graph) and istable(work.graph.frame)) and work.graph.frame or {}
    --[[ СТАРТ и ФИНИШ — каркас квеста, и они не должны ни наезжать
         друг на друга, ни попадать в рабочие колонки.

         СТАРТ — колонка 1 (place() наполняет 2..5, первая свободна).
         ФИНИШ — ниже старта и со сдвигом вправо: два блока в одной
         точке выглядят как один, и владелец снова «не увидит» финиш.

         Раньше ФИНИШ стоял на x=620 — ровно колонка этапов, и его
         накрывало их карточками: блок был, а соединить его было нечем.
         Обе координаты подобраны так, чтобы карточка (236x104) целиком
         попадала в видимую часть окна при первом открытии. ]]
    local FRAME_START_X, FRAME_START_Y = 40, 40
    local FRAME_FINISH_X, FRAME_FINISH_Y = 308, 220
    local function framePos(name, defX, defY)
        local rec = savedFrame[name]
        if istable(rec) and (tonumber(rec.x) or 0) > 0 then
            return math.floor(rec.x), math.floor(tonumber(rec.y) or 0)
        end
        return defX, defY
    end

    local startX, startY = framePos("start", FRAME_START_X, FRAME_START_Y)
    local startBlock = add("start", {}, startX, startY, "start")

    --[[ Диалоги. Фазу храним в самом блоке: в едином графе иначе
         непонятно, это разговор до квеста или после.

         UID БЛОКА = ID РЕПЛИКИ (исправлено 29.08). Раньше uid был
         «dlg_offer_1», а переходы в next/choices ссылаются на id вроде
         «offer_1». Связи хранятся по uid, значит найти по ним цель было
         невозможно — после переоткрытия квеста ВСЕ линии графа
         пропадали. Владелец это и описал: «не запоминает диалоги,
         сбивает их». ]]
    local dialogueBlocks, firstOffer = {}, nil
    for _, phase in ipairs({ "offer", "active", "complete" }) do
        for i, n in ipairs(dialogueList(work, phase)) do
            local x, y = place(2)
            local nodeID = tostring(n.id or "")
            if nodeID == "" then nodeID = phase .. "_" .. i end
            local b = add("dialogue", {
                phase = phase, id = nodeID, speaker = n.speaker, text = n.text,
                next = n.next, choices = table.Copy(n.choices or {}),
            }, tonumber(n._gx) ~= 0 and n._gx or x, tonumber(n._gy) ~= 0 and n._gy or y,
               nodeID)
            dialogueBlocks[nodeID] = b
            if phase == "offer" and not firstOffer then firstOffer = b end
        end
    end
    --[[ Авто-связь СТАРТ → первая реплика ставим ТОЛЬКО когда своей
         раскладки ещё нет (исправлено 29.08, найдено стендом).

         У блока СТАРТ один выход. Если автоматически занять его
         репликой, сохранённая связь «старт → кат-сцена» при загрузке
         отбрасывалась как дубль порта — владелец соединял блоки, а
         после переоткрытия линия пропадала. Сохранённая раскладка
         всегда приоритетнее догадки. ]]
    local hasSavedGraph = istable(work.graph) and istable(work.graph.links)
        and #work.graph.links > 0
    if firstOffer and not hasSavedGraph then
        startBlock.links[#startBlock.links + 1] = { to = firstOffer.uid, port = 0 }
    end

    --[[ ВОССТАНОВЛЕНИЕ СВЯЗЕЙ. Переходы живут в самих репликах
         (next и choices[i].next), а граф рисует линии по block.links.
         Раньше links при загрузке оставались пустыми — данные были
         целы, но граф выглядел «сбитым». ]]
    for _, b in pairs(dialogueBlocks) do
        local d = b.data
        local nx = tostring(d.next or "")
        if nx ~= "" and dialogueBlocks[nx] then
            b.links[#b.links + 1] = { to = nx, port = 0 }
        end
        for ci, ch in ipairs(d.choices or {}) do
            local cn = tostring(ch.next or "")
            if cn ~= "" and dialogueBlocks[cn] then
                b.links[#b.links + 1] = { to = cn, port = ci }
            end
        end
    end

    for i, s in ipairs(work.steps or {}) do
        local x, y = place(3)
        add("step", table.Copy(s),
            tonumber(s._gx) ~= 0 and s._gx or x,
            tonumber(s._gy) ~= 0 and s._gy or y, "step_" .. i)
    end

    for _, phase in ipairs({ "accept", "complete" }) do
        local cams = (work.cutscene or {})[phase] or {}
        if #cams > 0 then
            local x, y = place(4)
            local first = cams[1] or {}
            add("cutscene", { phase = phase, cams = table.Copy(cams) },
                tonumber(first._gx) ~= 0 and first._gx or x,
                tonumber(first._gy) ~= 0 and first._gy or y, "cut_" .. phase)
        end
    end

    if istable(work.music) and tostring(work.music.sound or "") ~= "" then
        local x, y = place(4)
        add("music", table.Copy(work.music),
            tonumber(work.music._gx) ~= 0 and work.music._gx or x,
            tonumber(work.music._gy) ~= 0 and work.music._gy or y, "music")
    end

    local r = work.rewards or {}
    local rx, ry = place(5)
    add("reward", { money = r.money or 0, items = table.Copy(r.items or {}),
        _gx = r._gx, _gy = r._gy },
        tonumber(r._gx) ~= 0 and r._gx or rx,
        tonumber(r._gy) ~= 0 and r._gy or ry, "reward")

    local a = work.achievement or {}
    if a.enabled then
        local ax, ay = place(5)
        add("achieve", table.Copy(a),
            tonumber(a._gx) ~= 0 and a._gx or ax,
            tonumber(a._gy) ~= 0 and a._gy or ay, "achieve")
    end

    --[[ Чекпоинты. UID = "cp_<id>" ровно как в ядре (Q.CheckpointUID):
         связи графа хранятся по этому имени, и разойтись они не должны. ]]
    for i, cp in ipairs(work.checkpoints or {}) do
        local cx, cy = place(4)
        local cpID = tostring(cp.id or ("cp" .. i))
        add("checkpoint", table.Copy(cp),
            tonumber(cp._gx) ~= 0 and cp._gx or cx,
            tonumber(cp._gy) ~= 0 and cp._gy or cy, "cp_" .. cpID)
    end

    local fx, fy = framePos("finish", FRAME_FINISH_X, FRAME_FINISH_Y)
    add("finish", {}, fx, fy, "finish")

    --[[ ВОССТАНОВЛЕНИЕ СВЯЗЕЙ ГРАФА.

         Диалоговые связи уже собраны выше из самих реплик — их не
         дублируем. Здесь поднимаем всё остальное: старт → кат-сцена,
         кат-сцена → награда и т.д.

         Ссылки на исчезнувшие блоки пропускаем: иначе граф нарисует
         линию в пустоту. ]]
    local byUID = {}
    for _, b in ipairs(blocks) do byUID[b.uid] = b end

    for _, l in ipairs((istable(work.graph) and work.graph.links) or {}) do
        local from, to = byUID[tostring(l.from or "")], byUID[tostring(l.to or "")]
        if from and to and from ~= to then
            local port = math.floor(tonumber(l.port) or 0)
            -- Диалоговые связи уже восстановлены из next/choices.
            local dup = false
            for _, ex in ipairs(from.links) do
                if (ex.port or 0) == port then
                    --[[ Связь уже есть — но режим мог быть задан только в
                         сохранённой раскладке. Переносим его, иначе
                         «после диалога» терялось при переоткрытии. ]]
                    ex.when = (l.when == "after") and "after" or ex.when
                    dup = true break
                end
            end
            if not dup then
                from.links[#from.links + 1] = { to = to.uid, port = port,
                    when = (l.when == "after") and "after" or "now" }
            end
        end
    end

    return blocks
end

--[[ Разбор графа обратно в квест. Возвращает готовую таблицу в штатном
     формате: её и отправляем на сервер. ]]
function Q.BlocksToQuest(work, blocks)
    local out = table.Copy(work or {})
    out.dialogue = { offer = {}, active = {}, complete = {} }
    out.steps = {}
    --[[ Камеры пересобираем из блоков, а ФЛАГИ МОМЕНТА переносим.
         Пересоздание таблицы с нуля стирало acceptAfterDialogue при
         первом же сохранении: автор включал «ждать конца диалога», жал
         сохранить — и настройка молча пропадала. ]]
    --[[ Список пересобираем с нуля: удалённый в студии блок обязан
         исчезнуть и из квеста, иначе маркер остался бы на карте. ]]
    out.checkpoints = {}
    out.cutscene = {
        accept = {}, complete = {},
        acceptAfterDialogue = (work and work.cutscene and work.cutscene.acceptAfterDialogue) == true,
        completeAfterDialogue = (work and work.cutscene and work.cutscene.completeAfterDialogue) == true,
    }
    out.rewards = { money = 0, items = {} }
    out.music = nil

    -- Диспетчер: как именно блок переносится в квест, знает сам вид
    -- (Q.BlockTypes[...].save). Порядок обхода — порядок блоков, он и был
    -- единым проходом; неизвестный вид молча пропустим, как и раньше.
    for _, b in ipairs(blocks or {}) do
        local def = Q_BY_ID[b.kind]
        if def and def.save then def.save(out, b, b.data or {}) end
    end

    --[[ СВЯЗИ ГРАФА (исправлено 29.08: «связь в графе с кат-сценой не
         устанавливается»).

         Переходы между репликами живут в самих репликах, поэтому они
         сохранялись. А связи с кат-сценой, музыкой, наградой и ачивкой
         не хранились НИГДЕ: соединил блоки, сохранил, переоткрыл — линий
         нет. Складываем всю раскладку связей отдельным полем.

         Пишем по uid: блоки можно двигать и удалять, порядок не важен. ]]
    out.graph = { links = {}, frame = {} }
    --[[ КАРКАС (СТАРТ и ФИНИШ). У них нет своих данных в квесте, поэтому
         позицию храним в графе. Без этого редактор при каждом открытии
         ставил их заново по умолчанию, и ФИНИШ уезжал за правый край
         холста — владелец видел это как «блок нельзя вынести в граф». ]]
    for _, b in ipairs(blocks or {}) do
        if b.kind == "start" or b.kind == "finish" then
            out.graph.frame[b.kind] = { x = math.floor(b.x or 0), y = math.floor(b.y or 0) }
        end
    end
    for _, b in ipairs(blocks or {}) do
        for _, l in ipairs(b.links or {}) do
            out.graph.links[#out.graph.links + 1] = {
                from = tostring(b.uid or ""),
                to = tostring(l.to or ""),
                port = math.floor(tonumber(l.port) or 0),
                -- Момент запуска: сразу при показе реплики или после разговора.
                when = (l.when == "after") and "after" or "now",
            }
        end
    end

    --[[ Ачивку выключаем явно, если блока нет: иначе удалённый блок
         продолжал бы выдавать достижение. ]]
    local hasAch = false
    for _, b in ipairs(blocks or {}) do if b.kind == "achieve" then hasAch = true end end
    if not hasAch then
        out.achievement = out.achievement or {}
        out.achievement.enabled = false
    end

    return out
end

-----------------------------------------------------------------------
-- ОКНО
-----------------------------------------------------------------------
local function mkBtn(p, txt, col)
    local b = vgui.Create("DButton", p)
    b:SetText(txt) b:SetFont("GRMQS_Body") b:SetTextColor(COL.text)
    b.Paint = function(s, w, h)
        local c = col or COL.card
        if s:IsHovered() then c = Color(math.min(255, c.r + 22), math.min(255, c.g + 22), math.min(255, c.b + 22)) end
        draw.RoundedBox(6, 0, 0, w, h, c)
    end
    return b
end

local function field(parent, title, val, multi)
    local l = vgui.Create("DLabel", parent)
    l:Dock(TOP) l:SetTall(16) l:DockMargin(10, 8, 10, 0)
    l:SetText(title) l:SetFont("GRMQS_Small") l:SetTextColor(COL.dim)
    local e = vgui.Create("DTextEntry", parent)
    e:Dock(TOP) e:SetTall(multi and 90 or 26) e:DockMargin(10, 2, 10, 0)
    e:SetMultiline(multi == true) e:SetText(tostring(val or ""))
    return e
end

local CARD_W, CARD_H, PORT = 236, 104, 13

function Q.OpenGraphStudio(data)
    if IsValid(Q.StudioFrame) then Q.StudioFrame:Remove() end
    data = istable(data) and data or {}
    local defs = data.definitions or {}
    local work, blocks, selected, linking = nil, {}, 0, nil
    local rebuildCards, rebuildProps, rebuildList
    -- Объявлены заранее: их зовёт addBlock, объявленный выше по файлу.
    -- Без этого имена были бы глобальными (nil на момент вызова).
    local scrollToBlock, findFreeSpot

    local f = vgui.Create("DFrame")
    Q.StudioFrame, Q.AdminFrame = f, f
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("quest_studio", f) end
    f:SetSize(math.Clamp(ScrW() - 36, 1180, 1760), math.Clamp(ScrH() - 36, 720, 1020))
    f:Center() f:SetTitle("") f:MakePopup() f:ShowCloseButton(false)
    f.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, COL.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 48, COL.side, true, true, false, false)
        draw.SimpleText("QUEST STUDIO", "GRMQS_Title", 16, 24, COL.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        --[[ ID В ШАПКЕ (заказ владельца 28.08). Он нужен постоянно: на
             него ссылаются «предыдущие квесты», команды сброса и логи.
             Раньше его негде было подсмотреть, не открывая файл. ]]
        local head = work and ((work.title or work.id) .. (work.draft and "  · черновик" or "")) or "нет квеста"
        draw.SimpleText(head, "GRMQS_Small", w / 2, 16, COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if work then
            draw.SimpleText("ID: " .. tostring(work.id or ""), "GRMQS_Small", w / 2, 33,
                COL.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local close = mkBtn(f, "X", COL.red)
    close:SetSize(34, 26)
    close.DoClick = function() f:Close() end
    f.PerformLayout = function(_, w) if IsValid(close) then close:SetPos(w - 42, 11) end end

    local left = vgui.Create("DScrollPanel", f)
    left:Dock(LEFT) left:SetWide(232) left:DockMargin(0, 48, 0, 0)
    left.Paint = function(_, w, h) surface.SetDrawColor(COL.side) surface.DrawRect(0, 0, w, h) end

    local right = vgui.Create("DScrollPanel", f)
    right:Dock(RIGHT) right:SetWide(330) right:DockMargin(0, 48, 0, 0)
    right.Paint = function(_, w, h) surface.SetDrawColor(COL.side) surface.DrawRect(0, 0, w, h) end

    local mid = vgui.Create("DPanel", f)
    mid:Dock(FILL) mid:DockMargin(0, 48, 0, 0)
    mid.Paint = function(_, w, h)
        surface.SetDrawColor(20, 26, 36) surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(30, 38, 50)
        for x = 0, w, 32 do surface.DrawLine(x, 36, x, h) end
        for y = 36, h, 32 do surface.DrawLine(0, y, w, y) end
    end

    local bar = vgui.Create("DPanel", mid)
    bar:Dock(TOP) bar:SetTall(36)
    bar.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(18, 24, 34))
        draw.SimpleText("Тяни блок из палитры слева на холст. Соединяй кружки-порты мышью. ПКМ по порту — убрать связь.",
            "GRMQS_Small", 12, h / 2, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local CANVAS_W, CANVAS_H = 3000, 2000

    local canvas = vgui.Create("DPanel", mid)
    canvas:SetPos(0, 36)
    canvas:SetSize(CANVAS_W, CANVAS_H)
    canvas:SetPaintBackground(false)

    --[[ ПАНОРАМИРОВАНИЕ ХОЛСТА (жалоба владельца 31.08: «вынос полос и
         блоков за пределы видимости»).

         КОРЕНЬ ПРОБЛЕМЫ. Холст 3000x2000 лежал в панели Dock(FILL)
         БЕЗ КАКОЙ-ЛИБО ПРОКРУТКИ. Видно было только левый верхний угол
         размером с окно (~870x900). Всё, что оказывалось правее или
         ниже, пропадало НАВСЕГДА: доскроллить туда было нечем, мышью
         не достать, вернуть блок обратно невозможно.

         Именно поэтому награда и ачивка «терялись»: блоки ставились по
         сетке вниз и вправо и уезжали за видимую границу.

         Теперь холст можно двигать: ПКМ или средняя кнопка по пустому
         месту — тянуть, колесо — вертикально, Shift+колесо —
         горизонтально. Смещение всегда в пределах холста, улететь в
         пустоту нельзя. ]]
    local panX, panY = 0, 0

    local function viewSize()
        return mid:GetWide(), math.max(1, mid:GetTall() - 36)
    end

    local function applyPan()
        local vw, vh = viewSize()
        -- Не пускаем холст дальше его краёв: справа и снизу должна
        -- оставаться геометрия, а не пустота за пределами холста.
        local minX = math.min(0, vw - CANVAS_W)
        local minY = math.min(0, vh - CANVAS_H)
        panX = math.Clamp(panX, minX, 0)
        panY = math.Clamp(panY, minY, 0)
        canvas:SetPos(panX, 36 + panY)
    end
    applyPan()

    --[[ Показать блок. Если он вне видимой области, подвинуть холст так,
         чтобы карточка попала в неё целиком, с небольшим полем. ]]
    scrollToBlock = function(b)
        if not b then return end
        local vw, vh = viewSize()
        local M = 40
        local bx, by = b.x or 0, b.y or 0
        if bx + panX < M then panX = M - bx end
        if bx + CARD_W + panX > vw - M then panX = vw - M - bx - CARD_W end
        if by + panY < M then panY = M - by end
        if by + CARD_H + panY > vh - M then panY = vh - M - by - CARD_H end
        applyPan()
    end

    local function blockByUID(uid)
        for _, b in ipairs(blocks) do if b.uid == tostring(uid) then return b end end
    end

    --[[ Свободное место под новый блок.

         Ищем по сетке в ВИДИМОЙ сейчас области: блок должен появиться
         там, где игрок смотрит, а не за краем. Клетка считается занятой,
         если карточка пересекается с уже стоящей (с запасом на зазор). ]]
    findFreeSpot = function()
        local vw, vh = viewSize()
        local stepX, stepY = CARD_W + 28, CARD_H + 24
        local startX = math.max(20, -panX + 24)
        local startY = math.max(20, -panY + 24)
        local function occupied(x, y)
            for _, ob in ipairs(blocks) do
                local ox, oy = ob.x or 0, ob.y or 0
                if x < ox + CARD_W + 12 and x + CARD_W + 12 > ox
                    and y < oy + CARD_H + 12 and y + CARD_H + 12 > oy then
                    return true
                end
            end
            return false
        end
        -- Сначала пробуем уместиться в видимом окне.
        local cols = math.max(1, math.floor((vw - 48) / stepX))
        local rows = math.max(1, math.floor((vh - 48) / stepY))
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local x, y = startX + c * stepX, startY + r * stepY
                if not occupied(x, y) then return x, y end
            end
        end
        -- Видимое занято — ищем по всему холсту.
        for y = 20, CANVAS_H - CARD_H, stepY do
            for x = 20, CANVAS_W - CARD_W, stepX do
                if not occupied(x, y) then return x, y end
            end
        end
        -- Совсем некуда: ставим в начало, но внутри холста.
        return 40, 40
    end

    --[[ Порты. Выход справа, вход слева. У реплики с ответами — по порту
         на каждый ответ, чтобы развилка была видна как развилка. ]]
    local function outPortPos(b, slot, count)
        local x = (b.x or 0) + CARD_W
        local y = (b.y or 0) + 30
        if count and count > 0 then
            y = (b.y or 0) + 44 + (slot - 0.5) * (CARD_H - 54) / count
        end
        return x, y
    end
    local function inPortPos(b) return (b.x or 0), (b.y or 0) + 30 end

    local function portCount(b)
        if b.kind == "dialogue" then return #((b.data or {}).choices or {}) end
        return 0
    end

    canvas.Paint = function(_, cw, chh)
        --[[ ЛИНИЯ СВЯЗИ. Жалоба владельца 31.08: «линия к блоку награда
             рисуется вообще хрен пойми куда».

             Формула была одна на все случаи:
                 C1 = x1 + dx,  C2 = x2 - dx,  dx = |x2-x1| * 0.5

             Для связи СЛЕВА НАПРАВО это верно. Но если цель ЛЕВЕЕ
             источника (награда левее кат-сцены на скриншоте),
             контрольные точки выворачиваются: C1 уезжает за спину цели,
             C2 — за спину источника. Кривая делает широкую петлю сквозь
             чужие карточки. Замер на координатах со скриншота: вылет
             37 px за пределы обоих блоков в каждую сторону.

             Для обратной связи вынос ограничиваем: петля остаётся
             аккуратной и огибает блоки, а не улетает за экран. ]]
        local function curve(x1, y1, x2, y2, col)
            local back = x2 < x1
            local dx
            if back then
                dx = math.min(90, math.max(40, math.abs(x2 - x1) * 0.25))
            else
                dx = math.max(40, math.abs(x2 - x1) * 0.5)
            end
            local px, py = x1, y1
            surface.SetDrawColor(col)
            for i = 1, 18 do
                local t = i / 18
                local mt = 1 - t
                local x = mt^3 * x1 + 3 * mt^2 * t * (x1 + dx) + 3 * mt * t^2 * (x2 - dx) + t^3 * x2
                --[[ У обратной связи разводим линию по вертикали: иначе
                     она накладывается на прямые связи между теми же
                     блоками и читается как одна. ]]
                local bend = back and 26 or 0
                local y = mt^3 * y1 + 3 * mt^2 * t * (y1 + bend) + 3 * mt * t^2 * (y2 + bend) + t^3 * y2
                surface.DrawLine(px, py, x, y)
                px, py = x, y
            end
            surface.DrawLine(x2, y2, x2 - 8, y2 - 5)
            surface.DrawLine(x2, y2, x2 - 8, y2 + 5)
        end

        for _, b in ipairs(blocks) do
            local cnt = portCount(b)
            for _, lnk in ipairs(b.links or {}) do
                local t = blockByUID(lnk.to)
                if t then
                    local x1, y1 = outPortPos(b, lnk.port or 0, cnt)
                    local x2, y2 = inPortPos(t)
                    curve(x1, y1, x2, y2, (lnk.port or 0) > 0 and Color(120, 200, 140, 200) or COL.line)
                end
            end
        end

        if linking and linking.from then
            local x1, y1 = outPortPos(linking.from, linking.slot, portCount(linking.from))
            local mx, my = canvas:CursorPos()
            surface.SetDrawColor(COL.gold)
            surface.DrawLine(x1, y1, mx, my)
            draw.SimpleText("отпустите на нужном блоке", "GRMQS_Small", mx + 12, my + 6, COL.gold)
        end
    end

    local function linkBlocks(from, slot, to)
        if not (from and to) or from == to then return false end
        from.links = from.links or {}
        -- Один выход — одна связь: иначе поток раздваивается молча.
        for i = #from.links, 1, -1 do
            if (from.links[i].port or 0) == slot then table.remove(from.links, i) end
        end
        from.links[#from.links + 1] = { to = to.uid, port = slot }
        --[[ Связь от ответа игрока дублируем в сам ответ: движок диалогов
             читает choices[i].next, а не граф. Без этого связь была бы
             только картинкой. ]]
        if from.kind == "dialogue" and slot > 0 then
            local ch = (from.data.choices or {})[slot]
            if ch and to.kind == "dialogue" then ch.next = tostring(to.data.id or to.uid) end
        elseif from.kind == "dialogue" and slot == 0 and to.kind == "dialogue" then
            from.data.next = tostring(to.data.id or to.uid)
        end
        return true
    end

    local function unlink(b, slot)
        for i = #(b.links or {}), 1, -1 do
            if (b.links[i].port or 0) == slot then table.remove(b.links, i) end
        end
        if b.kind == "dialogue" then
            if slot > 0 then
                local ch = (b.data.choices or {})[slot]
                if ch then ch.next = "" end
            else
                b.data.next = ""
            end
        end
    end

    rebuildCards = function()
        for _, c in ipairs(canvas:GetChildren()) do c:Remove() end

        local function makePort(card, b, slot, count, cy)
            local port = vgui.Create("DPanel", card)
            port:SetSize(PORT, PORT)
            port:SetPos(CARD_W - PORT / 2 - 1, cy - PORT / 2)
            port:SetCursor("hand")
            port.Paint = function(_, w, h)
                local linked = false
                for _, l in ipairs(b.links or {}) do if (l.port or 0) == slot then linked = true end end
                local col = slot > 0 and Color(120, 200, 140) or COL.line
                draw.RoundedBox(w / 2, 0, 0, w, h, linked and col or Color(60, 74, 92))
                if linking and linking.from == b and linking.slot == slot then
                    surface.SetDrawColor(COL.gold) surface.DrawOutlinedRect(0, 0, w, h, 2)
                end
            end
            port.OnMousePressed = function(_, mc)
                if mc == MOUSE_RIGHT then unlink(b, slot) rebuildCards() return end
                linking = { from = b, slot = slot }
            end
        end

        for i, b in ipairs(blocks) do
            local def = Q.BlockDef(b.kind)
            local card = vgui.Create("DPanel", canvas)
            card:SetPos(b.x or 40, b.y or 40)
            card:SetSize(CARD_W, CARD_H)
            card.Paint = function(_, w, h)
                local sel = selected == i
                draw.RoundedBox(8, 0, 0, w, h, sel and COL.nodeSel or COL.node)
                if sel then surface.SetDrawColor(COL.accent) surface.DrawOutlinedRect(0, 0, w, h, 2) end
                -- Цветная шапка = тип блока: видно с одного взгляда.
                draw.RoundedBoxEx(8, 0, 0, w, 24, def.color, true, true, false, false)
                draw.SimpleText(def.name, "GRMQS_Small", 10, 12, Color(16, 20, 28), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if b.kind == "dialogue" then
                    draw.SimpleText(tostring((b.data or {}).phase or "offer"), "GRMQS_Small", w - 10, 12,
                        Color(16, 20, 28), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                local lines = Q.WrapText(Q.BlockCaption(b), "GRMQS_Small", w - 22, 3)
                for li, line in ipairs(lines) do
                    draw.SimpleText(line, "GRMQS_Small", 10, 34 + (li - 1) * 15, COL.text)
                end

                --[[ Показываем, что блок запускается ЛИНИЕЙ, а не своей
                     фазой: иначе непонятно, работает связь или нет. ]]
                local driven = false
                for _, ob in ipairs(blocks) do
                    for _, l in ipairs(ob.links or {}) do
                        if l.to == b.uid then driven = true break end
                    end
                    if driven then break end
                end
                if driven and (b.kind == "cutscene" or b.kind == "music"
                    or b.kind == "reward" or b.kind == "achieve") then
                    --[[ Показываем и МОМЕНТ: без этого «после разговора»
                         видно только в панели, и на графе непонятно,
                         почему ролик идёт не сразу. ]]
                    local after = false
                    for _, ob in ipairs(blocks) do
                        for _, l in ipairs(ob.links or {}) do
                            if l.to == b.uid and l.when == "after" then after = true break end
                        end
                        if after then break end
                    end
                    draw.SimpleText(after and "◀ после диалога" or "◀ по линии",
                        "GRMQS_Small", w - 10, h - 12,
                        COL.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                if b.kind == "dialogue" then
                    local chs = (b.data or {}).choices or {}
                    local foot = #chs > 0 and (#chs .. " отв.") or "линейно"
                    for _, c in ipairs(chs) do
                        if tostring(c.action or "") == "accept" then foot = foot .. "  ·  ВЫДАЁТ КВЕСТ" break end
                    end
                    draw.SimpleText(foot, "GRMQS_Small", 10, h - 12, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end

            local grip = vgui.Create("DPanel", card)
            grip:SetPos(0, 0) grip:SetSize(CARD_W - PORT * 2, 24)
            grip:SetPaintBackground(false) grip:SetCursor("sizeall")
            grip.OnMousePressed = function(self, mc)
                if mc ~= MOUSE_LEFT then return end
                selected = i
                local mx, my = card:CursorPos()
                self._drag, self._ox, self._oy = true, mx, my
                rebuildProps()
            end
            grip.OnMouseReleased = function(self) self._drag = false end
            grip.Think = function(self)
                if self._drag and input.IsMouseDown(MOUSE_LEFT) then
                    local px, py = canvas:CursorPos()
                    --[[ Ограничиваем ВСЕ четыре стороны. Раньше стояло
                         только math.max(0, ...) — слева блок упирался в
                         край, а вправо и вниз уезжал за пределы холста,
                         откуда его было не достать. ]]
                    b.x = math.Clamp(px - (self._ox or 0), 0, CANVAS_W - CARD_W)
                    b.y = math.Clamp(py - (self._oy or 0), 0, CANVAS_H - CARD_H)
                    card:SetPos(b.x, b.y)
                elseif self._drag then self._drag = false end
            end

            card.OnMousePressed = function(_, mc)
                if mc ~= MOUSE_LEFT then return end
                selected = i rebuildProps()
            end
            card.OnMouseReleased = function()
                if linking and linking.from and linking.from ~= b then
                    linkBlocks(linking.from, linking.slot, b)
                end
                linking = nil
                rebuildCards() rebuildProps()
            end

            local cnt = portCount(b)
            if b.kind ~= "finish" then
                if cnt == 0 then
                    makePort(card, b, 0, 0, 30)
                else
                    for ci = 1, cnt do
                        local _, py = outPortPos(b, ci, cnt)
                        makePort(card, b, ci, cnt, py - (b.y or 0))
                    end
                end
            end
        end
    end

    --[[ Тянуть холст ПКМ или средней кнопкой. Левая занята связями и
         перетаскиванием карточек, поэтому панорамирование — на другой
         кнопке, иначе одно мешало бы другому. ]]
    canvas.OnMousePressed = function(self, mc)
        if mc == MOUSE_RIGHT or mc == MOUSE_MIDDLE then
            local mx, my = gui.MousePos()
            self._pan, self._px, self._py = true, mx, my
            self._sx, self._sy = panX, panY
            self:MouseCapture(true)
        end
    end
    canvas.OnMouseReleased = function(self, mc)
        linking = nil
        if self._pan then
            self._pan = false
            self:MouseCapture(false)
        end
    end
    canvas.OnMouseWheeled = function(_, delta)
        -- Shift — горизонталь: граф растёт вправо, и ходить по нему
        -- вдоль приходится чаще, чем вниз.
        if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then
            panX = panX + delta * 90
        else
            panY = panY + delta * 90
        end
        applyPan()
        return true
    end
    canvas.Think = function(self)
        if linking and not input.IsMouseDown(MOUSE_LEFT) then linking = nil end
        if self._pan then
            if input.IsMouseDown(MOUSE_RIGHT) or input.IsMouseDown(MOUSE_MIDDLE) then
                local mx, my = gui.MousePos()
                panX = (self._sx or 0) + (mx - (self._px or mx))
                panY = (self._sy or 0) + (my - (self._py or my))
                applyPan()
            else
                self._pan = false
                self:MouseCapture(false)
            end
        end
    end

    --[[ ПАЛИТРА. Кнопка добавляет блок в центр видимой области холста:
         «вытянуть из бокового вкладыша», как и просил владелец. ]]
    local function addBlock(kind)
        if not work then return end
        local def = Q.BlockDef(kind)
        if def.once then
            for _, b in ipairs(blocks) do
                if b.kind == kind then
                    notification.AddLegacy("Такой блок уже есть", NOTIFY_HINT, 3)
                    return
                end
            end
        end
        local data = {}
        if kind == "dialogue" then
            --[[ ID должен быть УНИКАЛЕН. Раньше брали os.time(): две
                 реплики, созданные в одну секунду, получали одинаковый
                 ID, сервер схлопывал их в одну, а переходы уводили не
                 туда. Ищем первый свободный номер среди существующих. ]]
            local used = {}
            for _, ob in ipairs(blocks) do
                if ob.kind == "dialogue" then used[tostring((ob.data or {}).id or "")] = true end
            end
            local n = 1
            while used["node_" .. n] do n = n + 1 end
            data = { phase = "offer", id = "node_" .. n,
                speaker = work.npc or "NPC", text = "Новая реплика", next = "", choices = {} }
        elseif kind == "step" then
            data = { type = "event", title = "Новый этап", event = "generic", count = 1 }
        elseif kind == "cutscene" then
            data = { phase = "accept", cams = {} }
        elseif kind == "music" then
            data = { sound = "", loop = false }
        elseif kind == "reward" then
            data = { money = 0, items = {} }
        elseif kind == "achieve" then
            data = { enabled = true, id = "quest_" .. tostring(work.id or ""),
                name = work.title or "Достижение", description = work.summary or "", reward = 0 }
        elseif kind == "checkpoint" then
            --[[ Свой id ОБЯЗАТЕЛЕН и должен быть уникален: по нему
                 строится uid блока, по нему же граф ищет связи, а
                 прогресс помнит пройденные точки. Без него две точки
                 схлопнулись бы в одну.

                 Ищем первый свободный номер, а не берём os.time(): две
                 точки, созданные в одну секунду, получили бы одинаковый
                 id — на этом уже обжигались с репликами. ]]
            local used = {}
            for _, ob in ipairs(blocks) do
                if ob.kind == "checkpoint" then used[tostring((ob.data or {}).id or "")] = true end
            end
            local n = 1
            while used["cp" .. n] do n = n + 1 end
            data = { id = "cp" .. n, label = "Чекпоинт " .. n, radius = 96,
                once = true, advanceStep = false }
        end
        --[[ UID НОВОГО БЛОКА (исправлено 29.08).

             Движок опознаёт блоки по uid: этапы как «step_N», эффекты по
             постоянному имени. Случайный uid вида «step_48231_3» после
             сохранения превращался в «step_1» — связи, нарисованные до
             сохранения, теряли цель.

             Поэтому uid сразу такой же, каким его сделает загрузка. ]]
        local uid
        if kind == "step" then
            local n = 0
            for _, ob in ipairs(blocks) do if ob.kind == "step" then n = n + 1 end end
            uid = "step_" .. (n + 1)
        elseif kind == "dialogue" then
            uid = data.id
        elseif kind == "cutscene" then
            uid = "cut_" .. (data.phase == "complete" and "complete" or "accept")
        elseif kind == "checkpoint" then
            --[[ Ровно то имя, каким блок соберёт загрузка (Q.CheckpointUID
                 в ядре и QuestToBlocks здесь же). Раньше uid был просто
                 "checkpoint", а после переоткрытия становился
                 "cp_checkpoint" — связь теряла источник и линия
                 пропадала. Владелец видел это как «чекпоинт нельзя
                 связать с наградой и ачивкой». ]]
            uid = "cp_" .. tostring(data.id)
        else
            uid = kind == "achieve" and "achieve" or kind
        end

        --[[ МЕСТО ДЛЯ НОВОГО БЛОКА (жалоба владельца 31.08: «проблемы с
             размещением блока наград и ачивок и их соединением с
             другими блоками»).

             Раньше координата была ЖЁСТКОЙ: x = 320, y = 120 + шаг по
             остатку от деления на 5. Шестой блок ложился ровно на
             первый, седьмой — на второй и так далее. Награда и ачивка
             добавляются последними, поэтому именно они регулярно
             оказывались ПОД уже стоящим блоком: карточка невидима,
             порт связи накрыт чужой карточкой, соединить нечем.

             Теперь ищем свободное место сеткой: идём по колонкам и
             строкам и берём первую клетку, где нет пересечения с уже
             стоящими блоками. Если всё занято — ставим в конец, но
             внутри холста. ]]
        local nx, ny = findFreeSpot()
        blocks[#blocks + 1] = {
            uid = uid,
            kind = kind, data = data, x = nx, y = ny, links = {},
        }
        selected = #blocks
        rebuildCards() rebuildProps()
        -- Показать только что добавленный блок: если он оказался за
        -- краем видимой области, игрок решит, что кнопка не сработала.
        if scrollToBlock then scrollToBlock(blocks[#blocks]) end
    end

    -----------------------------------------------------------------
    -- ПРАВАЯ ПАНЕЛЬ: свойства выбранного блока
    -----------------------------------------------------------------
    rebuildProps = function()
        right:Clear()
        local b = blocks[selected]
        local head = vgui.Create("DLabel", right)
        head:Dock(TOP) head:SetTall(26) head:DockMargin(10, 10, 10, 4)
        head:SetFont("GRMQS_Head") head:SetTextColor(COL.gold)
        head:SetText(b and Q.BlockDef(b.kind).name or "БЛОК НЕ ВЫБРАН")

        if not work then return end
        if not b then
            local hint = vgui.Create("DLabel", right)
            hint:Dock(TOP) hint:SetTall(150) hint:DockMargin(10, 8, 10, 8)
            hint:SetWrap(true) hint:SetFont("GRMQS_Small") hint:SetTextColor(COL.dim)
            hint:SetText("Слева — палитра блоков. Нажми, чтобы добавить на холст.\n\nТяни блок за цветную шапку.\n\nСоединяй: тяни от кружка справа к другому блоку. ПКМ по кружку — убрать связь.\n\nЗелёные кружки у реплики — ответы игрока, каждый ведёт куда захочешь.")
            return
        end

        local d = b.data or {}
        local hint = vgui.Create("DLabel", right)
        hint:Dock(TOP) hint:SetTall(32) hint:DockMargin(10, 0, 10, 4)
        hint:SetWrap(true) hint:SetFont("GRMQS_Small") hint:SetTextColor(COL.dim)
        hint:SetText(Q.BlockDef(b.kind).hint)

        if b.kind == "dialogue" then
            local ph = vgui.Create("DComboBox", right)
            ph:Dock(TOP) ph:SetTall(26) ph:DockMargin(10, 6, 10, 0)
            ph:AddChoice("До принятия квеста", "offer", d.phase == "offer" or d.phase == nil)
            ph:AddChoice("Во время квеста", "active", d.phase == "active")
            ph:AddChoice("После завершения", "complete", d.phase == "complete")
            ph.OnSelect = function(_, _, _, v) d.phase = v rebuildCards() end

            local idE = field(right, "ID реплики", d.id)
            local spE = field(right, "Говорящий", d.speaker)
            local txE = field(right, "Текст реплики", d.text, true)

            --[[ ТЕКСТ ПРИМЕНЯЕТСЯ СРАЗУ (исправлено 29.08).

                 Раньше значения попадали в квест только по кнопке
                 «Применить». Набрал реплику, кликнул другой блок или
                 сразу «Сохранить» — текст терялся, потому что панель
                 пересобиралась из старых данных. Это и есть «не
                 запоминает диалоги».

                 Пишем в d по каждому изменению. Кнопка оставлена: она
                 нужна для смены ID, где требуется перестроить связи. ]]
            spE.OnChange = function(e) d.speaker = e:GetValue() end
            txE.OnChange = function(e) d.text = e:GetValue() rebuildCards() end

            local apply = mkBtn(right, "Применить ID", COL.green)
            apply:Dock(TOP) apply:SetTall(30) apply:DockMargin(10, 10, 10, 6)
            apply.DoClick = function()
                local oldID = tostring(d.id or "")
                local newID = string.Trim(idE:GetValue() or "")
                if newID == "" or newID == oldID then return end

                --[[ Переименование ID обязано ПЕРЕПИСАТЬ ссылки на него.
                     Иначе переходы других реплик указывают в пустоту, и
                     разговор молча обрывается на середине. ]]
                for _, ob in ipairs(blocks) do
                    if ob.kind == "dialogue" then
                        local od = ob.data or {}
                        if tostring(od.next or "") == oldID then od.next = newID end
                        for _, ch in ipairs(od.choices or {}) do
                            if tostring(ch.next or "") == oldID then ch.next = newID end
                        end
                    end
                    for _, l in ipairs(ob.links or {}) do
                        if l.to == oldID then l.to = newID end
                    end
                end
                d.id, b.uid = newID, newID
                rebuildCards() rebuildProps()
            end

            --[[ КОГДА СРАБАТЫВАЮТ ЭФФЕКТЫ ЭТОЙ РЕПЛИКИ (заказ владельца
                 29.08: «кат-сцена срабатывает ещё до момента пока не
                 прошёл диалог, сделай для неё настройку срабатывать
                 после диалога»).

                 Настройка на самой связи, а не на кат-сцене: один ролик
                 может быть подключён к нескольким репликам, и момент у
                 каждой свой. ]]
            local outLinks = {}
            for _, l in ipairs(b.links or {}) do outLinks[#outLinks + 1] = l end
            if #outLinks > 0 then
                local hdr = vgui.Create("DLabel", right)
                hdr:Dock(TOP) hdr:SetTall(20) hdr:DockMargin(10, 10, 10, 0)
                hdr:SetFont("GRMQS_Small") hdr:SetTextColor(COL.gold)
                hdr:SetText("КОГДА ЗАПУСКАТЬ ПОДКЛЮЧЁННОЕ")

                for _, l in ipairs(outLinks) do
                    local target = l.to
                    local row = vgui.Create("DButton", right)
                    row:Dock(TOP) row:SetTall(34) row:DockMargin(10, 4, 10, 0) row:SetText("")
                    row.Paint = function(sp, w, h)
                        local after = (l.when == "after")
                        draw.RoundedBox(5, 0, 0, w, h, sp:IsHovered() and Color(34, 46, 62) or COL.card)
                        draw.RoundedBox(0, 0, 0, 4, h, after and COL.accent or COL.gold)
                        draw.SimpleText("→ " .. tostring(target), "GRMQS_Small", 10, 9, COL.text)
                        draw.SimpleText(after and "после разговора" or "сразу при показе реплики",
                            "GRMQS_Small", 10, 23, after and COL.accent or COL.dim)
                    end
                    row.DoClick = function()
                        --[[ Переключаем по клику: две кнопки на связь
                             заняли бы всю панель, а связей может быть
                             несколько. ]]
                        l.when = (l.when == "after") and "now" or "after"
                        rebuildCards() rebuildProps()
                    end
                end

                local note = vgui.Create("DLabel", right)
                note:Dock(TOP) note:SetTall(40) note:DockMargin(10, 4, 10, 4)
                note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
                note:SetText("Клик по строке меняет момент. «После разговора» — ролик не перекроет текст, который игрок ещё читает.")
            end

            local addCh = mkBtn(right, "+ Ответ игрока", COL.card)
            addCh:Dock(TOP) addCh:SetTall(26) addCh:DockMargin(10, 4, 10, 4)
            addCh.DoClick = function()
                d.choices = d.choices or {}
                d.choices[#d.choices + 1] = { text = "Новый ответ", next = "", action = "" }
                rebuildCards() rebuildProps()
            end
            for ci, ch in ipairs(d.choices or {}) do
                local box = vgui.Create("DPanel", right)
                box:Dock(TOP) box:SetTall(84) box:DockMargin(10, 4, 10, 0)
                box.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, COL.card) end
                local t = vgui.Create("DTextEntry", box) t:SetPos(6, 6) t:SetSize(296, 22) t:SetText(ch.text or "")
                t.OnChange = function(s) ch.text = s:GetValue() rebuildCards() end
                local act = vgui.Create("DComboBox", box) act:SetPos(6, 32) act:SetSize(180, 22)
                act:AddChoice("продолжить", "", (ch.action or "") == "")
                act:AddChoice("ПРИНЯТЬ КВЕСТ", "accept", ch.action == "accept")
                act:AddChoice("закрыть", "close", ch.action == "close")
                act.OnSelect = function(_, _, _, v) ch.action = v rebuildCards() end
                local del = mkBtn(box, "Удалить", COL.red)
                del:SetPos(6, 58) del:SetSize(90, 20)
                del.DoClick = function() table.remove(d.choices, ci) rebuildCards() rebuildProps() end
            end

        elseif b.kind == "step" then
            --[[ ПОЛНАЯ НАСТРОЙКА ЭТАПА (дозаполнено 28.08).

                 Раньше панель показывала только тип, название, одну цель
                 и количество. Поля target / radius / consume / описание
                 существовали в формате квеста и в старом редакторе, но в
                 узловой панели их не было — этап нельзя было донастроить,
                 не открывая старую студию.

                 Поля показываем ПО ТИПУ этапа: у «принести предмет» нет
                 радиуса, у «посетить место» нет счётчика событий. Так
                 автор не гадает, какие из восьми полей относятся к делу. ]]
            local typ = vgui.Create("DComboBox", right)
            typ:Dock(TOP) typ:SetTall(26) typ:DockMargin(10, 6, 10, 0)
            for _, k in ipairs({ { "Посетить место", "visit" }, { "Поговорить с NPC", "talk" },
                                 { "Событие/счётчик", "event" }, { "Иметь предмет", "item" } }) do
                typ:AddChoice(k[1], k[2], d.type == k[2])
            end
            typ.OnSelect = function(_, _, _, v) d.type = v rebuildProps() end

            --[[ Поля пишутся СРАЗУ, а не по кнопке: иначе набранное
                 теряется при клике на другой блок. Та же причина, что
                 и у реплик. ]]
            local ti = field(right, "Название для игрока", d.title)
            ti.OnChange = function(e) d.title = e:GetValue() rebuildCards() end
            local ds = field(right, "Пояснение (необязательно)", d.description)
            ds.OnChange = function(e) d.description = e:GetValue() end

            -- Главная цель этапа: смысл поля зависит от типа.
            local tgt, tgt2, rad, cons
            if d.type == "talk" then
                tgt = field(right, "ID NPC", d.npc)
            elseif d.type == "item" then
                tgt = field(right, "ID предмета", d.item)
                cons = vgui.Create("DCheckBoxLabel", right)
                cons:Dock(TOP) cons:SetTall(22) cons:DockMargin(10, 8, 10, 0)
                cons:SetText("Изъять предметы при сдаче") cons:SetTextColor(COL.text)
                cons:SetValue(d.consume == true)
                cons.OnChange = function(_, v) d.consume = v end
            elseif d.type == "visit" then
                rad = field(right, "Радиус точки", tostring(d.radius or 120))
            else
                tgt = field(right, "Событие", d.event)
                --[[ Цель события: пустая означает «любая». Без этого поля
                     нельзя было сделать «добыть именно железо». ]]
                tgt2 = field(right, "Цель события (пусто = любая)", d.target)
            end

            local cnt = field(right, "Количество", tostring(d.count or 1))

            local apply = mkBtn(right, "Применить", COL.green)
            apply:Dock(TOP) apply:SetTall(30) apply:DockMargin(10, 10, 10, 6)
            apply.DoClick = function()
                d.title = ti:GetValue()
                d.description = ds:GetValue()
                d.count = math.max(1, math.floor(tonumber(cnt:GetValue()) or 1))
                if d.type == "talk" then d.npc = tgt:GetValue()
                elseif d.type == "item" then d.item = tgt:GetValue()
                elseif d.type == "visit" then
                    d.radius = math.Clamp(math.floor(tonumber(rad:GetValue()) or 120), 24, 10000)
                else
                    d.event = tgt:GetValue()
                    d.target = tgt2:GetValue()
                end
                rebuildCards()
            end

            if d.type == "visit" then
                local tool = mkBtn(right, "Задать зону тулом", Color(70, 90, 50))
                tool:Dock(TOP) tool:SetTall(28) tool:DockMargin(10, 4, 10, 6)
                tool.DoClick = function()
                    --[[ НОМЕР ЭТАПА ОБЯЗАТЕЛЕН (найдено при ревизии тула
                         28.08). Тул пишет зону в steps[номер], а студия
                         его не передавала — оставался номер от прошлого
                         раза, и зона молча уезжала в ЧУЖОЙ этап.

                         Считаем позицию блока среди этапов: сервер
                         хранит их обычным массивом в том же порядке. ]]
                    local idx = 0
                    for _, ob in ipairs(blocks) do
                        if ob.kind == "step" then
                            idx = idx + 1
                            if ob == b then break end
                        end
                    end
                    --[[ Зону тул пишет в УЖЕ СОХРАНЁННЫЙ квест. Если блок
                         только что создан, на сервере его ещё нет —
                         сохраняем, иначе тул ответит «этап не найден». ]]
                    local out = Q.BlocksToQuest(work, blocks)
                    out.draft = #(out.steps or {}) == 0
                    net.Start("GRM_Quest_AdminOp")
                    net.WriteString("save") net.WriteTable(out) net.SendToServer()

                    RunConsoleCommand("grm_quest_tool_mode", "zone")
                    RunConsoleCommand("grm_quest_tool_quest_id", work.id or "")
                    RunConsoleCommand("grm_quest_tool_step", tostring(idx))
                    RunConsoleCommand("gmod_tool", "grm_quest_tool")
                    notification.AddLegacy("Этап " .. idx .. ": ЛКМ — первый угол, ПКМ — второй", NOTIFY_HINT, 6)
                end
                -- Показываем, задана зона или нет: без неё этап не работает.
                local zoneNote = vgui.Create("DLabel", right)
                zoneNote:Dock(TOP) zoneNote:SetTall(34) zoneNote:DockMargin(10, 2, 10, 6)
                zoneNote:SetWrap(true) zoneNote:SetFont("GRMQS_Small")
                local hasZone = istable(d.min) and istable(d.max) or istable(d.pos)
                zoneNote:SetTextColor(hasZone and COL.green or COL.red)
                zoneNote:SetText(hasZone and "Зона задана." or "Зона НЕ задана — этап не выполнится.")
            end

            local hintEv = vgui.Create("DLabel", right)
            hintEv:Dock(TOP) hintEv:SetTall(46) hintEv:DockMargin(10, 4, 10, 6)
            hintEv:SetWrap(true) hintEv:SetFont("GRMQS_Small") hintEv:SetTextColor(COL.dim)
            hintEv:SetText("Событие: mining, factory_produce, inventory_gain, ore_sell и любое из API. Этапы выполняются строго по порядку сверху вниз.")

        elseif b.kind == "cutscene" then
            --[[ ПОЛНАЯ НАСТРОЙКА КАМЕР (дозаполнено 28.08).

                 Раньше у камеры правились только титр и длительность.
                 FOV, тип перехода и время пролёта существовали в формате
                 и в старой студии, но здесь их не было — снять
                 кинематографичный проезд было нельзя.

                 Камеры редактируем по одной: выбранная разворачивается в
                 полный набор полей. Показывать восемь полей у каждой из
                 десяти камер сразу — панель превратится в простыню. ]]
            local ph = vgui.Create("DComboBox", right)
            ph:Dock(TOP) ph:SetTall(26) ph:DockMargin(10, 6, 10, 0)
            ph:AddChoice("При принятии квеста", "accept", d.phase ~= "complete")
            ph:AddChoice("При завершении квеста", "complete", d.phase == "complete")
            ph.OnSelect = function(_, _, _, v)
                --[[ Фаза входит в uid блока: без переименования связь
                     осталась бы указывать на «cut_accept», которого уже
                     нет. Переписываем ссылки, как при смене ID реплики. ]]
                local oldUID = tostring(b.uid or "")
                local newUID = "cut_" .. (v == "complete" and "complete" or "accept")
                if oldUID ~= newUID then
                    for _, ob in ipairs(blocks) do
                        for _, l in ipairs(ob.links or {}) do
                            if l.to == oldUID then l.to = newUID end
                        end
                    end
                    b.uid = newUID
                end
                d.phase = v
                rebuildCards()
            end

            local add = mkBtn(right, "+ Камера из взгляда", COL.green)
            add:Dock(TOP) add:SetTall(30) add:DockMargin(10, 8, 10, 4)
            add.DoClick = function()
                d.cams = d.cams or {}
                d.cams[#d.cams + 1] = {
                    id = "camera_" .. (#d.cams + 1), next = "",
                    transition = #d.cams == 0 and "cut" or "move",
                    moveDuration = 1, duration = 3, fov = 75, caption = "",
                    sound = "", image = "",
                    pos = { x = EyePos().x, y = EyePos().y, z = EyePos().z },
                    ang = { p = EyeAngles().p, y = EyeAngles().y, r = EyeAngles().r },
                }
                if d.cams[#d.cams - 1] then d.cams[#d.cams - 1].next = d.cams[#d.cams].id end
                b._cam = #d.cams
                rebuildCards() rebuildProps()
            end

            --[[ Список камер: строка — одна камера. Клик разворачивает
                 её настройки ниже. Первая всегда стартовая, это видно. ]]
            for ci, cam in ipairs(d.cams or {}) do
                local row = vgui.Create("DButton", right)
                row:Dock(TOP) row:SetTall(30) row:DockMargin(10, 3, 10, 0) row:SetText("")
                row.Paint = function(s, w, h)
                    local sel = b._cam == ci
                    draw.RoundedBox(5, 0, 0, w, h, sel and COL.nodeSel or COL.card)
                    local mark = ci == 1 and "СТАРТ" or (cam.transition == "move" and "пролёт" or "склейка")
                    draw.SimpleText(ci .. ". " .. (tostring(cam.caption or "") ~= "" and cam.caption or "без титра"),
                        "GRMQS_Small", 8, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(mark, "GRMQS_Small", w - 34, h / 2, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
                row.DoClick = function() b._cam = ci rebuildProps() end
                local del = mkBtn(row, "×", COL.red) del:SetPos(276, 4) del:SetSize(24, 22)
                del.DoClick = function()
                    table.remove(d.cams, ci)
                    b._cam = nil
                    rebuildCards() rebuildProps()
                end
            end

            local cam = (d.cams or {})[b._cam or 0]
            if cam then
                local box = vgui.Create("DPanel", right)
                box:Dock(TOP) box:SetTall(24) box:DockMargin(10, 10, 10, 0)
                box.Paint = function(_, w, h)
                    draw.RoundedBox(5, 0, 0, w, h, Color(20, 30, 44))
                    draw.SimpleText("КАМЕРА " .. tostring(b._cam), "GRMQS_Small", 8, h / 2,
                        COL.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                local cap = field(right, "Титр на экране", cam.caption)
                cap.OnChange = function(e) cam.caption = e:GetValue() rebuildCards() end
                local dur = field(right, "Показ точки, сек", tostring(cam.duration or 3))
                dur.OnChange = function(e) cam.duration = math.Clamp(tonumber(e:GetValue()) or 3, 0.25, 30) end
                local fov = field(right, "FOV (20-120, меньше = ближе)", tostring(cam.fov or 75))
                fov.OnChange = function(e) cam.fov = math.Clamp(tonumber(e:GetValue()) or 75, 20, 120) end

                --[[ Тип перехода. У первой камеры он всегда «мгновенно»:
                     сцена стартует в ней, лететь неоткуда. ]]
                local tr
                if b._cam > 1 then
                    tr = vgui.Create("DComboBox", right)
                    tr:Dock(TOP) tr:SetTall(26) tr:DockMargin(10, 8, 10, 0)
                    tr:AddChoice("Мгновенно (склейка)", "cut", cam.transition ~= "move")
                    tr:AddChoice("Плавный пролёт", "move", cam.transition == "move")
                    tr.OnSelect = function(_, _, _, v) cam.transition = v rebuildProps() end
                end
                local mv
                if b._cam > 1 and cam.transition == "move" then
                    mv = field(right, "Время пролёта, сек", tostring(cam.moveDuration or 1))
                end

                local snd = field(right, "Звук в этой точке", cam.sound)
                --[[ Поле пишется сразу: иначе выбранный в браузере путь
                     терялся при клике на другую камеру. ]]
                snd.OnChange = function(e) cam.sound = e:GetValue() end

                --[[ КНОПКА ВЫБОРА ЗВУКА (заказ владельца 29.08).

                     Раньше путь вписывали руками: ошибся в букве —
                     тишина без объяснений, а какие звуки вообще есть на
                     сервере, узнать было неоткуда. Браузер сканирует
                     игру и аддоны и даёт послушать до выбора. ]]
                local pickSnd = mkBtn(right, "Выбрать звук из списка", Color(58, 82, 112))
                pickSnd:Dock(TOP) pickSnd:SetTall(26) pickSnd:DockMargin(10, 4, 10, 2)
                pickSnd.DoClick = function()
                    if not (GRM.SoundBrowser and GRM.SoundBrowser.Open) then
                        notification.AddLegacy("Браузер звуков не загружен", NOTIFY_ERROR, 4)
                        return
                    end
                    GRM.SoundBrowser.Open(function(path)
                        cam.sound = path
                        if IsValid(snd) then snd:SetText(path) end
                        rebuildCards()
                    end, cam.sound)
                end

                local testSnd = mkBtn(right, "▶ Прослушать звук точки", COL.card)
                testSnd:Dock(TOP) testSnd:SetTall(24) testSnd:DockMargin(10, 0, 10, 4)
                testSnd.DoClick = function()
                    local path = string.Trim(tostring(cam.sound or ""))
                    if path == "" then
                        notification.AddLegacy("Звук не задан", NOTIFY_HINT, 3) return
                    end
                    --[[ Через браузер: он глушит предыдущий трек. Иначе
                         повторные нажатия наслаивали бы звуки друг на
                         друга — та же беда, что была в списке звуков. ]]
                    if GRM.SoundBrowser and GRM.SoundBrowser.Play then
                        GRM.SoundBrowser.Play(path)
                    else
                        surface.PlaySound((path:gsub("^sound/", "")))
                    end
                end

                local img = field(right, "Картинка (материал)", cam.image)

                local applyCam = mkBtn(right, "Применить камеру", COL.green)
                applyCam:Dock(TOP) applyCam:SetTall(28) applyCam:DockMargin(10, 10, 10, 4)
                applyCam.DoClick = function()
                    cam.caption = cap:GetValue()
                    cam.duration = math.Clamp(tonumber(dur:GetValue()) or 3, 0.25, 30)
                    cam.fov = math.Clamp(tonumber(fov:GetValue()) or 75, 20, 120)
                    if mv then cam.moveDuration = math.Clamp(tonumber(mv:GetValue()) or 1, 0.05, 30) end
                    cam.sound, cam.image = snd:GetValue(), img:GetValue()
                    rebuildCards()
                end

                local reaim = mkBtn(right, "Переснять с текущего взгляда", Color(70, 90, 50))
                reaim:Dock(TOP) reaim:SetTall(26) reaim:DockMargin(10, 2, 10, 4)
                reaim.DoClick = function()
                    cam.pos = { x = EyePos().x, y = EyePos().y, z = EyePos().z }
                    cam.ang = { p = EyeAngles().p, y = EyeAngles().y, r = EyeAngles().r }
                    notification.AddLegacy("Камера " .. tostring(b._cam) .. " переснята", NOTIFY_GENERIC, 3)
                end
            end

            local play = mkBtn(right, "▶ Просмотр всей сцены", COL.gold)
            play:Dock(TOP) play:SetTall(28) play:DockMargin(10, 8, 10, 6)
            play.DoClick = function()
                if #(d.cams or {}) == 0 then
                    notification.AddLegacy("Сначала добавьте камеры", NOTIFY_HINT, 3) return
                end
                --[[ ЗАПУСК ПРОСМОТРА (исправлено 29.08).

                     Раньше кнопка только слала пакет серверу, а тот
                     настраивал видимость мира и обратно ничего не
                     присылал — сцена не начиналась. Теперь запускаем
                     локально через Q.StartCutscene, а он сам сообщит
                     серверу о просмотре. ]]
                if not isfunction(Q.StartCutscene) then
                    notification.AddLegacy("Модуль кат-сцен не загружен", NOTIFY_ERROR, 4)
                    return
                end
                f:SetVisible(false)
                Q.StartCutscene(table.Copy(d.cams), true)
                if Q.Cutscene then Q.Cutscene.restoreFrame = f end
            end

            --[[ ГЛАВНЫЙ ПЕРЕКЛЮЧАТЕЛЬ МОМЕНТА — ПЕРВЫМ ДЕЛОМ.

                 Владелец 29.08: «так и где для кат-сцены правило, чтобы
                 она запускалась после диалога?» и следом — ролик всё
                 равно шёл поверх открытого диалога «1 / 2».

                 ПОЧЕМУ РАНЬШЕ НЕ РАБОТАЛО. Момент был свойством СВЯЗИ
                 графа. Но ролик «При принятии» запускает Q.Start, а его
                 зовут из ответа «Принять квест» — то есть внутри
                 разговора, мимо графа. Пометка на линии в этот путь не
                 попадала вообще.

                 ТЕПЕРЬ это свойство САМОГО РОЛИКА и стоит первым в его
                 панели: ролик один, а линий к нему может не быть вовсе. ]]
            local afterKey = (d.phase == "complete") and "completeAfterDialogue" or "acceptAfterDialogue"
            work.cutscene = work.cutscene or {}

            local waitHdr = vgui.Create("DLabel", right)
            waitHdr:Dock(TOP) waitHdr:SetTall(20) waitHdr:DockMargin(10, 8, 10, 0)
            waitHdr:SetFont("GRMQS_Small") waitHdr:SetTextColor(COL.gold)
            waitHdr:SetText("КОГДА ЗАПУСКАТЬ ЭТОТ РОЛИК")

            local waitBtn = vgui.Create("DButton", right)
            waitBtn:Dock(TOP) waitBtn:SetTall(46) waitBtn:DockMargin(10, 4, 10, 0) waitBtn:SetText("")
            waitBtn.Paint = function(sp, w, h)
                local wait = work.cutscene[afterKey] == true
                draw.RoundedBox(5, 0, 0, w, h, sp:IsHovered() and Color(34, 46, 62) or COL.card)
                draw.RoundedBox(0, 0, 0, 4, h, wait and COL.accent or COL.gold)
                draw.SimpleText(wait and "ЖДАТЬ КОНЦА ДИАЛОГА" or "СРАЗУ",
                    "GRMQS_Body", 12, 11, wait and COL.accent or COL.gold)
                draw.SimpleText(wait
                        and "Ролик дождётся, пока игрок дочитает и закроет разговор"
                        or "Ролик стартует в момент события — может перекрыть диалог",
                    "GRMQS_Small", 12, 29, COL.dim)
            end
            waitBtn.DoClick = function()
                work.cutscene[afterKey] = not (work.cutscene[afterKey] == true)
                rebuildProps()
            end

            --[[ Ниже — тонкая настройка для тех, кто ведёт ролик ЛИНИЕЙ от
                 конкретной реплики. Это отдельный случай: переключатель
                 выше решает вопрос для обычного «при принятии/завершении». ]]
            local incoming = {}
            for _, ob in ipairs(blocks) do
                for _, l in ipairs(ob.links or {}) do
                    if l.to == b.uid then
                        incoming[#incoming + 1] = { link = l, from = ob }
                    end
                end
            end

            local drivenNote = vgui.Create("DLabel", right)
            drivenNote:Dock(TOP) drivenNote:SetTall(46) drivenNote:DockMargin(10, 6, 10, 4)
            drivenNote:SetWrap(true) drivenNote:SetFont("GRMQS_Small")
            drivenNote:SetTextColor(#incoming > 0 and COL.accent or COL.dim)
            drivenNote:SetText(#incoming > 0
                and "Запускается ЛИНИЕЙ: сработает там, где вы её подключили, а не по фазе."
                or "Сейчас играет по своей фазе. Протяните линию от реплики или этапа, чтобы задать точный момент.")

            if #incoming > 0 then
                local hdr = vgui.Create("DLabel", right)
                hdr:Dock(TOP) hdr:SetTall(20) hdr:DockMargin(10, 6, 10, 0)
                hdr:SetFont("GRMQS_Small") hdr:SetTextColor(COL.gold)
                hdr:SetText("ОТДЕЛЬНО ПО КАЖДОЙ ЛИНИИ")

                for _, row in ipairs(incoming) do
                    local l, fromBlock = row.link, row.from
                    --[[ Для реплики момент имеет смысл: её текст читают.
                         Для этапа и старта разговора нет, там «после
                         диалога» ничего не изменит — так и пишем, чтобы
                         автор не искал несуществующую разницу. ]]
                    local isDialogue = fromBlock.kind == "dialogue"
                    local btn = vgui.Create("DButton", right)
                    btn:Dock(TOP) btn:SetTall(38) btn:DockMargin(10, 4, 10, 0) btn:SetText("")
                    btn.Paint = function(sp, w, h)
                        local after = (l.when == "after")
                        draw.RoundedBox(5, 0, 0, w, h, sp:IsHovered() and Color(34, 46, 62) or COL.card)
                        draw.RoundedBox(0, 0, 0, 4, h, after and COL.accent or COL.gold)
                        --[[ Показываем, от какого ОТВЕТА идёт линия. Без
                             этого автор не видел разницы между «связь
                             реплики» (сработает всегда) и «связь ответа»
                             (только при выборе этого варианта) — и ролик
                             казался привязанным к обоим ответам сразу. ]]
                        local port = tonumber(l.port) or 0
                        local src = "от: " .. tostring(fromBlock.uid)
                        if port > 0 then
                            local answers = (fromBlock.data or {}).choices or {}
                            local a = answers[port]
                            local text = a and tostring(a.text or "") or ""
                            if text ~= "" then
                                if #text > 34 then text = string.sub(text, 1, 34) .. "…" end
                                src = ("ответ %d: %s"):format(port, text)
                            else
                                src = ("ответ %d"):format(port)
                            end
                        end
                        draw.SimpleText(src, "GRMQS_Small", 10, 10, port > 0 and COL.gold or COL.text)
                        if isDialogue then
                            local moment = after and "ПОСЛЕ диалога" or "СРАЗУ при показе реплики"
                            if port > 0 then
                                moment = after and "ПОСЛЕ диалога, только при этом ответе"
                                                or "при выборе этого ответа"
                            end
                            draw.SimpleText(moment,
                                "GRMQS_Small", 10, 26, after and COL.accent or COL.dim)
                        else
                            draw.SimpleText("сразу (у этого блока нет диалога)",
                                "GRMQS_Small", 10, 26, COL.dim)
                        end
                    end
                    btn.DoClick = function()
                        if not isDialogue then
                            notification.AddLegacy("Момент важен только для связи от реплики", NOTIFY_HINT, 4)
                            return
                        end
                        l.when = (l.when == "after") and "now" or "after"
                        rebuildCards() rebuildProps()
                    end
                end

                local tip = vgui.Create("DLabel", right)
                tip:Dock(TOP) tip:SetTall(44) tip:DockMargin(10, 4, 10, 4)
                tip:SetWrap(true) tip:SetFont("GRMQS_Small") tip:SetTextColor(COL.dim)
                tip:SetText("Клик по строке меняет момент. «ПОСЛЕ диалога» — ролик дождётся, пока игрок дочитает и закроет разговор.")
            end

            local tool = mkBtn(right, "Ставить точки тулом в мире", Color(58, 82, 112))
            tool:Dock(TOP) tool:SetTall(26) tool:DockMargin(10, 2, 10, 6)
            tool.DoClick = function()
                RunConsoleCommand("grm_quest_tool_mode", "cutscene")
                RunConsoleCommand("grm_quest_tool_quest_id", work.id or "")
                RunConsoleCommand("grm_quest_tool_phase", d.phase or "accept")
                RunConsoleCommand("gmod_tool", "grm_quest_tool")
            end

        elseif b.kind == "music" then
            --[[ МОМЕНТ ВОСПРОИЗВЕДЕНИЯ (дозаполнено 28.08).

                 Раньше блок хранил только путь к звуку, и было неясно,
                 когда он заиграет. Теперь момент выбирается явно и
                 сохраняется в квест — движок читает его при событии. ]]
            local when = vgui.Create("DComboBox", right)
            when:Dock(TOP) when:SetTall(26) when:DockMargin(10, 6, 10, 0)
            for _, k in ipairs({ { "При принятии квеста", "start" },
                                 { "При завершении этапа", "step" },
                                 { "При завершении квеста", "complete" } }) do
                when:AddChoice(k[1], k[2], (d.when or "start") == k[2])
            end
            when.OnSelect = function(_, _, _, v) d.when = v rebuildCards() end

            local snd = field(right, "Путь к звуку", d.sound)
            snd.OnChange = function(e) d.sound = e:GetValue() rebuildCards() end

            -- Тот же браузер, что и у камер: руками пути не набирают.
            local pickMusic = mkBtn(right, "Выбрать звук из списка", Color(58, 82, 112))
            pickMusic:Dock(TOP) pickMusic:SetTall(26) pickMusic:DockMargin(10, 4, 10, 2)
            pickMusic.DoClick = function()
                if not (GRM.SoundBrowser and GRM.SoundBrowser.Open) then
                    notification.AddLegacy("Браузер звуков не загружен", NOTIFY_ERROR, 4)
                    return
                end
                GRM.SoundBrowser.Open(function(path)
                    d.sound = path
                    if IsValid(snd) then snd:SetText(path) end
                    rebuildCards()
                end, d.sound)
            end
            local vol = field(right, "Громкость 0.1 - 1.0", tostring(d.volume or 1))
            vol.OnChange = function(e) d.volume = math.Clamp(tonumber(e:GetValue()) or 1, 0.1, 1) end
            local lp = vgui.Create("DCheckBoxLabel", right)
            lp:Dock(TOP) lp:SetTall(22) lp:DockMargin(10, 8, 10, 0)
            lp:SetText("Зациклить (фоновая музыка)") lp:SetTextColor(COL.text) lp:SetValue(d.loop == true)
            lp.OnChange = function(_, v) d.loop = v end

            local apply = mkBtn(right, "Применить", COL.green)
            apply:Dock(TOP) apply:SetTall(30) apply:DockMargin(10, 10, 10, 4)
            apply.DoClick = function()
                d.sound = snd:GetValue()
                d.volume = math.Clamp(tonumber(vol:GetValue()) or 1, 0.1, 1)
                rebuildCards()
            end
            local test = mkBtn(right, "▶ Прослушать", COL.card)
            test:Dock(TOP) test:SetTall(26) test:DockMargin(10, 4, 10, 6)
            test.DoClick = function()
                local path = string.Trim(snd:GetValue() or "")
                if path ~= "" then
                    if GRM.SoundBrowser and GRM.SoundBrowser.Play then
                        GRM.SoundBrowser.Play(path)
                    else
                        surface.PlaySound(path)
                    end
                end
            end
            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(58) note:DockMargin(10, 4, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Пример: music/hl2_song20_submix0.mp3 или ambient/atmosphere/city_beat1.wav\nЗациклённый трек останавливается в конце квеста.")

        elseif b.kind == "reward" then
            local mon = field(right, "Деньги за квест", tostring(d.money or 0))
            mon.OnChange = function(e)
                d.money = math.max(0, math.floor(tonumber(e:GetValue()) or 0))
                rebuildCards()
            end
            local itemID = field(right, "ID предмета", "")
            local itemN = field(right, "Количество", "1")
            local addI = mkBtn(right, "Добавить предмет", COL.green)
            addI:Dock(TOP) addI:SetTall(28) addI:DockMargin(10, 8, 10, 4)
            addI.DoClick = function()
                local id = string.Trim(itemID:GetValue() or "")
                if id ~= "" then
                    d.items = d.items or {}
                    d.items[id] = math.max(1, math.floor(tonumber(itemN:GetValue()) or 1))
                    rebuildCards() rebuildProps()
                end
            end
            for id, c in pairs(d.items or {}) do
                local row = vgui.Create("DPanel", right)
                row:Dock(TOP) row:SetTall(26) row:DockMargin(10, 2, 10, 0)
                row.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, COL.card)
                    draw.SimpleText(id .. "  ×" .. tostring(c), "GRMQS_Small", 8, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local del = mkBtn(row, "×", COL.red) del:SetPos(276, 3) del:SetSize(24, 20)
                del.DoClick = function() d.items[id] = nil rebuildCards() rebuildProps() end
            end
            local apply = mkBtn(right, "Применить", COL.green)
            apply:Dock(TOP) apply:SetTall(30) apply:DockMargin(10, 10, 10, 6)
            apply.DoClick = function()
                d.money = math.max(0, math.floor(tonumber(mon:GetValue()) or 0))
                rebuildCards()
            end
            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(46) note:DockMargin(10, 4, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Выдаётся автоматически при закрытии последнего этапа. Подключать ничего не нужно.")

        elseif b.kind == "achieve" then
            --[[ ID выведен наружу (дозаполнено 28.08): раньше он молча
                 подставлялся из ID квеста, и две ачивки разных квестов
                 могли столкнуться, а переименовать было негде. ]]
            local aid = field(right, "ID достижения (только латиница)", d.id ~= "" and d.id or ("quest_" .. tostring(work.id or "")))
            local nm = field(right, "Название", d.name)
            nm.OnChange = function(e) d.name = e:GetValue() rebuildCards() end
            local ds = field(right, "Описание", d.description, true)
            ds.OnChange = function(e) d.description = e:GetValue() end
            local rw = field(right, "Деньги за ачивку", tostring(d.reward or 0))
            rw.OnChange = function(e) d.reward = math.max(0, math.floor(tonumber(e:GetValue()) or 0)) end
            local hid = vgui.Create("DCheckBoxLabel", right)
            hid:Dock(TOP) hid:SetTall(22) hid:DockMargin(10, 8, 10, 0)
            hid:SetText("Скрытая до получения") hid:SetTextColor(COL.text) hid:SetValue(d.hidden == true)
            hid.OnChange = function(_, v) d.hidden = v end
            local apply = mkBtn(right, "Применить", COL.green)
            apply:Dock(TOP) apply:SetTall(30) apply:DockMargin(10, 10, 10, 6)
            apply.DoClick = function()
                d.name, d.description = nm:GetValue(), ds:GetValue()
                d.reward = math.max(0, math.floor(tonumber(rw:GetValue()) or 0))
                -- ID чистим так же, как сервер: иначе он молча изменится при сохранении.
                local raw = string.lower(string.Trim(aid:GetValue() or "")):gsub("[^%w_%-%:]", "_")
                d.id = raw ~= "" and raw or ("quest_" .. tostring(work.id or ""))
                rebuildCards()
            end
            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(46) note:DockMargin(10, 4, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Выдаётся сразу после награды квеста. Её деньги — отдельная сумма.\n\nID пишите латиницей: кириллица в нём заменяется подчёркиваниями.")

        elseif b.kind == "checkpoint" then
            --[[ ПАНЕЛЬ ЧЕКПОИНТА (заказ владельца 30.08).

                 Точку на карте ставят тулом: вписывать координаты руками
                 в поля — гарантированная ошибка. Кнопка ниже переключает
                 тул в нужный режим и подставляет ID точки, чтобы клик в
                 мире попал именно в этот блок. ]]
            local cpID = tostring(d.id or ""):gsub("^cp_", "")
            if cpID == "" then cpID = tostring(b.uid or "cp"):gsub("^cp_", "") d.id = cpID end

            local lb = field(right, "Подпись над маркером", d.label or "")
            lb.OnChange = function(e) d.label = e:GetValue() rebuildCards() end

            local rd = field(right, "Радиус срабатывания", tostring(d.radius or 96))
            rd.OnChange = function(e)
                d.radius = math.Clamp(math.floor(tonumber(e:GetValue()) or 96), 16, 2048)
            end

            local pos = istable(d.pos) and d.pos or nil
            local placed = pos and not (pos.x == 0 and pos.y == 0 and pos.z == 0)
            local posLbl = vgui.Create("DLabel", right)
            posLbl:Dock(TOP) posLbl:SetTall(20) posLbl:DockMargin(10, 8, 10, 0)
            posLbl:SetFont("GRMQS_Small")
            posLbl:SetTextColor(placed and COL.green or COL.red)
            posLbl:SetText(placed
                and ("Точка на карте: %d, %d, %d"):format(pos.x, pos.y, pos.z)
                or "Точка НЕ поставлена — маркера в мире не будет")

            local tool = mkBtn(right, "Поставить точку тулом в мире", Color(58, 82, 112))
            tool:Dock(TOP) tool:SetTall(30) tool:DockMargin(10, 6, 10, 4)
            tool.DoClick = function()
                RunConsoleCommand("grm_quest_tool_mode", "checkpoint")
                RunConsoleCommand("grm_quest_tool_quest_id", work.id or "")
                RunConsoleCommand("grm_quest_tool_checkpoint_id", cpID)
                RunConsoleCommand("gmod_tool", "grm_quest_tool")
                notification.AddLegacy("Тул квестов: ЛКМ по земле ставит чекпоинт", NOTIFY_HINT, 5)
            end

            local adv = vgui.Create("DCheckBoxLabel", right)
            adv:Dock(TOP) adv:SetTall(22) adv:DockMargin(10, 8, 10, 0)
            adv:SetText("Считать этап пройденным") adv:SetTextColor(COL.text)
            adv:SetValue(d.advanceStep == true)
            adv.OnChange = function(_, v) d.advanceStep = v end

            local once = vgui.Create("DCheckBoxLabel", right)
            once:Dock(TOP) once:SetTall(22) once:DockMargin(10, 4, 10, 0)
            once:SetText("Срабатывает один раз") once:SetTextColor(COL.text)
            once:SetValue(d.once ~= false)
            once.OnChange = function(_, v) d.once = v end

            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(92) note:DockMargin(10, 8, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Красный полупрозрачный круг, вращается на месте.\n\n" ..
                "Протяните линию от этого блока к НАГРАДЕ, АЧИВКЕ, КАТ-СЦЕНЕ или " ..
                "ЭТАПУ — сработает, когда игрок дойдёт до точки.\n\n" ..
                "«Считать этап пройденным» включайте, если точка и есть цель этапа.")

        elseif b.kind == "start" then
            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(80) note:DockMargin(10, 4, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Соедини СТАРТ с первой репликой фазы «до принятия». Именно её игрок услышит, подойдя к NPC.")

        elseif b.kind == "finish" then
            --[[ У ФИНИША не было панели вовсе — блок выглядел сломанным.
                 Настраивать в нём нечего, но объяснить, что происходит в
                 этот момент, обязательно: это и был вопрос владельца
                 «к чему сделано — до квеста / вовремя / после». ]]
            local note = vgui.Create("DLabel", right)
            note:Dock(TOP) note:SetTall(150) note:DockMargin(10, 4, 10, 6)
            note:SetWrap(true) note:SetFont("GRMQS_Small") note:SetTextColor(COL.dim)
            note:SetText("Конец квеста. Настраивать здесь нечего — блок отмечает, чем всё заканчивается.\n\nКогда игрок закрывает последний этап, по порядку происходит:\n1) награда из блока НАГРАДА;\n2) ачивка и её отдельная выплата;\n3) уведомление игроку;\n4) кат-сцена с фазой «при завершении».")
        end

        -- Удаление блока: у СТАРТ и ФИНИШ его нет, они каркас графа.
        if b.kind ~= "start" and b.kind ~= "finish" then
            local del = mkBtn(right, "Удалить блок", COL.red)
            del:Dock(TOP) del:SetTall(28) del:DockMargin(10, 14, 10, 8)
            del.DoClick = function()
                -- Чистим ссылки на удаляемый блок, иначе останутся висячие связи.
                for _, other in ipairs(blocks) do
                    for i = #(other.links or {}), 1, -1 do
                        if other.links[i].to == b.uid then table.remove(other.links, i) end
                    end
                end
                table.remove(blocks, selected)
                selected = 0
                rebuildCards() rebuildProps()
            end
        end
    end

    -----------------------------------------------------------------
    -- ЛЕВАЯ ПАНЕЛЬ: список квестов + палитра блоков
    -----------------------------------------------------------------
    local function loadWork(def)
        work = table.Copy(def)
        work.dialogue = work.dialogue or { offer = {}, active = {}, complete = {} }
        work.steps = work.steps or {}
        work.rewards = work.rewards or { money = 0, items = {} }
        work.cutscene = work.cutscene or { accept = {}, complete = {} }
        blocks = Q.QuestToBlocks(work)

        --[[ СПАСЕНИЕ УЕХАВШИХ БЛОКОВ.

             До появления границ карточку можно было утащить далеко за
             холст, и координата такой уехала в сохранённый квест. При
             открытии блок оказывался вне досягаемости: не видно, не
             схватить, связь не построить.

             Возвращаем всё в пределы холста при загрузке — иначе уже
             сломанные квесты остались бы сломанными навсегда. ]]
        for _, b in ipairs(blocks) do
            b.x = math.Clamp(tonumber(b.x) or 0, 0, CANVAS_W - CARD_W)
            b.y = math.Clamp(tonumber(b.y) or 0, 0, CANVAS_H - CARD_H)
        end

        selected = 0
        panX, panY = 0, 0
        applyPan()
        rebuildCards() rebuildProps() rebuildList()
    end

    rebuildList = function()
        left:Clear()

        local title = vgui.Create("DLabel", left)
        title:Dock(TOP) title:SetTall(22) title:DockMargin(10, 10, 10, 4)
        title:SetText("КВЕСТЫ") title:SetFont("GRMQS_Head") title:SetTextColor(COL.gold)

        for _, dd in ipairs(defs) do
            local b = vgui.Create("DButton", left)
            b:Dock(TOP) b:SetTall(40) b:DockMargin(8, 0, 8, 4) b:SetText("")
            b.Paint = function(s, w, h)
                draw.RoundedBox(6, 0, 0, w, h, (work and work.id == dd.id) and COL.nodeSel or COL.card)
                draw.SimpleText(dd.title or dd.id, "GRMQS_Body", 10, 6, COL.text)
                -- ID видно прямо в списке: не нужно открывать каждый квест.
                draw.SimpleText(tostring(dd.id or ""), "GRMQS_Small", 10, 22, COL.accent)
                --[[ Квест чужой карты помечаем в списке: иначе автор
                     откроет его и будет чинить несуществующие точки. ]]
                local alien = tostring(dd.map or "") ~= ""
                    and tostring(dd.map) ~= string.lower(game.GetMap() or "")
                -- Непроверенная копия видна в списке: её легко забыть.
                local unchecked = istable(dd.copyNotes) and #dd.copyNotes > 0
                draw.SimpleText((alien and "ДРУГАЯ КАРТА · " or "")
                    .. (unchecked and "НЕ ПРОВЕРЕН · " or "")
                    .. (dd.draft and "черновик · " or "") .. tostring(#(dd.steps or {})) .. " эт.",
                    "GRMQS_Small", w - 10, 22,
                    (alien or unchecked) and COL.red or COL.dim, TEXT_ALIGN_RIGHT)
            end
            b.DoClick = function() loadWork(dd) end
        end

        local nw = mkBtn(left, "Новый квест", COL.green)
        nw:Dock(TOP) nw:SetTall(28) nw:DockMargin(8, 8, 8, 4)
        nw.DoClick = function()
            local draft = {
                draft = true, id = "quest_" .. os.time(), title = "Новый квест", npc = "guide",
                -- Квест создаётся под ту карту, на которой его делают.
                map = string.lower(game.GetMap() or ""),
                summary = "", enabled = true, steps = {}, rewards = { money = 0, items = {} },
                dialogue = { offer = {}, active = {}, complete = {} },
                cutscene = { accept = {}, complete = {} },
            }
            defs[#defs + 1] = draft
            loadWork(draft)
        end

        --[[ КОПИЯ И ШАБЛОН (заказ владельца 29.08).

             Копия — точный дубль: этапы, диалоги, камеры, награда.
             Шаблон — та же структура, но без привязок к месту:
             координаты зон, камеры и NPC очищены. Иначе автор получил
             бы «почти готовый» квест, тихо ведущий игроков в старые
             точки — худший вид ошибки, потому что он не виден. ]]
        local function makeCopy(asTemplate)
            if not work then
                notification.AddLegacy("Сначала выберите квест", NOTIFY_HINT, 3) return
            end
            if not (Q.CopyQuest and Q.CopyWarnings) then
                notification.AddLegacy("Модуль квестов не загружен", NOTIFY_ERROR, 4) return
            end
            -- Собираем текущее состояние графа: копируем то, что на экране.
            local src = Q.BlocksToQuest(work, blocks)
            local base = tostring(src.id or "quest")
            --[[ Ищем свободный ID: «_copy» на уже существующем имени
                 затёр бы прошлую копию. ]]
            local taken = {}
            for _, d in ipairs(defs) do taken[tostring(d.id or "")] = true end
            local suffix = asTemplate and "_tpl" or "_copy"
            local newID, n = base .. suffix, 1
            while taken[newID] do n = n + 1 newID = base .. suffix .. n end

            local copy, warnings = Q.CopyQuest(src, newID, asTemplate)
            if not copy then return end
            defs[#defs + 1] = copy
            loadWork(copy)
            notification.AddLegacy(asTemplate and "Шаблон создан" or "Копия создана", NOTIFY_GENERIC, 4)
        end

        local cp = mkBtn(left, "Копировать квест", Color(58, 82, 112))
        cp:Dock(TOP) cp:SetTall(26) cp:DockMargin(8, 4, 8, 2)
        cp.DoClick = function() makeCopy(false) end

        local tpl = mkBtn(left, "Сделать шаблон", Color(58, 82, 112))
        tpl:Dock(TOP) tpl:SetTall(26) tpl:DockMargin(8, 0, 8, 4)
        tpl.DoClick = function()
            Derma_Query("Шаблон очистит координаты зон, камеры и привязку к NPC.\n" ..
                "Этапы, диалоги и награда сохранятся.\n\nСоздать шаблон?",
                "Шаблон квеста", "Создать", function() makeCopy(true) end, "Отмена")
        end

        --[[ ПАЛИТРА БЛОКОВ — то, что владелец назвал «боковыми
             вкладышами». Нажатие кладёт блок на холст. ]]
        local ph = vgui.Create("DLabel", left)
        ph:Dock(TOP) ph:SetTall(22) ph:DockMargin(10, 14, 10, 4)
        ph:SetText("БЛОКИ") ph:SetFont("GRMQS_Head") ph:SetTextColor(COL.gold)

        for _, bt in ipairs(Q.BlockTypes) do
            local b = vgui.Create("DButton", left)
            b:Dock(TOP) b:SetTall(34) b:DockMargin(8, 0, 8, 4) b:SetText("") b:SetCursor("hand")
            b.Paint = function(s, w, h)
                draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(40, 54, 74) or COL.card)
                draw.RoundedBox(0, 0, 0, 5, h, bt.color)
                draw.SimpleText(bt.name, "GRMQS_Body", 14, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("+", "GRMQS_Head", w - 14, h / 2, bt.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() addBlock(bt.id) end
        end

        -- Свойства самого квеста: имя, NPC, флаги.
        local qh = vgui.Create("DLabel", left)
        qh:Dock(TOP) qh:SetTall(22) qh:DockMargin(10, 14, 10, 2)
        qh:SetText("КВЕСТ") qh:SetFont("GRMQS_Head") qh:SetTextColor(COL.gold)

        if work then
            --[[ ID КВЕСТА редактируемый: на него ссылаются другие квесты
                 через «предыдущие квесты», поэтому иногда его нужно
                 переименовать. Чистим теми же правилами, что сервер, —
                 иначе значение молча изменится при сохранении. ]]
            --[[ КАРТА КВЕСТА (заказ владельца 29.08).

                 Зоны этапов и точки камер — координаты. Открыв квест
                 чужой карты, автор правил бы точки, которых здесь нет,
                 и не понимал, почему ничего не работает. Показываем
                 карту явно и предупреждаем красным. ]]
            --[[ ПЛАШКА ПРЕДУПРЕЖДЕНИЯ У КОПИИ (заказ владельца 29.08).

                 Висит, пока автор не подтвердит, что всё проверил.
                 Показываем КОНКРЕТНО, что перепроверить, а не общее
                 «параметры могут отличаться»: список строится по
                 фактическому содержимому квеста.

                 Красным — то, что почти наверняка сломано (координаты,
                 ID достижения). Жёлтым — то, что стоит глянуть. ]]
            if istable(work.copyNotes) and #work.copyNotes > 0 then
                local must = 0
                for _, n in ipairs(work.copyNotes) do
                    if n.level ~= "check" then must = must + 1 end
                end

                local warn = vgui.Create("DPanel", left)
                warn:Dock(TOP) warn:SetTall(30 + #work.copyNotes * 30)
                warn:DockMargin(10, 8, 10, 0)
                warn.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(48, 34, 14))
                    draw.RoundedBox(0, 0, 0, 4, h, must > 0 and COL.red or COL.gold)
                    draw.SimpleText(must > 0
                            and ("ПРОВЕРЬТЕ ПЕРЕД ЗАПУСКОМ · " .. must)
                            or "ПРОВЕРЬТЕ ПАРАМЕТРЫ",
                        "GRMQS_Body", 10, 14, must > 0 and COL.red or COL.gold)
                    local y = 34
                    for _, n in ipairs(work.copyNotes) do
                        local col = (n.level == "check") and COL.dim or Color(240, 190, 120)
                        -- Текст длинный: переносим, иначе он уедет за панель.
                        local lines = Q.WrapText(n.text, "GRMQS_Small", w - 24, 2)
                        for _, line in ipairs(lines) do
                            draw.SimpleText("• " .. line, "GRMQS_Small", 10, y, col)
                            y = y + 14
                        end
                        y = y + 2
                    end
                end

                local done = mkBtn(left, "Я всё проверил — убрать напоминание", COL.green)
                done:Dock(TOP) done:SetTall(26) done:DockMargin(10, 4, 10, 0)
                done.DoClick = function()
                    --[[ Снимаем только по явному действию: если гасить
                         автоматически при первом сохранении, напоминание
                         исчезнет раньше, чем автор что-то исправит. ]]
                    work.copyNotes = nil
                    rebuildList()
                    notification.AddLegacy("Напоминание снято", NOTIFY_GENERIC, 3)
                end
            end

            local questMap = tostring(work.map or "")
            local here = string.lower(game.GetMap() or "")
            local mapRow = vgui.Create("DPanel", left)
            mapRow:Dock(TOP) mapRow:SetTall(38) mapRow:DockMargin(10, 8, 10, 0)
            mapRow.Paint = function(_, w, h)
                local mismatch = questMap ~= "" and questMap ~= here
                draw.RoundedBox(5, 0, 0, w, h, mismatch and Color(52, 24, 28) or Color(20, 30, 44))
                draw.RoundedBox(0, 0, 0, 4, h, mismatch and COL.red or COL.accent)
                draw.SimpleText(questMap ~= "" and ("Карта: " .. questMap) or "Карта не задана",
                    "GRMQS_Small", 10, 12, mismatch and COL.red or COL.text)
                draw.SimpleText(mismatch and ("вы на " .. here .. " — точки не совпадут")
                        or (questMap == "" and "проставится при сохранении" or "совпадает с текущей"),
                    "GRMQS_Small", 10, 26, COL.dim)
            end

            local iE = field(left, "ID квеста (латиница)", work.id)
            iE.OnChange = function(s2)
                local raw = string.lower(string.Trim(s2:GetValue() or "")):gsub("[^%w_%-%:]", "_")
                work.id = raw
            end
            local tE = field(left, "Название", work.title)
            local nE = field(left, "ID NPC", work.npc)
            local sE = field(left, "Описание игроку", work.summary, true)
            tE.OnChange = function(s) work.title = s:GetValue() end
            nE.OnChange = function(s) work.npc = s:GetValue() end
            sE.OnChange = function(s) work.summary = s:GetValue() end
            for _, fl in ipairs({ { "enabled", "Включён" }, { "repeatable", "Повторяемый" },
                                  { "autoStart", "Автостарт новичку" } }) do
                local c = vgui.Create("DCheckBoxLabel", left)
                c:Dock(TOP) c:SetTall(20) c:DockMargin(10, 6, 10, 0)
                c:SetText(fl[2]) c:SetTextColor(COL.text) c:SetValue(work[fl[1]] == true)
                c.OnChange = function(_, v) work[fl[1]] = v end
            end
        end

        local sv = mkBtn(left, "Сохранить", COL.green)
        sv:Dock(TOP) sv:SetTall(32) sv:DockMargin(8, 14, 8, 4)
        sv.DoClick = function()
            if not work then return end
            local out = Q.BlocksToQuest(work, blocks)
            out.draft = #(out.steps or {}) == 0
            --[[ Проверяем ПЕРЕД отправкой: не даём молча сохранить квест,
                 который нельзя будет взять у NPC. ]]
            local issues = (Q.Validate and Q.Validate(out)) or {}
            local errs = {}
            for _, it in ipairs(issues) do
                if it.level == "error" then errs[#errs + 1] = it.text end
            end
            local function send()
                net.Start("GRM_Quest_AdminOp")
                net.WriteString("save")
                net.WriteTable(out)
                net.SendToServer()
                notification.AddLegacy("Квест сохранён", NOTIFY_GENERIC, 3)
            end
            if #errs > 0 then
                Derma_Query("Найдены ошибки:\n\n• " .. table.concat(errs, "\n• ") ..
                    "\n\nСохранить всё равно?", "Проверка квеста",
                    "Сохранить", send, "Исправить", function() end)
            else
                send()
            end
        end

        local chk = mkBtn(left, "Проверить", COL.gold)
        chk:Dock(TOP) chk:SetTall(26) chk:DockMargin(8, 0, 8, 4)
        chk.DoClick = function()
            if not work then return end
            local out = Q.BlocksToQuest(work, blocks)
            local issues = (Q.Validate and Q.Validate(out)) or {}
            if #issues == 0 then
                notification.AddLegacy("Ошибок не найдено", NOTIFY_GENERIC, 4)
                return
            end
            local lines = {}
            for _, it in ipairs(issues) do
                lines[#lines + 1] = (it.level == "error" and "[!] " or "[?] ") .. it.text
            end
            Derma_Message(table.concat(lines, "\n"), "Проверка квеста", "Понятно")
        end

        --[[ СБРОС ПРОХОЖДЕНИЯ (заказ владельца 31.08: «админу нужен
             сброс квеста, чтобы проверить его заново»).

             Кнопка рядом с «Проверить»: правишь квест и тут же проходишь
             заново, не уходя в консоль. Право проверяет сервер —
             клиентская кнопка ничего не решает. ]]
        local reset = mkBtn(left, "СБРОСИТЬ ПРОХОЖДЕНИЕ", Color(58, 82, 112))
        reset:Dock(TOP) reset:SetTall(26) reset:DockMargin(8, 0, 8, 6)
        reset.DoClick = function()
            if not work then return end
            Derma_Query("Сбросить ВАШЕ прохождение «" .. tostring(work.title) ..
                "»?\n\nКвест можно будет пройти заново: снимутся этапы, чекпоинты и ачивка.",
                "Студия", "Сбросить", function()
                    net.Start("GRM_Quest_AdminOp") net.WriteString("reset")
                    net.WriteString(work.id or "") net.SendToServer()
                end, "Отмена")
        end

        local del = mkBtn(left, "Удалить квест", COL.red)
        del:Dock(TOP) del:SetTall(26) del:DockMargin(8, 0, 8, 10)
        del.DoClick = function()
            if not work then return end
            Derma_Query("Удалить «" .. tostring(work.title) .. "»?", "Студия", "Удалить", function()
                net.Start("GRM_Quest_AdminOp") net.WriteString("delete")
                net.WriteString(work.id or "") net.SendToServer()
            end, "Отмена")
        end
    end

    rebuildList()
    if defs[1] then loadWork(defs[1]) else rebuildProps() end
end

-- Приём GRM_Quest_AdminOpen живёт в cl_grm_quests: он выбирает узловой
-- редактор (эта функция) и падает на старое окно, только если студия
-- не загрузилась. Второй ресивер здесь молча затирал бы тот выбор.

print("[GRM Quest Studio] v3 unified node editor")
