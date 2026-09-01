--[[--------------------------------------------------------------------
    sim_fire_computer — заказ владельца 18.08: компьютер пожарных.
    Убраны кнопки ствола/рукава и закрепления/открепления машины,
    остались журнал пожаров и журнал вызовов.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fire_computer.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local cl = read("lua/entities/grm_comp_fire/cl_init.lua")
local sv = read("lua/entities/grm_comp_fire/init.lua")
local sh = read("lua/entities/grm_comp_fire/shared.lua")

print("\n=== УБРАННЫЕ КНОПКИ ===")
ok(cl:find("Закрепить машину", 1, true) == nil, "нет кнопки «Закрепить машину / насос»")
ok(cl:find("Снять машину", 1, true) == nil, "нет кнопки «Снять машину»")
ok(cl:find("Взять ствол", 1, true) == nil, "нет кнопки «Взять ствол / рукав»")
ok(cl:find("sendAction", 1, true) == nil, "клиент больше не шлёт действия дежурства")
ok(sv:find('util.AddNetworkString("GRM_CompFire_Action")', 1, true) == nil,
    "серверный канал действий дежурства убран")
ok(sv:find("CommissionTruck", 1, true) == nil and sv:find("TakeHoseFromTruck", 1, true) == nil,
    "серверные операции закрепления машины и выдачи рукава со станции убраны")

print("\n=== ЧТО ОСТАЛОСЬ ===")
ok(cl:find("📋 Журнал пожаров", 1, true) ~= nil, "журнал пожаров на месте")
ok(cl:find("Журнал вызовов (пожар · 911)", 1, true) ~= nil, "добавлен журнал вызовов")
ok(cl:find("local function requestCalls()", 1, true) ~= nil, "клиент запрашивает журнал вызовов")
ok(sv:find('net.Receive("GRM_CompFire_Calls"', 1, true) ~= nil, "сервер отдаёт журнал вызовов")
ok(sv:find('tostring(r.category or "") == "fire"', 1, true) ~= nil,
    "в журнал попадают только вызовы категории «Пожар»")
ok(sv:find("if not ent:CanManage(ply) then return end", 1, true) ~= nil,
    "журнал вызовов под тем же доступом: бойцы, диспетчеры, суперадмин")
ok(sv:find("while #rows > 100 do table.remove(rows) end", 1, true) ~= nil, "журнал ограничен последними 100 вызовами")
ok(cl:find('list:AddColumn("Статус")', 1, true) ~= nil and cl:find('list:AddColumn("Принял")', 1, true) ~= nil,
    "в окне журнала видно статус и кто принял вызов")
ok(cl:find("Вызовов по линии пожарной службы пока не поступало.", 1, true) ~= nil,
    "пустой журнал объясняет себя")
ok(sh:find("Чисто диспетчерский пост", 1, true) ~= nil, "описание энтити обновлено")
ok(cl:find("grm_fire_access", 1, true) ~= nil, "админские кнопки пожарки у суперадмина сохранены")

print(("\nFIRE COMPUTER: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
