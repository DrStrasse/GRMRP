-- sim_sliding_door.lua — проверка раздвижных дверей (находка 173):
--   • SD.Apply вешает механизм (isSlidingDoor, поля, методы Fade*);
--   • FadeActivate/FadeDeactivate меняют target, Think двигает проп;
--   • GRM.FFDLink.Fade активирует sliding-двери;
--   • keypad/scanner содержат isSlidingDoor;
--   • перм Extract/Apply prop_physics сохраняют sliding-конфиг;
--   • тул grm_sliding_door существует и в Q-меню.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function SysTime() return 1000 end
function math.random() return 1 end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
string.Trim = string.Trim or function(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
string.StartWith = string.StartWith or function(s, p) return string.sub(s, 1, #p) == p end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end

-- Векторы
local VMT = {}
VMT.__index = function(t, k)
  if k == "Distance" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return math.sqrt(dx * dx + dy * dy + dz * dz) end end
  return nil
end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VMT.__mul = function(a, b) if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
local AMT = {}
AMT.__index = function(t, k)
  if k == "Right" then return function() return Vector(1, 0, 0) end
  elseif k == "Forward" then return function() return Vector(0, 1, 0) end
  elseif k == "Up" then return function() return Vector(0, 0, 1) end
  end
  return nil
end
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AMT) end

local H = { hooks = {}, netrecv = {}, timerFns = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
timer = { Create = function(_, _, _, fn) H.timerFns[#H.timerFns + 1] = fn end, Simple = function(_, fn) if fn then fn() end end, Remove = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return nil end, CRC = function(s) return tostring(#s) end }
net = {
  Start = function() end, WriteString = function() end, WriteTable = function() end, WriteUInt = function() end,
  WriteBool = function() end, WriteData = function() end, Send = function() end, Broadcast = function() end,
  Receive = function() end, ReadString = function() return "" end, ReadTable = function() return {} end,
  ReadUInt = function() return 0 end,
}
game = { GetMap = function() return "gm" end }
ents = { GetAll = function() return {} end, Create = function() return { __valid = true } end }
file = { CreateDir = function() end, Exists = function() return false end, Read = function() return nil end, Write = function() end, Find = function() return {} end }
player = { GetAll = function() return {} end }
duplicator = { StoreEntityModifier = function() end, RegisterEntityModifier = function() end }
numpad = { Register = function() end, OnDown = function() end, OnUp = function() end, Remove = function() end, Activate = function() end, Deactivate = function() end }
Factions = {}
GRM = GRM or {}
GRM.Identity = {}
GRM.Notify = function() end

-- мок пропа
local PMT = {}
PMT.__index = function(t, k)
  if k == "GetClass" then return function() return "prop_physics" end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  elseif k == "SetPos" then return function(s, v) s.pos = v end
  elseif k == "GetAngles" then return function() return Angle(0, 0, 0) end
  elseif k == "PhysicsInit" then return function() end
  elseif k == "SetMoveType" then return function() end
  elseif k == "SetSolid" then return function() end
  elseif k == "GetPhysicsObject" then return function(s) s.phys=s.phys or { EnableMotion=function()end,Sleep=function()end,Wake=function()end,SetPos=function(_,v)s.physicsPos=v end,SetAngles=function()end,SetVelocityInstantaneous=function()end };return s.phys end
  elseif k == "CollisionRulesChanged" then return function(s)s.collisionUpdated=true end
  elseif k == "SetNWBool" then return function() end
  elseif k == "IsPlayer" then return function() return false end
  elseif k == "IsNPC" then return function() return false end
  elseif k == "IsWorld" then return function() return false end
  elseif k == "GetModel" then return function() return "models/x.mdl" end
  elseif k == "EmitSound" then return function(s, snd) s._sounds = s._sounds or {} s._sounds[#s._sounds + 1] = snd end
  end
  return nil
end
local function mkProp() return setmetatable({ pos = Vector(0, 0, 0), __valid = true }, PMT) end
local PMT2 = {}
PMT2.__index = function(t, k)
  if k == "SteamID64" then return function() return "76561198000000001" end
  elseif k == "SteamID" then return function() return "STEAM_0:1:1" end
  end
  return nil
end
local function mkPly() return setmetatable({}, PMT2) end

-- ══════════════ ЗАГРУЗКА ══════════════
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_sliding_door.lua")
ok(GRM.SlidingDoor ~= nil and GRM.SlidingDoor.Apply ~= nil, "модуль SlidingDoor загружен")
ok(H.hooks["Think"] and H.hooks["Think"]["GRM_SlidingDoor_Think"], "Think-хук анимации зарегистрирован")

-- ══════════════ 1. Apply ══════════════
local prop = mkProp()
local ply = mkPly()
local okApply, msg = GRM.SlidingDoor.Apply(ply, prop, { direction = "right", distance = 100, speed = 120, smooth = 1, autoclose = true, closeTime = 5 })
ok(okApply == true, "Apply вернул true")
ok(prop.isSlidingDoor == true, "проп помечен isSlidingDoor")
ok(prop.Sliding ~= nil and prop.Sliding.direction == "right" and prop.Sliding.distance == 100, "конфиг сохранён")
ok(prop.Sliding_BasePos.x == 0 and prop.Sliding_OpenPos.x == 100, "openPos = base + 100 по X (вправо)")
ok(isfunction(prop.FadeActivate) and isfunction(prop.FadeDeactivate) and isfunction(prop.FadeToggle), "методы Fade* (совместимость с FFD)")

-- ══════════════ 2. Открытие/закрытие + Think ══════════════
prop.FadeActivate()
ok(prop.Sliding_Open == true, "FadeActivate → открыта")
-- Think: прогресс растёт
local thinkFn = H.hooks["Think"]["GRM_SlidingDoor_Think"]
local T = 1000
local oldCurTime = CurTime
-- эмулируем тики: CurTime растёт
local fakeTime = 1000
_G.CurTime = function() return fakeTime end
thinkFn()
fakeTime = fakeTime + 0.5
thinkFn()
ok(prop.Sliding_Progress > 0, "Think двигает прогресс (прогресс=" .. tostring(prop.Sliding_Progress) .. ")")
ok(prop.pos.x > 0, "проп реально смещается (x=" .. tostring(prop.pos.x) .. ")")
ok(prop.physicsPos and prop.physicsPos.x == prop.pos.x and prop.collisionUpdated==true,"PhysicsObject и collision box смещаются вместе с моделью")
_G.CurTime = oldCurTime

-- ══════════════ 3. Remove ══════════════
GRM.SlidingDoor.Remove(prop)
ok(prop.isSlidingDoor ~= true, "Remove снял механизм")
ok(prop.pos.x == 0, "проп вернулся в basePos")

-- ══════════════ 4. FFD Link совместимость ══════════════
-- повторно применим и проверим, что FFDLink.Fade активирует sliding
GRM.SlidingDoor.Apply(ply, prop, { direction = "left", distance = 80, speed = 100, smooth = 1 })
-- мок ffdlink: грузим реальный sh_grm_ffdlink? Он требует много моков — вместо этого
-- проверим, что код Fade учитывает isSlidingDoor
local ffl = assert(io.open("lua/autorun/sh_grm_ffdlink.lua", "rb"))
local fflCode = ffl:read("*a") ffl:close()
ok(fflCode:find("d.isFadingDoor or d.isSlidingDoor", 1, true) ~= nil, "FFDLink.Fade учитывает sliding")

-- keypad/scanner
local kp = assert(io.open("lua/entities/grm_keypad/init.lua", "rb"))
local kpCode = kp:read("*a") kp:close()
ok(kpCode:find("prop.isFadingDoor or prop.isSlidingDoor", 1, true) ~= nil, "keypad: isSlidingDoor")
local sc = assert(io.open("lua/entities/grm_scanner/init.lua", "rb"))
local scCode = sc:read("*a") sc:close()
ok(scCode:find("prop.isFadingDoor or prop.isSlidingDoor", 1, true) ~= nil, "scanner: isSlidingDoor")

-- ══════════════ 5. ПЕРМ ══════════════
local ffd = assert(io.open("lua/weapons/gmod_tool/stools/ffd_fading_door.lua", "rb"))
local ffdCode = ffd:read("*a") ffd:close()
ok(ffdCode:find('ent.isSlidingDoor and ent.Sliding', 1, true) ~= nil, "перм Extract: sliding-ветка")
ok(ffdCode:find('istable(t.sliding)', 1, true) ~= nil, "перм Apply: sliding-ветка")
ok(ffdCode:find('GRM.SlidingDoor.Apply', 1, true) ~= nil, "перм Apply: вызывает SD.Apply")

-- ══════════════ 6. Тул + Q-меню ══════════════
local tool = assert(io.open("lua/weapons/gmod_tool/stools/grm_sliding_door.lua", "rb"))
local toolCode = tool:read("*a") tool:close()
ok(toolCode:find('TOOL.Name = "#tool.grm_sliding_door.name"', 1, true) ~= nil, "тул grm_sliding_door существует")
ok(toolCode:find("FFD Link", 1, true) ~= nil, "тул упоминает FFD Link")
local q = assert(io.open("lua/autorun/sh_grm_qmenu.lua", "rb"))
local qCode = q:read("*a") q:close()
ok(qCode:find('grm_sliding_door', 1, true) ~= nil, "Q-меню: тул раздвижной двери")

-- ══════════════ 7. FFD Link: isDoor распознаёт sliding-дверь (находка 173c) ══════════════
local fl = assert(io.open("lua/weapons/gmod_tool/stools/ffd_link.lua", "rb"))
local flCode = fl:read("*a") fl:close()
ok(flCode:find('ent.isFadingDoor == true or ent.isSlidingDoor == true', 1, true) ~= nil, "FFD Link: isDoor учитывает isSlidingDoor")

-- ══════════════ 8. ЗВУКИ (находка 173d) ══════════════
local sp = mkProp()
GRM.SlidingDoor.Apply(ply, sp, { direction = "right", distance = 100, speed = 120, smooth = 1, soundOpen = "doors/door_metal_open1.wav", soundClose = "doors/door_metal_close1.wav", soundMove = "doors/door_move1.wav" })
ok(sp.Sliding.soundOpen ~= "" and sp.Sliding.soundClose ~= "" and sp.Sliding.soundMove ~= "", "звуки сохранены в конфиге")
sp.FadeActivate()
local thinkFn2 = H.hooks["Think"]["GRM_SlidingDoor_Think"]
local oldT = _G.CurTime
local ft = 2000
_G.CurTime = function() return ft end
thinkFn2()
ft = ft + 0.5
thinkFn2()  -- в движении: soundMove
ok(sp._sounds and #sp._sounds > 0, "звук движения проигран в процессе")
-- догнать до открытия
for _ = 1, 20 do ft = ft + 0.5 thinkFn2() end
ok(sp.Sliding_Progress >= 1, "дверь открылась")
local hadOpen = false
for _, s in ipairs(sp._sounds or {}) do if s == "doors/door_metal_open1.wav" then hadOpen = true end end
ok(hadOpen, "звук ОТКРЫТИЯ проигран при достижении конца")
sp._sounds = {}
sp.FadeDeactivate()
for _ = 1, 20 do ft = ft + 0.5 thinkFn2() end
ok(sp.Sliding_Progress <= 0, "дверь закрылась")
local hadClose = false
for _, s in ipairs(sp._sounds or {}) do if s == "doors/door_metal_close1.wav" then hadClose = true end end
ok(hadClose, "звук ЗАКРЫТИЯ проигран при достижении начала")
_G.CurTime = oldT

-- перм/тул: звуки
ok(ffdCode:find('soundOpen', 1, true) ~= nil and ffdCode:find('soundMove', 1, true) ~= nil, "перм Extract/Apply хранит звуки")
ok(toolCode:find('grm_sliding_door_soundopen', 1, true) ~= nil, "тул: поле звука открытия")
ok(toolCode:find('grm_sliding_door_soundmove', 1, true) ~= nil, "тул: поле звука движения")

print(("SLIDING DOOR: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
