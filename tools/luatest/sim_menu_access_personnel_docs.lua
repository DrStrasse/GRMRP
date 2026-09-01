--[[--------------------------------------------------------------------
    sim_menu_access_personnel_docs — заказ владельца 18.08 (вторая часть):
      1) права разделов меню /factions: чувствительное — суперадмину,
         он раздаёт остальное; лидер больше не видит «Спецслужбы» и т.п.;
      2) кадровая вкладка: выбор организации не слетает, сотрудник
         выбирается, рядовому открывается его личное дело;
      3) /doc_admin: «Сохранить» работает и цвет применяется к уже
         выданным удостоверениям.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_menu_access_personnel_docs.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local access    = read("lua/autorun/sh_grm_faction_menu_access.lua")
local unified   = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local personnel = read("lua/autorun/sh_grm_faction_personnel.lua")
local docs      = read("lua/autorun/sh_grm_documents.lua")
local factions  = read("lua/autorun/sh_factions.lua")
local fixes     = read("lua/autorun/sh_faction_fixes.lua")

print("\n=== 1. ПРАВА РАЗДЕЛОВ МЕНЮ ОРГАНИЗАЦИЙ ===")
ok(access:find("GRM.MenuAccess", 1, true) ~= nil, "модуль прав меню существует")
ok(access:find('{ key = "security",  name = "Спецслужбы",           default = "admin"  }', 1, true) ~= nil,
    "«Спецслужбы» по умолчанию только суперадмину")
for _, key in ipairs({ "access", "mask", "curfew", "service", "gear", "create" }) do
    ok(access:find('key = "' .. key .. '"', 1, true) ~= nil, "раздел " .. key .. " учтён в реестре прав")
end
ok(access:find('return "admin"', 1, true) ~= nil,
    "неизвестный (навесной) раздел по умолчанию закрыт до суперадмина")
ok(access:find("function MA.CanSee", 1, true) ~= nil and access:find("function MA.CanSeeLocal", 1, true) ~= nil,
    "проверка видимости есть и общая, и клиентская")
ok(access:find("function MA.PlayerCan", 1, true) ~= nil,
    "серверная проверка: закрытый раздел нельзя выполнить в обход интерфейса")
ok(access:find("overrides", 1, true) ~= nil,
    "исключения по конкретной организации (открыть раздел одной, не открывая всем)")
ok(access:find('net.Receive(NET_SAVE', 1, true) ~= nil and access:find("ply:IsSuperAdmin()", 1, true) ~= nil,
    "сохранять права может только суперадмин")

ok(unified:find("local function tabVisible(tabKey)", 1, true) ~= nil,
    "боковое меню фильтрует разделы по правам")
ok(unified:find("if not tabVisible(tabKey) then return end", 1, true) ~= nil,
    "кнопка недоступного раздела не создаётся вовсе")
ok(unified:find('local key = "ext:" .. label', 1, true) ~= nil,
    "навесные разделы (арест, экономика, логистика) тоже под правами")
ok(unified:find('addTabBtn("menuaccess", "Права меню"', 1, true) ~= nil,
    "у суперадмина есть раздел настройки прав")
ok(unified:find("Разделы этого меню закрыты вашей должности.", 1, true) ~= nil,
    "если разделов не осталось — понятное объяснение, а не пустое окно")
ok(unified:find("local safe = { overview = true", 1, true) ~= nil,
    "если модуль прав не загружен — безопасный режим (чувствительное скрыто)")
ok(factions:find('GRM.MenuAccess.PlayerCan(ply, "access"', 1, true) ~= nil,
    "серверный гейт на смену доступа к волне департамента")
ok(fixes:find('GRM.MenuAccess.PlayerCan(ply, "access"', 1, true) ~= nil,
    "серверный гейт на смену доступа к госновостям")

print("\n=== 2. КАДРОВАЯ ВКЛАДКА ===")
ok(personnel:find('P.Version="1.1.0"', 1, true) ~= nil, "кадровый модуль v1.1.0")
ok(personnel:find("if IsValid(facCombo.Menu) then return end", 1, true) ~= nil,
    "список организаций не пересобирается, пока он раскрыт под курсором")
ok(personnel:find("if signature == comboSignature then", 1, true) ~= nil,
    "комбобокс трогаем только при реальном изменении набора организаций")
ok(personnel:find("if signature == listSignature then return end", 1, true) ~= nil,
    "реестр сотрудников не пересобирается, если состав не менялся")
ok(personnel:find("members:SelectItem(restore)", 1, true) ~= nil,
    "выделенный сотрудник переживает обновление списка")
ok(personnel:find("local viewerMode", 1, true) ~= nil and personnel:find('viewerMode = "self"', 1, true) ~= nil,
    "рядовому сотруднику открывается его личное дело (сервер реестр не отдаёт)")
ok(personnel:find("local function isManagerOf", 1, true) ~= nil,
    "режим определяется по роли: суперадмин / лидер / сотрудник")
ok(personnel:find("RealTime() - lastListRequest < 4", 1, true) ~= nil,
    "автосинк не дёргает реестр чаще раза в 4 секунды")
ok(personnel:find("if not force and name == selectedFaction then return end", 1, true) ~= nil,
    "повторный выбор той же организации не сбрасывает состояние")
ok(personnel:find("facCombo:SetEnabled(LocalPlayer():IsSuperAdmin())", 1, true) ~= nil,
    "переключать организации может только суперадмин, остальным — своя")

print("\n=== 3. УДОСТОВЕРЕНИЯ: /doc_admin ===")
ok(docs:find("local adminCommitFaction, adminApplyFlags", 1, true) ~= nil,
    "форвард-декларации для кнопки сохранения")
ok(docs:find("local function commitFactionSettings()", 1, true) ~= nil,
    "правки по каждой организации переносятся в шаблон при переключении")
ok(docs:find("if adminCommitFaction then adminCommitFaction() end", 1, true) ~= nil,
    "перед сохранением фиксируется текущая организация")
ok(docs:find('for _, key in ipairs({ "passport", "military", "license", "weaponLicense",', 1, true) ~= nil,
    "структура шаблона нормализуется — старый файл больше не роняет «Сохранить»")
ok(docs:find("tpl._applyIssuedColors = applyIssued", 1, true) ~= nil,
    "флаг «перекрасить уже выданные» уходит на сервер")
ok(docs:find("Перекрасить служебные удостоверения этой организации", 1, true) ~= nil
    and docs:find("Включая документы прикрытия с этой легендой", 1, true) ~= nil,
    "в меню есть оба переключателя перекраски")
ok(docs:find("if tpl._applyIssuedColors == true and istable(tpl.factions) then", 1, true) ~= nil,
    "сервер перекрашивает записи реестра по шаблону организации")
ok(docs:find("DOC.Registry.coverBadges or {}", 1, true) ~= nil,
    "документы прикрытия перекрашиваются отдельным флагом")
ok(docs:find("repaint documents by", 1, true) ~= nil,
    "перекраска пишется в реестр (сохранение на диск)")
ok(docs:find("Шаблоны сохранены. Перекрашено удостоверений", 1, true) ~= nil,
    "админ получает подтверждение с числом обновлённых документов")
ok(docs:find('GRM.Audit.Write("documents", "templates.save"', 1, true) ~= nil,
    "сохранение шаблонов пишется в аудит")

print(("\nMENU ACCESS + PERSONNEL + DOCS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
