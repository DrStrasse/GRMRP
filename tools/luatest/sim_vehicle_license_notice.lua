--[[ Живой прогон: при посадке в транспорт система больше НЕ проверяет В/У.
     Заказ владельца 21.08: «Водительские права не надо чтобы система проверяла
     у водителя когда он сидит в машине или на кресле… а то пишет
     ВАИ проверено (Категория С) — не надо.»
     Проверяем: по умолчанию тишина; ручное включение конвара возвращает старое
     поведение; пассажиров и кресла это не касается.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_vehicle_license_notice.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

function CurTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isbool(v) return type(v) == "boolean" end
function IsEntity(v) return type(v) == "table" end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function ErrorNoHalt() end
function Msg() end
function MsgN() end
function print_(...) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function math.Round(v) return math.floor((tonumber(v) or 0) + 0.5) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, s) local out = {} for m in tostring(s):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = m end return out end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function table.insert_(t, v) t[#t + 1] = v end
HUD_PRINTCONSOLE, HUD_PRINTTALK = 2, 3
FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED = 1, 2, 4

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do local a = fn(...) if a ~= nil then return a end end end,
    Call = function(n, _, ...) return hook.Run(n, ...) end,
}
timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end, Adjust = function() end }
concommand = { Add = function() end }
net = { Receive = function() end, Start = function() end, WriteString = function() end,
        WriteTable = function() end, WriteBool = function() end, WriteUInt = function() end,
        WriteEntity = function() end, Send = function() end, Broadcast = function() end,
        ReadString = function() return "" end, ReadTable = function() return {} end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end, CRC = function() return "0" end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end, Find = function() return {}, {} end,
         Delete = function() end }

local CONVARS = {}
CreateConVar = function(name, def)
    local cv = { _v = tostring(def) }
    function cv:GetBool() return self._v ~= "0" and self._v ~= "" and self._v ~= "false" end
    function cv:GetInt() return math.floor(tonumber(self._v) or 0) end
    function cv:GetFloat() return tonumber(self._v) or 0 end
    function cv:GetString() return self._v end
    function cv:SetValue(v) self._v = tostring(v) end
    CONVARS[name] = cv
    return cv
end
GetConVar = function(name) return CONVARS[name] end

local ALL = {}
player = { GetAll = function() return ALL end, GetBySteamID64 = function() return nil end }
ents = { FindByClass = function() return {} end, Create = function() return { _valid = false } end,
         GetAll = function() return {} end }

GRM = GRM or {}
GRM.Identity = { CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end }
GRM.Perf = { Players = function() return ALL end, Throttle = function() return true end,
             Coalesce = function(_, fn) if fn then fn() end end, Spread = function() end,
             Queue = function(_, fn) if fn then fn() end end }
GRM.Save = { Register = function() end, Mark = function() end, Flush = function() end }
GRM.Audit = { Write = function() end }
GRM.Boot = { OnMapStart = function(_, _, fn) if fn then fn() end end }
GRM.Net = { Guard = function(_, fn) return fn end, Stream = function() end, Receive = function() end }

local NOTIFY = {}
GRM.Notify = function(_, text) NOTIFY[#NOTIFY + 1] = tostring(text) end

local function mkPlayer()
    local p = { _valid = true, nw = {}, chat = {} }
    function p:IsPlayer() return true end
    function p:IsValid() return true end
    function p:Nick() return "Курт" end
    function p:SteamID64() return "76561190000000007" end
    function p:SteamID() return "STEAM_0:1:7" end
    function p:IsSuperAdmin() return true end
    function p:IsAdmin() return true end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:GetNWInt(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    ALL[#ALL + 1] = p
    return p
end

local function mkVehicle(model, class)
    return { _valid = true,
        GetModel = function() return model end,
        GetClass = function() return class or "prop_vehicle_jeep" end,
        IsVehicle = function() return true end }
end

assert(loadfile("lua/autorun/sh_grm_documents.lua"))()
local DOC = GRM.Documents

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ply = mkPlayer()
local KEY = "76561190000000007:char1"
DOC.Registry = DOC.Registry or {}
DOC.Registry.licenses = DOC.Registry.licenses or {}
DOC.Registry.milLicenses = DOC.Registry.milLicenses or {}
DOC.Registry.milLicenses[KEY] = {
    fullName = "Курт Вебер", number = "ВАИ-1001", status = "Действительно",
    categories = { ["C-В"] = true }, expiry = os.time() + 3600, points = 0, maxPoints = 12,
}

local enter = hooks["PlayerEnteredVehicle"] and hooks["PlayerEnteredVehicle"]["GRM_Doc_VehicleDriverCheck"]
local function sit(veh, role)
    NOTIFY = {}
    ply.chat = {}
    if enter then enter(ply, veh, role or 0) end
    return table.concat(NOTIFY, " | "), table.concat(ply.chat, " | ")
end

print("\n=== 1. ХУК ЖИВ, НО МОЛЧИТ ПО УМОЛЧАНИЮ ===")
ok(isfunction(enter), "хук PlayerEnteredVehicle зарегистрирован")
local cv = GetConVar("grm_doc_vehicle_check")
ok(cv ~= nil, "конвар grm_doc_vehicle_check заведён")
ok(cv and not cv:GetBool(), "по умолчанию автопроверка выключена")

print("\n=== 2. ГРУЗОВИК: НИКАКОГО «ВАИ ПРОВЕРЕНО» ===")
local truck = mkVehicle("models/kamaz/kamaz.mdl", "simfphys_kamaz")
local n, c = sit(truck)
ok(n == "", "уведомлений нет", n)
ok(c == "", "в чат ничего не пишется", c)
ok(not n:find("Категория", 1, true), "строка «Категория С» не появляется", n)

print("\n=== 3. БЕЗ ПРАВ ТОЖЕ ТИШИНА ===")
DOC.Registry.milLicenses[KEY] = nil
local bus = mkVehicle("models/bus/bus.mdl", "simfphys_bus")
n, c = sit(bus)
ok(n == "" and c == "", "нет ругани «Нет В/У категории»", n .. " / " .. c)

print("\n=== 4. КРЕСЛО / ПАССАЖИР ===")
n, c = sit(mkVehicle("models/nova/chair_office01.mdl", "prop_vehicle_prisoner_pod"))
ok(n == "" and c == "", "посадка на кресло молчит", n .. " / " .. c)
n, c = sit(truck, 1)
ok(n == "" and c == "", "пассажир не проверяется", n .. " / " .. c)

print("\n=== 5. РУЧНОЕ ВКЛЮЧЕНИЕ ВОЗВРАЩАЕТ ПРОВЕРКУ ===")
cv:SetValue("1")
DOC.Registry.milLicenses[KEY] = {
    fullName = "Курт Вебер", number = "ВАИ-1001", status = "Действительно",
    categories = { ["C-В"] = true }, expiry = os.time() + 3600, points = 0, maxPoints = 12,
}
n = sit(truck)
ok(n:find("Категория C-В", 1, true) ~= nil, "с конваром 1 проверка снова работает", n)
cv:SetValue("0")
n = sit(truck)
ok(n == "", "выключили — снова тишина", n)

print(("\nVEHICLE LICENSE NOTICE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
