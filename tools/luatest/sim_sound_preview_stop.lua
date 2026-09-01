--[[ Живой прогон остановки прослушивания звуков.

     Жалоба владельца 29.08: «нажимаю на звук, он проигрывает, нажимаю
     на следующий — он запускает следующий, но предыдущий не
     останавливает».

     ПРИЧИНА. surface.PlaySound выстреливает звук и забывает о нём:
     объекта нет, останавливать нечем. Перебирая список из десятка
     треков, человек получал какофонию из всех сразу.

     РЕШЕНИЕ. CreateSound возвращает объект с методом Stop. Держим
     ссылку на текущий трек и снимаем его перед запуском следующего.

     ОТДЕЛЬНЫЕ РИСКИ, которые тут проверяются:
       • закрыли окно — звук обязан замолчать, иначе остановить его уже
         нечем: окна нет;
       • выбрали звук — превью глушится, дальше он нужен в сцене;
       • та же болезнь была у кнопок «Прослушать» в самой студии.

     Запуск: luajit tools/luatest/sim_sound_preview_stop.lua ]]

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
function string.GetExtensionFromFilename(f) return string.match(tostring(f or ""), "%.([%w]+)$") end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--[[ Поддельный движок звука: считаем, что играет и что остановлено.
     Так проверяем ПОВЕДЕНИЕ, а не наличие строчки в файле. ]]
--[[ Таблицы НЕ пересоздаём, а чистим на месте: patch:Stop() держит
     ссылку на ту таблицу, что была в момент создания звука. Присваивание
     новой таблицы рвало связь, и остановки уходили в старую — из-за
     этого стенд насчитал 10 остановок вместо 9 и соврал. ]]
local PLAYING, STOPPED, FIRE_AND_FORGET = {}, {}, 0
local function resetSound()
    --[[ Сначала глушим то, что осталось от прошлого блока проверок:
         иначе первый же Play снимет старый трек и добавит лишнюю
         запись в STOPPED — стенд насчитает на одну остановку больше и
         соврёт о поведении кода. ]]
    if GRM.SoundBrowser and GRM.SoundBrowser.Stop then GRM.SoundBrowser.Stop() end
    for k in pairs(PLAYING) do PLAYING[k] = nil end
    for i = #STOPPED, 1, -1 do STOPPED[i] = nil end
end
local function mkPatch(path)
    local patch = { _path = path, _alive = true }
    function patch:SetSoundLevel() end
    function patch:PlayEx() PLAYING[self._path] = true end
    function patch:Stop()
        PLAYING[self._path] = nil
        STOPPED[#STOPPED + 1] = self._path
        self._alive = false
    end
    return patch
end
function CreateSound(ent, path) return mkPatch(path) end

surface = {
    CreateFont = function() end,
    -- Именно этим и был баг: звук уходит в никуда, остановить нельзя.
    PlaySound = function() FIRE_AND_FORGET = FIRE_AND_FORGET + 1 end,
    SetDrawColor = function() end, DrawRect = function() end,
}
draw = { RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end }
vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end }
concommand = { Add = function() end }
notification = { AddLegacy = function() end }
file = { Find = function() return {}, {} end }
function LocalPlayer() return { _valid = true } end
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
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

local function playingCount()
    local n = 0
    for _ in pairs(PLAYING) do n = n + 1 end
    return n
end

-----------------------------------------------------------------------
print("\n=== 1. БАГ ВОСПРОИЗВЕДЁН: PlaySound НЕ ОСТАНОВИТЬ ===")
-----------------------------------------------------------------------
FIRE_AND_FORGET = 0
surface.PlaySound("a.wav")
surface.PlaySound("b.wav")
ok(FIRE_AND_FORGET == 2, "старый способ запускает звуки один за другим", FIRE_AND_FORGET)
ok(#STOPPED == 0, "БАГ: остановить их нечем — объекта не остаётся")

ok(browser:find("surface.PlaySound(path)", 1, true) ~= nil,
   "запасной путь через PlaySound сохранён на случай отсутствия CreateSound")

-----------------------------------------------------------------------
print("\n=== 2. НОВЫЙ ЗВУК ГЛУШИТ ПРЕДЫДУЩИЙ ===")
-----------------------------------------------------------------------
ok(isfunction(SB.Play), "появился общий проигрыватель")
ok(isfunction(SB.Stop), "и остановка")

resetSound()
SB.Play("music/first.mp3")
ok(playingCount() == 1, "первый трек играет", playingCount())
ok(PLAYING["music/first.mp3"], "именно тот, что запросили")

SB.Play("music/second.mp3")
ok(playingCount() == 1,
   "ИСПРАВЛЕНО: играет ровно один трек, а не оба сразу", playingCount())
ok(PLAYING["music/second.mp3"], "играет новый")
ok(not PLAYING["music/first.mp3"], "старый остановлен")
ok(STOPPED[1] == "music/first.mp3", "и остановлен именно он", STOPPED[1])

--[[ Перебор списка — ровно то, что делал владелец. После десяти
     нажатий должен звучать один трек, а не десять. ]]
resetSound()
for i = 1, 10 do SB.Play("track" .. i .. ".wav") end
ok(playingCount() == 1, "после десяти нажатий играет один звук", playingCount())
ok(PLAYING["track10.wav"], "последний из нажатых")
ok(#STOPPED == 9, "остальные девять остановлены", #STOPPED)

-----------------------------------------------------------------------
print("\n=== 3. ОСТАНОВКА БЕЗОПАСНА ===")
-----------------------------------------------------------------------
resetSound()
SB.Stop()
ok(true, "остановка без играющего звука не роняет клиент")

SB.Play("x.wav")
SB.Stop()
ok(playingCount() == 0, "звук остановлен", playingCount())
SB.Stop()
ok(playingCount() == 0, "повторная остановка безопасна")

FIRE_AND_FORGET = 0
SB.Play("")
ok(playingCount() == 0 and FIRE_AND_FORGET == 0, "пустой путь ничего не запускает")
SB.Play(nil)
ok(playingCount() == 0, "nil тоже")

--[[ Путь с ведущей папкой движок не находит: чистим, иначе игрок
     слышит тишину и думает, что звук сломан. ]]
PLAYING = {}
SB.Play("sound/music/theme.mp3")
ok(PLAYING["music/theme.mp3"], "ведущее sound/ срезается")
ok(not PLAYING["sound/music/theme.mp3"], "и не остаётся в пути")

-----------------------------------------------------------------------
print("\n=== 4. ЗАКРЫТИЕ ОКНА ГЛУШИТ ЗВУК ===")
-----------------------------------------------------------------------
--[[ Самое неприятное: закрыл браузер, а трек играет. Остановить его
     уже нечем — окна нет. ]]
ok(browser:find("f.OnClose = function() SB.Stop() end", 1, true) ~= nil,
   "ИСПРАВЛЕНО: закрытие окна останавливает звук")
ok(browser:find("f.OnRemove = function() SB.Stop() end", 1, true) ~= nil,
   "и удаление панели тоже — окно могут снять сторожем окон")

-- Моделируем закрытие.
PLAYING = {}
SB.Play("long.mp3")
ok(playingCount() == 1, "трек играет перед закрытием")
SB.Stop()   -- то, что делает OnClose
ok(playingCount() == 0, "после закрытия тишина")

ok(browser:find('mkBtn(f, "■ Стоп", COL.card)', 1, true) ~= nil,
   "есть кнопка «Стоп» — трек можно оборвать, не закрывая окно")

--[[ Выбор звука тоже глушит превью: дальше он нужен в сцене, а не в
     ушах у автора. ]]
local applyFn = browser:match("apply%.DoClick = function%(%).-\n    end") or ""
ok(applyFn ~= "", "обработчик выбора найден")
ok(applyFn:find("SB.Stop()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: выбор звука останавливает прослушивание")

-- Порядок важен: сначала глушим, потом отдаём результат и закрываем.
local stopPos = applyFn:find("SB.Stop()", 1, true)
local pickPos = applyFn:find("onPick(selected)", 1, true)
ok(stopPos and pickPos and stopPos < pickPos,
   "остановка идёт до передачи результата")

-----------------------------------------------------------------------
print("\n=== 5. КЛИКИ В СПИСКЕ ИСПОЛЬЗУЮТ ОБЩИЙ ПРОИГРЫВАТЕЛЬ ===")
-----------------------------------------------------------------------
local rowClick = browser:match("row%.DoClick = function%(%).-\n            end") or ""
ok(rowClick ~= "", "обработчик клика по строке найден")
ok(rowClick:find("SB.Play(path)", 1, true) ~= nil,
   "клик проигрывает через общий проигрыватель")
ok(rowClick:find("surface.PlaySound", 1, true) == nil,
   "БАГ УБРАН: прямой вызов PlaySound из списка удалён")

local playBtn = browser:match("play%.DoClick = function%(%).-\n    end") or ""
ok(playBtn:find("SB.Play(selected)", 1, true) ~= nil,
   "кнопка «Прослушать» тоже через него")
ok(playBtn:find("surface.PlaySound", 1, true) == nil,
   "и без прямого вызова")

-----------------------------------------------------------------------
print("\n=== 6. ТА ЖЕ БОЛЕЗНЬ В СТУДИИ ИСПРАВЛЕНА ===")
-----------------------------------------------------------------------
--[[ Кнопки «Прослушать» у камеры и у блока музыки страдали тем же:
     повторные нажатия наслаивали звуки. ]]
ok(studio:find("GRM.SoundBrowser.Play(path)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: студия проигрывает через браузер")
local calls = select(2, studio:gsub("GRM%.SoundBrowser%.Play%(path%)", ""))
ok(calls >= 2, "обе кнопки прослушивания переведены", calls)

ok(studio:find("GRM.SoundBrowser and GRM.SoundBrowser.Play", 1, true) ~= nil,
   "есть защита, если браузер не загружен")
--[[ Запасной путь должен остаться: без браузера лучше проиграть
     звук без остановки, чем не проиграть вовсе. ]]
ok(studio:find("surface.PlaySound(path)", 1, true) ~= nil,
   "запасной вариант сохранён")

-----------------------------------------------------------------------
print("\n=== 7. НАСТРОЙКИ ЗВУКА РАЗУМНЫ ===")
-----------------------------------------------------------------------
local playFn = browser:match("function SB%.Play%(path%).-\nend") or ""
ok(playFn ~= "", "функция проигрывания найдена")
ok(playFn:find("SetSoundLevel(0)", 1, true) ~= nil,
   "звук не затухает с расстоянием — длинный трек не стихнет, если отойти")
ok(playFn:find("SB.Stop()", 1, true) ~= nil,
   "предыдущий трек снимается в самом начале")
ok(playFn:find("pcall(CreateSound", 1, true) ~= nil,
   "создание обёрнуто в pcall — битый путь не роняет студию")
ok(playFn:find("isfunction(CreateSound)", 1, true) ~= nil,
   "и есть проверка доступности CreateSound")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
