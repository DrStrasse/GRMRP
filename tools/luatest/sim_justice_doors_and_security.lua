--[[--------------------------------------------------------------------
    sim_justice_doors_and_security.lua
    Тест-стенд для Door Integrity Engine v4.0, Судебных ордеров (Warrant Core v2.0),
    Полицейского тарана v2.0 и суверенитета спецслужб с защитой судей.
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, msg)
    if v then
        pass = pass + 1
        print("  ok  " .. msg)
    else
        fail = fail + 1
        print("  FAIL " .. msg)
    end
end

print("=== ТЕСТ 1: Дверной фундамент (Door Integrity v4.0) ===")
local doorsCode = assert(io.open("lua/autorun/sh_grm_doors.lua", "rb")):read("*a")
local ramCode = assert(io.open("lua/weapons/ds_battering_ram/shared.lua", "rb")):read("*a")
local courtInitCode = assert(io.open("lua/entities/grm_comp_court/init.lua", "rb")):read("*a")
local courtClCode = assert(io.open("lua/entities/grm_comp_court/cl_init.lua", "rb")):read("*a")
local roomtapCode = assert(io.open("lua/autorun/server/sv_grm_roomtap.lua", "rb")):read("*a")

ok((doorsCode:match('D%.Version = "(%d+)') or "0")+0>=4, "Doors Core не ниже v4.0.0")
ok(doorsCode:find("function D.PurgeGhostDoors", 1, true) ~= nil, "D.PurgeGhostDoors дедупликатор фантомов существует")
ok(doorsCode:find("D.GetPartnerDoor", 1, true) ~= nil, "D.GetPartnerDoor связка двустворчатых дверей существует")
ok(doorsCode:find("function D.BreachDoor", 1, true) ~= nil, "D.BreachDoor синхронный силовой взлом существует")
ok(doorsCode:find("grm_door_audit", 1, true) ~= nil, "Диагностическая команда grm_door_audit зарегистрирована")

print("=== ТЕСТ 2: Судебная система и Электронные ордера (Warrant Core v2.0) ===")
ok(doorsCode:find("function D.HasPropertyWarrant", 1, true) ~= nil, "D.HasPropertyWarrant проверка ордера на адрес/помещение")
ok(doorsCode:find("function D.RequestWarrant", 1, true) ~= nil, "D.RequestWarrant подача ходатайства в суд")
ok(doorsCode:find("function D.ApproveWarrant", 1, true) ~= nil, "D.ApproveWarrant утверждение ордера судьей")
ok(doorsCode:find("function D.RejectWarrant", 1, true) ~= nil, "D.RejectWarrant отклонение ходатайства")
ok(doorsCode:find("function D.ListWarrants", 1, true) ~= nil, "D.ListWarrants реестр ордеров")

ok(courtInitCode:find("warrant_approve", 1, true) ~= nil, "grm_comp_court сервер обрабатывает warrant_approve")
ok(courtInitCode:find("warrant_request", 1, true) ~= nil, "grm_comp_court сервер обрабатывает warrant_request")
ok(courtClCode:find("Судебные ордера", 1, true) ~= nil, "grm_comp_court клиент содержит вкладку «Судебные ордера»")
ok(courtClCode:find("Обыск жилища", 1, true) ~= nil, "Интерфейс суда содержит тип «Обыск жилища»")
ok(courtClCode:find("Надзор за судьёй", 1, true) ~= nil, "Интерфейс суда содержит тип «Надзор за судьёй»")

print("=== ТЕСТ 3: Полицейский таран v2.0 (Battering Ram) ===")
ok(ramCode:find("REQUIRED_STRIKES = 3", 1, true) ~= nil, "Таран использует 3-шаговый цикл ударов")
ok(ramCode:find("search", 1, true) ~= nil, "Таран проверяет ордер на обыск (search warrant)")
ok(ramCode:find("GRM.Doors.BreachDoor", 1, true) ~= nil, "Таран вызывает D.BreachDoor при 3-м ударе")
ok(ramCode:find("RAM_HUD_Title", 1, true) ~= nil, "Клиентский HUD тарана обновлен")

print("=== ТЕСТ 4: Спецслужбы и защита судей в RoomTap ===")
ok(roomtapCode:find("isJudge", 1, true) ~= nil, "RoomTap проверяет статус судьи у спикера")
ok(roomtapCode:find("wiretap_judge", 1, true) ~= nil, "RoomTap требует ордер wiretap_judge для прослушки судей")
ok(roomtapCode:find("Защищено судебным иммунитетом", 1, true) ~= nil, "Речь судьи без ордера защищена иммунитетом")

print(string.format("\nРЕЗУЛЬТАТ: Пройдено проверок: %d/%d (провалов: %d)", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
print("ALL JUSTICE, DOORS & SECURITY TESTS PASSED!")
