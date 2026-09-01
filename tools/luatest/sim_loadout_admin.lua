--[[--------------------------------------------------------------------
    sim_loadout_admin — меню одежды/вооружения фракций (GRM Loadout Admin)
    и поддержка подотделов на сервере.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_loadout_admin.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ui    = read("lua/autorun/client/cl_grm_faction_loadout_admin.lua")
local fixes = read("lua/autorun/sh_faction_fixes.lua")

print("\n=== 1. НОВОЕ МЕНЮ В СТИЛЕ GRM ===")
ok(ui:find("GRM.LoadoutAdmin", 1, true) ~= nil, "модуль GRM.LoadoutAdmin")
ok(ui:find('LA.Version = "1.0.0"', 1, true) ~= nil, "версия 1.0.0")
ok(ui:find("GRMLoad_Title", 1, true) and ui:find("GRMLoad_Body", 1, true), "свои шрифты GRM")
ok(ui:find("bg     = Color(16, 20, 28, 252)", 1, true) ~= nil, "палитра как в остальных меню сборки")
ok(ui:find("ВООРУЖЕНИЕ ФРАКЦИЙ", 1, true) and ui:find("ОДЕЖДА ФРАКЦИЙ", 1, true),
    "оба окна: одежда и вооружение")
ok(ui:find("frame:ShowCloseButton(false)", 1, true) ~= nil, "своя рамка вместо стандартной DFrame")
ok(ui:find("GRM.Sound.UI", 1, true) ~= nil, "звуки через общий слой GRM.Sound")
ok(ui:find("GRM.UI.Track", 1, true) ~= nil, "окна регистрируются в реестре UI")

print("\n=== 2. СТРУКТУРА ФРАКЦИИ В ДЕРЕВЕ ===")
ok(ui:find("ДОЛЖНОСТИ (РАНГИ)", 1, true) ~= nil, "секция должностей (рангов)")
ok(ui:find("ОТДЕЛЫ И ПОДОТДЕЛЫ", 1, true) ~= nil, "секция отделов и подотделов")
ok(ui:find('scope = "subdepartment"', 1, true) ~= nil, "узлы подотделов редактируемы")
ok(ui:find("ПОДОТДЕЛЫ БЕЗ ОТДЕЛА", 1, true) ~= nil, "подотделы без родителя не теряются")
ok(ui:find("fd.roleNames", 1, true) and ui:find("fd.deptNames", 1, true),
    "показываются публичные названия должностей и отделов")
ok(ui:find('" • ключ "', 1, true) ~= nil, "рядом виден системный ключ")
ok(ui:find("sub.parent == deptKey", 1, true) ~= nil, "подотдел вложен в свой отдел")
ok(ui:find("%d должн. • %d отд. • %d подотд.", 1, true) ~= nil, "в списке организаций видна их структура")
ok(ui:find("Приоритет выдачи: подотдел", 1, true) ~= nil, "в шапке показан приоритет выдачи")

print("\n=== 3. РЕДАКТОРЫ ===")
ok(ui:find("local function buildModelsEditor", 1, true) ~= nil, "редактор моделей")
ok(ui:find("DAdjustableModelPanel", 1, true) ~= nil, "живой предпросмотр модели")
ok(ui:find("local function openEntryEditor", 1, true) ~= nil, "редактор пути/скина/бодигрупп")
ok(ui:find("ent:GetBodygroupCount(i)", 1, true) ~= nil, "бодигруппы подтягиваются из самой модели")
ok(ui:find("local function buildWeaponsEditor", 1, true) ~= nil, "редактор оружия")
ok(ui:find("local function weaponCatalog", 1, true) and ui:find("weaponCatalogCache", 1, true),
    "каталог оружия строится один раз и кэшируется")
ok(ui:find("Поиск по названию или классу", 1, true) ~= nil, "поиск по каталогу")
ok(ui:find("Поиск организации", 1, true) ~= nil, "поиск по организациям")
ok(ui:find("local function keepScroll", 1, true) ~= nil, "прокрутка не сбрасывается при сохранении")
ok(select(2, ui:gsub("keepScroll%(", "")) >= 3, "сохранение прокрутки применено во всех списках")

print("\n=== 4. СТАРЫЕ ТОЧКИ ВХОДА ВЕДУТ В НОВОЕ МЕНЮ ===")
ok(fixes:find("if GRM.LoadoutAdmin and GRM.LoadoutAdmin.OpenModels then", 1, true) ~= nil,
    "/models_admin открывает новое меню")
ok(fixes:find("if GRM.LoadoutAdmin and GRM.LoadoutAdmin.OpenWeapons then", 1, true) ~= nil,
    "/weapons_admin открывает новое меню")
ok(fixes:find("pendingModelsCb = function(data)", 1, true) ~= nil,
    "старое окно сохранено как фолбэк")
ok(ui:find("function LA.OpenModels", 1, true) and ui:find("function LA.OpenWeapons", 1, true),
    "публичные функции открытия")
ok(ui:find('net.Receive("FactionsExt_AdminModelsData"', 1, true) == nil
    and ui:find("net.Receive(NET_MODELS_DATA", 1, true) ~= nil,
    "используются те же сетевые каналы, что и раньше")

print("\n=== 5. СЕРВЕР: ПОДОТДЕЛЫ В ДАННЫХ И СОХРАНЕНИИ ===")
ok(fixes:find("local function factionStructureFor", 1, true) ~= nil, "единый сборщик структуры для обоих меню")
ok(fixes:find("subList = st.subList", 1, true) ~= nil, "список подотделов уходит клиенту")
ok(fixes:find("roleNames = st.roleNames", 1, true) and fixes:find("deptNames = st.deptNames", 1, true),
    "публичные названия должностей и отделов уходят клиенту")
ok(select(2, fixes:gsub('subdepartments = st%.subdepartments', "")) == 2,
    "и модели, и оружие подотделов передаются")
ok(fixes:find('f.Subdepartments[key].models = models', 1, true) ~= nil, "сохранение моделей подотдела")
ok(fixes:find('f.Subdepartments[key].weapons = weapons', 1, true) ~= nil, "сохранение оружия подотдела")
ok(fixes:find("applyWeaponsToTargetGroup(factionName, nil, nil, key)", 1, true) ~= nil,
    "оружие подотдела сразу выдаётся его сотрудникам")
ok(fixes:find("local subMatch =", 1, true) ~= nil, "выдача фильтрует по подотделу")

print("\n=== 6. СЕРВЕР: ПОДОТДЕЛ УЧАСТВУЕТ В ВЫДАЧЕ ===")
ok(fixes:find("Приоритет: ПОДОТДЕЛ (самый частный уровень) → роль → отдел → фракция", 1, true) ~= nil,
    "модели: приоритет описан в коде")
ok(fixes:find("f.Subdepartments[sub].models) and #f.Subdepartments[sub].models > 0", 1, true) ~= nil,
    "модели подотдела читаются при спавне")
ok(fixes:find("f.Subdepartments[sub].weapons) and #f.Subdepartments[sub].weapons > 0", 1, true) ~= nil,
    "оружие подотдела читается при выдаче")
ok(fixes:find("Приоритет: ПОДОТДЕЛ → отдел → роль → фракция", 1, true) ~= nil,
    "оружие: исторический порядок отдел>роль сохранён, подотдел добавлен сверху")

print(("\nLOADOUT ADMIN: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
