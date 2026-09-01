--[[--------------------------------------------------------------------
    sim_factions_unified_v3.lua
    Тест-стенд для Unified Factions UI v3.0 (все 10 разделов управления,
    кнопки, модалки, подсистемы и интеграция с сервером).
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, msg)
    if v then
        pass = pass + 1
        print("  ok  " .. msg)
    else
        fail = fail + 1
        print("  FAIL " .. msg)
    end
end

print("=== ТЕСТ: Unified Factions UI v3.0 (10 разделов и кнопки) ===")
local uiCode = assert(io.open("lua/autorun/client/cl_grm_factions_unified_ui.lua", "rb")):read("*a")
local facCode = assert(io.open("lua/autorun/sh_factions.lua", "rb")):read("*a")

ok((uiCode:match('UI%.Version = "(%d+)') or "0") + 0 >= 3, "Unified UI не ниже v3.0.0")
ok(uiCode:find('addTabBtn("overview"', 1, true) ~= nil, "Раздел 1: Обзор")
ok(uiCode:find('addTabBtn("members"', 1, true) ~= nil, "Раздел 2: Личный состав")
ok(uiCode:find('addTabBtn("structure"', 1, true) ~= nil, "Раздел 3: Структура и штат")
ok(uiCode:find('addTabBtn("personnel"', 1, true) ~= nil, "Раздел 4: Кадровые дела")
ok(uiCode:find('addTabBtn("access"', 1, true) ~= nil, "Раздел 5: Доступы и связь")
ok(uiCode:find('addTabBtn("gear"', 1, true) ~= nil, "Раздел 6: Вооружение и форма")
ok(uiCode:find('addTabBtn("mask"', 1, true) ~= nil, "Раздел 7: Маскировка")
ok(uiCode:find('addTabBtn("curfew"', 1, true) ~= nil, "Раздел 8: Комендантский час")
ok(uiCode:find('addTabBtn("finance"', 1, true) ~= nil, "Раздел 9: Казна и финансы")
ok(uiCode:find('addTabBtn("create"', 1, true) ~= nil, "Раздел 10: Создать организацию")

ok(uiCode:find("+ Пригласить игрока", 1, true) ~= nil, "Кнопка приглашения сотрудника")
ok(uiCode:find("Изменить должность", 1, true) ~= nil, "Кнопка изменения должности")
ok(uiCode:find("Перевести в отдел / подотдел", 1, true) ~= nil, "Кнопка перевода в отдел/подотдел")
ok(uiCode:find("Уволить", 1, true) ~= nil, "Кнопка увольнения")

ok(uiCode:find("+ Добавить", 1, true) ~= nil, "Кнопка добавления должности")
ok(uiCode:find("+ Создать новый отдел", 1, true) ~= nil, "Кнопка создания отдела")
ok(uiCode:find("+ Подотдел", 1, true) ~= nil, "Кнопка добавления подотдела")
ok(uiCode:find("skinListView", 1, true) ~= nil, "Кастомная стилизация DListView без белых шапок")

ok(facCode:find("OpenUnifiedFactionsMenu", 1, true) ~= nil, "sh_factions перенаправляет на Unified UI")

print(string.format("\nРЕЗУЛЬТАТ: Пройдено проверок: %d/%d (провалов: %d)", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
print("ALL UNIFIED UI V3 ASSERTIONS PASSED!")
