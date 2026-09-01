-- Симуляция сервера GMod для охранного стека GRM (Код 89):
--   sh_grm_alarm_config.lua + server/sv_grm_alarm.lua (динамик сирены,
--   сеть из терминала, автосейв персистента, save/load roundtrip)
--   server/sv_grm_cctv.lua (автосейв персистента на сеттерах)
--   sh_grm_perm_entities.lua (универсальный перм: новые классы Код 89)
-- Стенд доказывает поведение БЕЗ GMod.
----------------------------------------------------------------------

string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
math.Clamp = math.Clamp or function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

local H = { hooks = {}, timers = {}, netlog = {}, chatlog = {}, sounds = {}, seq = {}, players = {} }
_G._SIM = H
local realPrint = print
local function P(...) realPrint(...) end

function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end
HUD_PRINTTALK = 3
MASK_SOLID_BRUSHONLY = 1
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

-- вектора --------------------------------------------------------------
local VMT = {}
VMT.__index = function(self, k)
  if k == "DistToSqr" then return function(s, o) local dx,dy,dz = s.x-o.x, s.y-o.y, s.z-o.z return dx*dx+dy*dy+dz*dz end end
  return nil
end
VMT.__add = function(a, b) return V(a.x + (b.x or 0), a.y + (b.y or 0), a.z + (b.z or 0)) end
VMT.__sub = function(a, b) return V(a.x - (b.x or 0), a.y - (b.y or 0), a.z - (b.z or 0)) end
VMT.__mul = function(a, b)
  if type(a) == "number" then return V(a * b.x, a * b.y, a * b.z) end
  return V(a.x * b, a.y * b, a.z * b)
end
function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
Vector = V
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- реестр энтити ----------------------------------------------------------
-- Универсальный DT: GetX/SetX (кроме спецметодов) ходят в __dt[X].
local REG = { byClass = {}, byIdx = {}, nextIdx = 1 }
local function mkEnt(class, x, y, z)
  local e = { __class = class, __pos = V(x, y, z), __ang = Angle(0,0,0), __idx = REG.nextIdx, __dt = {}, __model = "" }
  REG.nextIdx = REG.nextIdx + 1
  e = setmetatable(e, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, p) self.__pos = p end end
    if k == "GetAngles" then return function() return self.__ang end end
    if k == "SetAngles" then return function(_, a) self.__ang = a end end
    if k == "GetClass" then return function() return self.__class end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "GetModel" then return function() return self.__model end end
    if k == "SetModel" then return function(_, m) self.__model = m end end
    if k == "Spawn" then return function() end end
    if k == "Activate" then return function() end end
    if k == "GetPhysicsObject" then return function() return { EnableMotion = function() end } end end
    if k == "Remove" then return function() self.__removed = true
      local list = REG.byClass[self.__class] or {}
      for i, xx in ipairs(list) do if xx == self then table.remove(list, i) break end end
      REG.byIdx[self.__idx] = nil end end
    local gk = k:match("^Get(%w+)$")
    if gk then return function() return self.__dt[gk] end end
    local sk = k:match("^Set(%w+)$")
    if sk then return function(_, val) self.__dt[sk] = val end end
    return nil
  end })
  REG.byClass[class] = REG.byClass[class] or {}
  table.insert(REG.byClass[class], e)
  REG.byIdx[e.__idx] = e
  return e
end
local function resetREG()
  REG.byClass, REG.byIdx, REG.nextIdx = {}, {}, 1
end

ents = {
  FindByClass = function(c) return REG.byClass[c] or {} end,
  Create = function(c) return mkEnt(c, 0, 0, 0) end,
  FindInSphere = function(center, r)
    local out, r2 = {}, (r or 0) * (r or 0)
    for _, e in pairs(REG.byIdx) do
      if IsValid(e) and center:DistToSqr(e:GetPos()) <= r2 then out[#out + 1] = e end
    end
    return out
  end,
}
Entity = function(i) return REG.byIdx[i] end

-- игроки -----------------------------------------------------------------
local function mkPly(id, x, isSAdmin)
  local p = { __pos = V(x, 0, 0), __idx = id, __sa = isSAdmin and true or false, __alive = true }
  p = setmetatable(p, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, v) self.__pos = v end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "IsSuperAdmin" then return function() return self.__sa end end
    if k == "IsPlayer" then return function() return true end end
    if k == "Alive" then return function() return self.__alive end end
    if k == "SteamID" then return function() return "STEAM_0:1:" .. tostring(self.__idx) end end
    if k == "SteamID64" then return function() return "76561198000000" .. tostring(100 + self.__idx) end end
    if k == "Nick" then return function() return "Игрок" .. tostring(self.__idx) end end
    if k == "PrintMessage" then return function(_, _, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) end end
    if k == "EyePos" then return function() return self.__pos + V(0, 0, 64) end end
    if k == "GetShootPos" then return function() return self.__pos end end
    if k == "GetAimVector" then return function() return V(1, 0, 0) end end
    return nil
  end })
  return p
end

-- файлы + JSON-токены (полный roundtrip таблиц без текстового JSON) ------
local FILES = {}
local TOKENS, tokN = {}, 0
util = {
  AddNetworkString = function() end,
  TableToJSON = function(t) tokN = tokN + 1 local tok = "TOK#" .. tokN TOKENS[tok] = t return tok end,
  JSONToTable = function(txt) if isstring(txt) then return TOKENS[txt] end return nil end,
  TraceLine = function() return H.trace or { Hit = false } end,
  IsValidModel = function() return true end,
}
file = {
  Read = function(p) return FILES[p] end,
  Write = function(p, d) FILES[p] = d end,
  Exists = function(p) return FILES[p] ~= nil end,
  IsDir = function() return true end,
  CreateDir = function() end,
}

hook = {
  Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
  Run = function() end,
}
timer = {
  Create = function(name, _, _, fn) H.timers[name] = fn end,
  Simple = function(_, fn) if fn then fn() end end,
}
player = { GetAll = function() return H.players or {} end }
game = { GetMap = function() return "gm_simtown" end }
local CC = {}
concommand = { Add = function(name, fn) CC[name] = fn end }

net = {
  Start = function(m) H.netlog.cur = { msg = m, f = {} } end,
  WriteUInt = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteFloat = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteString = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteBool = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v and "T" or "F" end,
  WriteEntity = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteTable = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  Broadcast = function() if H.netlog.cur then H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end end,
  Send = function() if H.netlog.cur then H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end end,
  Receive = function(m, fn) H.netrecv[m] = fn end,
}
H.netrecv = H.netrecv or {}
net.ReadUInt = function() return tonumber(table.remove(H.seq, 1)) or 0 end
net.ReadString = function() return tostring(table.remove(H.seq, 1) or "") end
net.ReadEntity = function() return table.remove(H.seq, 1) end
net.ReadTable = function() local v = table.remove(H.seq, 1) return istable(v) and v or {} end

-- CreateSound: записываем патчи, чтобы проверять Play/Stop -------------
CreateSound = function(ent, path)
  local p = { ent = ent, path = path, playing = false, stopped = false, level = 0, loop = nil }
  function p:SetSoundLevel(l) self.level = l end
  function p:Play() self.playing = true end
  function p:PlayEx() self.playing = true end
  function p:EnableLooping(b) self.loop = b end
  function p:Stop() self.playing = false self.stopped = true end
  H.sounds[#H.sounds + 1] = p
  return p
end

TT = 0
CurTime = function() return TT end
AddCSLuaFile = function() end
include = function(path) dofile("lua/" .. path) end

-- ── загрузка модулей ──────────────────────────────────────────────────
SERVER = true CLIENT = false
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
dofile("lua/autorun/server/sv_grm_alarm.lua")   -- сам инклудит sh_grm_alarm_config
dofile("lua/autorun/server/sv_grm_cctv.lua")    -- сам инклудит sh_grm_cctv_config
dofile("lua/autorun/sh_grm_perm_entities.lua")
local A = GRM.Alarm
local CCTV = GRM.CCTV

-- фреймворк ---------------------------------------------------------------
local checks, failed = 0, 0
local function ok(cond, name)
  checks = checks + 1
  if cond then P("  ok " .. tostring(checks) .. ". " .. name)
  else failed = failed + 1 P("  FAIL " .. tostring(checks) .. ". " .. name) end
end

local function findNet(msg)
  for i = #H.netlog, 1, -1 do
    if H.netlog[i].msg == msg then return H.netlog[i] end
  end
  return nil
end
local function patchFor(ent)
  for i = #H.sounds, 1, -1 do
    if H.sounds[i].ent == ent then return H.sounds[i] end
  end
  return nil
end
local function fileTable(path)
  local tok = FILES[path]
  return isstring(tok) and TOKENS[tok] or nil
end
local function countOfClass(list, class)
  local n = 0
  for _, rec in ipairs(list or {}) do if rec.class == class then n = n + 1 end end
  return n
end
local function fireThink() H.hooks.Think["GRM_Alarm_Scan"]() end
local function fireAlarmAct(ply, payload) H.seq = { payload } H.netrecv["GRM_Alarm_Act"](0, ply) end

-- ── мир: сеть main = хаб + терминал + динамик + сенсор ─────────────────
local admin = mkPly(1, 0, true)
local intruder = mkPly(2, 0, false)
intruder.__pos = V(30, 0, 0)

local hub = mkEnt("grm_alarm_hub", 0, 0, 0)
hub:SetDeviceID("hub1") hub:SetLabel("Блок") hub:SetNetworkID("main")
hub:SetMode(A.MODE_OFF) hub:SetAlarmActive(false) hub:SetPermanent(true)
A.RegisterDevice(hub)

local trm = mkEnt("grm_alarm_terminal", 0, 0, 0)
trm:SetDeviceID("trm1") trm:SetLabel("Терминал") trm:SetNetworkID("main")
trm:SetPermanent(true)
A.RegisterDevice(trm)

local spk = mkEnt("grm_alarm_speaker", 0, 0, 0)
spk:SetDeviceID("spk1") spk:SetLabel("Динамик") spk:SetNetworkID("main")
spk:SetActive(true) spk:SetPermanent(true)
A.RegisterDevice(spk)

local sen = mkEnt("grm_alarm_sensor", 30, 0, 0)
sen:SetDeviceID("sen1") sen:SetLabel("Датчик") sen:SetNetworkID("main")
sen:SetActive(true) sen:SetRadius(220) sen:SetLastTrigger(0) sen:SetPermanent(true)
A.RegisterDevice(sen)

P("== 1. Реестр устройств и payload терминала (динамик виден) ==")
ok(A.GetHub("main") == hub, "GetHub находит хаб сети main")
ok(A.GetMode("main") == A.MODE_OFF, "изначально режим сети = ВЫКЛ")
local netlogBefore = #H.netlog
A.OpenTerminal(admin, trm)
local m = findNet("GRM_Alarm_OpenTrm")
ok(m ~= nil and #H.netlog > netlogBefore, "терминал отправил NET_OPEN_TRM")
ok(m ~= nil and m.f[2] == "main", "payload: сеть = main")
ok(m ~= nil and m.f[7] == 1, "payload: динамиков в сети = 1 (новое поле Код 89)")

P("== 2. Armed → триггер сенсора → сирена хаба И динамика ==")
ok(A.SetMode("main", A.MODE_ARMED, admin), "режим сети → Под охраной")
ok(hub:GetMode() == A.MODE_ARMED, "хаб запомнил режим")
H.players = { intruder }
H.trace = { Hit = false } -- прямая видимость
TT = 100
fireThink()
ok(hub:GetAlarmActive() == true, "тревога активна после движения в зоне")
local hubPatch = patchFor(hub)
ok(hubPatch ~= nil and hubPatch.playing and not hubPatch.stopped, "сирена хаба играет")
ok(hubPatch.loop == true, "сирена хаба ЗАЦИКЛЕНА (находка 176: EnableLooping)")
local spkPatch = patchFor(spk)
ok(spkPatch ~= nil and spkPatch.playing and not spkPatch.stopped, "сирена ДИНАМИКА играет (Код 89)")
ok(spkPatch.loop == true, "сирена динамика ЗАЦИКЛЕНА (находка 176)")
ok(spkPatch ~= nil and spkPatch.path == "ambient/alarms/combine_bank_alarm_loop4.wav", "динамик играет тот же луп сирены")
A.ResetAlarm("main", admin)
ok(hub:GetAlarmActive() == false, "сброс тревоги: AlarmActive=false")
ok(hubPatch.stopped == true, "сирена хаба остановлена")
ok(spkPatch.stopped == true, "сирена динамика остановлена синком (Код 89)")
local orphan = 0
for _ in pairs(A.SpeakerPatches) do orphan = orphan + 1 end
ok(orphan == 0, "патчей-сирот динамиков не осталось")

P("== 3. set_speaker: выключение динамика глушит его звук + автосейв ==")
A.StartSiren(hub, "тест", nil)
local spkPatch2 = patchFor(spk)
ok(spkPatch2 ~= nil and spkPatch2.playing, "динамик снова играет при тревоге")
fireAlarmAct(admin, { action = "set_speaker", entIndex = spk:EntIndex(), active = false })
ok(spk:GetActive() == false, "динамик выключен из панели")
ok(spkPatch2.stopped == true, "его патч остановлен немедленно")
ok(H.timers["GRM_Alarm_SaveSoon"] ~= nil, "автосейв-дебаунс запланирован (Код 89)")
H.timers["GRM_Alarm_SaveSoon"]()
local saved1 = fileTable("grm_alarm/gm_simtown.json")
ok(istable(saved1), "перманент-сейв записан после правки")

P("== 4. set_network из терминала (строка сети в панели, Код 89) ==")
ok(trm:GetNetworkID() == "main", "до: сеть терминала = main")
fireAlarmAct(admin, { action = "set_network", entIndex = trm:EntIndex(), network = "Bank" })
ok(trm:GetNetworkID() == "bank", "после: сеть терминала = bank (нормализация регистра)")
H.timers["GRM_Alarm_SaveSoon"]()
local saved2 = fileTable("grm_alarm/gm_simtown.json")
local trmRec = nil
for _, rec in ipairs(saved2 or {}) do
  if rec.class == "grm_alarm_terminal" then trmRec = rec end
end
ok(istable(trmRec) and trmRec.network == "bank", "новая сеть утонула в перманент-сейве")
-- вернём терминал в main для чистоты мира
fireAlarmAct(admin, { action = "set_network", entIndex = trm:EntIndex(), network = "main" })
A.ResetAlarm("main", admin)

P("== 5. Перманентная выключенность динамика: тревога его не будит ==")
A.StartSiren(hub, "тест2", nil)
local spkPatch3 = patchFor(spk)
ok(spkPatch3 == nil or spkPatch3.stopped or not spkPatch3.playing,
  "динамик Active=false → новых патчей не запущено (сторожевой sync)")
local alive = 0
for _ in pairs(A.SpeakerPatches) do alive = alive + 1 end
ok(alive == 0, "в таблице патчей динамиков пусто при выключенном динамике")
A.ResetAlarm("main", admin)

P("== 6. SavePermanent/LoadPermanent roundtrip (все поля) ==")
-- отдельный мир «alpha», чтобы roundtrip не мешал main
local hub2 = mkEnt("grm_alarm_hub", 1000, 0, 0)
hub2:SetDeviceID("hub2") hub2:SetLabel("Хаб Alfa") hub2:SetNetworkID("alpha")
hub2:SetMode(A.MODE_ARMED) hub2:SetAlarmActive(false) hub2:SetPermanent(true)
A.RegisterDevice(hub2)
local spk2 = mkEnt("grm_alarm_speaker", 1020, 0, 0)
spk2:SetDeviceID("spk2") spk2:SetLabel("Динамик Alfa") spk2:SetNetworkID("alpha")
spk2:SetActive(false) spk2:SetPermanent(true)
A.RegisterDevice(spk2)
local sen2 = mkEnt("grm_alarm_sensor", 1040, 0, 0)
sen2:SetDeviceID("sen2") sen2:SetLabel("Сенсор Alfa") sen2:SetNetworkID("alpha")
sen2:SetActive(false) sen2:SetRadius(333) sen2:SetLastTrigger(0) sen2:SetPermanent(true)
A.RegisterDevice(sen2)
ok(A.SavePermanent() == true, "SavePermanent отработал")
local snapshot = fileTable("grm_alarm/gm_simtown.json")
ok(istable(snapshot) and countOfClass(snapshot, "grm_alarm_speaker") == 2,
  "в сейве оба динамика (main + alpha)")
local spkRec = nil
for _, rec in ipairs(snapshot or {}) do
  if rec.class == "grm_alarm_speaker" and rec.network == "alpha" then spkRec = rec end
end
ok(istable(spkRec) and spkRec.active == false, "сейв хранит active=false динамика (Код 89)")
-- «рестарт карты»: вайп реестра и мира
A.Devices = {}
A.Sirens = {}
A.SpeakerPatches = {}
resetREG()
H.sounds = {}
local nLoaded = A.LoadPermanent()
ok(nLoaded == 7, "LoadPermanent воскресил все 7 перманентов (4 сети main + 3 сети alpha)")
local lSpk = nil
for _, e in ipairs(ents.FindByClass("grm_alarm_speaker")) do
  if e:GetNetworkID() == "alpha" then lSpk = e end
end
ok(IsValid(lSpk), "динамик alpha воскрешён энтити")
ok(IsValid(lSpk) and lSpk:GetActive() == false, "...и его Active=false доехал (Код 89)")
ok(IsValid(lSpk) and lSpk:GetPermanent() == true, "...и Permanent-флаг восстановлен")
ok(IsValid(lSpk) and lSpk:GetLabel() == "Динамик Alfa", "...и подпись на месте")
local lSenA = nil
for _, e in ipairs(ents.FindByClass("grm_alarm_sensor")) do
  if e:GetNetworkID() == "alpha" then lSenA = e end
end
ok(IsValid(lSenA) and lSenA:GetRadius() == 333, "радиус датчика восстановлен (333)")
ok(IsValid(lSenA) and lSenA:GetActive() == false, "Active=false датчика восстановлен")
local lHubA = nil
for _, e in ipairs(ents.FindByClass("grm_alarm_hub")) do
  if e:GetNetworkID() == "alpha" then lHubA = e end
end
ok(IsValid(lHubA) and lHubA:GetMode() == A.MODE_ARMED, "режим хаба восстановлен (охрана)")
-- антидубль: повторная загрузка не ставит на занятое место
local nAgain = A.LoadPermanent()
ok(nAgain == 0, "повторный LoadPermanent: антидубль по месту (0 новых)")

P("== 7. Универсальный перм: новые классы Код 89 ==")
A.Devices = {}
resetREG()
H.chatlog = {}
local keypad = mkEnt("grm_keypad", 200, 0, 0)
local mobileLine = mkEnt("grm_mobile_line", 500, 0, 0)
local speaker3 = mkEnt("grm_alarm_speaker", 300, 0, 0)
H.trace = { Hit = false, Entity = keypad }
H.hooks.PlayerSay["GRM_PermEntities_Chat"](admin, "/permadd")
local permList = fileTable("grm_perm_entities.json")
ok(istable(permList) and countOfClass(permList, "grm_keypad") == 1, "grm_keypad принят в пермы (Код 89)")
H.hooks.PlayerSay["GRM_PermEntities_Chat"](admin, "/permadd")
permList = fileTable("grm_perm_entities.json")
ok(countOfClass(permList, "grm_keypad") == 1, "повторный /permadd: дедуп, записей всё ещё 1")
local dupMsg = false
for _, c in ipairs(H.chatlog) do if string.find(c, "уже в пермах") then dupMsg = true end end
ok(dupMsg, "админу показано «уже в пермах»")
H.trace = { Hit = false, Entity = speaker3 }
H.hooks.PlayerSay["GRM_PermEntities_Chat"](admin, "/permadd")
permList = fileTable("grm_perm_entities.json")
ok(countOfClass(permList, "grm_alarm_speaker") == 1, "grm_alarm_speaker принят в пермы (Код 89)")
H.trace = { Hit = false, Entity = mobileLine }
local before = countOfClass(fileTable("grm_perm_entities.json"), "grm_mobile_line")
H.hooks.PlayerSay["GRM_PermEntities_Chat"](admin, "/permadd")
local after = countOfClass(fileTable("grm_perm_entities.json"), "grm_mobile_line")
ok(before == 0 and after == 0, "временная grm_mobile_line отвергнута")
local rejMsg = false
for _, c in ipairs(H.chatlog) do if string.find(c, "нельзя пермить") then rejMsg = true end end
ok(rejMsg, "админу показано «нельзя пермить»")
-- «рестарт»: воскрешение из базы
resetREG()
H.hooks.InitPostEntity["GRM_PermEntities_Spawn"]()
ok(#ents.FindByClass("grm_keypad") == 1, "перм-кейпад воскрешён после «рестарта»")
ok(#ents.FindByClass("grm_alarm_speaker") == 1, "перм-динамик воскрешён после «рестарта»")
local risen = ents.FindByClass("grm_keypad")[1]
ok(IsValid(risen) and risen._grmPerm == true, "воскрешённый помечен _grmPerm")
-- антидубль при /permload поверх живой карты
H.hooks.PlayerSay["GRM_PermEntities_Chat"](admin, "/permload")
ok(#ents.FindByClass("grm_keypad") == 1, "/permload: дублей на занятых точках нет")

P("== 8. CCTV: автосейв персистента на сеттерах (Код 89) ==")
resetREG()
local cam = mkEnt("grm_cctv_camera", 800, 0, 0)
cam:SetDeviceID("cam1") cam:SetLabel("Камера") cam:SetNetworkID("main")
cam:SetActive(true) cam:SetCamFOV(75) cam:SetPermanent(true)
CCTV.RegisterDevice(cam)
admin.__pos = V(800, 0, 0)
-- было: правила менялись без сейва; теперь saveSoon-дебаунс
H.seq = { "set_network", cam, "Vault" }
H.netrecv["GRM_CCTV_Action"](0, admin)
ok(cam:GetNetworkID() == "vault", "set_network: сеть камеры = vault")
ok(H.timers["GRM_CCTV_SaveSoon"] ~= nil, "CCTV автосейв-дебаунс запланирован (Код 89)")
H.timers["GRM_CCTV_SaveSoon"]()
local ccSaved = fileTable("grm_cctv/gm_simtown.json")
ok(istable(ccSaved) and istable(ccSaved[1]) and ccSaved[1].network == "vault",
  "новая сеть камеры записана в перманент-сейв CCTV")

P("")
P(("РЕЗУЛЬТАТ: %d/%d проверок, провалов: %d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
P("SIM SECURITY: OK")
