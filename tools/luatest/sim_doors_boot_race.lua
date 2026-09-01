--[[--------------------------------------------------------------------
    sim_doors_boot_race — гонка на старте: ключи не работали первые
    секунды после перезапуска сервера.

    ЖАЛОБА ВЛАДЕЛЬЦА (31.08): «после перезапуска было несколько
    минут/секунд, что ключи дверные по дверям не срабатывали».
    Потом всё начинало работать само.

    ПРИЧИНА. База владельцев дверей грузится НЕ мгновенно: задача
    "doors.db" стоит в очереди планировщика GRM.Boot, а тот выполняет
    задачи порциями по 2 мс на тик, чтобы не ронять tickrate на старте.
    До её выполнения таблица D.Data.doors пуста.

    И вот главное: ПУСТАЯ БАЗА НЕОТЛИЧИМА ОТ «ДВЕРЬ НИЧЬЯ». getRecord
    не находил запись и заводил новую, со свежими правами и
    owner_type = "none". Владелец собственной двери на эти секунды
    становился посторонним: ключи отвечали отказом либо молча ничего
    не делали. Как только планировщик доходил до задачи — всё
    «чинилось само», поэтому баг и выглядел плавающим.

    ЧТО ПРОВЕРЯЕМ. Стенд поднимает НАСТОЯЩИЙ планировщик GRM.Boot из
    репозитория и воспроизводит порядок событий на старте карты.

    Запуск: luajit tools/luatest/sim_doors_boot_race.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Мок ровно под планировщик загрузки.
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function IsValid(v) return istable(v) and v._valid ~= false end
function ErrorNoHalt() end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1
local CVARS = {}
function CreateConVar(n, d)
    CVARS[n] = tostring(d)
    return {
        GetBool = function() return tonumber(CVARS[n]) ~= 0 end,
        GetInt = function() return math.floor(tonumber(CVARS[n]) or 0) end,
        GetFloat = function() return tonumber(CVARS[n]) or 0 end,
    }
end
function GetConVar(n) return CVARS[n] and CreateConVar(n, CVARS[n]) or nil end

local HOOKS = {}
hook = {
    Add = function(e, n, f) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = f end,
    Remove = function(e, n) if HOOKS[e] then HOOKS[e][n] = nil end end,
    Run = function() end, Call = function() end,
    GetTable = function() return HOOKS end,
}
timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end }
concommand = { Add = function() end }
function SysTime() return 0 end
function CurTime() return 0 end
function RealTime() return 0 end
function print_() end
util = { AddNetworkString = function() end }
net = setmetatable({}, { __index = function() return function() end end })
player = { GetAll = function() return {} end }
GRM = {}

assert(loadfile("lua/autorun/sh_00_grm_boot.lua"))()
local B = GRM.Boot
assert(B, "планировщик загрузки не поднялся")

-----------------------------------------------------------------------
print("\n=== 1. ПЛАНИРОВЩИК ДЕЙСТВИТЕЛЬНО ОТКЛАДЫВАЕТ ЗАГРУЗКУ ===")
-----------------------------------------------------------------------
do
    --[[ Это не выдумка стенда: задача early ждёт своей очереди, а не
         выполняется в момент регистрации. Именно этот зазор и ловил
         владелец после рестарта. ]]
    local ran = false
    B.Task("test.db", "early", function() ran = true end)
    ok(not ran, "БАГ ВОСПРОИЗВЕДЁН: задача early НЕ выполнена сразу при регистрации")
    ok(B.Done("test.db") == false, "и планировщик честно считает её невыполненной")

    B.Ensure("test.db")
    ok(ran, "Ensure выполняет задачу немедленно, вне очереди")
    ok(B.Done("test.db") == true, "после Ensure задача отмечена выполненной")

    -- Повторный Ensure не должен выполнять её второй раз.
    local count = 0
    B.Task("test.once", "early", function() count = count + 1 end)
    B.Ensure("test.once")
    B.Ensure("test.once")
    ok(count == 1, "повторный Ensure не выполняет задачу заново", count)
end

-----------------------------------------------------------------------
print("\n=== 2. ВОСПРОИЗВЕДЕНИЕ БАГА НА МОДЕЛИ ДВЕРЕЙ ===")
-----------------------------------------------------------------------
--[[ Собираем ту же связку, что в модуле: база грузится задачей, а
     getRecord обращается к ней. Сначала БЕЗ фикса — видим, что
     владелец теряет права. ]]
local function makeDoorsModel(withFix)
    local M = { Data = { doors = {} }, loaded = false }

    B.Tasks["doors.db"] = nil          -- чистая регистрация на каждый прогон
    B.Task("doors.db", "early", function()
        -- «Читаем с диска» сохранённую дверь владельца.
        M.Data.doors["map_m10"] = { id = "map_m10", owner_type = "player",
                                    owner_key = "STEAM_OWNER", locked = true }
        M.loaded = true
    end)

    function M.GetRecord(id, fix)
        if fix then
            if not B.Done("doors.db") then B.Ensure("doors.db", "запрос прав") end
        end
        local rec = M.Data.doors[id]
        if rec then return rec end
        -- Записи нет — заводим «ничью». Здесь и терялся владелец.
        local fresh = { id = id, owner_type = "none", locked = false }
        M.Data.doors[id] = fresh
        return fresh
    end

    return M
end

do
    -- БЕЗ фикса: игрок дёргает дверь до того, как планировщик дошёл до базы.
    local M = makeDoorsModel()
    local rec = M.GetRecord("map_m10", false)
    ok(rec.owner_type == "none",
        "БАГ ВОСПРОИЗВЕДЁН: до загрузки базы своя дверь считается НИЧЬЕЙ",
        rec.owner_type)

    local isOwner = rec.owner_type == "player" and rec.owner_key == "STEAM_OWNER"
    ok(not isOwner, "владелец не опознан — ключи ответят отказом")
end

do
    -- С фиксом: тот же момент времени, но права запрашиваются корректно.
    local M = makeDoorsModel()
    local rec = M.GetRecord("map_m10", true)
    ok(rec.owner_type == "player",
        "ИСПРАВЛЕНО: запрос прав дожидается базы и находит запись",
        rec.owner_type)
    ok(rec.owner_key == "STEAM_OWNER", "владелец на месте")
    ok(rec.locked == true, "состояние замка тоже восстановлено из базы")
end

do
    --[[ Ложная запись не должна оставаться в таблице: если её создать
         до загрузки, настоящая потом не подхватится, и дверь останется
         ничьей НАВСЕГДА — до ручной правки файла. Это худший исход. ]]
    local M = makeDoorsModel()
    M.GetRecord("map_m10", false)      -- создали «ничью» запись
    B.Ensure("doors.db")               -- база загрузилась позже
    local rec = M.Data.doors["map_m10"]
    ok(rec.owner_type == "player",
        "загрузка базы перезаписывает ложную запись, а не наоборот",
        rec.owner_type)
end

-----------------------------------------------------------------------
print("\n=== 3. ФИКС В БОЕВОМ МОДУЛЕ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_doors.lua")

    ok(src:find("local function ensureDoorsDB", 1, true) ~= nil,
        "появилась проверка готовности базы")
    ok(src:find('GRM.Boot.Ensure("doors.db"', 1, true) ~= nil,
        "она поднимает задачу базы по требованию")

    --[[ Проверяем, что вызов стоит ВНУТРИ getRecord: это единственная
         точка, через которую все права на дверь и проходят. ]]
    local gr = src:match("local function getRecord%(ent%).-\n    end")
    ok(gr ~= nil, "функция getRecord найдена")
    ok(gr and gr:find("ensureDoorsDB()", 1, true) ~= nil,
        "ИСПРАВЛЕНО: getRecord дожидается базы перед выдачей прав")

    -- Порядок: дождаться базы надо ДО чтения таблицы.
    local iEnsure = gr and gr:find("ensureDoorsDB()", 1, true)
    local iRead = gr and gr:find("D.Data.doors[id]", 1, true)
    ok(iEnsure and iRead and iEnsure < iRead,
        "ожидание стоит перед чтением таблицы, иначе смысла нет")

    -- Задача с таким именем действительно регистрируется.
    ok(src:find('GRM.Boot.Task("doors.db"', 1, true) ~= nil,
        "имя задачи совпадает с тем, что ждёт ensureDoorsDB")

    --[[ Ensure не должен падать, если планировщика нет вовсе (сборка
         без sh_00_grm_boot): модуль дверей обязан работать и так. ]]
    local ens = src:match("local function ensureDoorsDB%(%).-\n    end")
    ok(ens and ens:find("if not GRM.Boot", 1, true) ~= nil,
        "без планировщика функция не падает, а просто пропускает ожидание")
end

-----------------------------------------------------------------------
print("\n=== 4. ЗАЩИТА ОТ ЗАЦИКЛИВАНИЯ ===")
-----------------------------------------------------------------------
do
    --[[ Ensure зовётся из getRecord. Если бы сама загрузка базы внутри
         себя дёрнула getRecord, вышла бы рекурсия. Проверяем, что
         повторный вход безопасен: задача, уже выполняемая, не
         запускается второй раз. ]]
    local depth, maxDepth = 0, 0
    B.Tasks["recurse.db"] = nil
    B.Task("recurse.db", "early", function()
        depth = depth + 1
        if depth > maxDepth then maxDepth = depth end
        if depth < 5 then B.Ensure("recurse.db") end
        depth = depth - 1
    end)
    local okRun = pcall(B.Ensure, "recurse.db")
    ok(okRun, "повторный вход в задачу не роняет планировщик")
    ok(maxDepth <= 2, "и не уходит в глубокую рекурсию", maxDepth)
end

-----------------------------------------------------------------------
print("\n=== 5. НЕИЗВЕСТНАЯ ЗАДАЧА НЕ ЛОМАЕТ ЛОГИКУ ===")
-----------------------------------------------------------------------
do
    ok(B.Ensure("нет.такой.задачи") == false,
        "Ensure несуществующей задачи возвращает false, а не падает")
    ok(B.Done("нет.такой.задачи") == false, "Done тоже отвечает спокойно")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
