-- sim_econ_access.lua — проверка доступа к экономическому меню (находка 172):
--   • E.CanManageEconomy: суперадмин всегда; фракция без настроек — нет;
--   • включённая фракция: вся фракция (roles/depts пусты);
--   • роли приоритетны: если roles заданы — доступ только по ним;
--   • иначе отделы: если depts заданы — доступ по отделам;
--   • NET_OPEN_ADMIN/NET_ADMIN_ACT пускают CanManageEconomy (не только суперадмин);
--   • каналы GRM_EcoAccess_* на месте.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function SysTime() return 1000 end
function os.time() return 1700000000 end
function math.random() return 1 end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
function table.Merge(a, b) for k, v in pairs(b or {}) do a[k] = v end return a end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
string.Trim = string.Trim or function(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
string.Left = string.Left or function(s, n) return string.sub(s, 1, n) end
string.StartWith = string.StartWith or function(s, p) return string.sub(s, 1, #p) == p end
string.Normalize = string.Normalize or function(s) return s end
function tobool(v) return v == true end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
function Angle() return { p = 0, y = 0, r = 0 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end

local H = { hooks = {}, netrecv = {}, netlog = {}, seq = {}, timerFns = {} }
hook = { Add = function() end, Run = function() end }
timer = { Create = function() end, Simple = function(_, fn) if fn then fn() end end, Remove = function() end }
concommand = { Add = function() end }
util = {
  AddNetworkString = function() end, CRC = function(s) return tostring(#s) end,
  TableToJSON = function() return "{}" end, JSONToTable = function() return nil end,
  SteamIDTo64 = function(s) return "7656" .. tostring(#s) end,
}
net = {
  Start = function(m) H.netlog.cur = { msg = m, f = {} } end,
  WriteString = function(v) table.insert(H.netlog.cur.f, tostring(v or "")) end,
  WriteTable = function(v) table.insert(H.netlog.cur.f, v or {}) end,
  WriteUInt = function() end, WriteBool = function(v) table.insert(H.netlog.cur.f, v == true) end,
  WriteData = function() end, WriteEntity = function() end, WriteVector = function() end,
  Send = function() H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end,
  Broadcast = function() H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end,
  Receive = function(m, fn) H.netrecv[m] = fn end,
  ReadString = function() return tostring(table.remove(H.seq, 1) or "") end,
  ReadTable = function() return table.remove(H.seq, 1) or {} end,
  ReadUInt = function() return tonumber(table.remove(H.seq, 1) or 0) end,
  ReadBool = function() local v = table.remove(H.seq, 1) return v == true end,
  ReadData = function() return "" end,
}
local function netCount(msg)
  local n = 0 for _, e in ipairs(H.netlog) do if e.msg == msg then n = n + 1 end end return n
end
game = { GetMap = function() return "gm" end }
ents = { GetAll = function() return {} end }
local __files = {}
file = {
  CreateDir = function() end, Exists = function(p) return __files[p] ~= nil end,
  Read = function(p) return __files[p] end, Write = function(p, s) __files[p] = s end, Find = function() return {} end,
}

-- ── игрок ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "SteamID" then return function(s) return s.sid end
  elseif k == "SteamID64" then return function(s) return s.s64 end
  elseif k == "Nick" then return function(s) return s.nick end
  elseif k == "IsSuperAdmin" then return function(s) return s.super == true end
  elseif k == "EntIndex" then return function(s) return s.idx or 1 end
  elseif k == "GetNWBool" then return function() return false end
  elseif k == "GetNWInt" then return function() return 0 end
  elseif k == "GetNWFloat" then return function() return 0 end
  elseif k == "GetNWString" then return function() return "" end
  elseif k == "GetPos" then return function() return { x = 0, y = 0, z = 0 } end
  elseif k == "EmitSound" then return function() end
  elseif k == "ChatPrint" then return function() end
  elseif k == "PrintMessage" then return function() end
  elseif k == "TakeDamage" then return function() end
  end
  return nil
end
local function mkPly(nick, sid, s64, isSuper) return setmetatable({ nick = nick, sid = sid, s64 = s64, super = isSuper == true, idx = 1 }, PMT) end

-- ── фракции ──
local BankLeaderSid = "STEAM_0:1:100"
local BankDeputySid = "STEAM_0:1:101"
local BankCashierSid = "STEAM_0:1:102"
local BankJanitorSid = "STEAM_0:1:103"
Factions = {
  ["Нацбанк"] = {
    Leader = BankLeaderSid, LeaderRoleName = "Лидер",
    Roles = { "Лидер", "Заместитель", "Кассир", "Уборщик" },
    Departments = { "Правление", "Операционный", "Хозчасть" },
    Members = {
      [BankLeaderSid] = { Role = "Лидер", Department = "Правление" },
      [BankDeputySid] = { Role = "Заместитель", Department = "Правление" },
      [BankCashierSid] = { Role = "Кассир", Department = "Операционный" },
      [BankJanitorSid] = { Role = "Уборщик", Department = "Хозчасть" },
    },
  },
  ["Мэрия"] = { Leader = "STEAM_0:1:200", Roles = { "Лидер" }, Departments = { "Общий" }, Members = {} },
}
GRM = GRM or {}
GRM.Identity = { CharacterKey = function(p) return p.s64 .. ":char1" end }
GRM.Notify = function() end

local leader = mkPly("Лидер", BankLeaderSid, "76561198000000100")
local deputy = mkPly("Зам", BankDeputySid, "76561198000000101")
local cashier = mkPly("Кассир", BankCashierSid, "76561198000000102")
local janitor = mkPly("Уборщик", BankJanitorSid, "76561198000000103")
local super = mkPly("Главный", "STEAM_0:1:99", "76561198000000099", true)
player = { GetAll = function() return { super, leader, deputy, cashier, janitor } end }

-- ══════════════ ЗАГРУЗКА ЭКОНОМИКИ ══════════════
dofile("lua/autorun/sh_grm_economy.lua")
ok(GRM.Economy ~= nil, "экономика загружена")
ok(GRM.Economy.CanManageEconomy ~= nil, "E.CanManageEconomy определён")

-- ══════════════ 1. БАЗОВЫЕ ПРОВЕРКИ ══════════════
ok(GRM.Economy.CanManageEconomy(super) == true, "суперадмин — всегда доступ")
ok(GRM.Economy.CanManageEconomy(leader) == false, "лидер без выданного доступа — нет")

-- ══════════════ 2. ВКЛЮЧЁННАЯ ФРАКЦИЯ (все члены) ══════════════
GRM.Economy.Access["Нацбанк"] = { enabled = true, roles = {}, departments = {} }
ok(GRM.Economy.CanManageEconomy(leader) == true, "вся фракция: лидер — да")
ok(GRM.Economy.CanManageEconomy(janitor) == true, "вся фракция: уборщик — да (роли/отделы пусты)")
ok(GRM.Economy.CanManageEconomy(cashier) == true, "вся фракция: кассир — да")

-- ══════════════ 3. РОЛИ ПРИОРИТЕТНЫ ══════════════
GRM.Economy.Access["Нацбанк"] = { enabled = true, roles = { ["Лидер"] = true, ["Заместитель"] = true }, departments = { ["Операционный"] = true } }
ok(GRM.Economy.CanManageEconomy(leader) == true, "роли: лидер — да")
ok(GRM.Economy.CanManageEconomy(deputy) == true, "роли: заместитель — да")
ok(GRM.Economy.CanManageEconomy(cashier) == false, "роли: кассир (в Операционном, но роли заданы) — НЕТ (роли приоритетны)")
ok(GRM.Economy.CanManageEconomy(janitor) == false, "роли: уборщик — НЕТ")

-- ══════════════ 4. ОТДЕЛЫ (роли пусты) ══════════════
GRM.Economy.Access["Нацбанк"] = { enabled = true, roles = {}, departments = { ["Правление"] = true } }
ok(GRM.Economy.CanManageEconomy(leader) == true, "отделы: лидер (Правление) — да")
ok(GRM.Economy.CanManageEconomy(deputy) == true, "отделы: зам (Правление) — да")
ok(GRM.Economy.CanManageEconomy(cashier) == false, "отделы: кассир (Операционный) — НЕТ")

-- ══════════════ 5. ДРУГАЯ ФРАКЦИЯ ══════════════
ok(GRM.Economy.CanManageEconomy(mkPly("Мэр", "STEAM_0:1:200", "76561198000000200")) == false, "член Мэрии — НЕТ (доступ не выдан)")

-- ══════════════ 6. NET-КОНТРАКТ ══════════════
ok(H.netrecv["GRM_EcoAccess_Request"] ~= nil, "GRM_EcoAccess_Request зарегистрирован")
ok(H.netrecv["GRM_EcoAccess_Save"] ~= nil, "GRM_EcoAccess_Save зарегистрирован")
ok(H.netrecv["GRM_Eco_AdminOpen"] ~= nil, "GRM_Eco_AdminOpen зарегистрирован")
ok(H.netrecv["GRM_Eco_AdminAction"] ~= nil, "GRM_Eco_AdminAction зарегистрирован")

-- не-суперадмин НЕ может настроить доступ
local before = table.Count(GRM.Economy.Access)
H.seq = { "Нацбанк", true, { ["Лидер"] = true }, {} }
H.netrecv["GRM_EcoAccess_Save"](0, leader)
ok(table.Count(GRM.Economy.Access) == before, "не-суперадмин НЕ может сохранить доступ")

-- суперадмин сохраняет
H.seq = { "Нацбанк", true, { ["Лидер"] = true }, {} }
H.netrecv["GRM_EcoAccess_Save"](0, super)
ok(GRM.Economy.Access["Нацбанк"] ~= nil and GRM.Economy.Access["Нацбанк"].roles["Лидер"] == true, "суперадмин сохранил доступ (роль Лидер)")

-- сохранение на диск
ok(__files["grm_economy_access.json"] ~= nil, "файл grm_economy_access.json записан")

-- ══════════════ 7. ХАБ: openHub пускает CanManageEconomy ══════════════
local hubSrc = assert(io.open("lua/autorun/sh_grm_admin_hub.lua", "rb"))
local hubCode = hubSrc:read("*a") hubSrc:close()
ok(hubCode:find("CanManageEconomy", 1, true) ~= nil, "хаб использует CanManageEconomy")
ok(hubCode:find("econAccess", 1, true) ~= nil, "хаб шлёт флаг econAccess")
ok(hubCode:find("GRM_EcoAccess_Request", 1, true) ~= nil, "хаб: кнопка запроса доступа")

-- ══════════════ 8. ВКЛАДКА «ЭКОНОМИКА» В /factions (находка 172) ══════════════
local ffSrc = assert(io.open("lua/autorun/sh_faction_fixes.lua", "rb"))
local ffCode = ffSrc:read("*a") ffSrc:close()
ok(ffCode:find('OpenEconomyPanel', 1, true) ~= nil, "/factions: вкладка «Экономика» (OpenEconomyPanel)")
ok(ffCode:find('BuildAdminContent', 1, true) ~= nil, "/factions: вкладка встраивает BuildAdminContent (полная панель)")
ok(ffCode:find('GRM_Eco_AdminOpen', 1, true) ~= nil, "/factions: вкладка запрашивает данные экономики")
ok(ffCode:find('EmbedAdminPanel', 1, true) ~= nil, "/factions: вкладка регистрируется для обновления")
-- Находка 177: build принимает данные и из 1-го, и из 2-го аргумента
ok(ffCode:find('local function build(a, b)', 1, true) ~= nil and ffCode:find('local d = b or a', 1, true) ~= nil, "/factions: build защищён от лишнего аргумента (находка 177)")

local econSrc = assert(io.open("lua/autorun/sh_grm_economy.lua", "rb"))
local econCode = econSrc:read("*a") econSrc:close()
-- Находка 177b: серверные ограничения административных действий
ok(econCode:find('if ply:IsSuperAdmin() then', 1, true) ~= nil and econCode:find('fp.enabled       = a.fine.enabled == true', 1, true) ~= nil, "сервер: система штрафов сохраняется только суперадмином (находка 177c)")
ok(econCode:find('fp.maxAmount = math.max(0, math.floor(tonumber(a.fine.maxAmount) or fp.maxAmount))', 1, true) ~= nil, "сервер: лимит штрафа могут менять все с доступом (находка 177c)")
ok(econCode:find('elseif a.action == "player_give" or a.action == "player_take" or a.action == "player_set" then', 1, true) ~= nil and econCode:find('if not ply:IsSuperAdmin() then return end', 1, true) ~= nil, "сервер: изменение балансов игроков — только суперадмин (находка 177b)")
ok(econCode:find('elseif a.action == "config_save" and istable(a.config) then', 1, true) ~= nil and econCode:find('if not ply:IsSuperAdmin() then return end', 1, true) ~= nil, "сервер: config_save — только суперадмин (находка 177b)")
ok(econCode:find('function GRM.Economy.BuildAdminContent', 1, true) ~= nil, "экономика: BuildAdminContent публичная")
ok(econCode:find('function GRM.Economy.EmbedAdminPanel', 1, true) ~= nil, "экономика: EmbedAdminPanel публичная")
ok(econCode:find('parentTabs', 1, true) ~= nil, "экономика: buildAdminUI параметризован (parentTabs)")
-- Находка 177: данные передаются во втором аргументе (панель — в первом)
ok(econCode:find('GRM.Economy._embeddedBuild(GRM.Economy.EmbeddedAdmin, d)', 1, true) ~= nil, "экономика: _embeddedBuild(panel, d) — данные не теряются (находка 177)")

-- Находка 177: вкладку «Экономика» больше НЕ добавляет старый feco_admin (дубль)
local fecoSrc = assert(io.open("lua/autorun/sh_grm_feco_admin.lua", "rb"))
local fecoCode = fecoSrc:read("*a") fecoSrc:close()
ok(fecoCode:find('GRM_FecoAdmin_Tab', 1, true) == nil, "feco_admin: дублирующая вкладка убрана (находка 177)")
ok(fecoCode:find('Консольная команда', 1, true) ~= nil, "feco_admin: модуль (окно/команды) сохранён")

local facSrc = assert(io.open("lua/autorun/sh_factions.lua", "rb"))
local facCode = facSrc:read("*a") facSrc:close()
ok(facCode:find('CanManageEconomy', 1, true) ~= nil, "/factions: сервер пускает CanManageEconomy")
ok(facCode:find('GRM_FactionsAdmin_BuildTabs', 1, true) ~= nil, "/factions: хук вкладок в OpenLeaderMenu")

print(("ECON ACCESS: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
