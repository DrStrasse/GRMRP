--[[--------------------------------------------------------------------
    sim_door_menu_ui — заказ владельца 19.08: редактор категорий владельцев
    дверей (фракции, отделы, подотделы, лица без фракции, широкие настройки)
    и переделка окна «Управление дверью» в стиль GRM.

    Живая логика проверяется в sim_door_categories.lua.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_door_menu_ui.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local core = read("lua/autorun/sh_grm_doors.lua")
local ui   = read("lua/autorun/client/cl_grm_doors_menu.lua")

print("\n=== 1. ПРОФИЛЬ КАТЕГОРИИ (ДАННЫЕ) ===")
ok(has(core, "function D.NormalizeCategory"), "категория нормализуется по единой схеме")
ok(has(core, "version = 4, categories = arr"), "файл категорий поднят до версии 4")
ok(has(core, "departments    = toArray(raw.departments)") and has(core, "subdepartments = toArray(raw.subdepartments)")
    and has(core, "roles          = toArray(raw.roles)"), "в категории есть отделы, подотделы и должности")
ok(has(core, "D.CategoryFlags = {"), "флаги профиля объявлены общим списком")
ok(has(core, 'key = "everyone"') and has(core, 'key = "noFaction"') and has(core, 'key = "canLock"')
    and has(core, 'key = "lockAdminOnly"') and has(core, 'key = "keepLocked"') and has(core, 'key = "allowBuy"'),
    "шесть настроек: все, без фракции, замок, только админ, всегда заперта, приватизация")
ok(has(core, 'public = D.NormalizeCategory({ id = "public", name = "Общественная",'),
    "категория «Общественная» заводится из коробки")

print("\n=== 2. ПРАВИЛА ДОСТУПА ===")
ok(has(core, "function D.CategoryMatch"), "матчинг сотрудника с профилем категории")
ok(has(core, "function D.CategoryCanLock"), "отдельное право на замок")
ok(has(core, "function D.CategoryOfDoor"), "категория двери резолвится в одном месте")
ok(has(core, "actor.categoryLock = ownerCat and D.CategoryCanLock(ownerCat, actor) or false"),
    "право на замок считается для конкретного игрока")
ok(has(core, "lock = super or actor.categoryLock == true"), "матрица допуска слушает профиль категории")
ok(has(core, "if actor.categoryKeepLocked == true and not super then lock = false end"),
    "режим «всегда заперта» перекрывает замок")
ok(has(core, "buy = rec.ownable ~= false and actor.categoryBuy == true"),
    "приватизация категорийной двери — только по флагу")
ok(has(core, "if istable(keepCat) and keepCat.keepLocked == true and not locked then"),
    "принудительное запирание применяется и при прямом вызове LockDoor")
ok(has(core, "local fac, role, dept, sub = playerFactionInfo(ply)"), "актор знает отдел и подотдел")
ok(has(core, 'return name, m.Role, m.Department, tostring(m.Subdepartment or m.Subdept or "")'),
    "подотдел читается из состава организации")

print("\n=== 3. РЕДАКТИРОВАНИЕ ===")
ok(has(core, 'act == "cat_create"') and has(core, 'act == "cat_rename"') and has(core, 'act == "cat_delete"'),
    "создание, переименование и удаление категорий")
ok(has(core, 'act == "cat_flag"'), "переключение флагов профиля")
ok(has(core, 'act == "cat_member"'), "переключение фракций, отделов, подотделов и должностей")
ok(has(core, 'if list ~= "factions" and list ~= "departments" and list ~= "subdepartments" and list ~= "roles" then return end'),
    "принимаются только известные списки — мусор в файл не попадёт")
ok(has(core, 'act == "clear_owner"'), "владельца двери можно сбросить")
ok(has(core, 'if not acc.admin then notify(ply, "Только суперадмин.'), "редактирование категорий закрыто суперадмином")
ok(has(core, "function D.FactionTree"), "дерево организаций собирается для редактора")
ok(has(core, "row.subdepartments[#row.subdepartments + 1]"), "в дереве есть подотделы")
ok(has(core, "catsList[#catsList + 1] = D.NormalizeCategory(c, id)"), "категории уходят клиенту профилем целиком")

print("\n=== 4. ОКНО В СТИЛЕ GRM ===")
ok(ui:find('D.MenuVersion = "2%.%d+%.%d+"') ~= nil, "окно двери вынесено в отдельный модуль и версионировано")
ok(not has(core, 'sheet:AddSheet("Обзор"'), "старое окно на DPropertySheet удалено из ядра")
ok(has(core, "Окно «Управление дверью» переехало в отдельный клиентский модуль"), "в ядре осталась ссылка на новый модуль")
ok(has(ui, "math.Clamp(ScrW() * 0.68, 1000, 1480)"), "окно стало широким")
ok(has(ui, "GRM · УПРАВЛЕНИЕ ДВЕРЬЮ"), "шапка в стиле GRM")
ok(has(ui, "gold     = Color(245, 195, 65)") and has(ui, "sidebar  = Color(12, 15, 22, 255)"), "палитра GRM")
ok(has(ui, "local function addTab"), "боковое меню разделов вместо вкладок Derma")
ok(has(ui, 'addTab("overview"') and has(ui, 'addTab("coowners"') and has(ui, 'addTab("access"')
    and has(ui, 'addTab("categories"') and has(ui, 'addTab("admin"'), "пять разделов, включая редактор категорий")
ok(has(ui, "lastTab") and has(ui, "lastCategory"), "после действия окно возвращается в тот же раздел и категорию")

print("\n=== 5. РЕДАКТОР В ОКНЕ ===")
ok(has(ui, '"departments", fac.name') and has(ui, '"subdepartments", fac.name') and has(ui, '"roles", fac.name')
    and has(ui, '"factions", fac.name'), "чекбоксы организаций, отделов, подотделов и должностей")
ok(has(ui, "D.CategoryFlags or {}"), "флаги рисуются из общего списка, без дублирования")
ok(has(ui, 'action = "cat_flag"') and has(ui, 'action = "cat_member"'), "изменения уходят на сервер")
ok(has(ui, "НАСТРОИТЬ КАТЕГОРИИ"), "из администрирования есть переход в редактор")
ok(has(ui, "Отметьте, кому дверь открывается помимо владельца."), "раздел доступов объясняет себя")

print("\n=== 6. ПРОКРУТКА ОКНА ===")
ok(has(ui, "local baseVScroll = content.OnVScroll") and has(ui, "if baseVScroll then baseVScroll(pnl, offset) end"),
    "OnVScroll не подменяется: холст двигает оригинал, мы только запоминаем позицию")
ok(not ui:find("content%.OnVScroll = function%(_, offset%) lastScroll"),
    "старая подмена (полоса едет — страница стоит) убрана")
ok(has(ui, "if key ~= lastTab then lastScroll = 0 end"),
    "смена раздела не тянет за собой чужую позицию прокрутки")

print("\n=== 6.1 ПОЗИЦИЯ СПИСКА ПРИ ГАЛОЧКАХ ===")
ok(has(ui, "local scrollSilent = false") and has(ui, "if scrollSilent then return end"),
    "программный SetScroll не пишется в память позиции (из-за него список прыгал вверх)")
ok(has(ui, "local function setScroll(value)"), "все программные сдвиги идут через одну функцию")
ok(has(ui, "local wantScroll = lastScroll"), "позиция снимается ДО пересборки вкладки")
ok(has(ui, "local restoreScroll") and has(ui, "restoreScroll = function(tries)"),
    "восстановление с форвард-декларацией (правило замыканий соблюдено)")
ok(has(ui, "content:InvalidateLayout(true)") and has(ui, "restoreScroll(tries - 1)"),
    "позиция дожимается несколько кадров — холст считает высоту после раскладки")
ok(has(ui, 'D.MenuVersion = "2.1.0"'), "версия окна двери поднята")

print("\n=== 7. БИНД ОТКРЫТИЯ ===")
local f4 = read("lua/autorun/sh_grm_f4menu.lua")
ok(has(core, 'hook.Add("ShowSpare1", "GRM_Doors_ServerOverrideF3"'), "сервер открывает меню двери по F3")
ok(has(core, 'hook.Add("ShowSpare1", "GRM_Doors_OverrideF3"'), "клиент открывает меню двери по F3")
ok(not has(core, 'hook.Add("ShowTeam"'), "F2 двери больше не забирают (там тикеты)")
ok(not has(core, 'hook.Add("ShowSpare2"') and not has(core, 'hook.Add("ShowHelp"'),
    "F4 и F1 двери больше не перехватывают")
ok(has(core, 'hook.Remove("ShowTeam", "GRM_Doors_ServerOverrideF2")'),
    "старые перехваты снимаются при перезагрузке файла")
ok(not has(f4, "yieldsToDoor"), "F4-меню больше не уступает прицелу на дверь")

print("\n=== СПИСОК КАТЕГОРИЙ НЕ ПРЫГАЕТ ВВЕРХ ПОСЛЕ ГАЛОЧКИ ===")
ok(has(core, "function D.MenuSignature"), "подпись набора данных считается в общем слое")
ok(has(ui, "f.GRMPatch = function"), "окно умеет обновляться на месте, без пересборки")
ok(has(ui, "if IsValid(f) and f.GRMDoorEnt == ent and isfunction(f.GRMPatch) then"),
    "свежий снимок той же двери НЕ создаёт окно заново")
ok(has(ui, "if structureSame and lastTab == \"categories\" and catRefresh and catRefresh() then"),
    "при смене только галочек правится состояние чекбоксов, а не вкладка")
ok(has(ui, "memberRows[#memberRows + 1] = { list = list, value = value, set = set }"),
    "у каждой галочки есть живая ссылка на обновление")
ok(has(ui, "local function setChecked(on)") and has(ui, "if silent then return end"),
    "программная установка галочки не шлёт действие на сервер (нет петли)")
ok(has(ui, "local keep = IsValid(content.VBar) and content.VBar:GetScroll() or 0"),
    "если вкладку всё же пересобирают — прокрутка запоминается до Clear()")
ok(has(ui, "catRefresh = nil") and has(ui, "-- Старые ссылки на галочки ведут на уже уничтоженные панели."),
    "ссылки сбрасываются при смене вкладки")

print(("\nDOOR MENU UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
