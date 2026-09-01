--[[ Живой прогон единой панели состояния (заказ владельца 22.08:
     «переработай дизайн всего худа, всех прогресс-баров»).
     Проверяем реестр полос и то, что модули больше не рисуют своё.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_hud_bars.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local t = f:read("*a") f:close()
    return t
end

local hudSrc = read("lua/autorun/client/cl_grm_hud.lua")
local function has(n) return hudSrc:find(n, 1, true) ~= nil end

print("\n=== 1. РЕЕСТР ПОЛОС ===")
ok(has("function GRM.HUD.RegisterBar(id, def)"), "модуль может объявить свою полосу")
ok(has("function GRM.HUD.BarList()"), "панель берёт полосы списком по порядку")
ok(has("if a.order == b.order then return a.id < b.id end"),
   "порядок строгий: одинаковый order не даёт прыгающих полос")

-- живая проверка сортировки на копии логики реестра
local bars = {}
local function RegisterBar(id, def) def.id = id bars[id] = def end
RegisterBar("weight", { order = 60, label = "ВЕС", Get = function() end })
RegisterBar("stamina", { order = 30, label = "ВЫНОСЛИВОСТЬ", Get = function() end })
RegisterBar("hunger", { order = 50, label = "СЫТОСТЬ", Get = function() end })
local list = {}
for _, d in pairs(bars) do list[#list + 1] = d end
table.sort(list, function(a, b)
    if a.order == b.order then return a.id < b.id end
    return a.order < b.order
end)
ok(list[1].id == "stamina" and list[2].id == "hunger" and list[3].id == "weight",
   "полосы идут в заданном порядке: выносливость → сытость → вес")

print("\n=== 2. ПАНЕЛЬ СОБИРАЕТСЯ ПОД СОДЕРЖИМОЕ ===")
ok(has("local ph = headerH + pad + #rows * (rowH + gap) + moneyH + pad - gap"),
   "высота панели считается по числу полос, а не задана константой")
ok(has('label = "БРОНЯ"'), "броня показывается всегда, даже при 0")
ok(has('rows[#rows + 1] = { label = "ЗДОРОВЬЕ"'), "здоровье в общем списке, а не отдельным кодом")
ok(has("local ok, value, max, text, color, hidden = pcall(def.Get)"),
   "чужая полоса вызывается через pcall — ошибка модуля не роняет HUD")
ok(has('label = "НАЛИЧНЫЕ"') and has('label = "СЧЁТ"'),
   "финансы вынесены в две нижние кассеты")

print("\n=== 3. МОДУЛИ БОЛЬШЕ НЕ РИСУЮТ СВОЁ ===")
local move = read("lua/autorun/sh_grm_movement.lua")
ok(move:find('GRM.HUD.RegisterBar("stamina"', 1, true) ~= nil, "выносливость объявлена полосой")
ok(move:find('GRM.HUD.RegisterBar("breath"', 1, true) ~= nil, "дыхание тоже полоса")
ok(move:find('hook.Add("Think", "GRM_Movement_Breath"', 1, true) ~= nil,
   "запас воздуха считается своим отсчётом — движок его не отдаёт")

local food = read("lua/autorun/client/cl_grm_food_hud.lua")
ok(food:find('GRM.HUD.RegisterBar("hunger"', 1, true) ~= nil, "сытость объявлена полосой")
ok(food:find("x = sw - 1066", 1, true) == nil,
   "абсолютные координаты сытости убраны (на других разрешениях улетало)")

local enc = read("lua/autorun/client/cl_grm_encumbrance.lua")
ok(enc:find('GRM.HUD.RegisterBar("weight"', 1, true) ~= nil, "вес объявлен полосой")
ok(enc:find('hook.Add("HUDPaint", "GRM_Weight_HUD"', 1, true) == nil,
   "своя полоса веса по центру экрана убрана")
ok(enc:find('hook.Add("HUDPaint", "GRM_Weight_Warning"', 1, true) ~= nil,
   "предупреждение о перегрузе осталось отдельной строкой")

print("\n=== 4. СТАНДАРТНЫЙ ХУД НЕ ДУБЛИРУЕТ ===")
local clean = read("lua/autorun/client/cl_grm_hud_clean.lua")
ok(clean:find("CHudHealth = true", 1, true) ~= nil, "здоровье HL2 скрыто — рисуем своё")
ok(clean:find('hook.Add("HUDDrawTargetID"', 1, true) ~= nil, "чужая подпись над игроком тоже")

print(("\nHUD BARS: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
