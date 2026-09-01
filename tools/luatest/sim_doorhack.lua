-- sim_doorhack.lua — проверка взлома дверей экспериментальным чипом (находка 166):
--   • CHIPS.HasDoorHack находит чип (enabled / true / "включен" / DOOR в имени);
--   • серверный hackDoor открывает/разблокирует дверь (PlayerUse/KeyPress IN_USE);
--   • HUD-подсказка «НАЖМИТЕ E — ВЗЛОМАТЬ» рисуется при наличии чипа взлома;
--   • net.Receive("GRM_AugChip_RequestSync") зарегистрирован (раньше не было).
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function SysTime() return 1000 end
function math.random() return 1 end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
math.Clamp = math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
string.Trim = string.Trim or function(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
string.Normalize = string.Normalize or function(s) return s end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
IN_USE = 5

local H = { hooks = {}, netrecv = {}, netlog = {}, seq = {}, timerFns = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
timer = {
  Create = function(_, _, _, fn) H.timerFns[#H.timerFns + 1] = fn end,
  Simple = function(_, fn) if fn then fn() end end,
  Remove = function() end,
}
concommand = { Add = function() end }
util = {
  AddNetworkString = function() end,
  CRC = function(s) return tostring(#s) end,
  TableToJSON = function() return "{}" end,
  JSONToTable = function() return nil end,
  IsValidModel = function() return true end,
}
net = {
  Start = function(m) H.netlog.cur = { msg = m } end,
  WriteString = function() end, WriteTable = function() end, WriteEntity = function() end,
  WriteUInt = function() end, WriteBool = function() end, WriteData = function() end,
  Send = function() H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end,
  Broadcast = function() H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end,
  Receive = function(m, fn) H.netrecv[m] = fn end,
  ReadString = function() return tostring(table.remove(H.seq, 1) or "") end,
  ReadEntity = function() return table.remove(H.seq, 1) end,
  ReadTable = function() return table.remove(H.seq, 1) or {} end,
  ReadUInt = function() return tonumber(table.remove(H.seq, 1) or 0) end,
  ReadData = function() return "" end,
}
local __files = {}
file = {
  CreateDir = function() end,
  Exists = function(p) return __files[p] ~= nil end,
  Read = function(p) return __files[p] end,
  Write = function(p, s) __files[p] = s end,
  Find = function() return {} end,
}
game = { GetMap = function() return "gm_test" end }
player = { GetAll = function() return {} end }
ents = { GetAll = function() return {} end }

-- ── игрок ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "SteamID" then return function(s) return s.sid end
  elseif k == "SteamID64" then return function(s) return s.s64 end
  elseif k == "IsSuperAdmin" then return function() return false end
  elseif k == "IsPlayer" then return function() return true end
  elseif k == "GetPos" then return function(s) return s.pos or { x = 0, y = 0, z = 0 } end

  elseif k == "GetEyeTrace" then return function(s) return { Entity = s.aimEntity, HitPos = s.aimPos or { x = 0, y = 0, z = 0 } } end
  elseif k == "EyePos" then return function(s) return s.pos or { x = 0, y = 0, z = 0 } end
  elseif k == "EmitSound" then return function() end
  elseif k == "Notify" then return function() end
  elseif k == "ChatPrint" then return function() end
  elseif k == "TakeDamage" then return function() end
  elseif k == "SetWalkSpeed" or k == "SetRunSpeed" or k == "SetMaxHealth" or k == "SetHealth"
      or k == "SetArmor" or k == "SetNWInt" or k == "SetNWFloat" or k == "SetNWString"
      or k == "SetNWBool" or k == "Freeze" or k == "SetSequence" or k == "ResetSequence"
      or k == "SetPlaybackRate" or k == "SetModelScale" or k == "SetModel" or k == "SetSkin"
      or k == "SetColor" or k == "SetMaterial" or k == "SetRenderMode" or k == "SetLOD"
      or k == "DrawShadow" or k == "SetNoDraw" or k == "SetPos" or k == "SetAngles" then
    return function() end
  elseif k == "GetMaxHealth" then return function() return 100 end
  elseif k == "Health" then return function() return 100 end
  elseif k == "Armor" then return function() return 0 end
  elseif k == "GetNWInt" then return function() return 0 end
  elseif k == "GetNWFloat" then return function() return 0 end
  elseif k == "GetNWString" then return function() return "" end
  elseif k == "GetNWBool" then return function() return false end
  elseif k == "AccountID" then return function() return 1 end
  elseif k == "UserID" then return function() return 1 end
  elseif k == "LookupBone" then return function() return 0 end
  elseif k == "GetBoneMatrix" then return function() return nil end
  elseif k == "Alive" then return function() return true end
  elseif k == "IsDormant" then return function() return false end
  elseif k == "IsValid" then return function() return true end
  end
  return nil
end
local POSMT = {}
POSMT.__index = function(t, k)
  if k == "DistToSqr" then
    return function(self, o)
      local a, b = self, o or { x = 0, y = 0, z = 0 }
      local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
      return dx * dx + dy * dy + dz * dz
    end
  end
  return nil
end
local function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, POSMT) end
local function mkPly(sid, s64) return setmetatable({ sid = sid, s64 = s64, pos = vec3(0, 0, 0) }, PMT) end

-- ── дверь ──
local DMT = {}
DMT.__index = function(t, k)
  if k == "GetClass" then return function(s) return s.cls end
  elseif k == "GetPos" then return function() return { x = 0, y = 0, z = 0 } end
  elseif k == "EntIndex" then return function(s) return s.idx end
  elseif k == "Fire" then return function(s, act) s.fired = s.fired or {} s.fired[#s.fired + 1] = act end
  elseif k == "GetInternalVariable" then return function() return 1 end
  end
  return nil
end
local function mkDoor(cls, idx) return setmetatable({ cls = cls, idx = idx, __valid = true }, DMT) end

-- ── мок фракций/GRM ──
Factions = {}
GRM = GRM or {}
GRM.Identity = { CharacterKey = function(p) return p.s64 .. ":char1" end }
GRM.Notify = function() end

-- ══════════════ ЗАГРУЗКА ЧИПОВ ══════════════
dofile("lua/autorun/sh_grm_augmentation_chips.lua")
ok(GRM.AugChips ~= nil and GRM.AugChips.HasDoorHack ~= nil, "CHIPS.HasDoorHack определён")
ok(H.netrecv["GRM_AugChip_RequestSync"] ~= nil, "net.Receive GRM_AugChip_RequestSync зарегистрирован (раньше отсутствовал)")

-- ══════════════ 1. HasDoorHack ══════════════
local ply = mkPly("STEAM_0:1:5", "76561198000000005")
-- без чипов
ok(GRM.AugChips.HasDoorHack(ply) == nil, "без чипов — nil")

-- чип без doorHack (пишем напрямую в хранилище — GetPlayerChips возвращает копию)
local charKey = "76561198000000005:char1"
GRM.AugChips.PlayerChips[charKey] = { { id = "c1", name = "Ускорение", category = "civilian", implanted = true, active = true, modifiers = { speed = 1.5 } } }
ok(GRM.AugChips.HasDoorHack(ply) == nil, "гражданский чип без doorHack — nil")

-- experimental с doorHack="enabled"
local chips = GRM.AugChips.PlayerChips[charKey]
chips[2] = { id = "c2", name = "Эксперимент", category = "experimental", implanted = true, active = true, modifiers = { doorHack = "enabled" } }
ok(GRM.AugChips.HasDoorHack(ply) ~= nil, "experimental doorHack=enabled — найден")

-- doorHack="включен" (рус.)
chips[2].modifiers.doorHack = "включен"
ok(GRM.AugChips.HasDoorHack(ply) ~= nil, "doorHack=включен (рус.) — найден")

-- doorHack=true
chips[2].modifiers.doorHack = true
ok(GRM.AugChips.HasDoorHack(ply) ~= nil, "doorHack=true — найден")

-- DOOR в имени (легаси)
chips[2].modifiers.doorHack = "disabled"
chips[2].name = "DOOR BREAKER"
ok(GRM.AugChips.HasDoorHack(ply) ~= nil, "DOOR в имени — найден (легаси)")

-- неактивный чип — НЕ найден
chips[2].active = false
ok(GRM.AugChips.HasDoorHack(ply) == nil, "неактивный чип — nil")
chips[2].active = true

-- ══════════════ 2. ВЗЛОМ ДВЕРИ (сервер) ══════════════
-- хук PlayerUse/KeyPress вызывает hackDoor; дверь должна открыться/разблокироваться
local door = mkDoor("func_door", 10)
ply.aimEntity = door
local keyHook = nil
for _, fn in pairs(H.hooks["KeyPress"] or {}) do
  if fn then keyHook = fn end
end
ok(keyHook ~= nil, "KeyPress-хук взлома на месте")
keyHook(ply, IN_USE or 5)
ok(door.fired and #door.fired > 0, "дверь получила Fire-команды (Unlock/Open/Toggle)")
local joined = table.concat(door.fired or {}, ",")
ok(joined:find("Unlock", 1, true) ~= nil and joined:find("Open", 1, true) ~= nil, "дверь разблокирована и открыта")
ok(door.GRMHackUntil ~= nil and door.GRMHackUntil > CurTime(), "GRMHackUntil установлен")

-- повторный взлом в течение окна — без повторных Fire (guard)
door.fired = {}
keyHook(ply, IN_USE or 5)
ok(#(door.fired or {}) == 0, "повторный взлом в окне не дублирует Fire")

-- дверь вне досягаемости (>180 юнитов)
local far = mkDoor("func_door", 11)
local farPly = mkPly("STEAM_0:1:6", "76561198000000006")
farPly.pos = vec3(0, 0, 500)
farPly.aimEntity = far
GRM.AugChips.PlayerChips["76561198000000006:char1"] = { { id = "c9", name = "Взломщик", category = "experimental", implanted = true, active = true, modifiers = { doorHack = "enabled" } } }
keyHook(farPly, IN_USE or 5)
ok(far.fired == nil, "дверь далеко — не взломана")

-- без чипа — не взламывает
local noChipPly = mkPly("STEAM_0:1:7", "76561198000000007")
noChipPly.aimEntity = mkDoor("func_door", 12)
keyHook(noChipPly, IN_USE or 5)
ok(GRM.AugChips.GetPlayerChips(noChipPly)[1] == nil, "у игрока нет чипов")

-- ══════════════ 3. HUD-подсказка (клиентский код) ══════════════
-- Проверяем, что в cl_grm_augmentations_hud.lua подсказка использует HasDoorHack
local f = assert(io.open("lua/autorun/client/cl_grm_augmentations_hud.lua", "rb"))
local cl = f:read("*a") f:close()
ok(cl:find("HasDoorHack", 1, true) ~= nil, "HUD-подсказка использует CHIPS.HasDoorHack")
ok(cl:find("НАЖМИТЕ E — ВЗЛОМАТЬ", 1, true) ~= nil, "текст подсказки «НАЖМИТЕ E — ВЗЛОМАТЬ» на месте")
ok(cl:find("включен", 1, true) ~= nil, "подсказка учитывает doorHack=включен (рус.)")

-- ══════════════ 3.5 ПЕРЕПРОГРАММИРОВАНИЕ: doorHack сохраняется ══════════════
-- Серверный Reprogram фильтрует модификаторы по category.allowed — раньше
-- doorHack не был в allowed у experimental и ОТБРАСЫВАЛСЯ («применяет, но не
-- запоминает»). Проверяем, что теперь проходит.
local chipsR = GRM.AugChips.PlayerChips[charKey]
local chipR = chipsR[2]
chipR.modifiers = { speed = 1.5 } -- без doorHack
chipR.category = "experimental"
local recvReprogram = H.netrecv["GRM_AugChip_Reprogram"]
ok(recvReprogram ~= nil, "net.Receive GRM_AugChip_Reprogram зарегистрирован")
-- эмулируем запрос: id + modifiers с doorHack="enabled"
H.seq = { chipR.id, { doorHack = "enabled", speed = 1.5 } }
recvReprogram(0, ply)
ok(chipR.modifiers.doorHack == "enabled", "Reprogram сохраняет doorHack=enabled в модификаторы чипа")
ok(chipR.modifiers.speed == 1.5, "Reprogram сохраняет числовые модификаторы")

-- CreateChip: experimental с doorHack проходит
H.seq = { "Чип взлома", "experimental", { doorHack = "enabled" }, 1 }
local recvCreate = H.netrecv["GRM_AugChip_Create"]
ok(recvCreate ~= nil, "net.Receive GRM_AugChip_Create зарегистрирован")
-- (CreateChip вызывается через net; просто проверим прямо)
local okC, chipC = GRM.AugChips.CreateChip(ply, { name = "Взломщик2", category = "experimental", modifiers = { doorHack = "enabled" } })
ok(okC == true and chipC and chipC.modifiers and chipC.modifiers.doorHack == "enabled", "CreateChip experimental: doorHack проходит в чип")

-- Клиентский OpenReprogram берёт ВЫБРАННОЕ значение комбобокса (не старое)
local fint = assert(io.open("lua/autorun/client/cl_grm_augmentation_interface.lua", "rb"))
local intf = fint:read("*a") fint:close()
ok(intf:find("GetSelected", 1, true) ~= nil, "OpenReprogram использует GetSelected для комбобокса (не старое значение)")

-- ══════════════ 4. SyncChips по запросу ══════════════
H.netlog = {}
local reqRecv = H.netrecv["GRM_AugChip_RequestSync"]
ok(reqRecv ~= nil, "обработчик RequestSync есть")
reqRecv(0, ply)
local sent = false
for _, e in ipairs(H.netlog) do if e.msg == "GRM_AugChip_Sync" then sent = true break end end
ok(sent, "по RequestSync сервер шлёт GRM_AugChip_Sync клиенту")

print(("DOORHACK: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
