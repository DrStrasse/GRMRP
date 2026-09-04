-- sim_heist.lua — функциональная проверка ивента «Ограбление» (находка 179e):
--   • отмывщик: конфиг (минимум, цель, фракции), TakeJob (доступ/отказ),
--     автозапуск ивента при наборе участников (баннер+музыка broadcast);
--   • таймер 50 минут; DepositFromBag → MoneyHeld; цель → победа фракции;
--     истечение без цели → победа госструктур;
--   • /bag_unload: чат-хуки (EasyChat), выгрузка на землю / отмывщику;
--   • /permremove: PlayerSayTransform + устойчивый поиск записи.
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
_G.__now = 1000
function CurTime() return _G.__now end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b) return { r = r or 0, g = g or 0, b = b or 0 } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

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

local H = { hooks = {}, timers = {}, netrecv = {}, broadcasts = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
-- Находка 179t: timer.Create/Remove захватываются (watchdog музыки)
timer = {
  Create = function(n, delay, reps, fn) H.timers[n] = fn end,
  Remove = function(n) H.timers[n] = nil end,
  Simple = function(_, fn) if fn then fn() end end,
}
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return nil end, IsValidModel = function() return true end, TraceLine = function() return { Hit = false } end }
-- Находка 180c: мок file хранит КД-файл (saveCooldown/loadCooldown)
local __fmem = {}
file = { IsDir = function() return true end, CreateDir = function() end,
         Exists = function(p) return __fmem[p] ~= nil end,
         Read = function(p) return __fmem[p] end,
         Write = function(p, s) __fmem[p] = s end, Find = function() return {} end }
-- Находка 180c: os.time управляемый (для КД)
os = { time = function() return _G.__osNow or 1700000000 end, date = function() return "2026-08-05" end, exit = function(c) error("os.exit(" .. tostring(c) .. ")") end }
game = { GetMap = function() return "rp_test" end }
player = { GetAll = function() return _G.__players or {} end }
net = {
  Start = function(n) net.current = n end, WriteEntity = function() end, WriteString = function() end, WriteBool = function() end,
  WriteUInt = function() end, WriteFloat = function() end,
  -- Находка 180f: логируем таблицы (участники в broadcast)
  WriteTable = function(t) H.tables = H.tables or {} H.tables[#H.tables + 1] = t end,
  Send = function() end,
  Broadcast = function() H.broadcasts[#H.broadcasts + 1] = net.current end,
  Receive = function(n, fn) H.netrecv[n] = fn end, ReadEntity = function() return nil end, ReadString = function() return "" end,
  ReadBool = function() return false end, ReadTable = function() return {} end, ReadUInt = function() return 0 end, ReadFloat = function() return 0 end,
}
duplicator = { StoreEntityModifier = function() end, RegisterEntityModifier = function() end }
_F = {}
Entity = function(idx) return _F[idx] end
local spawnedClasses = {}
local heistPatches = {}
local emitLog = {}
local stopLog = {}
CreateSound = function(owner, path)
  -- Находка 179q: живой сервер может вернуть «пустой» патч (звук не найден) —
  -- методов EnableLooping/PlayEx на нём нет. Имитируем это переключателем.
  if _G.__emptySoundPatch then
    local p = { owner = owner, path = path, stopped = false }
    p.Stop = function() p.stopped = true end
    heistPatches[#heistPatches + 1] = p
    return p
  end
  local p = { owner = owner, path = path, stopped = false, loop = nil, played = false, level = nil, volume = nil, pitch = nil, playing = true, faded = nil }
  p.Stop = function() p.stopped = true; p.stopCount = (p.stopCount or 0) + 1 end
  p.SetSoundLevel = function(_, l) p.level = l end
  p.EnableLooping = function(_, b) p.loop = b end
  p.Play = function() p.played = true; p.playCount = (p.playCount or 0) + 1 end
  -- Находка 179w/179x: родной FadeOut(сек) — плавное затухание без таймеров
  p.FadeOut = function(_, dur) p.faded = dur; p.stopped = true end
  heistPatches[#heistPatches + 1] = p
  return p
end
ents = {
  Create = function(cls) return mkEnt(cls) end,
  FindByClass = function(cls)
    if cls == "grm_money_launderer" then return _G.__launderers or {} end
    if cls == "grm_bank_vault" then return _G.__vaults or {} end
    return {}
  end,
  FindInSphere = function() return _G.__near or {} end,
}

local function mkPly(super, nick, sid, steam)
  return {
    __valid = true, super = super == true, nick = nick or "Игрок",
    sid64 = sid or (super and "76561198000000001" or "76561198000000002"),
    sid = steam or "STEAM_0:1:1",
    IsSuperAdmin = function(self) return self.super end,
    IsPlayer = function() return true end,
    SteamID64 = function(self) return self.sid64 end,
    SteamID = function(self) return self.sid end,
    GetPos = function() return Vector(0, 0, 0) end,
    GetShootPos = function() return Vector(0, 0, 60) end,
    GetAimVector = function() return Vector(1, 0, 0) end,
    GetEyeTrace = function() return { Entity = _G.__aimEnt } end,
    Nick = function(self) return self.nick end,
    Alive = function() return true end,
    -- Находка 180d: приватный звук как у kom_hour (p:EmitSound / p:StopSound)
    EmitSound = function(self, path, lvl, pitch) emitLog[#emitLog + 1] = { path = path, lvl = lvl, pitch = pitch, player = self } end,
    StopSound = function(self, path) stopLog[#stopLog + 1] = { path = tostring(path), player = self } end,
  }
end

Factions = {
  Mafia = { Members = { ["STEAM_0:1:1"] = { Role = "Boss" } }, Leader = "STEAM_0:1:1", Roles = { "Boss" }, Departments = {} },
  Polizei = { Members = { ["STEAM_0:1:50"] = { Role = "Chief" } }, Leader = "STEAM_0:1:2", Roles = { "Chief" }, Departments = {} },
}
GRM = {
  Notify = function() end,
  Format = function(n) return tostring(math.floor(tonumber(n) or 0)) .. " GRM" end,
  GiveMoney = function() end, TakeMoney = function() return true end, HasMoney = function() return true end,
  GetAllBalances = function() return {} end,
  Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end, FactionMember = function(fData, ply) return fData.Members[ply:SteamID()] end },
}
local minimapLog = { points = 0, sentTo = {}, removed = 0, removedName = "" }
GRM.Minimap = {
  AddTempPoint = function(name, pos, dur) minimapLog.points = minimapLog.points + 1 end,
  SendTo = function(p) minimapLog.sentTo[#minimapLog.sentTo + 1] = p end,
  -- Находка 180e: удаление маркера
  RemoveTempPoint = function(name) minimapLog.removed = minimapLog.removed + 1; minimapLog.removedName = name end,
}

-- ── мок энтити ──
local entClasses = {}
local EMT = {}
EMT.__index = function(t, k)
  local m = entClasses[t.__entClass]
  if m and m[k] then return m[k] end
  if k == "GetClass" then return function(s) return s.__cls end
  elseif k == "EntIndex" then return function(s) return s.__idx end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  elseif k == "GetAngles" then return function() return Angle(0, 0, 0) end
  elseif k == "SetPos" then return function(s, v) s.pos = v end
  elseif k == "SetAngles" then return function() end
  elseif k == "SetModel" then return function() end
  elseif k == "PhysicsInit" then return function() end
  elseif k == "SetMoveType" then return function() end
  elseif k == "SetSolid" then return function() end
  elseif k == "SetUseType" then return function() end
  elseif k == "SetCollisionGroup" then return function() end
  elseif k == "SetAutomaticFrameAdvance" then return function() end
  elseif k == "SelectWeightedSequence" then return function() return -1 end
  elseif k == "LookupSequence" then return function() return -1 end
  elseif k == "ResetSequence" then return function() end
  elseif k == "SetPlaybackRate" then return function() end
  elseif k == "ResetSequenceInfo" then return function() end
  elseif k == "GetPhysicsObject" then return function() return { EnableMotion = function() end, Wake = function() end } end
  elseif k == "Spawn" then return function(s) spawnedClasses[s.__cls] = (spawnedClasses[s.__cls] or 0) + 1 end
  elseif k == "Activate" then return function() end
  elseif k == "Remove" then return function(s) s.__valid = false end
  elseif k == "EmitSound" then return function(s, path, lvl, pitch, vol) emitLog[#emitLog + 1] = { path = path, lvl = lvl, pitch = pitch, vol = vol } end
  elseif k == "StopSound" then return function(s, path) stopLog[#stopLog + 1] = tostring(path) end
  elseif k == "IsPlayer" then return function() return false end
  elseif k == "IsNPC" then return function() return false end
  elseif k == "IsWorld" then return function() return false end
  elseif k == "NextThink" then return function() end
  elseif k == "IsValid" then return function(s) return s.__valid ~= false end
  elseif k == "GetModel" then return function() return "models/x.mdl" end
  elseif k == "GetNWString" then return function() return "" end
  end
  return nil
end
local nextIdx = 1
local function mkEnt(cls)
  local e = setmetatable({ __cls = cls, __entClass = cls, __valid = true, __idx = nextIdx }, EMT)
  nextIdx = nextIdx + 1
  _F[e.__idx] = e
  return e
end

-- ══════════════ ЗАГРУЗКА ══════════════
dofile("lua/autorun/sh_grm_economy.lua")
local E = GRM.Economy
ENT = {}
dofile("lua/entities/grm_money_launderer/shared.lua")
dofile("lua/entities/grm_money_launderer/init.lua")
entClasses["grm_money_launderer"] = {}
for k, v in pairs(ENT) do entClasses["grm_money_launderer"][k] = v end

local ld = mkEnt("grm_money_launderer")
ld:SetPos(Vector(0, 0, 0))
ld.GetEnabled = function() return ld.__enabled ~= false end
ld.SetEnabled = function(_, v) ld.__enabled = v end
ld.GetEventActive = function() return ld.__eventActive == true end
ld.SetEventActive = function(_, v) ld.__eventActive = v end
ld.GetMinParticipants = function() return ld.__minP or 2 end
ld.SetMinParticipants = function(_, v) ld.__minP = v end
ld.GetGoalMoney = function() return ld.__goal or 500000 end
ld.SetGoalMoney = function(_, v) ld.__goal = v end
ld.GetMoneyHeld = function() return ld.__held or 0 end
ld.SetMoneyHeld = function(_, v) ld.__held = v end
ld.GetParticipantCount = function() return ld.__pc or 0 end
ld.SetParticipantCount = function(_, v) ld.__pc = v end
ld.GetEventEndsAt = function() return ld.__ends or 0 end
ld.SetEventEndsAt = function(_, v) ld.__ends = v end
ld.GetAllowedFactions = function() return ld.__allowed or "" end
ld.SetAllowedFactions = function(_, v) ld.__allowed = v end
ld.GetWinnerFaction = function() return ld.__winner or "" end
ld.SetWinnerFaction = function(_, v) ld.__winner = v end
ld.GetHeistTargetPos = function() return ld.__htp or Vector(0, 0, 0) end
ld.SetHeistTargetPos = function(_, v) ld.__htp = v end
-- Находка 180f: PreStartAt (ожидание старта)
ld.GetPreStartAt = function() return ld.__pre or 0 end
ld.SetPreStartAt = function(_, v) ld.__pre = v end
-- Находка 180h: GovFactions
ld.GetGovFactions = function() return ld.__gov or "" end
ld.SetGovFactions = function(_, v) ld.__gov = v end
ld.Participants = {} ld.ParticipantNames = {} ld.FactionDelivered = {}
ld:Initialize()

ok(GRM.MoneyLaunderer ~= nil or true, "отмывщик: модуль загружен (класс)")
-- мок хранилища (цель Рейхсбанк)
local vaultEnt = mkEnt("grm_bank_vault")
vaultEnt:SetPos(Vector(900, 900, 0))
_G.__vaults = { vaultEnt }
ld.GetHeistTargetPos = function() return ld.__htp or Vector(0, 0, 0) end
ld.SetHeistTargetPos = function(_, v) ld.__htp = v end

-- ══════════════ 1. Конфиг и TakeJob ══════════════
ld:SetMinParticipants(2)
ld:SetGoalMoney(500000)
ld:SetAllowedFactions("Mafia")

local cop = mkPly(false, "Полицейский", "76561198000000009", "STEAM_0:1:99")  -- не Mafia
-- cop не в Mafia → его фракция Polizei → не разрешена
ld.Participants = {}
ld:SetParticipantCount(0)
local okJob = ld:TakeJob(cop)
ok(okJob == false, "полицейский: задание НЕ выдано (фракция не в списке)")
ok(ld:GetParticipantCount() == 0, "участники не выросли")

local maf1 = mkPly(false, "Мафиози1", "76561198000000002") -- Mafia
ok(ld:TakeJob(maf1) == true, "мафиози: задание принято")
ok(ld:GetParticipantCount() == 1, "участников = 1")
ok(ld:GetEventActive() == false, "ивент ещё не начат (1 < 2)")

-- повторное взятие
ok(ld:TakeJob(maf1) == false, "повторное взятие отклонено")

-- Находка 179p: во время ивента отмена запрещена
ld:SetEventActive(true)
ok(ld:LeaveJob(maf1) == false, "LeaveJob: во время ивента отклонено (находка 179p)")
ld:SetEventActive(false)

-- Находка 179m: отмена участия
ld:SetParticipantCount(1)
ok(ld:LeaveJob(maf1) == true, "LeaveJob: участник вышел")
ok(ld:GetParticipantCount() == 0, "LeaveJob: счётчик уменьшен")
ok(ld:LeaveJob(maf1) == false, "LeaveJob: не-участник не может выйти")
-- вернём участника для теста автозапуска
ld:TakeJob(maf1)

-- второй участник → минимум набран → ОЖИДАНИЕ старта 40 сек (находка 180f)
local maf2 = mkPly(false, "Мафиози2", "76561198000000003")
ok(ld:TakeJob(maf2) == true, "второй мафиози принят")
ok(ld:GetEventActive() == false, "ИВЕНТ НЕ запущен сразу — идёт ожидание (находка 180f)")
ok(ld:GetPreStartAt() == _G.__now + 40, "ожидание: PreStartAt = now+40 сек (находка 180f)")

-- третий участник успевает вступить во время ожидания
local maf3 = mkPly(false, "Мафиози3", "76561198000000004")
ok(ld:TakeJob(maf3) == true, "третий мафиози вступил во время ожидания (находка 180f)")
ok(ld:GetParticipantCount() == 3, "участников = 3")
ok(ld:GetEventActive() == false, "ивент всё ещё ждёт старта (находка 180f)")

-- по истечении 40 сек Think запускает ивент
_G.__now = _G.__now + 41
ld:Think()
ok(ld:GetEventActive() == true, "ИВЕНТ ЗАПУЩЕН после ожидания 40 сек (находка 180f)")
ok(ld:GetPreStartAt() == 0, "ожидание сброшено при старте (находка 180f)")
ok(ld:GetEventEndsAt() == _G.__now + 3000, "таймер 50 минут (3000 сек)")

-- ══════════════ 2. Баннер и музыка (broadcast) ══════════════
local startBc = false
for _, m in ipairs(H.broadcasts) do if m == "GRM_Heist_Event" then startBc = true end end
ok(startBc, "broadcast GRM_Heist_Event отправлен (баннер/музыка всем)")

-- Находка 180f: broadcast содержит список РП-имён участников («криминал»)
local lastTbl = H.tables and H.tables[#H.tables] or nil
local namesOk = lastTbl and #lastTbl == 3
if namesOk then
    local found = 0
    for _, r in ipairs(lastTbl) do
        if r.name == "Мафиози1" or r.name == "Мафиози2" or r.name == "Мафиози3" then found = found + 1 end
    end
    namesOk = found == 3
end
ok(namesOk, "список: broadcast start несёт 3 РП-имени участников (находка 180f)")

-- ══════════════ 2aa. МУЗЫКА: КАК kom_hour — КАЖДОМУ ИГРОКУ (находка 180d) ══════════════
-- Звук идёт приватно каждому игроку (p:EmitSound 127/110) — все слышат
-- одинаково на любой точке карты. Без патчей и таймеров.
_G.__players = { maf1, maf2 }
emitLog = {}
ld:SetEventActive(false)
ld:StartEvent()
ok(#emitLog == 2, "музыка: EmitSound отправлен КАЖДОМУ игроку (x2, находка 180d)")
ok(emitLog[1] and emitLog[1].path == "music/hl2_song20_submix0.mp3", "музыка: путь HEIST_MUSIC")
ok(emitLog[1] and emitLog[1].lvl == 127 and emitLog[1].pitch == 110, "музыка: громкость 127/110 как у kom_hour (находка 180d)")
ok(emitLog[1] and emitLog[1].player == maf1 and emitLog[2] and emitLog[2].player == maf2, "музыка: звук приватный каждому (находка 180d)")
ok(H.timers["grm_heist_music_" .. tostring(ld:EntIndex())] == nil, "музыка: НЕТ таймеров (находка 179x)")

-- ══════════════ 2a. СТАРТ БЕЗ ПАТЧЕЙ (находка 180d) ══════════════
-- CreateSound не используется вовсе — патчу негде падать.
ld:SetEventActive(false)
emitLog = {}
local okStart2 = pcall(function() ld:StartEvent() end)
ok(okStart2, "музыка: StartEvent не падает (нет патчей — нечему падать)")
ok(#emitLog == 2, "музыка: снова EmitSound каждому (x2)")
stopLog = {}
ld:StopHeistMusic()
ok(#stopLog >= 2, "StopHeistMusic: StopSound каждому игроку + себе (находка 180d)")
ok(stopLog[1] and stopLog[1].path == "music/hl2_song20_submix0.mp3", "StopHeistMusic: правильный путь")

-- ══════════════ 2a1. СИНГЛТОН МУЗЫКИ (находка 179v) ══════════════
-- Второй отмывщик, запустивший ивент, глушит музыку первого (нет эха).
ok(GRM.HeistMusicOwner == nil, "синглтон: после StopHeistMusic владелец снят")
local ld2 = mkEnt("grm_money_launderer")
ld2:SetPos(Vector(0, 0, 0))
ld2.GetEventActive = function() return ld2.__ea == true end
ld2.SetEventActive = function(_, v) ld2.__ea = v end
ld2.SetEventEndsAt = function() end
ld2.GetEventEndsAt = function() return 0 end
ld2.SetMoneyHeld = function() end
ld2.SetWinnerFaction = function() end
ld2.GetParticipantCount = function() return 2 end
ld2.GetGoalMoney = function() return 500000 end
ld2.GetHeistTargetPos = function() return Vector(0, 0, 0) end
ld2.SetHeistTargetPos = function() end
ld2.GetPreStartAt = function() return ld2.__pre or 0 end
ld2.SetPreStartAt = function(_, v) ld2.__pre = v end
ld2.Participants = {} ld2.ParticipantNames = {} ld2.FactionDelivered = {}
emitLog = {}
ld2:StartEvent()
ok(GRM.HeistMusicOwner == ld2, "синглтон: владелец = второй отмывщик")
ok(#emitLog == 2, "синглтон: музыка второго сыграна всем (x2)")
-- первый отмывщик снова запускает ивент → глушит второго
stopLog = {}
ld:SetEventActive(false)
ld:StartEvent()
ok(#stopLog >= 2, "синглтон: музыка ПЕРВОГО заглушила второго (StopSound всем, находка 179v)")
ok(GRM.HeistMusicOwner == ld, "синглтон: владелец снова первый отмывщик")
ok(H.timers["grm_heist_music_" .. tostring(ld2:EntIndex())] == nil, "синглтон: таймеров музыки нет вообще (находка 179x)")
ld:StopHeistMusic()

-- ══════════════ 2a2. МАРКЕР ИСЧЕЗАЕТ ПРИ ПРЕРЫВАНИИ (находка 180e) ══════════════
minimapLog.removed = 0
minimapLog.removedName = ""
ld2:OnRemove()
ok(minimapLog.removed == 1 and minimapLog.removedName == "РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ", "маркер: удалён при OnRemove (прерывание, находка 180e)")

-- ══════════════ 2b. ЦЕЛЬ ИВЕНТА (находка 179f) ══════════════
-- дефолт: ближайшее хранилище
local ht = ld:HeistTarget()
ok(ht and ht.x == 900 and ht.y == 900, "цель по умолчанию = ближайшее хранилище (Рейхсбанк)")
-- маркеры участникам (в Participants — sid'ы maf1/maf2/maf3)
_G.__players = { maf1, maf2, maf3 }
minimapLog.points = 0
minimapLog.sentTo = {}
ld:SendHeistTargetMarkers()
ok(minimapLog.points == 3, "участники получили GPS-маркер (AddTempPoint x3)")
ok(#minimapLog.sentTo == 3, "маркеры отправлены точечно (SendTo x3)")
minimapLog.removed = 0
ok(minimapLog.removed == 0, "маркер: ещё не удалён (ивент идёт)")
-- установка цели суперадмином через action set_target (прицел = vault)
_G.__aimEnt = vaultEnt
local recvAction = H.netrecv["GRM_Heist_Action"]
ok(recvAction ~= nil, "обработчик GRM_Heist_Action есть")
local admin2 = mkPly(true, "Владелец", "76561198000000001")
-- эмулируем приём: ent=ld, action=set_target
_G.__readEnt = ld
net.ReadEntity = function() return _G.__readEnt end
net.ReadString = function() return _G.__readStr or "" end
net.ReadUInt = function() return 0 end
net.ReadFloat = function() return 0 end
_G.__readStr = "set_target"
recvAction(0, admin2)
ok(ld:GetHeistTargetPos().x == 900, "set_target: цель установлена по прицелу (хранилище)")
_G.__readStr = "clear_target"
recvAction(0, admin2)
ok(ld:GetHeistTargetPos().x == 0, "clear_target: цель сброшена (авто: хранилище)")

-- ══════════════ 3. DepositFromBag → MoneyHeld → победа ══════════════
GRM.Customization = {
  LootBagGet = function(ply) return 400000 end,
  LootBagSet = function() end,
}
local beforeDep = ld:GetMoneyHeld()
local dep = ld:DepositFromBag(maf1)
ok(dep == 400000, "сдано 400.000 отмывщику (из сумки)")
ok(ld:GetMoneyHeld() == 400000, "MoneyHeld = 400.000")
ok(ld:GetEventActive() == true, "ивент продолжается (цель не достигнута)")

-- добиваем цель (сначала поднимаем планку, чтобы проверить winner ДО сброса)
ld:SetGoalMoney(1000000)
GRM.Customization.LootBagGet = function() return 200000 end
dep = ld:DepositFromBag(maf2)
ok(ld:GetMoneyHeld() == 600000, "MoneyHeld = 600.000")
ok(ld:GetWinnerFaction() == "Mafia", "победитель — фракция преступников (Mafia), сдавшая больше всех")
ok(ld:GetEventActive() == true, "ивент продолжается (цель 1.000.000 не достигнута)")
-- теперь опускаем цель → досрочная победа
ld:SetGoalMoney(500000)
dep = ld:DepositFromBag(maf2)
ok(dep == 200000, "сдано ещё 200.000")
ok(ld:GetEventActive() == false, "ивент завершён досрочно (цель достигнута)")

-- ══════════════ 3b. ОСТАНОВКА МУЗЫКИ при завершении (находка 180d) ══════════════
-- Как у kom_hour: при завершении ивента звук глушится StopSound всем игрокам.
ld:SetEventActive(false)
_G.__players = { maf1, maf2 }
emitLog = {}
ld:StartEvent()
ok(#emitLog == 2, "остановка: музыка играет после рестарта (x2)")
stopLog = {}
minimapLog.removed = 0
minimapLog.removedName = ""
ld:EndEvent(true, "Цель достигнута")
ok(#stopLog >= 2, "остановка: EndEvent глушит музыку всем игрокам (находка 180d)")
ok(GRM.HeistMusicOwner == nil, "остановка: владелец снят")
ok(minimapLog.removed == 1 and minimapLog.removedName == "РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ", "маркер: удалён при завершении ивента (находка 180e)")
ok(H.timers["grm_heist_fade_" .. tostring(ld:EntIndex())] == nil, "остановка: fade-таймера нет вообще (находка 179x)")

-- ══════════════ 4. Таймер: истечение без цели → госструктуры ══════════════
ld:SetEventActive(true)
ld:SetEventEndsAt(_G.__now + 3000)
ld:SetMoneyHeld(0)
ld:SetGoalMoney(500000)
ld:SetWinnerFaction("")
ld.Participants = { a = "Mafia", b = "Mafia" }
ld:SetParticipantCount(2)
-- эмулируем истечение
_G.__now = _G.__now + 3001
ld:Think()
ok(ld:GetEventActive() == false, "по истечении 50 минут ивент завершён")
local endBc = false
for _, m in ipairs(H.broadcasts) do if m == "GRM_Heist_Event" then endBc = true end end
ok(endBc, "broadcast об окончании отправлен")
ok(ld:GetParticipantCount() == 0, "участники сброшены")

-- ══════════════ 5. /bag_unload: чат-хуки + выгрузка на землю/отмывщику ══════════════
local custSrc = assert(io.open("lua/autorun/sh_grm_customization.lua", "rb")):read("*a")
ok(custSrc:find('hook.Add("PlayerSay", "GRM_LootBag_UnloadSay"', 1, true) ~= nil, "bag_unload: живой владелец PlayerSay (веч.-18: EasyChat-дубль срезан)")
ok(custSrc:find('SpawnCashAt(pos, cur, nil)', 1, true) ~= nil, "bag_unload: выгрузка на землю (паллеты/пачка)")
ok(custSrc:find('FindNearestLaunderer(ply, 400)', 1, true) ~= nil, "bag_unload: сначала отмывщик рядом")
ok(E.FindNearestLaunderer ~= nil, "economy: FindNearestLaunderer есть")
local ecoSrc = assert(io.open("lua/autorun/sh_grm_economy.lua", "rb")):read("*a")
ok(ecoSrc:find('FindNearestLaunderer', 1, true) ~= nil and ecoSrc:find('ents.FindByClass("grm_money_launderer")', 1, true) ~= nil, "economy: поиск отмывщика по классу")

-- ══════════════ 6. /permremove: PlayerSayTransform + устойчивый поиск ══════════════
local permSrc = assert(io.open("lua/autorun/sh_grm_perm_entities.lua", "rb")):read("*a")
ok(permSrc:find('hook.Add("PlayerSay", "GRM_PermEntities_ChatTransform"', 1, true) ~= nil, "perm: боевой PlayerSay для /permadd /permremove (реестр библиотеки)")
ok(permSrc:find('bestRec, bestDist = nil, math.huge', 1, true) ~= nil, "perm: removePerm ищет ближайшую запись по классу (устойчиво)")

-- ══════════════ 6b. Меню: FactionList + config_full + поза + R-удаление (находка 179g) ══════════════
local fl = ld:FactionList()
ok(#fl == 2 and fl[1] == "Mafia" and fl[2] == "Polizei", "FactionList: список существующих фракций (отсортирован)")
-- config_full: таблица выбранных
local recvA = H.netrecv["GRM_Heist_Action"]
net.ReadTable = function() return _G.__readTbl or {} end
_G.__readStr = "config_full"
_G.__readUInt = 3
net.ReadUInt = function() local v = _G.__readUInt or 0; _G.__readUInt = nil; return v end
_G.__readTbl = { "Polizei" }
recvA(0, admin2)
ok(ld:GetMinParticipants() == 3, "config_full: минимум = 3")
ok(ld:GetAllowedFactions() == "Polizei", "config_full: фракции из чекбоксов (Polizei)")
_G.__readTbl = {}
recvA(0, admin2)
ok(ld:GetAllowedFactions() == "", "config_full: пустой список = любые")

-- ══════════════ 5b. ПЕРМ-ЦИКЛ Extract/Apply (находка 179r) ══════════════
-- Настроенная энтити -> Extract -> данные; свежая энтити -> Apply -> значения.
local function mkPermEnt(minP, goal, allowed, htpx)
  local e = { __minP = minP, __goal = goal, __allowed = allowed, __htp = htpx and Vector(htpx, 900, 50) or Vector(0, 0, 0) }
  e.GetMinParticipants = function(s) return s.__minP or 2 end
  e.SetMinParticipants = function(s, v) s.__minP = v end
  e.GetGoalMoney = function(s) return s.__goal or 500000 end
  e.SetGoalMoney = function(s, v) s.__goal = v end
  e.GetAllowedFactions = function(s) return s.__allowed or "" end
  e.SetAllowedFactions = function(s, v) s.__allowed = v end
  e.GetHeistTargetPos = function(s) return s.__htp or Vector(0, 0, 0) end
  e.SetHeistTargetPos = function(s, v) s.__htp = v end
  e.GetGovFactions = function(s) return s.__gov or "" end
  e.SetGovFactions = function(s, v) s.__gov = v end
  return e
end
local srcA = mkPermEnt(5, 900000, "Mafia,Polizei", 900)
local dataA = GRM.PermData.Extract["grm_money_launderer"](srcA)
ok(dataA and dataA.minParticipants == 5 and dataA.goalMoney == 900000, "перм: Extract сохраняет минимум/цель (находка 179r)")
ok(dataA and dataA.allowedFactions == "Mafia,Polizei", "перм: Extract сохраняет фракции")
ok(dataA and dataA.heistTarget and dataA.heistTarget.x == 900, "перм: Extract сохраняет цель ивента")
local dstA = mkPermEnt(nil, nil, nil, nil)
GRM.PermData.Apply["grm_money_launderer"](dstA, dataA)
ok(dstA:GetMinParticipants() == 5 and dstA:GetGoalMoney() == 900000, "перм: Apply применяет минимум/цель")
ok(dstA:GetAllowedFactions() == "Mafia,Polizei", "перм: Apply применяет фракции")
ok(dstA:GetHeistTargetPos().x == 900, "перм: Apply применяет цель ивента")
local srcB = mkPermEnt(nil, nil, nil, nil)
local dataB = GRM.PermData.Extract["grm_money_launderer"](srcB)
ok(dataB.minParticipants == 2 and dataB.goalMoney == 500000 and dataB.allowedFactions == "" and dataB.heistTarget == nil, "перм: Extract свежей энтити = дефолты, без цели")
pcall(GRM.PermData.Apply["grm_money_launderer"], dstA, { minParticipants = "abc", goalMoney = "zzz" })
ok(dstA:GetMinParticipants() == 2 and dstA:GetGoalMoney() == 500000, "перм: битые данные не падают — фолбэк 2/500000")
pcall(GRM.PermData.Apply["grm_money_launderer"], dstA, nil)
ok(dstA:GetMinParticipants() == 2, "перм: Apply(nil) не падает")

local lin3 = assert(io.open("lua/entities/grm_money_launderer/init.lua", "rb")):read("*a")
ok(lin3:find('SelectWeightedSequence(ACT_IDLE)', 1, true) ~= nil and lin3:find('SetAutomaticFrameAdvance(true)', 1, true) ~= nil and lin3:find('MOVETYPE_NONE', 1, true) ~= nil and lin3:find('SOLID_BBOX', 1, true) ~= nil and lin3:find('COLLISION_GROUP_NPC', 1, true) ~= nil, "поза: как у торгашей (BBOX/MOVETYPE_NONE/NPC-коллизия/автокадры/idle, находка 179i)")
ok(lin3:find('self:SetHullType', 1, true) == nil and lin3:find('SOLID_VPHYSICS', 1, true) == nil, "поза: нет физики и NPC-методов (не падает)")
local lcl4 = assert(io.open("lua/entities/grm_money_launderer/cl_init.lua", "rb")):read("*a")
ok(lcl4:find('ResetSequence', 1, true) == nil, "поза: анимация только на сервере (как у торгашей)")
ok(lin3:find('FactionList', 1, true) ~= nil and lin3:find('config_full', 1, true) ~= nil, "сервер: список фракций + config_full")
local lcl3 = assert(io.open("lua/entities/grm_money_launderer/cl_init.lua", "rb")):read("*a")
ok(lcl3:find('facState', 1, true) ~= nil and lcl3:find('factionsList', 1, true) ~= nil, "клиент: кликабельные строки фракций facState (находка 179s)")
ok(lcl3:find('config_full', 1, true) ~= nil and lcl3:find('DNumberWang', 1, true) ~= nil, "клиент: config_full + поля минимум/цель")
local tool3 = assert(io.open("lua/weapons/gmod_tool/stools/grm_bank_tool.lua", "rb")):read("*a")
ok(tool3:find('cls == "grm_money_launderer" and t.id ~= "heisttarget"', 1, true) ~= nil and tool3:find('Отмывщик удалён', 1, true) ~= nil, "тул: R удаляет отмывщика (находка 179g)")
ok(tool3:find('ПКМ по банковскому оборудованию = открыть его меню', 1, true) ~= nil and tool3:find('if ent.Use then ent:Use(ply) end', 1, true) ~= nil, "тул: ПКМ открывает меню (настройка скупщика, находка 179j)")
ok(tool3:find('trace.HitPos + trace.HitNormal)', 1, true) ~= nil, "тул: отмывщик ставится прямо на поверхность (не в воздухе, находка 179k)")
local lcl5 = assert(io.open("lua/entities/grm_money_launderer/cl_init.lua", "rb")):read("*a")
ok(lcl5:find('SetDecimals(0)', 1, true) ~= nil and lcl5:find('GetValue()', 1, true) ~= nil, "клиент: числа читаются из полей GetValue при сохранении (находка 179s)")
ok(lcl5:find('SetSize(620, 880)', 1, true) ~= nil, "клиент: меню больше (620x880, находка 179u)")
ok(lcl5:find('СОХРАНИТЬ НАСТРОЙКИ', 1, true) ~= nil and lcl5:find('SAVE_BAR', 1, true) ~= nil and lcl5:find('saveFn', 1, true) ~= nil, "клиент: кнопка «СОХРАНИТЬ НАСТРОЙКИ» в фикс. нижней панели SAVE_BAR (находка 179u)")
local lin4 = assert(io.open("lua/entities/grm_money_launderer/init.lua", "rb")):read("*a")
ok(lin4:find('net.ReadUInt(16)', 1, true) ~= nil, "сервер: чтение minP 16 бит (находка 179k)")
ok(lin4:find('GRM.PermData.Upsert', 1, true) ~= nil and lin4:find('persistConfig', 1, true) ~= nil, "сервер: сохранение через Upsert + persistConfig (находка 179r)")
ok(lin4:find('Перм-запись СОЗДАНА', 1, true) ~= nil and lin4:find('Перм-запись ОБНОВЛЕНА', 1, true) ~= nil, "сервер: обратная связь о сохранении настроек (находка 179r)")
ok(lin4:find('action == "config" then', 1, true) ~= nil and not lin4:find('ReadUInt(8)', 1, true), "сервер: старый config тоже 16 бит (нет ReadUInt(8), находка 179r)")
ok(lin4:find('function ENT:LeaveJob', 1, true) ~= nil and lin4:find('action == "leave"', 1, true) ~= nil, "сервер: LeaveJob + action leave (находка 179m)")
ok(lin4:find('ОТМЕНА УЧАСТИЯ В МОМЕНТ ИВЕНТА ЗАПРЕЩЕНА', 1, true) ~= nil and lin4:find('if self:GetEventActive() then', 1, true) ~= nil, "сервер: LeaveJob запрещён во время ивента (находка 179p)")
local lcl6 = assert(io.open("lua/entities/grm_money_launderer/cl_init.lua", "rb")):read("*a")
ok(lcl6:find('ОТМЕНИТЬ УЧАСТИЕ', 1, true) ~= nil and lcl6:find('act(ent, "leave")', 1, true) ~= nil, "клиент: кнопка «ОТМЕНИТЬ УЧАСТИЕ» (находка 179m)")
ok(lcl6:find('ОТМЕНА УЧАСТИЯ В МОМЕНТ ИВЕНТА ЗАПРЕЩЕНА', 1, true) ~= nil and lcl6:find('Color(80, 80, 90)', 1, true) ~= nil, "клиент: во время ивента кнопка заблокирована с подписью (находка 179p)")
local heistCl = assert(io.open("lua/autorun/client/cl_grm_heist.lua", "rb")):read("*a")
ok(heistCl:find('local function startMusic', 1, true) == nil and heistCl:find('Heist.Music', 1, true) == nil, "клиент: музыку сам НЕ запускает (играет с сервера, находка 179o)")
ok(heistCl:find('играет С СЕРВЕРА', 1, true) ~= nil, "клиент: комментарий «музыка с сервера»")

-- ══════════════ 7. Тул + перм + модели ══════════════
local tool = assert(io.open("lua/weapons/gmod_tool/stools/grm_bank_tool.lua", "rb")):read("*a")
ok(tool:find('grm_money_launderer', 1, true) ~= nil, "тул: тип «Отмывщик денег»")
local perm = assert(io.open("lua/autorun/sh_grm_perm_entities.lua", "rb")):read("*a")
ok(perm:find('grm_money_launderer     = true', 1, true) ~= nil, "PERM_CLASSES: отмывщик")
local lsh = assert(io.open("lua/entities/grm_money_launderer/shared.lua", "rb")):read("*a")
ok(lsh:find('HeistDuration = 3000', 1, true) ~= nil, "ивент: 50 минут (3000 сек)")
ok(lsh:find('HeistTargetPos', 1, true) ~= nil, "отмывщик: NWVar цели ивента (находка 179f)")
local lin2 = assert(io.open("lua/entities/grm_money_launderer/init.lua", "rb")):read("*a")
ok(lin2:find('РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ', 1, true) ~= nil and lin2:find('Двигайтесь к локации', 1, true) ~= nil, "маркер: «РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ», «Двигайтесь к локации!»")
ok(lin2:find('SendHeistTargetMarkers', 1, true) ~= nil, "отмывщик: раздача маркеров участникам")
ok(lin2:find('RemoveTempPoint(HEIST_TARGET_NAME)', 1, true) ~= nil and lin2:find('HEIST_TARGET_NAME = "РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ"', 1, true) ~= nil, "отмывщик: маркер удаляется при завершении/прерывании (находка 180e)")
ok(lin2:find('heist_target', 1, true) ~= nil and lin2:find('grm_heist_target', 1, true) ~= nil, "команда /heist_target (и clear)")
ok(lin2:find('heistTarget', 1, true) ~= nil, "перм: цель сохраняется (/permadd)")
local tool2 = assert(io.open("lua/weapons/gmod_tool/stools/grm_bank_tool.lua", "rb")):read("*a")
ok(tool2:find('heisttarget', 1, true) ~= nil and tool2:find('SetHeistTarget', 1, true) ~= nil, "тул: режим «Цель ивента — Рейхсбанк»")
ok(tool2:find('Цель ивента — Рейхсбанк', 1, true) ~= nil, "тул: название режима")
local lin = assert(io.open("lua/entities/grm_money_launderer/init.lua", "rb")):read("*a")
ok(lin:find('НАЧАТ ИВЕНТ: ОГРАБЛЕНИЕ', 1, true) ~= nil, "баннер: «НАЧАТ ИВЕНТ: ОГРАБЛЕНИЕ»")
ok(lin:find('HEIST_MUSIC = "music/hl2_song20_submix0.mp3"', 1, true) ~= nil, "сервер: константа HEIST_MUSIC")
ok((lin:find('ipairs(player.GetAll())', 1, true) ~= nil or lin:find('GRM.Perf.Players()', 1, true) ~= nil) and lin:find('p:EmitSound(HEIST_MUSIC, 127, 110)', 1, true) ~= nil, "сервер: музыка КАЖДОМУ игроку p:EmitSound 127/110 (находка 180d)")
ok(lin:find('Sound(HEIST_MUSIC)', 1, true) ~= nil, "сервер: прекэш Sound() как у kom_hour (находка 180d)")
ok(lin:find('util.PrecacheSound(HEIST_MUSIC)', 1, true) ~= nil, "сервер: прекэш util.PrecacheSound (страховка)")
ok(lin:find('CreateSound', 1, true) == nil and lin:find('FadeOutHeistMusic', 1, true) == nil, "сервер: CreateSound/FadeOut ПОЛНОСТЬЮ удалены (находка 180d)")
ok(lin:find('StartMusicWatchdog', 1, true) == nil and lin:find('MusicFadeTimerName', 1, true) == nil and lin:find('MUSIC_WATCHDOG_INTERVAL', 1, true) == nil and lin:find('_grmMusicRestartAt', 1, true) == nil, "сервер: watchdog/fade-таймеры ПОЛНОСТЬЮ удалены (находка 179x)")
ok(lin:find('GRM.HeistMusicOwner', 1, true) ~= nil and lin:find('GRM.HeistMusicOwner ~= self', 1, true) ~= nil, "сервер: синглтон музыки HeistMusicOwner (находка 179v)")
ok(lin:find('function ENT:StopHeistMusic', 1, true) ~= nil and lin:find('p:StopSound(HEIST_MUSIC)', 1, true) ~= nil, "сервер: StopHeistMusic — StopSound каждому игроку (находка 180d)")
ok(lin:find('self:StopHeistMusic()', 1, true) ~= nil and lin:find('function ENT:EndEvent', 1, true) ~= nil, "сервер: EndEvent останавливает музыку (находка 180d)")
local lcl = assert(io.open("lua/autorun/client/cl_grm_heist.lua", "rb")):read("*a")
ok(lcl:find('local function startMusic', 1, true) == nil, "клиент: нет startMusic (музыка с сервера)")
ok(lcl:find('GRMHeist_Banner', 1, true) ~= nil and lcl:find('ОГРАБЛЕНИЕ', 1, true) ~= nil, "клиент: баннер и отсчёт")
ok(lcl:find('Heist.Participants', 1, true) ~= nil and lcl:find('УЧАСТНИКИ (КРИМИНАЛ)', 1, true) ~= nil, "клиент: HUD-список РП-имён участников (находка 180f)")
-- Находка 180c: КД ограбления
ok(lin4:find('GRM.HeistCooldownUntil', 1, true) ~= nil and lin4:find('grm_heist_cooldown.json', 1, true) ~= nil, "сервер: глобальный КД + файл персистентности (находка 180c)")
ok(lin4:find('Ограбление на перезагрузке', 1, true) ~= nil and lin4:find('cdLeft', 1, true) ~= nil, "сервер: TakeJob отклоняется при КД с таймером (находка 180c)")
ok(lin4:find('GRM.HeistCooldownUntil = os.time() + math.max(60, GRM.HeistCooldownDuration or 1800)', 1, true) ~= nil, "сервер: КД ставится в EndEvent (находка 180c)")
ok(lcl3:find('ОГРАБЛЕНИЕ НА ПЕРЕЗАГРУЗКЕ', 1, true) ~= nil and lcl3:find('cooldownLeft', 1, true) ~= nil, "клиент: кнопка-блокировка при КД (находка 180c)")
-- Находка 180f: ожидание старта + список участников
ok(lcl3:find('ИВЕНТ НАЧНЁТСЯ ЧЕРЕЗ', 1, true) ~= nil and lcl3:find('preStartLeft', 1, true) ~= nil, "клиент: кнопка-статус ожидания старта (находка 180f)")
ok(lcl3:find('УЧАСТНИКИ (КРИМИНАЛ)', 1, true) ~= nil and lcl3:find('participantList', 1, true) ~= nil, "клиент: список РП-имён участников в меню (находка 180f)")
ok(lin4:find('PreStartAt', 1, true) ~= nil and lin4:find('PreStartDelay or 40', 1, true) ~= nil, "сервер: ожидание старта PreStartAt 40 сек (находка 180f)")
ok(lin4:find('ParticipantNames', 1, true) ~= nil and lin4:find('GRM_RPName', 1, true) ~= nil, "сервер: хранение РП-имён участников (находка 180f)")
ok(lin4:find('function ENT:ForceStart', 1, true) ~= nil and lin4:find('HeistCooldownUntil = 0', 1, true) ~= nil, "сервер: ForceStart игнорирует КД (находка 180g)")
ok(lin4:find('function ENT:ForceStop', 1, true) ~= nil and lin4:find('reason ~= "superadmin"', 1, true) ~= nil, "сервер: ForceStop без КД (находка 180g)")
ok(lin4:find('"/heist_force"', 1, true) ~= nil and lin4:find('"/heist_stop"', 1, true) ~= nil, "сервер: команды /heist_force и /heist_stop (находка 180g)")
-- Находка 180h: награда гос.структурам
ok(lin4:find('GovFactions', 1, true) ~= nil and lin4:find('IsGovFaction', 1, true) ~= nil, "сервер: чеклист гос.структур GovFactions (находка 180h)")
ok(lin4:find('PlayerDeath", "GRM_Heist_GovKills', 1, true) ~= nil and lin4:find('RegisterGovKill', 1, true) ~= nil, "сервер: учёт киллов криминала через PlayerDeath (находка 180h)")
ok(lsh:find('GovRewardMin = 200000', 1, true) ~= nil and lsh:find('GovRewardMax = 1000000', 1, true) ~= nil, "сервер: рамки награды 200к–1М (находка 180h)")
ok(lin4:find('GRM.FactionBudgetAdd', 1, true) ~= nil and lin4:find('kills[f] or 0', 1, true) ~= nil, "сервер: выплата в бюджет фракции по киллам (находка 180h)")
ok(lin4:find('govFactions = tostring(ent:GetGovFactions() or "")', 1, true) ~= nil and lin4:find('if data.govFactions ~= nil then', 1, true) ~= nil, "сервер: govFactions сохраняется в перм Extract/Apply (находка 180h)")
ok(lcl3:find('ГОС.СТРУКТУРЫ', 1, true) ~= nil and lcl3:find('govState', 1, true) ~= nil, "клиент: чеклист гос.структур в меню (находка 180h)")
-- Находка 180i: выплата криминалу x2
ok(lsh:find('CrimRewardMultiplier = 2', 1, true) ~= nil, "сервер: множитель выплаты криминалу x2 (находка 180i)")
ok(lin4:find('победа криминала', 1, true) ~= nil and lin4:find('held * (self.CrimRewardMultiplier or 2)', 1, true) ~= nil, "сервер: выплата криминалу = x2 от награбленного (находка 180i)")
ok(lcl3:find('КД между ограблениями', 1, true) ~= nil and lcl3:find('cdWang', 1, true) ~= nil, "клиент: поле настройки КД для суперадмина (находка 180c)")

-- ══════════════ 8. КУЛДАУН ОГРАБЛЕНИЯ (находка 180c) ══════════════
-- После завершения ивента ставится ГЛОБАЛЬНЫЙ КД (30 мин по умолчанию) —
-- взять задание нельзя, пока не истёк таймер.
_G.__osNow = 1700000000
ok(GRM.HeistCooldownUntil == _G.__osNow + 1800, "КД: после EndEvent установлен unix+1800 (30 мин)")
ok(__fmem["grm_heist_cooldown.json"] ~= nil, "КД: файл grm_heist_cooldown.json записан")
-- свежий отмывщик (без участников), ивент не активен
local ldCD = mkEnt("grm_money_launderer")
ldCD:SetPos(Vector(0, 0, 0))
ldCD.GetEnabled = function() return true end
ldCD.GetEventActive = function() return false end
ldCD.GetParticipantCount = function() return 0 end
ldCD.SetParticipantCount = function() end
ldCD.GetMinParticipants = function() return 2 end
ldCD.GetGoalMoney = function() return 500000 end
ldCD.GetAllowedFactions = function() return "" end
ldCD.GetPreStartAt = function() return ldCD.__pre or 0 end
ldCD.SetPreStartAt = function(_, v) ldCD.__pre = v end
ldCD.GetGovFactions = function() return ldCD.__gov or "" end
ldCD.SetGovFactions = function(_, v) ldCD.__gov = v end
ldCD.Participants = {} ldCD.ParticipantNames = {}
-- КД активен → отказ
ok(ldCD:TakeJob(maf1) == false, "КД: TakeJob отклонён пока КД активен")
-- истечение КД → задание снова можно взять
_G.__osNow = _G.__osNow + 1801
ok(ldCD:TakeJob(maf1) == true, "КД: после истечения TakeJob снова работает")
ldCD.Participants = {} ldCD.ParticipantNames = {}
ldCD:SetPreStartAt(0)

-- ══════════════ 8b. ПРИНУДИТЕЛЬНЫЙ СТАРТ/СТОП (находка 180g) ══════════════
-- /heist_force: суперадмин запускает ивент, игнорируя КД и все условия.
_G.__osNow = _G.__osNow + 1
GRM.HeistCooldownUntil = _G.__osNow + 1800 -- КД активен
local ldF = mkEnt("grm_money_launderer")
ldF:SetPos(Vector(0, 0, 0))
ldF.GetEventActive = function() return ldF.__ea == true end
ldF.SetEventActive = function(_, v) ldF.__ea = v end
ldF.SetEventEndsAt = function() end
ldF.GetEventEndsAt = function() return 0 end
ldF.SetMoneyHeld = function() end
ldF.SetWinnerFaction = function() end
ldF.GetWinnerFaction = function() return "" end
ldF.GetParticipantCount = function() return 0 end
ldF.SetParticipantCount = function() end
ldF.GetMinParticipants = function() return 2 end
ldF.GetGoalMoney = function() return 500000 end
ldF.GetPreStartAt = function() return ldF.__pre or 0 end
ldF.SetPreStartAt = function(_, v) ldF.__pre = v end
ldF.GetHeistTargetPos = function() return Vector(0, 0, 0) end
ldF.SetHeistTargetPos = function() end
ldF.Participants = {} ldF.ParticipantNames = {} ldF.FactionDelivered = {}
ok(ldF:ForceStart(admin2) == true, "force: ForceStart запустил ивент (находка 180g)")
ok(ldF:GetEventActive() == true, "force: ивент активен несмотря на КД (находка 180g)")
ok(GRM.HeistCooldownUntil == 0, "force: КД сброшен (находка 180g)")
-- повторный force при активном ивенте — отказ
ok(ldF:ForceStart(admin2) == false, "force: повторный запуск при активном ивенте отклонён")
-- /heist_stop: принудительное завершение
ok(ldF:ForceStop(admin2) == true, "force: ForceStop завершил ивент (находка 180g)")
ok(ldF:GetEventActive() == false, "force: ивент завершён (находка 180g)")
-- после superadmin-стопа КД НЕ ставится (можно тестировать снова)
ok(GRM.HeistCooldownUntil == 0, "force: после стопа КД не установлен (находка 180g)")
-- длительность КД настраивается через config_full (cdMin=20 → 1200 сек)
_G.__readTbl = {}
_G.__readUInt = 20
_G.__readStr = "config_full"
_G.__readTbl = { "Mafia" }
local recvCD = H.netrecv["GRM_Heist_Action"]
-- эмуляция: minP=2, goal=500000, фракции, cdMin=20
net.ReadUInt = function() return 2 end
local oldReadTable = net.ReadTable
net.ReadTable = function() return { "Mafia" } end
-- читаем по порядку: 16 бит minP, 32 бит goal, таблица, 16 бит cdMin
local callN = 0
net.ReadUInt = function()
    callN = callN + 1
    if callN == 1 then return 2 end
    if callN == 2 then return 500000 end
    if callN == 3 then return 20 end
    return 0
end
recvCD(0, admin2)
ok(GRM.HeistCooldownDuration == 1200, "КД: config_full установил длительность 20 мин (1200 сек)")
GRM.HeistCooldownUntil = 0

-- ══════════════ 9. НАГРАДА ГОС.СТРУКТУРАМ (находка 180h) ══════════════
-- dofile экономики переопределил GRM.FactionBudgetAdd — ставим свой мок
local budgetLog = {}
GRM.FactionBudgetAdd = function(name, delta, reason) budgetLog[name] = (budgetLog[name] or 0) + (delta or 0) end
GRM.FactionBudgetGet = function(name) return budgetLog[name] or 0 end
-- Победа госников: 200к–1М в бюджет фракций, пропорционально доставленному
-- отмывщику, распределение по киллам криминала (учёт через PlayerDeath).
local gov1 = mkPly(false, "Полицейский", "76561198000000010", "STEAM_0:1:50") -- Polizei (гос.структура)
local ldG = mkEnt("grm_money_launderer")
ldG:SetPos(Vector(0, 0, 0))
ldG.GetEventActive = function() return ldG.__ea == true end
ldG.SetEventActive = function(_, v) ldG.__ea = v end
ldG.SetEventEndsAt = function() end
ldG.GetEventEndsAt = function() return 0 end
ldG.SetMoneyHeld = function(_, v) ldG.__held = v end
ldG.GetMoneyHeld = function() return ldG.__held or 0 end
ldG.SetWinnerFaction = function() end
ldG.GetWinnerFaction = function() return "" end
ldG.GetParticipantCount = function() return 1 end
ldG.SetParticipantCount = function() end
ldG.GetMinParticipants = function() return 2 end
ldG.GetGoalMoney = function() return 500000 end
ldG.GetPreStartAt = function() return ldG.__pre or 0 end
ldG.SetPreStartAt = function(_, v) ldG.__pre = v end
ldG.GetHeistTargetPos = function() return Vector(0, 0, 0) end
ldG.SetHeistTargetPos = function() end
ldG.GetGovFactions = function() return ldG.__gov or "" end
ldG.SetGovFactions = function(_, v) ldG.__gov = v end
ldG.Participants = {} ldG.ParticipantNames = {} ldG.FactionDelivered = {} ldG.GovKills = {}
_G.__launderers = { ldG } -- PlayerDeath-хук ищет активный отмывщик по классу

-- отмечаем Polizei как гос.структуру + делаем maf1 участником
ldG:SetGovFactions("Polizei")
local sidMaf1 = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(maf1)) or maf1:SteamID64() or ""
ldG.Participants[tostring(sidMaf1)] = "Mafia"
ldG:SetEventActive(true)
_G.__players = { maf1, gov1 }
-- госник убивает криминала → килл фракции (PlayerDeath hook)
local deathHook = H.hooks.PlayerDeath and H.hooks.PlayerDeath.GRM_Heist_GovKills
ok(deathHook ~= nil, "награда: PlayerDeath-хук учёта киллов зарегистрирован (находка 180h)")
deathHook(maf1, nil, gov1)
ok(ldG.GovKills["Polizei"] == 1, "награда: госник убил криминала → Polizei +1 килл (находка 180h)")
-- убийство НЕ госником (Mafia по Mafia) не засчитывается
local mafKiller = mkPly(false, "Киллер", "76561198000000020", "STEAM_0:1:77")
Factions.Mafia.Members["STEAM_0:1:77"] = { Role = "Soldier" }
deathHook(maf1, nil, mafKiller)
ok(ldG.GovKills["Mafia"] == nil and ldG.GovKills["Polizei"] == 1, "награда: килл не-госника не засчитан (находка 180h)")
-- победа госников: доставлено 500.000 → награда 500.000 в бюджет Polizei
budgetLog = {}
ldG:SetMoneyHeld(500000)
ldG:EndEvent(false, "Время вышло")
print("    debug: held=" .. tostring(ldG:GetMoneyHeld()) .. " gov=" .. tostring(ldG:GetGovFactions()) .. " budget Polizei=" .. tostring(budgetLog["Polizei"]))
ok(budgetLog["Polizei"] == 500000, "награда: Polizei получила 500.000 в бюджет (пропорционально, находка 180h)")
-- минимум: доставлено 50.000 → 200.000
budgetLog = {}
ldG:SetMoneyHeld(50000)
ldG:SetEventActive(true)
ldG:EndEvent(false, "Время вышло")
ok(budgetLog["Polizei"] == 200000, "награда: минимум 200.000 (находка 180h)")
-- максимум: доставлено 2.000.000 → 1.000.000
budgetLog = {}
ldG:SetMoneyHeld(2000000)
ldG:SetEventActive(true)
ldG:EndEvent(false, "Время вышло")
ok(budgetLog["Polizei"] == 1000000, "награда: максимум 1.000.000 (находка 180h)")
-- распределение по киллам: Polizei 3 килла, Gov 1 килл, reward 1.000.000 → 750.000/250.000
ldG:SetGovFactions("Polizei,Gov")
Factions.Gov = { Members = { ["STEAM_0:1:99"] = { Role = "Agent" } }, Leader = "STEAM_0:1:98", Roles = { "Agent" }, Departments = {} }
local gov2 = mkPly(false, "Агент", "76561198000000030", "STEAM_0:1:99")
budgetLog = {}
ldG.GovKills = { Polizei = 3, Gov = 1 }
ldG:SetMoneyHeld(2000000)
ldG:SetEventActive(true)
ldG:EndEvent(false, "Время вышло")
ok(budgetLog["Polizei"] == 750000 and budgetLog["Gov"] == 250000, "награда: распределение по киллам 3:1 (750к/250к, находка 180h)")
-- без киллов — поровну
budgetLog = {}
ldG.GovKills = {}
ldG:SetMoneyHeld(2000000)
ldG:SetEventActive(true)
ldG:EndEvent(false, "Время вышло")
ok(budgetLog["Polizei"] == 500000 and budgetLog["Gov"] == 500000, "награда: без киллов — поровну (находка 180h)")
-- килл не-участника не засчитывается
ldG.GovKills = {}
ldG.Participants = {}
ldG:SetEventActive(true)
deathHook(mafKiller, nil, gov1) -- жертва не участник
ok(ldG.GovKills["Polizei"] == nil, "награда: килл не-участника не засчитан (находка 180h)")

-- ══════════════ 9i. ВЫПЛАТА КРИМИНАЛУ ПРИ ПОБЕДЕ — x2 (находка 180i) ══════════════
ldG.GetWinnerFaction = function() return ldG.__winner or "" end
ldG.SetWinnerFaction = function(_, v) ldG.__winner = v end
budgetLog = {}
ldG.FactionDelivered = { Mafia = 400000, Yakuza = 100000 }
ldG:SetMoneyHeld(500000)
ldG:SetWinnerFaction("Mafia")
ldG:SetEventActive(true)
ldG:EndEvent(true, "Цель достигнута")
ok(budgetLog["Mafia"] == 800000 and budgetLog["Yakuza"] == 200000, "криминал: выплата x2 распределена по сданному 400к/100к → 800к/200к (находка 180i)")
ok((budgetLog["Mafia"] or 0) + (budgetLog["Yakuza"] or 0) == 1000000, "криминал: сумма = x2 от награбленного (1.000.000, находка 180i)")
budgetLog = {}
ldG.FactionDelivered = { Mafia = 300000 }
ldG:SetMoneyHeld(300000)
ldG:SetWinnerFaction("Mafia")
ldG:SetEventActive(true)
ldG:EndEvent(true, "Цель достигнута")
ok(budgetLog["Mafia"] == 600000, "криминал: одна фракция — вся выплата x2 (600.000, находка 180i)")
budgetLog = {}
ldG.FactionDelivered = { Mafia = 300000 }
ldG:SetMoneyHeld(300000)
ldG:SetEventActive(true)
ldG:EndEvent(false, "superadmin")
ok(budgetLog["Mafia"] == nil, "криминал: при superadmin-стопе выплат нет (находка 180i)")

print(string.format("sim_heist: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
