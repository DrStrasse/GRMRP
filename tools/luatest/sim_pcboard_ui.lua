--[[--------------------------------------------------------------------
    sim_pcboard_ui — состав планшета госслужб /pcboard и его интерфейса.

    Живая логика — sim_pcboard_runtime.lua. Здесь: наличие вкладки «Госбаза»
    в /factions, окно справки, вывод в чат, права и защита сети.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_pcboard_ui.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local core = read("lua/autorun/sh_grm_pcboard.lua")
local ui   = read("lua/autorun/client/cl_grm_pcboard_ui.lua")

print("\n=== 1. ЯДРО ===")
ok(has(core, 'PB.Version = "1.0.0"'), "модуль версионирован")
ok(has(core, "PB.RegisterProvider"), "блоки справки регистрируются провайдерами")
ok(has(core, 'PB.RegisterProvider("wanted"') and has(core, 'PB.RegisterProvider("military"')
    and has(core, 'PB.RegisterProvider("medical"') and has(core, 'PB.RegisterProvider("covers"'),
    "провайдеры розыска, воинского учёта, медицины и легенд на месте")
ok(has(core, "GRM.Wanted") and has(core, "GRM.Documents") and has(core, "GRM.Property")
    and has(core, "GRM.VehicleDealer") and has(core, "GRM.Diplomas"),
    "данные берутся из существующих модулей, своей базы нет")
ok(has(core, "if not (W and W.Records) then return nil end"),
    "нет модуля на сервере — блок просто не появится")
ok(has(core, "function PB.ResolveAccess"), "уровень считается по цепочке организация→отдел→подотдел→должность")
ok(has(core, 'apply((fac.roles or {})[tostring(role or "")], "должность")'),
    "должность — последняя ступень переопределения")
ok(has(core, "Ловушка Lua"), "разобран случай false в галочках блоков")

print("\n=== 2. УРОВНИ ДОПУСКА ===")
for _, level in ipairs({ "police", "military", "medical", "fire", "justice", "special", "admin" }) do
    ok(has(core, level .. "  = {") or has(core, level .. " = {") or has(core, level .. "   = {")
        or has(core, level .. "    = {") or has(core, level .. "     = {"),
        "уровень " .. level .. " объявлен")
end
ok(has(core, 'levels = { police = true, military = true, justice = true, special = true, admin = true }'),
    "розыск и штрафы — правоохранителям, комендатуре и юстиции")
ok(has(core, 'justice  = { rank = 3, name = "Юстиция"'), "уровень «Юстиция» в таблице уровней")
ok(has(core, 'fire     = { rank = 1, name = "Пожарная служба"'), "уровень «Пожарная служба» в таблице")
ok(has(core, '"none", "fire", "medical", "police", "military", "justice", "special", "admin"'),
    "новые уровни попали в порядок выбора в редакторе")
ok(has(core, 'levels = { fire = true, medical = true, special = true, admin = true }'),
    "медкарта — медикам, пожарным и спецслужбам")
ok(has(core, 'levels = { fire = true, justice = true, special = true, admin = true }'),
    "недвижимость — пожарным (владелец объекта) и юстиции")
ok(has(core, 'levels = { admin = true }'), "служебные данные аккаунта — только администрации")

print("\n=== 3. РП И ЗАЩИТА ОТ АБЬЮЗА ===")
ok(has(core, "local function meAction"), "РП-действие рисуется системой")
ok(has(core, "meStart") and has(core, "meDone"), "два действия: начало запроса и результат")
ok(has(core, "if not (opts.self or hidden) then meAction(actor, s.meStart) end"),
    "скрытый запрос обходится без РП-действия")
ok(has(core, 'return false, "Скрытый запрос доступен только спецслужбам."'),
    "скрытый запрос закрыт для остальных")
ok(has(core, "local function checkLimits"), "есть кулдаун и лимит запросов в минуту")
ok(has(core, "local function writeLog"), "каждый запрос пишется в журнал")
ok(has(core, 'GRM.Audit.Write("pcboard", "query"'), "журнал дублируется в общий аудит")
ok(has(core, 'GRM.Access.Register("pcboard.audit"'), "право на просмотр журнала зарегистрировано")
ok(has(core, "net.Send(actor)"), "справка уходит только запросившему, без broadcast")
ok(not has(core, "net.Broadcast()"), "в модуле нет широковещательных пакетов")

print("\n=== 4. КОМАНДЫ ===")
ok(has(core, 'cmd ~= "/pcboard"') and has(core, '"/пробить"'), "команда и русский псевдоним")
ok(has(core, 'hook.Add("PlayerSay", "GRM_PCBoard_Chat"')
    and has(core, 'hook.Add("PlayerSayTransform", "GRM_PCBoard_ChatEC"'),
    "команда работает и в штатном чате, и в EasyChat")
ok(has(core, 'sub == "журнал"') and has(core, 'sub == "я"') and has(core, 'sub == "авто"'),
    "подкоманды: журнал, я, авто")
ok(has(core, "local function aimTarget"), "цель по прицелу с ограничением дистанции")
ok(has(core, "GRM.Registry"), "поиск по номеру идёт через реестр ID")

print("\n=== 5. НАСТРОЙКА ===")
ok(has(core, "grm_pcboard/access.json") or has(core, 'ACCESS_FILE = DIR .. "/access.json"'),
    "настройки лежат в data/grm_pcboard/access.json")
ok(has(core, "function PB.Normalize"), "любые входные данные приводятся к строгому виду")
ok(has(core, "if not (IsValid(ply) and ply:IsSuperAdmin()) then return end"),
    "настройки правит только суперадмин")
ok(has(core, 'GRM.Boot.OnMapStart("GRM_PCBoard_Load"'), "старт через планировщик GRM.Boot")

print("\n=== 6. ИНТЕРФЕЙС ===")
ok(has(ui, 'hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_PCBoard_Tab"'),
    "вкладка встраивается штатным хуком меню организаций")
ok(has(ui, 'sheet:AddSheet("Госбаза"'), "вкладка называется «Госбаза»")
ok(has(ui, "lp:IsSuperAdmin()"), "вкладку видит только суперадмин")
ok(has(ui, "local function printCard"), "справка печатается в чат")
ok(has(ui, "function PB.OpenCardWindow"), "та же справка открывается окном")
ok(has(ui, 'CreateClientConVar("grm_cl_pcboard_window"'), "окно включается конваром игрока")
ok(has(ui, "ОРГАНИЗАЦИЯ ЦЕЛИКОМ"), "в редакторе есть узел организации")
ok(has(ui, '"Отдел: "') and has(ui, '"Подотдел: "') and has(ui, '"Должность: "'),
    "в редакторе есть отделы, подотделы и должности")
ok(has(ui, '"По уровню"') and has(ui, '"Включить"') and has(ui, '"Выключить"'),
    "галочки блоков имеют три состояния")
ok(has(ui, "Кулдаун, с") and has(ui, "Запросов в минуту") and has(ui, "Время пробития, с"),
    "лимиты настраиваются в интерфейсе")
ok(has(ui, "Только на службе") and has(ui, "Скрытый запрос спецслужбам"),
    "переключатели службы и скрытого запроса")
ok(has(ui, "Провайдеры живут на сервере"), "клиент считает матрицу по присланным данным")
ok(has(ui, "grm_pcboard_log"), "кнопка журнала запросов")

print("\n=== 7. РАЗМЕР И ЧИТАЕМОСТЬ ОКНА (заказ 21.08) ===")
ok(has(ui, "math.Clamp(math.floor(ScrW() * 0.86), 1020, 1900)"),
    "окно настроек тянется под экран, а не фиксировано 1020")
ok(has(ui, "frame:SetSizable(true)"), "размер окна можно менять мышью")
ok(has(ui, "frame:SetMinWidth(1020)"), "минимальный размер не даёт схлопнуть раскладку")
ok(has(ui, "local function elide"), "длинные названия отделов обрезаются с многоточием")
ok(has(ui, "0xC0) == 0x80"), "обрезка идёт по UTF-8, кириллица не рвётся пополам")
ok(has(ui, "подпись поля рисуется НАД полем"), "подписи снизу больше не налезают на ввод")
ok(has(ui, "local function checkField"), "галочки получили явную ширину и видимый текст")
ok(has(ui, 'ScrW() * 0.42'), "окно справки тоже масштабируется под экран")

print(("\nPCBOARD UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
