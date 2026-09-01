-- sim_alarm.lua — функциональная проверка GRM Alarm (находка 176):
--   • сирена зацикливается (EnableLooping(true)) — и у хаба, и у динамиков;
--   • нет двойного звука: EmitSound только если CreateSound вернул nil;
--   • StopSiren глушит и патч, и резервный EmitSound (StopSound);
--   • скан датчиков: ARMED + обычный игрок → StartSiren; суперадмин/свой
--     (CanControl) НЕ триггерит; PASSIVE — только лог, без сирены;
--   • звук по умолчанию — ambient/alarms/combine_bank_alarm_loop4.wav.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
include = function(p) dofile("lua/" .. p) end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return _G.__now or 1000 end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b) return { r = r or 0, g = g or 0, b = b or 0 } end
string.Trim = string.Trim or function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end

local VMT = {
  __index = function(t, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
  end,
  __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
  __mul = function(a, b) if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end,
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- ── мок окружения ──
local H = { hooks = {}, timers = {}, cmds = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
timer = { Create = function(n, _, _, fn) H.timers[n] = fn end, Simple = function(_, fn) if fn then fn() end end }
concommand = { Add = function(n, fn) H.cmds[n] = fn end }

-- звуковые патчи: логируем вызовы
local patchLog = {}
local function mkPatch(owner)
  local p = { owner = owner, stopped = false, loop = nil, played = false, level = nil, volume = nil }
  p.Stop = function() p.stopped = true end
  p.SetSoundLevel = function(_, l) p.level = l end
  p.EnableLooping = function(_, b) p.loop = b end
  p.PlayEx = function(_, v, pitch) p.played = true p.volume = v end
  patchLog[#patchLog + 1] = p
  return p
end
_G.__createSoundResult = "patch" -- "patch" | "nil"
CreateSound = function(owner, path)
  if _G.__createSoundResult == "nil" then return nil end
  return mkPatch(owner)
end

local files = {}
file = {
  IsDir = function() return true end, CreateDir = function() end,
  Exists = function(p) return files[p] ~= nil end,
  Read = function(p) return files[p] end,
  Write = function(p, s) files[p] = s end,
  Find = function() return {} end,
}
os = { time = function() return 1700000000 end, date = function(f) return f and "2026-08-05" or "2026-08-05" end }
game = { GetMap = function() return "rp_test" end }
util = {
  AddNetworkString = function() end,
  TableToJSON = function() return "{}" end,
  JSONToTable = function() return nil end,
  TraceLine = function() return { Hit = false } end,
}
net = {
  Start = function() end, WriteEntity = function() end, WriteString = function() end, WriteBool = function() end,
  WriteUInt = function() end, WriteTable = function() end, Send = function() end, Broadcast = function() end,
  Receive = function() end, ReadTable = function() return {} end, ReadString = function() return "" end,
  ReadBool = function() return false end, ReadUInt = function() return 0 end,
}
ents = {
  Create = function() return nil end,
  FindInSphere = function() return {} end,
}
player = { GetAll = function() return _G.__players or {} end }
_G.__entities = {}
Entity = function(idx) return _G.__entities[idx] end
GRM = {
  Notify = function() end,
  Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end },
}

-- ── мок энтити ──
local EMT = {}
EMT.__index = function(t, k)
  if k == "GetClass" then return function(s) return s.__cls end
  elseif k == "EntIndex" then return function(s) return s.__idx end
  elseif k == "IsValid" then return function() return true end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  elseif k == "GetAngles" then return function() return Angle(0, 0, 0) end
  elseif k == "GetPhysicsObject" then return function() return { EnableMotion = function() end, Wake = function() end } end
  elseif k == "GetModel" then return function(s) return s.model or "models/x.mdl" end
  elseif k == "GetNetworkID" then return function(s) return s.network or "main" end
  elseif k == "SetNetworkID" then return function(s, v) s.network = v end
  elseif k == "GetDeviceID" then return function(s) return s.deviceID or "dev" end
  elseif k == "SetDeviceID" then return function(s, v) s.deviceID = v end
  elseif k == "GetLabel" then return function(s) return s.label or "" end
  elseif k == "SetLabel" then return function(s, v) s.label = v end
  elseif k == "GetMode" then return function(s) return s.mode or 1 end
  elseif k == "SetMode" then return function(s, v) s.mode = v end
  elseif k == "GetAlarmActive" then return function(s) return s.alarmActive == true end
  elseif k == "SetAlarmActive" then return function(s, v) s.alarmActive = v end
  elseif k == "GetRadius" then return function(s) return s.radius or 220 end
  elseif k == "SetRadius" then return function(s, v) s.radius = v end
  elseif k == "GetActive" then return function(s) return s.active ~= false end
  elseif k == "SetActive" then return function(s, v) s.active = v end
  elseif k == "GetLastTrigger" then return function(s) return s.lastTrigger or 0 end
  elseif k == "SetLastTrigger" then return function(s, v) s.lastTrigger = v end
  elseif k == "GetPermanent" then return function(s) return s.permanent == true end
  elseif k == "SetPermanent" then return function(s, v) s.permanent = v end
  elseif k == "GetOwnerSteam" then return function(s) return s.ownerSteam or "" end
  elseif k == "SetOwnerSteam" then return function(s, v) s.ownerSteam = v end
  elseif k == "StopSound" then return function(s, path) s.stoppedSounds = s.stoppedSounds or {} s.stoppedSounds[#s.stoppedSounds + 1] = path end
  elseif k == "EmitSound" then return function(s, path) s.emitted = s.emitted or {} s.emitted[#s.emitted + 1] = path end
  end
  return nil
end
local nextIdx = 1
local function mkEnt(cls, network)
  local e = setmetatable({ __cls = cls, __valid = true, __idx = nextIdx, network = network or "main", mode = 1, active = true, pos = Vector(0, 0, 0) }, EMT)
  nextIdx = nextIdx + 1
  _G.__entities[e.__idx] = e
  return e
end

-- ── мок игрока ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "IsSuperAdmin" then return function(s) return s.super == true end
  elseif k == "Alive" then return function() return true end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  elseif k == "EyePos" then return function(s) return (s.pos or Vector(0, 0, 0)) + Vector(0, 0, 60) end
  elseif k == "Nick" then return function(s) return s.nick or "Player" end
  elseif k == "SteamID64" then return function(s) return s.sid64 end
  elseif k == "SteamID" then return function() return "STEAM_0:1:1" end
  end
  return nil
end
local function mkPly(super, nick)
  return setmetatable({ __valid = true, super = super == true, nick = nick or "Player", sid64 = super and "76561198000000001" or "76561198000000002", pos = Vector(50, 0, 0) }, PMT)
end

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
local A = GRM.Alarm
ok(A ~= nil and A.StartSiren ~= nil and A.StopSiren ~= nil, "модуль Alarm загружен")
ok(A.Config.SirenSound == "ambient/alarms/combine_bank_alarm_loop4.wav", "звук по умолчанию: combine_bank_alarm_loop4.wav")

-- ══════════════ 1. StartSiren: зацикливание, без дубля EmitSound ══════════════
_G.__now = 1000
local hub = mkEnt("grm_alarm_hub")
hub.mode = A.MODE_ARMED
A.StartSiren(hub, "тест", nil)
ok(hub.alarmActive == true, "StartSiren поднял флаг тревоги на хабе")
ok(#patchLog == 1, "создан ровно один звуковой патч (без дубля EmitSound)")
ok(patchLog[1].loop == true, "патч зациклен (EnableLooping(true))")
ok(patchLog[1].played == true and patchLog[1].volume == 1, "патч проигран (PlayEx volume=1)")
ok(hub.emitted == nil, "EmitSound НЕ вызывался при успешном CreateSound")
ok(A.Sirens[hub:EntIndex()] ~= nil and A.Sirens[hub:EntIndex()].stopAt > 1000, "таймер авто-останова установлен (45с)")

-- ══════════════ 2. Fallback: CreateSound=nil → EmitSound ══════════════
patchLog = {}
_G.__createSoundResult = "nil"
local hub2 = mkEnt("grm_alarm_hub")
hub2.mode = A.MODE_ARMED
A.StartSiren(hub2, "тест-fallback", nil)
ok(#patchLog == 0, "патч не создан (мок nil)")
ok(hub2.emitted ~= nil and hub2.emitted[1] == "ambient/alarms/combine_bank_alarm_loop4.wav", "fallback EmitSound сыграл разово")
_G.__createSoundResult = "patch"

-- ══════════════ 3. StopSiren: глушит патч + StopSound ══════════════
local hub3 = mkEnt("grm_alarm_hub")
hub3.mode = A.MODE_ARMED
A.StartSiren(hub3, "тест", nil)
local patch = patchLog[#patchLog]
A.StopSiren(hub3)
ok(patch.stopped == true, "StopSiren остановил патч")
ok(hub3.stoppedSounds ~= nil and hub3.stoppedSounds[1] == "ambient/alarms/combine_bank_alarm_loop4.wav", "StopSiren глушит резервный EmitSound (StopSound)")
ok(hub3.alarmActive == false, "StopSiren сбросил флаг тревоги")
ok(A.Sirens[hub3:EntIndex()] == nil, "запись сирены удалена")

-- ══════════════ 4. Динамики: syncSpeakers зацикливает патч ══════════════
patchLog = {}
local spk = mkEnt("grm_alarm_speaker")
A.RegisterDevice(spk)
A.RegisterDevice(hub)
spk.active = true
hub.mode = A.MODE_ARMED
A.StartSiren(hub, "для динамика", nil)
ok(patchLog[#patchLog].loop == true, "динамик: патч зациклен (EnableLooping(true))")
local spkPatch = A.SpeakerPatches[spk:EntIndex()]
ok(spkPatch ~= nil and spkPatch.played == true, "динамик играет при активной тревоге")
A.StopSiren(hub)
ok(A.SpeakerPatches[spk:EntIndex()] == nil, "после сброса тревоги динамик замолчал (патч остановлен)")

-- ══════════════ 5. Скан датчиков ══════════════
local thinkFn = H.hooks["Think"]["GRM_Alarm_Scan"]
ok(thinkFn ~= nil, "скан-тикер зарегистрирован")

-- 5a. ARMED + обычный игрок → тревога
local hub5 = mkEnt("grm_alarm_hub", "net5")
A.RegisterDevice(hub5)
hub5.mode = A.MODE_ARMED
local sensor = mkEnt("grm_alarm_sensor", "net5")
A.RegisterDevice(sensor)
sensor.active = true
sensor.radius = 220
local ply = mkPly(false, "Тестер")
_G.__players = { ply }
_G.__now = 2000
thinkFn()
ok(A.Sirens[hub5:EntIndex()] ~= nil, "ARMED + обычный игрок в радиусе → сирена запущена")
ok(sensor.lastTrigger == 2000, "датчик зафиксировал время срабатывания")
A.StopSiren(hub5)

-- 5b. Суперадмин ТРИГГЕРИТ (жалоба владельца 22.08: «сигнализация не
-- работает» — он проверял её сам, будучи суперадмином, и был «своим»).
local hub6 = mkEnt("grm_alarm_hub", "net6")
A.RegisterDevice(hub6)
hub6.mode = A.MODE_ARMED
local sensor6 = mkEnt("grm_alarm_sensor", "net6")
A.RegisterDevice(sensor6)
sensor6.active = true
local admin = mkPly(true, "Админ")
_G.__players = { admin }
_G.__now = 3000
thinkFn()
ok(A.Sirens[hub6:EntIndex()] ~= nil, "по умолчанию датчик замечает и суперадмина — иначе не проверить")
ok(sensor6.lastTrigger ~= nil, "датчик отметил срабатывание")

-- и наоборот: включили конвар — администрация ходит незаметно
GetConVar("grm_alarm_ignore_admins"):SetValue("1")
local hub6b = mkEnt("grm_alarm_hub", "net6b")
A.RegisterDevice(hub6b)
hub6b.mode = A.MODE_ARMED
local sensor6b = mkEnt("grm_alarm_sensor", "net6b")
A.RegisterDevice(sensor6b)
sensor6b.active = true
_G.__players = { admin }
_G.__now = 3100
thinkFn()
ok(A.Sirens[hub6b:EntIndex()] == nil, "с grm_alarm_ignore_admins 1 суперадмин снова «свой»")
GetConVar("grm_alarm_ignore_admins"):SetValue("0")

-- диагностика объясняет, почему тревоги может не быть
ok(type(A.Diagnose) == "function", "есть команда диагностики grm_alarm_status")
local diag = table.concat(A.Diagnose(admin), " | ")
ok(diag:find("сеть", 1, true) ~= nil, "диагностика перечисляет сети", diag)

-- 5c. PASSIVE → только лог, без сирены
local hub7 = mkEnt("grm_alarm_hub", "net7")
A.RegisterDevice(hub7)
hub7.mode = A.MODE_PASSIVE
local sensor7 = mkEnt("grm_alarm_sensor", "net7")
A.RegisterDevice(sensor7)
sensor7.active = true
_G.__players = { mkPly(false, "Тестер2") }
_G.__now = 4000
thinkFn()
ok(A.Sirens[hub7:EntIndex()] == nil, "PASSIVE: сирена не запускается")
ok(sensor7.lastTrigger == 4000, "PASSIVE: движение зафиксировано (лог)")
ok(#(A.Logs["net7"] or {}) >= 1 and A.Logs["net7"][1].text:find("пассив", 1, true) ~= nil, "PASSIVE: в лог пишется [пассив]")

-- 5d. OFF → датчики молчат
local hub8 = mkEnt("grm_alarm_hub", "net8")
A.RegisterDevice(hub8)
hub8.mode = A.MODE_OFF
local sensor8 = mkEnt("grm_alarm_sensor", "net8")
A.RegisterDevice(sensor8)
sensor8.active = true
_G.__players = { mkPly(false, "Тестер3") }
_G.__now = 5000
thinkFn()
ok(A.Sirens[hub8:EntIndex()] == nil and sensor8.lastTrigger == nil, "OFF: датчики молчат")

-- 5e. Датчик выключен (Active=false) → не сканирует
local hub9 = mkEnt("grm_alarm_hub", "net9")
A.RegisterDevice(hub9)
hub9.mode = A.MODE_ARMED
local sensor9 = mkEnt("grm_alarm_sensor", "net9")
A.RegisterDevice(sensor9)
sensor9.active = false
_G.__players = { mkPly(false, "Тестер4") }
_G.__now = 6000
thinkFn()
ok(A.Sirens[hub9:EntIndex()] == nil and sensor9.lastTrigger == nil, "выключенный датчик не сканирует")

print(string.format("sim_alarm: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
