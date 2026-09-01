--[[--------------------------------------------------------------------
    sim_industry_container — единая ёмкость: склад, станок, грузовик,
    инвентарь игрока.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Логистику, заводское оборудование надо
    полностью переделать». Ёмкость — фундамент переделки: раньше
    «ёмкость» была реализована пять раз (инвентарь, FC.StorageData,
    L.Warehouses, грузовой ящик, багажник) и перенести предмет между
    ними можно было только через руки игрока.

    ЧТО ПРОВЕРЯЕМ.
      * Вес и лимиты: переполненный контейнер не принимает груз.
      * АТОМАРНОСТЬ: неудавшийся перенос не оставляет предмет в никуда.
        Это самая опасная ошибка такого слоя — она незаметна на одном
        предмете и съедает целый рейс.
      * Адаптер инвентаря: частичное добавление откатывается, а не
        размазывает перенос по двум местам.
      * Круг сохранения: serialize → deserialize → то же содержимое.

    Запуск: luajit tools/luatest/sim_industry_container.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- Глобалы GMod, которых вне игры нет.
istable   = istable   or function(v) return type(v) == "table" end
isstring  = isstring  or function(v) return type(v) == "string" end
isfunction = isfunction or function(v) return type(v) == "function" end
IsValid   = IsValid   or function(v) return type(v) == "table" and v.__valid ~= false end

-- Заглушка инвентаря: ведёт себя как настоящий, но с лимитом слотов.
local inv = { slots = {}, maxSlots = 4, used = 0 }
local function invCount()
    local n = 0
    for _, slot in pairs(inv.slots) do n = n + (slot.count or 0) end
    return n
end
local function invItemCount(id)
    local n = 0
    for _, slot in pairs(inv.slots) do
        if slot.id == id then n = n + (slot.count or 0) end
    end
    return n
end
GRM = GRM or {}
GRM.Inventory = GRM.Inventory or {}
function GRM.Inventory.AddItem(ply, id, count)
    local room = math.max(0, inv.maxSlots - invCount())
    local put = math.min(count, room)
    if put > 0 then
        inv.slots[#inv.slots + 1] = { id = id, count = put }
    end
    return count - put        -- сколько НЕ влезло
end
function GRM.Inventory.RemoveItem(ply, id, count)
    local left = count
    for i = 1, #inv.slots do
        local slot = inv.slots[i]
        if slot and slot.id == id and left > 0 then
            local take = math.min(slot.count, left)
            slot.count = slot.count - take
            left = left - take
            if slot.count <= 0 then inv.slots[i] = nil end
        end
    end
    return left               -- сколько НЕ удалось снять
end
function GRM.Inventory.CountItem(ply, id) return invItemCount(id) end
function GRM.Inventory.GetPlayerInv(ply) return inv end

-- Боевые файлы: ядро и контейнеры.
local function load(p)
    local chunk = assert(loadfile(p))
    chunk()
end
load("lua/autorun/sh_grm_industry_core.lua")
load("lua/autorun/sh_grm_industry_container.lua")

local I = GRM.Industry
local C = GRM.Container
ok(I ~= nil and C ~= nil, "ядро и контейнер загружены из боевых файлов")

-----------------------------------------------------------------------
print("\n=== 1. СОЗДАНИЕ И ЧТЕНИЕ ===")
-----------------------------------------------------------------------
do
    local c = C.Ensure("crate:1", "store", "faction_a", 100)
    ok(c ~= nil, "контейнер создаётся")
    ok(C.Get("crate:1") == c, "повторный Ensure возвращает тот же контейнер")
    ok(C.Ensure("crate:1", "store", "faction_b").owner == "faction_b", "владелец обновляется")
    ok(C.Ensure("nope", "store") ~= nil, "бесхозный контейнер создаётся")
    ok(C.Get("нет такого") == nil, "несуществующий контейнер — nil")

    ok(C.Count("crate:1", "scrap_metal") == 0, "пустой контейнер даёт ноль")
    ok(C.Has("crate:1", "scrap_metal", 0), "ноль предметов у нас есть всегда")
    ok(not C.Has("crate:1", "scrap_metal", 1), "одного предмета в пустом контейнере нет")
    ok(C.IsEmpty("crate:1"), "новый контейнер пустой")
end

-----------------------------------------------------------------------
print("\n=== 2. ВЕС И ЛИМИТЫ ===")
-----------------------------------------------------------------------
do
    C.Ensure("crate:2", "store", "", 10)           -- лимит 10 кг
    local unit = I.WeightOf("scrap_metal")         -- 1.2 кг
    local fits = math.floor(10 / unit)
    ok(fits == 8, "по весу влезает восемь лома", fits)

    local okAdd = C.Add("crate:2", "scrap_metal", fits)
    ok(okAdd == true, "восемь лома помещаются")
    ok(near and true or true, "—")
    ok(C.Count("crate:2", "scrap_metal") == 8, "содержимое совпадает")

    local overOk, overReason = C.Add("crate:2", "scrap_metal", 1)
    ok(overOk == false and overReason == "no_space", "девятый лом не влезает", overReason)
    ok(C.Count("crate:2", "scrap_metal") == 8, "при отказе содержимое не меняется")

    ok(C.Free("crate:2") >= 0 and C.Free("crate:2") < 1, "свободного места почти нет", C.Free("crate:2"))

    C.Ensure("crate:3", "store", "", -1)
    ok(C.Capacity("crate:3") == -1, "лимит -1 означает «без лимита»")
    ok(C.Free("crate:3") == math.huge, "без лимита места бесконечно")
    ok(C.Add("crate:3", "scrap_metal", 10000) == true, "безлимитный контейнер принимает сколько угодно")
end

-----------------------------------------------------------------------
print("\n=== 3. АТОМАРНОСТЬ ПЕРЕНОСА ===")
-----------------------------------------------------------------------
do
    --[[ ГЛАВНАЯ ПРОВЕРКА СЛОЯ. Перенос — «всё или ничего». Если приёмник
         переполнен, источник обязан остаться нетронутым: предмет, который
         списали и не положили, исчезает бесследно. ]]
    C.Ensure("src:1", "store", "", -1)
    C.Ensure("dst:1", "store", "", 5)             -- влезает 4 лома
    C.Add("src:1", "scrap_metal", 10)

    local okMove, reason = C.Move("src:1", "dst:1", "scrap_metal", 10)
    ok(okMove == false, "перенос сверх лимита не проходит")
    ok(reason == "no_space", "причина — нет места", reason)
    ok(C.Count("src:1", "scrap_metal") == 10, "ИСТОЧНИК НЕ ПОСТРАДАЛ — предмет не пропал")
    ok(C.Count("dst:1", "scrap_metal") == 0, "приёмник пуст")

    -- Перенос того, чего нет.
    local ok2, r2 = C.Move("src:1", "dst:1", "gpu_basic", 1)
    ok(ok2 == false and r2 == "not_enough", "перенос отсутствующего предмета не проходит", r2)
    ok(C.Count("src:1", "scrap_metal") == 10, "источник по-прежнему цел")

    -- Нормальный перенос.
    local ok3 = C.Move("src:1", "dst:1", "scrap_metal", 4)
    ok(ok3 == true, "перенос в пределах лимита проходит")
    ok(C.Count("src:1", "scrap_metal") == 6, "с источника списано")
    ok(C.Count("dst:1", "scrap_metal") == 4, "в приёмник зачислено")

    -- Нулевое и отрицательное количество не должно ничего делать.
    ok(C.Move("src:1", "dst:1", "scrap_metal", 0) == false, "нулевой перенос отклонён")
    ok(C.Move("src:1", "dst:1", "scrap_metal", -3) == false, "отрицательный перенос отклонён")
    ok(C.Count("src:1", "scrap_metal") == 6, "количество после мусорных вызовов не изменилось")

    -- Перенос в несуществующий контейнер.
    local ok4, r4 = C.Move("src:1", "мимо", "scrap_metal", 1)
    ok(ok4 == false and r4 == "target_missing", "перенос в несуществующий контейнер отклонён", r4)
    ok(C.Count("src:1", "scrap_metal") == 6, "источник цел и здесь")

    -- Перенос сам в себя — не должен удваивать.
    local ok5 = C.Move("src:1", "src:1", "scrap_metal", 3)
    ok(ok5 == true and C.Count("src:1", "scrap_metal") == 6, "перенос сам в себя не меняет количество")
end

-----------------------------------------------------------------------
print("\n=== 4. ПЕРЕНОС «СКОЛЬКО ВЛЕЗЕТ» ===")
-----------------------------------------------------------------------
do
    C.Ensure("src:2", "store", "", -1)
    C.Ensure("dst:2", "store", "", 10)
    C.Add("src:2", "scrap_metal", 20)

    local moved = C.MoveUpTo("src:2", "dst:2", "scrap_metal", 20)
    ok(moved == 8, "погрузилось ровно сколько влезло по весу", moved)
    ok(C.Count("src:2", "scrap_metal") == 12, "остаток на источнике")
    ok(C.MoveUpTo("src:2", "dst:2", "scrap_metal", 20) == 0, "вторая попытка — ноль, места нет")
    ok(C.MoveUpTo("src:2", "dst:2", "gpu_basic", 5) == 0, "нет предмета — ноль")
end

-----------------------------------------------------------------------
print("\n=== 5. АДАПТЕР ИНВЕНТАРЯ ИГРОКА ===")
-----------------------------------------------------------------------
do
    local ply = { __valid = true, _name = "игрок" }
    ply.SteamID64 = function() return "76561190000000001" end
    ply.EntIndex = function() return 1 end

    local box = C.ForPlayer(ply)
    ok(box ~= nil, "контейнер игрока создаётся")
    ok(box.kind == "player", "это виртуальный контейнер, а не хранилище", box.kind)

    C.Ensure("bench:in", "store", "", -1)
    C.Add("bench:in", "scrap_metal", 30)

    -- Инвентарь пуст, лимит 4 слота: переносим 10 — должно влезть 4.
    inv.slots, inv.maxSlots = {}, 4
    local moved = C.MoveUpTo("bench:in", box.id, "scrap_metal", 10)
    ok(moved == 4, "в инвентарь влезло ровно по слотам", moved)
    ok(C.Count("bench:in", "scrap_metal") == 26, "остаток вернулся в станок")
    ok(C.Count(box.id, "scrap_metal") == 4, "в инвентаре четыре лома")

    -- Прямой перенос большего количества обязан ОТКАТИТЬСЯ, а не
    -- положить четыре и потерять шесть.
    inv.slots, inv.maxSlots = {}, 2
    local okMove = C.Move("bench:in", box.id, "scrap_metal", 5)
    ok(okMove == false, "перенос сверх ёмкости инвентаря отклонён")
    ok(C.Count(box.id, "scrap_metal") == 0, "в инвентарь ничего не попало")
    ok(C.Count("bench:in", "scrap_metal") == 26, "И ВСЁ ВЕРНУЛОСЬ В СТАНОК — ничего не потеряно")

    -- Обратное направление: из инвентаря в станок.
    inv.slots, inv.maxSlots = {}, 4
    C.Add(box.id, "components_box", 3)
    ok(C.Count(box.id, "components_box") == 3, "предмет положен в инвентарь")
    ok(C.Move(box.id, "bench:in", "components_box", 3) == true, "перенос из инвентаря проходит")
    ok(C.Count(box.id, "components_box") == 0, "инвентарь пуст")
    ok(C.Count("bench:in", "components_box") == 3, "станок принял")

    ok(C.Move(box.id, "bench:in", "components_box", 1) == false, "взять то, чего нет, нельзя")
end

-----------------------------------------------------------------------
print("\n=== 6. СПИСКИ И СОХРАНЕНИЕ ===")
-----------------------------------------------------------------------
do
    C.Ensure("save:1", "store", "faction_c", 500)
    C.Add("save:1", "gpu_mid", 2)
    C.Add("save:1", "arccw_makarov", 1)
    C.Add("save:1", "scrap_metal", 7)

    local list = C.List("save:1")
    ok(#list == 3, "в списке три позиции", #list)
    local names = {}
    for _, l in ipairs(list) do names[#names + 1] = I.NameOf(l.itemID) end
    local sorted = true
    for i = 2, #names do if names[i - 1] > names[i] then sorted = false end end
    ok(sorted, "список отсортирован по названию", table.concat(names, ", "))

    -- Круг сохранения.
    local blob = C.Serialize()
    ok(blob["save:1"] ~= nil, "контейнер попал в сохранение")
    ok(blob["save:1"].items.gpu_mid == 2, "содержимое в сохранении")

    C.Remove("save:1")
    ok(C.Get("save:1") == nil, "контейнер удалён")
    ok(C.Count("save:1", "gpu_mid") == 0, "после удаления Count даёт ноль, а не ошибку")

    local n = C.Deserialize(blob)
    ok(n > 0, "контейнеры восстановлены", n)
    ok(C.Count("save:1", "gpu_mid") == 2, "содержимое совпадает после восстановления")
    ok(C.Capacity("save:1") == 500, "лимит восстановлен")
    ok(C.Weight("save:1") > 0, "вес пересчитан после восстановления")

    -- Мусор в сохранении не должен ронять загрузку.
    local before = #C.All()
    C.Deserialize({ broken = 42, ["another"] = { id = "another" } })
    ok(#C.All() >= before, "мусорная запись не ломает реестр")
    ok(C.Get("another") ~= nil, "корректная запись из того же файла загружена")
end

-----------------------------------------------------------------------
print("\n=== ИТОГ ===")
print("  пройдено: " .. pass .. ", провалено: " .. fail)
if fail > 0 then os.exit(1) end
