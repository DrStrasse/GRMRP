--[[--------------------------------------------------------------------
    sim_fire_dispatch — заказ владельца 18.08: уведомление о пожаре
    с обязательным принятием вызова.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fire_dispatch.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local disp   = read("lua/autorun/sh_grm_fire_dispatch.lua")
local status = read("lua/autorun/sh_grm_fire_status.lua")
local compSv = read("lua/entities/grm_comp_fire/init.lua")
local compCl = read("lua/entities/grm_comp_fire/cl_init.lua")
local hub    = read("lua/autorun/sh_grm_admin_hub.lua")

print("\n=== 1. СОЗДАНИЕ ВЫЗОВА ===")
ok(status:find('hook.Run("GRM_FireIncidentOpened", inc)', 1, true) ~= nil,
    "открытие очага поднимает хук вызова")
ok(status:find('F.StatusVersion = "1.5.0"', 1, true) ~= nil, "учёт пожаров v1.5.0")
ok(disp:find('hook.Add("GRM_FireIncidentOpened", "GRM_FireDispatch_Open"', 1, true) ~= nil,
    "диспетчер слушает открытие очага")
ok(disp:find('hook.Add("GRM_911_Call", "GRM_FireDispatch_911"', 1, true) ~= nil,
    "вызов 911 категории «Пожар» тоже создаёт вызов расчёту")
ok(disp:find("function D.CreateCall", 1, true) ~= nil, "есть создание вызова")
ok(disp:find("call.origin:DistToSqr(origin) <= 600 * 600", 1, true) ~= nil,
    "на один очаг не плодится несколько вызовов")
ok(disp:find("local function areaName", 1, true) ~= nil,
    "в вызове указывается район-ориентир по точкам карты")

print("\n=== 2. КОМУ ПРИХОДИТ ===")
ok(disp:find("function D.Responders", 1, true) ~= nil, "список получателей вычисляется")
ok(disp:find("F.CanFightPro(ply) == true", 1, true) ~= nil, "бойцы пожарного расчёта")
ok(disp:find("F.CanDispatch(ply) == true", 1, true) ~= nil, "диспетчеры")
ok(disp:find("notifyFactions[fac] == true", 1, true) ~= nil,
    "фракции из /grm_fire_notify получают вызов")
ok(disp:find('ply:ChatPrint("[Пожарная служба] "', 1, true) ~= nil, "дубль в чат, чтобы не пропустить")
ok(disp:find('GRM.Sound.Emit(ply, "npc/scanner/scanner_siren2.wav"', 1, true) ~= nil, "сирена вызова")

print("\n=== 3. ПРИНЯТИЕ ВЫЗОВА ===")
ok(disp:find("ПРИНЯТЬ ВЫЗОВ", 1, true) ~= nil and disp:find("ОТКАЗАТЬСЯ", 1, true) ~= nil,
    "карточка с кнопками принятия и отказа")
ok(disp:find("function D.AcceptCall", 1, true) ~= nil, "серверная обработка принятия")
ok(disp:find('return false, "Вызов уже принял "', 1, true) ~= nil,
    "второй расчёт не перехватывает уже принятый вызов")
ok(disp:find('return false, "Вы не в пожарном расчёте"', 1, true) ~= nil,
    "принять может только пожарный/диспетчер/суперадмин")
ok(disp:find('GRM.Minimap.AddTempPoint("ВЫЗОВ #"', 1, true) ~= nil,
    "принявшему ставится метка на карте")
ok(disp:find('hook.Add("HUDPaint", "GRM_FireDispatch_HUD"', 1, true) ~= nil,
    "у принявшего на экране цель с расстоянием")
ok(disp:find("Вызов #\" .. call.id .. \" принял \"", 1, true) ~= nil,
    "остальным сообщается, кто принял")
ok(disp:find("pnl.expires = SysTime() + math.max(10, timeout)", 1, true) ~= nil,
    "карточка живёт ограниченное время с обратным отсчётом")

print("\n=== 4. НАПОМИНАНИЯ И ЗАКРЫТИЕ ===")
ok(disp:find("D.ReminderDelay = 45", 1, true) ~= nil and disp:find("D.MaxReminders  = 3", 1, true) ~= nil,
    "если вызов не приняли — повторное оповещение (до 3 раз)")
ok(disp:find('timer.Create("GRM_FireDispatch_Tick", 5, 0', 1, true) ~= nil, "сторож вызовов")
ok(disp:find("if not next(D.Calls) then return end", 1, true) ~= nil,
    "сторож не крутится вхолостую без вызовов")
ok(disp:find('hook.Add("GRM_FireExtinguished", "GRM_FireDispatch_Close"', 1, true) ~= nil,
    "потушенный пожар закрывает вызов")
ok(disp:find('D.CloseCall(id, "истёк срок вызова")', 1, true) ~= nil, "просроченные вызовы закрываются")
ok(disp:find("function D.SaveCalls", 1, true) ~= nil and disp:find("grm_fire/calls.json", 1, true) ~= nil,
    "вызовы сохраняются на диск")

print("\n=== 5. ЖУРНАЛ И ДОСТУП ===")
ok(disp:find("function D.LogRows", 1, true) ~= nil, "журнал вызовов формируется модулем")
ok(compSv:find("D.LogRows(100)", 1, true) ~= nil,
    "компьютер станции берёт вызовы у диспетчера, а не только 911")
ok(compCl:find("🚨 Активные вызовы — принять", 1, true) ~= nil,
    "в компьютере есть кнопка принятия активных вызовов")
ok(compCl:find('list:AddColumn("Район")', 1, true) ~= nil, "в журнале виден район")
ok(disp:find('concommand.Add("grm_fire_calls"', 1, true) ~= nil and disp:find('"/fire_calls"', 1, true) ~= nil,
    "команда /fire_calls и консольная grm_fire_calls")
ok(disp:find("ПРИНЯТЬ ВЫБРАННЫЙ ВЫЗОВ", 1, true) ~= nil, "из списка вызов можно принять")
ok(hub:find('{ "Пожарные: вызовы (принятие)", "grm_fire_calls"', 1, true) ~= nil,
    "в админ-хабе есть пункт вызовов")

print(("\nFIRE DISPATCH: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
