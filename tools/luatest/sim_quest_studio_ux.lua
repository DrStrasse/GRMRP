--[[ Живой прогон понятности Quest Studio (заказ владельца 28.08).

     «Не понятно как выстраивать выдачу наград и ачивок, и к чему
      сделано криво - до квеста / вовремя / после? надо нормально
      сделать дизайн, ничего не понятно в этом меню. Кое как разобрался
      только с кат-сценой, а как подключить выплаты? Как диалоги
      нормально настроить?»

     ЧТО БЫЛО НЕ ТАК.

       1) Нигде не было записано, в какой момент что срабатывает.
          Порядок жил только в коде finishQuest, автор его не видел.
       2) Вкладки шли в порядке «Награды до Этапов», хотя награда
          выдаётся ПОСЛЕ всех этапов.
       3) Главная ловушка: квест выдаётся ТОЛЬКО ответом с действием
          accept в диалоге. Нет такого ответа — квест взять нельзя, и
          студия об этом молчала.
       4) Не было никакой проверки: о поломке узнавали на сервере.

     Стенд проверяет и ПОРЯДОК в коде сервера, и содержимое подсказок,
     и работу валидатора на живых примерах квестов.

     Запуск: luajit tools/luatest/sim_quest_studio_ux.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t)
    local o = {}
    for k, v in pairs(t or {}) do o[k] = istable(v) and table.Copy(v) or v end
    return o
end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function CurTime() return 100 end
function ErrorNoHalt() end
os.time = function() return 1700000000 end
hook = { Add = function() end, Run = function() end, GetTable = function() return {} end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end, Compress = function(x) return x end }
file = { Exists = function() return false end, Read = function() return "" end,
    Write = function() end, CreateDir = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end }
game = { GetMap = function() return "rp_city" end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests
assert(Q, "GRM.Quests не загрузился")

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local client = readf("lua/autorun/client/cl_grm_quests.lua")
local server = readf("lua/autorun/sh_grm_quests.lua")

-----------------------------------------------------------------------
print("\n=== 1. ПОРЯДОК «ДО / ВОВРЕМЯ / ПОСЛЕ» ЗАПИСАН ЯВНО ===")
-----------------------------------------------------------------------
ok(istable(Q.Lifecycle), "ИСПРАВЛЕНО: жизненный цикл описан таблицей, а не только кодом")

--[[ Дальше работаем с копией, а не с Q.Lifecycle напрямую: если таблицы
     нет, стенд обязан продолжить и показать ВСЕ остальные провалы, а не
     упасть на первой же строке. Первая версия падала и маскировала
     регрессии — откат «убрать таблицу» давал один провал вместо многих. ]]
local LIFE = istable(Q.Lifecycle) and Q.Lifecycle or {}
ok(#LIFE >= 5, "в нём все стадии", #LIFE)

local byPhase = {}
for i, row in ipairs(LIFE) do byPhase[row.phase] = i end
-- Отсутствующая стадия не должна ронять сравнения ниже.
local function idx(name) return byPhase[name] or 0 end
ok(byPhase.offer and byPhase.start and byPhase.active and byPhase.complete and byPhase.after,
   "есть все ключевые фазы: offer, start, active, complete, after")

--[[ Порядок должен совпадать с реальной осью времени, иначе подсказка
     врёт: диалог до принятия идёт раньше принятия, принятие раньше
     этапов, этапы раньше завершения. ]]
ok(idx("offer") > 0 and idx("offer") < idx("start"), "диалог «до» идёт раньше принятия")
ok(idx("start") > 0 and idx("start") < idx("active"), "принятие раньше этапов")
ok(idx("active") > 0 and idx("active") < idx("complete"), "этапы раньше завершения")
ok(idx("complete") > 0 and idx("complete") < idx("after"), "завершение раньше разговора «после»")

-- Каждая стадия объясняет себя человеческим языком.
local emptyText = 0
for _, row in ipairs(LIFE) do
    if tostring(row.what or "") == "" or tostring(row.when or "") == "" then
        emptyText = emptyText + 1
    end
end
ok(emptyText == 0 and #LIFE > 0, "у каждой стадии есть подпись и пояснение", emptyText)

-----------------------------------------------------------------------
print("\n=== 2. ПОДСКАЗКА НЕ РАСХОДИТСЯ С КОДОМ ===")
-----------------------------------------------------------------------
--[[ Главный риск любой документации — она устаревает. Проверяем, что
     реальный порядок в finishQuest тот же, что обещает Lifecycle:
     сначала награда, потом ачивка, потом уведомление, потом кат-сцена. ]]
local finish = server:match("local function finishQuest.-\n    end") or ""
ok(finish ~= "", "функция завершения квеста найдена")

local pReward = finish:find("reward(ply,def)", 1, true)
local pAch    = finish:find("unlockQuestAchievement", 1, true)
local pNotice = finish:find('questNotice(ply,"complete"', 1, true)
-- По началу вызова: аргументы (флаг «ждать конца диалога», тег) со
-- временем добавляются, а проверяем мы ПОРЯДОК шагов, а не сигнатуру.
local pCut    = finish:find("cutscene(ply,def.cutscene.complete", 1, true)
ok(pReward and pAch and pReward < pAch,
   "в коде награда квеста выдаётся ДО ачивки — как и написано в подсказке")
ok(pAch and pNotice and pAch < pNotice, "ачивка до уведомления")
ok(pNotice and pCut and pNotice < pCut, "уведомление до кат-сцены")

local completeText = ""
for _, row in ipairs(LIFE) do
    if row.phase == "complete" then completeText = tostring(row.what or "") end
end
ok(completeText:find("награда", 1, true) ~= nil,
   "подсказка завершения говорит про награду", completeText)
ok(completeText:find("ачивк", 1, true) ~= nil, "и про ачивку")

-- Награда выдаётся ровно один раз, в завершении, а не при старте.
local startFn = server:match("function Q%.Start.-\n    end") or ""
ok(startFn ~= "", "функция старта найдена")
ok(startFn:find("reward(ply", 1, true) == nil,
   "при ПРИНЯТИИ квеста награда не выдаётся — как и обещает подсказка")

-----------------------------------------------------------------------
print("\n=== 3. ВАЛИДАТОР ЛОВИТ ГЛАВНУЮ ЛОВУШКУ ===")
-----------------------------------------------------------------------
ok(isfunction(Q.Validate), "ИСПРАВЛЕНО: появилась проверка квеста")

--[[ Ловушка, на которой владелец и застрял: всё заполнено, а квест
     взять нельзя, потому что в диалоге нет ответа с действием accept. ]]
local noAccept = {
    id = "q1", title = "Тест", npc = "guide",
    steps = { { type = "event", event = "mining", count = 1, title = "Копать" } },
    rewards = { money = 100, items = {} },
    dialogue = { offer = { { id = "offer_1", text = "Привет", choices = {
        { text = "Пока", action = "close" } } } }, active = {}, complete = {} },
}
local issues = Q.Validate(noAccept)
local foundAccept = false
for _, it in ipairs(issues) do
    if it.level == "error" and tostring(it.text):find("Принять квест", 1, true) then
        foundAccept = true
    end
end
ok(foundAccept,
   "БАГ ПОЙМАН: нет ответа «Принять квест» — валидатор кричит ошибкой")

-- С правильным ответом ошибка уходит.
noAccept.dialogue.offer[1].choices[2] = { text = "Берусь", action = "accept" }
local fixed = Q.Validate(noAccept)
local stillAccept = false
for _, it in ipairs(fixed) do
    if tostring(it.text):find("Принять квест", 1, true) then stillAccept = true end
end
ok(not stillAccept, "добавили ответ — ошибка исчезла")

-- Автостарт квесту диалог не нужен: он выдаётся сам.
local auto = table.Copy(noAccept)
auto.dialogue = { offer = {}, active = {}, complete = {} }
auto.autoStart = true
local autoIssues = Q.Validate(auto)
local autoErr = false
for _, it in ipairs(autoIssues) do
    if it.level == "error" and tostring(it.text):find("взять квест", 1, true) then autoErr = true end
end
ok(not autoErr, "у автостартового квеста диалог не требуется — ложной ошибки нет")

-----------------------------------------------------------------------
print("\n=== 4. ВАЛИДАТОР ЛОВИТ ОСТАЛЬНЫЕ ТИПОВЫЕ ОШИБКИ ===")
-----------------------------------------------------------------------
local function hasIssue(def, needle, level)
    for _, it in ipairs(Q.Validate(def)) do
        if tostring(it.text):find(needle, 1, true) and (not level or it.level == level) then
            return true
        end
    end
    return false
end

local base = table.Copy(noAccept)

ok(hasIssue({ id = "x", title = "", steps = {} }, "названия", "error"),
   "пустое название — ошибка")
ok(hasIssue({ id = "x", title = "T", steps = {} }, "Нет ни одного этапа", "error"),
   "квест без этапов — ошибка")

local noReward = table.Copy(base)
noReward.rewards = { money = 0, items = {} }
noReward.achievement = { enabled = false }
ok(hasIssue(noReward, "Награды нет совсем", "warn"),
   "нулевая награда — предупреждение (частая забывчивость)")

local badEvent = table.Copy(base)
badEvent.steps = { { type = "event", event = "", count = 1, title = "?" } }
ok(hasIssue(badEvent, "событие не указано", "error"), "этап-событие без события — ошибка")

local badItem = table.Copy(base)
badItem.steps = { { type = "item", item = "", count = 1, title = "?" } }
ok(hasIssue(badItem, "предмет не указан", "error"), "этап-предмет без предмета — ошибка")

local badVisit = table.Copy(base)
badVisit.steps = { { type = "visit", title = "Дойти" } }
ok(hasIssue(badVisit, "без заданной зоны", "error"), "этап-посещение без зоны — ошибка")

--[[ Висячая ссылка обрывает разговор молча: игрок жмёт ответ и диалог
     просто закрывается. Найти такое вручную почти невозможно. ]]
local badLink = table.Copy(base)
badLink.dialogue.offer[1].choices[1] = { text = "Дальше", next = "nowhere" }
ok(hasIssue(badLink, "несуществующий ID", "warn"), "переход в никуда — предупреждение")

--[[ Действие без аргумента: «Деньги» без суммы выдаёт ноль и выглядит
     как поломка выплат. Это ровно тот вопрос, что задал владелец. ]]
local noArg = table.Copy(base)
noArg.dialogue.offer[1].choices[1] = { text = "Взять деньги", action = "give_money", actionArg = "" }
ok(hasIssue(noArg, "без аргумента", "warn"),
   "действие «Деньги» без суммы — предупреждение")

local achNoName = table.Copy(base)
achNoName.achievement = { enabled = true, id = "a1", name = "", reward = 10 }
ok(hasIssue(achNoName, "без названия", "warn"), "ачивка без названия — предупреждение")

local achNoID = table.Copy(base)
achNoID.achievement = { enabled = true, id = "", name = "N", reward = 10 }
ok(hasIssue(achNoID, "без ID", "error"), "ачивка без ID — ошибка")

-- Полностью корректный квест не должен давать ошибок.
local good = {
    id = "good", title = "Хороший", npc = "guide",
    steps = { { type = "event", event = "mining", count = 3, title = "Копать" } },
    rewards = { money = 500, items = { ore = 2 } },
    achievement = { enabled = true, id = "ach_good", name = "Шахтёр", reward = 100 },
    dialogue = { offer = { { id = "o1", text = "Работа есть", choices = {
        { text = "Берусь", action = "accept" } } } }, active = {}, complete = {} },
}
local goodIssues = Q.Validate(good)
local goodErrors = 0
for _, it in ipairs(goodIssues) do if it.level == "error" then goodErrors = goodErrors + 1 end end
ok(goodErrors == 0, "правильно собранный квест проходит проверку без ошибок", goodErrors)

ok(#Q.Validate(nil) == 0, "nil не роняет проверку")
ok(#Q.Validate({}) > 0, "пустая таблица даёт замечания, а не тишину")

-----------------------------------------------------------------------
print("\n=== 5. ВКЛАДКИ ИДУТ В ПОРЯДКЕ РАБОТЫ ===")
-----------------------------------------------------------------------
--[[ Раньше «Награды» стояли третьими, до «Диалогов», хотя награда — это
     самый конец истории. Нумерация и порядок теперь совпадают с осью
     времени. ]]
local tabOrder = {}
for name in client:gmatch('panelTab%("(%d[^"]*)"') do tabOrder[#tabOrder + 1] = name end
ok(#tabOrder >= 6, "все вкладки пронумерованы", #tabOrder)

local function tabIndex(needle)
    for i, n in ipairs(tabOrder) do if n:find(needle, 1, true) then return i end end
end
ok(tabIndex("Основное") == 1, "1 — Основное", tabIndex("Основное"))
ok(tabIndex("Этапы") == 2, "2 — Этапы", tabIndex("Этапы"))
ok(tabIndex("Диалоги") == 3, "3 — Диалоги (там выдаётся квест)", tabIndex("Диалоги"))
ok(tabIndex("Награды") == 4, "4 — Награды", tabIndex("Награды"))
ok(tabIndex("Кат-сцены") == 6, "6 — Кат-сцены", tabIndex("Кат-сцены"))
ok(tabIndex("Этапы") < tabIndex("Награды"),
   "ИСПРАВЛЕНО: этапы идут ДО наград — как в реальной последовательности")

-----------------------------------------------------------------------
print("\n=== 6. ЛЕНТА ЖИЗНЕННОГО ЦИКЛА НА ВКЛАДКАХ ===")
-----------------------------------------------------------------------
ok(client:find("local function lifecycleStrip", 1, true) ~= nil,
   "ИСПРАВЛЕНО: есть лента «до / вовремя / после»")
ok(client:find("Q.Lifecycle", 1, true) ~= nil,
   "и она берёт текст из общей таблицы, а не дублирует его")

local strips = select(2, client:gsub("lifecycleStrip%(", ""))
ok(strips >= 6, "лента показана на всех вкладках, а не на одной", strips)

for tab, phase in pairs({ stages = "active", rewards = "complete", notifications = "start" }) do
    ok(client:find("lifecycleStrip(" .. tab, 1, true) ~= nil,
       "лента есть на вкладке: " .. tab)
end
ok(client:find('lifecycleStrip(rewards,"complete"', 1, true) ~= nil,
   "на «Наградах» подсвечена стадия ЗАВЕРШЕНИЕ — отвечает на «когда выдаётся»")
ok(client:find('lifecycleStrip(stages,"active"', 1, true) ~= nil,
   "на «Этапах» подсвечена стадия ВО ВРЕМЯ")

-----------------------------------------------------------------------
print("\n=== 7. ОТВЕТЫ НА ВОПРОСЫ ВЛАДЕЛЬЦА ПРЯМО В ОКНЕ ===")
-----------------------------------------------------------------------
-- «Как подключить выплаты?»
ok(client:find("Выдаётся автоматически", 1, true) ~= nil,
   "на «Наградах» написано, что выплата происходит сама")
ok(client:find("Подключать ничего не нужно", 1, true) ~= nil,
   "прямым текстом: подключать ничего не надо")
ok(client:find("ПО ХОДУ разговора", 1, true) ~= nil,
   "и отдельно объяснено, как выдать деньги в середине квеста")

-- «Как диалоги нормально настроить?»
ok(client:find("КВЕСТ ВЫДАЁТСЯ ТОЛЬКО", 1, true) ~= nil,
   "на «Диалогах» выделено главное правило выдачи квеста")

-- Ачивка: её награда отдельная, это неочевидно.
ok(client:find("ОТДЕЛЬНАЯ сумма", 1, true) ~= nil,
   "сказано, что деньги ачивки не заменяют награду квеста")

-- Кат-сцена наград не даёт.
ok(client:find("Кат-сцена НЕ выдаёт награду", 1, true) ~= nil,
   "на «Кат-сценах» сказано, что это только ролик")

-- Уведомления это не награда.
ok(client:find("Это только текст на экране", 1, true) ~= nil,
   "на «Уведомлениях» сказано, что они ничего не выдают")

-- Этапы идут по порядку.
ok(client:find("СТРОГО по порядку", 1, true) ~= nil,
   "на «Этапах» сказано, что порядок важен")

-----------------------------------------------------------------------
print("\n=== 8. КНОПКА ПРОВЕРКИ В СТУДИИ ===")
-----------------------------------------------------------------------
ok(client:find('button(f,"Проверить"', 1, true) ~= nil,
   "ИСПРАВЛЕНО: в студии есть кнопка проверки")
ok(client:find("Q.Validate and Q.Validate(work)", 1, true) ~= nil,
   "она вызывает тот же валидатор, что и сервер — не свою копию правил")
ok(client:find("НЕ БУДЕТ РАБОТАТЬ", 1, true) ~= nil,
   "вердикт написан понятным языком, а не кодом ошибки")
ok(client:find("Ошибок не найдено", 1, true) ~= nil,
   "и отдельно сообщает, когда всё хорошо")

--[[ Проверка должна снимать данные с полей ДО валидации, иначе она
     проверит устаревшую копию и соврёт. ]]
local checkBtn = client:match('button%(f,"Проверить".-setStatus%(%("Проверка') or ""
ok(checkBtn:find("syncGeneral()", 1, true) ~= nil,
   "перед проверкой данные снимаются с полей — валидируется то, что на экране")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
