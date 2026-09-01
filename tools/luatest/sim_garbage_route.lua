--[[--------------------------------------------------------------------
    sim_garbage_route — мусоровоз: 3 пакета, последовательные GPS-метки,
    полигон только с полным кузовом.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_garbage_route.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local core = read("lua/autorun/sh_grm_jobs.lua")
local cfg  = read("lua/autorun/sh_grm_jobs_config.lua")
local v4   = read("lua/autorun/sh_grm_jobs_v4.lua")
local v5   = read("lua/autorun/sh_grm_jobs_v5.lua")

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

print("\n=== 1. ВМЕСТИМОСТЬ И МАРШРУТ: 3 ПАКЕТА ===")
ok(cfg:find("garbageStops = 3", 1, true), "в маршруте 3 контейнера")
ok(cfg:find("garbageCapacity = 3", 1, true), "кузов на 3 пакета")
ok(cfg:find("GARBAGE_PROFILE", 1, true), "профиль миграции существует")
ok(cfg:find("d.garbageProfile < GARBAGE_PROFILE", 1, true),
    "старый сохранённый конфиг (2 контейнера / кузов 8) мигрирует автоматически")
ok(select(2, cfg:gsub("garbageCapacity < d?%.?garbageStops", "")) >= 1
    or cfg:find("garbageCapacity < JB.WorkConfig.garbageStops", 1, true) ~= nil,
    "кузов никогда не меньше числа контейнеров (иначе 3/3 недостижимо)")
ok(core:find('needVehicle = true, points = 3', 1, true), "шаблон работы объявляет 3 точки")
ok(core:find("tonumber(tpl.points) or 3", 1, true), "фолбэк числа точек тоже 3")
ok(v4:find("garbageCapacity)or 3", 1, true), "загрузка пакета сверяется с вместимостью 3")
ok(v5:find('GRM_GarbageCapacity",tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity)or 3', 1, true),
    "NW-вместимость мусоровоза = 3")

print("\n=== 2. ПОЛИГОН ПРИНИМАЕТ ТОЛЬКО ПОЛНЫЙ РЕЙС ===")
ok(v5:find("local required=math.max(0,#(j.points or{})-1)", 1, true),
    "нужное число пакетов считается по маршруту")
ok(v5:find("if j.routeState==\"ready\" and required>0 and load<required then", 1, true),
    "неполный кузов не запускает выгрузку")
ok(v5:find("Полигон принимает только полный рейс", 1, true), "игрок получает понятное сообщение")
ok(v5:find('j.routeState=="ready"', 1, true),
    "сломанный маршрут (нет мусорки/свалки) не запирает игрока")

print("\n=== 3. GPS-МЕТКИ ПО ОЧЕРЕДИ ===")
local mStart = core:find('hook.Add("HUDPaint", "GRM_Jobs_GarbageRouteMarkers"', 1, true)
local marker = mStart and core:sub(mStart, (core:find("\n    end)", mStart, true) or #core) + 8) or nil
ok(marker ~= nil, "хук маршрутных меток найден")
if marker then
    ok(marker:find("local p = tracker.points[current]", 1, true), "берётся ТОЛЬКО текущая точка маршрута")
    ok(not marker:find("for i, p in ipairs(tracker.points)", 1, true), "цикл по всем точкам убран")
    ok(select(2, marker:gsub("drawScreenMarker%(", "")) == 1, "на экране ровно одна метка за кадр")
    ok(marker:find("ПОЛИГОН", 1, true) and marker:find("СОБРАТЬ МУСОР", 1, true),
        "подписи: контейнер до сбора, полигон после")
    ok(marker:find("collected, stops", 1, true), "в подписи виден прогресс X/Y")
end

print("\n=== 4. МЕТКА ГАСНЕТ ТОЛЬКО ПОСЛЕ ЗАГРУЗКИ В МАШИНУ ===")
ok(v4:find("j.pointIndex=(tonumber(j.pointIndex)or 1)+1;saveJobs(\"garbage loaded\")", 1, true),
    "индекс точки двигает ИМЕННО загрузка пакета в кузов")
ok(not core:find("pointIndex = j.pointIndex + 1", 1, true),
    "приближение к точке само по себе не переключает метку")
ok(core:find("net.WriteUInt(math.max(1, tonumber(j.pointIndex) or 1), 8)", 1, true),
    "актуальный индекс уходит клиенту в трекере")
ok(v4:find('GRM_Garbage_BlockVehicle', 1, true),
    "с пакетом в руках нельзя сесть в машину — только загрузить")

print("\n=== 5. HUD И СТАДИЯ ===")
ok(core:find('stageName = ("собрано %d/%d")', 1, true), "стадия показывает собрано X/Y")
ok(core:find('stageName = ("на полигон • %d/%d")', 1, true), "после полного кузова стадия — полигон")
ok(v4:find("Кузов полон — на полигон", 1, true), "уведомление о полном кузове")

print(("\nGARBAGE ROUTE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
