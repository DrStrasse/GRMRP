--[[ Контракт единого тула «GRM: транспорт» (заказ владельца 21.08:
     «инструмент работает кривовато, старые файлы не удалены, расстановка
     зоны непонятна, нет нормальных подписей»).
     Проверяем по исходникам: старых тулов нет, у нового есть превью,
     подсказки на экране, подписи полей и все режимы.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_transport_tool.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function read(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a") f:close() return s
end
local function has(s, n) return s and s:find(n, 1, true) ~= nil end

print("\n=== 1. СТАРЫЕ ТУЛЫ УДАЛЕНЫ ===")
ok(read("lua/weapons/gmod_tool/stools/grm_garage.lua") == nil, "старого тула гаражей больше нет")
ok(read("lua/weapons/gmod_tool/stools/vehicle_dealer_tool.lua") == nil, "старого тула дилера больше нет")
local tool = read("lua/weapons/gmod_tool/stools/grm_transport.lua")
ok(tool ~= nil, "единый тул на месте")

local qmenu = read("lua/autorun/sh_grm_qmenu.lua") or ""
ok(not has(qmenu, 'id = "vehicle_dealer_tool"'), "Q-меню не предлагает удалённый тул дилера")
ok(not has(qmenu, 'id = "grm_garage",'), "Q-меню не предлагает удалённый тул гаражей")
ok(has(qmenu, 'id = "grm_transport"'), "Q-меню знает новый тул")
ok(has(qmenu, "grm_transport = {") and has(qmenu, 'cvar = "grm_transport_mode"'),
    "у нового тула есть панель настроек в Q-меню")

print("\n=== 2. РЕЖИМЫ И ПОДПИСИ КНОПОК ===")
for _, m in ipairs({ "zone", "slot", "terminal", "door", "dealer", "link" }) do
    ok(has(tool, 'key = "' .. m .. '"'), "режим объявлен: " .. m)
end
ok(has(tool, "lmb =") and has(tool, "rmb =") and has(tool, "r ="),
    "у каждого режима расписано, что делают ЛКМ, ПКМ и R")
ok(has(tool, 'hook.Add("HUDPaint", "GRM_TransportTool_HUD"'),
    "подсказка показывается прямо на экране, а не только в панели")
ok(has(tool, "Первый угол поставлен — кликните второй"), "во время разметки зоны видно, что делать дальше")

print("\n=== 3. ПРЕВЬЮ РАЗМЕТКИ ===")
ok(has(tool, 'hook.Add("PostDrawTranslucentRenderables", "GRM_TransportTool_Draw"'),
    "разметка рисуется в мире")
ok(has(tool, "НОВАЯ ЗОНА ГАРАЖА"), "будущая зона рисуется по курсору ДО второго клика")
ok(has(tool, "МАЛО: нужна сторона от 200"), "видно, если зона слишком маленькая")
ok(has(tool, "render.DrawWireframeSphere"), "первый угол подсвечивается отдельно")
ok(has(tool, '"свободно, машина встанет по стрелке"'), "у мест выдачи подпись и направление")
ok(has(tool, '"СТОЙКА ВЫЗОВА"'), "стойки подписаны")
ok(has(tool, '"ДИЛЕР: "') and has(tool, "покупки → гараж"), "дилеры подписаны и видно их гараж")
ok(has(tool, "d.garageCenter"), "связь дилера с гаражом показана линией")

print("\n=== 4. ДАННЫЕ ДЛЯ ПРЕВЬЮ ===")
ok(has(tool, 'local NET_REQ  = "GRM_Transport_ToolReq"') and has(tool, 'local NET_DATA = "GRM_Transport_ToolData"'),
    "у тула свои сетевые имена (не наследие удалённых файлов)")
ok(has(tool, "util.AddNetworkString(NET_REQ)") and has(tool, "util.AddNetworkString(NET_DATA)"),
    "имена регистрируются на сервере — «unpooled message» не будет")
ok(has(tool, 'ents.FindByClass("sent_vehicle_dealer")'), "в превью попадают и дилеры")
ok(has(tool, "ply:IsSuperAdmin()"), "данные разметки отдаются только суперадмину")

print("\n=== 5. ПОДПИСИ В ПАНЕЛИ ИНСТРУМЕНТА ===")
ok(has(tool, 'panel:ControlHelp("ГАРАЖ")') and has(tool, 'panel:ControlHelp("МЕСТО ВЫДАЧИ")')
    and has(tool, 'panel:ControlHelp("ДИЛЕР")'), "настройки разбиты на именованные блоки")
ok(has(tool, '"ЧТО СТАВИМ"'), "выбор режима подписан")
ok(has(tool, "Название места (необязательно)") and has(tool, "Куда смотрит машина")
    and has(tool, "Высота появления над землёй"), "поля места выдачи подписаны понятно")
ok(has(tool, "ПОРЯДОК: зона → места выдачи"), "порядок работы описан в панели")

print("\n=== 6. ОТМЕНА И УДАЛЕНИЕ ===")
ok(has(tool, "Разметка зоны отменена"), "R отменяет начатую зону, а не молчит")
ok(has(tool, "RemoveNearestSlot") and has(tool, "RemoveNearestTerminal"), "R удаляет место и стойку")
ok(has(tool, "Shift+R по зоне — удалить гараж"), "удаление гаража подсказано явно")

print(("\nTRANSPORT TOOL: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
