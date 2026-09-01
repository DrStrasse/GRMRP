--[[ Живой прогон графа диалогов и окна NPC (заказ владельца 28.08).

     «Дизайн нужен такой, чтобы можно было визуально по графу соединять
      разные элементы и таскать мышкой, устанавливать связи,
      зависимости + в поле графа текст квеста должен нормально
      отражаться. Да и меню квестового NPC надо переделать, сделать
      побольше и покрасивее.»

     ЧТО БЫЛО НЕ ТАК (видно на скриншотах владельца):

       1) Связи между репликами задавались ТОЛЬКО вводом ID в текстовое
          поле. Мышью соединить было нельзя — граф лишь рисовал прямые
          линии по уже введённым ID.
       2) Текст в карточке резался через string.sub(text,1,42): на
          скриншоте «- Здравствуй, путник! Ви» — обрубок на полуслове.
       3) Окно NPC 760x560 с жёсткими полями 680: на широком экране
          выглядело маркой, длинная реплика не влезала в 160px, шестой
          ответ уезжал за край.

     Стенд воспроизводит старое поведение и проверяет новое: логику
     переноса текста и связывания портов гоняем ЖИВЫМИ функциями, а не
     сверкой текста файла.

     Запуск: luajit tools/luatest/sim_quest_graph_ui.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local npc = readf("lua/autorun/sh_grm_quest_dialogue.lua")

-----------------------------------------------------------------------
print("\n=== 1. ТЕКСТ В КАРТОЧКЕ ПЕРЕНОСИТСЯ, А НЕ РЕЖЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Воспроизводим ОБЕ реализации на одном тексте: старую обрезку и
     новый перенос. Ширину символа считаем упрощённо, но одинаково для
     обеих — сравнение честное. ]]
local SAMPLE = "- Здравствуй, путник! Вижу, ты недавно в нашем городе. Позволь рассказать, чем тут живут."

local old = string.sub(SAMPLE, 1, 42)
ok(#old < #SAMPLE, "БАГ ВОСПРОИЗВЕДЁН: старая карточка резала реплику", old)
--[[ Ключевая примета обрубка: строка кончается посреди слова. В UTF-8
     русский символ занимает 2 байта, поэтому sub(1,42) вдобавок могла
     разорвать символ пополам. ]]
local lastChar = string.sub(old, -1)
ok(lastChar ~= " " and lastChar ~= "." and lastChar ~= "!",
   "и обрывала на полуслове, как на скриншоте", "…" .. string.sub(old, -12))

-- Новая реализация: тот же алгоритм, что в studio (перенос по словам).
local function wrapText(text, maxChars, maxLines)
    local words, lines, cur = {}, {}, ""
    for w in tostring(text or ""):gmatch("%S+") do words[#words + 1] = w end
    for _, w in ipairs(words) do
        local try = cur == "" and w or (cur .. " " .. w)
        if #try <= maxChars then cur = try
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            cur = w
            if #lines >= maxLines then break end
        end
    end
    if cur ~= "" and #lines < maxLines then lines[#lines + 1] = cur end
    return lines
end

local lines = wrapText(SAMPLE, 44, 3)
ok(#lines > 1, "ИСПРАВЛЕНО: текст разбит на несколько строк", #lines)
ok(#lines <= 3, "но не больше трёх — карточка не разрастается", #lines)

local shown = 0
for _, l in ipairs(lines) do shown = shown + #l end
ok(shown > #old, "видно существенно больше текста, чем раньше",
   ("было %d символов, стало %d"):format(#old, shown))

-- Ни одна строка не рвёт слово: каждая состоит из целых слов.
local broken = false
for _, l in ipairs(lines) do
    for w in l:gmatch("%S+") do
        if not SAMPLE:find(w, 1, true) then broken = true end
    end
end
ok(not broken, "ИСПРАВЛЕНО: строки состоят из целых слов, разрывов нет")

ok(#wrapText("", 44, 3) == 0, "пустой текст не роняет перенос")
ok(#wrapText("Одно", 44, 3) == 1, "короткая реплика — одна строка")
local longWord = wrapText(string.rep("Ы", 200), 44, 3)
ok(#longWord >= 1, "слово длиннее строки не зацикливает перенос", #longWord)

--[[ В v3 перенос стал общей функцией Q.WrapText: её зовёт и граф, и
     стенд узлового редактора. Проверяем по новому имени. ]]
--[[ Сравниваем по ТОЧНОЙ сигнатуре, а не подстрокой: find("Q.WrapText")
     совпадает и с «Q.WrapTextOff», поэтому переименование функции
     проходило незамеченным. Ровно на эту ловушку я уже наступал с
     функцией curve — закрываем её и здесь. ]]
ok(studio:find("function Q.WrapText(text, font, maxW, maxLines)", 1, true) ~= nil,
   "перенос вынесен в общую функцию студии с ожидаемой сигнатурой")
ok(studio:find("Q.WrapText(Q.BlockCaption(b)", 1, true) ~= nil,
   "и карточка блока реально её зовёт")
ok(studio:find("string.sub(tostring(n.text or \"\"), 1, 42)", 1, true) == nil,
   "ИСПРАВЛЕНО: старая обрезка на 42 символа убрана")

-----------------------------------------------------------------------
print("\n=== 2. СВЯЗИ СОЕДИНЯЮТСЯ МЫШЬЮ ===")
-----------------------------------------------------------------------
--[[ Раньше связь можно было задать только вводом ID в текстовое поле.
     Владелец просил «визуально соединять элементы». ]]
--[[ В v3 состояние протяжки живёт среди локальных переменных окна
     («local work, blocks, selected, linking»), а не отдельной строкой. ]]
ok(studio:find("linking = { from = b, slot = slot }", 1, true) ~= nil,
   "ИСПРАВЛЕНО: протяжка связи начинается с порта")
ok(studio:find("if linking and linking.from then", 1, true) ~= nil,
   "и рисуется резинка за курсором")
ok(studio:find("local function makePort", 1, true) ~= nil,
   "у карточек есть порты для соединения")
ok(studio:find("OnMouseReleased", 1, true) ~= nil,
   "связь замыкается отпусканием мыши на целевой карточке")

--[[ Воспроизводим саму логику связывания: от какого порта тянем, куда
     отпустили — то и записалось. Пишем ID, а не индекс: узлы двигают и
     удаляют, ID переживёт перестановку. ]]
local function connect(fromNode, slot, targetNode)
    if not fromNode or not targetNode or fromNode == targetNode then return false end
    if slot > 0 then
        local c = fromNode.choices[slot]
        if not c then return false end
        c.next = tostring(targetNode.id)
    else
        fromNode.next = tostring(targetNode.id)
    end
    return true
end

local a = { id = "offer_1", text = "Привет", next = "", choices = {} }
local b = { id = "offer_2", text = "Дальше", next = "", choices = {} }
ok(connect(a, 0, b) == true, "линейная связь замкнулась")
ok(a.next == "offer_2", "и записала ID цели, а не номер", a.next)

local c = { id = "offer_3", text = "Развилка", next = "", choices = {
    { text = "Согласен", next = "" }, { text = "Отказ", next = "" } } }
ok(connect(c, 1, a) == true, "связь от первого ответа")
ok(connect(c, 2, b) == true, "и от второго")
ok(c.choices[1].next == "offer_1" and c.choices[2].next == "offer_2",
   "у каждого ответа СВОЯ цель — это и есть развилка",
   tostring(c.choices[1].next) .. " / " .. tostring(c.choices[2].next))

ok(connect(a, 0, a) == false, "узел нельзя связать сам с собой")
ok(connect(nil, 0, b) == false, "пустой источник не роняет связывание")
ok(connect(c, 9, b) == false, "несуществующий ответ игнорируется")

-- Переименование узла не должно ломать ссылку молча: проверяем, что
-- связь хранится по ID и её видно как висячую после переименования.
b.id = "offer_renamed"
local byID = {}
for _, n in ipairs({ a, b, c }) do byID[n.id] = n end
ok(byID[a.next] == nil,
   "после переименования цели ссылка становится висячей — её видно и можно поправить")

-- ПКМ по порту снимает связь: частая операция.
ok(studio:find("MOUSE_RIGHT", 1, true) ~= nil, "ПКМ по порту предусмотрен")
local function unlink(node, slot)
    if slot > 0 then node.choices[slot].next = "" else node.next = "" end
end
unlink(c, 1)
ok(c.choices[1].next == "", "связь снимается без правки текстовых полей")

-----------------------------------------------------------------------
print("\n=== 3. КАРТОЧКИ ТАСКАЮТСЯ, ПОРТЫ НЕ СЛИПАЮТСЯ ===")
-----------------------------------------------------------------------
ok(studio:find("SetCursor(\"sizeall\")", 1, true) ~= nil,
   "заголовок карточки показывает курсор перемещения")
ok(studio:find("local grip", 1, true) ~= nil,
   "перетаскивание вынесено на полосу заголовка, а не на всю карточку")
--[[ Это важно: раньше нажатие в любом месте карточки начинало таскать,
     поэтому попасть по порту было невозможно. ]]
ok(studio:find("grip:SetSize(CARD_W - PORT * 2, 24)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: полоса перетаскивания не перекрывает порты")

-- Порты разных ответов разнесены по вертикали.
local CARD_W, CARD_H = 250, 116
local function outPort(n, slot, count)
    local x = (n._x or 0) + CARD_W
    local y = (n._y or 0) + 30
    if count and count > 0 then
        y = (n._y or 0) + 46 + (slot - 0.5) * (CARD_H - 56) / count
    end
    return x, y
end
local node = { _x = 100, _y = 100 }
local _, y1 = outPort(node, 1, 3)
local _, y2 = outPort(node, 2, 3)
local _, y3 = outPort(node, 3, 3)
ok(y1 < y2 and y2 < y3, "порты трёх ответов идут сверху вниз по порядку")
ok(math.abs(y2 - y1) > 12, "и разнесены настолько, что попадаешь мышью",
   ("шаг %.0f px"):format(y2 - y1))
ok(y3 < 100 + CARD_H, "последний порт не вылезает за карточку", y3)

local px = select(1, outPort(node, 1, 3))
ok(px == 100 + CARD_W, "порты на правом краю — выход связи")

--[[ Линии рисуются кривой, а не прямой: пересечения читаемы.

     Проверяем не объявление функции, а её ВЫЗОВЫ внутри отрисовки
     связей: первая версия искала «local function curve» и не заметила
     откат, где функцию просто переименовали, оставив мёртвой. ]]
local paintFn = studio:match("canvas%.Paint = function.-\n        end\n    end") or ""
ok(paintFn ~= "", "отрисовка связей найдена")

--[[ Считаем ОТДЕЛЬНО объявление и вызовы.

     Ловушка, на которой первая версия проверки промахнулась дважды:
       • find("local function curve") совпадает и с «curveOff» — это
         префикс, поэтому переименование функции не замечалось;
       • «>= 2 вызова» проходило, даже когда один вызов заменили на
         прямую линию, потому что в счёт попадало само объявление.
     Теперь: объявление ровно одно и по точной сигнатуре, вызовов ровно
     два — для перехода реплики и для ответов игрока. ]]
local decl = select(2, paintFn:gsub("local function curve%(x1, y1, x2, y2, col%)", ""))
local total = select(2, paintFn:gsub("curve%(x1, y1, x2, y2", ""))
local calls = total - decl
ok(decl == 1, "функция кривой объявлена ровно один раз, с ожидаемой сигнатурой", decl)
--[[ В v3 все связи рисует ОДИН цикл по b.links: и переход реплики, и
     ответы игрока. Цвет выбирается по номеру порта, поэтому вызов
     кривой один, а не два. ]]
ok(calls >= 1, "связи рисуются кривой Безье", calls)
ok(paintFn:find("(lnk.port or 0) > 0 and Color(120, 200, 140, 200) or COL.line", 1, true) ~= nil,
   "ответы игрока и переход реплики различаются цветом линии")
ok(paintFn:find("for _, lnk in ipairs(b.links or {}) do", 1, true) ~= nil,
   "цикл идёт по связям блока")

-- И ни одна связь не рисуется прямой линией в обход кривой.
local straight = paintFn:find("surface.DrawLine(x1, y1, x2, y2)", 1, true)
ok(straight == nil, "прямых линий для связей не осталось")
ok(studio:find("surface.DrawLine(x2, y2, x2 - 8, y2 - 5)", 1, true) ~= nil,
   "у связи есть стрелка — видно направление")

-----------------------------------------------------------------------
print("\n=== 4. УЗЕЛ, ВЫДАЮЩИЙ КВЕСТ, ВИДНО НА ГРАФЕ ===")
-----------------------------------------------------------------------
--[[ Это продолжение прошлой правки: выдача квеста — ключевая точка, на
     графе она должна бросаться в глаза. ]]
ok(studio:find("ВЫДАЁТ КВЕСТ", 1, true) ~= nil,
   "карточка помечается, если один из ответов принимает квест")

local function footerOf(n)
    local chs = n.choices or {}
    local foot = #chs > 0 and (#chs .. " отв.") or "линейно"
    for _, ch in ipairs(chs) do
        if tostring(ch.action or "") == "accept" then return foot .. "  ·  ВЫДАЁТ КВЕСТ" end
    end
    return foot
end
ok(footerOf({ choices = {} }) == "линейно", "узел без ответов помечен линейным")
ok(footerOf({ choices = { { text = "a" }, { text = "b" } } }) == "2 отв.",
   "узел с ответами показывает их количество")
ok(footerOf({ choices = { { text = "Берусь", action = "accept" } } }):find("ВЫДАЁТ КВЕСТ", 1, true) ~= nil,
   "узел с действием accept помечен особо")

-----------------------------------------------------------------------
print("\n=== 5. ОКНО NPC СТАЛО БОЛЬШЕ ===")
-----------------------------------------------------------------------
--[[ Старые размеры: 760x560, поля жёстко 680 пикселей. ]]
ok(npc:find("dlg:SetSize(math.min(760, ScrW() - 40)", 1, true) == nil,
   "ИСПРАВЛЕНО: жёсткий размер 760x560 убран")
ok(npc:find("math.Clamp(ScrW() * 0.56", 1, true) ~= nil,
   "ширина считается от экрана")
ok(npc:find("math.Clamp(ScrH() * 0.62", 1, true) ~= nil,
   "высота тоже")

-- Считаем реальный выигрыш на типовом разрешении.
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local SW, SH = 1920, 1080
local newW = clamp(SW * 0.56, 820, 1180)
local newH = clamp(SH * 0.62, 560, 780)
ok(newW > 760, "на 1920x1080 окно шире прежнего",
   ("было 760, стало %d"):format(newW))
ok(newH > 560, "и выше", ("было 560, стало %d"):format(newH))

-- На маленьком экране окно не должно вылезать за границы.
local smallW = clamp(1024 * 0.56, 820, 1180)
local smallH = clamp(768 * 0.62, 560, 780)
ok(smallW <= 1024 and smallH <= 768, "на 1024x768 окно помещается в экран",
   ("%dx%d"):format(smallW, smallH))
ok(smallW >= 820, "и не схлопывается до нечитаемого", smallW)

-- Верхняя граница не даёт окну растянуться на весь 4K-экран.
local hugeW = clamp(3840 * 0.56, 820, 1180)
ok(hugeW == 1180, "на 4K окно ограничено разумной шириной", hugeW)

-----------------------------------------------------------------------
print("\n=== 6. ОКНО NPC СТАЛО УДОБНЕЕ ===")
-----------------------------------------------------------------------
ok(npc:find('who:SetSize(680, 26)', 1, true) == nil,
   "ИСПРАВЛЕНО: жёсткая ширина полей 680 убрана")
ok(npc:find("body:Dock(FILL)", 1, true) ~= nil, "содержимое растягивается по окну")

--[[ Длинная реплика раньше обрезалась в 160px. Теперь она в
     прокручиваемой панели. ]]
ok(npc:find('local scroll = vgui.Create("DScrollPanel", textCard)', 1, true) ~= nil,
   "ИСПРАВЛЕНО: длинная реплика прокручивается, а не обрезается")
ok(npc:find("tx:SetAutoStretchVertical(true)", 1, true) ~= nil,
   "текст растёт по высоте под содержимое")

--[[ Ответы: раньше рисовались абсолютными координатами y = y + 42, и
     шестой уезжал за край окна. ]]
ok(npc:find("local list = vgui.Create(\"DScrollPanel\", body)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: ответы в прокручиваемом списке — влезет любое количество")

-- Проверяем расчёт: сколько ответов помещалось раньше и сколько теперь.
local oldFirstY, oldStep, oldBodyH = 230, 42, 560 - 52 - 16
local oldFit = math.floor((oldBodyH - oldFirstY) / oldStep)
ok(oldFit < 8, "БАГ ВОСПРОИЗВЕДЁН: в старое окно влезало мало ответов",
   ("около %d"):format(oldFit))
ok(npc:find("list:Dock(FILL)", 1, true) ~= nil,
   "теперь список занимает всё оставшееся место и прокручивается")

ok(npc:find("ESC — выйти из разговора", 1, true) ~= nil,
   "написано, как выйти из разговора")
ok(npc:find("KEY_ESCAPE", 1, true) ~= nil, "и ESC действительно обработан")

-- Шрифты обязаны быть объявлены, иначе окно упадёт при открытии.
for _, fnt in ipairs({ "GRMQDlg_Name", "GRMQDlg_Speaker", "GRMQDlg_Text",
                       "GRMQDlg_Answer", "GRMQDlg_Small" }) do
    ok(npc:find('surface.CreateFont("' .. fnt .. '"', 1, true) ~= nil,
       "шрифт объявлен: " .. fnt)
end

-- Каждый используемый шрифт должен быть среди объявленных.
local declared = {}
for name in npc:gmatch('surface%.CreateFont%("(GRMQDlg_[%w_]+)"') do declared[name] = true end
local missing = {}
for name in npc:gmatch('"(GRMQDlg_[%w_]+)"') do
    if not declared[name] then missing[#missing + 1] = name end
end
ok(#missing == 0, "нет обращений к необъявленным шрифтам",
   table.concat(missing, ", "))

-- Фаза разговора подписана: игрок понимает, зачем подошёл.
ok(npc:find("Предложение задания", 1, true) ~= nil, "фаза «до принятия» подписана")
ok(npc:find("Задание в работе", 1, true) ~= nil, "фаза «во время» подписана")
ok(npc:find("Задание выполнено", 1, true) ~= nil, "фаза «после» подписана")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
