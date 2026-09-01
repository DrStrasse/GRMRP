--[[ Живой прогон обвязки должностей, фаза 5 (заказ владельца 27.08).

     Проверяется:
       1) точки спавна должности — начальник появляется в кабинете, а не
          в общей раздевалке; порядок тот же, что у формы;
       2) тег должности в шапке служебного канала;
       3) назначение и снятие попадают в кадровое дело;
       4) укомплектованность штата (свободные места = вакансии);
       5) удаление должности убирает её точки спавна;
       6) всё это не ломает организацию без должностей.

     Запуск: luajit tools/luatest/sim_faction_position_wiring.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return istable(v) and v._entity == true end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function string.Explode(sep, str)
    local out = {}
    for piece in string.gmatch(tostring(str or "") .. sep, "(.-)" .. sep) do out[#out + 1] = piece end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end

local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Run = function(name, ...) for _, fn in pairs(hooks[name] or {}) do fn(...) end end,
}
timer = { Simple = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
GRM = {}
FactionsAPI = { Save = function() end }

local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end

assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions

local FAC = {
    DisplayName = "Полиция",
    Tag = "ПД",
    Departments = { "patrol" },
    DepartmentTags = { patrol = "ПАТР" },
    Subdepartments = {},
    Roles = { "sergeant" },
    Positions = {},
    Members = {},
}
Factions = { ["Полиция"] = FAC }

POS.Set("Полиция", "patrol_head", { name = "Начальник патруля", node = "dept:patrol",
    kind = "head", slots = 1, tag = "НАЧ" })
POS.Set("Полиция", "inspector", { name = "Инспектор", node = "dept:patrol",
    kind = "staff", slots = 4 })

FAC.Members["1:char1"] = { Role = "sergeant", Department = "patrol", Position = "patrol_head" }
FAC.Members["2:char1"] = { Role = "sergeant", Department = "patrol", Position = "inspector" }

local spawnSrc = body("lua/autorun/sh_spawn_points.lua")
local factionsSrc = body("lua/autorun/sh_factions.lua")
local coreSrc = body("lua/autorun/sh_grm_factions_core_v4.lua")
local uiSrc = body("lua/autorun/client/cl_grm_factions_unified_ui.lua")

print("\n=== 1. ТОЧКИ СПАВНА ДОЛЖНОСТИ ===")
ok(spawnSrc:find("PositionSpawnPoints", 1, true) ~= nil, "у организации есть таблица точек должностей")
ok(spawnSrc:find("function AddSpawnPointForPosition", 1, true) ~= nil, "точку должности можно добавить")
ok(spawnSrc:find("function RemoveSpawnPointFromPosition", 1, true) ~= nil, "и удалить")
ok(spawnSrc:find("function GetSpawnPointsForPosition", 1, true) ~= nil, "и прочитать")
--[[ Раньше эти четыре проверки искали в исходнике конкретные строки
     («ПРИОРИТЕТ 0», «positions = f.PositionSpawnPoints or {}»). Механику
     осей свели в одну таблицу SPAWN_AXES, строки исчезли — и стенд
     покраснел на работающем коде. Это ровно §10.1.4: проверять надо
     контракт, а не буквы реализации. Поведение (приоритет, рестарт,
     очистка) проверяется вызовами API в sim_spawn_points.lua, раздел 8;
     здесь остаётся проводка: ось должности объявлена, стоит первой и
     участвует в общей загрузке. ]]
local axesBlock = spawnSrc:match("local SPAWN_AXES = %{.-\n    %}")
ok(axesBlock ~= nil, "оси иерархии объявлены одной таблицей SPAWN_AXES")
axesBlock = axesBlock or ""
ok(axesBlock:find('id = "position"', 1, true) ~= nil
   and axesBlock:find('member = "Position"', 1, true) ~= nil
   and axesBlock:find('bundle = "positions"', 1, true) ~= nil,
   "ось должности описана целиком (поле, участник, ключ JSON)")
local posAt = axesBlock:find('id = "position"', 1, true)
local subAt = axesBlock:find('id = "sub"', 1, true)
ok(posAt and subAt and posAt < subAt,
   "должность стоит в таблице раньше подотдела — это и есть порядок выбора точки")
ok(spawnSrc:find("GRM.Positions.Get(f, positionID)", 1, true) ~= nil,
   "точку нельзя повесить на несуществующую должность")
ok(spawnSrc:find("bundle[axis.bundle] = f[axis.field]", 1, true) ~= nil,
   "сохранение идёт по всем осям сразу (ось не забудут добавить в bundle)")
ok(spawnSrc:find("f[axis.field] = istable(stored) and stored or {}", 1, true) ~= nil,
   "и загрузка тоже по всем осям сразу")
ok(spawnSrc:find("GRM_SpawnPoints_PositionGone", 1, true) ~= nil,
   "удаление должности убирает её точки спавна")

print("\n=== 2. ТЕГ ДОЛЖНОСТИ В ЭФИРЕ ===")
--[[ sh_factions.lua целиком тянет половину API GMod, поэтому берём из него
     ровно блок тегов — но именно ЖИВОЙ код файла, а не его копию. ]]
GRM.Factions = GRM.Factions or {}
GRM.Factions.DisplayName = function(v, fb)
    if istable(v) then return tostring(v.DisplayName or fb or "") end
    return tostring(v or fb or "")
end
GRM.Factions.RegistrationName = function(v) return tostring(v or "") end
GRM.Factions.DepartmentTag = function(f, key)
    key = tostring(key or "") if key == "" then return "" end
    local tags = istable(f) and f.DepartmentTags or nil
    return tags and tostring(tags[key] or "") or ""
end
GRM.Factions.SubdepartmentTag = function(f, key)
    key = tostring(key or "") if key == "" then return "" end
    local subs = istable(f) and f.Subdepartments or nil
    local sub = subs and subs[key]
    return istable(sub) and tostring(sub.tag or "") or ""
end

local src = body("lua/autorun/sh_factions.lua")
local blockStart = src:find("function GRM.Factions.PositionTag", 1, true)
local blockEnd = src:find("\nfunction GRM.Factions.RoleDisplayName", blockStart, true)
assert(blockStart and blockEnd, "блок тегов не найден в sh_factions.lua")
local chunk = src:sub(blockStart, blockEnd)
-- factionTrim — локальная утилита файла, объявляем её так же, как в нём.
chunk = "local function factionTrim(v,m) return string.sub(string.Trim(tostring(v or '')),1,tonumber(m) or 96) end\n" .. chunk
local fn = assert(loadstring(chunk, "sh_factions.tags"))
setfenv(fn, _G)
fn()

ok(isfunction(GRM.Factions.PositionTag), "функция тега должности объявлена")
ok(GRM.Factions.PositionTag(FAC, "patrol_head") == "НАЧ", "тег берётся из должности",
   GRM.Factions.PositionTag(FAC, "patrol_head"))
ok(GRM.Factions.PositionTag(FAC, "inspector") == "", "без тега — пусто, уровень пропускается")
ok(GRM.Factions.PositionTag(FAC, "нет_такой") == "", "неизвестная должность тега не даёт")

local tagHead = GRM.Factions.ChannelTag(FAC, "patrol", "", "ПД", "patrol_head")
ok(tagHead == "ПД | ПАТР | НАЧ", "шапка канала показывает должность последней", tagHead)
local tagPlain = GRM.Factions.ChannelTag(FAC, "patrol", "", "ПД", "inspector")
ok(tagPlain == "ПД | ПАТР", "у рядового шапка прежняя", tagPlain)
local tagOld = GRM.Factions.ChannelTag(FAC, "patrol", "", "ПД")
ok(tagOld == "ПД | ПАТР", "старый вызов из четырёх аргументов работает как раньше", tagOld)
ok(factionsSrc:find("rec.Position)", 1, true) ~= nil, "должность прокинута в служебные каналы")
ok(factionsSrc:find("nwPositionID", 1, true) ~= nil, "и в networked-тег канала")

print("\n=== 3. КАДРОВОЕ ДЕЛО ===")
ok(coreSrc:find("GRM_FactionCore_PersonnelPosition", 1, true) ~= nil,
   "назначение попадает в кадровое дело")
ok(coreSrc:find("position_changed", 1, true) ~= nil, "у события свой тип записи")
ok(coreSrc:find("Назначен на должность", 1, true) ~= nil, "назначение пишется человеческим текстом")
ok(coreSrc:find("Снят с должности", 1, true) ~= nil, "снятие тоже")
ok(coreSrc:find("Переведён с должности", 1, true) ~= nil, "и перевод между должностями")

print("\n=== 4. ШТАТ И ВАКАНСИИ ===")
local stHead = POS.Staffing(FAC, "patrol_head")
ok(stHead.taken == 1 and stHead.free == 0, "место начальника занято")
local stInsp = POS.Staffing(FAC, "inspector")
ok(stInsp.taken == 1 and stInsp.free == 3, "у инспектора три свободных места — это и есть вакансии",
   stInsp.free)
ok(uiSrc:find("ШТАТ · СВОБОДНО МЕСТ", 1, true) ~= nil, "укомплектованность видна в обзоре организации")
ok(uiSrc:find("ШТАТ УКОМПЛЕКТОВАН", 1, true) ~= nil, "и отдельная подпись, когда мест не осталось")
ok(uiSrc:find('addStat(3, "ЗВАНИЙ"', 1, true) ~= nil,
   "без должностей карточка показывает звания, как раньше")

print("\n=== 5. СОВМЕСТИМОСТЬ ===")
local clean = { DisplayName = "Без должностей", Tag = "БД", Departments = { "main" },
    DepartmentTags = {}, Roles = { "member" }, Positions = {}, Members = {} }
Factions["Чистая"] = clean
ok(GRM.Factions.ChannelTag(clean, "main", "", "БД", "") == "БД",
   "организация без должностей: шапка прежняя",
   GRM.Factions.ChannelTag(clean, "main", "", "БД", ""))
ok(GRM.Factions.PositionTag(clean, "") == "", "пустая должность тега не даёт")
local member = { Role = "member", Department = "main" }
ok(POS.OfMember(clean, member) == nil, "сотрудник без должности законен")

POS.Delete("Полиция", "inspector")
ok(FAC.Members["2:char1"].Position == "", "удаление должности освободило сотрудника")
ok(POS.Get(FAC, "patrol_head") ~= nil, "прочие должности не задеты")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
