--[[--------------------------------------------------------------------
    sim_dealer_phone_boot — заказ владельца от 18.08:
      1) навесные вкладки (в т.ч. арест) вернулись в /factions (Unified UI);
      2) дилер авто: категории вместо одного списка, стиль GRM,
         фракция выбирается из списка, а не вводится руками;
      3) торговец телефонами («Салон связи») как тип GRM.Vendor;
      4) аудит нагрузки: старты через GRM.Boot, таймеры не крутятся вхолостую.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_dealer_phone_boot.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local unified = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local dealerCl = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
local dealerSh = read("lua/autorun/sh_grm_vehicle_dealer.lua")
local dealerTool = read("lua/weapons/gmod_tool/stools/grm_transport.lua")
local vendor = read("lua/autorun/sh_grm_vendor.lua")
local vendorTool = read("lua/weapons/gmod_tool/stools/grm_vendor_tool.lua")
local phoneVendor = read("lua/autorun/sh_grm_phone_vendor.lua")
local boot = read("lua/autorun/sh_00_grm_boot.lua")
local arrest = read("lua/autorun/sh_grm_arrest.lua")
local industryUI = read("lua/autorun/client/cl_grm_industry_ui.lua")
local cuffs = read("lua/autorun/server/sv_grm_handcuffs.lua")
local trunk = read("lua/autorun/sh_grm_trunk.lua")
local broadcast = read("lua/autorun/sh_grm_broadcast.lua")

print("\n=== 1. НАВЕСНЫЕ ВКЛАДКИ В /factions (арест, экономика, кадры) ===")
ok(unified:find('hook.Call, "GRM_FactionsAdmin_BuildTabs"', 1, true) ~= nil,
    "Unified UI зовёт хук навесных вкладок (раньше его звало только старое меню)")
ok(unified:find("proxy.AddSheet = function", 1, true) ~= nil,
    "прокси с AddSheet: модуль думает, что это DPropertySheet")
ok(unified:find("local hookHost = vgui.Create(\"DPanel\", f)", 1, true) ~= nil
    and unified:find("parkHookedPanels", 1, true) ~= nil,
    "панели модулей паркуются, а не удаляются при content:Clear()")
ok(unified:find("local parkHookedPanels\n", 1, true) ~= nil,
    "форвард-декларация parkHookedPanels (замыкание refreshView видит её)")
ok(unified:find("f.OnRemove = function", 1, true) ~= nil,
    "панели модулей убираются вместе с окном, без утечки")
ok(select(2, unified:gsub("addTabBtn%(key", "")) >= 1,
    "каждая навесная страница становится кнопкой бокового меню GRM")
ok(read("lua/autorun/sh_grm_arrest.lua"):find('tabs:AddSheet("Доступ к аресту"', 1, true) ~= nil
    and arrest:find('tabs:AddSheet("Категории ареста"', 1, true) ~= nil,
    "вкладки ареста регистрируются тем же хуком — значит теперь видны в /factions")

print("\n=== 2. ДИЛЕР АВТО: КАТЕГОРИИ, GRM-СТИЛЬ, ФРАКЦИИ СПИСКОМ ===")
ok(dealerSh:find("function VD.FactionList()", 1, true) ~= nil,
    "сервер отдаёт реестр организаций для выпадающего списка")
ok(dealerSh:find("VD.BaseCategories", 1, true) ~= nil and dealerSh:find("function VD.CategoryList", 1, true) ~= nil,
    "список категорий: базовые + уже использованные в ассортименте")
ok(dealerSh:find("factionName=", 1, true) ~= nil,
    "в каталог игроку уходит ПУБЛИЧНОЕ имя организации, а не служебный ключ")
ok(dealerTool:find("factions = GRM.VehicleDealer.FactionList()", 1, true) ~= nil
    and dealerTool:find("categories = GRM.VehicleDealer.CategoryList", 1, true) ~= nil,
    "админка получает списки фракций и категорий при открытии")
ok(dealerCl:find('fac:AddChoice("— доступно всем —"', 1, true) ~= nil,
    "организация выбирается из списка (ручной ввод убран)")
ok(dealerCl:find("нет такой организации", 1, true) ~= nil,
    "сохранённая ранее опечатка подсвечивается как неизвестная организация")
ok(dealerCl:find('cat:AddChoice("＋ своя категория…"', 1, true) ~= nil,
    "категория из списка, но свою добавить можно")
ok(dealerCl:find("byCategory", 1, true) ~= nil and dealerCl:find("byFaction", 1, true) ~= nil,
    "каталог раскладывается по категориям и по организациям, а не одним списком")
ok(dealerCl:find('nav:AddCaption("Категории")', 1, true) ~= nil
    and dealerCl:find('nav:AddCaption("Служебный по организациям")', 1, true) ~= nil,
    "разделы бокового меню: категории отдельно, служебный транспорт отдельно")
ok(dealerCl:find("local function sideNav", 1, true) ~= nil and dealerCl:find("local function grmFrame", 1, true) ~= nil,
    "каркас окна GRM: шапка + боковое меню (как в /factions)")
ok(dealerCl:find("C.gold", 1, true) ~= nil and dealerCl:find("GRMVD_Title", 1, true) ~= nil,
    "палитра и шрифты GRM")
ok(dealerCl:find("client v4.6.0", 1, true) ~= nil, "клиент дилера v4.6.0 (гаражи, лимит, выдача, выкуп, память разделов)")

print("\n=== 3. ТОРГОВЕЦ ТЕЛЕФОНАМИ ===")
ok(vendor:find("V.TypeNames", 1, true) ~= nil and vendor:find("function V.RegisterType", 1, true) ~= nil,
    "реестр типов торговцев вынесен из захардкоженных списков")
ok(vendorTool:find("TYPESLIST()", 1, true) ~= nil,
    "тулган берёт типы из реестра — новый торговец появляется сам")
ok(phoneVendor:find('V.RegisterType("phone", "Салон связи"', 1, true) ~= nil,
    "зарегистрирован тип phone «Салон связи»")
ok(phoneVendor:find("GRM.Mobile", 1, true) ~= nil and phoneVendor:find("MB.Tiers", 1, true) ~= nil,
    "ассортимент строится из реестра телефонов, а не дублируется руками")
ok(phoneVendor:find("tier.apps and \"Смартфоны\" or \"Телефоны\"", 1, true) ~= nil,
    "товары разложены по категориям: телефоны и смартфоны")
ok(phoneVendor:find('GRM.Boot.Task("vendor.phone"', 1, true) ~= nil,
    "регистрация идёт через Boot — не зависит от порядка загрузки файлов")
ok(phoneVendor:find('concommand.Add("grm_phone_vendor_reload"', 1, true) ~= nil,
    "каталог можно перечитать без перезапуска карты")

print("\n=== 4. ПОРЯДОК ВЫПОЛНЕНИЯ И НАГРУЗКА ===")
ok(boot:find("function B.OnMapStart", 1, true) ~= nil,
    "у Boot появилась единая точка «сделать на старте карты»")
ok(boot:find('B.Version = "1.1.0"', 1, true) ~= nil, "Boot v1.1.0")

local files = {
    "lua/autorun/sh_07_grm_sound.lua", "lua/autorun/sh_spawn_points.lua", "lua/autorun/sh_grm_atm.lua",
    "lua/autorun/sh_grm_broadcast.lua", "lua/autorun/sh_grm_augmentation_chips.lua",
    "lua/autorun/sh_grm_augmentations.lua", "lua/autorun/sh_grm_diplomas.lua", "lua/autorun/sh_grm_ctx.lua",
    "lua/autorun/sh_grm_ffdlink.lua", "lua/autorun/sh_grm_factions_core_v4.lua",
    "lua/autorun/sh_grm_fire_status.lua", "lua/autorun/sh_grm_jobs.lua", "lua/autorun/sh_grm_movement.lua",
    "lua/autorun/sh_grm_property.lua", "lua/autorun/sh_grm_prop_protect.lua", "lua/autorun/sh_grm_radionet.lua",
    "lua/autorun/sh_grm_services.lua", "lua/autorun/sh_grm_vendor.lua", "lua/autorun/sh_grm_special_service.lua",
    "lua/autorun/sh_grm_vehicle_dealer.lua", "lua/autorun/zz_grm_food_inventory_patch.lua",
    "lua/autorun/sh_grm_wanted_fines.lua", "lua/autorun/client/cl_grm_hud.lua",
    "lua/autorun/client/cl_grm_augmentations_hud.lua", "lua/autorun/client/cl_grm_customization.lua",
    "lua/autorun/server/sv_grm_roomtap.lua", "lua/autorun/server/sv_grm_vehicle_dealer_anim_fix.lua",
}
local converted, leftovers = 0, {}
for _, path in ipairs(files) do
    local src = read(path)
    if src:find("GRM.Boot.OnMapStart", 1, true) then converted = converted + 1 end
    for name in src:gmatch('hook%.Add%("InitPostEntity",%s*"([%w_]+)"') do
        leftovers[#leftovers + 1] = path .. ":" .. name
    end
end
ok(converted == #files, ("все %d модулей стартуют через Boot (переведено %d)"):format(#files, converted))
ok(#leftovers == 0, "прямых InitPostEntity в переведённых модулях не осталось", table.concat(leftovers, ", "))

-- Тиры расставлены осмысленно: точки спавна и структура фракций — до игроков.
ok(read("lua/autorun/sh_spawn_points.lua"):find('"early"', 1, true) ~= nil,
    "точки спавна — приоритет early (нужны до входа игроков)")
ok(read("lua/autorun/sh_grm_factions_core_v4.lua"):find('"early"', 1, true) ~= nil,
    "миграция структуры фракций — early")
ok(read("lua/autorun/sh_07_grm_sound.lua"):find('"late"', 1, true) ~= nil,
    "прекэш звуков — late, не мешает старту")
ok(read("lua/autorun/client/cl_grm_hud.lua"):find('"late"', 1, true) ~= nil,
    "запросы HUD — late")

print("\n--- холостые таймеры ---")
ok(arrest:find("if (A.ArrestedCount or 0) <= 0 then return end", 1, true) ~= nil,
    "контроль арестованных не обходит игроков, когда арестованных нет")
ok(arrest:find("A.ArrestedCount = (A.ArrestedCount or 0) + 1", 1, true) ~= nil,
    "счётчик арестованных ведётся при самом аресте")
ok(cuffs:find("if istable(HC.Cuffed) and next(HC.Cuffed) == nil then return end", 1, true) ~= nil,
    "распад прогресса освобождения молчит, пока никто не закован")
ok(cuffs:find("HC.Cuffed[target] = true", 1, true) ~= nil, "реестр закованных ведётся при надевании наручников")
ok(trunk:find("if not istable(TK.Viewers) or next(TK.Viewers) == nil then return end", 1, true) ~= nil,
    "сторож багажника спит, пока его никто не открыл")
ok(broadcast:find("if (BC.LiveCount or 0) <= 0 then return end", 1, true) ~= nil,
    "сторож эфира спит, пока нет ни одного включённого микрофона")
ok(read("lua/autorun/server/sv_grm_industry_logistics.lua"):find("if not next(I.Routes) then return end", 1, true) ~= nil,
    "тик рейсов логистики спит без активных маршрутов")
ok(read("lua/autorun/server/sv_grm_industry.lua"):find("if not next(I.Jobs) then return end", 1, true) ~= nil,
    "тик задач цеха спит без активных работ")
ok(industryUI:find('timer.Create("GRM', 1, true) == nil
    and industryUI:find('hook.Add("PostDrawTranslucentRenderables"', 1, true) ~= nil,
    "подписи над узлами рисуются хуком отрисовки, а не вечным таймером")

print(("\nDEALER + PHONE VENDOR + BOOT: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
