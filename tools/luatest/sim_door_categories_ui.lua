--[[ Контракт категорий дверей (заказ владельца 21.08):
     ключи должны воспринимать категории, категории — работать по фракциям,
     а список в окне не должен прыгать наверх после каждой галочки.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_door_categories_ui.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local core = read("lua/autorun/sh_grm_doors.lua")
local access = read("lua/autorun/sh_grm_doors_access.lua")
--[[ Свеп ds_key_swep удалён 31.08: двери и транспорт обслуживает
     единый модуль взаимодействия (плюс связка grm_keyring как предмет).
     Право на замок спрашивается там же, поэтому и проверяем его. ]]
local keys = read("lua/autorun/sh_grm_interact.lua")
local function has(s, n) return s:find(n, 1, true) ~= nil end

print("\n=== 1. КАТЕГОРИИ ВИДЯТ ФРАКЦИЮ ИГРОКА ===")
ok(has(core, 'local nwFac = ply.GetNWString and ply:GetNWString("GRM_Faction", "") or ""'),
    "принадлежность берётся и из NW-полей, а не только из таблицы состава")
ok(has(core, 'ply:GetNWString("GRM_Department", "")') and has(core, 'ply:GetNWString("GRM_Subdepartment", "")'),
    "отдел и подотдел тоже подхватываются запасным путём")
ok(has(core, "function D.CategoryMatch"), "матрица категории на месте")
ok(has(core, "actor.categoryHas = ownerCat and D.CategoryMatch(ownerCat, actor) or false"),
    "принадлежность к категории считается для конкретного игрока")
ok(has(core, "local isCat = rec.owner_type == \"category\" and fac and actor.categoryHas == true"),
    "категорийная дверь даёт ключ своим")

print("\n=== 2. КЛЮЧИ РАБОТАЮТ С КАТЕГОРИЯМИ ===")
ok(has(keys, "D.CanToggleLock"), "ключи спрашивают право именно на замок")
ok(has(core, "function D.CanToggleLock"), "право на замок считается в ядре")
ok(has(core, 'if istable(cat) and cat.lockAdminOnly == true then'),
    "флаг «замком управляет только администрация» учитывается")
ok(has(core, "Вам разрешён только проход"), "если категория запрещает замок — понятный отказ")

print("\n=== 3. СПИСОК КАТЕГОРИЙ НЕ ПРЫГАЕТ ===")
ok(has(access, "local restore"), "возврат прокрутки вынесен в отдельную функцию")
ok(has(access, "if math.abs(sp:GetVBar():GetScroll() - prevScroll) > 1 and tries > 1 then"),
    "попытка повторяется, пока позиция реально не встанет")
ok(has(access, "sp:InvalidateLayout(true)"), "перед возвратом холст пересчитывается")
ok(has(access, "timer.Simple(0, function() restore(8) end)"), "запас в несколько кадров")

print(("\nDOOR CATEGORIES UI: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
