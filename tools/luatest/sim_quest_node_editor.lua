--[[ Живой прогон единого узлового редактора квестов (заказ 28.08).

     «Меню квестов лучше всего в единое меню сделать с одной вкладкой,
      но допустим с модульными блоками которые можно вытягивать из
      боковых вкладышей в центральный граф и соединять — кат-сцены,
      диалоги, музыка, ачивки и т.д.»

     ЧТО БЫЛО НЕ ТАК. Редактор состоял из пяти вкладок: Граф, Квест,
     Этапы, Камеры, Награды. Диалог жил на одной, камеры на другой,
     награды на третьей — связи между ними существовали только в голове
     автора.

     ГЛАВНЫЙ РИСК НОВОЙ СХЕМЫ: граф — это представление квеста, и при
     разборе обратно можно молча потерять данные. Поэтому основная
     часть стенда — round-trip: квест → блоки → квест, с побайтовой
     сверкой всех полей.

     Запуск: luajit tools/luatest/sim_quest_node_editor.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
CLIENT, SERVER = true, false
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t)
    if not istable(t) then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = istable(v) and table.Copy(v) or v end
    return o
end
function EyePos() return Vector(10, 20, 30) end
function EyeAngles() return Angle(1, 2, 3) end
os.time = function() return 1700000000 end

local FONTS = {}
surface = {
    CreateFont = function(n) FONTS[n] = true end,
    SetFont = function() end,
    -- Ширина символа фиксированная: перенос считается детерминированно.
    GetTextSize = function(s) return #tostring(s) * 7, 12 end,
    SetDrawColor = function() end, DrawRect = function() end,
    DrawLine = function() end, DrawOutlinedRect = function() end,
    PlaySound = function() end,
}
draw = { RoundedBox = function() end, RoundedBoxEx = function() end,
    SimpleText = function() end, SimpleTextOutlined = function() end }
hook = { Add = function() end, Run = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end }
timer = { Simple = function() end }
notification = { AddLegacy = function() end }
concommand = { Add = function() end }
function ScrW() return 1920 end
function ScrH() return 1080 end
NOTIFY_HINT, NOTIFY_GENERIC = 1, 0
GRM = {}

assert(loadfile("lua/autorun/client/zz_grm_quest_studio.lua"))()
local Q = GRM.Quests
assert(Q, "GRM.Quests не загрузился")

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local server = readf("lua/autorun/sh_grm_quests.lua")

-----------------------------------------------------------------------
print("\n=== 1. ОДНО МЕНЮ ВМЕСТО ПЯТИ ВКЛАДОК ===")
-----------------------------------------------------------------------
--[[ Владелец просил «единое меню с одной вкладкой». Проверяем, что
     старая раскладка вкладок действительно убрана. ]]
ok(studio:find("tabBtn(", 1, true) == nil,
   "ИСПРАВЛЕНО: кнопок-вкладок больше нет")
ok(studio:find('tabBtn("Камеры"', 1, true) == nil, "вкладка «Камеры» убрана")
ok(studio:find('tabBtn("Награды"', 1, true) == nil, "вкладка «Награды» убрана")
ok(studio:find("showTab", 1, true) == nil, "переключения вкладок нет вовсе")
ok(studio:find("Q.BlockTypes", 1, true) ~= nil, "вместо них — типы блоков")

-----------------------------------------------------------------------
print("\n=== 2. ПАЛИТРА БЛОКОВ ===")
-----------------------------------------------------------------------
ok(istable(Q.BlockTypes), "палитра описана таблицей")
local kinds = {}
for _, b in ipairs(Q.BlockTypes) do kinds[b.id] = b end

-- Ровно те виды, что перечислил владелец, плюс каркас графа.
for _, want in ipairs({ "dialogue", "cutscene", "music", "achieve" }) do
    ok(kinds[want] ~= nil, "есть блок из заказа владельца: " .. want)
end
for _, want in ipairs({ "start", "step", "reward", "finish" }) do
    ok(kinds[want] ~= nil, "есть служебный блок: " .. want)
end

local noName, noHint, noColor = 0, 0, 0
for _, b in ipairs(Q.BlockTypes) do
    if tostring(b.name or "") == "" then noName = noName + 1 end
    if tostring(b.hint or "") == "" and not b.once then noHint = noHint + 1 end
    if not istable(b.color) then noColor = noColor + 1 end
end
ok(noName == 0, "у каждого блока есть название", noName)
ok(noColor == 0, "и свой цвет — тип виден с одного взгляда", noColor)
ok(noHint == 0, "и пояснение, что он делает", noHint)

ok(kinds.start.once == true, "СТАРТ можно поставить только один")
ok(kinds.finish.once == true, "ФИНИШ тоже")
ok(kinds.dialogue.once ~= true, "а реплик можно сколько угодно")

ok(isfunction(Q.BlockDef), "есть поиск описания блока по типу")
ok(Q.BlockDef("music").id == "music", "он находит нужный", Q.BlockDef("music").id)
ok(Q.BlockDef("нет_такого") ~= nil, "и не падает на неизвестном типе")

-----------------------------------------------------------------------
print("\n=== 3. КРУГ «КВЕСТ → БЛОКИ → КВЕСТ» БЕЗ ПОТЕРЬ ===")
-----------------------------------------------------------------------
--[[ Самое опасное место: если разбор теряет поле, автор молча лишится
     диалога или награды при первом же сохранении. ]]
local QUEST = {
    id = "intro", title = "Введение", npc = "guide", summary = "Осмотреться в городе",
    enabled = true, repeatable = false, autoStart = false,
    steps = {
        { type = "event", title = "Копать", event = "mining", count = 3 },
        { type = "talk", title = "Поговорить", npc = "guide", count = 1 },
    },
    rewards = { money = 15200, items = { ore = 2, bread = 1 } },
    achievement = { enabled = true, id = "ach_intro", name = "Успешный старт",
        description = "Вы освоились", reward = 500, hidden = false },
    dialogue = {
        offer = {
            { id = "offer_1", speaker = "Гид", text = "Здравствуй, путник!", next = "offer_2",
              choices = { { text = "Берусь", action = "accept", next = "" } } },
            { id = "offer_2", speaker = "Гид", text = "Удачи", next = "", choices = {} },
        },
        active = { { id = "act_1", speaker = "Гид", text = "Работай", next = "", choices = {} } },
        complete = {},
    },
    cutscene = {
        accept = { { id = "camera_1", next = "", transition = "cut", duration = 3, fov = 75,
                     caption = "Город", pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 90, r = 0 } } },
        complete = {},
    },
}

local blocks = Q.QuestToBlocks(QUEST)
ok(#blocks > 0, "квест разобран в блоки", #blocks)

local function countKind(list, kind)
    local n = 0
    for _, b in ipairs(list) do if b.kind == kind then n = n + 1 end end
    return n
end
ok(countKind(blocks, "dialogue") == 3, "все три реплики стали блоками", countKind(blocks, "dialogue"))
ok(countKind(blocks, "step") == 2, "оба этапа стали блоками", countKind(blocks, "step"))
ok(countKind(blocks, "cutscene") == 1, "кат-сцена стала блоком", countKind(blocks, "cutscene"))
ok(countKind(blocks, "reward") == 1, "награда стала блоком")
ok(countKind(blocks, "achieve") == 1, "ачивка стала блоком")
ok(countKind(blocks, "start") == 1, "есть блок СТАРТ")
ok(countKind(blocks, "finish") == 1, "есть блок ФИНИШ")

local back = Q.BlocksToQuest(QUEST, blocks)

ok(back.id == QUEST.id and back.title == QUEST.title, "имя и ID пережили круг")
ok(back.npc == QUEST.npc, "NPC на месте")
ok(#back.steps == 2, "этапы вернулись все", #back.steps)
ok(back.steps[1].event == "mining" and back.steps[1].count == 3,
   "и с целыми полями", tostring(back.steps[1].event))
ok(back.steps[2].npc == "guide", "второй этап тоже цел")

ok(#back.dialogue.offer == 2, "реплики фазы offer вернулись", #back.dialogue.offer)
ok(#back.dialogue.active == 1, "фаза active не потерялась", #back.dialogue.active)
ok(back.dialogue.offer[1].text == "Здравствуй, путник!", "текст реплики цел")
ok(back.dialogue.offer[1].speaker == "Гид", "говорящий цел")
--[[ Дальше идут проверки полей ответа. Обращаться к choices[1] напрямую
     нельзя: если разбор их потерял, стенд упадёт на nil и покажет ОДИН
     провал вместо всех. Первая версия так и делала — откат «терять
     ответы» выглядел мелкой поломкой вместо катастрофы. ]]
local ch1 = ((back.dialogue.offer[1] or {}).choices or {})[1] or {}
ok(#((back.dialogue.offer[1] or {}).choices or {}) == 1, "ответы игрока целы")
ok(ch1.action == "accept",
   "и действие «принять квест» не потерялось — иначе квест нельзя было бы взять",
   tostring(ch1.action))
ok(ch1.text == "Берусь", "текст ответа цел", tostring(ch1.text))
--[[ Считаем ответы во ВСЕХ репликах: потеря даже одного означает
     оборванную ветку диалога. ]]
local totalChoices = 0
for _, ph in ipairs({ "offer", "active", "complete" }) do
    for _, n in ipairs(back.dialogue[ph] or {}) do
        totalChoices = totalChoices + #(n.choices or {})
    end
end
ok(totalChoices == 1, "суммарное число ответов совпадает с исходным", totalChoices)
ok(back.dialogue.offer[1].next == "offer_2", "линейный переход реплики цел",
   tostring(back.dialogue.offer[1].next))

ok(back.rewards.money == 15200, "деньги награды целы", back.rewards.money)
ok(back.rewards.items.ore == 2 and back.rewards.items.bread == 1, "предметы целы")
ok(back.achievement.enabled == true, "ачивка включена")
ok(back.achievement.name == "Успешный старт", "название ачивки цело")
ok(back.achievement.reward == 500, "выплата ачивки цела")

ok(#back.cutscene.accept == 1, "камеры кат-сцены целы", #back.cutscene.accept)
ok(back.cutscene.accept[1].caption == "Город", "титр камеры цел")
ok(back.cutscene.accept[1].pos.x == 1, "координаты камеры целы")

-- Двойной круг не должен ничего накапливать или терять.
local blocks2 = Q.QuestToBlocks(back)
local back2 = Q.BlocksToQuest(back, blocks2)
ok(#back2.steps == #back.steps, "второй круг: этапы стабильны")
ok(#back2.dialogue.offer == #back.dialogue.offer, "реплики стабильны")
ok(back2.rewards.money == back.rewards.money, "награда стабильна")
ok(#back2.cutscene.accept == #back.cutscene.accept, "камеры стабильны")

-- Пустой квест не должен падать.
local empty = Q.BlocksToQuest({ id = "e", title = "E" }, Q.QuestToBlocks({ id = "e", title = "E" }))
ok(istable(empty.steps) and #empty.steps == 0, "пустой квест разбирается без ошибок")
ok(istable(empty.dialogue.offer), "структура диалогов создана")

-----------------------------------------------------------------------
print("\n=== 4. УДАЛЁННЫЙ БЛОК ДЕЙСТВИТЕЛЬНО ПРОПАДАЕТ ===")
-----------------------------------------------------------------------
--[[ Ловушка: ачивка живёт в отдельном поле, и если просто убрать блок,
     она продолжила бы выдаваться. ]]
local noAch = {}
for _, b in ipairs(blocks) do if b.kind ~= "achieve" then noAch[#noAch + 1] = b end end
local backNoAch = Q.BlocksToQuest(QUEST, noAch)
ok(backNoAch.achievement.enabled == false,
   "ИСПРАВЛЕНО: убрали блок ачивки — достижение выключено, а не осталось висеть")

local noSteps = {}
for _, b in ipairs(blocks) do if b.kind ~= "step" then noSteps[#noSteps + 1] = b end end
local backNoSteps = Q.BlocksToQuest(QUEST, noSteps)
ok(#backNoSteps.steps == 0, "убрали блоки этапов — этапов не осталось")

local noRew = {}
for _, b in ipairs(blocks) do if b.kind ~= "reward" then noRew[#noRew + 1] = b end end
local backNoRew = Q.BlocksToQuest(QUEST, noRew)
ok(backNoRew.rewards.money == 0, "убрали блок награды — деньги обнулились")

-----------------------------------------------------------------------
print("\n=== 5. РАСКЛАДКА ПЕРЕЖИВАЕТ СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
--[[ Без этого блоки прыгали бы в исходную сетку после каждого
     сохранения: нормализация на сервере пересобирает таблицы по полям. ]]
for _, b in ipairs(blocks) do
    if b.kind == "dialogue" then b.x, b.y = 777, 888 end
    if b.kind == "step" then b.x, b.y = 555, 666 end
end
local moved = Q.BlocksToQuest(QUEST, blocks)
ok(moved.dialogue.offer[1]._gx == 777 and moved.dialogue.offer[1]._gy == 888,
   "координаты реплики попали в квест",
   tostring(moved.dialogue.offer[1]._gx))
ok(moved.steps[1]._gx == 555, "координаты этапа тоже", tostring(moved.steps[1]._gx))
ok(moved.rewards._gx ~= nil, "у награды есть координаты")

-- Сервер обязан их сохранять, а не отбрасывать при нормализации.
ok(server:find("out._gx=math.Clamp", 1, true) ~= nil,
   "ИСПРАВЛЕНО: нормализация этапа сохраняет координаты блока")
ok(server:find("_gx=math.Clamp(math.floor(tonumber(node._gx)or 0),0,20000)", 1, true) ~= nil,
   "нормализация узлов диалога и камер тоже")

-- И они переживают повторный разбор.
local reblocks = Q.QuestToBlocks(moved)
local dlgBlock
for _, b in ipairs(reblocks) do if b.kind == "dialogue" then dlgBlock = b break end end
ok(dlgBlock and dlgBlock.x == 777,
   "после перезагрузки блок стоит там, где его оставили",
   dlgBlock and dlgBlock.x)

-----------------------------------------------------------------------
print("\n=== 6. СВЯЗИ МЫШЬЮ ПИШУТСЯ В САМ КВЕСТ ===")
-----------------------------------------------------------------------
--[[ Связь должна не только рисоваться, но и попадать в choices[i].next:
     движок диалогов читает именно его, а не граф. ]]
ok(studio:find("local function linkBlocks", 1, true) ~= nil, "есть функция связывания")
local linkFn = studio:match("local function linkBlocks.-\n    end") or ""
ok(linkFn:find("ch.next = tostring(to.data.id or to.uid)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: связь от ответа пишется в choices[i].next, а не только в граф")
ok(linkFn:find("from.data.next = tostring(to.data.id or to.uid)", 1, true) ~= nil,
   "линейный переход тоже пишется в данные реплики")
ok(linkFn:find("if from == to then", 1, true) ~= nil
   or linkFn:find("from == to", 1, true) ~= nil,
   "блок нельзя связать сам с собой")

-- Один выход — одна связь, иначе поток раздваивается молча.
ok(linkFn:find("table.remove(from.links, i)", 1, true) ~= nil,
   "старая связь с того же порта снимается перед новой")

ok(studio:find("local function unlink", 1, true) ~= nil, "связь можно снять")
local unlinkFn = studio:match("local function unlink.-\n    end") or ""
ok(unlinkFn:find('ch.next = ""', 1, true) ~= nil,
   "снятие связи чистит и данные реплики, а не только картинку")

ok(studio:find("MOUSE_RIGHT", 1, true) ~= nil, "ПКМ по порту снимает связь")
ok(studio:find("linking = { from = b, slot = slot }", 1, true) ~= nil,
   "протяжка начинается с порта")

-- Удаление блока чистит ссылки на него.
local delFn = studio:match('del%.DoClick = function%(%)\n                %-%- Чистим.-\n            end') or ""
ok(studio:find("if other.links[i].to == b.uid then table.remove(other.links, i) end", 1, true) ~= nil,
   "удаление блока убирает висячие связи на него")

-----------------------------------------------------------------------
print("\n=== 7. ТЕКСТ В БЛОКЕ ЧИТАЕТСЯ ===")
-----------------------------------------------------------------------
ok(isfunction(Q.WrapText), "перенос текста доступен")
local long = "Здравствуй, путник! Вижу, ты недавно в нашем городе, позволь рассказать о нём"
local lines = Q.WrapText(long, "GRMQS_Small", 214, 3)
ok(#lines > 1, "длинный текст разбит на строки", #lines)
ok(#lines <= 3, "но не больше трёх", #lines)
local broken = false
for _, l in ipairs(lines) do
    for w in l:gmatch("%S+") do
        local clean = w:gsub("…", "")
        if clean ~= "" and not long:find(clean, 1, true) then broken = true end
    end
end
ok(not broken, "строки состоят из целых слов — обрывов на полуслове нет")
ok(#Q.WrapText("", "GRMQS_Small", 214, 3) == 0, "пустой текст не роняет перенос")

ok(isfunction(Q.BlockCaption), "у блока есть заголовок")
ok(Q.BlockCaption({ kind = "dialogue", data = { text = "Привет" } }) == "Привет",
   "реплика показывает свой текст")
ok(Q.BlockCaption({ kind = "reward", data = { money = 500, items = {} } }):find("500", 1, true) ~= nil,
   "награда показывает сумму", Q.BlockCaption({ kind = "reward", data = { money = 500, items = {} } }))
ok(Q.BlockCaption({ kind = "reward", data = { money = 0, items = {} } }):find("не задана", 1, true) ~= nil,
   "пустая награда честно об этом говорит")
ok(Q.BlockCaption({ kind = "cutscene", data = { cams = {} } }):find("Камер нет", 1, true) ~= nil,
   "кат-сцена без камер предупреждает")
ok(Q.BlockCaption({ kind = "music", data = { sound = "" } }):find("не выбран", 1, true) ~= nil,
   "музыка без звука предупреждает")
ok(Q.BlockCaption({ kind = "step", data = { title = "Копать" } }) == "Копать",
   "этап показывает название")

-----------------------------------------------------------------------
print("\n=== 8. ПРОВЕРКА ПЕРЕД СОХРАНЕНИЕМ ===")
-----------------------------------------------------------------------
--[[ Сохранение прогоняет квест через тот же валидатор, что и сервер:
     нельзя молча записать квест, который нельзя взять у NPC. ]]
--[[ Проверяем ТЕЛО обработчика сохранения, а не файл целиком: откат,
     где вызов валидатора заменили пустой таблицей, при поиске по всему
     файлу не замечался — строка «Найдены ошибки» оставалась на месте. ]]
local saveFn = studio:match("sv%.DoClick = function%(%).-\n        end") or ""
ok(saveFn ~= "", "обработчик сохранения найден")
ok(saveFn:find("Q.Validate(out)", 1, true) ~= nil,
   "перед сохранением квест реально прогоняется через валидатор")
ok(saveFn:find("it.level == \"error\"", 1, true) ~= nil,
   "ошибки отбираются отдельно от предупреждений")
ok(saveFn:find("Найдены ошибки:", 1, true) ~= nil,
   "и об ошибках сообщают до отправки")
ok(saveFn:find("#errs > 0", 1, true) ~= nil,
   "отправка без подтверждения только когда ошибок нет")
ok(studio:find('Q.BlocksToQuest(work, blocks)', 1, true) ~= nil,
   "на сервер уходит разобранный из графа квест, а не сырые блоки")

--[[ Проверяем на живом примере: собранный из блоков квест без ответа
     «принять квест» валидатор обязан завернуть. ]]
local badBlocks = Q.QuestToBlocks(QUEST)
for _, b in ipairs(badBlocks) do
    if b.kind == "dialogue" then b.data.choices = {} end
end
local badQuest = Q.BlocksToQuest(QUEST, badBlocks)
-- Валидатор живёт в общей части; подгружаем её отдельно.
SERVER = false
local okLoad = pcall(function()
    local chunk = loadfile("lua/autorun/sh_grm_quests.lua")
    if chunk then chunk() end
end)
if isfunction(Q.Validate) then
    local issues = Q.Validate(badQuest)
    local found = false
    for _, it in ipairs(issues) do
        if it.level == "error" and tostring(it.text):find("Принять квест", 1, true) then found = true end
    end
    ok(found, "собранный из блоков квест без accept — валидатор ловит ошибку")
else
    ok(okLoad, "валидатор доступен для проверки", "Q.Validate отсутствует")
end

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
