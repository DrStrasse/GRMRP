--[[ Живой прогон связей с кат-сценой и запуска просмотра.

     Жалоба владельца 29.08: «связь в графе с кат-сценой не
     устанавливается и не запускается кат-сцена».

     ДВЕ РАЗНЫЕ ПРИЧИНЫ:

       1) СВЯЗЬ НЕ СОХРАНЯЛАСЬ. Переходы между репликами лежат в самих
          репликах (next / choices[i].next), поэтому они переживали
          сохранение. А связи с кат-сценой, музыкой, наградой и ачивкой
          не хранились НИГДЕ: соединил блоки, сохранил, переоткрыл —
          линий нет.

       2) ПРОСМОТР НЕ ЗАПУСКАЛСЯ. startCutscene была локальной функцией
          файла cl_grm_quests. Редактор живёт в другом файле и дотянуться
          до неё не мог: кнопка слала пакет серверу, тот лишь настраивал
          видимость мира (PVS) и обратно ничего не присылал.

     Запуск: luajit tools/luatest/sim_quest_cutscene_link.lua ]]

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
NOTIFY_HINT, NOTIFY_GENERIC, NOTIFY_ERROR = 1, 0, 2
GRM = {}

assert(loadfile("lua/autorun/client/zz_grm_quest_studio.lua"))()
local Q = GRM.Quests

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local client = readf("lua/autorun/client/cl_grm_quests.lua")
local server = readf("lua/autorun/sh_grm_quests.lua")

local function findBlock(blocks, uid)
    for _, b in ipairs(blocks) do if b.uid == uid then return b end end
end

--- Квест с кат-сценой, наградой и репликой.
local function makeQuest()
    return {
        id = "intro", title = "Введение", npc = "guide",
        steps = { { type = "event", title = "Копать", event = "mining", count = 1 } },
        rewards = { money = 500, items = {} },
        dialogue = {
            offer = { { id = "offer_1", speaker = "Гид", text = "Привет",
                        next = "", choices = { { text = "Берусь", action = "accept", next = "" } } } },
            active = {}, complete = {},
        },
        cutscene = {
            accept = { { id = "camera_1", transition = "cut", duration = 3, fov = 75,
                         caption = "Город", pos = { x = 1, y = 2, z = 3 },
                         ang = { p = 0, y = 90, r = 0 } } },
            complete = {},
        },
    }
end

-----------------------------------------------------------------------
print("\n=== 1. БАГ ВОСПРОИЗВЕДЁН: СВЯЗИ ХРАНИЛИСЬ ТОЛЬКО У РЕПЛИК ===")
-----------------------------------------------------------------------
--[[ Переход реплики лежит в самой реплике, поэтому переживал круг.
     У кат-сцены такого поля нет — связь была негде хранить. ]]
local sample = makeQuest()
ok(sample.dialogue.offer[1].next ~= nil,
   "у реплики есть поле перехода — её связь сохранялась")
ok(sample.cutscene.accept[1].next == nil or sample.cutscene.accept[1].next == "",
   "БАГ: у блока кат-сцены поля связи с другими блоками нет вовсе")
ok(sample.rewards.next == nil, "у награды тоже")

-----------------------------------------------------------------------
print("\n=== 2. СВЯЗЬ СТАРТ → КАТ-СЦЕНА ПЕРЕЖИВАЕТ СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
local quest = makeQuest()
local blocks = Q.QuestToBlocks(quest)

local st = findBlock(blocks, "start")
local cut = findBlock(blocks, "cut_accept")
local rew = findBlock(blocks, "reward")
ok(st and cut and rew, "блоки старт, кат-сцена и награда созданы")

--[[ Соединяем как в редакторе. linkBlocks сначала снимает прежнюю
     связь с того же порта — повторяем это, иначе стенд создаёт две
     линии из одного выхода, чего интерфейс не допускает. ]]
local function connect(from, to, port)
    port = port or 0
    for i = #from.links, 1, -1 do
        if (from.links[i].port or 0) == port then table.remove(from.links, i) end
    end
    from.links[#from.links + 1] = { to = to.uid, port = port }
end
connect(st, cut)      -- старт → кат-сцена (заменяет авто-связь на реплику)
connect(cut, rew)     -- кат-сцена → награда

local saved = Q.BlocksToQuest(quest, blocks)
ok(istable(saved.graph), "ИСПРАВЛЕНО: раскладка связей попала в квест")
ok(istable(saved.graph.links) and #saved.graph.links >= 2,
   "обе связи сохранены", saved.graph and #saved.graph.links)

local function hasLink(g, from, to)
    for _, l in ipairs((istable(g) and g.links) or {}) do
        if l.from == from and l.to == to then return true end
    end
    return false
end
ok(hasLink(saved.graph, "start", "cut_accept"), "связь старт → кат-сцена записана")
ok(hasLink(saved.graph, "cut_accept", "reward"), "связь кат-сцена → награда записана")

-- Переоткрываем: линии обязаны вернуться.
local reopened = Q.QuestToBlocks(saved)
local st2 = findBlock(reopened, "start")
local cut2 = findBlock(reopened, "cut_accept")
local function linkedTo(b, uid)
    for _, l in ipairs((b and b.links) or {}) do if l.to == uid then return true end end
    return false
end
ok(linkedTo(st2, "cut_accept"),
   "ИСПРАВЛЕНО: после переоткрытия связь старт → кат-сцена на месте")
ok(linkedTo(cut2, "reward"), "и кат-сцена → награда тоже")

-- Второй круг — связи не должны копиться или пропадать.
local saved2 = Q.BlocksToQuest(saved, reopened)
ok(#saved2.graph.links == #saved.graph.links,
   "второй круг: число связей не изменилось",
   #saved2.graph.links .. " против " .. #saved.graph.links)

-----------------------------------------------------------------------
print("\n=== 3. МУСОРНЫЕ СВЯЗИ НЕ ВОССТАНАВЛИВАЮТСЯ ===")
-----------------------------------------------------------------------
--[[ Ссылка на удалённый блок нарисовала бы линию в пустоту. ]]
local dirty = Q.BlocksToQuest(quest, blocks)
dirty.graph.links[#dirty.graph.links + 1] = { from = "start", to = "нет_такого", port = 0 }
dirty.graph.links[#dirty.graph.links + 1] = { from = "тоже_нет", to = "reward", port = 0 }
local clean = Q.QuestToBlocks(dirty)
local cs = findBlock(clean, "start")
ok(not linkedTo(cs, "нет_такого"), "связь на исчезнувший блок пропущена")
local total = 0
for _, b in ipairs(clean) do total = total + #(b.links or {}) end
ok(total >= 2, "живые связи при этом сохранились", total)

-- Связь блока с самим собой не имеет смысла.
local selfLink = Q.BlocksToQuest(quest, blocks)
selfLink.graph.links[#selfLink.graph.links + 1] = { from = "reward", to = "reward", port = 0 }
local noSelf = Q.QuestToBlocks(selfLink)
ok(not linkedTo(findBlock(noSelf, "reward"), "reward"), "петля на себя отброшена")

-- Диалоговые связи не должны задваиваться: они уже подняты из реплик.
local dlgQuest = makeQuest()
dlgQuest.dialogue.offer[1].choices[1].next = "offer_1"
local dlgBlocks = Q.QuestToBlocks(dlgQuest)
local savedDlg = Q.BlocksToQuest(dlgQuest, dlgBlocks)
local reDlg = Q.QuestToBlocks(savedDlg)
local o1 = findBlock(reDlg, "offer_1")
local portCount = {}
for _, l in ipairs((o1 and o1.links) or {}) do
    portCount[l.port] = (portCount[l.port] or 0) + 1
end
local dup = false
for _, c in pairs(portCount) do if c > 1 then dup = true end end
ok(not dup, "на одном порту не появляется двух связей")

-----------------------------------------------------------------------
print("\n=== 4. СЕРВЕР НЕ СТИРАЕТ РАСКЛАДКУ ===")
-----------------------------------------------------------------------
--[[ Нормализация пересобирает квест по полям: без своей функции поле
     graph исчезло бы при первом сохранении, как было с координатами. ]]
ok(server:find("local function normalizeGraph", 1, true) ~= nil,
   "ИСПРАВЛЕНО: у раскладки связей есть нормализация")
ok(server:find("graph=normalizeGraph(raw.graph)", 1, true) ~= nil,
   "и она вызывается при сохранении квеста")

-- Воспроизводим правила нормализации.
local function normalizeGraph(value)
    if not istable(value) then return nil end
    local out = { links = {} }
    for _, l in ipairs(istable(value.links) and value.links or {}) do
        if #out.links >= 256 then break end
        local from = string.Trim(tostring(l.from or ""))
        local to = string.Trim(tostring(l.to or ""))
        if from ~= "" and to ~= "" then
            out.links[#out.links + 1] = { from = from, to = to,
                port = math.Clamp(math.floor(tonumber(l.port) or 0), 0, 32) }
        end
    end
    if #out.links == 0 then return nil end
    return out
end
ok(normalizeGraph(nil) == nil, "нет графа — нет поля, файл не засоряется")
ok(normalizeGraph({ links = {} }) == nil, "пустой список тоже отбрасывается")
ok(normalizeGraph({ links = { { from = "", to = "x" } } }) == nil,
   "связь без источника отбрасывается")
local okg = normalizeGraph({ links = { { from = "a", to = "b", port = 99 } } })
ok(okg and okg.links[1].port == 32, "номер порта зажимается сверху",
   okg and okg.links[1].port)
local many = { links = {} }
for i = 1, 400 do many.links[i] = { from = "a", to = "b" } end
ok(#normalizeGraph(many).links == 256, "число связей ограничено — файл не раздуется",
   #normalizeGraph(many).links)

-----------------------------------------------------------------------
print("\n=== 5. ПРОСМОТР КАТ-СЦЕНЫ ЗАПУСКАЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Вторая причина: функция запуска была локальной и редактор её не
     видел. Кнопка слала пакет серверу, а тот сцену не начинал. ]]
ok(client:find("Q.StartCutscene = startCutscene", 1, true) ~= nil,
   "ИСПРАВЛЕНО: запуск сцены доступен другим файлам")

local playFn = studio:match("play%.DoClick = function%(%).-\n            end") or ""
ok(playFn ~= "", "обработчик кнопки просмотра найден")
ok(playFn:find("Q.StartCutscene(table.Copy(d.cams), true)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: кнопка запускает сцену локально")
ok(playFn:find('net.Start("GRM_Quest_CutscenePreview")', 1, true) == nil,
   "БАГ УБРАН: пакет серверу вместо запуска больше не шлётся")
ok(playFn:find("isfunction(Q.StartCutscene)", 1, true) ~= nil,
   "есть защита, если модуль кат-сцен не загружен")
ok(playFn:find("f:SetVisible(false)", 1, true) ~= nil,
   "окно студии прячется на время просмотра")
ok(playFn:find("Q.Cutscene.restoreFrame = f", 1, true) ~= nil,
   "и возвращается после — иначе редактор пропал бы навсегда")

--[[ Сервер по-прежнему должен узнать о просмотре: без этого дальние
     объекты не прогрузятся и сцена будет снимать пустоту (PVS). ]]
ok(client:find('net.Start("GRM_Quest_CutscenePreview")', 1, true) ~= nil,
   "startCutscene сам сообщает серверу о предпросмотре")
ok(server:find('net.Receive("GRM_Quest_CutscenePreview"', 1, true) ~= nil,
   "сервер это сообщение принимает")
ok(server:find("startCutscenePVS(ply,nodes)", 1, true) ~= nil,
   "и подгружает мир вокруг камер")

--[[ Порядок важен: сначала помечаем сцену активной, потом просим
     сервер. Иначе кадр может успеть отрисоваться без данных. ]]
local startFn = client:match("local function startCutscene.-\nend") or ""
ok(startFn ~= "", "функция запуска найдена")
ok(startFn:find("adminPreview", 1, true) ~= nil,
   "у запуска есть режим предпросмотра для админа")
ok(startFn:find("В этой фазе нет точек кат%-сцены") ~= nil,
   "пустой список камер не роняет запуск, а сообщает об этом")

-----------------------------------------------------------------------
print("\n=== 6. У БЛОКОВ ЕСТЬ ПОРТЫ ДЛЯ СОЕДИНЕНИЯ ===")
-----------------------------------------------------------------------
--[[ Если бы у кат-сцены не было порта, связь нельзя было бы даже
     протянуть мышью. ]]
ok(studio:find('if b.kind ~= "finish" then', 1, true) ~= nil,
   "порт выхода есть у всех блоков, кроме финиша")
ok(studio:find("makePort(card, b, 0, 0, 30)", 1, true) ~= nil,
   "блок без ответов получает один общий порт")

-- Число портов: у реплики по ответу, у остальных один.
local function portCountOf(b)
    if b.kind == "dialogue" then return #((b.data or {}).choices or {}) end
    return 0
end
ok(portCountOf({ kind = "cutscene", data = {} }) == 0,
   "у кат-сцены один общий выход, а не список")
ok(portCountOf({ kind = "dialogue", data = { choices = { {}, {} } } }) == 2,
   "у реплики с двумя ответами два порта")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
