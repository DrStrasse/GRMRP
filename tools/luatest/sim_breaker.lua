-- sim_breaker.lua — проверка «Взломщика» ds_lockpick (находка 174):
--   • модель C4 (w_c4.mdl), новое название, holdtype grenade;
--   • цели: grm_keypad, grm_scanner, FFD/sliding-двери, обычные двери
--     (включая обёртку через GetParent);
--   • QTE: сервер ставит метку старта, успех требует минимального времени,
--     дистанция, взломщик в руках; применение хака по типу цели;
--   • клиент: прогресс-бар, 5 пинов, отмена.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return _G.__now or 1000 end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
local VMT = {
  __index = function(t, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
  end,
  __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
  __mul = function(a, b) if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end,
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
MASK_SHOT = 0

-- ── мок окружения ──
local netLog = { lastStart = nil, lastEntity = nil, lastBool = nil, lastSend = nil }
net = {
  Start = function(name) netLog.lastStart = name end,
  WriteEntity = function(e) netLog.lastEntity = e end,
  WriteBool = function(b) netLog.lastBool = b end,
  Send = function(ply) netLog.lastSend = ply end,
  SendToServer = function() end,
  Receive = function(name, fn) netLog.recv = netLog.recv or {} netLog.recv[name] = fn end,
  ReadEntity = function() return netLog.lastEntity end,
  ReadBool = function() return netLog.lastBool end,
}
util = { AddNetworkString = function() end, TraceLine = function(t) return { Entity = _G.__aimEnt } end }
hook = { Add = function(n, id, fn) netLog.hooks = netLog.hooks or {} netLog.hooks[n] = netLog.hooks[n] or {} netLog.hooks[n][id] = fn end, Run = function() end }

-- ── мок игрока ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "GetShootPos" then return function() return Vector(0, 0, 0) end
  elseif k == "GetAimVector" then return function() return Vector(1, 0, 0) end
  elseif k == "GetPos" then return function() return Vector(0, 0, 0) end
  elseif k == "GetActiveWeapon" then return function(s) return s.__wep end
  elseif k == "GetClass" then return function() return "player" end
  elseif k == "EmitSound" then return function() end
  end
  return nil
end
local function mkPly(wep) return setmetatable({ __wep = wep or nil, __valid = true }, PMT) end

-- ── мок сущностей ──
local EMT = {}
EMT.__index = function(t, k)
  if k == "GetClass" then return function(s) return s.__cls end
  elseif k == "GetParent" then return function(s) return s.__parent end
  elseif k == "GetPos" then return function() return Vector(0, 0, 0) end
  elseif k == "GetClassKey" then return function() end
  end
  return nil
end
local function mkEnt(cls, extra)
  local e = setmetatable({ __cls = cls, __valid = true, __parent = nil }, EMT)
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

-- ── мок GRM.Doors ──
local doorLog = { locked = {}, opened = {} }
GRM = GRM or {}
GRM.Notify = function() end
GRM.Doors = {
  IsDoor = function(e) return IsValid(e) and (e.__cls == "prop_door_rotating" or e.__cls == "func_door") end,
  LockDoor = function(e, locked) doorLog.locked[e] = locked end,
  GetPartnerDoor = function() return nil end,
}

-- ── загрузка свапа ──
SWEP = { Primary = {}, Secondary = {} }
dofile("lua/weapons/ds_lockpick/shared.lua")
local SW = SWEP
ok(SW.WorldModel == "models/weapons/w_c4.mdl", "WorldModel = w_c4.mdl (бомба)")
ok(SW.ViewModel:find("c_c4", 1, true) ~= nil, "ViewModel = c_c4")
ok(SW.PrintName == "Взломщик", "PrintName = Взломщик")
ok(SW.HoldType == "slam", "HoldType = slam (как у weapon_slam, находка 176c)")

-- ── GetAimedTarget ──
local wep = setmetatable({}, { __index = SW })
wep.__valid = true
wep.GetClass = function() return "ds_lockpick" end
wep.SetNextPrimaryFire = function() end
wep.SetHoldType = function() end
wep.GetOwner = function() return _G.__owner end
local ply = mkPly(wep)
_G.__owner = ply

_G.__aimEnt = mkEnt("grm_keypad")
ok(wep:GetAimedTarget() == _G.__aimEnt, "цель: grm_keypad")
_G.__aimEnt = mkEnt("grm_scanner")
ok(wep:GetAimedTarget() == _G.__aimEnt, "цель: grm_scanner")
_G.__aimEnt = mkEnt("prop_physics", { isFadingDoor = true })
ok(wep:GetAimedTarget() == _G.__aimEnt, "цель: FFD-дверь (isFadingDoor)")
_G.__aimEnt = mkEnt("prop_physics", { isSlidingDoor = true })
ok(wep:GetAimedTarget() == _G.__aimEnt, "цель: sliding-дверь (isSlidingDoor)")
_G.__aimEnt = mkEnt("prop_door_rotating")
ok(wep:GetAimedTarget() == _G.__aimEnt, "цель: обычная дверь")
local kp = mkEnt("grm_keypad")
_G.__aimEnt = mkEnt("prop_dynamic", { __parent = kp })
ok(wep:GetAimedTarget() == kp, "цель через GetParent: кейпад-родитель")
local ffd = mkEnt("prop_physics", { isFadingDoor = true })
_G.__aimEnt = mkEnt("prop_dynamic", { __parent = ffd })
ok(wep:GetAimedTarget() == ffd, "цель через GetParent: FFD-дверь-родитель")
_G.__aimEnt = mkEnt("prop_physics")
ok(wep:GetAimedTarget() == nil, "не-цель (обычный проп) не принимается")

-- ── PrimaryAttack (сервер) ──
_G.__now = 1000
local kp2 = mkEnt("grm_keypad")
_G.__aimEnt = kp2
wep:PrimaryAttack()
ok(netLog.lastStart == "GRM_Breaker_StartQTE", "PrimaryAttack шлёт GRM_Breaker_StartQTE")
ok(netLog.lastEntity == kp2, "в старте передана цель")
ok(ply.__grmBreakerStart == 1000, "сервер поставил метку старта взлома")
-- повторный вызов в кулдауне не шлёт
netLog.lastStart = nil
wep:PrimaryAttack()
ok(netLog.lastStart == nil, "повторный клик в кулдауне 0.8с игнорируется")
_G.__now = 1001
netLog.lastStart = nil
wep:PrimaryAttack()
ok(netLog.lastStart == "GRM_Breaker_StartQTE", "после кулдауна снова можно")

-- ── Серверная обработка результата ──
local recv = netLog.recv["GRM_Breaker_FinishQTE"]
ok(recv ~= nil, "обработчик GRM_Breaker_FinishQTE зарегистрирован")

-- 1. Кейпад: успех → ProcessGrant
local granted = 0
local kp3 = mkEnt("grm_keypad", { ProcessGrant = function() granted = granted + 1 end, IsKeypadLocked = function() return false end })
ply2 = mkPly(wep)
ply2.__grmBreakerStart = 1000
_G.__now = 1003  -- >= MIN_HACK (2.0)
netLog.lastEntity, netLog.lastBool = kp3, true
recv(0, ply2)
ok(granted == 1, "успех по кейпаду → ProcessGrant")

-- 2. Анти-чит: слишком быстро → нет применения
local granted2 = 0
local kp4 = mkEnt("grm_keypad", { ProcessGrant = function() granted2 = granted2 + 1 end, IsKeypadLocked = function() return false end })
local ply3 = mkPly(wep)
ply3.__grmBreakerStart = 1000
_G.__now = 1001  -- меньше MIN_HACK
netLog.lastEntity, netLog.lastBool = kp4, true
recv(0, ply3)
ok(granted2 == 0, "успех раньше минимального времени QTE отклонён (анти-чит)")

-- 3. Сканер: успех → ProcessGrant
local scanned = 0
local sc1 = mkEnt("grm_scanner", { ProcessGrant = function(self, ply, fac) scanned = scanned + 1 end })
local ply4 = mkPly(wep)
ply4.__grmBreakerStart = 1000
_G.__now = 1003
netLog.lastEntity, netLog.lastBool = sc1, true
recv(0, ply4)
ok(scanned == 1, "успех по сканеру → ProcessGrant (обход фракции)")

-- 4. FFD-дверь: успех → FadeActivate
local faded = 0
local ffd2 = mkEnt("prop_physics", { isFadingDoor = true, FadeActivate = function() faded = faded + 1 end })
local ply5 = mkPly(wep)
ply5.__grmBreakerStart = 1000
_G.__now = 1003
netLog.lastEntity, netLog.lastBool = ffd2, true
recv(0, ply5)
ok(faded == 1, "успех по FFD-двери → FadeActivate")

-- 5. Обычная дверь: разблокировка + открытие
local dr1 = mkEnt("prop_door_rotating", { Fire = function(self, ev, _, _) doorLog.opened[ev] = true end })
local ply6 = mkPly(wep)
ply6.__grmBreakerStart = 1000
_G.__now = 1003
netLog.lastEntity, netLog.lastBool = dr1, true
recv(0, ply6)
ok(doorLog.locked[dr1] == false, "обычная дверь разблокирована (LockDoor false)")
ok(doorLog.opened["Open"] == true, "обычная дверь открыта (Fire Open)")

-- 6. Неудача: уведомление, цель не тронута
local granted3 = 0
local kp5 = mkEnt("grm_keypad", { ProcessGrant = function() granted3 = granted3 + 1 end, IsKeypadLocked = function() return false end })
local ply7 = mkPly(wep)
ply7.__grmBreakerStart = 1000
_G.__now = 1003
netLog.lastEntity, netLog.lastBool = kp5, false
recv(0, ply7)
ok(granted3 == 0, "неудача → цель не взломана")

-- 7. Взломщик не в руках → отказ
local granted4 = 0
local kp6 = mkEnt("grm_keypad", { ProcessGrant = function() granted4 = granted4 + 1 end, IsKeypadLocked = function() return false end })
local ply8 = mkPly(mkEnt("weapon_pistol"))
ply8.__grmBreakerStart = 1000
_G.__now = 1003
netLog.lastEntity, netLog.lastBool = kp6, true
recv(0, ply8)
ok(granted4 == 0, "без взломщика в руках успех не применяется")

-- ── Клиентская часть: статические проверки ──
local src = assert(io.open("lua/weapons/ds_lockpick/shared.lua", "rb"))
local code = src:read("*a") src:close()
ok(code:find("ПРОГРЕСС ВЗЛОМА", 1, true) ~= nil, "клиент: прогресс-бар взлома")
ok(code:find("maxPins = 5", 1, true) ~= nil, "клиент: 5 пинов")
ok(code:find("GRM_Breaker_FinishQTE", 1, true) ~= nil, "клиент: шлёт результат")
ok(code:find("cancelQTE", 1, true) ~= nil, "клиент: отмена взлома")
ok(code:find("ВЗЛОМ СКАНЕРА", 1, true) ~= nil, "клиент: заголовок для сканера")
ok(code:find("c4_disarm", 1, true) ~= nil, "клиент: звук c4_disarm при успехе")
ok(not code:find("LerpColor(", 1, true), "клиент: нет вызова глобального LerpColor (находка 176b)")
ok(code:find("local function lerpColor", 1, true) ~= nil, "клиент: своя функция lerpColor определена")

-- ── Вендор/инвентарь ──
local v = assert(io.open("lua/autorun/sh_grm_vendor.lua", "rb"))
local vCode = v:read("*a") v:close()
ok(vCode:find('["ds_lockpick"]', 1, true) ~= nil and vCode:find("Взломщик (QTE)", 1, true) ~= nil and vCode:find("w_c4.mdl", 1, true) ~= nil, "вендор: взломщик с моделью C4")
local inv = assert(io.open("lua/autorun/sh_grm_inventory.lua", "rb"))
local invCode = inv:read("*a") inv:close()
ok(invCode:find('name = "Взломщик"', 1, true) ~= nil, "инвентарь: предмет переименован")

-- ── КЛИЕНТСКАЯ ВЕТКА: файл должен загружаться без ошибок и в CLIENT-режиме
-- (ловит индексацию upvalue-функций, найденную владельцем на живом сервере)
SERVER, CLIENT = false, true
surface = { CreateFont = function() end, PlaySound = function() end, SetDrawColor = function() end, DrawRect = function() end, DrawOutlinedRect = function() end, SetFont = function() end, GetTextSize = function() return 10, 10 end }
draw = { RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end }
vgui = { Create = function() return { __valid = true, SetTitle = function() end, SetSize = function() end, Center = function() end, MakePopup = function() end, ShowCloseButton = function() end, Close = function() end, Paint = function() end, OnKeyCodePressed = function() end, Think = function() end } end }
LocalPlayer = function() return mkPly(wep) end
function FrameTime() return 0.1 end
function FrameNumber() return 1 end
SWEP = { Primary = {}, Secondary = {} }
local cliOK, cliErr = pcall(dofile, "lua/weapons/ds_lockpick/shared.lua")
ok(cliOK, "клиентская ветка загружается без ошибок" .. (cliErr and (" (" .. tostring(cliErr) .. ")") or ""))
ok(netLog.recv and netLog.recv["GRM_Breaker_StartQTE"] ~= nil, "клиент зарегистрировал приём старта QTE")
ok(netLog.recv and netLog.recv["GRM_Breaker_FinishQTE"] ~= nil, "серверный обработчик результата на месте")

print(string.format("sim_breaker: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
