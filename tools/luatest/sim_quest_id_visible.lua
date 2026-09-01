--[[ Живой прогон отображения ID квеста (заказ владельца 28.08).

     «Надо чтобы квест id выводился куда нибудь в меню квестов.»

     ЧТО БЫЛО НЕ ТАК. ID нигде не показывался: ни в списке квестов, ни в
     шапке студии, ни в журнале игрока. А он нужен постоянно —
     на него ссылаются «предыдущие квесты», команда сброса прогресса и
     ачивка (её ID по умолчанию «quest_<id>»). Единственный способ
     узнать ID был — открыть файл квестов на сервере.

     Стенд проверяет три места вывода и то, что ID можно переименовать,
     не получив расхождения с сервером.

     Запуск: luajit tools/luatest/sim_quest_id_visible.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end
local studio = readf("lua/autorun/client/zz_grm_quest_studio.lua")
local journal = readf("lua/autorun/client/cl_grm_quests.lua")
local server = readf("lua/autorun/sh_grm_quests.lua")

-----------------------------------------------------------------------
print("\n=== 1. ID В ШАПКЕ СТУДИИ ===")
-----------------------------------------------------------------------
--[[ Шапка видна всегда, на любой вкладке — там ID полезнее всего. ]]
local headFn = studio:match("f%.Paint = function.-\n    end") or ""
ok(headFn ~= "", "шапка окна найдена")
ok(headFn:find('"ID: " .. tostring(work.id or "")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ID выводится в шапке студии")
ok(headFn:find("COL.accent", 1, true) ~= nil,
   "и подсвечен цветом, а не теряется в сером тексте")

--[[ Название и ID не должны рисоваться в одной точке — иначе наложатся.
     Проверяем, что у них разные Y. ]]
local titleY = headFn:match('draw%.SimpleText%(head, "GRMQS_Small", w / 2, (%d+)')
local idY = headFn:match('"ID: " %.%. tostring%(work%.id or ""%), "GRMQS_Small", w / 2, (%d+)')
ok(titleY and idY, "у названия и ID заданы координаты", tostring(titleY) .. " / " .. tostring(idY))
ok(titleY and idY and tonumber(idY) > tonumber(titleY),
   "ID нарисован НИЖЕ названия — строки не накладываются",
   tostring(titleY) .. " -> " .. tostring(idY))
ok(idY and tonumber(idY) < 48, "и обе строки внутри шапки высотой 48", tostring(idY))

-----------------------------------------------------------------------
print("\n=== 2. ID В СПИСКЕ КВЕСТОВ ===")
-----------------------------------------------------------------------
--[[ В списке ID нужен, чтобы не открывать каждый квест ради него. ]]
ok(studio:find('draw.SimpleText(tostring(dd.id or ""), "GRMQS_Small", 10, 22, COL.accent)', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ID виден в строке списка квестов")

--[[ Счётчик этапов раньше занимал ту же строку, что теперь ID. Он
     должен был уехать вправо, иначе тексты налезут друг на друга. ]]
ok(studio:find('"GRMQS_Small", w - 10, 22, COL.dim, TEXT_ALIGN_RIGHT', 1, true) ~= nil,
   "счётчик этапов ушёл вправо — не сталкивается с ID")
ok(studio:find('draw.SimpleText(dd.title or dd.id, "GRMQS_Body", 10, 6, COL.text)', 1, true) ~= nil,
   "название поднято, чтобы освободить место под ID")

-- Три текста в строке должны идти на разной высоте или в разных краях.
local rowTitleY = studio:match('draw%.SimpleText%(dd%.title or dd%.id, "GRMQS_Body", 10, (%d+)')
local rowIdY = studio:match('draw%.SimpleText%(tostring%(dd%.id or ""%), "GRMQS_Small", 10, (%d+)')
ok(rowTitleY and rowIdY and tonumber(rowIdY) > tonumber(rowTitleY),
   "ID под названием, а не поверх него",
   tostring(rowTitleY) .. " -> " .. tostring(rowIdY))
ok(rowIdY and tonumber(rowIdY) < 40, "и помещается в строку высотой 40", tostring(rowIdY))

-----------------------------------------------------------------------
print("\n=== 3. ID РЕДАКТИРУЕТСЯ ===")
-----------------------------------------------------------------------
ok(studio:find('field(left, "ID квеста (латиница)", work.id)', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ID можно поменять прямо в студии")

--[[ КЛЮЧЕВОЕ. Сервер чистит ID: приводит к нижнему регистру и заменяет
     всё, кроме латиницы, цифр и _-: на подчёркивание. Если клиент этого
     не делает, автор впишет «Моя Ачивка», сохранит, а на сервере
     окажется другой ID — и ссылки из других квестов сломаются молча. ]]
local serverRule = server:find('local id=string.lower(trim(raw.id,64)):gsub("[^%w_%-%:]","_")', 1, true)
ok(serverRule ~= nil, "правило чистки ID на сервере найдено")
--[[ Проверяем ТЕЛО обработчика поля ID, а не файл целиком: такая же
     чистка есть в блоке ачивки, поэтому поиск по всему файлу проходил
     даже когда обработчик писал значение сырым. ]]
local idHandler = studio:match('iE%.OnChange = function%(s2%).-\n            end') or ""
ok(idHandler ~= "", "обработчик поля ID найден")
ok(idHandler:find('gsub("[^%w_%-%:]", "_")', 1, true) ~= nil,
   "клиент чистит ID теми же правилами — значение не изменится при сохранении")
ok(idHandler:find("string.lower(string.Trim", 1, true) ~= nil,
   "и так же приводит к нижнему регистру")
ok(idHandler:find("work.id = s2:GetValue()", 1, true) == nil,
   "сырое значение в ID не пишется")

-- Воспроизводим правило и сверяем поведение клиента с сервером.
local function sanitize(v)
    return (string.lower((tostring(v or ""):gsub("^%s*(.-)%s*$", "%1"))):gsub("[^%w_%-%:]", "_"))
end
ok(sanitize("Intro_Quest") == "intro_quest", "регистр опускается", sanitize("Intro_Quest"))
ok(sanitize("my quest!") == "my_quest_", "пробелы и знаки заменяются", sanitize("my quest!"))
ok(sanitize("ok-id:2") == "ok-id:2", "разрешённые символы не портятся", sanitize("ok-id:2"))
ok(sanitize("  trim  ") == "trim", "края обрезаются", sanitize("  trim  "))

--[[ Пустой ID сервер отвергает целиком («ID обязателен»), поэтому
     проверка квеста обязана поймать это раньше сохранения. ]]
ok(server:find('if id=="" then return nil,"ID обязателен"', 1, true) ~= nil,
   "сервер отвергает пустой ID — значит валидатор должен предупредить")

-----------------------------------------------------------------------
print("\n=== 4. ID В ЖУРНАЛЕ ИГРОКА ===")
-----------------------------------------------------------------------
--[[ Админу удобнее смотреть ID прямо в игре, не заходя в студию. ]]
ok(journal:find('tostring(d.id or"")', 1, true) ~= nil,
   "ИСПРАВЛЕНО: ID выводится в карточке квеста журнала")
ok(journal:find('(d.category~=""and d.category or"КВЕСТ").."   ·   "', 1, true) ~= nil,
   "он приписан к категории, а не занял отдельную строку — вёрстка не поехала")

-- Категория не должна пропасть ради ID.
local line = journal:match('label%(detail,%(d%.category[^\n]*') or ""
ok(line:find("d.category", 1, true) ~= nil, "категория осталась на месте")
ok(line:find("d.id", 1, true) ~= nil, "и ID рядом с ней")

--[[ У квеста без категории строка не должна начинаться с разделителя. ]]
local function caption(cat, id)
    return ((cat ~= "" and cat) or "КВЕСТ") .. "   ·   " .. tostring(id or "")
end
ok(caption("История", "intro") == "История   ·   intro", "категория и ID вместе",
   caption("История", "intro"))
--[[ Сравниваем началом строки, а не sub(1,5): «КВЕСТ» в UTF-8 занимает
     10 байт, и побайтовая резка давала обрубок. Ошибка была в самой
     проверке, а не в коде. ]]
ok(caption("", "intro"):find("^КВЕСТ") ~= nil,
   "без категории показывается слово КВЕСТ, а не пустота", caption("", "intro"))
ok(caption("", ""):find("КВЕСТ", 1, true) ~= nil, "пустой ID не роняет подпись")

-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
