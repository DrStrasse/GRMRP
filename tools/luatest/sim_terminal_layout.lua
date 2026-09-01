--[[ Контракт окон терминалов (заказ владельца 21.08: «окна побольше и
     пошире, вкладки не влазят, половина полей не подписана»).
     Проверяем ПО ИСХОДНИКАМ: размеры окон тянутся под экран, у каждого
     терминала с госбазой есть вкладки «Автопарк» и «Номерные знаки», а поля
     ввода со своим Paint рисуют подсказку сами.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_terminal_layout.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function read(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
local function has(s, n) return s and s:find(n, 1, true) ~= nil end

local TERMINALS = {
    "grm_comp_cityhall", "grm_comp_court", "grm_comp_medical", "grm_comp_military",
    "grm_comp_military_police", "grm_comp_police", "grm_comp_security", "grm_comp_traffic",
    "grm_doc_computer",
}

print("\n=== 1. ОКНА ТЕРМИНАЛОВ ТЯНУТСЯ ПОД ЭКРАН ===")
for _, name in ipairs(TERMINALS) do
    local src = read("lua/entities/" .. name .. "/cl_init.lua")
    ok(src ~= nil, "файл найден: " .. name)
    if src then
        ok(not has(src, "frame:SetSize(960, 700)") and not has(src, "frame:SetSize(780, 620)")
            and not has(src, "frame:SetSize(860, 640)") and not has(src, "frame:SetSize(980, 720)"),
            name .. ": фиксированного маленького окна больше нет")
        ok(has(src, "frame:SetSize(math.Clamp(ScrW()"), name .. ": размер считается от экрана")
    end
end

print("\n=== 2. ВКЛАДКИ ЕСТЬ ВЕЗДЕ, ГДЕ ЕСТЬ ГОСБАЗА ===")
for _, name in ipairs(TERMINALS) do
    local src = read("lua/entities/" .. name .. "/cl_init.lua") or ""
    if has(src, "GRM.PCBoard.AttachTab") then
        ok(has(src, "GRM.Fleet.AttachTab"), name .. ": есть вкладка «Автопарк»")
        ok(has(src, "GRM.Plates.AttachTab"), name .. ": есть вкладка «Номерные знаки»")
    end
end

print("\n=== 3. ВКЛАДКИ ПОДПИСАНЫ И С ИКОНКАМИ ===")
local fleet = read("lua/autorun/sh_grm_fleet.lua") or ""
local plates = read("lua/autorun/sh_grm_plates.lua") or ""
ok(has(fleet, 'sheetPanel:AddSheet("Автопарк", pnl, "icon16/lorry_add.png")'), "вкладка автопарка названа и с иконкой")
ok(has(plates, 'sheet:AddSheet("Номерные знаки", pnl, "icon16/car.png")'), "вкладка номеров названа и с иконкой")
ok(has(fleet, 'sheet:AddSheet("Закупка", buyPnl, "icon16/cart.png")')
    and has(fleet, 'sheet:AddSheet("Автопарк организации", parkPnl, "icon16/lorry.png")')
    and has(fleet, 'sheet:AddSheet("Рынок (суперадмин)", adminPnl, "icon16/wrench.png")'),
    "внутренние разделы автопарка тоже подписаны")

print("\n=== 4. ПОЛЯ ВВОДА ПОДПИСАНЫ ===")
ok(has(fleet, "not self:HasFocus()") and has(fleet, "placeholder or \"\""),
    "автопарк: подсказка поля рисуется вручную (со своим Paint движок её не рисует)")
ok(has(plates, "not self:HasFocus()"), "номера: подсказка поля рисуется вручную")
ok(has(fleet, '"КЛАСС ТРАНСПОРТА"') and has(fleet, '"ЦЕНА ЗА ЕДИНИЦУ"')
    and has(fleet, '"ЛИМИТ НА ОРГАНИЗАЦИЮ"') and has(fleet, '"УРОВЕНЬ ДОПУСКА"'),
    "у формы рынка каждое поле подписано заголовком")
ok(has(fleet, '"ГАРАЖ ПРИПИСКИ"') and has(fleet, '"СКОЛЬКО ЕДИНИЦ"'),
    "в закупке подписаны выбор гаража и количество")

print("\n=== 5. СОБСТВЕННЫЕ ОКНА МОДУЛЕЙ ТОЖЕ МАСШТАБИРУЮТСЯ ===")
ok(has(fleet, "f:SetSize(math.Clamp(ScrW()"), "окно автопарка тянется под экран")
ok(has(plates, "f:SetSize(math.Clamp(ScrW()"), "окно номеров тянется под экран")

print(("\nTERMINAL LAYOUT: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
