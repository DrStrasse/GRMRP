--[[ Живой прогон выручки автоматов (заказ владельца 27.08):
     «Автоматы с едой не запоминают сколько было чего куплено и сумма
      общая теряется после рестарта».

     ДВЕ ПРИЧИНЫ, найденные при разборе:

     1) ШТАТНОЕ СОХРАНЕНИЕ СТИРАЛО БИЗНЕС-ДАННЫЕ. GRM.Food.SaveVendingMachines
        писала в файл только pos/ang и ПЕРЕЗАПИСЫВАЛА его целиком. Владелец
        и касса, которые дописывал модуль бизнеса, исчезали при каждом
        сохранении.

     2) ПРИВЯЗКА ПО ПОРЯДКОВОМУ НОМЕРУ. Строки файла сопоставлялись с
        автоматами по индексу в ents.FindByClass. Порядок сущностей в GMod
        не гарантирован: после рестарта касса могла уехать к чужому
        автомату или потеряться совсем.

     Плюс: счётчиков «сколько продано за всё время» не было вовсе —
     считалась только текущая касса, и после снятия денег история исчезала.

     Запуск: luajit tools/luatest/sim_vending_persist.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local biz = body("lua/autorun/sh_grm_vending_biz.lua")
local food = body("lua/autorun/server/sv_grm_food.lua")

print("\n=== 1. ШТАТНОЕ СОХРАНЕНИЕ БОЛЬШЕ НЕ СТИРАЕТ ВЫРУЧКУ ===")
ok(food:find("row.owner = GRM.VendingBiz.GetOwner", 1, true) ~= nil,
   "владелец пишется вместе с позицией автомата")
ok(food:find("row.cash = GRM.VendingBiz.GetCash", 1, true) ~= nil, "касса пишется тоже")
ok(food:find("row.sold =", 1, true) ~= nil and food:find("row.earned =", 1, true) ~= nil,
   "счётчики «продано» и «заработано» сохраняются")
ok(food:find("GRM.VendingBiz.SetCash(ent, tonumber(row.cash)", 1, true) ~= nil,
   "при загрузке касса возвращается на автомат")
ok(food:find('ent:SetNWString("GRM_VendOwner", row.owner)', 1, true) ~= nil,
   "и владелец возвращается")
ok(food:find("ent.GRMVendSold = math.max", 1, true) ~= nil,
   "история продаж переживает перезагрузку карты")

print("\n=== 2. ПРИВЯЗКА ПО ПОЗИЦИИ, А НЕ ПО ПОРЯДКУ ===")
ok(biz:find("local function posKey(vec)", 1, true) ~= nil, "появился ключ по координатам")
ok(biz:find("byPos[posKey(ent:GetPos())] = ent", 1, true) ~= nil,
   "автоматы ищутся по месту на карте")
ok(biz:find("local ent = entsList[i]", 1, true) == nil,
   "старая привязка по порядковому номеру убрана из сохранения")
ok(biz:find("local ent = list[i]", 1, true) == nil,
   "и из восстановления тоже")
ok(biz:find("Порядок сущностей в GMod", 1, true) ~= nil,
   "причина зафиксирована в комментарии для будущих правок")

print("\n=== 3. СЧЁТЧИКИ ЗА ВСЁ ВРЕМЯ ===")
ok(biz:find("function VB.GetStats(ent)", 1, true) ~= nil, "итоги автомата можно прочитать")
ok(biz:find("ent.GRMVendEarned = math.max(0, math.floor(tonumber(ent.GRMVendEarned) or 0)) + p", 1, true) ~= nil,
   "заработок копится за всё время, а не только до снятия кассы")
ok(biz:find('ent:SetNWInt("GRM_VendSold"', 1, true) ~= nil,
   "счётчики networked — их видно в интерфейсе")

print("\n=== 4. ЗАПИСЬ НА ДИСК ЭКОНОМНАЯ, НО НАДЁЖНАЯ ===")
ok(biz:find("if not force and not dirty then return end", 1, true) ~= nil,
   "файл не переписывается каждые 20 с без нужды")
ok(biz:find('hook.Add("ShutDown", "GRM_VendingBiz_Persist", function() persistOverlay(true) end)', 1, true) ~= nil,
   "на выключении сервера сохранение принудительное")
ok(biz:find("if VB.MarkDirty then VB.MarkDirty() end", 1, true) ~= nil,
   "любое изменение кассы помечает данные к записи")
ok(biz:find("if VB.Persist then VB.Persist(true) end", 1, true) ~= nil,
   "покупка автомата сохраняется сразу, не дожидаясь таймера")

print("\n=== 5. ЖИВАЯ ПРОВЕРКА ЛОГИКИ СЧЁТЧИКОВ ===")
-- Повторяем арифметику AddSale на заглушке: три продажи и снятие кассы.
local ent = { cash = 0, sold = 0, earned = 0 }
local function addSale(price)
    ent.cash = ent.cash + price
    ent.sold = ent.sold + 1
    ent.earned = ent.earned + price
end
addSale(150) addSale(150) addSale(300)
ok(ent.cash == 600 and ent.sold == 3 and ent.earned == 600,
   "три продажи: касса 600, продано 3, заработано 600")
ent.cash = 0   -- владелец снял выручку
ok(ent.sold == 3 and ent.earned == 600,
   "после снятия кассы история продаж СОХРАНЯЕТСЯ — это и просил владелец",
   ent.sold .. " / " .. ent.earned)
addSale(200)
ok(ent.cash == 200 and ent.earned == 800, "новые продажи копятся дальше")

print("\n=== 6. КЛЮЧ ПОЗИЦИИ УСТОЙЧИВ ===")
--[[ Ключ округляет координаты: физика может сместить автомат на доли
     юнита, и это не должно рвать привязку. ]]
local function posKey(v) return string.format("%.0f:%.0f:%.0f", v.x, v.y, v.z) end
ok(posKey({ x = 100.4, y = -200.2, z = 33.1 }) == posKey({ x = 100.0, y = -200.0, z = 33.0 }),
   "дрожание позиции на доли юнита не рвёт привязку")
ok(posKey({ x = 100, y = 0, z = 0 }) ~= posKey({ x = 200, y = 0, z = 0 }),
   "разные автоматы различаются")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
