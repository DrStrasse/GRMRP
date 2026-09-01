--[[ Живой прогон управления должностями, фаза 2 (заказ владельца 27.08).

     Проверяется серверная часть — то, что нельзя проверить глазами:
       1) создание, правка и удаление должностей через Factions_Action;
       2) назначение и снятие сотрудников;
       3) штат: второго начальника на одно место не поставить;
       4) нельзя назначить на должность чужого подразделения;
       5) удаление должности освобождает людей, а не ломает организацию;
       6) раздел зарегистрирован в правах меню и в самом UI.

     Запуск: luajit tools/luatest/sim_faction_positions_ui.lua ]]
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

local hookRuns = {}
hook = {
    Add = function() end,
    Run = function(name, ...) hookRuns[#hookRuns + 1] = { name = name, args = { ... } } end,
}
timer = { Simple = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
GRM = {}

local saved = 0
FactionsAPI = { Save = function() saved = saved + 1 end }

assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions

local FAC = {
    DisplayName = "Полиция",
    Departments = { "patrol", "detectives" },
    Subdepartments = { traffic = { id = "traffic", name = "Дорожный надзор", parentDept = "patrol" } },
    Roles = { "lieutenant", "sergeant", "private" },
    Positions = {},
    Members = {
        ["1:char1"] = { Role = "lieutenant", Department = "patrol" },
        ["2:char1"] = { Role = "sergeant",   Department = "patrol" },
        ["3:char1"] = { Role = "sergeant",   Department = "patrol" },
        ["4:char1"] = { Role = "private",    Department = "detectives" },
    },
}
Factions = { ["Полиция"] = FAC }

print("\n=== 1. СОЗДАНИЕ ДОЛЖНОСТЕЙ ===")
local okSet, msg = POS.Set("Полиция", "patrol_head",
    { name = "Начальник патрульного отдела", node = "dept:patrol", kind = "head", slots = 1, tag = "НАЧ" })
ok(okSet == true, "должность создаётся", msg)
ok(saved > 0, "изменение сразу сохраняется на диск")
ok(POS.Get(FAC, "patrol_head").kind == "head", "вид должности сохранён")
ok(POS.Get(FAC, "patrol_head").tag == "НАЧ", "тег сохранён")

POS.Set("Полиция", "inspector", { name = "Инспектор", node = "dept:patrol", kind = "staff", slots = 2 })
POS.Set("Полиция", "det_head", { name = "Начальник розыска", node = "dept:detectives", kind = "head", slots = 1 })
ok(#POS.List(FAC) == 3, "все три должности в списке", #POS.List(FAC))

print("\n=== 2. ПРОВЕРКА ДАННЫХ ===")
ok(select(1, POS.Set("Полиция", "", {})) == false, "должность без ключа не создаётся")
ok(select(1, POS.Set("Полиция", "ghost", { node = "dept:НЕТУ" })) == false,
   "нельзя повесить должность на несуществующий отдел")
ok(select(1, POS.Set("Полиция", "ghost2", { node = "sub:НЕТУ" })) == false,
   "нельзя повесить должность на несуществующий подотдел")
ok(select(1, POS.Set("НетТакой", "x", {})) == false, "несуществующая организация отклоняется")
POS.Set("Полиция", "Стран Ный!Ключ", { name = "Тест", node = "root" })
ok(POS.Get(FAC, "стран_ный_ключ") ~= nil, "ключ приводится к безопасному виду")
POS.Delete("Полиция", "стран_ный_ключ")

print("\n=== 3. НАЗНАЧЕНИЕ ===")
local okA, msgA = POS.Assign("Полиция", "1:char1", "patrol_head")
ok(okA == true, "сотрудник назначается на должность", msgA)
ok(FAC.Members["1:char1"].Position == "patrol_head", "должность записана участнику")
ok(select(1, POS.Assign("Полиция", "1:char1", "patrol_head")) == false,
   "повторное назначение на ту же должность отклоняется")

local okDup, msgDup = POS.Assign("Полиция", "2:char1", "patrol_head")
ok(okDup == false, "второго начальника на единственное место не поставить", msgDup)
ok(tostring(msgDup):find("заняты", 1, true) ~= nil, "и объясняет почему", msgDup)

ok(select(1, POS.Assign("Полиция", "2:char1", "inspector")) == true, "на свободное место назначает")
ok(select(1, POS.Assign("Полиция", "3:char1", "inspector")) == true, "второй инспектор помещается")
ok(select(1, POS.Assign("Полиция", "4:char1", "inspector")) == false,
   "третий инспектор не помещается: мест всего два")

print("\n=== 4. ЧУЖОЕ ПОДРАЗДЕЛЕНИЕ ===")
local okAlien, msgAlien = POS.Assign("Полиция", "4:char1", "patrol_head")
ok(okAlien == false, "сотрудник розыска не станет начальником патруля", msgAlien)
ok(select(1, POS.Assign("Полиция", "4:char1", "det_head")) == true,
   "а начальником своего отдела — станет")
ok(select(1, POS.Assign("Полиция", "999:char1", "inspector")) == false,
   "неизвестный сотрудник отклоняется")

print("\n=== 5. СНЯТИЕ И УДАЛЕНИЕ ===")
local okOff, msgOff = POS.Assign("Полиция", "3:char1", "")
ok(okOff == true, "сотрудник снимается с должности", msgOff)
ok(FAC.Members["3:char1"].Position == "", "должность очищена")
ok(POS.Staffing(FAC, "inspector").free == 1, "место освободилось")

local okDel, msgDel = POS.Delete("Полиция", "inspector")
ok(okDel == true, "должность удаляется", msgDel)
ok(FAC.Members["2:char1"].Position == "", "занимавший её сотрудник освобождён, но остался в организации")
ok(FAC.Members["2:char1"].Role == "sergeant", "звание при этом не тронуто")
ok(select(1, POS.Delete("Полиция", "inspector")) == false, "повторное удаление отклоняется")

print("\n=== 6. НОРМАЛИЗАЦИЯ ПРИ ЗАГРУЗКЕ ===")
FAC.Members["2:char1"].Position = "давно_удалённая"
POS.NormalizeAll()
ok(FAC.Members["2:char1"].Position == "", "ссылка на исчезнувшую должность стирается")
ok(FAC.Members["1:char1"].Position == "patrol_head", "живые назначения не трогаются")

print("\n=== 7. СОБЫТИЯ ДЛЯ ДРУГИХ МОДУЛЕЙ ===")
local names = {}
for _, h in ipairs(hookRuns) do names[h.name] = true end
ok(names["GRM_FactionPositionChanged"] == true, "об изменении должности сообщается хуком")
ok(names["GRM_FactionMemberPositionChanged"] == true, "о назначении сотрудника сообщается хуком")

print("\n=== 8. ИНТЕРФЕЙС И ПРАВА ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local ui = body("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local factions = body("lua/autorun/sh_factions.lua")
local access = body("lua/autorun/sh_grm_faction_menu_access.lua")

ok(ui:find('addTabBtn("positions"', 1, true) ~= nil, "раздел «Должности» есть в меню организаций")
ok(ui:find("buildPositionsTab", 1, true) ~= nil, "у раздела есть построитель")
ok(access:find('key = "positions"', 1, true) ~= nil, "раздел объявлен в правах меню")
ok(access:find('{ key = "positions", name = "Должности",            default = "leader" }', 1, true) ~= nil,
   "по умолчанию раздел доступен лидеру, а не только суперадмину")
ok(ui:find("positions = true", 1, true) ~= nil, "раздел виден и в безопасном режиме без модуля прав")

for _, act in ipairs({ "positionSave", "positionDelete", "positionAssign" }) do
    ok(factions:find('action == "' .. act .. '"', 1, true) ~= nil,
       "сервер принимает действие " .. act)
    ok(ui:find('"' .. act .. '"', 1, true) ~= nil, "интерфейс отправляет действие " .. act)
    ok(factions:find(act .. "=true", 1, true) ~= nil,
       act .. " проходит Root Guard при правке чужой организации")
end
ok(factions:find("getFactionAndShift", 1, true) ~= nil,
   "действия используют штатную проверку прав: суперадмин или лидер своей организации")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
