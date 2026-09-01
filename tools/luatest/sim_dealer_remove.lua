--[[--------------------------------------------------------------------
    sim_dealer_remove — заказ владельца 19.08: «у дилера в меню должна быть
    кнопка убрать транспорт, как в C-меню».

    Раньше из меню дилера убирался только ЛИЧНЫЙ транспорт с записью гаража
    («В ГАРАЖ»); служебная машина организации записи не имеет, и убрать её
    можно было исключительно контекстным C-меню.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_dealer_remove.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local core = read("lua/autorun/sh_grm_vehicle_dealer.lua")
local cl   = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
local ctx  = read("lua/autorun/sh_grm_ctx.lua")

print("\n=== 1. СЕРВЕР ===")
ok(has(core, 'VD.Version="3.8.0"'), "версия дилера поднята до 3.8.0")
ok(has(core, "function VD.ActiveRows"), "сервер собирает список живого транспорта игрока")
ok(has(core, "ent.GRMGarageOwner==ply"), "в список попадает только свой транспорт")
ok(has(core, "ownershipName=VD.VehicleKinds[kind]"), "видно тип владения (личный/служебный)")
ok(has(core, "net.WriteTable(VD.ActiveRows(ply))"), "список уходит клиенту вместе с каталогом и гаражом")
ok(has(core, 'elseif op=="remove"then'), "есть операция remove")
ok(has(core, "В транспорте сидит водитель"), "нельзя убрать машину из-под чужого водителя")
ok(has(core, 'return true,r and"Транспорт убран в гараж"or"Служебный транспорт убран"'),
    "личный уходит в гараж, служебный просто снимается с карты")

print("\n=== 2. КЛИЕНТ ===")
ok(has(cl, "local activeVeh = net.ReadTable() or {}"), "клиент читает список живого транспорта")
ok(has(cl, "local function activeCard"), "есть карточка активной машины")
ok(has(cl, 'nav:AddSection("active", "На карте (убрать)"'), "в боковом меню появился раздел «На карте»")
ok(has(cl, 'send(dealer, rmAction, v.id)'), "кнопка шлёт действие через переменную (store/fleet_store/remove)")
ok(has(cl, 'local rmQuery = v.personal') and has(cl, "Derma_Query(rmQuery"), "убирание подтверждается диалогом")
ok(has(cl, 'currentMode == "active"'), "режим отрисовки раздела учтён в render")

print("\n=== 3. C-МЕНЮ НЕ СЛОМАНО ===")
ok(has(ctx, 'if doAct == "remove" then'), "контекстное «Убрать Т/С» на месте")
ok(has(core, "function _G.VD_RemoveDealerVehicle"), "общая точка удаления для C-меню сохранена")

print("\n=== 4. РАЗДЕЛ НЕ СБРАСЫВАЕТСЯ ПОСЛЕ ДЕЙСТВИЙ ===")
ok(has(cl, "local lastSection, lastSearch, lastScroll"), "окно помнит раздел, поиск и прокрутку")
ok(has(cl, "lastSection = key"), "выбранный раздел запоминается при клике")
ok(has(cl, 'local restore = nav.Buttons[lastSection] or nav.Buttons["all"]'),
    "после пересборки открывается тот же раздел, а не «Весь каталог»")
ok(not has(cl, 'if nav.Buttons["all"] then nav.Buttons["all"]:DoClick() end'),
    "принудительный переход на первую вкладку убран")
ok(has(cl, "if baseVScroll then baseVScroll(pnl, offset) end"),
    "OnVScroll не подменяется — список продолжает прокручиваться")
ok(has(cl, "local restoring = false") and has(cl, "if not restoring and currentMode ~="),
    "во время восстановления прокрутка не обнуляется сама собой")
ok(has(cl, "lastSearch = self:GetValue()"), "строка поиска тоже переживает продажу")

print(("\nDEALER REMOVE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
