-- sim_alarm_integration.lua — проверка интеграции сигнализации с устройствами
-- доступа (находка 179h):
--   • события: неверный PIN кейпада, взлом взломщиком (кейпад/сканер/дверь),
--     отказ сканера — пишутся в A.Log (kind="breach") и оповещают фракции;
--   • настройка оповещаемых фракций суперадмином (чекбоксы, /grm_alarm_notify,
--     GRM_AlarmNotify_Save), пусто = никто;
--   • хуки GRM_KeypadDenied / GRM_ScannerDenied вызываются кейпадом/сканером.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
include = function(p)
  if p == "shared.lua" then return end
  dofile("lua/" .. p)
end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b) return { r = r or 0, g = g or 0, b = b or 0 } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end

local VMT = {
  __index = function(t, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
  end,
  __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

local H = { hooks = {}, netrecv = {}, cmds = {}, logs = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function(n, ...) local h = H.hooks[n] if h then for _, f in pairs(h) do f(...) end end end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function(n, fn) H.cmds[n] = fn end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return nil end, IsValidModel = function() return true end }
file = { IsDir = function() return true end, CreateDir = function() end, Exists = function() return false end, Read = function() return nil end, Write = function() end, Find = function() return {} end }
os = { time = function() return 1700000000 end, date = function() return "2026-08-05" end }
game = { GetMap = function() return "rp_test" end }
player = { GetAll = function() return _G.__players or {} end }
net = {
  Start = function() end, WriteEntity = function() end, WriteString = function() end, WriteBool = function() end,
  WriteUInt = function() end, WriteTable = function() end, Send = function() end, Broadcast = function() end,
  Receive = function(n, fn) H.netrecv[n] = fn end, ReadEntity = function() return nil end, ReadString = function() return "" end,
  ReadBool = function() return false end, ReadTable = function() return _G.__nextTbl or {} end, ReadUInt = function() return 0 end,
}
ents = { FindInSphere = function() return {} end, FindByClass = function() return {} end }

local function mkPly(super, nick, sid, steam)
  return {
    __valid = true, super = super == true, nick = nick or "Игрок",
    sid64 = sid or (super and "76561198000000001" or "76561198000000002"), sid = steam or "STEAM_0:1:1",
    IsSuperAdmin = function(self) return self.super end,
    IsPlayer = function() return true end,
    SteamID64 = function(self) return self.sid64 end,
    SteamID = function(self) return self.sid end,
    Nick = function(self) return self.nick end,
    GetPos = function() return Vector(0, 0, 0) end,
  }
end
local function mkEnt(cls, extra)
  local e = { __valid = true, __cls = cls, pos = Vector(0, 0, 0) }
  for k, v in pairs(extra or {}) do e[k] = v end
  e.GetClass = function() return e.__cls end
  e.GetPos = function() return e.pos end
  e.GetNetworkID = function() return "main" end
  e.IsPlayer = function() return false end
  e.IsNPC = function() return false end
  e.IsWorld = function() return false end
  return e
end

Factions = {
  Mafia = { Members = { ["STEAM_0:1:1"] = { Role = "Boss" } }, Leader = "STEAM_0:1:1", Roles = {}, Departments = {} },
  Polizei = { Members = { ["STEAM_0:1:2"] = { Role = "Chief" } }, Leader = "STEAM_0:1:2", Roles = {}, Departments = {} },
}
GRM = {
  Notify = function() end,
  Format = function(n) return tostring(n) end,
  Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end, FactionMember = function(fData, ply) return fData.Members[ply:SteamID()] end },
  Minimap = { AddTempPoint = function() end, SendTo = function() end },
}

-- ══════════════ ЗАГРУЗКА ══════════════
dofile("lua/autorun/sh_grm_alarm_config.lua")
-- attempt-guard-convars
FCVAR_ARCHIVE = FCVAR_ARCHIVE or 1
if not CreateConVar then
    local CV = {}
    function CreateConVar(name, def)
        local cv = { value = def }
        function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
        function cv:GetBool() return tostring(self.value) ~= "0" end
        function cv:GetFloat() return tonumber(self.value) or 0 end
        function cv:GetString() return tostring(self.value) end
        function cv:SetValue(v) self.value = v end
        CV[name] = cv
        return cv
    end
    function GetConVar(n) return CV[n] end
end
dofile("lua/autorun/server/sv_grm_alarm.lua")
dofile("lua/autorun/sh_grm_alarm_integration.lua")
local AN = GRM.AlarmNotify
ok(AN ~= nil and AN.Report ~= nil and AN.NotifyFactions ~= nil, "модуль интеграции загружен")

-- ══════════════ 1. Настройка фракций (суперадмин) ══════════════
ok(istable(AN.Data.factions) and table.Count(AN.Data.factions) == 0, "изначально: никто не оповещается")
-- сохранить: Polizei
local saveRecv = H.netrecv["GRM_AlarmNotify_Save"]
ok(saveRecv ~= nil, "обработчик Save зарегистрирован")
local admin = mkPly(true, "Владелец")
_G.__nextTbl = { "Polizei" }
saveRecv(0, admin)
ok(AN.IsNotified("Polizei") == true and AN.IsNotified("Mafia") == false, "после Save: Polizei оповещается, Mafia нет")
ok(AN.FactionList()[1] == "Mafia" and AN.FactionList()[2] == "Polizei", "FactionList: список существующих (отсортирован)")
-- не-суперадмин не может сохранить
_G.__nextTbl = { "Mafia" }
local player1 = mkPly(false, "Игрок")
saveRecv(0, player1)
ok(AN.IsNotified("Mafia") == false, "не-суперадмин не может изменить настройку")

-- ══════════════ 2. Оповещение членов фракции ══════════════
local cop = mkPly(false, "Полицейский", "76561198000000003", "STEAM_0:1:2") -- Polizei
local maf = mkPly(false, "Мафиози", "76561198000000004", "STEAM_0:1:1")   -- Mafia
_G.__players = { cop, maf }
local notified = {}
GRM.Notify = function(ply, msg) notified[ply.nick] = msg end
AN.NotifyFactions("⚠ ВЗЛОМ КЕЙПАДА", Vector(10, 10, 10))
ok(notified["Полицейский"] ~= nil, "член Polizei получил оповещение")
ok(notified["Мафиози"] == nil, "член Mafia не получил (не в списке)")

-- ══════════════ 3. События устройств ══════════════
local kp = mkEnt("grm_keypad")
local sc = mkEnt("grm_scanner")
local ffd = mkEnt("prop_physics", { isFadingDoor = true })
local door = mkEnt("prop_door_rotating")

-- неверный PIN → GRM_KeypadDenied → A.Log breach + оповещение
H.logs = {}
GRM.Alarm.Log = function(netID, kind, text) H.logs[#H.logs + 1] = { netID = netID, kind = kind, text = text } end
hook.Run("GRM_KeypadDenied", player1, kp)
ok(#H.logs >= 1 and H.logs[#H.logs].kind == "breach" and H.logs[#H.logs].text:find("неверный PIN", 1, true) ~= nil, "кейпад: неверный PIN → журнал breach")
ok(notified["Полицейский"] ~= nil and notified["Полицейский"]:find("неверный PIN", 1, true) ~= nil, "кейпад: оповещение с текстом")

-- взлом взломщиком (GRM_OnDeviceHacked): кейпад/сканер/ffd
hook.Run("GRM_OnDeviceHacked", player1, kp)
ok(H.logs[#H.logs].text:find("ВЗЛОМ КЕЙПАДА", 1, true) ~= nil, "взлом кейпада → журнал")
hook.Run("GRM_OnDeviceHacked", player1, sc)
ok(H.logs[#H.logs].text:find("ВЗЛОМ СКАНЕРА", 1, true) ~= nil, "взлом сканера → журнал")
hook.Run("GRM_OnDeviceHacked", player1, ffd)
ok(H.logs[#H.logs].text:find("ВЗЛОМ ЭЛЕКТРОНИКИ ДВЕРИ", 1, true) ~= nil, "взлом FFD-двери → журнал")

-- взлом обычной двери (GRM_OnDoorLockpicked)
hook.Run("GRM_OnDoorLockpicked", player1, door)
ok(H.logs[#H.logs].text:find("ВЗЛОМ ЗАМКА ДВЕРИ", 1, true) ~= nil, "взлом замка двери → журнал")

-- отказ сканера (GRM_ScannerDenied)
hook.Run("GRM_ScannerDenied", player1, sc)
ok(H.logs[#H.logs].text:find("Сканер: отказ доступа", 1, true) ~= nil, "отказ сканера → журнал")

-- ══════════════ 4. Кейпад/сканер реально шлют хуки ══════════════
local kpSrc = assert(io.open("lua/entities/grm_keypad/init.lua", "rb")):read("*a")
ok(kpSrc:find('hook.Run("GRM_KeypadDenied", ply, self)', 1, true) ~= nil, "кейпад: вызывает GRM_KeypadDenied (находка 179h)")
local scSrc = assert(io.open("lua/entities/grm_scanner/init.lua", "rb")):read("*a")
ok(scSrc:find('hook.Run("GRM_ScannerDenied", ply, self)', 1, true) ~= nil, "сканер: вызывает GRM_ScannerDenied (находка 179h)")

-- ══════════════ 5. Клиент и команда ══════════════
local cl = assert(io.open("lua/autorun/client/cl_grm_alarm_notify.lua", "rb")):read("*a")
ok(cl:find("DCheckBoxLabel", 1, true) ~= nil and cl:find("facList", 1, true) ~= nil, "клиент: чекбоксы фракций")
local sh = assert(io.open("lua/autorun/sh_grm_alarm_integration.lua", "rb")):read("*a")
ok(sh:find('"/grm_alarm_notify"', 1, true) ~= nil and sh:find('PlayerSayTransform', 1, true) ~= nil, "команда /grm_alarm_notify (EasyChat)")
ok(sh:find('AddCSLuaFile("autorun/client/cl_grm_alarm_notify.lua")', 1, true) ~= nil, "клиентский файл регистрируется")
ok(sh:find('if SERVER then', 1, true) ~= nil and sh:find('util.AddNetworkString("GRM_AlarmNotify_Open")', 1, true) ~= nil and sh:find('end -- if SERVER (сеть настройки)', 1, true) ~= nil, "AddNetworkString только на сервере (фикс клиента, находка 179h-fix)")

print(string.format("sim_alarm_integration: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
