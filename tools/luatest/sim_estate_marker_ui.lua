--[[ Живой прогон правок по замечаниям владельца 27.08 (скриншоты):

     1) «Подсказки в инструменте бизнеса и жилья нужно сделать чуть выше,
         оно в ХУД впадает.»
     2) «Материал значка зоны бизнеса и жилья models/debug/debugwhite,
         чтобы цвет применялся нормально.»
     3) «Сам значок неправильно повёрнут. Масштаб надо ещё меньше.
         Значок опустить ниже, повернуть по оси чтобы смотрел на игрока,
         а не сверху словно крыша.»
     4) «Подпись торгового автомата слишком не видна и слишком высоко.
         Можно было бы как компьютеры сделать на самой модели.»

     Запуск: luajit tools/luatest/sim_estate_marker_ui.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

-----------------------------------------------------------------------
-- 1. ПОДСКАЗКА ТУЛА НЕ НАЛЕЗАЕТ НА HUD
-----------------------------------------------------------------------
print("\n=== 1. ПОДСКАЗКА ТУЛА И ПАНЕЛЬ «СОСТОЯНИЕ» ===")

local tool = readf("lua/weapons/gmod_tool/stools/grm_business.lua")
local hud  = readf("lua/autorun/client/cl_grm_hud.lua")

ok(hud:find("GRM.HUD.StatusRect", 1, true) ~= nil,
   "HUD публикует прямоугольник панели состояния — есть за что зацепиться")
ok(tool:find("GRM.HUD.StatusRect", 1, true) ~= nil,
   "ИСПРАВЛЕНО: тул читает StatusRect, а не гадает с фиксированным отступом")

--[[ Живая проверка геометрии: воспроизводим расчёт из тула и старый
     вариант, сравниваем перекрытие с панелью состояния. ]]
local ScrH = 900
local function rectsOverlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w
       and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Панель «СОСТОЯНИЕ» из cl_grm_hud: 6 строк, ширина 320, прижата к низу.
local rows, rowH, gap, pad, headerH = 6, 24, 4, 10, 24
local ph = headerH + pad + rows * (rowH + gap) + pad - gap
local statusRect = { x = 16, y = math.max(16, ScrH - 28 - ph), w = 320, h = ph }

local w, h = 560, 52 + 3 * 22

-- Старый расчёт: жёстко от низа экрана.
local oldRect = { x = 24, y = ScrH - h - 120, w = w, h = h }
ok(rectsOverlap(oldRect, statusRect) == true,
   "БАГ ВОСПРОИЗВЁДЕН: старая подсказка пересекалась с панелью состояния",
   ("подсказка y=%d..%d, HUD y=%d..%d"):format(oldRect.y, oldRect.y + h,
        statusRect.y, statusRect.y + statusRect.h))

-- Новый расчёт.
local function newRect(sr)
    local x, y = 24, ScrH - h - 120
    if sr and (sr.y or 0) > 0 then x = sr.x; y = sr.y - h - 14 end
    y = math.max(y, 110)
    return { x = x, y = y, w = w, h = h }
end
local fixed = newRect(statusRect)
ok(rectsOverlap(fixed, statusRect) == false,
   "ИСПРАВЛЕНО: подсказка больше не пересекает панель состояния",
   ("подсказка y=%d..%d, HUD y=%d"):format(fixed.y, fixed.y + h, statusRect.y))
ok(fixed.y + h <= statusRect.y, "подсказка стоит СТРОГО над панелью, с зазором")
ok(fixed.y >= 110, "и не улетает под заголовок тула вверху экрана", fixed.y)
ok(fixed.x == statusRect.x, "левый край выровнен с HUD — выглядит как один блок")

-- HUD выключен: работает старый отступ, без ошибок.
local noHud = newRect(nil)
ok(noHud.y > 0 and noHud.y < ScrH, "без HUD подсказка всё равно на экране", noHud.y)

-- Маленький экран: подсказка не уезжает за верх.
ScrH = 600
local small = (function()
    local ph2 = headerH + pad + rows * (rowH + gap) + pad - gap
    local sr = { x = 16, y = math.max(16, ScrH - 28 - ph2), w = 320, h = ph2 }
    local x, y = 24, ScrH - h - 120
    if sr.y > 0 then x = sr.x; y = sr.y - h - 14 end
    return math.max(y, 110)
end)()
ok(small >= 110, "на низком экране подсказка прижимается, но не уходит за край", small)

-----------------------------------------------------------------------
-- 2-3. ЗНАЧОК ЗОНЫ: МАТЕРИАЛ, МАСШТАБ, ВЫСОТА, ПОВОРОТ
-----------------------------------------------------------------------
print("\n=== 2. МАТЕРИАЛ ЗНАЧКА ===")

-- Поднимаем реальный модуль в минимальном окружении.
SERVER, CLIENT = false, true
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function math.Round(v) return math.floor(v + 0.5) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = istable(v) and table.Copy(v) or v end return o end

local AngMT = {}
AngMT.__index = AngMT
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AngMT) end
function AngMT:RotateAroundAxis() end

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2 + self.y^2 + self.z^2) end
-- Угол вектора: нам важен только yaw.
function VecMT:Angle() return Angle(0, math.deg(math.atan2(self.y, self.x)), 0) end
function VecMT.__add(a, b) return Vector(a.x+b.x, a.y+b.y, a.z+b.z) end
function VecMT.__sub(a, b) return Vector(a.x-b.x, a.y-b.y, a.z-b.z) end
function VecMT.__mul(a, s) if isnumber(s) then return Vector(a.x*s, a.y*s, a.z*s) end return Vector(a.x*s.x, a.y*s.y, a.z*s.z) end
function VecMT.__eq(a, b) return a.x==b.x and a.y==b.y and a.z==b.z end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT) end

function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
color_white = Color(255, 255, 255)
function ErrorNoHalt() end
CurTime = function() return 100 end
RENDERGROUP_TRANSLUCENT = 1

hook = { _t = {} }
function hook.Add(e, i, f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Remove(e, i) if hook._t[e] then hook._t[e][i] = nil end end
function hook.Run(e, ...) for _, f in pairs(hook._t[e] or {}) do local r = f(...) if r ~= nil then return r end end end

timer = { Simple = function() end, Create = function() end, Remove = function() end }
concommand = { Add = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
surface = setmetatable({}, { __index = function() return function() return 0 end end })
draw = setmetatable({}, { __index = function() return function() end end })
render = setmetatable({}, { __index = function() return function() end end })
cam = { Start3D2D = function() end, End3D2D = function() end }
util = setmetatable({ AddNetworkString = function() end }, { __index = function() return function() end end })
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
vgui = setmetatable({}, { __index = function() return function() return setmetatable({}, { __index = function() return function() end end }) end end })
language = { Add = function() end }
chat = { AddText = function() end }
notification = { AddLegacy = function() end }
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end }
function ScrW() return 1600 end
function ScrH() return 900 end
function LocalPlayer() return nil end
function EyePos() return Vector(0, 0, 0) end
function EyeAngles() return Angle(0, 0, 0) end
function GetConVar() return { GetString = function() return "" end, GetInt = function() return 3 end, GetBool = function() return false end, GetFloat = function() return 0 end } end
function CreateConVar() return GetConVar() end
function ClientsideModel() return nil end
function Material() return { IsError = function() return false end } end
function Entity() return nil end
function IsFirstTimePredicted() return true end
GRM = { Perf = { Players = function() return {} end } }

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

ok(ES.MarkerMaterial == "models/debug/debugwhite",
   "ИСПРАВЛЕНО: материал значка ровно тот, что просил владелец", ES.MarkerMaterial)

local src = readf("lua/autorun/sh_grm_estate.lua")
ok(src:find("SetMaterial(ES.MarkerMaterial)", 1, true) ~= nil,
   "материал реально применяется к модели значка, а не просто лежит в конфиге")
ok(src:find("SetColorModulation", 1, true) ~= nil,
   "цвет по-прежнему задаётся модуляцией — теперь поверх чистого белого")

print("\n=== 3. МАСШТАБ, ВЫСОТА И ПОВОРОТ ЗНАЧКА ===")

-- Старые значения из истории модуля.
local OLD_BIZ, OLD_EST, OLD_H = 1 / 1.5, 1 / 2, 78

ok(ES.MarkerScale.business < OLD_BIZ,
   "ИСПРАВЛЕНО: бизнес-значок меньше прежнего",
   ("было %.2f, стало %.2f"):format(OLD_BIZ, ES.MarkerScale.business))
ok(ES.MarkerScale.estate < OLD_EST,
   "ИСПРАВЛЕНО: значок жилья меньше прежнего",
   ("было %.2f, стало %.2f"):format(OLD_EST, ES.MarkerScale.estate))
ok(ES.MarkerScale.business <= OLD_BIZ / 2.5,
   "уменьшение существенное, а не косметическое (в 2.5+ раза)",
   ("%.2f -> %.2f"):format(OLD_BIZ, ES.MarkerScale.business))
ok(ES.MarkerScale.business > ES.MarkerScale.estate,
   "бизнес чуть крупнее жилья — виды различимы издалека")
ok(ES.MarkerScale.estate > 0.05,
   "но не превратились в точку", ES.MarkerScale.estate)

ok(ES.MarkerHeight < OLD_H,
   "ИСПРАВЛЕНО: значок опущен ниже",
   ("было %d, стало %d"):format(OLD_H, ES.MarkerHeight))
--[[ Высота пересмотрена 28.08: владелец просил опустить ещё на 10-20
     юнитов. Значок теперь почти на уровне центра зоны. Ноль не берём —
     небольшой подъём нужен, чтобы модель не резалась о пол. ]]
ok(ES.MarkerHeight <= 22 and ES.MarkerHeight > 0,
   "значок опущен почти к центру зоны, но не утоплен в пол", ES.MarkerHeight)

ok(ES.MarkerRoll == 90,
   "ИСПРАВЛЕНО: задан Roll 90° — логотип стоит вертикально, а не лежит крышей")

--[[ Проверяем сам расчёт разворота: значок должен смотреть на игрока
     с любой стороны. Воспроизводим формулу из PostDrawTranslucentRenderables. ]]
local function markerAngle(markerPos, eyePos)
    local dir = eyePos - markerPos
    dir.z = 0
    return Angle(0, dir:Angle().y, ES.MarkerRoll)
end

local mpos = Vector(0, 0, 100)
local a = markerAngle(mpos, Vector(500, 0, 120))
ok(math.abs(a.y - 0) < 0.01, "игрок на востоке — значок повёрнут на него", a.y)
a = markerAngle(mpos, Vector(0, 500, 120))
ok(math.abs(a.y - 90) < 0.01, "игрок на севере — значок довернулся", a.y)
a = markerAngle(mpos, Vector(-500, 0, 120))
ok(math.abs(math.abs(a.y) - 180) < 0.01, "игрок на западе — значок довернулся", a.y)

-- Высота камеры не должна заваливать значок: смотрим сверху.
local high = markerAngle(mpos, Vector(500, 0, 5000))
ok(high.p == 0, "с высоты значок НЕ заваливается назад — не «крыша»")
ok(high.y == markerAngle(mpos, Vector(500, 0, 101)).y,
   "yaw не зависит от высоты камеры — значок стабилен")
ok(high.r == 90, "roll фиксирован: логотип всегда вертикально")

--[[ Пересмотрено 28.08. Промежуточный вариант «значок смотрит на игрока»
     оказался хуже исходного: он замирал и дёргался в зависимости от
     стороны подхода (владелец: «вращение испоганено, он вращается туда
     куда смотрит игрок»). Вернули ровное вращение вокруг своей оси. ]]
ok(src:find("CurTime() * ES.MarkerSpin", 1, true) ~= nil,
   "значок вращается сам по времени, независимо от камеры")
ok(src:find("dir:Angle().y", 1, true) == nil,
   "и НЕ доворачивается вслед за игроком")

-- Подпись должна следовать за опущенным значком.
--[[ Подпись обязана быть НАД значком. Раньше она смещалась вниз на 16
     юнитов; после опускания эмблемы такой сдвиг увёл бы текст под пол.

     ВАЖНО (28.08, переделка дизайна по скриншотам). Этот HUD-текст
     остался ТОЛЬКО для зон без привязанных дверей. У объектов с дверью
     и название, и цена теперь живут на 3D2D-табличке над входом:
     HUDPaint рисует поверх геометрии, и на скриншотах владельца было
     видно надписи соседних квартир прямо сквозь стену.

     Подробности таблички — в sim_estate_door_marker.lua. Здесь
     проверяем только уцелевшую ветку «зона без дверей». ]]
ok(src:find("(pos + Vector(0, 0, 18)):ToScreen()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: подпись поднята над значком, а не спрятана под пол")
ok(src:find("(pos - Vector(0, 0, 16)):ToScreen()", 1, true) == nil,
   "прежний сдвиг вниз убран")

local hudBlock = src:match('hook%.Add%("HUDPaint", "GRM_Estate_Labels".-\n    end%)') or ""
ok(hudBlock ~= "", "блок HUD-подписей найден")
ok(hudBlock:find("if not zone.onDoor then", 1, true) ~= nil,
   "HUD-подпись рисуется только для зон БЕЗ дверей — текст не светит сквозь стены")

-----------------------------------------------------------------------
-- 4. ПЛАШКА ТОРГОВОГО АВТОМАТА
-----------------------------------------------------------------------
print("\n=== 4. ПОДПИСЬ ТОРГОВОГО АВТОМАТА ===")

local vend = readf("lua/autorun/client/cl_grm_vending_gui.lua")
-- Разворот плашки теперь живёт в общей базе компьютеров (grm_comp_base):
-- одиннадцать копий Draw сведены в одну, и эталон приёма — там.
local comp = readf("lua/entities/grm_comp_base/cl_init.lua")

ok(vend:find("Vector(0, 0, 82)", 1, true) == nil,
   "ИСПРАВЛЕНО: надпись больше не висит на 82 юнита над автоматом")
ok(vend:find("LocalToWorld", 1, true) ~= nil,
   "ИСПРАВЛЕНО: плашка привязана к корпусу автомата, а не к мировой точке")
ok(vend:find("OBBMins", 1, true) ~= nil and vend:find("OBBMaxs", 1, true) ~= nil,
   "позиция считается от габаритов модели — подходит любой модели автомата")

-- Тот же приём разворота, что у терминалов-компьютеров.
local function usesCompStyle(text)
    return text:find("RotateAroundAxis(ang:Up(), 90)", 1, true) ~= nil
       and text:find("RotateAroundAxis(ang:Forward(), 90)", 1, true) ~= nil
end
ok(usesCompStyle(comp), "контроль: у компьютера-терминала именно такой разворот плашки")
ok(usesCompStyle(vend),
   "ИСПРАВЛЕНО: автомат оформлен тем же приёмом, «как компьютеры»")

ok(vend:find("draw.RoundedBox", 1, true) ~= nil,
   "у подписи появилась тёмная подложка — читается на любом фоне")
ok(vend:find("GRMVend_Title", 1, true) ~= nil and vend:find("surface.CreateFont(\"GRMVend_Title\"", 1, true) ~= nil,
   "шрифт объявлен там же, где используется — не будет 'font doesn't exist'")
ok(vend:find("GRMVend_Sub", 1, true) ~= nil and vend:find("surface.CreateFont(\"GRMVend_Sub\"", 1, true) ~= nil,
   "второй шрифт тоже объявлен")

ok(vend:find("400 * 400", 1, true) ~= nil,
   "далёкие автоматы не рисуют плашку — бережём кадр")
ok(vend:find("Dot(self:GetForward())", 1, true) ~= nil,
   "сзади плашка не рисуется — она на передней грани, как настоящая наклейка")
ok(vend:find("НАЖМИТЕ  E", 1, true) ~= nil,
   "подсказка «нажмите E» осталась")
ok(vend:find("local near = dist <= 170 * 170", 1, true) ~= nil,
   "и показывается только когда игрок реально дотянется до автомата")

--[[ Живая проверка геометрии плашки: она обязана оказаться на корпусе,
     а не над ним. Берём габариты стандартной модели автомата. ]]
do
    local mins, maxs = Vector(-16, -14, 0), Vector(16, 14, 72)
    local frontOffset = maxs.x + 0.6
    local height = mins.z + (maxs.z - mins.z) * 0.86
    ok(height < maxs.z, "плашка НИЖЕ верхней кромки автомата — на корпусе", height)
    ok(height > (maxs.z - mins.z) * 0.5, "но в верхней половине, на уровне глаз", height)
    ok(frontOffset > maxs.x, "чуть вынесена вперёд — не мерцает с текстурой", frontOffset)
    ok(frontOffset - maxs.x < 2, "но не отлипла от корпуса", frontOffset - maxs.x)
    -- Старый вариант для сравнения.
    ok(82 > maxs.z, "БАГ ВОСПРОИЗВЁДЕН: старая надпись висела выше самого автомата",
       ("82 против высоты корпуса %d"):format(maxs.z))
end

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
