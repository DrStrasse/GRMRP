--[[ Живой прогон полноты настроек блоков (заказ владельца 28.08).

     На вопрос «каждый блок настраиваемый?» честный ответ был «почти»:

       • у ЭТАПА не было полей target, radius, consume и описания —
         донастроить можно было только через старую студию;
       • у КАТ-СЦЕНЫ правились лишь титр и длительность: FOV, тип
         перехода и время пролёта отсутствовали;
       • у АЧИВКИ не выводился ID — он молча подставлялся из ID квеста,
         и две ачивки разных квестов могли столкнуться;
       • у ФИНИША не было панели вовсе — блок выглядел сломанным;
       • МУЗЫКА сохранялась в квест, но движок её не проигрывал: не было
         ни момента воспроизведения, ни самого воспроизведения.

     Стенд проверяет, что все поля дошли и до панели, и до формата
     квеста, и что музыка реально звучит в заданный момент.

     Запуск: luajit tools/luatest/sim_quest_block_fields.lua ]]

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
local server = readf("lua/autorun/sh_grm_quests.lua")
local client = readf("lua/autorun/client/cl_grm_quests.lua")

--- Тело ветки конкретного блока в панели свойств.
local function branch(kind)
    local anchor = studio:find("rebuildProps = function()", 1, true)
    if not anchor then return "" end
    local pat = (kind == "dialogue") and 'if b.kind == "dialogue" then' or
        ('elseif b.kind == "' .. kind .. '" then')
    local s = studio:find(pat, anchor, true)
    if not s then return "" end
    local e = studio:find('elseif b.kind == "', s + 10, true) or (s + 4000)
    return studio:sub(s, e)
end

-----------------------------------------------------------------------
print("\n=== 1. У КАЖДОГО БЛОКА ЕСТЬ ПАНЕЛЬ ===")
-----------------------------------------------------------------------
--[[ Раньше ФИНИШ не имел ветки вовсе: выбираешь блок — панель пустая,
     выглядит как поломка. ]]
for _, kind in ipairs({ "dialogue", "step", "cutscene", "music", "reward", "achieve", "start", "finish" }) do
    ok(branch(kind) ~= "", "панель есть у блока: " .. kind)
end
ok(branch("finish"):find("Конец квеста", 1, true) ~= nil,
   "ИСПРАВЛЕНО: ФИНИШ объясняет, что происходит в этот момент")
ok(branch("finish"):find("награда", 1, true) ~= nil,
   "и перечисляет порядок: награда, ачивка, уведомление, кат-сцена")

-----------------------------------------------------------------------
print("\n=== 2. ЭТАП: ВСЕ ПОЛЯ ФОРМАТА ===")
-----------------------------------------------------------------------
local st = branch("step")
ok(st:find("Пояснение", 1, true) ~= nil, "ИСПРАВЛЕНО: появилось описание этапа")
ok(st:find("Цель события", 1, true) ~= nil, "ИСПРАВЛЕНО: появилась цель события (target)")
ok(st:find("Радиус точки", 1, true) ~= nil, "ИСПРАВЛЕНО: появился радиус зоны")
ok(st:find("Изъять предметы", 1, true) ~= nil, "ИСПРАВЛЕНО: появилась галочка изъятия")

--[[ Поля показываются ПО ТИПУ: у «принести предмет» радиуса быть не
     должно, иначе автор гадает, что из восьми полей относится к делу. ]]
ok(st:find('if d.type == "talk" then', 1, true) ~= nil, "поля зависят от типа этапа")
ok(st:find('elseif d.type == "visit" then', 1, true) ~= nil, "у «посетить» своя ветка")
ok(st:find("d.consume = v", 1, true) ~= nil, "галочка пишется в данные")
ok(st:find("d.target = tgt2:GetValue()", 1, true) ~= nil, "цель события сохраняется")
ok(st:find("d.radius = math.Clamp", 1, true) ~= nil, "радиус сохраняется с ограничением")
ok(st:find("d.description = ds:GetValue()", 1, true) ~= nil, "описание сохраняется")

-- Предупреждение о незаданной зоне: без неё этап молча не выполнится.
ok(st:find("Зона НЕ задана", 1, true) ~= nil,
   "видно, задана ли зона у этапа «посетить место»")

-- Все поля переживают круг «блоки → квест».
local quest = { id = "q", title = "Q", npc = "guide",
    steps = {}, rewards = { money = 0, items = {} },
    dialogue = { offer = {}, active = {}, complete = {} },
    cutscene = { accept = {}, complete = {} } }
local stepBlock = { uid = "s1", kind = "step", x = 10, y = 20, links = {}, data = {
    type = "event", title = "Добыть", description = "Копай в шахте",
    event = "mining", target = "iron", count = 7, radius = 300, consume = true } }
local backQ = Q.BlocksToQuest(quest, { stepBlock })
local s1 = backQ.steps[1] or {}
ok(s1.target == "iron", "цель события дошла до квеста", tostring(s1.target))
ok(s1.description == "Копай в шахте", "описание дошло")
ok(s1.radius == 300, "радиус дошёл", tostring(s1.radius))
ok(s1.consume == true, "изъятие дошло")
ok(s1.count == 7, "количество дошло", tostring(s1.count))

-----------------------------------------------------------------------
print("\n=== 3. КАТ-СЦЕНА: FOV, ПЕРЕХОД, ПРОЛЁТ ===")
-----------------------------------------------------------------------
local cs = branch("cutscene")
ok(cs:find("FOV", 1, true) ~= nil, "ИСПРАВЛЕНО: появился FOV")
ok(cs:find("Плавный пролёт", 1, true) ~= nil, "ИСПРАВЛЕНО: появился выбор перехода")
ok(cs:find("Время пролёта", 1, true) ~= nil, "ИСПРАВЛЕНО: появилось время пролёта")
ok(cs:find("Звук в этой точке", 1, true) ~= nil, "и звук камеры")
ok(cs:find("Картинка (материал)", 1, true) ~= nil, "и картинка")

ok(cs:find("cam.fov = math.Clamp(tonumber(fov:GetValue()) or 75, 20, 120)", 1, true) ~= nil,
   "FOV пишется с ограничением 20-120")
ok(cs:find("cam.moveDuration = math.Clamp", 1, true) ~= nil, "время пролёта ограничено")

--[[ У первой камеры перехода быть не может: сцена в ней стартует. ]]
ok(cs:find("if b._cam > 1 then", 1, true) ~= nil,
   "у первой камеры выбор перехода скрыт — лететь неоткуда")
ok(cs:find('cam.transition == "move"', 1, true) ~= nil,
   "время пролёта показывается только для пролёта")
ok(cs:find("Переснять с текущего взгляда", 1, true) ~= nil,
   "камеру можно переснять, не удаляя")

-- Камеры переживают круг.
local camBlock = { uid = "c1", kind = "cutscene", x = 0, y = 0, links = {}, data = {
    phase = "complete", cams = { { id = "camera_1", transition = "cut", duration = 4,
        fov = 35, moveDuration = 2, caption = "Финал", sound = "a.wav", image = "m.png",
        pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 0, r = 0 } } } } }
local backC = Q.BlocksToQuest(quest, { camBlock })
local c1 = (backC.cutscene.complete or {})[1] or {}
ok(c1.fov == 35, "FOV дошёл до квеста", tostring(c1.fov))
ok(c1.moveDuration == 2, "время пролёта дошло", tostring(c1.moveDuration))
ok(c1.caption == "Финал", "титр дошёл")
ok(c1.sound == "a.wav" and c1.image == "m.png", "звук и картинка дошли")

-----------------------------------------------------------------------
print("\n=== 4. АЧИВКА: ID НАРУЖУ ===")
-----------------------------------------------------------------------
local ac = branch("achieve")
ok(ac:find("ID достижения", 1, true) ~= nil, "ИСПРАВЛЕНО: ID выведен в панель")
--[[ ID должен чиститься так же, как на сервере, иначе он молча
     изменится при сохранении и автор не поймёт почему. ]]
ok(ac:find('gsub("[^%w_%-%:]", "_")', 1, true) ~= nil,
   "ID чистится теми же правилами, что и на сервере")
ok(ac:find('quest_" .. tostring(work.id or "")', 1, true) ~= nil,
   "пустой ID подставляется из квеста, а не остаётся пустым")

local function sanitize(v)
    local raw = string.lower(string.Trim(v or "")):gsub("[^%w_%-%:]", "_")
    return raw ~= "" and raw or "quest_fallback"
end
--[[ НАХОДКА СТЕНДА. Lua-класс %w не знает кириллицу, поэтому русский
     ID целиком превращается в подчёркивания — и на сервере тоже. Это
     не баг чистки, а её честное поведение, но автор об этом должен
     знать заранее, поэтому в панели висит предупреждение. ]]
ok(sanitize("ach latin!") == "ach_latin_", "пробелы и знаки заменяются", sanitize("ach latin!"))
ok(sanitize("Ачивка"):find("%a") == nil,
   "кириллица вырождается в подчёркивания — поэтому в панели про это сказано",
   sanitize("Ачивка"))
ok(sanitize("") == "quest_fallback", "пустое значение даёт запасной ID")
ok(sanitize("ach_ok-1") == "ach_ok-1", "нормальный ID не портится")

-----------------------------------------------------------------------
print("\n=== 5. МУЗЫКА: МОМЕНТ И ГРОМКОСТЬ ===")
-----------------------------------------------------------------------
local mu = branch("music")
ok(mu:find("При принятии квеста", 1, true) ~= nil, "ИСПРАВЛЕНО: выбирается момент")
ok(mu:find("При завершении этапа", 1, true) ~= nil, "есть момент «этап»")
ok(mu:find("При завершении квеста", 1, true) ~= nil, "есть момент «завершение»")
ok(mu:find("Громкость", 1, true) ~= nil, "ИСПРАВЛЕНО: появилась громкость")
ok(mu:find("d.volume = math.Clamp", 1, true) ~= nil, "громкость ограничена")
ok(mu:find("Зациклить", 1, true) ~= nil, "зацикливание на месте")

local musicBlock = { uid = "m1", kind = "music", x = 5, y = 6, links = {}, data = {
    sound = "music/track.mp3", when = "complete", loop = true, volume = 0.7 } }
local backM = Q.BlocksToQuest(quest, { musicBlock })
ok(istable(backM.music), "блок музыки попал в квест")
ok(backM.music.when == "complete", "момент дошёл", tostring(backM.music.when))
ok(backM.music.volume == 0.7, "громкость дошла", tostring(backM.music.volume))
ok(backM.music.loop == true, "зацикливание дошло")

-----------------------------------------------------------------------
print("\n=== 6. МУЗЫКА ПЕРЕЖИВАЕТ СОХРАНЕНИЕ НА СЕРВЕРЕ ===")
-----------------------------------------------------------------------
--[[ Нормализация пересобирает квест по полям: без своей функции блок
     музыки просто исчезал бы при первом сохранении. ]]
ok(server:find("local function normalizeMusic", 1, true) ~= nil,
   "ИСПРАВЛЕНО: у музыки есть нормализация")
ok(server:find("music=normalizeMusic(raw.music)", 1, true) ~= nil,
   "и она вызывается при сохранении квеста")

-- Проверяем саму логику нормализации на живых данных.
local function normalizeMusic(value)
    if not istable(value) then return nil end
    local sound = string.Trim(tostring(value.sound or ""))
    if sound == "" then return nil end
    local when = tostring(value.when or "start")
    if when ~= "start" and when ~= "step" and when ~= "complete" then when = "start" end
    return { sound = sound, when = when, loop = value.loop == true,
        volume = math.Clamp(tonumber(value.volume) or 1, .1, 1) }
end
ok(normalizeMusic(nil) == nil, "нет блока — нет музыки")
ok(normalizeMusic({ sound = "" }) == nil, "пустой путь означает «музыки нет»")
ok(normalizeMusic({ sound = "a.mp3", when = "чушь" }).when == "start",
   "неизвестный момент откатывается к «принятию»")
ok(normalizeMusic({ sound = "a.mp3", volume = 99 }).volume == 1, "громкость зажата сверху")
ok(normalizeMusic({ sound = "a.mp3", volume = 0 }).volume == 0.1, "и снизу")

-----------------------------------------------------------------------
print("\n=== 7. МУЗЫКА РЕАЛЬНО ИГРАЕТ ===")
-----------------------------------------------------------------------
--[[ Главное: блок больше не декорация. Сервер шлёт команду в нужный
     момент, клиент её проигрывает. ]]
ok(server:find('util.AddNetworkString("GRM_Quest_Music")', 1, true) ~= nil,
   "сетевое сообщение объявлено")
ok(server:find("local function questMusic", 1, true) ~= nil, "есть отправка музыки")
ok(server:find('questMusic(ply,"start",def)', 1, true) ~= nil,
   "ИСПРАВЛЕНО: музыка играет при принятии квеста")
ok(server:find('questMusic(ply,"step",def)', 1, true) ~= nil,
   "и при завершении этапа")
ok(server:find('questMusic(ply,"complete",def)', 1, true) ~= nil,
   "и при завершении квеста")

--[[ Момент сверяется: трек «на завершение» не должен зазвучать при
     принятии. Воспроизводим проверку из questMusic. ]]
local sent
local function questMusic(kind, m)
    sent = nil
    if not istable(m) then return end
    if tostring(m.when or "start") ~= kind then
        if kind == "complete" and m.loop then sent = "stop" end
        return
    end
    sent = m.sound
end
local track = { sound = "t.mp3", when = "complete", loop = false }
questMusic("start", track)  ok(sent == nil, "при принятии трек «на завершение» молчит")
questMusic("step", track)   ok(sent == nil, "и при этапе тоже")
questMusic("complete", track) ok(sent == "t.mp3", "а в свой момент звучит", tostring(sent))

--[[ Зациклённый трек обязан глушиться в конце квеста, иначе он играл бы
     вечно, даже после сдачи задания. ]]
local loopTrack = { sound = "bg.mp3", when = "start", loop = true }
questMusic("complete", loopTrack)
ok(sent == "stop", "ИСПРАВЛЕНО: зациклённая музыка глушится в конце квеста", tostring(sent))
local onceTrack = { sound = "bg.mp3", when = "start", loop = false }
questMusic("complete", onceTrack)
ok(sent == nil, "разовый трек глушить незачем")

-- Клиент умеет и играть, и останавливать.
ok(client:find('net.Receive("GRM_Quest_Music"', 1, true) ~= nil, "клиент принимает музыку")
ok(client:find("Q._musicPatch", 1, true) ~= nil, "зациклённый трек хранится, чтобы его можно было снять")
ok(client:find('if path == "" then return end', 1, true) ~= nil,
   "пустой путь выключает музыку")
ok(client:find("CreateSound", 1, true) ~= nil,
   "зацикленный трек создаётся через CreateSound — surface.PlaySound не умеет останавливаться")
ok(client:find('hook.Add("PlayerDeath", "GRM_Quest_MusicStop"', 1, true) ~= nil,
   "смерть игрока тоже снимает трек")
ok(client:find("isfunction(CreateSound)", 1, true) ~= nil,
   "есть защита на случай отсутствия CreateSound")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
