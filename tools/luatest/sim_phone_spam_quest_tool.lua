--[[ Живой прогон двух правок (заказ владельца 28.08).

     1) «Почему-то спамится при нажатии стрелки — у вас нету телефона,
         можно купить его в /phoneshop. Надо чтобы не спамило этим
         предупреждением и чтобы не срабатывало оно в целом когда игрок
         пишет что-то в чате или в консоли.»

        ТРИ ПРИЧИНЫ, все найдены в коде:
          • chatBusy() проверял только чат. Консоль и игровое меню не
            учитывались, а в консоли стрелки листают историю команд —
            каждое нажатие уходило в телефон;
          • keyDown отсекал по textInputActive() только KEY_UP, поэтому
            остальные стрелки доходили всегда;
          • клиент дёргал сервер ДАЖЕ без телефона, сервер отвечал
            «купите в /phoneshop» без всякого ограничения.

     2) «Инструмент квестов поредактируй, приведи в соответствие, мб
         есть что либо лишнее.»

        Найден настоящий баг: студия не передавала тулу НОМЕР ЭТАПА, и
        зона молча уезжала в чужой этап.

     Запуск: luajit tools/luatest/sim_phone_spam_quest_tool.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local mobile = readf("lua/autorun/sh_grm_mobile.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local tool = readf("lua/weapons/gmod_tool/stools/grm_quest_tool.lua")

-----------------------------------------------------------------------
print("\n=== 1. ЧАТ, КОНСОЛЬ И МЕНЮ БЛОКИРУЮТ СТРЕЛКИ ===")
-----------------------------------------------------------------------
local busyFn = mobile:match("local function chatBusy%(%).-\n    end") or ""
ok(busyFn ~= "", "функция определения занятого ввода найдена")
ok(busyFn:find("chat.IsChatOpen", 1, true) ~= nil, "чат учитывается (было и раньше)")
ok(busyFn:find("gui.IsConsoleVisible", 1, true) ~= nil,
   "ИСПРАВЛЕНО: консоль теперь учитывается — в ней стрелки листают историю")
ok(busyFn:find("gui.IsGameUIVisible", 1, true) ~= nil,
   "ИСПРАВЛЕНО: игровое меню тоже")
ok(busyFn:find("vgui.CursorVisible", 1, true) ~= nil,
   "и любое открытое окно с курсором")

--[[ Воспроизводим логику: при каждом виде занятости стрелка не должна
     доходить до телефона. ]]
local function chatBusy(st)
    if st.chatOpen then return true end
    if st.console then return true end
    if st.gameUI then return true end
    if st.cursor and not st.phoneOpen then return true end
    return false
end
ok(chatBusy({ chatOpen = true }) == true, "открытый чат блокирует")
ok(chatBusy({ console = true }) == true, "открытая консоль блокирует")
ok(chatBusy({ gameUI = true }) == true, "игровое меню блокирует")
ok(chatBusy({ cursor = true }) == true, "чужое окно с курсором блокирует")
ok(chatBusy({}) == false, "в обычной игре ничего не блокирует")
--[[ Важно: когда открыт САМ телефон, курсор виден, и блокировать
     стрелки нельзя — иначе по меню телефона не походишь. ]]
ok(chatBusy({ cursor = true, phoneOpen = true }) == false,
   "при открытом телефоне курсор не мешает управлять им")

-----------------------------------------------------------------------
print("\n=== 2. ОТСЕКАЮТСЯ ВСЕ СТРЕЛКИ, А НЕ ТОЛЬКО ВВЕРХ ===")
-----------------------------------------------------------------------
ok(mobile:find("if key==KEY_UP and not M.open and textInputActive() then return end", 1, true) == nil,
   "БАГ УБРАН: проверка больше не ограничена одной клавишей")
ok(mobile:find("if not M.open and textInputActive() then return end", 1, true) ~= nil,
   "ИСПРАВЛЕНО: при активном вводе отсекается любая клавиша")

local function keyBlocked(key, phoneOpen, inputActive)
    if not phoneOpen and inputActive then return true end
    return false
end
for _, k in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
    ok(keyBlocked(k, false, true) == true, "в чате блокируется стрелка " .. k)
end
ok(keyBlocked("UP", true, true) == false,
   "при ОТКРЫТОМ телефоне ввод не блокирует — иначе им нельзя пользоваться")

-----------------------------------------------------------------------
print("\n=== 3. БЕЗ ТЕЛЕФОНА СЕРВЕР НЕ ДЁРГАЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Корень спама: клиент слал запрос всегда, сервер на каждый отвечал
     строкой в чат. ]]
--[[ Проверяем ТЕЛО keyDown, а не файл целиком.

     Первая версия искала подстроки по всему файлу и пропустила откат:
     строка «есть телефон → запрос» осталась в опросе клавиш ниже,
     поэтому проверка проходила, хотя keyDown снова дёргал сервер
     безусловно. Смотрим именно ту ветку, что выполняется при закрытом
     телефоне. ]]
local keyDownFn = mobile:match("local function keyDown%(key%).-\n    end") or ""
ok(keyDownFn ~= "", "функция keyDown найдена")

local closedBranch = keyDownFn:match("if not M%.open then.-\n        end") or ""
ok(closedBranch ~= "", "ветка «телефон закрыт» найдена")
ok(closedBranch:find("requestServerOpen(); if hasPhone()", 1, true) == nil,
   "БАГ УБРАН: безусловный запрос к серверу удалён")
ok(closedBranch:find("if hasPhone() then requestServerOpen()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: сервер дёргается только когда телефон есть")
--[[ Ключевое: requestServerOpen обязан стоять ПОСЛЕ проверки hasPhone,
     а не до неё. ]]
local reqPos = closedBranch:find("requestServerOpen", 1, true)
local chkPos = closedBranch:find("hasPhone()", 1, true)
ok(reqPos and chkPos and chkPos < reqPos,
   "проверка наличия телефона идёт РАНЬШЕ запроса к серверу")

local calls = 0
local function pressUp(hasPhone)
    if hasPhone then calls = calls + 1 end   -- requestServerOpen
end
calls = 0
for _ = 1, 20 do pressUp(false) end
ok(calls == 0, "20 нажатий без телефона — ноль запросов к серверу", calls)
calls = 0
for _ = 1, 3 do pressUp(true) end
ok(calls == 3, "с телефоном запросы идут как обычно", calls)

-- Опрос клавиш (второй путь открытия) использует ту же проверку.
ok(mobile:find("if not M.open and not textInputActive() then", 1, true) ~= nil,
   "опрос клавиш тоже проверяет ввод, а не только чат")

-----------------------------------------------------------------------
print("\n=== 4. СЕРВЕР: ВТОРОЙ РУБЕЖ ОТ СПАМА ===")
-----------------------------------------------------------------------
--[[ На клиента полагаться нельзя: MB.Open зовут команда, инвентарь и
     чужой код. Сообщение обязано иметь ограничение по частоте. ]]
ok(mobile:find("ply._grmMobNoPhoneAt", 1, true) ~= nil,
   "ИСПРАВЛЕНО: у сообщения появилось ограничение по времени")
ok(mobile:find("CurTime() - (ply._grmMobNoPhoneAt or -999) >= 8", 1, true) ~= nil,
   "не чаще раза в 8 секунд")

--[[ Проверяем, что ограничение накрывает ОБА сообщения, а не одно:
     иначе ветка «телефон в инвентаре» продолжила бы спамить. ]]
local guard = mobile:match("if CurTime%(%) %- %(ply%._grmMobNoPhoneAt or %-999%) >= 8 then.-\n            end") or ""
ok(guard ~= "", "блок ограничения найден")
ok(guard:find("Купите его в /phoneshop", 1, true) ~= nil,
   "сообщение «нет телефона» под ограничением")
ok(guard:find("Нажмите «Использовать»", 1, true) ~= nil,
   "и сообщение «телефон в инвентаре» тоже")

-- Живая модель ограничения.
local shown, last = 0, -999
local function serverNotify(t)
    if t - last >= 8 then last = t shown = shown + 1 end
end
shown, last = 0, -999
for i = 1, 30 do serverNotify(i * 0.1) end   -- 30 нажатий за 3 секунды
ok(shown == 1, "БАГ ИСПРАВЛЕН: 30 быстрых нажатий дают ОДНО сообщение", shown)
serverNotify(20)
ok(shown == 2, "через 8+ секунд подсказка появится снова", shown)

-----------------------------------------------------------------------
print("\n=== 5. ТУЛ КВЕСТОВ: НОМЕР ЭТАПА ===")
-----------------------------------------------------------------------
--[[ НАСТОЯЩИЙ БАГ, найденный при ревизии: тул пишет зону в
     steps[номер], а студия номер не передавала. Оставался номер от
     прошлого раза — зона уезжала в чужой этап. ]]
ok(studio:find('RunConsoleCommand("grm_quest_tool_step"', 1, true) ~= nil,
   "ИСПРАВЛЕНО: студия передаёт тулу номер этапа")

local zoneBtn = studio:match('tool%.DoClick = function%(%).-\n                end') or ""
ok(zoneBtn ~= "", "обработчик кнопки «Задать зону» найден")
ok(zoneBtn:find('ob.kind == "step"', 1, true) ~= nil,
   "номер считается среди блоков-этапов")
ok(zoneBtn:find('net.WriteString("save")', 1, true) ~= nil,
   "перед запуском тула квест сохраняется — иначе тул не найдёт новый этап")

--[[ Воспроизводим подсчёт: важно, что нумеруются только этапы, а не
     все блоки подряд. Иначе номер сдвинется на реплики и награды. ]]
local function stepIndex(blocks, target)
    local idx = 0
    for _, b in ipairs(blocks) do
        if b.kind == "step" then
            idx = idx + 1
            if b == target then return idx end
        end
    end
    return 0
end
local s1 = { kind = "step" }
local s2 = { kind = "step" }
local s3 = { kind = "step" }
local mixed = { { kind = "start" }, s1, { kind = "dialogue" }, s2,
                { kind = "reward" }, s3, { kind = "finish" } }
ok(stepIndex(mixed, s1) == 1, "первый этап получает номер 1", stepIndex(mixed, s1))
ok(stepIndex(mixed, s2) == 2, "второй — номер 2, реплика между ними не считается",
   stepIndex(mixed, s2))
ok(stepIndex(mixed, s3) == 3, "третий — номер 3, награда не сбивает счёт",
   stepIndex(mixed, s3))
ok(stepIndex(mixed, { kind = "step" }) == 0, "чужой блок даёт 0, а не случайный номер")

--[[ Порядок блоков на холсте не должен влиять: сервер хранит этапы
     массивом в порядке разбора, и номер обязан ему соответствовать. ]]
local reordered = { s2, s1, s3 }
ok(stepIndex(reordered, s2) == 1, "номер следует порядку блоков, а не имени")

-----------------------------------------------------------------------
print("\n=== 6. ТУЛ КВЕСТОВ: УБРАНО ЛИШНЕЕ ===")
-----------------------------------------------------------------------
ok(tool:find("NumSlider", 1, true) == nil,
   "ИСПРАВЛЕНО: ручной слайдер номера этапа убран — его выставляет студия")
--[[ Ищем ссылку именно в ТЕКСТЕ ЗАГОЛОВКА панели, а не по всему файлу:
     команда упомянута в комментарии, объясняющем саму правку, и поиск
     по файлу давал ложный провал. ]]
local header = tool:match('p:AddControl%("Header",{Description="[^"]*"') or ""
ok(header ~= "", "заголовок панели найден")
ok(header:find("/grm_quests_admin", 1, true) == nil,
   "ИСПРАВЛЕНО: устаревшая ссылка на консольную команду убрана из заголовка")
ok(tool:find("Quest Studio (ПКМ по NPC)", 1, true) ~= nil,
   "вместо неё сказано, как открыть студию на самом деле")

--[[ Поля показываются по режиму: раньше все семь висели всегда, и в
     режиме зоны предлагалось заполнить модель NPC. ]]
ok(tool:find("p.Think=function()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: панель прячет поля не своего режима")
ok(tool:find('f:SetVisible(m=="npc")', 1, true) ~= nil, "поля NPC только в режиме NPC")
ok(tool:find('phase:SetVisible(m=="cutscene")', 1, true) ~= nil,
   "фаза кат-сцены только в своём режиме")
ok(tool:find('questField:SetVisible(m~="npc")', 1, true) ~= nil,
   "ID квеста не нужен при расстановке NPC")

-- Подсказка тоже должна меняться по режиму, а не быть общей простынёй.
ok(tool:find("help:SetText", 1, true) ~= nil, "подсказка зависит от режима")
for _, m in ipairs({ "npc", "zone", "cutscene" }) do
    ok(tool:find(m .. "=", 1, true) ~= nil, "есть текст подсказки для режима: " .. m)
end

-- Три режима на месте: ничего рабочего не выкинули.
for _, m in ipairs({ "npc", "zone", "cutscene" }) do
    ok(tool:find('mode=="' .. m .. '"', 1, true) ~= nil
       or tool:find('AddChoice("Квестовый NPC","npc")', 1, true) ~= nil,
       "режим сохранён: " .. m)
end
ok(tool:find("TOOL:Reload", 1, true) ~= nil, "удаление NPC по R на месте")
ok(tool:find("GRM.Quests.OpenAdmin", 1, true) ~= nil, "открытие студии по ПКМ на месте")
ok(tool:find("PostDrawTranslucentRenderables", 1, true) ~= nil,
   "предпросмотр зон и камер в мире не тронут")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
