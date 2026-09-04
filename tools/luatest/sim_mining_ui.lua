--[[--------------------------------------------------------------------
    sim_mining_ui — заказ владельца 19.08: «всё что касается торгашей и
    шахты mine исправить, пофиксить, доработать, особенно дизайн GRM окон
    + получение и сдача инструмента weapon_jackhammer_sd».

    Живая логика — sim_mining_runtime.lua. Здесь: состав модуля, окна и
    вычищенные болячки старого кода.
    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_mining_ui.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local core   = read("lua/autorun/sh_grm_mining.lua")
local admin  = read("lua/autorun/sh_grm_ore_admin.lua")
local buyerS = read("lua/entities/grm_ore_buyer/init.lua")
local buyerC = read("lua/entities/grm_ore_buyer/cl_init.lua")
local buyerSh= read("lua/entities/grm_ore_buyer/shared.lua")
local node   = read("lua/entities/grm_ore_node.lua")
local chunk  = read("lua/entities/grm_ore_chunk.lua")
local vendC  = read("lua/entities/grm_vendor/cl_init.lua")

print("\n=== 1. ЯДРО ШАХТЫ ===")
ok(has(core, 'M.Version = "2.0.0"'), "модуль шахты версионирован")
ok(has(core, "M.OreOrder") and has(core, "M.Ores = {"), "типы руды в одном реестре")
ok(has(core, "function M.SavePrices") and has(core, "function M.LoadPrices"),
    "цены сохраняются в файл (раньше сбрасывались рестартом)")
ok(has(core, 'PRICE_FILE = DIR .. "/prices.json"'), "файл цен на месте")
ok(has(core, "SAVE read-back ПУСТ"), "запись проверяется чтением обратно")
ok(has(core, "function M.Sell"), "продажа считается на сервере")
ok(has(core, 'if IsValid(buyer) and ply:GetPos():DistToSqr(buyer:GetPos()) > M.Config.UseDistance ^ 2 then'),
    "дистанция до скупщика проверяется")
ok(has(core, 'if ore == "all" then'), "поддержана продажа всей руды разом")
ok(has(core, "GRM.Net.Guard(ply, key"), "сетевые приёмы под guard")
ok(has(core, "function M.CountOres"), "количество руды берётся из инвентаря, а не со слов клиента")

print("\n=== 2. ИНСТРУМЕНТ (weapon_jackhammer_sd) ===")
ok(has(core, 'M.ToolClasses = { "weapon_jackhammer_sd"'), "класс бура вынесен в конфиг со списком запасных")
ok(has(core, "function M.ToolClass"), "берётся реально зарегистрированный на сервере класс")
ok(has(core, "Аддон бура не установлен на сервере"), "если аддона нет — честное сообщение, а не тишина")
ok(has(core, "function M.GiveTool") and has(core, "function M.ReturnTool"), "выдача и сдача — отдельные функции")
ok(has(core, "if hasTool(ply) then return false, \"Бур уже у вас на руках\" end"), "второй бур на руки не выдаётся")
ok(has(core, 'CreateConVar("grm_mining_deposit"'), "залог настраивается конваром")
ok(has(core, 'GRM.TakeMoney(ply, deposit, "Залог за бур")') and has(core, "Возврат залога за бур"),
    "залог списывается при выдаче и возвращается при сдаче")
ok(has(core, "Возврат залога: бур не выдан"), "если выдача сорвалась — залог возвращается сразу")
ok(has(core, 'hook.Add("PlayerDeath", "GRM_Mining_ToolOnDeath"'), "бур не уносится в могилу")
ok(has(core, "function M.IsMiningTool"), "проверка «это бур» в одном месте")

print("\n=== 3. ДОБЫЧА ===")
ok(has(core, "function M.PushProgress") and has(core, "ply.GRMMiningNextPush"),
    "прогресс добычи троттлится (раньше пакет шёл на каждый удар)")
ok(has(core, "Руда добывается только буром"), "подсказка, если бьют не тем")
ok(not has(node, 'print("[GRM Ore Node]'), "отладочный спам из узла руды убран")
ok(not has(chunk, 'print("[GRM Ore Chunk]'), "отладочный спам из куска руды убран")
ok(has(node, 'self:SetNWString("GRM_OreType", oreType)'), "тип руды виден клиенту (для подписи прогресса)")
ok(has(chunk, "Собираем и соседние куски"), "кучка руды подбирается одним нажатием")
ok(has(chunk, "Инвентарь полон"), "переполнение инвентаря объясняется игроку")

print("\n=== 4. ОКНО СКУПЩИКА В СТИЛЕ GRM ===")
ok(has(buyerC, "GRM · СКУПЩИК РУДЫ"), "шапка в стиле GRM")
ok(has(buyerC, "gold    = Color(245, 195, 65)"), "палитра GRM")
ok(has(buyerC, "math.Clamp(ScrW() * 0.60, 860, 1180)"), "окно стало широким")
ok(not has(buyerC, 'vgui.Create("DListView"'), "старый DListView убран")
ok(has(buyerC, "ИНСТРУМЕНТ ДОБЫЧИ") and has(buyerC, "ПОЛУЧИТЬ БУР") and has(buyerC, "СДАТЬ БУР"),
    "раздел инструмента с выдачей и сдачей")
ok(has(buyerC, "ПРОДАТЬ ВСЁ"), "кнопка «продать всё»")
ok(has(buyerC, "Залог: "), "видно размер залога")
ok(has(buyerC, "GRM.Sign.Draw") and has(buyerC, "function ENT:DrawTranslucent"),
   "вывеска скупщика — общий слой GRM.Sign, один проход за кадр")
ok(not has(buyerC, 'hook.Add("HUDPaint", "GRM_OreBuyerLabel"'), "перебор всех скупщиков каждый кадр убран")
ok(has(vendC, "GRM.Sign.Draw") and not has(vendC, 'hook.Add("HUDPaint", "GRM_VendorLabel"'),
    "вывеска торгашей тоже идёт через GRM.Sign")

print("\n=== 5. ЧИСТОТА КОДА ===")
local sellHandlers = 0
for _, src in ipairs({ core, admin, buyerS }) do
    for _ in src:gmatch('net%.Receive%("grm_ore_sell"') do sellHandlers = sellHandlers + 1 end
end
ok(sellHandlers == 1, "приёмник продажи ровно один", sellHandlers)
ok(not has(buyerS, "ply:Give(\"weapon_jackhammer_sd\")"), "скупщик больше не выдаёт бур в обход правил")
ok(has(buyerS, "GRM.Mining.PushBuyer"), "скупщик только открывает окно, логика в ядре")
ok(has(buyerS, "self:NextThink(CurTime() + 0.25)"), "Think NPC больше не крутится 50 раз в секунду")
ok(has(buyerSh, "ENT.AdminOnly = true"), "скупщика из спавн-меню ставит только администрация")
ok(has(admin, "!mineclean"), "добавлена уборка валяющейся руды")
ok(has(admin, 'hook.Add("PlayerSay", "GRM_OreAdminCmdsEC"'), "команды — боевая цепочка PlayerSay + реестр")

print(("\nMINING UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
