-- sim_qmenu_v4_budget — порции иконок и отказ от BuildCPanel в UI
local src
do
    local fh = io.open("lua/autorun/sh_grm_qmenu.lua", "r")
    src = fh:read("*a") fh:close()
end
local bare = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")

local pass, fail = 0, 0
local function ok(c, m)
    if c then pass = pass + 1 print("  ok  " .. m)
    else fail = fail + 1 print("  FAIL " .. m) end
end

ok(src:find("ICON_BUDGET", 1, true) ~= nil, "есть бюджет иконок")
ok(src:find("ICON_BUDGET = 8", 1, true) ~= nil, "бюджет = 8 за кадр")
ok(src:find("QM._iconQueue", 1, true) ~= nil, "есть очередь иконок")
ok(src:find("GRM_QMenu_Icons", 1, true) ~= nil, "порции в Think")
ok(not bare:find("showToolSettings", 1, true), "нет старого showToolSettings")
ok(src:find("эту функцию НЕ вызывает", 1, true) ~= nil, "маркер: UI не зовёт BuildToolPanel")
ok(not bare:find("CP:PerformLayout", 1, true), "нет прямого PerformLayout")
ok(not bare:find("CP:SetTall", 1, true), "нет SetTall по ControlPanel")
ok(src:find("function QM.OpenMenu", 1, true) ~= nil, "OpenMenu существует")
ok(src:find("QM._holdOpen", 1, true) ~= nil, "флаг удержания есть")
ok(not src:find("ScreenClickerEnabled", 1, true), "Think не гасит по кликеру")
ok(not bare:find('{"tools", "Инструменты"', 1, true)
    and not bare:find('{ "tools", "Инструменты"', 1, true),
    "вкладки «Инструменты» нет")
ok(src:find("fillToolList", 1, true) ~= nil, "список тулов в средней колонке")
ok(src:find("TOOLS_W", 1, true) ~= nil and src:find("PANEL_W", 1, true) ~= nil,
    "две отдельные колонки: инструменты и панель")
ok(not bare:find('RunConsoleCommand("+menu")', 1, true), "нет кнопки +menu")
ok(src:find("нет настроек в меню", 1, true) ~= nil, "честная подсказка, когда настроек нет вовсе")

print(("РЕЗУЛЬТАТ: %d/%d, fail=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
