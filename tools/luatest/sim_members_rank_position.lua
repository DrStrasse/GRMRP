--[[ Живой прогон двух правок 27.08 по отчёту владельца.

     1) «Закрытие меню фракций вызывает меню pcboard».
        Вкладка «Госбаза» внутри /factions при создании просит у сервера
        снимок допусков. Ответ приходит на кадр-другой позже. Если меню уже
        закрыли, панель вкладки уничтожена — и обработчик, не найдя её,
        открывал ОТДЕЛЬНОЕ полноэкранное окно.

     2) «В разделе личного состава ранги от должностей отличаться должны».
        Колонка «Должность» показывала ЗВАНИЕ, кнопка «Изменить должность»
        меняла ЗВАНИЕ, а настоящей должности в списке не было вовсе.

     Запуск: luajit tools/luatest/sim_members_rank_position.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function string.Explode(sep, str)
    local out = {}
    for piece in string.gmatch(tostring(str or "") .. sep, "(.-)" .. sep) do out[#out + 1] = piece end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
GRM = {}
FactionsAPI = { Save = function() end }

local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local pcb = body("lua/autorun/client/cl_grm_pcboard_ui.lua")
local ui = body("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local fac = body("lua/autorun/sh_factions.lua")

print("\n=== 1. ГОСБАЗА БОЛЬШЕ НЕ ВЫСКАКИВАЕТ ПРИ ЗАКРЫТИИ ФРАКЦИЙ ===")
ok(pcb:find("function PB.OpenAccessMenu(payload, wantWindow)", 1, true) ~= nil,
   "открытие окна стало осознанным решением, а не побочным эффектом")
ok(pcb:find("if wantWindow ~= true and not IsValid(PB._accessFrame) then return end", 1, true) ~= nil,
   "снимок для вкладки НЕ открывает отдельное окно — корень бага закрыт")
ok(pcb:find("function PB.RequestAccessMenu(wantWindow)", 1, true) ~= nil,
   "запрос сообщает, чего от ответа ждут")
ok(pcb:find("PB._wantWindow = nil", 1, true) ~= nil,
   "флаг сбрасывается после ответа — следующий снимок не откроет окно случайно")
ok(pcb:find('concommand.Add("grm_pcboard_access", function() PB.RequestAccessMenu(true) end)', 1, true) ~= nil,
   "явная команда игрока по-прежнему открывает окно")
ok(pcb:find("if IsValid(panel) then PB.RequestAccessMenu(false) end", 1, true) ~= nil,
   "встроенная вкладка просит снимок для себя, без окна")
ok(pcb:find("PB.RequestAccessMenu(not IsValid(PB._accessHost) and IsValid(PB._accessFrame))", 1, true) ~= nil,
   "кнопка «Обновить» сохраняет текущий режим: во вкладке — вкладка, в окне — окно")

print("\n=== 2. ЗВАНИЕ И ДОЛЖНОСТЬ РАЗВЕДЕНЫ В ЛИЧНОМ СОСТАВЕ ===")
ok(ui:find('list:AddColumn("Звание")', 1, true) ~= nil, "появилась отдельная колонка звания")
ok(ui:find('list:AddColumn("Должность")', 1, true) ~= nil, "и отдельная колонка должности")
local rankIdx = ui:find('list:AddColumn("Звание")', 1, true)
local posIdx = ui:find('list:AddColumn("Должность")', 1, true)
ok(rankIdx and posIdx and rankIdx < posIdx, "звание идёт перед должностью")
ok(ui:find("GRM.Positions.OfMember(fac, rec)", 1, true) ~= nil,
   "должность берётся из записи сотрудника")
ok(ui:find("roleDisplay, posDisplay", 1, true) ~= nil,
   "в строку списка уходят обе величины, а не одна")
ok(ui:find("posObj and C.gold or C.dim", 1, true) ~= nil,
   "должность подсвечена: начальника видно в списке сразу")
ok(ui:find('posDisplay = "—"', 1, true) ~= nil,
   "сотрудник без должности показывается прочерком, а не пусто")

print("\n=== 3. КНОПКИ НАЗЫВАЮТ ВЕЩИ СВОИМИ ИМЕНАМИ ===")
ok(ui:find('mkBtn(bBar, "Изменить звание"', 1, true) ~= nil,
   "кнопка меняет звание и называется «Изменить звание»")
ok(ui:find('mkBtn(bBar, "Назначить должность"', 1, true) ~= nil,
   "добавлена отдельная кнопка назначения должности")
ok(ui:find('mkBtn(bBar, "Изменить должность"', 1, true) == nil,
   "старой обманчивой кнопки больше нет")
ok(ui:find('sendAction("positionAssign"', 1, true) ~= nil,
   "кнопка шлёт действие назначения должности")
ok(ui:find("— снять с должности —", 1, true) ~= nil, "и позволяет снять с должности")
ok(ui:find("st.free <= 0 and (not own or own.id ~= pos.id)", 1, true) ~= nil,
   "занятые места помечены до клика, а не отказом сервера после")

print("\n=== 4. ОСТАЛЬНЫЕ ПОДПИСИ ПРИВЕДЕНЫ В ПОРЯДОК ===")
ok(ui:find("Звания и ранги (Roles)", 1, true) ~= nil,
   "в «Структуре» список званий подписан званиями")
ok(ui:find("Системный ключ нового звания (eng)", 1, true) ~= nil, "создание звания подписано верно")
ok(ui:find("Новое публичное название звания", 1, true) ~= nil, "переименование звания тоже")
ok(ui:find("Выберите звание в списке!", 1, true) ~= nil, "и подсказки при выборе")
ok(fac:find('draw.SimpleText("Звание:  "', 1, true) ~= nil,
   "окно приглашения показывает звание под верной подписью")
ok(fac:find('"\\nЗвание:  "', 1, true) ~= nil, "и подтверждение приглашения тоже")

print("\n=== 5. РАЗДЕЛ ДОЛЖНОСТЕЙ НЕ ЗАДЕТ ===")
ok(ui:find('addTabBtn("positions"', 1, true) ~= nil, "раздел «Должности» на месте")
ok(ui:find("buildPositionsTab", 1, true) ~= nil, "его построитель на месте")

print("\n=== 6. ЖИВАЯ ПРОВЕРКА ДАННЫХ ===")
assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions
local FAC = {
    DisplayName = "828-ая дивизия ВДВ",
    Departments = { "hq" }, Subdepartments = {},
    Roles = { "general_major", "sergeant" },
    Positions = {}, Members = {},
}
Factions = { ["828"] = FAC }
POS.Set("828", "div_commander", { name = "Командир дивизии", node = "dept:hq", kind = "head", slots = 1 })

-- Ровно случай со скриншота: генерал-майор в штабе.
local general = { Role = "general_major", Department = "hq", Position = "div_commander" }
local sergeant = { Role = "sergeant", Department = "hq" }
FAC.Members["1:char1"] = general
FAC.Members["2:char1"] = sergeant

ok(POS.OfMember(FAC, general).name == "Командир дивизии",
   "у генерал-майора видна должность отдельно от звания")
ok(general.Role == "general_major", "и звание при этом осталось прежним")
ok(POS.OfMember(FAC, sergeant) == nil,
   "сотрудник без должности законен — в списке будет прочерк")
ok(general.Role ~= sergeant.Role and POS.OfMember(FAC, general) ~= nil,
   "две оси видны в списке независимо друг от друга")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
