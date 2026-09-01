--[[ Живой прогон прав должностей, фаза 3 (заказ владельца 27.08).

     Проверяется:
       1) право должности работает наравне с правом звания;
       2) главное следствие: право можно отдать НАЧАЛЬНИКУ ОТДЕЛА, не
          раздавая его всем сержантам организации;
       3) наследование прав начальником — выключено по умолчанию;
       4) замещение заместителем — выключено по умолчанию и действует
          только пока начальника нет в сети;
       5) удаление должности уносит её права;
       6) старый файл доступов читается без изменений.

     Запуск: luajit tools/luatest/sim_faction_position_perms.lua ]]
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
function isentity(v) return istable(v) and v._entity == true end
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

local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Run = function(name, ...)
        for _, fn in pairs(hooks[name] or {}) do fn(...) end
    end,
}
timer = { Simple = function() end }
concommand = { Add = function() end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
util = {
    AddNetworkString = function() end,
    JSONToTable = function() return {} end,
    TableToJSON = function() return "{}" end,
}
net = { Start = function() end, Send = function() end, WriteTable = function() end,
    Receive = function() end, WriteString = function() end, WriteBool = function() end }
player = { GetAll = function() return {} end }
function print_dummy() end

GRM = {}
FactionsAPI = { Save = function() end }

assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions
assert(loadfile("lua/autorun/sh_grm_faction_perms.lua"))()
local PERMS = GRM.FactionPerms

-- Игроки: у каждого свой персонаж в составе.
local function mkPly(key, super)
    return { _entity = true, _valid = true, _key = key,
        IsSuperAdmin = function() return super == true end,
        SteamID = function() return key end,
        SteamID64 = function() return key end,
        GetNWString = function(_, k, d) return d or "" end,
        GetNWBool = function(_, _, d) return d or false end }
end

local FAC = {
    DisplayName = "Полиция",
    Departments = { "patrol", "transport" },
    Subdepartments = {},
    Roles = { "sergeant", "private" },
    Positions = {},
    Members = {},
}
Factions = { ["Полиция"] = FAC }

POS.Set("Полиция", "transport_head", { name = "Начальник транспортного отдела",
    node = "dept:transport", kind = "head", slots = 1 })
POS.Set("Полиция", "transport_deputy", { name = "Зам начальника транспорта",
    node = "dept:transport", kind = "deputy", slots = 1 })
POS.Set("Полиция", "mechanic", { name = "Механик",
    node = "dept:transport", kind = "staff", slots = 3 })

local head    = mkPly("1:char1")
local deputy  = mkPly("2:char1")
local mech    = mkPly("3:char1")
local sergeant = mkPly("4:char1")   -- сержант БЕЗ должности

FAC.Members["1:char1"] = { Role = "sergeant", Department = "transport", Position = "transport_head" }
FAC.Members["2:char1"] = { Role = "sergeant", Department = "transport", Position = "transport_deputy" }
FAC.Members["3:char1"] = { Role = "private",  Department = "transport", Position = "mechanic" }
FAC.Members["4:char1"] = { Role = "sergeant", Department = "patrol" }

-- Опознание персонажа: ключ участника ↔ игрок.
local online = { [head._key] = head, [deputy._key] = deputy, [mech._key] = mech, [sergeant._key] = sergeant }
GRM.Identity = {
    CharacterKey = function(p) return p._key end,
    FactionMember = function(f, p) return istable(f.Members) and f.Members[p._key] or nil end,
    ResolveCharacter = function(key) return online[key] end,
}

PERMS.Data = {}

print("\n=== 1. ГЛАВНОЕ: ПРАВО ТОЧЕЧНО, А НЕ ВСЕМ СЕРЖАНТАМ ===")
PERMS.GrantToPosition("Полиция", "transport_head", "fleet_manage")
ok(PERMS.PlayerHasPermission(head, "fleet_manage") == true,
   "начальник транспортного отдела распоряжается автопарком")
ok(PERMS.PlayerHasPermission(sergeant, "fleet_manage") == false,
   "другой сержант того же звания — НЕ распоряжается (раньше было невозможно)")
ok(PERMS.PlayerHasPermission(mech, "fleet_manage") == false, "механик отдела тоже не получает")

print("\n=== 2. ПРАВО ЗВАНИЯ РАБОТАЕТ КАК РАНЬШЕ ===")
PERMS.GrantToRole("Полиция", "sergeant", "plates_check")
ok(PERMS.PlayerHasPermission(sergeant, "plates_check") == true, "право звания действует")
ok(PERMS.PlayerHasPermission(head, "plates_check") == true, "и у начальника тоже — он сержант")
ok(PERMS.PlayerHasPermission(mech, "plates_check") == false, "рядовой звание не имеет — права нет")

print("\n=== 3. НАСЛЕДОВАНИЕ: ПО УМОЛЧАНИЮ ВЫКЛЮЧЕНО ===")
PERMS.GrantToPosition("Полиция", "mechanic", "fleet_buy")
ok(PERMS.PositionSettings("Полиция").inherit == false, "наследование выключено из коробки")
ok(PERMS.PlayerHasPermission(head, "fleet_buy") == false,
   "начальник НЕ получает право механика молча")

PERMS.SetPositionSetting("Полиция", "inherit", true)
ok(PERMS.PositionSettings("Полиция").inherit == true, "флаг включается")
ok(PERMS.PlayerHasPermission(head, "fleet_buy") == true,
   "после включения начальник наследует право подчинённой должности")
ok(PERMS.PlayerHasPermission(mech, "fleet_manage") == false,
   "наследование работает только сверху вниз, не наоборот")

-- Начальник ЧУЖОГО отдела наследовать не должен.
POS.Set("Полиция", "patrol_head", { name = "Начальник патруля", node = "dept:patrol", kind = "head", slots = 1 })
FAC.Members["4:char1"].Position = "patrol_head"
ok(PERMS.PlayerHasPermission(sergeant, "fleet_buy") == false,
   "начальник другого отдела чужие права не наследует")
PERMS.SetPositionSetting("Полиция", "inherit", false)

print("\n=== 4. ЗАМЕЩЕНИЕ: ТОЛЬКО КОГДА НАЧАЛЬНИКА НЕТ ===")
ok(PERMS.PositionSettings("Полиция").standin == false, "замещение выключено из коробки")
ok(PERMS.PlayerHasPermission(deputy, "fleet_manage") == false,
   "зам не получает права начальника, пока флаг выключен")

PERMS.SetPositionSetting("Полиция", "standin", true)
ok(PERMS.PlayerHasPermission(deputy, "fleet_manage") == false,
   "начальник в сети — зам всё ещё без его прав")

online[head._key] = nil          -- начальник вышел из игры
ok(PERMS.PlayerHasPermission(deputy, "fleet_manage") == true,
   "начальника нет в сети — зам замещает его")
ok(PERMS.PlayerHasPermission(mech, "fleet_manage") == false,
   "рядовой механик при этом ничего не замещает")

online[head._key] = head         -- вернулся
ok(PERMS.PlayerHasPermission(deputy, "fleet_manage") == false,
   "начальник вернулся — замещение прекращается")
PERMS.SetPositionSetting("Полиция", "standin", false)

print("\n=== 5. УДАЛЕНИЕ ДОЛЖНОСТИ УНОСИТ ПРАВА ===")
ok(PERMS.PositionHasPermission("Полиция", "mechanic", "fleet_buy") == true, "право механика на месте")
POS.Delete("Полиция", "mechanic")
ok(PERMS.PositionHasPermission("Полиция", "mechanic", "fleet_buy") == false,
   "права удалённой должности вычищены — новая одноимённая их не унаследует")
ok(PERMS.PlayerHasPermission(head, "fleet_manage") == true, "прочие права не задеты")

print("\n=== 6. СОВМЕСТИМОСТЬ СО СТАРЫМ ФАЙЛОМ ===")
PERMS.Data = { ["Полиция"] = { roles = { sergeant = { plates_issue = true } } } }
ok(PERMS.PlayerHasPermission(sergeant, "plates_issue") == true,
   "старый файл без раздела должностей читается как раньше")
ok(PERMS.GetFactionPositions("Полиция") ~= nil, "отсутствующий раздел должностей не роняет чтение")
ok(PERMS.PositionSettings("Полиция").inherit == false, "и настройки берутся по умолчанию")
FAC.Members["1:char1"].Position = ""
ok(PERMS.PlayerHasPermission(head, "plates_issue") == true,
   "сотрудник без должности живёт на одних званиях")

print("\n=== 7. СВЯЗКА С ОСТАЛЬНЫМИ МОДУЛЯМИ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local permsSrc = body("lua/autorun/sh_grm_faction_perms.lua")
local accessSrc = body("lua/autorun/sh_03_grm_access.lua")
local factionsSrc = body("lua/autorun/sh_factions.lua")
local uiSrc = body("lua/autorun/client/cl_grm_faction_perms_ui.lua")

ok(accessSrc:find("PERMS.PlayerHasPermission(ply, name)", 1, true) ~= nil,
   "GRM.Access ходит через ту же точку — должности работают во всех модулях сразу")
ok(permsSrc:find("PositionGrants", 1, true) ~= nil, "должностной источник встроен в проверку игрока")
ok(factionsSrc:find('SetNWString("GRM_Position"', 1, true) ~= nil,
   "должность networked — доступна фолбэку и другим модулям")
ok(permsSrc:find('GetNWString("GRM_Position"', 1, true) ~= nil,
   "запасной путь по NW-полям знает про должность")
ok(accessSrc:find("должность:", 1, true) ~= nil,
   "grm_access_check объясняет, что право могло прийти от должности")
ok(uiSrc:find("Доступы по должностям", 1, true) ~= nil, "в интерфейсе есть раздел должностей")
ok(uiSrc:find("GrantToPosition", 1, true) ~= nil, "интерфейс умеет выдавать право должности")
ok(uiSrc:find("Начальник наследует", 1, true) ~= nil, "переключатель наследования доступен")
ok(uiSrc:find("Заместитель получает", 1, true) ~= nil, "переключатель замещения доступен")
ok(permsSrc:find("GRM_FactionPositionChanged", 1, true) ~= nil,
   "модуль прав слушает удаление должностей")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
