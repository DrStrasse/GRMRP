--[[--------------------------------------------------------------------
    sim_nameplate_ui — шапка над головой v3 и кнопки /pcboard в служебных
    компьютерах (этап 2 концепции CONCEPT_PCBOARD_IDENTITY.md).

    Живая логика — sim_nameplate_runtime.lua. Здесь: объединение двух HUD,
    состав отрисовки и интеграции.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_nameplate_ui.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local np    = read("lua/autorun/sh_grm_nameplate.lua")
local pcb   = read("lua/autorun/sh_grm_pcboard.lua")
local pcbUI = read("lua/autorun/client/cl_grm_pcboard_ui.lua")

print("\n=== 1. ОДИН HUD ВМЕСТО ДВУХ ===")
ok(has(np, 'hook.Add("HUDPaint", "GRM_Nameplate"'), "единая отрисовка шапки")
ok(has(np, 'hook.Remove("HUDPaint", "Factions_HUD")'), "старая шапка организаций снимается")
ok(has(np, 'hook.Remove("HUDPaint", "GRM_RPDesc")'), "старая плашка описания снимается")
ok(has(np, "грузится ПОСЛЕ нас"), "объяснено, почему снятие идёт после загрузки")
ok(has(np, "local wrapCache"), "перенос строк кэшируется, а не считается каждый кадр")
ok(has(np, "GRM.Perf.Players"), "проход по игрокам через общий кэш GRM.Perf")

print("\n=== 1б. ДВЕ ПЛАШКИ СРАЗУ (жалоба 21.08) ===")
local rpdesc = read("lua/autorun/sh_grm_rpdesc.lua")
local factions0 = read("lua/autorun/sh_factions.lua")
ok(has(np, "NP.Active = cvEnable:GetBool()"), "у шапки есть флаг активности")
ok(has(rpdesc, "if GRM.Nameplate and GRM.Nameplate.Active then return end"),
    "старая плашка описания молчит, пока работает новая")
ok(has(factions0, "if GRM.Nameplate and GRM.Nameplate.Active then return end"),
    "старая шапка организации молчит, пока работает новая")
ok(has(np, 'cvars.AddChangeCallback("grm_cl_nameplate"'),
    "выключил новую шапку — старые вернулись")
ok(has(np, "grm_nameplate_debug"), "есть диагностика: кто именно рисует над головами")
ok(has(np, "veh:OBBMaxs().z"), "в транспорте плашка считается от габаритов машины")

print("\n=== 2. ВИДИМОСТЬ ИМЕНИ ===")
ok(has(np, "function NP.NameVisible"), "правило видимости имени — одна функция на сервер и клиент")
ok(has(np, '"grm_nameplate_mode", "docs"'), "по умолчанию «Неизвестный» до предъявления документа")
ok(has(np, 'if SERVER then\n    CreateConVar("grm_nameplate_mode"'),
    "реплицируемые конвары создаёт только сервер")
ok(has(np, "function NP.UnknownLabel"), "незнакомец подписан с полом из паспорта")
ok(has(np, "function NP.Describe"), "состав плашки считается отдельно от отрисовки")
ok(has(np, 'ply:GetNWBool("GRM_FactionOnDuty", false)'), "тег и должность — только на службе")
ok(has(np, "Легенда сильнее знакомства"), "под легендой показывается прикрытие")
ok(has(np, 'out.name = "Тело"'), "мёртвый подписан телом")
ok(has(np, 'cidMode == "gov"'), "номер гражданина показывается по настройке")

print("\n=== 3. ЗНАКОМСТВА ===")
ok(has(np, "function NP.Learn") and has(np, "function NP.Knows"), "знакомства — отдельный слой")
ok(has(np, "grm_identity/acquaintance.json") or has(np, 'FILE = DIR .. "/acquaintance.json"'),
    "знакомства хранятся в файле и переживают перезаход")
ok(has(np, "function NP.Introduce"), "команда «представиться»")
ok(has(np, "function NP.ShowDocument"), "команда «предъявить документ»")
ok(has(np, 'hook.Add("GRM_PCBoardIdentified", "GRM_Nameplate_PCBoard"'),
    "пробитие по базе делает сотрудника знакомым с лицом")
ok(has(np, "Под легендой знакомство НЕ записывается"), "легенда не выдаёт настоящее имя")
ok(has(np, '"/представиться"') and has(np, '"/паспорт"') and has(np, '"/знакомые"'),
    "русские команды на месте")
ok(has(np, 'hook.Add("PlayerSay", "GRM_Nameplate_Chat"')
    and has(np, 'hook.Add("PlayerSayTransform", "GRM_Nameplate_ChatEC"'),
    "команды работают и в штатном чате, и в EasyChat")

print("\n=== 4. ОСОБЫЕ ПРИМЕТЫ ===")
ok(has(np, "function NP.Marks") and has(np, "function NP.SetMarks"), "приметы — отдельное поле, не описание")
ok(has(np, "над головой приметы не показываются"), "приметы видно только при осмотре и в справке")
ok(has(np, "function NP.OpenMarksEditor"), "редактор примет в стиле GRM")
ok(has(pcb, 'PB.RegisterProvider("marks"'), "приметы попали в справку /pcboard")

print("\n=== 5. ПРОИЗВОДИТЕЛЬНОСТЬ И СТАРТ ===")
ok(has(np, 'timer.Create("GRM_Nameplate_Refresh", 15, 0'), "обновление подписей раз в 15 секунд, не в кадре")
ok(has(np, 'GRM.Boot.OnMapStart("GRM_Nameplate_Load"'), "старт через планировщик GRM.Boot")
ok(has(np, 'hook.Add("ShutDown", "GRM_Nameplate_Save"'), "данные сохраняются при выключении карты")
ok(has(np, "if not (dirty or force) then return false end"), "файл пишется только при изменениях")

print("\n=== 6. КНОПКИ /pcboard В СЛУЖЕБНЫХ КОМПЬЮТЕРАХ ===")
ok(has(pcbUI, "function PB.AttachTab"), "вкладка терминала реализована один раз")
ok(has(pcbUI, "RunConsoleCommand(\"grm_pcboard\""), "кнопка шлёт ту же команду, второй реализации нет")
ok(has(pcbUI, 'hook.Add("GRM_PCBoardCard", panel'), "справка сама ложится в открытый терминал")
ok(has(pcbUI, "не видит local, объявленный ниже по файлу"),
    "помощник объявлен выше вызывающих (правило форвард-локалов)")
local terminals = { "grm_comp_police", "grm_comp_military", "grm_comp_military_police",
    "grm_comp_security", "grm_comp_traffic", "grm_comp_medical", "grm_comp_court",
    "grm_comp_cityhall", "grm_doc_computer" }
for _, name in ipairs(terminals) do
    local src = read("lua/entities/" .. name .. "/cl_init.lua")
    ok(has(src, "GRM.PCBoard.AttachTab(tabs)"), "вкладка «Госбаза» в терминале " .. name)
end

print(("\nNAMEPLATE UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
