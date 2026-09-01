-- Симуляция сервера GMod для Кода 88 (мобильные телефоны, GTA IV) + регресс
-- телефонии Код 88.1 (репорт «чат закрыт»: звонки-призраки глушили чат).
-- БЕЗ GMod: грузятся РЕАЛЬНЫЕ sv_grm_phone.lua, sh_grm_mobile.lua,
-- sh_grm_phone_shop.lua, sh_grm_rp_chat.lua, sh_grm_chat_config.lua на моках.
----------------------------------------------------------------------

string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
string.Explode = function(sep, s)
  s = tostring(s or "")
  local out, pos = {}, 1
  while true do
    local i = string.find(s, sep, pos, true)
    if not i then out[#out + 1] = string.sub(s, pos) break end
    out[#out + 1] = string.sub(s, pos, i - 1)
    pos = i + #sep
  end
  return out
end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.Copy = function(t)
  local o = {}
  for k, v in pairs(t or {}) do
    o[k] = (type(v) == "table") and table.Copy(v) or v
  end
  return o
end

local H = { hooks = {}, timers = {}, netlog = {}, netrecv = {}, seq = {}, notify = {}, players = {} }
_G._SIM = H
local realPrint = print
local function P(...) realPrint(...) end

function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end
NULL = false
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
IsColor = function(v) return istable(v) and v.r ~= nil and v.g ~= nil and v.b ~= nil end

-- вектора --------------------------------------------------------------
local VMT = {}
VMT.__index = function(self, k)
  if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
  if k == "Angle" then return function() return { p = 0, y = 0, r = 0 } end end
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

-- реестр энтити ---------------------------------------------------------
local REG = { byClass = {}, byIdx = {}, nextIdx = 1 }
local function mkEnt(class, x, y, z)
  local e = { __class = class, __pos = V(x, y, z), __nw = {}, __dt = {}, __idx = REG.nextIdx, __ang = Angle(0, 0, 0), __snd = {} }
  REG.nextIdx = REG.nextIdx + 1
  local mt
  mt = { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, p) self.__pos = p end end
    if k == "GetAngles" then return function() return self.__ang end end
    if k == "SetAngles" then return function(_, a) self.__ang = a end end
    if k == "GetClass" then return function() return self.__class end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "GetModel" then return function() return self.__model or "" end end
    if k == "SetModel" then return function(_, m) self.__model = m end end
    local nwget = k:match("^GetNW(%w+)$")
    if nwget then return function(_, key, def) local v = self.__nw[key] if v == nil then return def end return v end end
    local nwset = k:match("^SetNW(%w+)$")
    if nwset then return function(_, key, val) self.__nw[key] = val end end
    -- DT-аксессоры телефонных энтити (как в shared.lua классов)
    local dtg = k:match("^Get(%w+)$")
    if dtg and rawget(self, "__dt")[dtg] ~= nil then return function() return self.__dt[dtg] end end
    local dts = k:match("^Set(%w+)$")
    if dts and rawget(self, "__dt")[dts] ~= nil then return function(_, v) self.__dt[dts] = v end end
    if k == "EmitSound" then return function(_, s) self.__snd[#self.__snd + 1] = s end end
    if k == "Spawn" then return function() end end
    if k == "Activate" then return function() end end
    if k == "GetPhysicsObject" then return function() return { EnableMotion = function() end } end end
    if k == "Remove" then return function() self.__removed = true
      local list = REG.byClass[self.__class] or {}
      for i, x in ipairs(list) do if x == self then table.remove(list, i) break end end
      REG.byIdx[self.__idx] = nil end end
    return nil
  end }
  e = setmetatable(e, mt)
  REG.byClass[class] = REG.byClass[class] or {}
  table.insert(REG.byClass[class], e)
  REG.byIdx[e.__idx] = e
  return e
end

local DT_PHONE = { PhoneNumber = "", DisplayName = "", ExchangeID = "main", LineState = "idle", CallID = 0, OtherPhone = false,
                   OwnerSID64 = "", TerminalName = "", TargetNumber = "", Active = false, MaxLines = 60 }
local function attachPhoneDT(e, class)
  for k, v in pairs(DT_PHONE) do e.__dt[k] = v end
  if class == "grm_mobile_line" then e.IsMobile = true e.__dt.ExchangeID = "cell" end
  return e
end

ents = { FindByClass = function(c) return REG.byClass[c] or {} end,
         Create = function(c) return attachPhoneDT(mkEnt(c, 0, 0, 0), c) end }
Entity = function(i) return REG.byIdx[i] end

-- игроки -----------------------------------------------------------------
local function mkPly(id, x, isSAdmin)
  local p = { __pos = V(x, 0, 0), __idx = id, __sa = isSAdmin and true or false, __isply = true }
  p = setmetatable(p, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, v) self.__pos = v end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "IsSuperAdmin" then return function() return self.__sa end end
    if k == "IsAdmin" then return function() return self.__sa end end
    if k == "IsPlayer" then return function() return true end end
    if k == "Alive" then return function() return true end end
    if k == "SteamID" then return function() return "STEAM_0:1:" .. tostring(self.__idx) end end
    if k == "SteamID64" then return function() return "76561198000000" .. tostring(100 + self.__idx) end end
    if k == "PrintMessage" then return function(_, _, txt) H.notify[#H.notify + 1] = { ply = self, msg = tostring(txt) } end end
    if k == "GetShootPos" then return function() return self.__pos end end
    if k == "GetAimVector" then return function() return V(1, 0, 0) end end
    if k == "GetForward" then return function() return V(1, 0, 0) end end
    if k == "Nick" then return function() return "Игрок" .. tostring(self.__idx) end end
    if k == "Health" then return function() return 100 end end
    if k == "GetMaxHealth" then return function() return 100 end end
    if k == "Armor" then return function() return 0 end end
    if k == "GetNWString" then return function(_, key, def)
      if key == "GRM_RPName" then return self.__rpname or "" end
      return def end end
    if k == "SetNWString" then return function(_, key, v) if key == "GRM_RPName" then self.__rpname = v end end end
    if k == "GetNWBool" then return function(_, _, def) return def end end
    if k == "LookupBone" then return function() return nil end end -- hand-проп не крутим в стенде
    if k == "GetEyeTrace" then return function() return { Entity = nil } end end
    if k == "EmitSound" then return function() end end
    return nil
  end })
  return p
end

local function addPlayer(p) H.players[#H.players + 1] = p return p end
local function delPlayer(p)
  for i, x in ipairs(H.players) do if x == p then table.remove(H.players, i) return end end
end

-- окружение GMod ---------------------------------------------------------
local FILES = {}
local JSON_HOLD = {}
util = {
  AddNetworkString = function() end,
  -- плоский мок: расшифровка возвращает объект последней сериализации (или подмену врачом)
  JSONToTable = function(t, a, b) return JSON_HOLD end,
  TableToJSON = function(t) JSON_HOLD = t return "TBL" end,
  TraceLine = function() return { Entity = nil } end,
}
file = { Read = function(p) return FILES[p] end,
         Write = function(p, d) FILES[p] = d end,
         Append = function(p, d) FILES[p] = (FILES[p] or "") .. tostring(d) end,
         Exists = function(p) return FILES[p] ~= nil end,
         IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Remove = function(name, id) if H.hooks[name] then H.hooks[name][id] = nil end end,
         Run = function() end }
timer = { Create = function(name, d, r, fn) H.timers[name] = fn end,
          Simple = function(_, fn) if fn then fn() end end }
player = { GetAll = function() return H.players end,
           GetBySteamID64 = function(sid)
             for _, p in ipairs(H.players) do if p:SteamID64() == tostring(sid) then return p end end
             return nil end }
game = { GetMap = function() return "gm_simtown" end }
net = { Start = function(m) H.cur = { msg = m, f = {} } end,
        WriteUInt = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteFloat = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteDouble = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteInt = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteEntity = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteData = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteString = function(v) H.cur.f[#H.cur.f + 1] = v end,
        WriteBool = function(v) H.cur.f[#H.cur.f + 1] = v and "T" or "F" end,
        WriteTable = function(v) H.cur.f[#H.cur.f + 1] = v end,
        Broadcast = function() H.netlog[#H.netlog + 1] = H.cur H.cur = nil end,
        Send = function(p) if H.cur then
          if istable(p) and not p.__isply then H.cur.multicast = #p end
          H.cur.sentTo = p H.netlog[#H.netlog + 1] = H.cur H.cur = nil end end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
net.ReadUInt = function() return tonumber(table.remove(H.seq, 1)) or 0 end
net.ReadInt = function() return tonumber(table.remove(H.seq, 1)) or 0 end
net.ReadEntity = function() return table.remove(H.seq, 1) end
net.ReadBool = function() return (table.remove(H.seq, 1)) == "T" end
net.ReadString = function() return tostring(table.remove(H.seq, 1) or "") end
net.ReadTable = function() local v = table.remove(H.seq, 1) return istable(v) and v or {} end
concommand = { Add = function() end }
HUD_PRINTTALK = 3
TT = 0
CurTime = function() return TT end
AddCSLuaFile = function() end
include = function(p) if p == "autorun/sh_grm_phone_config.lua" then dofile("lua/autorun/sh_grm_phone_config.lua") end end
MOVETYPE_NONE = 0 SOLID_NONE = 1

local function fire(name, ...) for _, fn in pairs(H.hooks[name] or {}) do fn(...) end end
local function netlog(pred)
  local out = {}
  for _, e in ipairs(H.netlog) do if pred(e) then out[#out + 1] = e end end
  return out
end

-- ══ загрузка модулей ═══════════════════════════════════════════════════
SERVER = true CLIENT = false
GRM = {}

GRM.Notify = function(ply, msg, r, g, b) H.notify[#H.notify + 1] = { ply = ply, msg = tostring(msg) } end
GRM.Format = function(n) return tostring(n) .. "р" end
local WALLET = {}
GRM.HasMoney = function(ply, n) return (WALLET[ply:SteamID64()] or 0) >= (n or 0) end
GRM.GetBalance = function(ply) return WALLET[ply:SteamID64()] or 0 end
GRM.TakeMoney = function(ply, n) WALLET[ply:SteamID64()] = math.max(0, (WALLET[ply:SteamID64()] or 0) - n) end
GRM.GiveMoney = function(ply, n) WALLET[ply:SteamID64()] = (WALLET[ply:SteamID64()] or 0) + n end

local IVDEFS, INVS = {}, {}
GRM.Inventory = {
  Config = { MaxSlots = 24 },
  RegisterItem = function(id, data) IVDEFS[id] = data end,
  GetItemDef = function(id) return IVDEFS[id] end,
  GetMaxStack = function(id) local d = IVDEFS[id] return (d and d.maxStack) or 1 end,
  GetPlayerInv = function(ply) INVS[ply:SteamID64()] = INVS[ply:SteamID64()] or { slots = {} } return INVS[ply:SteamID64()] end,
  AddItem = function(ply, id, count)
    count = count or 1
    local inv = GRM.Inventory.GetPlayerInv(ply)
    if not IVDEFS[id] then return count end
    local left = count
    for i = 1, GRM.Inventory.Config.MaxSlots do
      if left <= 0 then break end
      if not inv.slots[i] then inv.slots[i] = { id = id, count = left } left = 0 end
    end
    return left
  end,
  CountItem = function(ply, id)
    local inv = GRM.Inventory.GetPlayerInv(ply)
    local n = 0
    for _, s in pairs(inv.slots) do if s and s.id == id then n = n + (s.count or 1) end end
    return n
  end,
  SyncSlot = function() end,
}

dofile("lua/autorun/sh_grm_chat_config.lua")
dofile("lua/autorun/server/sv_grm_phone.lua")
dofile("lua/autorun/sh_grm_mobile.lua")
dofile("lua/autorun/sh_grm_rp_chat.lua")
dofile("lua/autorun/sh_grm_phone_shop.lua")

local MB = GRM.Mobile
local PH = GRM.Phone

-- муляж RadioNet: стойка поднята; качество по X: ≤100 → 0.5, ≤400 → 0.2, иначе 0
GRM.RadioNet = { _activeRacks = { {} }, QualityAt = function(pos)
  if pos.x <= 100 then return 0.5 elseif pos.x <= 400 then return 0.2 end
  return 0 end }

-- фреймворк ---------------------------------------------------------------
local checks, failed = 0, 0
local function ok(cond, name)
  checks = checks + 1
  if cond then P("  ok " .. tostring(checks) .. ". " .. name)
  else failed = failed + 1 P("  FAIL " .. tostring(checks) .. ". " .. name) end
end
local function hasNotif(ply, needle)
  for _, n in ipairs(H.notify) do
    if n.ply == ply and string.find(n.msg, needle, 1, true) then return true end
  end
  return false
end
-- внутренний notify телефонии пишет в NET_INFO (GRM_Phone_Info)
local function hasInfo(ply, needle)
  for _, e in ipairs(H.netlog) do
    if e.msg == "GRM_Phone_Info" and isstring(e.f[1]) and string.find(e.f[1], needle, 1, true) then
      if e.sentTo == ply then return true end
      if istable(e.sentTo) then
        for _, p in ipairs(e.sentTo) do if p == ply then return true end end
      end
    end
  end
  return false
end
local function clearLogs() H.netlog = {} H.notify = {} end

-- ══ 1. Тиры и регистрация предметов ════════════════════════════════════
P("== 1. Тиры и регистрация предметов ==")
ok(istable(MB), "GRM.Mobile загружен")
ok(#MB.Order == 7, "7 тиров в Order")
local allReg = true
for _, tk in ipairs(MB.Order) do
  local t = MB.Tiers[tk]
  if not (t and IVDEFS[t.item] and IVDEFS[t.item].useFunc == "mobile_open" and IVDEFS[t.item].model == t.model) then allReg = false end
end
ok(allReg, "все 7 трубок зарегистрированы (mobile_open + модель)")
ok(MB.Tiers.crappy.sms == false and MB.Tiers.tinkle.apps == true, "флаги: crappy без SMS, tinkle с приложениями")
ok(MB.Tiers.crappy.minQ > MB.Tiers.whiz_gold.minQ, "порог сигнала: дешёвый требовательнее (0.35 vs 0.10)")
ok(#MB.AvailableApps("crappy")==3,"crappy: Телефон+Калькулятор+Такси")
ok(#MB.AvailableApps("badger")==5,"badger: +SMS+Контакты+Такси")
ok(#MB.AvailableApps("tinkle")==9,"tinkle: все приложения + Такси")

-- ══ 2. Номера и сигнал ════════════════════════════════════════════════
P("== 2. Номера и сигнал ==")
local n1 = MB.GenerateNumber()
ok(#n1 == 5 and tonumber(n1) >= 10000 and tonumber(n1) <= 99999, "мобильный номер 5-значный: " .. n1)
local p1 = addPlayer(mkPly(1, 0, true))
WALLET[p1:SteamID64()] = 100000
ok(MB.CarriedTier(p1) == nil, "нет телефона — тира нет")
GRM.Inventory.AddItem(p1, "mobile_crappy", 1)
GRM.Inventory.AddItem(p1, "mobile_whiz_gold", 1)
ok(MB.CarriedTier(p1) == "whiz_gold", "активная линия — по ЛУЧШЕЙ трубке")
local rnBackup = GRM.RadioNet
GRM.RadioNet = nil
ok(MB.SignalOf(p1) == 1, "без RadioNet сигнал = 1 (свободная связь)")
GRM.RadioNet = rnBackup
ok(MB.SignalOf(p1) == 0.5, "при живой сети сигнал = QualityAt")
p1:SetPos(V(200, 0, 0))
ok(MB.SignalOf(p1) == 0.2, "край покрытия: 0.2")
ok(not MB.SignalOK(p1, "crappy") and MB.SignalOK(p1, "whiz_gold"), "при 0.2 crappy глохнет, золотой работает")
p1:SetPos(V(1000, 0, 0))
ok(MB.SignalOf(p1) == 0 and not MB.SignalOK(p1, "whiz_gold"), "вне покрытия глохнет даже золотой")
p1:SetPos(V(0, 0, 0))

-- ══ 3. Жизненный цикл линии ════════════════════════════════════════════
P("== 3. Жизненный цикл линии ==")
TT = 1
fireThink0 = nil
H.timers["GRM_Mob_Think"]()
local line = MB.Lines[p1:SteamID64()]
ok(IsValid(line) and line:GetClass() == "grm_mobile_line", "линия создана тикером")
ok(line.IsMobile == true, "линия IsMobile")
ok(#tostring(line:GetPhoneNumber()) == 5, "5-значный номер на линии")
ok(line:GetExchangeID() == "cell", "АТС линии = cell")
ok(MB.LineOnline(line) == true, "LineOnline в покрытии (0.5)")
ok(MB.CanUseLine(p1, line) == true, "CanUseLine: владелец + трубка в инвентаре")
p1:SetPos(V(250, 350, 0))
H.timers["GRM_Mob_Think"]()
ok(line:GetPos().x == 250 and line:GetPos().y == 350, "линия следует за владельцем")
-- убрал телефоны → линия снимается
local inv1 = GRM.Inventory.GetPlayerInv(p1)
for i, s in pairs(inv1.slots) do
  if s and IVDEFS[s.id] and IVDEFS[s.id].useFunc == "mobile_open" then inv1.slots[i] = nil end
end
H.timers["GRM_Mob_Think"]()
ok(MB.Lines[p1:SteamID64()] == nil, "трубка убрана → запись линии очищена")
ok(line.__removed == true, "энтити линии удалена из мира")

-- ══ 4. Звонок: мобильный ↔ город + голос + текст + прослушка ═══════════
P("== 4. Звонок мобильный ↔ стационарный ==")
GRM.Inventory.AddItem(p1, "mobile_tinkle", 1)
local pbx = ents.Create("grm_pbx_station")
pbx:SetPos(V(500, 0, 0)) pbx.__dt.Active = true pbx.__dt.ExchangeID = "main" pbx.__dt.MaxLines = 60
local phoneB = ents.Create("grm_phone")
phoneB:SetPos(V(500, 0, 0))
phoneB.__dt.PhoneNumber = "1234" phoneB.__dt.DisplayName = "Квартира Б" phoneB.__dt.ExchangeID = "main"
local p2 = addPlayer(mkPly(2, 500, false))
p1:SetPos(V(0, 0, 0))
H.timers["GRM_Mob_Think"]()
line = MB.Lines[p1:SteamID64()]
ok(IsValid(line), "линия восстановлена с новой трубкой")
local num1 = line:GetPhoneNumber()
clearLogs()
MB.Dial(p1, "1234")
ok(table.Count(PH.Calls) == 1, "запись звонка создана")
ok(line:GetLineState() == "dialing" and phoneB.__dt.LineState == "ringing", "dialing → ringing")
ok(hasInfo(p1, "Вызов номера"), "уведомление о наборе (NET_INFO)")
PH.Answer(p2, phoneB)
local myCall = PH.Calls[line:GetCallID()]
ok(istable(myCall) and myCall.answered == true, "вызов принят")
ok(line:GetLineState() == "call" and phoneB.__dt.LineState == "call", "обе линии в call")
-- голос: локально далеко (500>355), слышно ТОЛЬКО по телефону
local vh = H.hooks["PlayerCanHearPlayersVoice"]["GRM_Phone_IntegratedVoice"]
ok(vh(p2, p1) == true, "голос: город слышит мобильного (по линии, не локально)")
ok(vh(p1, p2) == true, "голос: мобильный слышит город")
-- текстовое реле: сообщение глушится и летит в линию
clearLogs()
local r1 = H.hooks["PlayerSay"]["GRM_Phone_LineTextChat"](p1, "зайди за товаром")
ok(r1 == "", "во время разговора чат глушится в трубку (by design)")
ok(#netlog(function(e) return e.msg == "GRM_Phone_Text" end) >= 2, "текст доставлен абоненту (+ эхо)")
-- прослушка ловит мобильный номер
local tap = ents.Create("grm_phone_wiretap")
tap:SetPos(V(3000, 0, 0))
tap.__dt.Active = true tap.__dt.TargetNumber = num1 tap.__dt.ExchangeID = ""
local p10 = addPlayer(mkPly(10, 3000, false))
PH.Monitoring[p10] = tap
ok(vh(p10, p1) == true, "прослушка: голос мобильного слышен (дистанция 3000!)")
clearLogs()
H.hooks["PlayerSay"]["GRM_Phone_LineTextChat"](p1, "склад на окраине")
ok(#netlog(function(e) return e.msg == "GRM_Phone_Text" and e.f[6] == "T" end) >= 1, "прослушка получила копию текста")
PH.Monitoring[p10] = nil
-- сторонний игрок не глушится
local p3 = addPlayer(mkPly(3, 0, false))
ok(H.hooks["PlayerSay"]["GRM_Phone_LineTextChat"](p3, "просто так") == nil, "прохожий вне звонка не глушится")

-- ══ 5. Потеря сигнала рвёт разговор ════════════════════════════════════
P("== 5. Потеря сигнала ==")
p1:SetPos(V(1000, 0, 0))
H.timers["GRM_Mob_Think"]()
ok(table.Count(PH.Calls) == 0, "разговор оборван потерей сигнала")
ok(line:GetLineState() == "idle", "мобильная линия в idle")
ok(phoneB.__dt.LineState == "idle", "городская линия в idle")
ok(hasNotif(p1, "потерян сигнал"), "уведомление «потерян сигнал»")
p1:SetPos(V(0, 0, 0))
H.timers["GRM_Mob_Think"]()

-- ══ 6. SMS / контакты / заметки ════════════════════════════════════════
P("== 6. SMS, контакты, заметки ==")
local p4 = addPlayer(mkPly(4, 0, false))
GRM.Inventory.AddItem(p4, "mobile_badger", 1)
H.timers["GRM_Mob_Think"]()
local line4 = MB.Lines[p4:SteamID64()]
ok(IsValid(line4), "линия второго абонента создана")
local num4 = line4:GetPhoneNumber()
clearLogs()
MB.SendSms(p1, num4, "гони деньги · кириллица тоже")
ok(#(MB.Data[p4:SteamID64()].sms) == 1, "SMS дошло до ящика второго")
ok(#(MB.Data[p1:SteamID64()].sms) == 1, "копия «исходящее» сохранена")
ok(MB.Data[p4:SteamID64()].sms[1].dir == "in" and MB.Data[p4:SteamID64()].sms[1].read == false, "входящее непрочитанное")
MB.HandleAction(p4, { op = "open" })
local sl = netlog(function(e) return e.msg == "GRM_Mob_State" and e.sentTo == p4 end)
ok(sl[#sl].f[1].unread == 1, "бейдж непрочитанных = 1")
MB.HandleAction(p4, { op = "sms_read" })
MB.HandleAction(p4, { op = "open" })
sl = netlog(function(e) return e.msg == "GRM_Mob_State" and e.sentTo == p4 end)
ok(sl[#sl].f[1].unread == 0, "sms_read снял непрочитанные")
MB.SendSms(p1, "77777", "никто не ответит")
ok(hasNotif(p1, "не обслуживается"), "SMS на несуществующий номер — отказ")
-- crappy не умеет SMS
local p5 = addPlayer(mkPly(5, 0, false))
GRM.Inventory.AddItem(p5, "mobile_crappy", 1)
clearLogs()
MB.HandleAction(p5, { op = "sms", num = num4, text = "test" })
ok(hasNotif(p5, "не умеет SMS"), "crappy: SMS закрыты тиром")
-- контакты на badger
MB.HandleAction(p4, { op = "contact_add", name = "Жорик", num = num1 })
MB.HandleAction(p4, { op = "contact_add", name = "Альфонс", num = "55555" })
local crec = MB.Data[p4:SteamID64()].contacts
ok(#crec == 2 and crec[1].name == "Альфонс", "контакты сохраняются и сортируются")
for i = 1, 60 do MB.HandleAction(p4, { op = "contact_add", name = "n" .. i, num = tostring(40000 + i) }) end
ok(#MB.Data[p4:SteamID64()].contacts <= MB.ContactsCap, "кап контактов " .. MB.ContactsCap)
MB.HandleAction(p4, { op = "contact_del", i = 1 })
local cc = #MB.Data[p4:SteamID64()].contacts
ok(cc >= 0 and cc <= MB.ContactsCap, "удаление контакта отработало")
-- заметки: на tinkle можно, на badger нельзя
MB.HandleAction(p1, { op = "note_add", text = "код от двери 4451" })
ok(#MB.Data[p1:SteamID64()].notes == 1, "заметка добавлена (tinkle)")
MB.HandleAction(p1, { op = "note_del", i = 1 })
ok(#MB.Data[p1:SteamID64()].notes == 0, "заметка удалена")
MB.HandleAction(p4, { op = "note_add", text = "---" })
ok(#MB.Data[p4:SteamID64()].notes == 0, "badger: заметки закрыты тиром")

-- ══ 7. Форум ════════════════════════════════════════════════════════════
P("== 7. Форум ==")
MB.HandleAction(p1, { op = "forum_post", text = "продаю гараж недорого" })
ok(#MB.Forum.posts == 1, "первый пост прошёл")
local firstForumID = tonumber(MB.Forum.posts[1] and MB.Forum.posts[1].id)
ok(firstForumID and firstForumID > 0, "публикация получила серверный ID")
MB.HandleAction(p1, { op = "forum_like", id = firstForumID })
ok(#(MB.Forum.posts[1].likes or {}) == 1, "реакция добавлена сервером по CharacterKey")
TT = TT + 0.5
MB.HandleAction(p1, { op = "forum_like", id = firstForumID })
ok(#(MB.Forum.posts[1].likes or {}) == 0, "повторная реакция корректно снимается")
MB.HandleAction(p1, { op = "forum_post", text = "сразу второй" })
ok(#MB.Forum.posts == 1, "рейт-лимит: второй подряд отклонён")
MB.HandleAction(p4, { op = "forum_post", text = "пост от badger" })
ok(#MB.Forum.posts == 1, "badger не может постить (apps закрыт)")
p1._grmMobForumTs = os.time() - 10
MB.HandleAction(p1, { op = "forum_post", text = "после паузы можно", replyTo = firstForumID })
ok(#MB.Forum.posts == 2, "после паузы пост проходит")
ok(tonumber(MB.Forum.posts[1].replyTo) == firstForumID and MB.Forum.posts[1].replyAuthor ~= "", "ответ привязан сервером к существующей публикации")
for i = 1, 200 do p1._grmMobForumTs = nil MB.HandleAction(p1, { op = "forum_post", text = "спам " .. i }) end
ok(#MB.Forum.posts <= MB.ForumCap, "кап форума " .. MB.ForumCap)
MB.HandleAction(p1, { op = "forum_query" })
local fl = netlog(function(e) return e.msg == "GRM_Mob_Data" and e.sentTo == p1 and e.f[1] == "forum" end)
ok(#fl >= 1 and #fl[#fl].f[2].rows <= 40, "forum_query: ≤40 строк, новые сверху")
ok(fl[#fl].f[2].rows[1].text ~= nil, "строки форума непустые")

-- ══ 8. Биржа и фракция ══════════════════════════════════════════════════
P("== 8. Биржа труда и фракция ==")
GRM.Jobs = { Cfg = { posts = {
  ["Порт"] = { { title = "разгрузить баржу", kind = "order", reward = 800, desc = "быстро" },
               { title = "вахта охраны", kind = "vacancy", salary = 120, shiftsLeft = 3, desc = "ночная" },
               { title = "занятое", kind = "order", reward = 10, takenBy = "x" } },
} }, Active = {} }
MB.HandleAction(p1, { op = "jobs_query" })
local jl = netlog(function(e) return e.msg == "GRM_Mob_Data" and e.f[1] == "jobs" and e.sentTo == p1 end)
ok(#jl >= 1 and #jl[#jl].f[2].rows == 2, "биржа: 2 строки, занятый заказ отфильтрован")
ok(jl[#jl].f[2].rows[1].fac == "Порт", "строки биржи сгруппированы по фракции")
-- фракция: p1 лидер, p2 член, один офлайн
Factions = { ["Люди горыныча"] = {
  Leader = p1:SteamID64(),
  Members = {
    [p1:SteamID64()] = { Role = "атаман", Department = "штаб" },
    [p2:SteamID64()] = { Role = "боец", Department = "патруль" },
    ["offline_ivan"] = { Role = "снабженец", Department = "тыл" },
  } } }
MB.HandleAction(p1, { op = "fac_query" })
local fa = netlog(function(e) return e.msg == "GRM_Mob_Data" and e.f[1] == "fac" and e.sentTo == p1 end)
local fdata = fa[#fa] and fa[#fa].f[2].data or {}
ok(fdata.name == "Люди горыныча" and fdata.total == 3, "фракция: 3 члена")
ok(fdata.online == 2, "фракция: 2 онлайн")
ok(fdata.rows[1].online == true, "сортировка: онлайн сначала")
local leadRow = nil
for _, r in ipairs(fdata.rows) do if r.leader then leadRow = r end end
ok(leadRow ~= nil and leadRow.role == "атаман", "лидер помечен")
-- у p3 старшая трубка, но фракции нет
GRM.Inventory.AddItem(p3, "mobile_tinkle", 1)
MB.HandleAction(p3, { op = "fac_query" })
local fa3 = netlog(function(e) return e.msg == "GRM_Mob_Data" and e.f[1] == "fac" and e.sentTo == p3 end)
ok(#fa3 >= 1 and fa3[#fa3].f[2].data == nil, "смартфон без фракции — пустые данные")

-- ══ 9. Регресс Код 88.1 «чат закрыт» ════════════════════════════════════
P("== 9. Звонки-призраки (репорт «чат закрыт») ==")
-- 9а. ring timeout: никто не взял трубку
clearLogs()
MB.Dial(p1, "1234")
TT = TT + 40
H.timers["GRM_Phone_CallThink"]()
ok(table.Count(PH.Calls) == 0 and line:GetLineState() == "idle", "ring-timeout гасит непринятый вызов")
-- 9б. собеседник ОТКЛЮЧИЛСЯ посреди разговора
TT = CurTime() + 1
MB.Dial(p1, "1234")
PH.Answer(p2, phoneB)
ok(table.Count(PH.Calls) == 1, "звонок поднят (9б)")
clearLogs()
delPlayer(p2)
fire("PlayerDisconnected", p2)
ok(table.Count(PH.Calls) == 0, "дисконнект стороны гасит звонок")
ok(line:GetLineState() == "idle" and phoneB.__dt.LineState == "idle", "обе линии вернулись в idle")
ok(hasInfo(p1, "отключился"), "оставшаяся сторона уведомлена")
-- важное: после смерти звонка чат p1 НЕ глушится
ok(H.hooks["PlayerSay"]["GRM_Phone_LineTextChat"](p1, "алло?") == nil, "чат освободился после конца звонка")
-- 9в. обе трубки брошены → abandoned через 3с
p2 = addPlayer(mkPly(2, 500, false))
local phA = ents.Create("grm_phone")
phA:SetPos(V(300, 0, 0))
phA.__dt.PhoneNumber = "1111" phA.__dt.DisplayName = "Офис А" phA.__dt.ExchangeID = "main"
local p6 = addPlayer(mkPly(6, 300, false))
GRM.Phone.Dial(p6, phA, "1234")
PH.Answer(p2, phoneB)
ok(table.Count(PH.Calls) == 1, "звонок Город↔Город поднят (9в)")
p6:SetPos(V(2300, 0, 0))
p2:SetPos(V(2500, 0, 0))
TT = CurTime() + 1
H.timers["GRM_Phone_CallThink"]() -- фиксирует aloneSince
ok(table.Count(PH.Calls) == 1, "первые 3с звонок ещё жив (grace)")
TT = CurTime() + 5
H.timers["GRM_Phone_CallThink"]()
ok(table.Count(PH.Calls) == 0, "брошенный звонок завершён (abandoned)")
ok(phA.__dt.LineState == "idle" and phoneB.__dt.LineState == "idle", "линии очищены")
-- 9г. телефон собеседника УДАЛЁН посреди разговора
MB.Dial(p1, "1234")
PH.Answer(p2, phoneB)
ok(table.Count(PH.Calls) == 1, "звонок поднят (9г)")
clearLogs()
phoneB:Remove()
H.timers["GRM_Phone_CallThink"]()
ok(table.Count(PH.Calls) == 0, "звонок гаснет при удалении энтити")
ok(line:GetLineState() == "idle", "выжившая линия НЕ зависла в call")
ok(hasInfo(p1, "разъединена"), "уведомление о разрыве")
-- 9д. самолечение застрявшей линии (не должно остаться путей к «вечной занятости»)
local phC = ents.Create("grm_phone")
phC:SetPos(V(300, 0, 0))
phC.__dt.PhoneNumber = "7777" phC.__dt.ExchangeID = "main"
phC.__dt.LineState = "call" phC.__dt.CallID = 424242
H.timers["GRM_Phone_CallThink"]()
ok(phC.__dt.LineState == "idle" and phC.__dt.CallID == 0, "застрявшая линия самолечится в idle")

-- ══ 10. RP chat: молчание локального чата стало видимым ════════════════
P("== 10. Подсказка «никто не слышит» ==")
local p7 = addPlayer(mkPly(7, 5000, false))
local rp = H.hooks["PlayerSay"]["GRM_RPChat_PlayerSay"]
clearLogs()
ok(rp(p7, "/grm_arrest_admin", false) == nil, "чужая slash-команда проходит дальше по PlayerSay")
ok(rp(p7, "!grm_persistence", false) == nil, "чужая bang-команда проходит дальше по PlayerSay")
TT = CurTime() + 10
ok(rp(p7, "кто-нибудь тут есть?", false) == "", "обычный текст всеяден: RP-chat забирает")
local hintHits = netlog(function(e)
  if e.msg ~= "GRM_RPChat_Msg" or e.sentTo ~= p7 then return false end
  for _, f in ipairs(e.f) do
    if isstring(f) and string.find(f, "никто не слышит", 1, true) then return true end
  end
  return false
end)
ok(#hintHits == 1, "отправитель видит «рядом никого нет» вместо молчания")
-- троттл: повтор в пределах 8с не спамит
TT = CurTime() + 2
rp(p7, "ау?", false)
local hintHits2 = netlog(function(e)
  if e.msg ~= "GRM_RPChat_Msg" or e.sentTo ~= p7 then return false end
  for _, f in ipairs(e.f) do
    if isstring(f) and string.find(f, "никто не слышит", 1, true) then return true end
  end
  return false
end)
ok(#hintHits2 == 1, "троттл: повторная подсказка не летит")
-- рядом появился человек → подсказка не нужна
local p8 = addPlayer(mkPly(8, 5010, false))
TT = CurTime() + 10
rp(p7, "теперь другой вопрос", false)
local hintHits3 = netlog(function(e)
  if e.msg ~= "GRM_RPChat_Msg" or e.sentTo ~= p7 then return false end
  for _, f in ipairs(e.f) do
    if isstring(f) and string.find(f, "никто не слышит", 1, true) then return true end
  end
  return false
end)
ok(#hintHits3 == 1, "при слушателе рядом подсказки нет")
ok(#netlog(function(e) return e.msg == "GRM_RPChat_Msg" and e.sentTo == p8 end) >= 1, "рядом стоящий получил сообщение")

-- ══ 11. Магазин: покупка телефонов в инвентарь ═════════════════════════
P("== 11. Телефонный магазин (invItem) ==")
local cat = GRM.Phone.Shop and GRM.Phone.Shop.Catalog or nil
ok(istable(cat), "каталог магазина на месте")
ok(cat ~= nil and cat.mobile_crappy ~= nil and cat.mobile_whiz_gold ~= nil, "в каталоге есть мобильные товары")
ok(cat.mobile_tinkle.invItem == "mobile_tinkle", "invItem дошёл через normalize")
ok(cat.mobile_whiz_gold.price == 14000, "цены соответствуют тирам")
-- слияние с существующим сохранённым каталогом (без мобильных) — самозалечивание
JSON_HOLD = { my_custom = { id = "my_custom", name = "Чужой проп", price = 1, class = "prop_physics", model = "" } }
GRM.Phone.Shop.LoadCatalog()
cat = GRM.Phone.Shop.Catalog
ok(cat.my_custom ~= nil, "чужой товар из старого каталога сохранился")
ok(cat.mobile_badger ~= nil and cat.mobile_badger.invItem == "mobile_badger", "мобильные домержены в старый каталог")
local p9 = addPlayer(mkPly(9, 0, true))
WALLET[p9:SteamID64()] = 20000
clearLogs()
-- покупка доступа не нужна: мобильный покупается сразу
H.seq = { "mobile_badger" }
H.netrecv["GRM_PhoneShop_Spawn"](0, p9)
ok(GRM.Inventory.CountItem(p9, "mobile_badger") == 1, "трубка попала в инвентарь")
ok(GRM.GetBalance(p9) == 20000 - 1800, "деньги списаны (1800)")
ok(hasNotif(p9, "Телефон в инвентаре"), "уведомление об успехе")
ok(#ents.FindByClass("grm_mobile_line") >= 0 and table.Count(GRM.Phone.Shop.Owned or {}) == 0, "мирового спавна/ownership нет")
-- второй такой же — можно, третий — нет (maxOwned 2)
H.seq = { "mobile_badger" }
H.netrecv["GRM_PhoneShop_Spawn"](0, p9)
H.seq = { "mobile_badger" }
H.netrecv["GRM_PhoneShop_Spawn"](0, p9)
ok(GRM.Inventory.CountItem(p9, "mobile_badger") == 2, "вторая трубка куплена")
ok(hasNotif(p9, "максимум таких телефонов"), "третья — отказ по лимиту")
-- не хватает денег
WALLET[p9:SteamID64()] = 100
H.seq = { "mobile_whiz_gold" }
H.netrecv["GRM_PhoneShop_Spawn"](0, p9)
ok(hasNotif(p9, "Недостаточно средств"), "отказ при нехватке денег")
ok(GRM.Inventory.CountItem(p9, "mobile_whiz_gold") == 0, "предмет не выдан")
-- доступная кнопка «Купить доступ» для invItem отключена
H.seq = { "mobile_tinkle" }
H.netrecv["GRM_PhoneShop_BuyAccess"](0, p9)
ok(hasNotif(p9, "покупается сразу"), "«Купить доступ» для мобильного отклонён с пояснением")
-- обычный товар по-прежнему требует доступ (каталог сбрасываем к дефолтному после мердж-теста)
FILES["grm_phone/shop_catalog.json"] = nil
JSON_HOLD = {}
GRM.Phone.Shop.LoadCatalog()
clearLogs()
WALLET[p9:SteamID64()] = 100000
H.seq = { "phone" }
H.netrecv["GRM_PhoneShop_Spawn"](0, p9)
ok(hasNotif(p9, "купите доступ"), "стационарный товар: старая модель доступа не сломана")

-- ══ 13. Код 88.3 — регресс живых багов (находка 105) ═══════════════════
P("== 13. Код 88.3: регресс живых багов ==")

-- 13.1 Реальный init.lua линии в строгой песочнице: SetUseType(nil) = ошибка
-- (как в GMod), неизвестные глобалы запрещены — класс бага находки 105
-- (NO_USE не существует в GLua → Initialize умирал → LineState="" → «линия занята»).
local srcEnt = assert(io.open("lua/entities/grm_mobile_line/init.lua", "rb")):read("*a")
local dt105 = { ExchangeID = "", LineState = "" }
local calls105 = {}
local ENT105 = {}
ENT105.GetExchangeID = function() return dt105.ExchangeID end
ENT105.SetExchangeID = function(_, v) dt105.ExchangeID = v end
ENT105.GetLineState = function() return dt105.LineState end
ENT105.SetLineState = function(_, v) dt105.LineState = v end
ENT105.SetMoveType = function(_, v) calls105.movetype = v end
ENT105.SetSolid = function(_, v) calls105.solid = v end
ENT105.SetNoDraw = function(_, v) calls105.nodraw = v end
ENT105.SetUseType = function(_, v)
  assert(type(v) == "number", "bad argument #1 to 'SetUseType' (number expected, got nil)")
  calls105.usetype = v
end
ENT105.NetworkVar = function() end
local env105 = {
  ENT = ENT105, AddCSLuaFile = function() end, include = function() end,
  print = print, type = type, tostring = tostring, pairs = pairs, ipairs = ipairs,
  SIMPLE_USE = 0, MOVETYPE_NONE = 0, SOLID_NONE = 1,
}
setmetatable(env105, { __index = function(_, k) error("unknown global in init.lua: " .. tostring(k), 2) end })
local ch105, chErr105 = loadstring(srcEnt, "init.lua")
ok(ch105 ~= nil, "init.lua парсится: " .. tostring(chErr105))
if ch105 then
  setfenv(ch105, env105)
  local okRun105, runErr105 = pcall(ch105)
  ok(okRun105, "init.lua выполняется: " .. tostring(runErr105))
  local okInit105, initErr105 = pcall(function() ENT105:Initialize() end)
  ok(okInit105 and dt105.LineState == "idle" and dt105.ExchangeID == "cell",
     "Initialize: LineState=idle, ExchangeID=cell (" .. tostring(initErr105) .. ")")
  ok(calls105.usetype == 0, "SetUseType получил ЧИСЛО (SIMPLE_USE), не nil")
end

-- 13.2 Флаг «UI открыт»: open/ping/close/протух + автообновление данных
clearLogs()
MB.HandleAction(p1, { op = "open" })
ok(tonumber(p1._grmMobUI) ~= nil, "op=open поставил серверный флаг стойки")
local ts0 = p1._grmMobUI
TT = TT + 1
MB.HandleAction(p1, { op = "ping" })
ok(p1._grmMobUI ~= nil and p1._grmMobUI > ts0, "op=ping освежает флаг")
clearLogs()
p1._grmMobDataTs = nil
H.timers["GRM_Mob_Think"]()
local pushed105 = false
for _, e in ipairs(H.netlog) do
  if e.msg == "GRM_Mob_Data" and e.f[1] == "contacts" then pushed105 = true end
end
ok(pushed105, "открытый UI: автообновление contacts в тикере")
ok(tonumber(p1._grmMobDataTs) ~= nil, "метка автообновления выставлена")
MB.HandleAction(p1, { op = "close" })
ok(p1._grmMobUI == nil, "op=close снимает флаг")
MB.HandleAction(p1, { op = "open" })
TT = TT + 5
H.timers["GRM_Mob_Think"]()
ok(p1._grmMobUI == nil, "протухший флаг (>3с без пинга) снят тикером")

-- 13.3 Стойка: StartCommand обнуляет движение/кнопки при свежем флаге
local cleared = {}
local cmd105 = { ClearMovement = function() cleared.move = true end, ClearButtons = function() cleared.btn = true end }
MB.HandleAction(p1, { op = "open" })
fire("StartCommand", p1, cmd105)
ok(cleared.move == true and cleared.btn == true, "StartCommand: движение и кнопки обнулены в телефоне")
cleared = {}
MB.HandleAction(p1, { op = "close" })
fire("StartCommand", p1, cmd105)
ok(cleared.move == nil, "после close стойка не действует")
TT = TT + 2

-- 13.4 Самолечение пустого LineState (трупы старого бага на живой линии)
local l105 = MB.Lines[p1:SteamID64()]
ok(IsValid(l105), "линия p1 жива для теста самолечения")
if IsValid(l105) then
  l105:SetLineState("")
  H.timers["GRM_Mob_Think"]()
  ok(l105:GetLineState() == "idle", "пустой LineState вылечен в idle тикером")
end

-- ══ 12. Итог ═══════════════════════════════════════════════════════════
H.timers["GRM_Mob_Think"]()
H.timers["GRM_Phone_CallThink"]()
ok(true, "финальный прогон тикеров без ошибок")
-- итоговая сводка теперь включает секцию 13
P("")
if failed == 0 then
  P("PASS " .. tostring(checks) .. "/" .. tostring(checks) .. " — sim_mobile OK")
else
  P("FAIL " .. tostring(failed) .. "/" .. tostring(checks) .. " — sim_mobile")
  os.exit(1)
end
