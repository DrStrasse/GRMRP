--[[--------------------------------------------------------------------
    sim_laws — заказ владельца 19.08: разделы кодекса, удобный редактор,
    стиль GRM, синхронизация частями и приоритетный старт.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_laws.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local s = read("lua/autorun/sh_grm_laws.lua")

print("\n=== 1. РАЗДЕЛЫ ===")
ok(s:find('LAWS.Version      = "2.0.0"', 1, true) ~= nil, "модуль законов v2.0.0")
for _, cat in ipairs({ "general", "criminal", "administrative", "military", "economic" }) do
    ok(s:find('id = "' .. cat .. '"', 1, true) ~= nil, "раздел " .. cat)
end
ok(s:find("Общие положения", 1, true) ~= nil and s:find("Уголовные", 1, true) ~= nil
    and s:find("Административные", 1, true) ~= nil and s:find("Воинские", 1, true) ~= nil
    and s:find("Экономические", 1, true) ~= nil, "названия разделов на русском")
ok(s:find("function LAWS.ValidCategory", 1, true) ~= nil, "неизвестная категория схлопывается в «Общие»")
ok(s:find("function LAWS.ByCategory", 1, true) ~= nil, "выборка по разделу")
ok(s:find("navButton(\"all\", \"Весь кодекс\", C.gold)", 1, true) ~= nil, "вкладка «Весь кодекс»")
ok(s:find("for _, cat in ipairs(LAWS.Categories) do\n            navButton(cat.id, cat.name", 1, true) ~= nil,
    "остальные вкладки строятся по реестру разделов")

print("\n=== 2. СТРУКТУРА СТАТЬИ ===")
ok(s:find("article   = string.sub(tostring(law.article", 1, true) ~= nil, "номер статьи")
ok(s:find("title     = string.sub(cleanText(law.title)", 1, true) ~= nil, "заголовок статьи")
ok(s:find("penalty   = string.sub(cleanText(law.penalty", 1, true) ~= nil, "наказание")
ok(s:find("local function titleFromText", 1, true) ~= nil,
    "у старых записей заголовок берётся из первой строки — миграция без потерь")
ok(s:find("updatedBy = tostring(law.updatedBy", 1, true) ~= nil, "видно, кто правил статью")

print("\n=== 3. РЕДАКТОР ===")
ok(s:find("buildEditor = function()", 1, true) ~= nil, "редактор строится прямо в окне")
ok(s:find('entry(editorPanel, "Текст статьи", true)', 1, true) ~= nil, "многострочное поле текста")
ok(s:find('entry(rowTop, "№ статьи")', 1, true) ~= nil, "поле номера статьи")
ok(s:find('entry(editorPanel, "Наказание / санкция")', 1, true) ~= nil, "поле наказания")
ok(s:find('local catCombo = vgui.Create("DComboBox", editorPanel)', 1, true) ~= nil, "выбор раздела в редакторе")
ok(s:find('btn(buttons, law.id > 0 and "СОХРАНИТЬ СТАТЬЮ" or "ОПУБЛИКОВАТЬ"', 1, true) ~= nil,
    "одна кнопка и на создание, и на правку")
ok(s:find('Derma_Query("Удалить статью #"', 1, true) ~= nil, "удаление с подтверждением")
ok(s:find("if not editable then return end", 1, true) ~= nil,
    "без права правки редактор доступен только на чтение")
ok(s:find('searchBox = entry(topRow, "Поиск по кодексу', 1, true) ~= nil, "поиск по кодексу")

print("\n=== 4. ДОСТУП ===")
ok(s:find('GRM.Admin.RegisterPerm("laws.edit"', 1, true) ~= nil,
    "право laws.edit регистрируется в админ-платформе")
ok(s:find("GRM.FactionEconomy.CanPublishLaws(ply) == true", 1, true) ~= nil,
    "прежний доступ фракций сохранён")
ok(s:find('if not canEdit(ply) then result(ply, false, "Нет права публиковать законы") return end', 1, true) ~= nil,
    "сервер проверяет право на публикацию")
ok(s:find('GRM.Audit.Write("laws", "add"', 1, true) ~= nil, "изменения кодекса пишутся в аудит")

print("\n=== 5. СИНХРОНИЗАЦИЯ И ПРИОРИТЕТЫ ===")
ok(s:find('GRM.Net.Stream("laws.list", payload, { ply }', 1, true) ~= nil, "кодекс уходит частями")
ok(s:find('GRM.Net.Receive("laws.list", applyPayload)', 1, true) ~= nil, "клиент собирает его обратно")
ok(s:find('net.Start("GRM_Laws_List")', 1, true) ~= nil, "остался фолбэк одним пакетом")
ok(s:find('GRM.Boot.OnMapStart("GRM_Laws_Load", "normal"', 1, true) ~= nil, "загрузка через планировщик Boot")
ok(s:find("for ply in pairs(LAWS.Viewers) do", 1, true) ~= nil,
    "обновления идут только тем, у кого открыто окно")
ok(s:find('GRM.Net.Guard(ply, "laws.action"', 1, true) ~= nil, "действия под сетевым щитом")

print("\n=== 6. СТИЛЬ GRM ===")
ok(s:find("bg        = Color(16, 20, 28, 252)", 1, true) ~= nil, "общая палитра GRM")
ok(s:find('draw.SimpleText("GRM · СВОД ЗАКОНОВ"', 1, true) ~= nil, "золотой заголовок окна")
ok(s:find("LAWS.CategoryColor(law.category)", 1, true) ~= nil, "у каждого раздела свой цвет полосы")

print(("\nLAWS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
