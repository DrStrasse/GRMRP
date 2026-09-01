--[[--------------------------------------------------------------------
    sim_stability_load — заказ владельца 18.08 (вечерний блок):
      1) вкладки /factions не сбрасываются в пустой экран;
      2) цвета чат-каналов: /fr золотой с красным тэгом, /dep бордовый;
      3) распределение нагрузки в рантайме + детектор фризов.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_stability_load.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ui       = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local factions = read("lua/autorun/sh_factions.lua")
local perf     = read("lua/autorun/sh_06_grm_performance.lua")
local keys     = read("lua/autorun/server/sv_vehicle_keys.lua")

print("\n=== 1. ВКЛАДКИ /factions НЕ СБРАСЫВАЮТСЯ ===")
ok(ui:find("local currentParkHooked = nil", 1, true) ~= nil,
    "парковка панелей доступна и автосинку, не только UI.Open")
ok(ui:find("currentParkHooked = parkHookedPanels", 1, true) ~= nil, "ссылка проставляется при открытии окна")
ok(ui:find("if currentParkHooked then currentParkHooked() end", 1, true) ~= nil,
    "автосинк паркует панели модулей ПЕРЕД Clear() — вкладка больше не пустеет")
ok(ui:find('if isstring(currentTab) and currentTab:sub(1, 4) == "ext:" then return end', 1, true) ~= nil,
    "разделы модулей вообще не пересобираются автосинком — они обновляют себя сами")
ok(ui:find('local key = "ext:" .. label', 1, true) ~= nil, "ключ навесного раздела единый (ext:)")

print("\n=== 2. ЦВЕТА КАНАЛОВ ===")
ok(factions:find("local CH_RADIO_GOLD = Color(255, 200, 0)", 1, true) ~= nil, "золотой цвет рации задан явно")
ok(factions:find("local CH_RADIO_TAG  = Color(225, 60, 60)", 1, true) ~= nil, "тэг рации — красный")
ok(factions:find("local CH_DEP_WINE   = Color(170, 45, 60)", 1, true) ~= nil, "госволна — бордовая")
ok(factions:find('printChannel("[Рация] ", CH_RADIO_GOLD, CH_RADIO_TAG, tag, name, role, text, CH_RADIO_GOLD)', 1, true) ~= nil,
    "/fr: заголовок и весь текст золотые, тэг красный")
ok(factions:find('printChannel("[Волна] ", CH_DEP_WINE, CH_DEP_WINE, tag, name, role, text, CH_DEP_WINE)', 1, true) ~= nil,
    "/dep, /d: всё бордовое без разноцветья")
ok(factions:find('printChannel("[Волна OOC] ", CH_DEP_WINE, CH_DEP_WINE', 1, true) ~= nil,
    "/depb, /db: тоже бордовые")
ok(factions:find("bodyColor = bodyColor or Color(255, 255, 255)", 1, true) ~= nil,
    "цвет тела сообщения — параметр, а не жёстко зашитый набор")

print("\n=== 3. РАСПРЕДЕЛЕНИЕ НАГРУЗКИ ===")
ok(perf:find('P.Version   = "1.3.0"', 1, true) ~= nil, "Perf v1.3.0")
ok(perf:find("function P.Queue", 1, true) ~= nil, "очередь разовых фоновых задач")
ok(perf:find("function P.Spread", 1, true) ~= nil, "порционный обход больших списков")
ok(perf:find("grm_perf_budget_ms", 1, true) ~= nil, "бюджет миллисекунд на кадр настраивается конваром")
ok(perf:find("hook.Remove(\"Think\", \"GRM_Perf_Jobs\")", 1, true) ~= nil,
    "планировщик засыпает, когда очередь пуста")
ok(perf:find('for i = #P.Jobs, 1, -1 do', 1, true) ~= nil,
    "повторная постановка того же обхода заменяет прежний, а не копится")
ok(perf:find('concommand.Add("grm_perf_queue"', 1, true) ~= nil, "очередь видно из консоли")
ok(keys:find('GRM.Perf.Spread("vehiclekeys.refresh"', 1, true) ~= nil,
    "обновление ключей транспорта размазано по кадрам на полном сервере")

print("\n=== 4. ДЕТЕКТОР ФРИЗОВ ===")
ok(perf:find('hook.Add("Think", "GRM_Perf_SpikeWatch"', 1, true) ~= nil, "считается время кадра/тика")
ok(perf:find("grm_perf_spike_ms", 1, true) ~= nil, "порог всплеска настраивается")
ok(perf:find('"gmod_sent_vehicle_fphysics_base", "lvs_base"', 1, true) ~= nil,
    "в момент всплеска считаются машины simfphys и LVS")
ok(perf:find('concommand.Add("grm_perf_report"', 1, true) ~= nil, "отчёт по фризам из консоли")
ok(perf:find('concommand.Add("grm_perf_reset"', 1, true) ~= nil, "статистику можно сбросить")
ok(perf:find("while #P.Spikes > 40 do table.remove(P.Spikes, 1) end", 1, true) ~= nil,
    "история всплесков ограничена — детектор сам не течёт")

print(("\nSTABILITY + LOAD: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
