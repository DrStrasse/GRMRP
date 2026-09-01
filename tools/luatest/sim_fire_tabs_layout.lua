--[[--------------------------------------------------------------------
    sim_fire_tabs_layout — заказ владельца 18.08 (третья часть):
      1) пожарные настройки есть в едином админ-меню и в админ-хабе;
      2) вкладка «Пожарные» (и остальные access-модули) встраивается в
         НОВОЕ меню организаций, а не только в старое;
      3) боковое меню /factions прокручивается и уходит в два столбца,
         когда разделов больше, чем помещается по высоте.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fire_tabs_layout.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local hub     = read("lua/autorun/sh_grm_admin_hub.lua")
local center  = read("lua/autorun/client/cl_grm_unified_admin.lua")
local unified = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")

print("\n=== 1. ПОЖАРНЫЕ НАСТРОЙКИ В АДМИН-МЕНЮ ===")
ok(hub:find('{ "Пожарные: доступы", "/fire_access"', 1, true) ~= nil, "хаб: доступы пожарных")
ok(hub:find('{ "Пожарные: очаги и таймеры", "grm_fire_spots"', 1, true) ~= nil, "хаб: очаги и таймеры")
ok(hub:find('{ "Пожарные: журнал пожаров", "grm_fire_log"', 1, true) ~= nil, "хаб: журнал пожаров")
ok(hub:find('{ "Пожарные: машины", "grm_fire_trucks"', 1, true) ~= nil, "хаб: пожарные машины")
ok(hub:find('{ "Пожарные: оповещение фракций", "grm_fire_notify"', 1, true) ~= nil, "хаб: оповещение фракций")
ok(hub:find('["/fire_access"] = true', 1, true) ~= nil and hub:find('["grm_fire_spots"] = true', 1, true) ~= nil,
    "команды разрешены белым списком запуска")
ok(hub:find('if command:sub(1, 1) ~= "/" and command:sub(1, 1) ~= "!" then', 1, true) ~= nil,
    "консольные пункты запускаются локально (раньше уходили в PlayerSay и не работали)")
ok(hub:find('HB.Version = "1.3.0"', 1, true) ~= nil, "хаб v1.3.0")
ok(center:find('{"Пожарные: доступы","grm_fire_access"}', 1, true) ~= nil
    and center:find('{"Пожарные: машины","grm_fire_trucks"}', 1, true) ~= nil,
    "единый центр управления: пожарные кнопки добавлены")
ok(center:find('{"Полная админ-панель GRM","grm_admin"}', 1, true) ~= nil,
    "из центра есть переход в полную админ-панель")

print("\n=== 2. ВКЛАДКИ ACCESS-МОДУЛЕЙ В НОВОМ МЕНЮ ОРГАНИЗАЦИЙ ===")
local modules = {
    { "lua/autorun/sh_grm_fire_access.lua",   "GRM_FireAccess_Tab",   "Пожарные" },
    { "lua/autorun/sh_grm_alarm_access.lua",  "GRM_AlarmAccess_Tab",  "сигнализация" },
    { "lua/autorun/sh_grm_doors_access.lua",  "GRM_DoorsAccess_Tab",  "двери и ордера" },
    { "lua/autorun/sh_grm_wanted_access.lua", "GRM_WantedAccess_Tab", "розыск" },
    { "lua/autorun/sh_grm_cctv_access.lua",   "GRM_CCTVAccess_Tab",   "CCTV" },
    { "lua/autorun/sh_grm_phone_access.lua",  "GRM_PhoneAccess_Tab",  "телефония" },
}
for _, row in ipairs(modules) do
    local src = read(row[1])
    ok(src:find('hook.Add("GRM_FactionsAdmin_BuildTabs", "' .. row[2] .. '"', 1, true) ~= nil,
        row[3] .. ": вкладка идёт через штатный хук меню")
    ok(src:find("OpenAdminMenu = function(...)", 1, true) == nil,
        row[3] .. ": подмена глобальной OpenAdminMenu убрана")
    ok(src:find("_wrapped", 1, true) == nil, row[3] .. ": следов старой обёртки не осталось")
end

print("\n=== 3. РАСКЛАДКА БОКОВОГО МЕНЮ ===")
ok(unified:find("local sidebarScroll = vgui.Create(\"DScrollPanel\", sidebarHost)", 1, true) ~= nil,
    "боковое меню прокручивается")
ok(unified:find("local function relayoutNav()", 1, true) ~= nil, "раскладка кнопок пересчитывается")
ok(unified:find("local columns = (perColumn > 0 and count > perColumn) and 2 or 1", 1, true) ~= nil,
    "при переполнении по высоте — два столбца")
ok(unified:find("sidebarHost:SetWide(360)", 1, true) ~= nil,
    "в двухстолбцовом режиме панель расширяется")
ok(unified:find("navRows[#navRows + 1] = btn", 1, true) ~= nil,
    "кнопки разделов учитываются в раскладке")
ok(unified:find("sidebar.PerformLayout = function() relayoutNav() end", 1, true) ~= nil,
    "раскладка пересчитывается при изменении размера окна")

print(("\nFIRE + TABS + LAYOUT: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
