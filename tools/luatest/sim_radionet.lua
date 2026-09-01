-- Симуляция сервера GMod для sh_grm_radionet.lua (Код 85)
-- Стенд доказывает: топологию сети, покрытие/качество, цепочки связи,
-- маршрутизацию голоса (эфир/громкая связь/мегафон), «радио-искажение»,
-- автоперсистентность и доступ к chat-командам БЕЗ GMod.
----------------------------------------------------------------------

string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local H = { hooks = {}, timers = {}, netlog = {}, concommands = {}, chatlog = {} }
_G._SIM = H
local realPrint = print
local function P(...) realPrint(...) end

function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end

-- вектора --------------------------------------------------------------
local VMT = {}
VMT.__index = function(self, k)
  if k == "DistToSqr" then return function(s, o) local dx,dy,dz = s.x-o.x, s.y-o.y, s.z-o.z return dx*dx+dy*dy+dz*dz end end
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
  local e = { __class = class, __pos = V(x, y, z), __nw = {}, __idx = REG.nextIdx, __ang = Angle(0,0,0), __snd = {} }
  REG.nextIdx = REG.nextIdx + 1
  local mt
  mt = { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, p) self.__pos = p end end
    if k == "GetAngles" then return function() return self.__ang end end
    if k == "SetAngles" then return function(_, a) self.__ang = a end end
    if k == "GetClass" then return function() return self.__class end end
    if k == "EntIndex" then return function() return self.__idx end end
    local nwget = k:match("^GetNW(%w+)$")
    if nwget then return function(_, key, def) local v = self.__nw[key] if v == nil then return def end return v end end
    local nwset = k:match("^SetNW(%w+)$")
    if nwset then return function(_, key, val) self.__nw[key] = val end end
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

ents = { FindByClass = function(c) return REG.byClass[c] or {} end,
         Create = function(c) return mkEnt(c, 0, 0, 0) end }
Entity = function(i) return REG.byIdx[i] end

-- игроки -----------------------------------------------------------------
local function mkPly(id, x, isSAdmin)
  local p = { __pos = V(x, 0, 0), __idx = id, __sa = isSAdmin and true or false, __chat = {} }
  p = setmetatable(p, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, v) self.__pos = v end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "IsSuperAdmin" then return function() return self.__sa end end
    if k == "SteamID" then return function() return "STEAM_0:1:" .. tostring(self.__idx) end end
    if k == "SteamID64" then return function() return "76561198000000" .. tostring(100 + self.__idx) end end
    if k == "PrintMessage" then return function(_, _, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) self.__chat[#self.__chat + 1] = tostring(txt) end end
    if k == "GetShootPos" then return function() return self.__pos end end
    if k == "GetAimVector" then return function() return V(1, 0, 0) end end
    if k == "Nick" then return function() return "Игрок" .. tostring(self.__idx) end end
    if k == "GetNWString" then return function() return "" end end
    return nil
  end })
  return p
end

-- окружение GMod ---------------------------------------------------------
local FILES = {}
local JSON_HOLD = nil
util = {
  AddNetworkString = function() end,
  JSONToTable = function(t, a, b) return JSON_HOLD end,
  TableToJSON = function(t) JSON_HOLD = t return "TBL" end,
  TraceLine = function(td) return H.trace end,
}
file = { Read = function(p) return FILES[p] end, Write = function(p, d) FILES[p] = d end,
         Exists = function(p) return FILES[p] ~= nil end, IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function() end }
timer = { Create = function(name, d, r, fn) H.timers[name] = fn end,
          Simple = function(_, fn) fn() end }
player = { GetAll = function() return H.players or {} end }
game = { GetMap = function() return "gm_simtown" end }
net = { Start = function(m) H.netlog.cur = { msg = m, f = {} } end,
        WriteUInt = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
        WriteString = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
        WriteBool = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v and "T" or "F" end,
        Broadcast = function() H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end,
        WriteTable = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
        Send = function(ply) if H.netlog.cur then H.netlog.cur.sentTo = ply H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
net.ReadUInt = function() return tonumber(table.remove(H.seq or {}, 1)) or 0 end
net.ReadString = function() return tostring(table.remove(H.seq or {}, 1) or "") end
net.ReadTable = function() local v = table.remove(H.seq or {}, 1) return istable(v) and v or {} end
H.netrecv = H.netrecv or {}
H.seq = {}
concommand = { Add = function() end }
HUD_PRINTTALK = 3
TT = 0
CurTime = function() return TT end
AddCSLuaFile = function() end

-- грузим модуль ----------------------------------------------------------
SERVER = true CLIENT = false
-- Код 99: модуль регистрирует предмет модулятора в инвентарь при загрузке —
-- стаб инвентаря нужен до dofile; per-player слоты через ply.__inv
H.regItems = {}
GRM = GRM or {}
GRM.Inventory = {
  RegisterItem = function(id, data) H.regItems[id] = data end,
  GetPlayerInv = function(ply)
    if not ply then return nil end
    ply.__inv = ply.__inv or { slots = {} }
    return ply.__inv
  end,
  CountItem = function(ply, id)
    local n = 0
    for _, s in pairs(((ply or {}).__inv or {}).slots or {}) do if s.id == id then n = n + (s.count or 1) end end
    return n
  end,
}
dofile("lua/autorun/sh_grm_radionet.lua")
local RN = GRM.RadioNet
RN.Recompute()

-- фреймворк ---------------------------------------------------------------
local checks, failed = 0, 0
local function ok(cond, name)
  checks = checks + 1
  if cond then P("  ok " .. tostring(checks) .. ". " .. name)
  else failed = failed + 1 P("  FAIL " .. tostring(checks) .. ". " .. name) end
end
local function approx(a, b, eps) return math.abs(a - b) < (eps or 0.01) end

P("== 1. Пустой мир: сети нет ==")
ok(#RN._coverage == 0, "кругов покрытия нет")
ok(RN.QualityAt(V(0, 0, 0)) == 0, "качество в точке = 0")
ok(not RN.CoveredAt(V(0, 0, 0)), "покрытия нет")

P("== 2. Одна активная стойка = слабый репитер ==")
local rack = mkEnt("grm_server_rack", 0, 0, 0)
rack:SetNWBool("GRM_RN_On", true)
RN.Recompute()
ok(#RN._activeRacks == 1, "1 активная стойка")
ok(#RN._coverage == 1, "1 круг покрытия (стойка)")
ok(RN.QualityAt(V(0, 0, 0)) == 1, "в центре качество 1.0")
ok(approx(RN.QualityAt(V(1000, 0, 0)), 1 - (1000 - 660) / 540, 0.01), "на 1000 юн качество ~0.37")
ok(RN.CoveredAt(V(1000, 0, 0)), "1000 юн — покрыто")
ok(not RN.CoveredAt(V(1200, 0, 0)), "на краю (1200) — не покрыто")

P("== 3. Антенна без стойки рядом — мертва ==")
local ant = mkEnt("grm_antenna", 3000, 0, 0)
RN.Recompute()
ok(RN._antsTotal == 1 and RN._antsLinked == 0, "антенна есть, связи нет")
ok(RN.QualityAt(V(3000, 0, 0)) == 0, "вокруг глухой антенны сигнала нет")

P("== 4. Стойка №2 активирует антенну — усиление ==")
local rack2 = mkEnt("grm_server_rack", 3500, 0, 0)
rack2:SetNWBool("GRM_RN_On", true)
RN.Recompute()
ok(RN._antsLinked == 1, "антенна связана")
ok(RN.CoveredAt(V(5500, 0, 0)), "зона усиления покрыта (5500)")
ok(approx(RN.QualityAt(V(5500, 0, 0)), 1 - (2500 - 1760) / 1440, 0.01), "качество 5500 ~0.49")
ok(not RN.CoveredAt(V(6000, 0, 0)), "у самого края (6000) — уже не берёт")

P("== 5. Стойка выключена → антенна глохнет ==")
rack2:SetNWBool("GRM_RN_On", false)
RN.Recompute()
ok(RN._antsLinked == 0, "связь антенны пропала")
ok(not RN.CoveredAt(V(5500, 0, 0)), "усиленная зона обесточена")
rack2:SetNWBool("GRM_RN_On", true)
RN.Recompute()

P("== 6. Цепочка микрофон → передатчик → стойка ==")
local st = mkEnt("grm_radio_station", 500, 0, 0)       -- рядом со стойкой
local mic = mkEnt("grm_broadcast_mic", 900, 0, 0)      -- рядом с передатчиком
RN.Recompute()
ok(RN.MicLink(mic) == 2, "микрофон в сети через передатчик")
local micFar = mkEnt("grm_broadcast_mic", 9000, 0, 0)
ok(RN.MicLink(micFar) == 0, "голый микрофон — link 0")
rack:SetNWBool("GRM_RN_On", false)
RN.Recompute()
ok(RN.MicLink(mic) == 1, "стойка погашена → передатчик вне сети (link 1)")
rack:SetNWBool("GRM_RN_On", true)
RN.Recompute()
ok(RN.MicLink(mic) == 2, "стойка вернулась → link 2")

P("== 7. Громкоговорители: активность от сети ==")
local spk1 = mkEnt("grm_loudspeaker", 600, 0, 0)   -- у стойки
local spk2 = mkEnt("grm_loudspeaker", 5500, 0, 0)  -- в зоне антенны
local spk3 = mkEnt("grm_loudspeaker", 20000, 0, 0) -- в глуши
RN.Recompute()
ok(RN.SpeakerActive(spk1), "громкоговоритель у стойки — в сети")
ok(RN.SpeakerActive(spk2), "громкоговоритель в покрытии антенны — в сети")
ok(not RN.SpeakerActive(spk3), "громкоговоритель в глуши — мёртв")

P("== 8. Гейт ручной рации ==")
local sA = mkPly(101, 0, false)       -- в покрытии стойки
local sB = mkPly(102, 5500, false)    -- в покрытии антенны (далеко!)
local sC = mkPly(103, 20000, false)   -- глушь
local sD = mkPly(104, 20800, false)   -- глушь, 800 юн от sC
H.players = { sA, sB, sC, sD }
ok(RN.RadioPairOK(sA, sB), "оба в сети на разных концах — частота ловится")
ok(not RN.RadioPairOK(sA, sC), "второй в глуши — связи нет")
ok(RN.RadioPairOK(sC, sD), "оба в глуши, но в 800 юн — прямая дальность")

P("== 9. Маршрут голоса: радиоэфир ==")
local speaker = mkPly(201, 900, false)
speaker._grmBCMic = mic
mic.BCLive = true mic.BCSpeaker = speaker
mic:SetNWBool("GRM_BC_PA", false)
local radio = mkEnt("grm_radio", 5000, 0, 0)
radio:SetNWBool("GRM_BC_On", true)
radio:SetNWInt("GRM_BC_Mic", mic:EntIndex())
local lst1 = mkPly(202, 5100, false)  -- у приёмника (в покрытии антенны)
local lst2 = mkPly(203, 100000, false) -- приёмников рядом нет
local lst3 = mkPly(204, 1100, false)   -- рядом с ведущим (200 юн)
H.players = { sA, sB, sC, sD, speaker, lst1, lst2, lst3 }
RN.Recompute()
TT = 0
local c1, h1 = RN.VoiceRoute(lst1, speaker)
ok(c1 == true and h1 == false, "у приёмника в покрытии — эфир слышно (не 3D)")
local c2 = RN.VoiceRoute(lst2, speaker)
ok(c2 == false, "в глуши без приёмника — заглушён")
local c3 = RN.VoiceRoute(lst3, speaker)
ok(c3 == nil, "рядом с ведущим — решает локальный голос (nil)")
radio:SetPos(V(50000, 0, 0))
radio:SetNWBool("GRM_BC_On", true)
local c4 = RN.VoiceRoute(lst1, speaker)
ok(c4 == false, "приёмник уехал из покрытия → слушатель глух")
radio:SetPos(V(5000, 0, 0))

P("== 10. Маршрут: микрофон вне сети не душит локальный голос ==")
speaker._grmBCMic = micFar
micFar.BCLive = true micFar.BCSpeaker = speaker
micFar:SetNWBool("GRM_BC_PA", false)
local c5 = RN.VoiceRoute(lst2, speaker)
ok(c5 == nil, "микрофон голый — VoiceRoute не вмешивается (nil)")

P("== 11. Маршрут: ГРОМКАЯ СВЯЗЬ через громкоговорители ==")
speaker._grmBCMic = mic
mic:SetNWBool("GRM_BC_PA", true)
local lstPA = mkPly(205, 1500, false) -- 500 юн от громкоговорителя(1000)…
H.players = { speaker, lstPA, lst2 }
local spk4 = mkEnt("grm_loudspeaker", 1000, 0, 0)  -- в покрытии стойки
RN.Recompute()
RN.PAQuality = 1 -- детерминизм стенда (нет выпадений)
local c6, h6 = RN.VoiceRoute(lstPA, speaker)
ok(c6 == true and h6 == false, "рядом с сетевым громкоговорителем — голос усилен (не 3D)")
ok(speaker._rnTxSeen ~= nil and speaker._rnFx == "pa", "штамп передачи «pa» выставлен")
spk4:SetPos(V(50000, 0, 0))
local c7 = RN.VoiceRoute(lstPA, speaker)
ok(c7 == false, "громкоговорителей в сети нет — громкая связь заглохла")
spk4:Remove()

P("== 12. Маршрут: мегафон ==")
local ms = mkPly(206, 0, false)
ms._rnMegaOn = true
local mNear = mkPly(207, 1500, false)
local mFar = mkPly(208, 2000, false)
local savedQ = RN.MegaQuality
RN.MegaQuality = 1 -- детерминизм: без выпадений
local c8, h8 = RN.VoiceRoute(mNear, ms)
ok(c8 == true and h8 == false, "мегафон: 1500 юн — слышно усиленно")
local c9 = RN.VoiceRoute(mFar, ms)
ok(c9 == nil, "мегафон: 2000 юн — вне досягаемости (nil)")
ms._rnMegaOn = false
local c10 = RN.VoiceRoute(mNear, ms)
ok(c10 == nil, "мегафон выключен — обычный голос")
RN.MegaQuality = savedQ

P("== 13. «Радио-искажение»: выпадения детерминированы и ∝ качеству ==")
local drops, total = 0, 200
for s = 1, total do
  TT = s * 0.2
  if RN.Drop(77, 0.5) then drops = drops + 1 end
end
ok(drops >= 60 and drops <= 140, "q=0.5 → выпадений " .. drops .. "/200 (≈50%)")
TT = 42.0
local d1 = RN.Drop(5, 0.6)
local d2 = RN.Drop(5, 0.6)
ok(d1 == d2, "тот же срез времени — то же решение")
ok(RN.Drop(5, 1.0) == false, "q=1.0 — никогда не рвёт")
ok(RN.Drop(5, 0) == true, "q=0 — всегда обрыв")

P("== 14. FX-рассылка: щелчки/треск ==")
TT = 100
speaker._rnTxSeen = TT speaker._rnFx = "radio"
H.netlog = {}
H.players = { speaker }
H.timers["GRM_RN_FxWatch"]()
ok(#H.netlog >= 1 and H.netlog[1].msg == "GRM_RN_FX" and H.netlog[1].f[3] == "T", "старт передачи → net GRM_RN_FX (on)")
TT = 103
H.netlog = {}
H.timers["GRM_RN_FxWatch"]()
ok(#H.netlog >= 1 and H.netlog[1].f[3] == "F", "замолчал → net GRM_RN_FX (off)")

P("== 15. Чат-команды и доступ ==")
local admin = mkPly(300, 0, true)
local user = mkPly(301, 0, false)
H.players = { admin, user }
H.trace = { Hit = true, HitPos = V(2400, 0, 0), HitNormal = V(0, 0, 1), Entity = nil }
local n0 = #REG.byClass["grm_server_rack"]
ok(RN.HandleChat(user, "/rack_add") == true and #REG.byClass["grm_server_rack"] == n0, "обычный игрок не ставит стойки (команда поглощена, энтити нет)")
ok(RN.HandleChat(admin, "/rack_add") == true and #REG.byClass["grm_server_rack"] == n0 + 1, "суперадмин поставил стойку (/rack_add)")
ok(RN.HandleChat(user, "/rn_status") == true, "/rn_status у игрока — поглощён")
ok(RN.HandleChat(admin, "/rn_status") == true, "/rn_status у суперадмина — поглощён")
local foundStatus = false
for _, m in ipairs(H.chatlog) do if m:find("диагностика") then foundStatus = true break end end
ok(foundStatus, "диагностика напечатана в чат")
ok(RN.HandleChat(admin, "/rn_unknown") == false, "чужие команды не трогаем")

P("== 16. Автоперсистентность (рестарт-эквивалент) ==")
local cnt0 = table.Count(RN.Persist or {})
ok(cnt0 >= 1, "записи персиста живут (" .. tostring(cnt0) .. ")")
local racksBefore = #REG.byClass["grm_server_rack"]
H.hooks["InitPostEntity"]["GRM_RN_Restore"]()
ok(#REG.byClass["grm_server_rack"] == racksBefore, "антидубль: при работающих стойках восстановление ничего не создало")
-- сносим именно ПЕРСИСТНУЮ стойку (поставленную /rack_add на 2400)
local persistedRack = nil
for _, e in ipairs(REG.byClass["grm_server_rack"]) do
  if e:GetPos().x == 2400 then persistedRack = e break end
end
ok(persistedRack ~= nil, "персистная стойка найдена в мире")
persistedRack:Remove()
H.hooks["InitPostEntity"]["GRM_RN_Restore"]()
ok(#REG.byClass["grm_server_rack"] == racksBefore, "после потери стойки восстановление её вернуло")
local restoredRack = nil
for _, e in ipairs(REG.byClass["grm_server_rack"]) do
  if e:GetPos().x == 2400 and e:GetNWBool("GRM_RN_On", false) then restoredRack = e break end
end
ok(restoredRack ~= nil, "воскрешенная стойка стоит на старом месте и включена")

P("== 17. NW-зеркала для 3D2D ==")
RN.Recompute()
ok(mic:GetNWInt("GRM_RN_Link", -9) == 2, "микрофон: NW link = 2")
ok(st:GetNWBool("GRM_RN_Online", false) == true, "передатчик: NW online")
ok(ant:GetNWBool("GRM_RN_Linked", false) == true, "антенна: NW linked")

P("== 18. NetSys (Код 87): реестр позывных ==")
RN.Recompute()
local micId = mic:GetNWString("GRM_NetID", "")
ok(micId:match("^MIC%-%d%d%d$") ~= nil, "микрофон получил позывной " .. micId)
local antId = ant:GetNWString("GRM_NetID", "")
ok(antId:match("^ANT%-%d%d%d$") ~= nil, "антенна получила позывной " .. antId)
local spkId1 = spk1:GetNWString("GRM_NetID", "")
ok(spkId1:match("^SPK%-%d%d%d$") ~= nil, "громкоговоритель: " .. spkId1)
local preCount = table.Count(RN.Sys.devices or {})
RN.Recompute()
ok(table.Count(RN.Sys.devices or {}) == preCount, "рестарт-рекомпьют не плодит записи (стабильные id)")
ok(mic:GetNWString("GRM_NetID", "") == micId, "позывной стабилен между пересчётами")
-- «воскрешение» записи по позиции после рестарта
local spkA = mkEnt("grm_loudspeaker", 600, 90001, 0)
RN.Recompute()
local spkAid = spkA:GetNWString("GRM_NetID", "")
ok(spkAid ~= "", "новый громкоговоритель зарегистрирован: " .. spkAid)
spkA:Remove()
local spkA2 = mkEnt("grm_loudspeaker", 600, 90001, 0)
RN.Recompute()
ok(spkA2:GetNWString("GRM_NetID", "") == spkAid, "после «рестарта» запись воскресла по позиции (тот же id)")

P("== 19. Точечное управление: пульт и выключатели ==")
-- своя активная стойка в тестовой «секции 90001» — пульту нужна живая сеть
local rack87 = mkEnt("grm_server_rack", 0, 90001, 0)
rack87:SetNWBool("GRM_RN_On", true)
RN.Recompute()
ok(rack87:GetNWString("GRM_NetID", ""):match("^RAX%-%d%d%d$") ~= nil, "стойка секции зарегистрирована")
local con = mkEnt("grm_net_console", 100, 90001, 0) -- у активной стойки (0,90001,0)
RN.Recompute()
ok(con:GetNWString("GRM_NetID", ""):match("^CON%-%d%d%d$") ~= nil, "пульт получил позывной")
ok(con:GetNWBool("GRM_RN_Online", false) == true, "пульт у активной стойки — в сети")
local conFar = mkEnt("grm_net_console", 90000, 90001, 0)
RN.Recompute()
ok(conFar:GetNWBool("GRM_RN_Online", false) == false, "пульт в глуши — вне сети")
-- разрешения/связь пульта
H.notifies = {}
GRM.Notify = function(ply, txt) H.notifies[#H.notifies + 1] = tostring(txt) end
local admin = mkPly(301, 0, true)
local guest = mkPly(302, 0, false)
H.players[#H.players + 1] = admin
H.players[#H.players + 1] = guest
local function netlogFind(msg)
  for i = #H.netlog, 1, -1 do if H.netlog[i].msg == msg then return H.netlog[i] end end
  return nil
end
RN.ConsoleOpen(guest, con)
ok(H.notifies[#H.notifies]:find("суперадмина") ~= nil, "гостю в пульт отказано (только суперадмин)")
RN.ConsoleOpen(admin, conFar)
ok(H.notifies[#H.notifies]:find("ВНЕ СЕТИ") ~= nil, "пульт без стойки рядом не открывается")
RN.ConsoleOpen(admin, con)
local dump1 = netlogFind("GRM_RN_NetOpen")
ok(dump1 ~= nil and istable(dump1.f) and istable(dump1.f[2]), "снапшот пульта отправлен админу")
local devIds = {}
for _, d in ipairs(dump1.f[2].devices or {}) do devIds[d.id] = d end
ok(devIds[micId] ~= nil and devIds[micId].kind == "mic", "в снапшоте микрофон идентифицирован " .. micId)
ok(devIds[spkAid] ~= nil and devIds[spkAid].alive == true, "в снапшоте живой громкоговоритель")
-- пеленг: дистанция от пульта (100,90001) до громкоговорителя (600,90001) = 500
ok(devIds[spkAid] ~= nil and devIds[spkAid].dist == 500, "пеленг: дистанция до SPK посчитана (500)")
-- операции пульта (seq: idx, op, таблица)
local function fireOp(ply, idx, op, tbl)
  H.seq = { idx, op, tbl or {} }
  H.netrecv["GRM_RN_NetOp"](0, ply)
end
fireOp(guest, con:EntIndex(), "toggle", { id = spkAid })
ok(RN.Sys.devices[spkAid].off ~= true, "операция пульта от гостя проигнорирована")
fireOp(admin, conFar:EntIndex(), "toggle", { id = spkAid })
ok(RN.Sys.devices[spkAid].off ~= true, "операция через пульт ВНЕ СЕТИ отклонена")
-- выключить громкоговоритель у стойки: spk1 (600,0,0) был активен
RN.Recompute()
ok(RN.SpeakerActive(spk1) == true, "до выключения громкоговоритель в сети")
fireOp(admin, con:EntIndex(), "toggle", { id = spkId1 })
ok(RN.Sys.devices[spkId1].off == true, "пульт пометил вывод ВЫКЛ")
RN.Recompute()
ok(RN.SpeakerActive(spk1) == false, "выключенный пультом громкоговоритель молчит (точечная настройка)")
fireOp(admin, con:EntIndex(), "toggle", { id = spkId1 })
RN.Recompute()
ok(RN.SpeakerActive(spk1) == true, "повторный toggle вернул громкоговоритель в эфир")
-- выключить АНТЕННУ: её круг покрытия схлопывается
local covBefore = #RN._coverage
fireOp(admin, con:EntIndex(), "toggle", { id = antId })
RN.Recompute()
ok(#RN._coverage == covBefore - 1, "антенна ВЫКЛ → её круг покрытия убран (взаимозависимость звеньев)")
ok(RN.CoveredAt(V(5500, 0, 0)) == false, "точка покрывалась только антенной — теперь глушь")
ok(RN.ReceiverOK(radio) == false, "приёмник в зоне той антенны — вне покрытия")
fireOp(admin, con:EntIndex(), "toggle", { id = antId })
RN.Recompute()
ok(RN.CoveredAt(V(5500, 0, 0)) == true, "антенна обратно ВКЛ → покрытие восстановлено")
-- пульт нельзя выключить сам у себя
local conId = con:GetNWString("GRM_NetID", "")
fireOp(admin, con:EntIndex(), "toggle", { id = conId })
ok(RN.Sys.devices[conId].off ~= true, "пульт сам себя не гасит")

P("== 20. Группы и нацеленный вывод ==")
fireOp(admin, con:EntIndex(), "assign", { id = spkId1, group = "Север", on = true })
ok(RN.DeviceInGroupForEnt(spk1, "Север") == true, "громкоговоритель включён в группу «Север»")
fireOp(admin, con:EntIndex(), "assign", { id = spkId1, group = "Север", on = false })
ok(RN.DeviceInGroupForEnt(spk1, "Север") == false, "громкоговоритель выведен из группы")
fireOp(admin, con:EntIndex(), "assign", { id = spkId1, group = "Север", on = true })
fireOp(admin, con:EntIndex(), "assign", { id = spkA2:GetNWString("GRM_NetID",""), group = "Север", on = true })
RN.ConsoleOpen(admin, con)
local dump2 = netlogFind("GRM_RN_NetOpen")
ok(dump2 ~= nil and #((dump2.f[2] or {}).groups or {}) >= 1, "группа видна в снапшоте пульта")
-- оповещение по группе (SendAlert вызывается с targetGroup)
H.alerts = {}
GRM.Broadcast = GRM.Broadcast or {}
GRM.Broadcast.SendAlert = function(name, text, global, srcPly, tgt)
  H.alerts[#H.alerts + 1] = { name = name, text = text, tgt = tgt }
  return true, "Оповещение передано"
end
fireOp(admin, con:EntIndex(), "alert", { target = "Север", text = "Внимание, Север!" })
ok(H.alerts[#H.alerts] ~= nil and H.alerts[#H.alerts].tgt == "Север", "/alert с пульта ушёл на конкретную группу")
fireOp(admin, con:EntIndex(), "alert", { target = "", text = "Внимание, город!" })
ok(H.alerts[#H.alerts] ~= nil and H.alerts[#H.alerts].tgt == nil, "/alert без группы = весь город (nil-группа)")
-- цель громкой связи микрофона
fireOp(admin, con:EntIndex(), "mic_target", { id = micId, group = "Север" })
ok(mic:GetNWString("GRM_RN_Target", "") == "Север", "микрофону назначена цель ГРОМКОЙ СВЯЗИ")
ok(RN.Sys.devices[micId].paTarget == "Север", "цель сохранилась в записи реестра")
-- голос ведущего: звучит только у громкоговорителей группы
mic.BCLive = true mic.BCSpeaker = ms
mic:SetNWBool("GRM_BC_PA", true)
RN.Drop = function() return false end -- маршрут без выпадений для чистого теста
ms._grmBCMic = mic
local paL1 = mkPly(401, 650, false)   -- у spk1 (600,0): в группе
local paL2 = mkPly(402, 5600, false)  -- у spk2 (5500,0): НЕ в группе
H.players[#H.players + 1] = paL1
H.players[#H.players + 1] = paL2
ok(RN.SpeakerActive(spk2) == true, "второй громкоговоритель в сети, но вне группы")
local hear1 = RN.VoiceRoute(paL1, ms)
local hear2 = RN.VoiceRoute(paL2, ms)
ok(hear1 == true, "слушатель у громкоговорителя группы слышит громкую связь")
ok(hear2 == false, "слушатель у громкоговорителя ВНЕ группы — тишина (нацеленность)")
fireOp(admin, con:EntIndex(), "mic_target", { id = micId, group = "" })
ok(mic:GetNWString("GRM_RN_Target", "") == "", "цель сброшена — снова весь город")
local hear2b = RN.VoiceRoute(paL2, ms)
ok(hear2b == true, "без цели громкая связь снова звучит везде")
mic:SetNWBool("GRM_BC_PA", false) mic.BCLive = false ms._grmBCMic = nil
-- удаление группы снимает принадлежности
fireOp(admin, con:EntIndex(), "group_del", { group = "Север" })
ok(RN.DeviceInGroupForEnt(spk1, "Север") == false, "group_del снял группу с устройств")
-- удаление записи-призрака
RN.Sys.devices["SPK-666"] = { id = "SPK-666", kind = "speaker", pos = { x = 1, y = 1, z = 1 }, off = false, groups = {} }
fireOp(admin, con:EntIndex(), "dev_del", { id = micId })
ok(RN.Sys.devices[micId] ~= nil, "живое устройство из реестта не выкинуть")
fireOp(admin, con:EntIndex(), "dev_del", { id = "SPK-666" })
ok(RN.Sys.devices["SPK-666"] == nil, "запись-призрак удалена пультом")

P("== 21. Журнал событий и пеленг передач ==")
local logBefore = #RN.Sys.log
local txp = mkPly(501, 1234, false)
txp._rnTxSeen = TT txp._rnFx = "radio"
H.players[#H.players + 1] = txp
H.timers["GRM_RN_FxWatch"]()
local lastE = RN.Sys.log[#RN.Sys.log]
ok(#RN.Sys.log > logBefore, "старт передачи записан в журнал")
ok(lastE ~= nil and lastE.kind == "tx_radio", "событие = эфир микрофона")
ok(lastE ~= nil and tostring(lastE.who):find("Игрок501") ~= nil, "в журнале кто передавал")
ok(lastE ~= nil and lastE.q >= 0 and lastE.q <= 100, "пеленг: качество канала в записи (q=" .. tostring(lastE and lastE.q) .. ")")
txp._rnTxSeen = nil
H.timers["GRM_RN_FxWatch"]()
ok(RN.Sys.log[#RN.Sys.log].kind == "tx_end", "окончание передачи тоже залогировано")
-- кап журнала
for i = 1, 400 do RN.LogEvent("test", "тест", "0", nil, "наполнение") end
ok(#RN.Sys.log == RN.LogCap, "журнал усечён до LogCap=" .. tostring(RN.LogCap))
-- /rn_log
H.chatlog = {}
ok(RN.HandleChat(admin, "/rn_log") == true, "/rn_log — команда принята")
local sawLog = false
for _, l in ipairs(H.chatlog) do if l:find("журнал") or l:find("tx_") then sawLog = true break end end
ok(sawLog, "/rn_log печатает последние события админу")
H.chatlog = {}
RN.HandleChat(guest, "/rn_log")
ok(#H.chatlog == 1 and H.chatlog[1]:find("суперадмина"), "гостю /rn_log закрыт")
-- очистка журнала пультом
fireOp(admin, con:EntIndex(), "log_clear")
ok(#RN.Sys.log == 0, "журнал очищен операцией пульта")

P("== 22. Автоперсист появился и у пульта ==")
H.trace = { Hit = true, HitPos = V(7700, 90001, 0), HitNormal = V(0, 0, 1) }
RN.HandleChat(admin, "/console_add")
ok(RN._restoring ~= true, "флаг восстановления не застрял")
local conAdded = nil
for _, e in ipairs(REG.byClass["grm_net_console"]) do
  if e:GetPos().x >= 7700 and e:GetPos().x <= 7705 then conAdded = e break end
end
ok(conAdded ~= nil, "/console_add поставил пульт по прицелу")
local conInPersist = false
for k, rec in pairs(RN.Persist or {}) do
  if rec.class == "grm_net_console" then conInPersist = true break end
end
ok(conInPersist, "пульт сохранён в автоперсистенте карты")

P("== 23. Код 88.4 — авто-свипер персистента (постановка любым способом) ==")
-- энтити, поставленная МИМО команд (Q-меню/дюп), сама уходит в персист
local sweepAnt = mkEnt("grm_antenna", 60000, 0, 0)
local function hasPersistAt(class, x)
  local want = class .. "|" .. string.format("%.0f_%.0f_%.0f", x, 0, 0)
  return RN.Persist[want] ~= nil, want
end
local hadBefore = hasPersistAt("grm_antenna", 60000)
ok(hadBefore == false, "новая антенна вне реестра (чистый старт проверки)")
RN._devSweep()
local inNow = hasPersistAt("grm_antenna", 60000)
ok(inNow, "свипер: антенна, поставленная мимо команд, попала в персист")
ok(sweepAnt._grmRNKey ~= nil, "свипер пометил энтити своим ключом")
-- переезд: ключ мигрирует на новую позицию, старой записи нет
local oldKey = sweepAnt._grmRNKey
sweepAnt:SetPos(V(61000, 0, 0))
RN._devSweep()
ok(RN.Persist[oldKey] == nil, "после переезда старый ключ удалён")
ok(hasPersistAt("grm_antenna", 61000), "после переезда новый ключ записан")
-- удаление живьём: запись выпадает (иначе воскрешала бы снятое)
sweepAnt:Remove()
RN._devSweep()
ok(hasPersistAt("grm_antenna", 61000) == false, "удалённая антенна выпала из персиста")
-- свипер не трогает чужие классы
local alien = mkEnt("prop_physics", 62000, 0, 0)
RN._devSweep()
local alienOk = true
for k, rec in pairs(RN.Persist or {}) do if rec.class == "prop_physics" then alienOk = false end end
ok(alienOk, "чужие классы свипер игнорирует")
alien:Remove()

P("== 24. Радиоканалы /freq /r (Код 98, находка 115) ==")
-- мир: (0,0,0) — покрытие стойки; (5500,0,0) — покрытие антенны;
-- (20000,0,0) и (20800,0,0) — глушь, между собой 800 юн (< 1500 прямой)
local u1 = mkPly(601, 0, false)
local u2 = mkPly(602, 5500, false)
local u3 = mkPly(603, 20000, false)
local u4 = mkPly(604, 20800, false)
local u5 = mkPly(605, 100, false)
H.players = { u1, u2, u3, u4, u5 }
local function lastChat(p, pat)
  for i = #p.__chat, 1, -1 do if p.__chat[i]:find(pat) then return p.__chat[i] end end
  return nil
end
-- Код 99: частоты требуют активный модулятор в инвентаре — выдаём всем пятерым
local function giveUnit(p, on)
  p.__inv = { slots = { [1] = { id = "radio_modulator", count = 1, data = { on = on == true } } } }
end
giveUnit(u1, true) giveUnit(u2, true) giveUnit(u3, true) giveUnit(u4, true) giveUnit(u5, true)
-- FreqKey: нормализация и отсечки
ok(RN.FreqKey("145") == "145.0", "FreqKey: «145» → «145.0»")
ok(RN.FreqKey("999.9") == "999.9", "FreqKey: верхняя граница 999.9 ок")
ok(RN.FreqKey("145.55") == nil, "FreqKey: шаг мельче 0.1 — отказ")
ok(RN.FreqKey("0.5") == nil and RN.FreqKey("1000") == nil and RN.FreqKey("abc") == nil, "FreqKey: вне диапазона/мусор — отказ")
-- /r без настроенной частоты
ok(RN.HandleChat(u1, "/r привет") == true, "/r поглощён даже без частоты")
ok(lastChat(u1, "не на частоте") ~= nil and RN.FreqOf(u1) == nil, "/r без частоты — подсказка, эфира нет")
-- невалидные частоты отвергаются (обработчик раньше отсутствовал — команды висели в чате)
ok(RN.HandleChat(u1, "/freq abc") == true and RN.FreqOf(u1) == nil, "/freq abc — отказ")
ok(RN.HandleChat(u1, "/freq 0.5") == true and RN.FreqOf(u1) == nil, "/freq 0.5 (ниже 1) — отказ")
ok(RN.HandleChat(u1, "/freq 1000") == true and RN.FreqOf(u1) == nil, "/freq 1000 (выше 999.9) — отказ")
ok(RN.HandleChat(u1, "/freq 145.55") == true and RN.FreqOf(u1) == nil, "/freq 145.55 (шаг 0.01) — отказ")
ok(lastChat(u1, "1–999.9") ~= nil, "отказ сопровождается подсказкой формата")
-- подключение (C-меню шлёт именно такое: /freq <число>)
ok(RN.HandleChat(u1, "/freq 145.5") == true and RN.FreqOf(u1) == "145.5", "/freq 145.5 — рация настроена")
ok(lastChat(u1, "на частоте 145.5") ~= nil, "подтверждение подключения в чат")
ok(RN.HandleChat(u2, "/FREQ 200") == true and RN.FreqOf(u2) == "200.0", "регистр команды не важен: /FREQ 200 → 200.0")
RN.HandleChat(u2, "/freq 145.5")
RN.HandleChat(u3, "/freq 145.5")
RN.HandleChat(u4, "/freq 145.5")
ok(RN.FreqOf(u2) == "145.5" and RN.FreqOf(u3) == "145.5" and RN.FreqOf(u4) == "145.5", "четверо на одной частоте 145.5")
ok(RN.HandleChat(u1, "/freq") == true and lastChat(u1, "145.5 МГц") ~= nil, "голый /freq — напоминает текущую частоту")
-- передача: оба в сети (разные круги покрытия) — чистый текст
TT = 500
local n2before, n3before, n4before = #u2.__chat, #u3.__chat, #u4.__chat
ok(RN.HandleChat(u1, "/r Operaciya nachalas") == true, "/r ушёл в эфир (отправитель в сети)")
ok(lastChat(u1, "%[Рация 145.5%] Игрок601: Operaciya nachalas") ~= nil, "отправителю — собственное эхо")
ok(#u2.__chat == n2before + 1 and u2.__chat[#u2.__chat] == "[Рация 145.5] Игрок601: Operaciya nachalas", "второй абонент в сети — текст чистый, без помех")
ok(#u3.__chat == n3before, "абонент в глуши (вне сети и далеко) — ничего не получил")
ok(#u4.__chat == n4before, "второй «глухой» тоже мимо")
ok(lastChat(u1, "тишина") == nil, "есть слышащие — подсказки про тишину нет")
-- передача по прямой дальности: помехи ∝ расстоянию
TT = 502
RN.HandleChat(u3, "/r Ky ky svyaz proveryaem")
local m4 = lastChat(u4, "%[Рация 145.5%] Игрок603:")
ok(m4 ~= nil, "прямая дальность 800 юн — доставлено")
local b4 = m4 and m4:match("Игрок603: (.+)$")
ok(b4 ~= nil and b4 ~= "Ky ky svyaz proveryaem" and b4:find("%*") ~= nil, "текст с помехами: часть символов съело шипение")
ok(b4 ~= nil and #b4 == #"Ky ky svyaz proveryaem", "длина сообщения сохранена")
ok(lastChat(u3, "%[Рация 145.5%] Игрок603: Ky ky svyaz proveryaem") ~= nil, "у отправителя — чистое эхо")
ok(lastChat(u1, "Игрок603") == nil and lastChat(u2, "Игрок603") == nil, "до дальних абонентов (в сети, но вне пары) передача из глуши не долетела")
ok(lastChat(u3, "тишина") == nil, "слушатель был — тишины нет")
-- один на частоте: эфир слышит тишину
RN.HandleChat(u5, "/freq 77.7")
TT = 504
RN.HandleChat(u5, "/r kto nibud na svyazi")
ok(lastChat(u5, "тишина") ~= nil, "один абонент — подсказка «в эфире тишина»")
-- антифлуд
local n5 = #u5.__chat
RN.HandleChat(u5, "/r snova snova")
ok(lastChat(u5, "Не так быстро") ~= nil and #u5.__chat == n5 + 1, "антифлуд: повтор раньше паузы отброшен")
-- !-вариант команды
TT = 510
ok(RN.HandleChat(u1, "!r poreshali") == true and u2.__chat[#u2.__chat] == "[Рация 145.5] Игрок601: poreshali", "!r работает так же, как /r")
-- маршрутные предохранители: чужие команды не страдают
ok(RN.HandleChat(admin, "/radio ne nasha") == false, "/radio — чужая команда, не трогаем")
ok(RN.HandleChat(admin, "/report bug") == false, "/report — чужая, пропускаем")
ok(RN.HandleChat(admin, "/r") == true and lastChat(admin, "Формат: /r") ~= nil, "голый /r — подсказка формата (поглощён)")
-- отключение
ok(RN.HandleChat(u1, "/freqleave") == true and RN.FreqOf(u1) == nil, "/freqleave — рация отключена")
ok(RN.HandleChat(u1, "/r test") == true and lastChat(u1, "не на частоте") ~= nil, "после отключения /r снова отказан")
RN.HandleChat(u1, "/freq 145.5")
ok(RN.HandleChat(u1, "/freq 0") == true and RN.FreqOf(u1) == nil, "/freq 0 — тоже отключение (для C-меню)")
ok(RN._freq[tostring(u1:SteamID64())] == nil, "запись sid64 зачищена сменой частоты на off")
-- восстановление при перезаходе (память сессии по sid64)
u2._rnFreq = nil
H.hooks["PlayerInitialSpawn"]["GRM_RN_FreqSpawn"](u2)
ok(u2._rnFreq == "145.5", "PlayerInitialSpawn: частота воскрешена из памяти sid64")
-- журнал: передачи попадают в /rn_log
local sawSay = false
for _, e in ipairs(RN.LogTail(40)) do if e.kind == "freq_say" then sawSay = true break end end
ok(sawSay, "радиопередачи журналируются (вид freq_say)")
-- юнит-проверки скремблера
ok(RN.FreqScramble("privet gorod", 1, 5) == "privet gorod", "скремблер: keep=1 — текст нетронут")
local sA1, sA2 = RN.FreqScramble("privet gorod", 0.4, 42), RN.FreqScramble("privet gorod", 0.4, 42)
ok(sA1 == sA2 and sA1 ~= "privet gorod", "скремблер детерминирован seed'ом")
ok(RN.FreqScramble("a b c", 0.5, 7):find(" ") ~= nil, "пробелы сквозь помехи живут")
-- статус суперадмина теперь показывает абонентов частот
local sawFreqLine = false
for _, ln in ipairs(RN.StatusLines()) do if ln:find("Радиочастоты") then sawFreqLine = true break end end
ok(sawFreqLine, "/rn_status печатает строку абонентов радиочастот")

P("== 25. Код 99: частоты — только с активным модулятором (находка 116) ==")
ok(H.regItems["radio_modulator"] ~= nil, "модуль зарегистрировал предмет radio_modulator в инвентаре")
local unitDef = H.regItems["radio_modulator"] or {}
ok(unitDef.model == RN.UnitModel or unitDef.model == RN.UnitModelFB, "модель предмета — reciever01b (или фолбэк, н85)")
ok(unitDef.useFunc == "radio_toggle" and unitDef.maxStack == 1 and unitDef.type == "item", "деф модулятора: item/useFunc radio_toggle/стак 1")
local w1 = mkPly(701, 0, false)      -- в покрытии, но БЕЗ железки
H.players[#H.players + 1] = w1
ok(RN.HasRadioUnit(w1) == false, "без модулятора — HasRadioUnit=false")
ok(RN.HandleChat(w1, "/freq 145.5") == true and RN.FreqOf(w1) == nil and lastChat(w1, "модулятор") ~= nil, "/freq без модулятора — отказ с подсказкой, частота не настроена")
ok(RN.HandleChat(w1, "/r test") == true and lastChat(w1, "модулятор") ~= nil, "/r без модулятора — тот же отказ")
giveUnit(w1, false)                  -- модулятор есть, но ВЫКЛЮЧЕН
ok(RN.HasRadioUnit(w1) == false, "модулятор ВЫКЛ — связи нет (гейт по data.on)")
ok(RN.HandleChat(w1, "/freq 200") == true and RN.FreqOf(w1) == nil, "выключенный: /freq отклонён")
giveUnit(w1, true)                   -- активировали
ok(RN.HasRadioUnit(w1) == true, "модулятор ВКЛ — HasRadioUnit=true")
ok(RN.HandleChat(w1, "/freq 200") == true and RN.FreqOf(w1) == "200.0", "активный: частота настроена")
TT = 520
local n1b = #u2.__chat
ok(RN.HandleChat(w1, "/r kto tut") == true, "активный: /r уходит в эфир")
ok(lastChat(w1, "тишина") ~= nil and #u2.__chat == n1b, "на 200.0 он один — тишина, чужих доставок нет")
w1.__inv = { slots = {} }            -- выбросил предмет совсем
ok(RN.HasRadioUnit(w1) == false, "модулятор выброшен — юнита нет")
ok(RN.HandleChat(w1, "/r eshyo") == true and lastChat(w1, "модулятор") ~= nil, "без предмета /r закрыт даже при настроенной частоте")
ok(RN.HandleChat(w1, "/freqleave") == true and RN.FreqOf(w1) == nil, "/freqleave доступен без модулятора (сброс частоты)")
giveUnit(w1, true)
RN.HandleChat(w1, "/freq 205")       -- частота настроена корректно
giveUnit(w1, false)                  -- …и модулятор выключили (предмет на месте)
ok(RN.HasRadioUnit(w1) == false and RN.FreqOf(w1) == "205.0", "ВЫКЛ: связи нет, частота при этом не сбрасывается (помнится)")
RN.HandleChat(w1, "/freq")
ok(lastChat(w1, "модулятор ВЫКЛ") ~= nil, "голый /freq честно говорит про выключенный модулятор")
TT = 522
ok(RN.HandleChat(w1, "/r proverka") == true and lastChat(w1, "модулятор") ~= nil, "ВЫКЛ + частота есть — /r всё равно закрыт")

P("")
P("ИТОГ: " .. tostring(checks) .. " проверок, провалов: " .. tostring(failed))
if failed > 0 then os.exit(1) end
P("SIM_RADIONET OK")
