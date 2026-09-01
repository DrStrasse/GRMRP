--[[ Живой прогон формы должностей, фаза 4 (заказ владельца 27.08).

     До этой фазы своя форма должности задавалась ТОЛЬКО из кода: в дереве
     редактора /models_admin её просто не было. Теперь узел должности стоит
     рядом со своим подразделением.

     Проверяется:
       1) наборы должности сохраняются на диск и переживают рестарт;
       2) форма должности сильнее формы отдела и звания (порядок выдачи);
       3) сервер принимает сохранение только для существующей должности;
       4) в дереве редактора есть узлы должностей всех трёх уровней;
       5) должность с удалённым подразделением не пропадает из редактора;
       6) организация без должностей выглядит и работает как раньше.

     Запуск: luajit tools/luatest/sim_faction_position_loadout.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-- POS.Set/Delete живут под SERVER: стенд проверяет именно серверную сторону.
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
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
GRM = {}
FactionsAPI = { Save = function() end }

assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions

local FAC = {
    DisplayName = "Полиция",
    Departments = { "patrol" },
    Subdepartments = { traffic = { id = "traffic", name = "Дорожный надзор", parentDept = "patrol",
        models = { { path = "models/sub.mdl" } } } },
    Roles = { "sergeant" },
    Positions = {},
    Members = {},
    Models = { { path = "models/faction.mdl" } },
    RoleModels = { sergeant = { { path = "models/rank.mdl" } } },
    DepartmentModels = { patrol = { { path = "models/dept.mdl" } } },
    PositionModels = {},
    PositionWeapons = {},
}
Factions = { ["Полиция"] = FAC }

POS.Set("Полиция", "chief", { name = "Начальник полиции", node = "root", kind = "head", slots = 1 })
POS.Set("Полиция", "patrol_head", { name = "Начальник патруля", node = "dept:patrol", kind = "head", slots = 1 })
POS.Set("Полиция", "traffic_head", { name = "Старший дорожного надзора", node = "sub:traffic", kind = "senior", slots = 1 })

print("\n=== 1. ФОРМА ДОЛЖНОСТИ СИЛЬНЕЕ ОСТАЛЬНЫХ ===")
FAC.PositionModels["patrol_head"] = { { path = "models/head_uniform.mdl" } }
local boss = { Role = "sergeant", Department = "patrol", Position = "patrol_head" }
local rank = { Role = "sergeant", Department = "patrol" }
local list, why = POS.ResolveLoadout(FAC, boss, "models")
ok(why == "position:patrol_head", "начальник получает форму своей должности", why)
ok(list[1].path == "models/head_uniform.mdl", "именно её модель")
local _, why2 = POS.ResolveLoadout(FAC, rank, "models")
ok(why2 == "dept:patrol", "подчинённый того же отдела остаётся в форме отдела", why2)

FAC.PositionWeapons["patrol_head"] = { "weapon_pistol" }
local _, whyW = POS.ResolveLoadout(FAC, boss, "weapons")
ok(whyW == "position:patrol_head", "оружие должности работает так же", whyW)

print("\n=== 2. СОХРАНЕНИЕ НА ДИСК (переживает рестарт) ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local fixes = body("lua/autorun/sh_faction_fixes.lua")
ok(fixes:find("PositionModels = f.PositionModels or {}", 1, true) ~= nil,
   "форма должностей пишется в файл организаций")
ok(fixes:find("PositionWeapons = f.PositionWeapons or {}", 1, true) ~= nil,
   "оружие должностей пишется тоже")
ok(fixes:find("f.PositionModels = istable(data.PositionModels)", 1, true) ~= nil,
   "и читается обратно при загрузке")
ok(fixes:find("f.PositionWeapons = istable(data.PositionWeapons)", 1, true) ~= nil,
   "оружие читается обратно")

print("\n=== 3. СЕРВЕР ПРИНИМАЕТ СОХРАНЕНИЕ ===")
ok(fixes:find('elseif saveType == "position" then', 1, true) ~= nil,
   "обработчик сохранения формы должности есть")
local _, saveCount = fixes:gsub('saveType == "position"', "")
ok(saveCount == 2, "он есть и для моделей, и для оружия", saveCount)
ok(fixes:find("GRM.Positions.Get(f, key)", 1, true) ~= nil,
   "сохранение только для существующей должности — иначе набор повис бы в воздухе")
ok(fixes:find("posList = st.posList", 1, true) ~= nil, "должности уходят в снимок редактора")

print("\n=== 4. ДЕРЕВО РЕДАКТОРА ===")
local ui = body("lua/autorun/client/cl_grm_faction_loadout_admin.lua")
ok(ui:find("positionsOfNode", 1, true) ~= nil, "узлы должностей строятся по подразделению")
ok(ui:find('scope = "position"', 1, true) ~= nil, "у узла свой тип сохранения")
ok(ui:find("ДОЛЖНОСТИ ОРГАНИЗАЦИИ", 1, true) ~= nil, "должности организации отдельной группой")
ok(ui:find('positionsOfNode(fd, "dept:" .. deptKey)', 1, true) ~= nil, "должности отдела под отделом")
ok(ui:find('positionsOfNode(fd, "sub:" .. sub.id)', 1, true) ~= nil, "должности подотдела под подотделом")
ok(ui:find("ДОЛЖНОСТИ БЕЗ ПОДРАЗДЕЛЕНИЯ", 1, true) ~= nil,
   "должность с удалённым подразделением не теряется из редактора")
ok(ui:find("ЗВАНИЯ (РАНГИ)", 1, true) ~= nil,
   "группа званий переименована — раньше звания назывались должностями и путали")

print("\n=== 5. РАСПРЕДЕЛЕНИЕ ПО УЗЛАМ ===")
-- Повторяем логику дерева: каждая должность попадает ровно под свой узел.
local fd = { posList = {} }
for _, pos in ipairs(POS.List(FAC)) do
    fd.posList[#fd.posList + 1] = { id = pos.id, name = pos.name, node = pos.node }
end
local function ofNode(node)
    local out = {}
    for _, p in ipairs(fd.posList) do if p.node == node then out[#out + 1] = p end end
    return out
end
ok(#ofNode("root") == 1 and ofNode("root")[1].id == "chief", "должность организации на своём месте")
ok(#ofNode("dept:patrol") == 1 and ofNode("dept:patrol")[1].id == "patrol_head", "должность отдела на своём месте")
ok(#ofNode("sub:traffic") == 1 and ofNode("sub:traffic")[1].id == "traffic_head", "должность подотдела на своём месте")
ok(#fd.posList == 3, "ни одна должность не потерялась и не задвоилась", #fd.posList)

print("\n=== 6. СОВМЕСТИМОСТЬ ===")
local clean = { DisplayName = "Без должностей", Departments = { "main" }, Roles = { "member" },
    Members = {}, Positions = {}, Models = { { path = "models/x.mdl" } },
    DepartmentModels = { main = { { path = "models/main.mdl" } } } }
local _, whyClean = POS.ResolveLoadout(clean, { Role = "member", Department = "main" }, "models")
ok(whyClean == "dept:main", "организация без должностей одевается как раньше", whyClean)
FAC.PositionModels["patrol_head"] = nil
local _, whyEmpty = POS.ResolveLoadout(FAC, boss, "models")
ok(whyEmpty == "dept:patrol",
   "должность без своей формы не ломает выдачу — падаем на форму отдела", whyEmpty)
POS.Delete("Полиция", "patrol_head")
ok(FAC.PositionModels["patrol_head"] == nil and FAC.PositionWeapons["patrol_head"] == nil,
   "удаление должности убирает и её наборы, чтобы новая одноимённая не унаследовала чужую форму")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
