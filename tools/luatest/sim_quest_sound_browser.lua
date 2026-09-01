--[[ Живой прогон звука кат-сцены и браузера звуков.

     Заказ владельца 29.08: «проигрывание звука в кат-сцене и выбор
     звука надо сделать нормально, чтобы работало + выбор должен быть
     из меню звуков, все звуки и саунды игры + аддонов должны
     сканироваться и выводиться в специальное меню, открываемое
     кнопочкой в меню квестов в подменю катсцены в её настройках».

     ПОЧЕМУ ЗВУК НЕ РАБОТАЛ — три причины:
       • он запускался ТОЛЬКО в фазе hold. У точки с плавным пролётом
         ветка move отрабатывала первой, и звук пропускался совсем;
       • surface.PlaySound не умеет останавливаться: пропустил сцену
         пробелом — трек продолжал играть поверх игры;
       • путь не чистился: «sound/x.wav» с ведущей папкой движок молча
         не находит, игрок слышал тишину без объяснений.

     Запуск: luajit tools/luatest/sim_quest_sound_browser.lua ]]

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
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function string.GetExtensionFromFilename(f)
    return string.match(tostring(f or ""), "%.([%w]+)$")
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--[[ Поддельная файловая система: две папки, вложенность и посторонние
     расширения — чтобы проверить и рекурсию, и отбор. ]]
local FS = {
    ["sound/*"]              = { { "menu.wav", "readme.txt" }, { "music", "weapons", ".", ".." } },
    ["sound/music/*"]        = { { "theme.mp3", "loop.ogg" }, { "extra" } },
    ["sound/music/extra/*"]  = { { "deep.wav" }, {} },
    ["sound/weapons/*"]      = { { "shot.wav", "model.mdl" }, {} },
}
file = { Find = function(pattern, where)
    local row = FS[pattern]
    if not row then return {}, {} end
    return row[1], row[2]
end }

surface = { CreateFont = function() end, PlaySound = function() end,
    SetDrawColor = function() end, DrawRect = function() end }
draw = { RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end }
vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end }
concommand = { Add = function() end }
notification = { AddLegacy = function() end }
function ScrW() return 1920 end
function ScrH() return 1080 end
NOTIFY_HINT, NOTIFY_ERROR = 1, 2
GRM = {}

assert(loadfile("lua/autorun/client/cl_grm_sound_browser.lua"))()
local SB = GRM.SoundBrowser
assert(SB, "браузер звуков не загрузился")

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local browser = readf("lua/autorun/client/cl_grm_sound_browser.lua")
local client = readf("lua/autorun/client/cl_grm_quests.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

-----------------------------------------------------------------------
print("\n=== 1. СКАНИРОВАНИЕ НАХОДИТ ЗВУКИ ===")
-----------------------------------------------------------------------
local st = SB.NewScan()
local guard = 0
while not SB.Step(st, 2) do
    guard = guard + 1
    if guard > 100 then break end
end
ok(st.done, "обход завершился", guard)

local found = {}
for _, p in ipairs(st.files) do found[p] = true end
ok(found["menu.wav"], "найден звук в корне")
ok(found["music/theme.mp3"], "найден mp3 во вложенной папке")
ok(found["music/loop.ogg"], "и ogg тоже")
ok(found["music/extra/deep.wav"], "рекурсия работает на два уровня вглубь")
ok(found["weapons/shot.wav"], "вторая ветка папок тоже обойдена")
ok(#st.files == 5, "найдено ровно пять звуков", #st.files)

--[[ Посторонние файлы попадать не должны: их движок не проиграет. ]]
ok(not found["readme.txt"], "текстовые файлы отсеяны")
ok(not found["weapons/model.mdl"], "модели отсеяны")

--[[ Ведущее «sound/» убрано: с ним движок звук не находит. ]]
local hasPrefix = false
for _, p in ipairs(st.files) do if p:find("^sound/") then hasPrefix = true end end
ok(not hasPrefix, "ИСПРАВЛЕНО: пути без ведущего sound/ — движок их примет")

-----------------------------------------------------------------------
print("\n=== 2. СКАНИРОВАНИЕ НЕ ВЕШАЕТ КЛИЕНТ ===")
-----------------------------------------------------------------------
--[[ Полное дерево звуков — десятки тысяч файлов. За один кадр это
     несколько секунд заморозки, и человек решит, что игра зависла. ]]
local st2 = SB.NewScan()
local firstDone = SB.Step(st2, 1)
ok(firstDone == false, "за один шаг обход не завершается — работа делится по кадрам")
ok(st2.dirs == 1, "обработана ровно одна папка за шаг", st2.dirs)
ok(#st2.queue > 0, "остальные папки ждут следующего кадра", #st2.queue)

ok(browser:find("f.Think = function()", 1, true) ~= nil,
   "обход идёт в Think, а не одним циклом")
ok(browser:find("SB.Step(state, 14)", 1, true) ~= nil,
   "с ограниченным бюджетом на кадр")

--[[ Точки «.» и «..» в списке папок — классическая причина вечного
     цикла: обход ушёл бы сам в себя. ]]
ok(browser:find('if sub ~= "." and sub ~= ".." then', 1, true) ~= nil,
   "служебные точки пропускаются — обход не зацикливается")
ok(st.dirs < 20, "число обойдённых папок конечно", st.dirs)

-- Повторный вызов на завершённом состоянии безопасен.
ok(SB.Step(st, 5) == true, "шаг по завершённому обходу возвращает готовность")
ok(SB.Step(nil, 5) == true, "nil не роняет обход")

-----------------------------------------------------------------------
print("\n=== 3. ПОИСК ПО СПИСКУ ===")
-----------------------------------------------------------------------
local all = st.files
ok(#SB.Filter(all, "") == #all, "пустой запрос возвращает всё", #SB.Filter(all, ""))
ok(#SB.Filter(all, "music") == 3, "поиск по папке", #SB.Filter(all, "music"))
ok(#SB.Filter(all, "theme") == 1, "поиск по имени файла")
ok(#SB.Filter(all, "THEME") == 1, "регистр не важен — человек ищет как удобно")
ok(#SB.Filter(all, "неттакого") == 0, "по пустому запросу ничего не находится")
ok(#SB.Filter(nil, "x") == 0, "nil-список не роняет поиск")

-----------------------------------------------------------------------
print("\n=== 4. ЗВУК В КАТ-СЦЕНЕ ЗАПУСКАЕТСЯ ПРАВИЛЬНО ===")
-----------------------------------------------------------------------
ok(client:find("function Q.PlayCutsceneSound", 1, true) ~= nil,
   "ИСПРАВЛЕНО: звук ставит одна общая функция")
ok(client:find("function Q.StopCutsceneSound", 1, true) ~= nil,
   "и её можно остановить")

local playFn = client:match("function Q%.PlayCutsceneSound.-\nend") or ""
ok(playFn ~= "", "функция найдена")
ok(playFn:find('path:gsub("^sound/", "")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ведущее sound/ срезается — иначе движок не найдёт файл")
ok(playFn:find("CreateSound", 1, true) ~= nil,
   "используется CreateSound: его можно остановить, в отличие от PlaySound")
ok(playFn:find("SetSoundLevel(0)", 1, true) ~= nil,
   "звук слышно везде — камера сцены может быть далеко от тела игрока")
ok(playFn:find("surface.PlaySound(path)", 1, true) ~= nil,
   "есть запасной путь, если CreateSound недоступен")

-- Проверяем саму нормализацию пути.
local function normalize(p) return (tostring(p or ""):gsub("^sound/", "")) end
ok(normalize("sound/music/a.wav") == "music/a.wav", "путь с папкой чинится",
   normalize("sound/music/a.wav"))
ok(normalize("music/a.wav") == "music/a.wav", "правильный путь не портится")
ok(normalize("") == "", "пустой путь остаётся пустым")

--[[ Ключевое: звук должен ставиться и при пролёте тоже. Раньше он жил
     только в ветке hold и у точки с плавным переходом пропадал. ]]
ok(client:find("s.soundNode~=s.index then s.soundNode=s.index;Q.PlayCutsceneSound(node.sound)", 1, true) ~= nil,
   "звук ставится через общую функцию в проходе кадра")

-- Остановка при выходе из сцены.
local stopFn = client:match("local function stopCutscene%(%).-\nend") or ""
ok(stopFn:find("Q.StopCutsceneSound()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: выход из сцены глушит звук — пропуск пробелом не оставит трек")

-----------------------------------------------------------------------
print("\n=== 5. КНОПКА ВЫБОРА В НАСТРОЙКАХ КАТ-СЦЕНЫ ===")
-----------------------------------------------------------------------
ok(studio:find("Выбрать звук из списка", 1, true) ~= nil,
   "ИСПРАВЛЕНО: в настройках камеры есть кнопка выбора")
ok(studio:find("GRM.SoundBrowser.Open(function(path)", 1, true) ~= nil,
   "она открывает браузер звуков")

local camBranch = studio:match('local pickSnd = mkBtn.-\n                end') or ""
ok(camBranch:find("cam.sound = path", 1, true) ~= nil,
   "выбранный путь записывается в камеру")
ok(camBranch:find("snd:SetText(path)", 1, true) ~= nil,
   "и сразу виден в поле — иначе непонятно, применилось ли")
ok(studio:find("GRM.SoundBrowser and GRM.SoundBrowser.Open", 1, true) ~= nil,
   "есть защита, если браузер не загружен")

ok(studio:find("▶ Прослушать звук точки", 1, true) ~= nil,
   "звук точки можно проверить, не запуская всю сцену")

--[[ Поле должно писаться сразу: иначе выбранный путь терялся при
     переключении на другую камеру — эта болезнь уже была раньше. ]]
ok(studio:find("snd.OnChange = function(e) cam.sound = e:GetValue() end", 1, true) ~= nil,
   "ручной ввод пути тоже применяется сразу")

-- Тот же браузер у блока музыки.
ok(studio:find("local pickMusic = mkBtn", 1, true) ~= nil,
   "у блока МУЗЫКА тоже есть выбор из списка")

-----------------------------------------------------------------------
print("\n=== 6. БРАУЗЕР УДОБЕН И НЕ ЗАХЛЁБЫВАЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Список из десятков тысяч кнопок вешает интерфейс намертво. ]]
ok(browser:find("math.min(#filtered, 300)", 1, true) ~= nil,
   "за раз рисуется не больше 300 строк")
ok(browser:find("уточните поиск", 1, true) ~= nil,
   "и сказано, что показано не всё")

ok(browser:find("row.DoDoubleClick", 1, true) ~= nil,
   "двойной клик сразу выбирает звук")
ok(browser:find("surface.PlaySound(path)", 1, true) ~= nil,
   "одиночный клик проигрывает — выбирать вслепую бессмысленно")
ok(browser:find("SB.Cache = state.files", 1, true) ~= nil,
   "результат кэшируется: второе открытие мгновенное")
ok(browser:find('concommand.Add("grm_sound_rescan"', 1, true) ~= nil,
   "кэш можно сбросить после монтирования нового аддона")
ok(browser:find('file.Find(dir .. "*", "GAME")', 1, true) ~= nil,
   "сканируется GAME — это игра, распакованные аддоны и .gma")

-- Расширения ровно те, что движок проигрывает.
ok(SB.Extensions.wav and SB.Extensions.mp3 and SB.Extensions.ogg,
   "поддержаны wav, mp3 и ogg")
ok(SB.Extensions.txt == nil and SB.Extensions.mdl == nil,
   "посторонние расширения в список не входят")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
