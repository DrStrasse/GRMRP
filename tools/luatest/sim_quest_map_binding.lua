--[[ Живой прогон привязки квеста к карте.

     Заказ владельца 29.08: «квесты должны запоминать конкретную карту,
     под которую они создавались».

     ПОЧЕМУ ЭТО ВАЖНО. Зоны этапов и точки камер — это КООРДИНАТЫ. На
     другой карте они указывают в пустоту: игрок получает цель, до
     которой невозможно дойти, а кат-сцена снимает стену.

     ЧТО БЫЛО. Файл определений уже свой у каждой карты, но внутри
     записи карта не хранилась. Квест, перенесённый копированием файла
     или восстановленный из бэкапа, молча оказывался на чужой карте и
     ломался без объяснений.

     ОТДЕЛЬНЫЙ РИСК: прогресс игроков общий на весь сервер, а
     определения раздельные. Активный квест другой карты не должен
     висеть в журнале целью, до которой не добраться, — но и стираться
     не должен: вернулся на ту карту, продолжил с места.

     Запуск: luajit tools/luatest/sim_quest_map_binding.lua ]]

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

--- Текущую карту можно подменять: в этом весь смысл проверок.
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
assert(Q, "GRM.Quests не загрузился")

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local server = readf("lua/autorun/sh_grm_quests.lua")
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")

-----------------------------------------------------------------------
print("\n=== 1. КАРТА ХРАНИТСЯ В САМОМ КВЕСТЕ ===")
-----------------------------------------------------------------------
local def = Q.NormalizeDefinition({
    id = "intro", title = "Введение", map = "RP_Downtown",
    steps = { { type = "event", title = "Копать", event = "mining", count = 1 } },
})
ok(def ~= nil, "квест нормализовался")
ok(def.map == "rp_downtown",
   "ИСПРАВЛЕНО: карта сохраняется в записи и приводится к нижнему регистру",
   tostring(def.map))

--[[ Старые квесты создавались без метки. Они обязаны открываться, а не
     исчезать после обновления. ]]
local legacy = Q.NormalizeDefinition({
    id = "old", title = "Старый",
    steps = { { type = "event", title = "x", event = "e", count = 1 } },
})
ok(legacy.map == "", "квест без метки даёт пустое поле, а не ошибку", tostring(legacy.map))

--[[ Файл определений и так свой у каждой карты — это должно остаться:
     метка внутри записи его дополняет, а не заменяет. ]]
ok(server:find('Q.DefFile = Q.DataDir .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json"', 1, true) ~= nil,
   "файл определений по-прежнему разделён по картам")

-----------------------------------------------------------------------
print("\n=== 2. ПРОВЕРКА СООТВЕТСТВИЯ КАРТЕ ===")
-----------------------------------------------------------------------
ok(isfunction(Q.FitsMap), "появилась проверка соответствия карте")

CURRENT_MAP = "rp_city"
ok(Q.FitsMap({ map = "rp_city" }) == true, "квест своей карты подходит")
ok(Q.FitsMap({ map = "rp_downtown" }) == false, "квест чужой карты не подходит")
ok(Q.FitsMap({ map = "" }) == true,
   "квест без метки подходит везде — иначе старые перестали бы выдаваться")
ok(Q.FitsMap({}) == true, "отсутствующее поле = без метки")
ok(Q.FitsMap(nil) == false, "nil не роняет проверку")

-- Регистр не должен мешать: карты пишут по-разному.
ok(Q.FitsMap({ map = "RP_CITY" }) == true, "регистр не важен")

-- Смена карты меняет результат.
CURRENT_MAP = "rp_downtown"
ok(Q.FitsMap({ map = "rp_city" }) == false, "после смены карты прежний квест уже не подходит")
ok(Q.FitsMap({ map = "rp_downtown" }) == true, "а квест новой карты подходит")
CURRENT_MAP = "rp_city"

-----------------------------------------------------------------------
print("\n=== 3. ЧУЖОЙ КВЕСТ НЕ ЗАПУСКАЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Главное последствие: игрок берёт квест, получает цель «дойти до
     точки», а точки на этой карте нет. Пройти невозможно. ]]
local canStartFn = server:match("local function canStart%(ply,def%).-\n    end") or ""
ok(canStartFn ~= "", "функция проверки старта найдена")
ok(canStartFn:find("Q.FitsMap(def)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: старт квеста проверяет карту")
ok(canStartFn:find("и здесь не работает", 1, true) ~= nil,
   "и объясняет игроку причину, а не молчит")

--[[ Порядок важен: проверка карты должна идти ДО записи прогресса,
     иначе квест «начнётся» и застрянет. ]]
local mapPos = canStartFn:find("Q.FitsMap", 1, true)
local progPos = canStartFn:find("progressFor(ply)", 1, true)
ok(mapPos and progPos and mapPos < progPos,
   "карта проверяется раньше, чем трогается прогресс")

-- Автостарт тоже обязан уважать карту.
ok(server:find("if def.autoStart and not def.draft and Q.FitsMap(def) then", 1, true) ~= nil,
   "ИСПРАВЛЕНО: автостартовый квест чужой карты не выдаётся при входе")

-----------------------------------------------------------------------
print("\n=== 4. ПРОГРЕСС НЕ ТЕРЯЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Прогресс общий на весь сервер. Квест чужой карты не показываем, но
     и не стираем: вернулся игрок на ту карту — продолжает с места. ]]
local syncFn = server:match("sync=function%(ply%).-\n    end") or ""
ok(syncFn ~= "", "функция синхронизации найдена")
ok(syncFn:find("Q.FitsMap(d)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: в журнал попадают только квесты текущей карты")
ok(syncFn:find("Q.Progress[", 1, true) == nil and syncFn:find("=nil", 1, true) == nil,
   "прогресс при этом не стирается")

--[[ Моделируем: игрок начал квест на одной карте, зашёл на другую,
     вернулся. Прогресс обязан пережить обе смены. ]]
local progress = { intro = { status = "active", step = 2 } }
local defsCity = { intro = { id = "intro", map = "rp_city" } }
local defsTown = { other = { id = "other", map = "rp_downtown" } }

local function visibleOn(mapName, defs)
    CURRENT_MAP = mapName
    local out = {}
    for id, p in pairs(progress) do
        local d = defs[id]
        if d and Q.FitsMap(d) then out[#out + 1] = id end
    end
    return out
end
ok(#visibleOn("rp_city", defsCity) == 1, "на своей карте квест виден")
ok(#visibleOn("rp_downtown", defsTown) == 0, "на другой карте не виден")
ok(progress.intro ~= nil and progress.intro.step == 2,
   "и прогресс при этом цел — этап не сбросился", progress.intro.step)
ok(#visibleOn("rp_city", defsCity) == 1, "вернулись — квест снова в журнале")
CURRENT_MAP = "rp_city"

-- События чужого квеста не должны двигать его прогресс.
ok(server:find('and Q.FitsMap(def) and p.status=="active"', 1, true) ~= nil,
   "события не продвигают квест чужой карты")

-----------------------------------------------------------------------
print("\n=== 5. МЕТКА ПРОСТАВЛЯЕТСЯ ПРИ СОХРАНЕНИИ ===")
-----------------------------------------------------------------------
--[[ Метку ставим при сохранении, а не только при создании: так её
     получат и старые квесты, которые просто открыли и пересохранили. ]]
ok(server:find('if tostring(def.map or "")=="" then def.map=string.lower(game.GetMap() or "") end', 1, true) ~= nil,
   "ИСПРАВЛЕНО: квест без метки получает текущую карту при сохранении")

local function stampOnSave(d, mapName)
    if tostring(d.map or "") == "" then d.map = string.lower(mapName) end
    return d
end
ok(stampOnSave({ id = "a" }, "rp_city").map == "rp_city", "пустая метка заполняется")
ok(stampOnSave({ id = "b", map = "rp_old" }, "rp_city").map == "rp_old",
   "заданная метка НЕ перетирается — иначе перенос квеста ломался бы молча")

-- Новый квест в редакторе создаётся сразу с картой.
ok(studio:find('map = string.lower(game.GetMap() or ""),', 1, true) ~= nil,
   "новый квест в студии сразу помечается текущей картой")

-----------------------------------------------------------------------
print("\n=== 6. ВАЛИДАТОР ПРЕДУПРЕЖДАЕТ ===")
-----------------------------------------------------------------------
CURRENT_MAP = "rp_city"
local alien = {
    id = "q", title = "Чужой", npc = "guide", map = "rp_downtown",
    steps = { { type = "event", event = "mining", count = 1, title = "x" } },
    rewards = { money = 10, items = {} },
    dialogue = { offer = { { id = "o1", text = "hi", choices = {
        { text = "ok", action = "accept" } } } }, active = {}, complete = {} },
}
local found = false
for _, it in ipairs(Q.Validate(alien)) do
    if it.level == "error" and tostring(it.text):find("создан для карты", 1, true) then found = true end
end
ok(found, "ИСПРАВЛЕНО: проверка квеста ловит чужую карту как ошибку")

alien.map = "rp_city"
local stillFound = false
for _, it in ipairs(Q.Validate(alien)) do
    if tostring(it.text):find("создан для карты", 1, true) then stillFound = true end
end
ok(not stillFound, "на своей карте ошибки нет")

alien.map = ""
local legacyErr = false
for _, it in ipairs(Q.Validate(alien)) do
    if tostring(it.text):find("создан для карты", 1, true) then legacyErr = true end
end
ok(not legacyErr, "квест без метки не считается сломанным")

-----------------------------------------------------------------------
print("\n=== 7. КАРТА ВИДНА В РЕДАКТОРЕ ===")
-----------------------------------------------------------------------
ok(studio:find('"Карта: " .. questMap', 1, true) ~= nil,
   "ИСПРАВЛЕНО: карта квеста показана в панели")
ok(studio:find("Карта не задана", 1, true) ~= nil,
   "и видно, когда метки нет")
ok(studio:find("вы на ", 1, true) ~= nil,
   "при несовпадении сказано, где вы находитесь")
ok(studio:find("mismatch and COL.red", 1, true) ~= nil,
   "чужая карта подсвечена красным")
ok(studio:find("ДРУГАЯ КАРТА · ", 1, true) ~= nil,
   "и помечена прямо в списке квестов — видно до открытия")

-- Логика подсветки.
local function isAlien(questMap, here)
    return questMap ~= "" and questMap ~= here
end
ok(isAlien("rp_downtown", "rp_city") == true, "чужая карта опознаётся")
ok(isAlien("rp_city", "rp_city") == false, "своя — нет")
ok(isAlien("", "rp_city") == false, "без метки тревоги нет")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
