-- sim_customization_render.lua — функциональная проверка отрисовки аксессуаров
-- (находка 175):
--   • свои аксессуары от 1-го лица НЕ рисуются никогда (ShouldDrawLocalPlayer gate);
--   • от 3-го лица на себя рисуются;
--   • аксессуары других игроков рисуются всегда (и от 1-го, и от 3-го лица);
--   • opaque-fallback перебирает ВСЕХ игроков (фонарик F больше не прячет
--     аксессуары остальных), guard не даёт двойного DrawModel в кадре.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = false, true
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function FrameTime() return 0.1 end
function FrameNumber() return _G.__frame or 1000 end
function SysTime() return 1000 end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function math.NormalizeAngle(a) a = a % 360 if a > 180 then a = a - 360 end return a end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
function Lerp(t, a, b) return a + (b - a) * t end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
RENDERGROUP_BOTH = 0
MASK_SOLID = 0

local VMT = {
  __index = function(t, k)
    if k == "AngleEx" then return function() return Angle(0, 0, 0) end end
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
  end,
  __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
  __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
  __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
  __mul = function(a, b) if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end,
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
local AMT = {
  __index = function(t, k)
    if k == "Forward" then return function() return Vector(1, 0, 0) end
    elseif k == "Right" then return function() return Vector(0, 1, 0) end
    elseif k == "Up" then return function() return Vector(0, 0, 1) end end
    return nil
  end,
}
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AMT) end

function LerpVector(t, a, b) return Vector(Lerp(t, a.x, b.x), Lerp(t, a.y, b.y), Lerp(t, a.z, b.z)) end
function LerpAngle(t, a, b) return Angle(Lerp(t, a.p, b.p), Lerp(t, a.y, b.y), Lerp(t, a.r, b.r)) end
function ScrW() return 1920 end
function ScrH() return 1080 end

-- ── мок окружения ──
local H = { hooks = {}, netrecv = {}, timers = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
net = {
  Start = function() end, WriteString = function() end, WriteUInt = function() end, WriteTable = function() end,
  SendToServer = function() end, Send = function() end, Broadcast = function() end,
  Receive = function(n, fn) H.netrecv[n] = fn end,
  ReadEntity = function() return nil end, ReadString = function() return "" end, ReadTable = function() return {} end, ReadBool = function() return false end, ReadUInt = function() return 0 end,
}
timer = { Create = function(n, _, _, fn) H.timers[n] = fn end, Simple = function() end }
util = { AddNetworkString = function() end, IsValidModel = function(m) return type(m) == "string" and m:find("^models/", 1) ~= nil end }
surface = { CreateFont = function() end, PlaySound = function() end, SetFont = function() end, GetTextSize = function() return 10, 10 end }
draw = { RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end, DrawLine = function() end, DrawWireframeSphere = function() end }
render = { SetColorMaterial = function() end, DrawLine = function() end, DrawWireframeSphere = function() end }
notification = { AddLegacy = function() end }
os = { date = function() return "" end }
concommand = { Add = function() end }

-- заглушка vgui-панели: любой метод — функция-заглушка
local PANEL = {}
PANEL.__index = function(t, k)
  local v = function() return PANEL_STUB end
  rawset(t, k, v)
  return v
end
PANEL_STUB = setmetatable({ __valid = true }, PANEL)
vgui = { Create = function() return setmetatable({ __valid = true }, PANEL) end }

-- счётчик реальных DrawModel хранится в самом ent (draws)
local function mkRenderEnt()
  local e = { __valid = true, draws = 0 }
  function e:SetNoDraw() end
  function e:SetSkin() end
  function e:SetColor() end
  function e:SetMaterial() end
  function e:SetRenderMode() end
  function e:SetLOD() end
  function e:DrawShadow() end
  function e:Remove() end
  function e:SetModelScale() end
  function e:SetRenderOrigin() end
  function e:SetRenderAngles() end
  function e:SetupBones() end
  function e:DrawModel() self.draws = self.draws + 1 end
  return e
end
ClientsideModel = function() return mkRenderEnt() end

-- ── мок игроков ──
local matrixStub = { GetAngles = function() return Angle(0, 0, 0) end, GetTranslation = function() return Vector(0, 0, 0) end }
local PMT = {}
PMT.__index = function(t, k)
  if k == "IsPlayer" then return function() return true end
  elseif k == "Alive" then return function(s) return s.alive end
  elseif k == "IsDormant" then return function(s) return s.dormant end
  elseif k == "GetPos" then return function() return Vector(0, 0, 0) end
  elseif k == "ShouldDrawLocalPlayer" then return function(s) return s.shouldDraw end
  elseif k == "LookupBone" then return function() return 1 end
  elseif k == "GetBoneMatrix" then return function() return matrixStub end
  elseif k == "GetClass" then return function() return "player" end
  elseif k == "SetupBones" then return function() end
  end
  return nil
end
local function mkPly(shouldDraw)
  return setmetatable({ __valid = true, alive = true, dormant = false, shouldDraw = shouldDraw == true }, PMT)
end
_G.__lp = nil
LocalPlayer = function() return _G.__lp end
_G.__players = {}
player = { GetAll = function() return _G.__players end }

-- ── загрузка клиентского модуля ──
GRM = { UI = { Track = function() end, Close = function() end } }
dofile("lua/autorun/client/cl_grm_customization.lua")
local C = GRM.Customization
-- удобство: draws игрока через его render-кэш
local function entOf(ply) return C.RenderCache[ply] and C.RenderCache[ply].head and C.RenderCache[ply].head.ent end
local function drawsOf(ply) local e = entOf(ply) return e and e.draws or 0 end

C.Catalog = {
  hat = { id = "hat", name = "Шляпа", model = "models/props_c17/doll01.mdl", bone = "ValveBiped.Bip01_Head1", position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 }, scale = 1 },
}
local loadout = { head = { accessoryID = "hat", bone = "ValveBiped.Bip01_Head1", position = { x = 0, y = 0, z = 0 }, angles = { p = 0, y = 0, r = 0 }, scale = 1 } }

local fallback = H.hooks["PostDrawOpaqueRenderables"]["GRM_Customization_DrawAccessoriesOpaque"]
local postPlayerDraw = H.hooks["PostPlayerDraw"]["GRM_Customization_DrawAccessories"]
ok(fallback ~= nil and postPlayerDraw ~= nil, "хуки отрисовки зарегистрированы")

-- сценарий: lp в 1-м лице, рядом другой игрок
local lp = mkPly(false)
local p2 = mkPly(false)
_G.__lp = lp
_G.__players = { lp, p2 }
C.ClientLoadouts[lp]=loadout;C.ActiveRenderPlayers[lp]=true
C.ClientLoadouts[p2]=loadout;C.ActiveRenderPlayers[p2]=true

-- ═══ КАДР 1000: lp в 1-м лице, fallback (фонарик-проход) ═══
_G.__frame = 1000
fallback(false, false, false)
local entP2 = entOf(p2)
local entLp = entOf(lp)
ok(IsValid(entP2), "аксессуар другого игрока получил ClientsideModel")
ok(entLp == nil, "свои аксессуары от 1-го лица НЕ создали модель (gate в drawAccessories)")
ok(drawsOf(p2) == 1, "аксессуар другого игрока отрисован (fallback, 1-е лицо смотрящего)")
ok(drawsOf(lp) == 0, "свои аксессуары от 1-го лица НЕ отрисованы")

-- ═══ КАДР 1001: lp в 3-м лице → fallback рисует и его ═══
lp.shouldDraw = true
_G.__frame = 1001
fallback(false, false, false)
entLp = entOf(lp)
ok(IsValid(entLp), "при 3-м лице свои аксессуары получили модель")
ok(drawsOf(lp) == 1 and drawsOf(p2) == 2, "в новом кадре отрисованы и lp (3-е лицо), и другой игрок")

-- ═══ КАДР 1002: повторный fallback в том же кадре — guard ═══
fallback(false, false, false)
ok(drawsOf(p2) == 2 and drawsOf(lp) == 1, "guard: в одном кадре нет второго DrawModel")

-- ═══ КАДР 1003: PostPlayerDraw для lp от 3-го лица — рисует ═══
_G.__frame = 1003
postPlayerDraw(lp)
ok(drawsOf(lp) == 2, "PostPlayerDraw рисует lp от 3-го лица")

-- ═══ КАДР 1004: lp вернулся в 1-е лицо — PostPlayerDraw и fallback не рисуют ═══
lp.shouldDraw = false
_G.__frame = 1004
postPlayerDraw(lp)
fallback(false, false, false)
ok(drawsOf(lp) == 2, "ни PostPlayerDraw, ни fallback не рисуют lp от 1-го лица")
ok(drawsOf(p2) == 3, "другие игроки при этом рисуются всегда")

-- ═══ КАДР 1005: PostPlayerDraw других игроков ═══
_G.__frame = 1005
postPlayerDraw(p2)
ok(drawsOf(p2) == 4, "PostPlayerDraw рисует других игроков (1-е лицо смотрящего)")

print(string.format("sim_customization_render: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
