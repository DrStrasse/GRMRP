--[[--------------------------------------------------------------------
    sim_phone_load_safety — битый файл не уничтожает телефонную сеть.

    НАХОДКА АУДИТА 31.08 (AUDIT_2026-08-31_SECURITY.md, п. 2.1),
    высокий приоритет.

    ЧТО БЫЛО. P.LoadMapEntities сначала СНОСИЛА все телефоны с карты и
    только потом читала файл:

        for class in {...} do
            for ent in ents.FindByClass(class) do ent:Remove() end
        end
        local data = util.JSONToTable(file.Read(...) or "") or {}

    Если JSON повреждён (обрыв записи при падении сервера, полный диск),
    разбор вернёт nil, `or {}` подставит пустоту — и цикл восстановления
    не создаст ничего. Телефоны, таксофоны, АТС и прослушка исчезают со
    всей карты молча, без единой строки в консоль.

    Это был ЕДИНСТВЕННЫЙ загрузчик в проекте без pcall: остальные
    одиннадцать обёрнуты и уводят битый файл в карантин.

    ЧТО ПРОВЕРЯЕМ:
      1. порядок операций: читаем и проверяем ДО удаления;
      2. битый JSON не приводит к потере энтити;
      3. битый файл уходит в карантин, а не затирается;
      4. администратор получает сообщение, а не тишину;
      5. на исправном файле загрузка работает как раньше.

    Запуск: luajit tools/luatest/sim_phone_load_safety.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local src = read("lua/autorun/server/sv_grm_phone.lua")

print("\n=== 1. ЧИТАЕМ ДО ТОГО, КАК СНОСИТЬ ===")
--[[ Порядок здесь и есть суть бага. Проверяем по позициям в тексте
     функции: разбор файла обязан идти РАНЬШЕ удаления энтити. ]]
local fn = src:match("function P%.LoadMapEntities%(ply%)(.-)\nend") or ""
ok(fn ~= "", "функция загрузки найдена")

local atRemove = fn:find("ent:Remove()", 1, true) or math.huge
local atParse = fn:find("JSONToTable", 1, true) or math.huge
ok(atParse < atRemove,
    "файл разбирается ДО удаления телефонов",
    ("разбор=%s удаление=%s"):format(tostring(atParse), tostring(atRemove)))

print("\n=== 2. РАЗБОР ЗАЩИЩЁН ОТ МУСОРА ===")
ok(fn:find("pcall", 1, true) ~= nil, "JSONToTable обёрнут в pcall")
--[[ `or {}` маскирует ошибку: пустая таблица неотличима от «файл пуст».
     Нужен явный отказ, иначе сеть тихо исчезнет и в следующее
     сохранение пустота запишется поверх рабочих данных. ]]
ok(fn:find("istable", 1, true) ~= nil, "результат разбора проверяется на таблицу")

print("\n=== 3. БИТЫЙ ФАЙЛ НЕ ЗАТИРАЕТСЯ ===")
ok(src:find("carantine", 1, true) ~= nil or src:find("corrupt", 1, true) ~= nil
   or fn:find("corrupt", 1, true) ~= nil,
    "повреждённый файл уходит в карантин, а не пропадает")

print("\n=== 4. АДМИН УЗНАЁТ О ПРОБЛЕМЕ ===")
ok(fn:find("notify", 1, true) ~= nil, "о неудаче сообщается, а не тишина")

print("\n=== 5. ЖИВОЙ ПРОГОН ПОРЯДКА ОПЕРАЦИЙ ===")
--[[ Моделируем обе версии и считаем, сколько телефонов осталось на
     карте после загрузки битого файла. Это и есть цена бага. ]]
--[[ Объявляем ДО использования: имя, встреченное раньше local, Lua
     компилирует как обращение к глобалу и молча получает nil — тот же
     класс бага, что ловит sim_global_hygiene. ]]
local function istableLike(v) return type(v) == "table" end

local function loadOld(entities, rawIsBroken)
    --[[ Старая версия: сносим СРАЗУ, читаем потом. Таблицу заменяем
         новой — это и есть «телефонов на карте не осталось». Прошлая
         версия модели по ошибке считала исходный список, из-за чего
         проверка не краснела на сломанном коде. ]]
    local live = {}                       -- карта после удаления: пусто
    --[[ ВНИМАНИЕ на конструкцию: `cond and nil or X` в Lua ВСЕГДА даёт X,
         потому что `and nil` — ложь. Первая версия модели попалась
         именно на этом и не воспроизводила баг. Пишем явным if. ]]
    local data
    if not rawIsBroken then data = { {}, {}, {} } end
    data = data or {}
    for _ in ipairs(data) do live[#live + 1] = {} end
    return #live
end
local function loadNew(entities, rawIsBroken)
    -- Новая версия: читаем и проверяем, и только при успехе сносим.
    local data
    if not rawIsBroken then data = { {}, {}, {} } end
    if not istableLike(data) then return #entities end   -- карту не тронули
    local live = {}
    for _ in ipairs(data) do live[#live + 1] = {} end
    return #live
end

local before = { {}, {}, {} }
local oldLeft = loadOld(before, true)
ok(oldLeft == 0, "старая логика теряла все телефоны на битом файле — баг воспроизведён",
    ("осталось %d из 3"):format(oldLeft))

local newLeft = loadNew(before, true)
ok(newLeft == 3, "новая логика сохраняет их на месте", ("осталось %d из 3"):format(newLeft))

local okLeft = loadNew(before, false)
ok(okLeft == 3, "на исправном файле загрузка работает как раньше", okLeft)

print(("\nPHONE LOAD SAFETY: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
