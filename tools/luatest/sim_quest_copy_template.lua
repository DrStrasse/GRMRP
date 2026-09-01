--[[ Живой прогон копирования квестов и шаблонов.

     Заказ владельца 29.08: «сделай возможность копирования квестов и
     создание шаблонов, но при этом с пометкой о необходимости изменить
     какие-либо параметры или просто плашку с предупреждением».

     ЧТО НЕЛЬЗЯ ПРОСТО СКОПИРОВАТЬ — и почему это опасно:

       • ID квеста: копия с тем же ID ЗАТРЁТ оригинал;
       • ID достижения: два квеста с одной ачивкой — вторая молча не
         выдастся, система считает её полученной;
       • зоны этапов и точки камер: это координаты, копия ведёт игроков
         ровно туда же, куда оригинал;
       • ID NPC: оба квеста повиснут на одном персонаже.

     Худший из этих багов — координаты: он НЕ ВИДЕН при беглом взгляде,
     квест выглядит рабочим и тихо ведёт не туда. Поэтому шаблон их
     чистит, а копия громко предупреждает.

     Запуск: luajit tools/luatest/sim_quest_copy_template.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isvector(v) return istable(v) and v.x ~= nil end
function isangle(v) return istable(v) and v.p ~= nil end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t)
    if not istable(t) then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = istable(v) and table.Copy(v) or v end
    return o
end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function CurTime() return 100 end
function ErrorNoHalt() end
os.time = function() return 1700000000 end
local CURRENT_MAP = "rp_city"
game = { GetMap = function() return CURRENT_MAP end }
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end, Compress = function(x) return x end }
file = { Exists = function() return false end, Read = function() return "" end,
    Write = function() end, CreateDir = function() end, IsDir = function() return true end }
net = setmetatable({}, { __index = function() return function() return "" end end })
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_quests.lua"))()
local Q = GRM.Quests

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local server = readf("lua/autorun/sh_grm_quests.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

--- Полноценный квест: зоны, камеры, ачивка, NPC, цепочка.
local function makeQuest()
    return {
        id = "intro", title = "Введение", npc = "guide", map = "rp_city",
        enabled = true, draft = false,
        prerequisites = { "prologue" },
        steps = {
            { type = "visit", title = "Дойти до завода",
              min = { x = 10, y = 20, z = 30 }, max = { x = 40, y = 50, z = 60 } },
            { type = "event", title = "Копать", event = "mining", count = 3 },
        },
        rewards = { money = 500, items = { ore = 2 } },
        achievement = { enabled = true, id = "quest_intro", name = "Старт", reward = 100 },
        dialogue = {
            offer = { { id = "offer_1", text = "Привет", choices = {
                { text = "Берусь", action = "accept" } } } },
            active = {}, complete = {},
        },
        cutscene = {
            accept = { { id = "camera_1", duration = 3, fov = 75,
                         pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 0, r = 0 } } },
            complete = {},
        },
    }
end

local function hasNote(list, needle)
    for _, n in ipairs(list or {}) do
        if tostring(n.text):find(needle, 1, true) then return true, n.level end
    end
    return false
end

-----------------------------------------------------------------------
print("\n=== 1. КОПИЯ НЕ ЗАТИРАЕТ ОРИГИНАЛ ===")
-----------------------------------------------------------------------
ok(isfunction(Q.CopyQuest), "появилось копирование квеста")
ok(isfunction(Q.CopyWarnings), "и разбор того, что перепроверить")

local src = makeQuest()
local copy, warns = Q.CopyQuest(src, "intro_copy", false)
ok(copy ~= nil, "копия создана")
ok(copy.id == "intro_copy", "у копии НОВЫЙ id — оригинал не затрётся", copy.id)
ok(src.id == "intro", "оригинал не тронут", src.id)
ok(copy.title:find("(копия)", 1, true) ~= nil, "в названии видно, что это копия", copy.title)

--[[ Копия не должна сразу уйти в бой: она ведёт игроков в старые
     координаты, пока автор их не поправил. ]]
ok(copy.draft == true, "копия помечена черновиком")
ok(copy.enabled == false, "и выключена — не появится у NPC до правки")

-- Содержимое переносится целиком: это всё-таки копия.
ok(#copy.steps == 2, "этапы скопированы", #copy.steps)
ok(#copy.dialogue.offer == 1, "диалоги скопированы")
ok(copy.rewards.money == 500, "награда скопирована")
ok(copy.rewards.items.ore == 2, "предметы награды тоже")

--[[ Пустой ID не должен приводить к безымянному квесту. ]]
local auto = Q.CopyQuest(src, "", false)
ok(auto.id ~= "" and auto.id ~= "intro", "пустой ID заменяется на производный", auto.id)
local dirty = Q.CopyQuest(src, "Моя Копия!", false)
ok(not dirty.id:find(" "), "ID чистится так же, как на сервере", dirty.id)

-----------------------------------------------------------------------
print("\n=== 2. ID ДОСТИЖЕНИЯ ОБЯЗАН БЫТЬ СВОЙ ===")
-----------------------------------------------------------------------
--[[ Самая коварная ловушка: с прежним ID ачивка второго квеста просто
     не выдастся — система решит, что игрок её уже получил. ]]
ok(copy.achievement.id ~= src.achievement.id,
   "ИСПРАВЛЕНО: у копии свой ID достижения",
   copy.achievement.id .. " против " .. src.achievement.id)
ok(copy.achievement.id == "quest_intro_copy", "он выведен из нового ID квеста",
   copy.achievement.id)
ok(copy.achievement.name == "Старт", "название ачивки сохранено — его правят вручную")

-- Если ачивки нет, ничего не выдумываем.
local noAch = makeQuest()
noAch.achievement = { enabled = false }
local c2 = Q.CopyQuest(noAch, "x_copy", false)
ok(c2.achievement.enabled == false, "выключенная ачивка остаётся выключенной")

-----------------------------------------------------------------------
print("\n=== 3. ПРЕДУПРЕЖДЕНИЯ ПО ФАКТУ, А НЕ ОБЩИЕ СЛОВА ===")
-----------------------------------------------------------------------
ok(#warns > 0, "предупреждения выданы", #warns)

local hasZone, zoneLevel = hasNote(warns, "Зон этапов")
ok(hasZone, "сказано про зоны этапов")
ok(zoneLevel == "must", "и это обязательный к правке пункт", tostring(zoneLevel))
ok(hasNote(warns, "1"), "указано КОЛИЧЕСТВО зон, а не просто «есть зоны»")

local hasCam, camLevel = hasNote(warns, "Точек камер")
ok(hasCam, "сказано про камеры")
ok(camLevel == "must", "тоже обязательный пункт")

ok(hasNote(warns, "ID квеста заменён"), "сказано про новый ID")
ok(hasNote(warns, "ID достижения обновлён"), "сказано про ачивку")
ok(hasNote(warns, "guide"), "назван конкретный NPC, а не «проверьте NPC»")
ok(hasNote(warns, "предыдущие квесты"), "сказано про цепочку квестов")

--[[ Пустые разделы упоминаться не должны: иначе предупреждение
     превращается в шум, который перестают читать. ]]
local bare = {
    id = "bare", title = "Пустой", steps = {}, rewards = { money = 0, items = {} },
    dialogue = { offer = {}, active = {}, complete = {} },
    cutscene = { accept = {}, complete = {} },
}
local bareWarns = Q.CopyWarnings(bare)
ok(not hasNote(bareWarns, "Зон этапов"), "нет зон — нет пункта про зоны")
ok(not hasNote(bareWarns, "Точек камер"), "нет камер — нет пункта про камеры")
ok(not hasNote(bareWarns, "NPC"), "нет NPC — нет пункта про NPC")
ok(hasNote(bareWarns, "ID квеста заменён"), "но про ID сказано всегда")
ok(#bareWarns < #warns, "у пустого квеста предупреждений меньше",
   #bareWarns .. " против " .. #warns)

ok(#Q.CopyWarnings(nil) == 0, "nil не роняет разбор")

-- Копия квеста с другой карты предупреждает и об этом.
CURRENT_MAP = "rp_downtown"
local alienWarns = Q.CopyWarnings(makeQuest())
ok(hasNote(alienWarns, "создан для карты"), "чужая карта тоже попадает в список")
CURRENT_MAP = "rp_city"

-----------------------------------------------------------------------
print("\n=== 4. ШАБЛОН ЧИСТИТ ПРИВЯЗКИ К МЕСТУ ===")
-----------------------------------------------------------------------
--[[ Главное отличие шаблона: он НЕ должен выглядеть готовым. Оставить
     координаты — значит получить квест, который тихо ведёт не туда. ]]
local tpl = Q.CopyQuest(makeQuest(), "intro_tpl", true)
ok(tpl.title:find("(шаблон)", 1, true) ~= nil, "в названии видно, что это шаблон", tpl.title)

ok(tpl.steps[1].min == nil and tpl.steps[1].max == nil,
   "ИСПРАВЛЕНО: координаты зоны очищены — их нельзя унаследовать молча")
ok(tpl.steps[1].pos == nil, "точка тоже очищена")
ok(tpl.steps[1].type == "visit", "но ТИП этапа сохранён — структура полезна")
ok(tpl.steps[1].title == "Дойти до завода", "и название этапа сохранено")
ok(#tpl.steps == 2, "все этапы на месте", #tpl.steps)

ok(#tpl.cutscene.accept == 0, "камеры очищены — они снимали другое место")
ok(tpl.npc == "", "привязка к NPC снята")
ok(#tpl.prerequisites == 0, "цепочка предыдущих квестов снята")

-- Диалоги и награда — это содержание, их шаблон сохраняет.
ok(#tpl.dialogue.offer == 1, "диалоги сохранены: это и есть ценность шаблона")
ok(tpl.rewards.money == 500, "награда сохранена")

--[[ Обычная копия, наоборот, обязана сохранить координаты: человек
     просил именно копию. ]]
ok(copy.steps[1].min ~= nil, "у обычной копии координаты НЕ чистятся")
ok(#copy.cutscene.accept == 1, "и камеры на месте")

-----------------------------------------------------------------------
print("\n=== 5. ПРЕДУПРЕЖДЕНИЕ ПЕРЕЖИВАЕТ СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
--[[ Автор может закрыть студию и вернуться завтра. Если заметки живут
     только в памяти, напоминание исчезнет, а старые координаты
     останутся. ]]
ok(istable(copy.copyNotes) and #copy.copyNotes > 0,
   "ИСПРАВЛЕНО: заметки лежат в самом квесте", copy.copyNotes and #copy.copyNotes)

local saved = Q.NormalizeDefinition(copy)
ok(saved ~= nil, "копия нормализуется без ошибок")
ok(istable(saved.copyNotes) and #saved.copyNotes > 0,
   "заметки пережили сохранение", saved.copyNotes and #saved.copyNotes)
ok(saved.copyNotes[1].text ~= "", "текст заметки не потерялся")

-- Уровень важности сохраняется: по нему красится плашка.
local levels = {}
for _, n in ipairs(saved.copyNotes) do levels[n.level] = true end
ok(levels.must, "уровень «обязательно» сохранён")

-- Квест без заметок не должен обрастать пустым полем в файле.
local plain = Q.NormalizeDefinition(makeQuest())
ok(plain.copyNotes == nil, "у обычного квеста поля заметок нет — файл не засоряется")

-- Мусор не должен ломать нормализацию.
local junk = Q.NormalizeDefinition({ id = "j", title = "J", copyNotes = "строка",
    steps = { { type = "event", event = "e", count = 1, title = "x" } } })
ok(junk.copyNotes == nil, "строка вместо списка отбрасывается")

-----------------------------------------------------------------------
print("\n=== 6. ВАЛИДАТОР ЗНАЕТ О НЕПРОВЕРЕННОЙ КОПИИ ===")
-----------------------------------------------------------------------
local issues = Q.Validate(saved)
local found, lvl = false, nil
for _, it in ipairs(issues) do
    if tostring(it.text):find("Это копия", 1, true) then found, lvl = true, it.level end
end
ok(found, "ИСПРАВЛЕНО: проверка квеста напоминает о непроверенной копии")
--[[ Именно предупреждение, а не ошибка: автор мог осознанно оставить
     те же координаты, и запрещать сохранение было бы неверно. ]]
ok(lvl == "warn", "это предупреждение, а не запрет на сохранение", tostring(lvl))

saved.copyNotes = nil
local clean = Q.Validate(saved)
local still = false
for _, it in ipairs(clean) do
    if tostring(it.text):find("Это копия", 1, true) then still = true end
end
ok(not still, "после подтверждения напоминание уходит")

-----------------------------------------------------------------------
print("\n=== 7. КНОПКИ И ПЛАШКА В СТУДИИ ===")
-----------------------------------------------------------------------
ok(studio:find('mkBtn(left, "Копировать квест"', 1, true) ~= nil, "есть кнопка копирования")
ok(studio:find('mkBtn(left, "Сделать шаблон"', 1, true) ~= nil, "и кнопка шаблона")
ok(studio:find("Шаблон очистит координаты зон", 1, true) ~= nil,
   "шаблон спрашивает подтверждение и честно говорит, что удалит")

local copyFn = studio:match("local function makeCopy%(asTemplate%).-\n        end") or ""
ok(copyFn ~= "", "обработчик копирования найден")
ok(copyFn:find("Q.BlocksToQuest(work, blocks)", 1, true) ~= nil,
   "копируется текущее состояние графа, а не сохранённое ранее")
ok(copyFn:find("while taken[newID] do", 1, true) ~= nil,
   "ищется свободный ID — вторая копия не затрёт первую")

--[[ Плашку проверяем через УСЛОВИЕ её показа, а не поиском текста:
     откат «if false then» оставлял весь текст в файле, и проверка
     проходила, хотя плашка не рисовалась никогда. ]]
local plaqueCond = studio:match("if istable%(work%.copyNotes%) and #work%.copyNotes > 0 then")
ok(plaqueCond ~= nil,
   "ИСПРАВЛЕНО: плашка показывается по факту наличия заметок")
ok(studio:find("if false then", 1, true) == nil,
   "условие показа не выродилось в «никогда»")
ok(studio:find("ПРОВЕРЬТЕ ПЕРЕД ЗАПУСКОМ", 1, true) ~= nil, "текст плашки на месте")
ok(studio:find("Я всё проверил — убрать напоминание", 1, true) ~= nil,
   "снимается только осознанным действием")
ok(studio:find("Q.WrapText(n.text", 1, true) ~= nil,
   "длинный текст переносится, а не уезжает за панель")
ok(studio:find("НЕ ПРОВЕРЕН · ", 1, true) ~= nil,
   "непроверенная копия помечена в списке квестов")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
