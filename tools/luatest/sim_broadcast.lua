-- Симуляция сервера GMod для sh_grm_broadcast.lua
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
string.lower = string.lower
table.sort = table.sort
local H = { hooks = {}, netrecv = {}, savedTypes = {}, concommands = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end

_G._SIM = H
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function IsValid(o) return o ~= nil and o ~= false end

util = {
  AddNetworkString = function(s) H.savedTypes[#H.savedTypes+1] = s end,
  JSONToTable = function(t) return nil end,
  TableToJSON = function(t) return "{}" end,
}
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end, IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end }
timer = { Create = function() end, Simple = function() end }
ents = { FindByClass = function(c) return H.entsByClass and H.entsByClass[c] or {} end,
         Create = function(c) return nil end }
player = { GetAll = function() return H.players or {} end,
           GetBySteamID = function() return nil end }
Entity = function(i) return nil end
game = { GetMap = function() return "gm_test" end }
os.mtime = os.time

local netlog = {}
net = { Start = function(m) netlog.cur = { msg = m, fields = {} } end,
        WriteString = function(s) table.insert(netlog.cur.fields, {"s", tostring(s)}) end,
        WriteUInt = function(v,b) table.insert(netlog.cur.fields, {"u", v}) end,
        WriteInt = function(v,b) table.insert(netlog.cur.fields, {"i", v}) end,
        WriteBool = function(v) table.insert(netlog.cur.fields, {"b", v}) end,
        WriteTable = function(t) table.insert(netlog.cur.fields, {"t", "table"}) end,
        Send = function(tg) netlog.sent = netlog.sent or {} table.insert(netlog.sent, { msg = netlog.cur.msg, to = tg }) netlog.cur = nil end,
        Broadcast = function() netlog.sent = netlog.sent or {} table.insert(netlog.sent, { msg = netlog.cur and netlog.cur.msg, to = "BROADCAST" }) netlog.cur = nil end,
        SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }

local ply = setmetatable({
  sid = "STEAM_0:1:234", s64 = "76561198000000001",
  SteamID = function(self) return self.sid end,
  SteamID64 = function(self) return self.s64 end,
  IsSuperAdmin = function() return true end,
  IsAdmin = function() return true end,
  Nick = function() return "Владелец" end,
  GetNWString = function() return "Иван Тестов" end,
  PrintMessage = function(self, chan, txt) P("PLY-MSG: " .. tostring(txt)) end,
}, { __index = function(_, k) P("СТУБ-ВЫЗОВ ply:" .. tostring(k)) return function() return nil end end })
H.players = { ply }

-- вектор-заглушка с DistToSqr (SendAlert мерит радиус громкоговорителей)
local VMT = {}
VMT.__index = function(self, k)
  if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
  return nil
end
local function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end

-- громкоговоритель-заглушка
local spk = setmetatable({}, { __index = function(_, k)
  if k == "SetNWBool" then return function() end end
  if k == "EmitSound" then return function() P("SPK EMIT") end end
  if k == "EntIndex" then return function() return 5 end end
  if k == "GetPos" then return function() return V(0, 0, 0) end end
  P("СТУБ-ВЫЗОВ spk:" .. tostring(k)) return function() return nil end
end })
H.entsByClass = { grm_loudspeaker = { spk }, grm_radio = {}, grm_broadcast_mic = {} }
ply.GetPos = function() return V(10, 0, 0) end

GAMEMODE = nil
AddCSLuaFile = function() end

-- подгружаем сам модуль (shared вызовется целиком; SERVER-часть нам и нужна)
if SERVER == nil then SERVER = true end
CLIENT = false
dofile("lua/autorun/sh_grm_broadcast.lua")

P("=== hook PlayerSay: /alertall Привет город ===")
local r = H.hooks["PlayerSay"]["GRM_BC_AdminCmds"] (ply, "/alertall Привет город")
P("return:", tostring(r))

P("=== hook PlayerSay: /alert Привет район ===")
local r2 = H.hooks["PlayerSay"]["GRM_BC_AdminCmds"] (ply, "/alert Привет район")
P("return:", tostring(r2))

P("=== net sent:")
for _, s in ipairs(netlog.sent or {}) do P("net -> " .. tostring(s.msg) .. " to " .. tostring(type(s.to))) end

-- ══ Код 88.4 — авто-свипер персистента broadcast-устройств ══════════════
local BC = GRM.Broadcast
local swpOk, swpFail = 0, 0
local function sok(cond, name)
  if cond then swpOk = swpOk + 1 P("  ok  " .. name)
  else swpFail = swpFail + 1 P("  FAIL " .. name) end
end
sok(BC ~= nil and BC._devSweep ~= nil, "свипер экспортирован (BC._devSweep)")
if BC and BC._devSweep then
  local pos = { x = 50000, y = 7, z = 3 }
  local radio = {
    GetClass = function() return "grm_radio" end,
    GetPos = function() return pos end,
    GetAngles = function() return { p = 0, y = 0, r = 0 } end,
  }
  H.entsByClass = { grm_radio = { radio } }
  BC._devSweep()
  local key1 = "grm_radio|50000_7_3"
  sok(BC.Persist[key1] ~= nil, "свипер: радио мимо команд попало в персист")
  sok(radio._grmBCKey == key1, "энтити помечена ключом свипера")
  -- переезд: миграция ключа
  pos.x = 51000
  BC._devSweep()
  sok(BC.Persist[key1] == nil, "после переезда старая запись удалена")
  sok(BC.Persist["grm_radio|51000_7_3"] ~= nil, "после переезда новая запись создана")
  -- удаление живьём: выпадает из реестра
  H.entsByClass = {}
  BC._devSweep()
  sok(BC.Persist["grm_radio|51000_7_3"] == nil, "удалённое радио выпало из персиста")
  -- чужие классы не трогаем
  local alien = { GetClass = function() return "prop_physics" end,
    GetPos = function() return { x = 1, y = 2, z = 3 } end,
    GetAngles = function() return { p = 0, y = 0, r = 0 } end }
  H.entsByClass = { prop_physics = { alien } }
  BC._devSweep()
  local clean = true
  for k, rec in pairs(BC.Persist or {}) do if rec.class == "prop_physics" then clean = false end end
  sok(clean, "чужие классы игнорируются")
  H.entsByClass = nil
end
P(string.format("свипер broadcast: %d ok, %d fail", swpOk, swpFail))
if swpFail > 0 then os.exit(1) end
P("SIM_BROADCAST OK")
