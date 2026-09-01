-- Симуляция Кода 108 (заказ владельца) БЕЗ GMod:
--  1) «Основной» отдел больше НЕ воскресает сам: раньше ensureDefaults
--     вставлял его при каждом вызове, а вызов идёт из каждого действия и
--     каждой рассылки SYNC — стоило удалить «Основной», как очередной sync
--     создавал его заново. Проверяем: удаление «Основного» держится и в
--     памяти, и в SYNC-пакете, и после «рестарта» модуля (loadFactions).
--  2) Дефолтный отдел участников — ПЕРВЫЙ РЕАЛЬНЫЙ (getDefaultDepartment),
--     а не литерал «Основной» из воздуха.
--  3) «Живые» вкладки меню /factions: refreshAllUI теперь перестраивает
--     админские «Ранги»/«Отделы»/«Список» и комбо ролей/отделов по КАЖДОЙ
--     рассылке SYNC_ALL — без перезапуска меню и перевыбора фракции.

string.Trim = string.Trim or function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false and not (istable(o) and o.__removed) end
function AddCSLuaFile() end
-- GLua-расширения table.*, которых нет в ваниле
table.HasValue = table.HasValue or function(t, v)
  for _, x in pairs(t) do if x == v then return true end end
  return false
end
table.Count = table.Count or function(t)
  local c = 0
  for _ in pairs(t or {}) do c = c + 1 end
  return c
end
HUD_PRINTTALK = HUD_PRINTTALK or 3

local checks, failed = 0, 0
local function ok(cond, label)
  checks = checks + 1
  if cond then print("  ok " .. checks .. ". " .. label)
  else failed = failed + 1 print("  FAIL " .. checks .. ". " .. label) end
end

local H = { hooks = {}, netrecv = {}, notifies = {} }

-- ── файлы+JSON в памяти (как в sim_ffdtools): TableToJSON->токен->deepCopy ──
local FILES, jsonhold = {}, {}
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepCopy(v) end
  return out
end
util = {
  AddNetworkString = function() end,
  TableToJSON = function(t) jsonhold[#jsonhold + 1] = t return "#SIMJSON" .. #jsonhold end,
  JSONToTable = function(txt)
    local i = tonumber(tostring(txt):match("#SIMJSON(%d+)"))
    return i and deepCopy(jsonhold[i]) or nil
  end,
  SteamIDTo64 = function() return "76561198000000000" end,
}
file = {
  Write = function(n, c) FILES[n] = c end,
  Read = function(n) return FILES[n] end,
  Exists = function(n) return FILES[n] ~= nil end,
}
hook = { Add = function(name, id, fn) H.hooks[name .. "/" .. id] = fn end, Run = function() end }
timer = { Create = function() end, Simple = function() end, Remove = function() end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end, GetBySteamID = function() return nil end }
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
sound = sound or {}
notification = { AddLegacy = function() end }
GRM = GRM or {}

-- ── сеть: маркер сообщений + захват SYNC_ALL-пакета ──
net = {
  Start      = function(m) H.curmsg = m end,
  WriteTable = function(t) if H.curmsg == "Factions_SyncAll" then H.lastSync = t end end,
  WriteString = function(v) H.lastWStr = v end,
  WriteBool   = function(v) H.lastWBool = v end,
  WriteUInt   = function() end,
  Send        = function() H.curmsg = nil end,
  Broadcast   = function() H.curmsg = nil end,
  SendToServer = function() H.curmsg = nil end,
  Receive     = function(m, fn) H.netrecv[m] = fn end,
  ReadString  = function() return table.remove(H.readStack, 1) end,
  ReadTable   = function() if H.readStack then return table.remove(H.readStack, 1) end return H.readTbl end,
  ReadBool    = function() return true end,
  ReadUInt    = function() return 0 end,
}
steamworks = { RequestPlayerInfo = function(_, cb) cb("Игрок") end }

local function mkPly(sid, sa)
  return {
    SteamID = function() return sid end,
    SteamID64 = function() return "765" .. tostring(sid):gsub("%D", "") end,
    IsSuperAdmin = function() return sa and true or false end,
    PrintMessage = function() end,
    Nick = function() return "Админ " .. tostring(sid) end,
  }
end

-- ════ ЧАСТЬ A (server): «Основной» не воскресает + дефолт первого отдела ════
print("== sh_factions.lua SERVER: удалённый «Основной» не воскресает ==")
SERVER, CLIENT = true, false
dofile("lua/autorun/sh_factions.lua")
ok(type(H.netrecv["Factions_Action"]) == "function" and type(_G.FactionsAPI) == "table",
   "сервер фракций загружен (actions + FactionsAPI)")

local admin = mkPly("STEAM_0:1:1", true)
local function fireAction(ply, action, args)
  H.readStack = { action, args or {} }
  H.netrecv["Factions_Action"](0, ply)
end
local function deptsOf(name)
  local f = (_G.FactionsAPI.List() or {})[name]
  return (f and f.Departments) or {}
end
local function hasDept(name, dept)
  for _, d in ipairs(deptsOf(name)) do if d == dept then return true end end
  return false
end

-- создаём фракцию: стартовый список отделов — «Основной» (осознанный дефолт
-- создания; владелец против именно ВОСКРЕШЕНИЯ после удаления)
fireAction(admin, "createFaction", { "Медики", "STEAM_0:1:7" })
ok(#deptsOf("Медики") == 1 and deptsOf("Медики")[1] == "Основной",
   "свежая фракция: один стартовый отдел «Основной» (дефолт создания, не баг)")

fireAction(admin, "addDepartment", { "Медики", "Патруль" })
fireAction(admin, "addDepartment", { "Медики", "ОМОН" })
ok(#deptsOf("Медики") == 3, "добавлены отделы Патруль и ОМОН")

-- ГЛАВНОЕ: удаляем «Основной» — он НЕ должен появиться заново
fireAction(admin, "removeDepartment", { "Медики", "Основной" })
ok(not hasDept("Медики", "Основной") and #deptsOf("Медики") == 2,
   "«Основной» удалён и НЕ воскрес в памяти (была автовставка в ensureDefaults)")
-- очередная рассылка (была в done() после каждого действия) тоже чистая
fireAction(admin, "renameDepartment", { "Медики", "ОМОН", "СОБР" }) -- ещё одно действие → sync
ok(not hasDept("Медики", "Основной") and deptsOf("Медики")[1] == "Патруль"
   and deptsOf("Медики")[2] == "СОБР",
   "после следующего действия «Основной» снова не появился")
ok(type(H.lastSync) == "table" and H.lastSync["Медики"]
   and not (function() for _, d in ipairs(H.lastSync["Медики"].Departments or {}) do
     if d == "Основной" then return true end end return false end)(),
   "SYNC-пакет клиентам тоже без «Основного» (раньше sync сам его и создавал)")

-- дефолтный отдел участника — ПЕРВЫЙ РЕАЛЬНЫЙ
local okA = _G.FactionsAPI.AddMember("Медики", "STEAM_0:1:9")
local mem = (_G.FactionsAPI.List())["Медики"].Members["STEAM_0:1:9"]
ok(okA and mem ~= nil and mem.Department == "Патруль",
   "новый участник без явного отдела попал в ПЕРВЫЙ РЕАЛЬНЫЙ (Патруль), не в «Основной»")

-- удаление отдела с участниками: они переезжают в первый оставшийся реальный
fireAction(admin, "removeDepartment", { "Медики", "Патруль" })
mem = (_G.FactionsAPI.List())["Медики"].Members["STEAM_0:1:9"]
ok(mem.Department == "СОБР" and not hasDept("Медики", "Основной"),
   "при удалении Патруля люди переехали в первый реальный (СОБР), «Основной» не появился")

-- последний отдел удалять нельзя — фракция не остаётся без отделов совсем
fireAction(admin, "removeDepartment", { "Медики", "СОБР" })
ok(#deptsOf("Медики") == 1 and deptsOf("Медики")[1] == "СОБР",
   "последний отдел защищён от удаления (гард по-прежнему на месте)")

-- «рестарт сервера»: перезагружаем модуль на той же файловой базе
dofile("lua/autorun/sh_factions.lua")
ok(type(H.netrecv["Factions_Action"]) == "function", "модуль перезагружен (имитация рестарта)")
ok(not hasDept("Медики", "Основной") and #deptsOf("Медики") == 1
   and deptsOf("Медики")[1] == "СОБР",
   "после загрузки из factions.json «Основной» НЕ воскрес (ensureAllDefaults чист)")
_G.FactionsAPI.Broadcast()
ok(H.lastSync and H.lastSync["Медики"] and H.lastSync["Медики"].Departments[1] == "СОБР",
   "и послерестартный SYNC — сразу чистый")

-- ════ ЧАСТЬ B (client): «живые» вкладки /factions по SYNC_ALL ════════
print("== sh_factions.lua CLIENT: вкладки Ранги/Отделы/Список живут без перезапуска ==")
SERVER, CLIENT = false, true
surface = { CreateFont = function() end }
draw = draw or {}
H.lastSync = nil

-- VGUI: дерево детей + комбо с выбором/вариантами.
-- ВАЖНО: __index-нуп возвращается только для методов; ключи с префиксом
-- «__» (наши поля) обязаны читаться как nil — иначе IsValid() стенда,
-- видя truthy o.__removed (нуп из метатаблицы), считает панель мёртвой.
local function mkVgui(cls, parent)
  local c = { _cls = cls, __children = {} }
  local mt = { __index = function(_, k)
    if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
    return function() return nil end
  end }
  setmetatable(c, mt)
  function c:AddChoice(text, data) self.__choices = self.__choices or {} self.__choices[#self.__choices + 1] = text end
  function c:Clear() self.__choices = {} self.__children = {} end
  function c:SetValue(v) self.__val = v end
  function c:GetValue() return self.__val end
  function c:SetText(t) self.__txt = t end
  function c:GetText() return self.__txt or "" end
  function c:SetChecked(v) self.__chk = v end
  function c:IsHovered() return false end
  if parent and parent.__children then parent.__children[#parent.__children + 1] = c end
  return c
end
vgui = { Create = mkVgui }
local function mkCombo(v) local c = mkVgui("DComboBox") c.__val = v return c end
local function mkScroll() return mkVgui("DScrollPanel") end

ui = { currentFrame = mkVgui("DFrame") } -- меню «открыто», ссылки на вкладки ниже
ui.factionComboRanks = mkCombo("Полиция") ui.ranksScroll = mkScroll()
ui.factionComboDepts = mkCombo("Полиция") ui.deptsScroll = mkScroll()
ui.factionComboList  = mkCombo("Полиция") ui.memberScroll = mkScroll()
ui.factionCombo3 = mkCombo("Полиция")
ui.roleCombo3 = mkCombo("Рядовой") ui.deptCombo3 = mkCombo("Основной")
ui.roleComboLeader = mkCombo("Рядовой") ui.deptComboLeader = mkCombo("Основной")
ui.ranksScrollLeader = mkScroll() -- лидерская вкладка «Ранги» тоже открыта

-- LocalPlayer — лидер «Полиции» (для лидерских вкладок и живых комбо)
LocalPlayer = function() return { SteamID = function() return "STEAM_0:1:9" end, IsSuperAdmin = function() return true end } end

dofile("lua/autorun/sh_factions.lua")
ok(type(H.netrecv["Factions_SyncAll"]) == "function", "клиент фракций загружен (SYNC-приёмник есть)")
ok(type(refreshAllUI) == "function", "refreshAllUI объявлен")

local function payload(roles, depts, members)
  return {
    ["Полиция"] = {
      Leader = "STEAM_0:1:9",
      Roles = roles, Departments = depts, Members = members or {},
      Tag = "", Color = { r = 255, g = 200, b = 50 }, DepAccess = false,
      LeaderRoleName = "Лидер",
    },
  }
end
local function fireSync(tbl) H.readStack = nil H.readTbl = tbl H.netrecv["Factions_SyncAll"]() end

-- 1-я рассылка: 2 ранга + 1 отдел, участников нет
fireSync(payload({ "Лидер", "Рядовой" }, { "Основной" }))
ok(#ui.ranksScroll.__children == 3, "админ-«Ранги»: 2 ранга + панель добавления = 3 строки")
ok(#ui.deptsScroll.__children == 2, "админ-«Отделы»: 1 отдел + панель добавления = 2 строки")
ok(#ui.memberScroll.__children == 0, "админ-«Список»: участников нет")
ok(#ui.ranksScrollLeader.__children == 3, "лидер-«Ранги»: тоже построен (2+1)")

-- 2-я рассылка МЕНЯЕТ состав: +ранг, +отдел, +участник — вкладки обязаны
-- перестроиться СРАЗУ (раньше мёртво висели до перевыбора фракции/перезапуска)
fireSync(payload({ "Лидер", "Рядовой", "Капитан" }, { "Основной", "ОМОН" },
  { ["STEAM_0:1:7"] = { Role = "Рядовой", Department = "Основной" } }))
ok(#ui.ranksScroll.__children == 4, "ЖИВАЯ вкладка «Ранги»: 3+1 строк без перезапуска меню")
ok(#ui.deptsScroll.__children == 3, "ЖИВАЯ вкладка «Отделы»: 2+1 строк без переключения вкладки")
ok(#ui.memberScroll.__children == 1, "ЖИВАЯ вкладка «Список»: участник появился сам")
ok(#ui.ranksScrollLeader.__children == 4, "лидер-«Ранги»: тоже перестроен по рассылке")

-- живые комбо ролей/отделов (админ и лидер): списки пересобраны, выбор сохранён
ok(ui.roleCombo3.__val == "Рядовой" and #(ui.roleCombo3.__choices or {}) == 3,
   "админ-комбо ролей: 3 варианта, выбранный «Рядовой» сохранён")
ok(ui.deptCombo3.__val == "Основной" and #(ui.deptCombo3.__choices or {}) == 2,
   "админ-комбо отделов: 2 варианта, выбранное сохранено")
ok(ui.roleComboLeader.__val == "Рядовой" and #(ui.roleComboLeader.__choices or {}) == 3,
   "лидер-комбо ролей: пересобрано по своей фракции")
ok(ui.deptComboLeader.__val == "Основной" and #(ui.deptComboLeader.__choices or {}) == 2,
   "лидер-комбо отделов: пересобрано по своей фракции")

-- удалённый ранг исчезает из комбо: выбор сбрасывается, список короче
fireSync(payload({ "Лидер", "Капитан" }, { "Основной" }))
ok(ui.roleCombo3.__val ~= "Рядовой" and #(ui.roleCombo3.__choices or {}) == 2,
   "ранг «Рядовой» удалён — комбо срезал список и не держит мёртвый выбор")
ok(#ui.ranksScroll.__children == 3, "вкладка «Ранги» сжалась до 2+1 строк")
-- фракция удалена шефом — вкладки по ней чистятся, комбо фракций пересобрано
fireSync({})
ok(#ui.ranksScroll.__children == 0 and #ui.deptsScroll.__children == 0,
   "фракции пропали: вкладки очистились, краша нет")
-- меню закрыто (ui.* = nil) — рассылка не роняет клиента
ui = {}
local okClosed = pcall(fireSync, payload({ "Лидер" }, { "Основной" }))
ok(okClosed, "SYNC_ALL при закрытом меню — тихо, без ошибок")

print("")
print(("РЕЗУЛЬТАТ: %d/%d проверок, провалов: %d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
print("SIM FACTIONS LIVE: OK")
