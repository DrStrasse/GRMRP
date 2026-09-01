--[[--------------------------------------------------------------------
    sim_perf_core — GRM Perf v1.3.0: живой прогон + проверка применения
    в горячих местах модулей.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_perf_core.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

print("\n=== 1. ЯДРО GRM.Perf ===")
stub.reset()
local loaded, err = stub.loadModule("lua/autorun/sh_06_grm_performance.lua")
ok(loaded, "модуль поднялся", err)
local P = _G.GRM and _G.GRM.Perf
ok(P and P.Version == "1.3.0", "версия 1.3.0", P and P.Version)

-- Коалесцирование: 500 событий -> ОДИН отложенный вызов.
local runs = 0
for _ = 1, 500 do P.Coalesce("test.key", 0, function() runs = runs + 1 end) end
ok(runs == 0, "коалесцированный вызов не выполняется сразу")
stub.runTimers()
ok(runs == 1, "500 событий свернулись в 1 вызов", tostring(runs))

-- Реестр entity: OnEntityCreated не заводит таймер на каждую entity.
local created = 0
for _ = 1, 200 do
    created = created + 1
    local e = stub.makeEntity({ class = "grm_test_ent" })
    _G.hook.Run("OnEntityCreated", e)
end
local timerCount = 0
for _ in pairs(stub.timers) do timerCount = timerCount + 1 end
ok(timerCount <= 1, ("на 200 созданных entity заведено таймеров: %d"):format(timerCount))
stub.runTimers()
ok(#P.Entities("grm_test_ent") == 200, "реестр класса собрал все 200", tostring(#P.Entities("grm_test_ent")))

-- Кэш игроков
local p1 = stub.makeEntity({ class = "player", isPlayer = true })
local p2 = stub.makeEntity({ class = "player", isPlayer = true })
P._playersDirty = true
local list1 = P.Players()
local list2 = P.Players()
ok(#list1 == 2, "кэш игроков видит обоих", tostring(#list1))
ok(rawequal(list1, list2), "повторный вызов отдаёт ту же таблицу (без аллокации)")
p2.__valid = false
ok(#P.Players() == 1, "невалидный игрок исчезает из кэша")

-- Кэш трейса
local traces = 0
local viewer = stub.makeEntity({ class = "player", isPlayer = true })
viewer.GetEyeTrace = function() traces = traces + 1 return { Entity = p1 } end
stub.frame = 10
P.EyeTrace(viewer) P.EyeTrace(viewer) P.EyeTrace(viewer)
ok(traces == 1, "три потребителя в одном кадре = один трейс", tostring(traces))
stub.frame = 11
stub.time = 100
P.EyeTrace(viewer)
ok(traces == 2, "в новом кадре трейс обновился", tostring(traces))

-- Кэш материалов
local matCalls = 0
_G.Material = function(path) matCalls = matCalls + 1 return { path = path } end
P.Material("a/b.png") P.Material("a/b.png") P.Material("a/b.png")
ok(matCalls == 1, "Material() кэшируется", tostring(matCalls))

-- Троттлинг
stub.time = 0
ok(P.Throttle("t", 1) == true and P.Throttle("t", 1) == false, "троттлинг режет повторный вызов")

print("\n=== 2. ПРИМЕНЕНИЕ В МОДУЛЯХ (устранение микрофризов) ===")
local function usesPlayers(path)
    return read(path):find("GRM.Perf.Players()", 1, true) ~= nil
end
ok(usesPlayers("lua/autorun/sh_factions.lua"), "Factions_HUD: кэш игроков вместо player.GetAll в кадре")
ok(usesPlayers("lua/autorun/sh_grm_rpdesc.lua"), "RP-описания: кэш игроков")
ok(usesPlayers("lua/autorun/sh_grm_arrest.lua"), "Арест: кэш игроков")
ok(usesPlayers("lua/autorun/server/sv_grm_alarm.lua"), "Сигнализация: кэш игроков")
ok(usesPlayers("lua/autorun/server/sv_grm_handcuffs.lua"), "Наручники: кэш игроков")
ok(usesPlayers("lua/autorun/sh_grm_medical_full.lua"), "Медицина: кэш игроков")

local alarm = read("lua/autorun/server/sv_grm_alarm.lua")
ok(alarm:find("local alive = {}", 1, true) and alarm:find("if #alive == 0 then return end", 1, true),
    "Сигнализация: список живых строится один раз на проход, пустой скан отсекается")

local eye = 0
for _, f in ipairs({
    "lua/autorun/client/cl_grm_handcuffs.lua",
    "lua/autorun/client/cl_grm_augmentations_hud.lua",
    "lua/autorun/client/cl_vehicle_hud.lua",
    "lua/autorun/sh_grm_incassation.lua",
    "lua/autorun/sh_grm_doors.lua",
    "lua/autorun/sh_grm_prop_protect.lua",
    "lua/entities/grm_augmentation_pod/init.lua",
}) do
    if read(f):find("GRM.Perf.EyeTrace", 1, true) then eye = eye + 1 end
end
ok(eye == 7, ("покадровые GetEyeTrace переведены на общий кэш: %d/7"):format(eye))

local fire = read("addons/grm_fire/lua/autorun/sh_grm_fire_addon.lua")
ok(fire:find('GRM.Perf.Entities("grm_fire_ladder")', 1, true) and fire:find("if #ladders == 0 then return end", 1, true),
    "SetupMove пожарной лестницы: реестр + ранний выход (было ents.FindByClass каждый тик)")

local radio = read("lua/autorun/sh_grm_radionet.lua")
ok(select(2, radio:gsub('GRM%.Perf%.Entities%("grm_', "")) >= 5,
    "Радиосеть: пять сканов классов в пересчёте 0.7с заменены реестрами")

local spots = read("addons/grm_fire/lua/entities/grm_fire_spot/cl_init.lua")
ok(spots:find("GRM.Perf.Entities", 1, true), "Маркеры очагов: покадровый скан класса убран")


print("\n=== 3. ВТОРАЯ ВОЛНА: ВРЕМЯ, ДВЕРИ, ОГОНЬ ===")
local doors = read("lua/autorun/sh_grm_doors.lua")
local liveGetAll = 0
for line in doors:gsub("%-%-%[%[.-%]%]", ""):gmatch("[^\n]+") do
    local body = line:gsub("^%s+", "")
    if not body:match("^%-%-") and body:find("ents.GetAll()", 1, true) then liveGetAll = liveGetAll + 1 end
end
ok(liveGetAll == 0, ("двери: живых ents.GetAll() не осталось (%d)"):format(liveGetAll))
ok(doors:find("for _, ent in ipairs(D.AllDoors()) do", 1, true) ~= nil,
    "сверка замков каждые 2с идёт по реестру дверей, а не по всем энтити")

local slide = read("lua/autorun/sh_grm_sliding_door.lua")
ok(slide:find("function SD.HasMoving", 1, true) and slide:find("if not SD._anyMoving then return end", 1, true),
    "раздвижные двери: покадровый обход отключается, когда ничего не едет")
ok(slide:find("if moving or next >= 1 or next <= 0 then", 1, true),
    "звуковые строки не собираются у стоящей двери")

local hose = read("addons/grm_fire/lua/entities/grm_fire_hose/init.lua")
ok(hose:find("local function hoseList()", 1, true) ~= nil
    and hose:find("local function walkPressure(ent, seen, hoses)", 1, true) ~= nil
    and hose:find("for _, h in ipairs(hoses) do", 1, true) ~= nil,
    "рукава: список рукавов берётся один раз на обход графа давления")
ok(hose:find("self._PressureAt = now + 0.25", 1, true),
    "рукава: пересчёт давления троттлится (было 12 обходов графа в секунду на рукав)")
ok(read("addons/grm_fire/lua/autorun/sh_grm_fire_hose.lua"):find("GRM.Perf.Entities(\"grm_fire_hose\")", 1, true) ~= nil,
    "счётчик рукавов на насосе использует реестр")

local fire = read("lua/autorun/sh_grm_fire.lua")
ok(fire:find("local function liveVfire()", 1, true) ~= nil, "очаги vFire берутся из общего реестра")
local rawVfire = select(2, fire:gsub('ents%.FindByClass%("vfire"%)', ""))
ok(rawVfire <= 1, ("прямых сканов vfire осталось %d (только фолбэк внутри хелпера)"):format(rawVfire))

local pod = read("lua/entities/grm_augmentation_pod/init.lua")
ok(pod:find("self:NextThink(CurTime() + 2)", 1, true) ~= nil, "капсула аугментаций не думает каждый тик")

local bc = read("lua/autorun/sh_grm_broadcast.lua")
ok(bc:find('GRM.Perf.Entities("grm_radio")', 1, true) ~= nil, "проверка слышимости радио использует реестр")

print(("\nPERF CORE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
