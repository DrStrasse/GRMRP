--[[--------------------------------------------------------------------
    sim_garbage_route_fix — заказ владельца 19.08:
    «мусоровоз сбивает маршрут, хотя он выстроен, и пишет что маршрута нет,
     хотя точки стоят».

    Причина: маршрут строился ТОЛЬКО из точек, к которым нашлась физическая
    мусорка grm_garbage_bin; при её отсутствии/«угоне» соседней точкой рейс
    объявлялся ненастроенным, а сверка ещё и переписывала уже выстроенный
    маршрут. Теперь точка самодостаточна, мусорка — дополнение.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_garbage_route_fix.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local v5   = read("lua/autorun/sh_grm_jobs_v5.lua")
local v4   = read("lua/autorun/sh_grm_jobs_v4.lua")
local core = read("lua/autorun/sh_grm_jobs.lua")

print("\n=== 1. МАРШРУТ СТРОИТСЯ ПО ТОЧКАМ, А НЕ ПО МУСОРКАМ ===")
ok(not has(v5, "if rec and JB.GarbageBindings[rec.id]then out[#out+1]=obj end"),
    "фильтр «только точки с привязанной мусоркой» убран")
ok(has(v5, "for _,obj in ipairs(source or{})do if obj._grmJobPoint then out[#out+1]=obj end end"),
    "в маршрут идут все точки типа garbage")
ok(has(core, "Не установлено ни одной точки маршрута мусоровоза"),
    "текст отказа честный: нет точек, а не «нет связанных мусорок»")

print("\n=== 2. ПРИВЯЗКА МУСОРОК НЕ «УГОНЯЕТ» КОНТЕЙНЕРЫ ===")
ok(has(v5, "table.sort(pairsList"), "пары «точка↔мусорка» сортируются по расстоянию")
ok(has(v5, "if not claimed[pair.bin]and not bindings[pair.rec.id]then"),
    "жадное сопоставление: ближайшая пара выигрывает, остальные не ломаются")
ok(has(v5, "function JB.BinForPoint"), "есть резолвер «мусорка текущей точки» с запасным поиском по радиусу")

print("\n=== 3. СВЕРКА НЕ СБИВАЕТ ВЫСТРОЕННЫЙ РЕЙС ===")
ok(not has(v5, 'if not(rec and JB.GarbageBindings[id])then'),
    "точка больше не переписывается из-за пропавшей мусорки")
ok(has(v5, "if not rec then rec=nearestUnused(points,(j.points or{})[i],used)"),
    "замена ищется только когда сама запись точки удалена")
ok(has(v5, "j.routeBinsMissing"), "отсутствие контейнеров считается отдельно, рейс остаётся ready")
ok(not has(v5, '"missing_bin"'), "статус missing_bin больше не выставляется")
ok(has(v5, 'j.routeState="missing_point"'), "новый статус только для реально удалённой точки")

print("\n=== 4. СБОР БЕЗ ФИЗИЧЕСКОЙ МУСОРКИ ===")
ok(has(v5, "function JB.CollectAtPoint"), "есть сбор пакета прямо на точке маршрута")
ok(has(v5, 'Контейнера на точке нет'), "игрок получает понятную подсказку")
ok(has(v5, 'box:SetSourcePointID(tostring(idx))'), "на точке создаётся тот же пакет grm_garbage_box")
ok(has(v4, 'elseif JB.CollectAtPoint then JB.CollectAtPoint(ply)'),
    "клавиша G без пакета в руках зовёт сбор на точке")
ok(has(v4, 'p:GetNWBool("GRM_GarbageJob",false)'), "клиент шлёт запрос только на работе мусоровоза")
ok(has(core, 'ply:SetNWBool("GRM_GarbageJob", isGarbage)'), "сервер выставляет флаг работы мусоровоза")

print("\n=== 5. ПОИСК В МУСОРКЕ ПО РАССТОЯНИЮ ===")
ok(not has(v5, "JB.GarbageBindings[id]~=bin"), "жёсткая сверка привязки при использовании убрана")
ok(has(v4, "bin:GetPos():DistToSqr(curPos)>bindRadius*bindRadius"),
    "после задержки проверяется расстояние до текущей точки")

print("\n=== 6. АДМИН-СХЕМА ===")
ok(has(v5, "hasBin=IsValid(bin)"), "в схеме видно, есть ли у точки контейнер")
ok(has(v5, "без контейнера — сбор на точке клавишей G"), "точка без контейнера не считается поломкой")

print(("\nGARBAGE ROUTE FIX: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
