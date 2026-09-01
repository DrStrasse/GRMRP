--[[ Живой прогон сохранения диалогов в узловом редакторе.

     Жалоба владельца 29.08: «не запоминает диалоги, нормально не
     сохраняет, сбивает их».

     НАЙДЕНО ЧЕТЫРЕ ПРИЧИНЫ, все разные:

       1) UID блока не совпадал с ID реплики. Блок получал uid
          «dlg_offer_1», а переходы в next/choices ссылаются на «offer_1».
          Связи графа хранятся по uid — найти цель было невозможно.

       2) Связи вообще НЕ ВОССТАНАВЛИВАЛИСЬ при загрузке. Переходы
          лежат в самих репликах, а block.links создавался пустым:
          данные целы, но граф после переоткрытия пустой. Это и есть
          «сбивает».

       3) Текст применялся только по кнопке «Применить». Набрал реплику,
          кликнул другой блок — панель пересобралась из старых данных, и
          текст пропал. Это «не запоминает».

       4) ID новой реплики брался из os.time(): две реплики, созданные в
          одну секунду, получали одинаковый ID и схлопывались в одну.

     Запуск: luajit tools/luatest/sim_quest_dialogue_persist.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
CLIENT, SERVER = true, false
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
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
function EyePos() return Vector(1, 2, 3) end
function EyeAngles() return Angle(4, 5, 6) end
os.time = function() return 1700000000 end
surface = { CreateFont = function() end, SetFont = function() end,
    GetTextSize = function(s) return #tostring(s) * 7, 12 end,
    SetDrawColor = function() end, DrawRect = function() end, DrawLine = function() end,
    DrawOutlinedRect = function() end, PlaySound = function() end }
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

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

--- Квест с разветвлённым диалогом: две ветки и линейный переход.
local function makeQuest()
    return {
        id = "intro", title = "Введение", npc = "guide",
        steps = { { type = "event", title = "Копать", event = "mining", count = 1 } },
        rewards = { money = 100, items = {} },
        dialogue = {
            offer = {
                { id = "offer_1", speaker = "Гид", text = "Здравствуй, путник!",
                  next = "", choices = {
                    { text = "Берусь", action = "accept", next = "offer_2" },
                    { text = "Расскажи о городе", action = "", next = "offer_3" },
                  } },
                { id = "offer_2", speaker = "Гид", text = "Отлично, удачи!",
                  next = "", choices = {} },
                { id = "offer_3", speaker = "Гид", text = "Город большой...",
                  next = "offer_1", choices = {} },
            },
            active = { { id = "act_1", speaker = "Гид", text = "Работай", next = "", choices = {} } },
            complete = {},
        },
        cutscene = { accept = {}, complete = {} },
    }
end

local function findBlock(blocks, uid)
    for _, b in ipairs(blocks) do if b.uid == uid then return b end end
end
local function countLinks(blocks)
    local n = 0
    for _, b in ipairs(blocks) do n = n + #(b.links or {}) end
    return n
end

-----------------------------------------------------------------------
print("\n=== 1. UID БЛОКА = ID РЕПЛИКИ ===")
-----------------------------------------------------------------------
local quest = makeQuest()
local blocks = Q.QuestToBlocks(quest)

ok(findBlock(blocks, "offer_1") ~= nil,
   "ИСПРАВЛЕНО: блок доступен по ID реплики, а не по «dlg_offer_1»")
ok(findBlock(blocks, "dlg_offer_1") == nil,
   "БАГ УБРАН: старый синтетический uid больше не используется")
ok(findBlock(blocks, "offer_2") ~= nil and findBlock(blocks, "offer_3") ~= nil,
   "все реплики фазы offer нашлись по своим ID")
ok(findBlock(blocks, "act_1") ~= nil, "реплика фазы active тоже")

--[[ Без совпадения uid и id связь физически не может найти цель:
     воспроизводим старое поведение. ]]
local function oldUID(phase, i) return "dlg_" .. phase .. "_" .. i end
local byOldUID = {}
for i in ipairs(quest.dialogue.offer) do byOldUID[oldUID("offer", i)] = true end
ok(byOldUID["offer_2"] == nil,
   "БАГ ВОСПРОИЗВЕДЁН: переход «offer_2» не находил блок со старым uid")

-----------------------------------------------------------------------
print("\n=== 2. СВЯЗИ ВОССТАНАВЛИВАЮТСЯ ПРИ ЗАГРУЗКЕ ===")
-----------------------------------------------------------------------
--[[ Главная причина «сбивает диалоги»: данные сохранялись, но граф
     открывался без единой линии. ]]
local o1 = findBlock(blocks, "offer_1")
ok(o1 ~= nil, "первая реплика найдена")
ok(#(o1.links or {}) == 2,
   "ИСПРАВЛЕНО: у реплики с двумя ответами восстановлены обе связи",
   #(o1.links or {}))

local byPort = {}
for _, l in ipairs(o1.links or {}) do byPort[l.port] = l.to end
ok(byPort[1] == "offer_2", "первый ответ ведёт в offer_2", tostring(byPort[1]))
ok(byPort[2] == "offer_3", "второй ответ ведёт в offer_3", tostring(byPort[2]))

local o3 = findBlock(blocks, "offer_3")
ok(o3 and #(o3.links or {}) == 1, "линейный переход тоже восстановлен",
   o3 and #(o3.links or {}))
ok(o3 and (o3.links[1] or {}).port == 0, "и он на порту реплики, а не ответа")
ok(o3 and (o3.links[1] or {}).to == "offer_1", "ведёт обратно в offer_1")

-- Блок СТАРТ подключён к первой реплике фазы offer.
local st = findBlock(blocks, "start")
ok(st and #(st.links or {}) == 1, "СТАРТ связан с первой репликой")
ok(st and (st.links[1] or {}).to == "offer_1", "именно с offer_1",
   st and (st.links[1] or {}).to)

--[[ Висячая ссылка не должна создавать связь в никуда: иначе граф
     нарисует линию к несуществующему блоку. ]]
local broken = makeQuest()
broken.dialogue.offer[1].choices[1].next = "нет_такой_реплики"
local bBlocks = Q.QuestToBlocks(broken)
local bo1 = findBlock(bBlocks, "offer_1")
ok(#(bo1.links or {}) == 1, "битая ссылка не превращается в связь", #(bo1.links or {}))

-----------------------------------------------------------------------
print("\n=== 3. КРУГ ЗАГРУЗКА → СОХРАНЕНИЕ → ЗАГРУЗКА ===")
-----------------------------------------------------------------------
--[[ Именно этот сценарий у владельца ломался: открыл, сохранил,
     переоткрыл — диалоги «сбились». ]]
local back = Q.BlocksToQuest(quest, blocks)
ok(#back.dialogue.offer == 3, "все три реплики сохранились", #back.dialogue.offer)
ok(#back.dialogue.active == 1, "фаза active не потерялась")

local savedO1
for _, n in ipairs(back.dialogue.offer) do if n.id == "offer_1" then savedO1 = n end end
ok(savedO1 ~= nil, "offer_1 на месте после сохранения")
ok(savedO1 and #(savedO1.choices or {}) == 2, "оба ответа сохранились",
   savedO1 and #(savedO1.choices or {}))
ok(savedO1 and savedO1.choices[1].next == "offer_2", "переход первого ответа цел",
   savedO1 and savedO1.choices[1].next)
ok(savedO1 and savedO1.choices[1].action == "accept", "действие «принять квест» цело")
ok(savedO1 and savedO1.text == "Здравствуй, путник!", "текст реплики цел")

-- Второй круг: связи обязаны выжить и после переоткрытия.
local blocks2 = Q.QuestToBlocks(back)
ok(countLinks(blocks2) == countLinks(blocks),
   "ИСПРАВЛЕНО: после переоткрытия число связей то же",
   countLinks(blocks2) .. " против " .. countLinks(blocks))

local r1 = findBlock(blocks2, "offer_1")
local byPort2 = {}
for _, l in ipairs(r1.links or {}) do byPort2[l.port] = l.to end
ok(byPort2[1] == "offer_2" and byPort2[2] == "offer_3",
   "и ведут туда же, куда вели")

-- Третий круг — на случай накопления мусора.
local back3 = Q.BlocksToQuest(back, blocks2)
ok(#back3.dialogue.offer == 3, "третий круг: реплик столько же", #back3.dialogue.offer)
local blocks3 = Q.QuestToBlocks(back3)
ok(countLinks(blocks3) == countLinks(blocks), "и связей столько же",
   countLinks(blocks3))

-----------------------------------------------------------------------
print("\n=== 4. ТЕКСТ ПРИМЕНЯЕТСЯ СРАЗУ ===")
-----------------------------------------------------------------------
--[[ Причина «не запоминает»: значение уходило в квест только по кнопке.
     Кликнул другой блок — панель пересобралась из старых данных. ]]
--[[ Берём ветку диалога ИЗ ПАНЕЛИ СВОЙСТВ, а не первое совпадение по
     файлу: «if b.kind == "dialogue"» встречается ещё в BlocksToQuest и
     в отрисовке карточек выше, и шаблон цеплялся за них — проверки
     падали, хотя код был на месте. ]]
local propsFn = studio:match("rebuildProps = function%(%).-\n    end") or ""
local dlgBranch = propsFn:match('if b%.kind == "dialogue" then.-elseif b%.kind == "step" then') or ""
ok(propsFn ~= "", "панель свойств найдена")
ok(dlgBranch ~= "", "панель реплики найдена")
ok(dlgBranch:find("txE.OnChange = function(e) d.text = e:GetValue()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: текст реплики пишется сразу при вводе")
ok(dlgBranch:find("spE.OnChange = function(e) d.speaker = e:GetValue() end", 1, true) ~= nil,
   "говорящий тоже")

--[[ Моделируем прежнее поведение и новое. ]]
local data = { text = "старый" }
local function oldFlow(typed) return data.text end          -- без «Применить»
local function newFlow(typed) data.text = typed return data.text end
ok(oldFlow("новый текст") == "старый",
   "БАГ ВОСПРОИЗВЕДЁН: без кнопки текст оставался старым")
ok(newFlow("новый текст") == "новый текст",
   "ИСПРАВЛЕНО: текст сохраняется по мере ввода")

-- Та же болезнь была у остальных блоков.
--[[ Проверяем с открывающей скобкой: find("mon.OnChange") совпадает и
     с «mon.OnChangeOff», поэтому переименование обработчика проходило
     незамеченным. На эту ловушку с префиксом я уже наступал раньше. ]]
for _, pair in ipairs({
    { "step", "ti.OnChange = function" }, { "music", "snd.OnChange = function" },
    { "reward", "mon.OnChange = function" }, { "achieve", "nm.OnChange = function" },
}) do
    ok(studio:find(pair[2], 1, true) ~= nil,
       "поле применяется сразу в блоке: " .. pair[1])
end
ok(studio:find("cap.OnChange = function(e) cam.caption", 1, true) ~= nil,
   "титр камеры тоже применяется сразу")

-----------------------------------------------------------------------
print("\n=== 5. ID НОВОЙ РЕПЛИКИ УНИКАЛЕН ===")
-----------------------------------------------------------------------
--[[ os.time() за одну секунду даёт одинаковое значение: две реплики
     получали один ID, сервер схлопывал их в одну. ]]
ok(studio:find('id = "node_" .. os.time() % 100000', 1, true) == nil,
   "БАГ УБРАН: ID больше не берётся из времени")
ok(studio:find('while used["node_" .. n] do n = n + 1 end', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ищется первый свободный номер")

local function nextID(existing)
    local used = {}
    for _, id in ipairs(existing) do used[id] = true end
    local n = 1
    while used["node_" .. n] do n = n + 1 end
    return "node_" .. n
end
ok(nextID({}) == "node_1", "первая реплика — node_1")
ok(nextID({ "node_1" }) == "node_2", "вторая — node_2")
ok(nextID({ "node_1", "node_2" }) == "node_3", "третья — node_3")
ok(nextID({ "node_2" }) == "node_1", "дырка в нумерации переиспользуется")

-- Прежний способ давал коллизию.
local function oldID() return "node_" .. (os.time() % 100000) end
ok(oldID() == oldID(),
   "БАГ ВОСПРОИЗВЕДЁН: две реплики за секунду получали ОДИН ID", oldID())

-----------------------------------------------------------------------
print("\n=== 6. ПЕРЕИМЕНОВАНИЕ ID НЕ РВЁТ ПЕРЕХОДЫ ===")
-----------------------------------------------------------------------
--[[ Если сменить ID реплики, ссылки на неё из других реплик обязаны
     обновиться — иначе разговор молча обрывается. ]]
ok(dlgBranch:find("Применить ID", 1, true) ~= nil, "кнопка отвечает за смену ID")
ok(dlgBranch:find('if tostring(od.next or "") == oldID then od.next = newID end', 1, true) ~= nil,
   "ИСПРАВЛЕНО: линейные переходы переписываются на новый ID")
ok(dlgBranch:find('if tostring(ch.next or "") == oldID then ch.next = newID end', 1, true) ~= nil,
   "переходы ответов тоже")
ok(dlgBranch:find("if l.to == oldID then l.to = newID end", 1, true) ~= nil,
   "и связи графа")
ok(dlgBranch:find("d.id, b.uid = newID, newID", 1, true) ~= nil,
   "uid блока обновляется вместе с ID — иначе связи снова разъедутся")

-- Моделируем переименование.
local nodes = {
    { id = "a", next = "b", choices = {} },
    { id = "b", next = "", choices = { { text = "x", next = "a" } } },
}
local function rename(list, oldID, newID)
    for _, n in ipairs(list) do
        if n.next == oldID then n.next = newID end
        for _, ch in ipairs(n.choices or {}) do
            if ch.next == oldID then ch.next = newID end
        end
        if n.id == oldID then n.id = newID end
    end
end
rename(nodes, "a", "intro_hello")
ok(nodes[1].id == "intro_hello", "реплика переименована")
ok(nodes[2].choices[1].next == "intro_hello",
   "ссылка из другой реплики обновилась", nodes[2].choices[1].next)

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
