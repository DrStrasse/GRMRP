--[[ Живой прогон слоя вывесок GRM (заказ владельца 21.08: «у скупщиков
     полетел заголовок»). Проверяем, что вывеска рисуется одним проходом,
     заголовок реально попадает в кадр, подложка растёт под длинный текст,
     а ошибка внутри не оставляет матрицу 3D2D открытой.
     Грузится РЕАЛЬНЫЙ lua/autorun/client/cl_grm_sign.lua (CLIENT=true).
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_sign.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, true
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, TEXT_ALIGN_LEFT = 1, 3, 0

local VEC = {}
VEC.__index = VEC
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC) end
function VEC.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VEC:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx * dx + dy * dy + dz * dz end
function Angle(p, y, r) return { p = p, y = y, r = r } end

local HOOKS = {}
hook = { Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
         Run = function() end, Remove = function() end }

local CONVARS = {}
function CreateClientConVar(name, def)
    local cv = { value = def }
    function cv:GetBool() return tostring(self.value) ~= "0" end
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end

-- Рисовалка-протокол: запоминаем всё, что «нарисовано».
local LOG = { boxes = {}, texts = {}, start = 0, stop = 0 }
local FONT_OK = {}          -- какие шрифты «создались»
local CUR_FONT = nil
surface = {
    CreateFont = function(name) FONT_OK[name] = true end,
    SetFont = function(name)
        if not FONT_OK[name] and name ~= "DermaLarge" and name ~= "DermaDefault" and name ~= "DermaDefaultBold" then
            error("Tried to use font " .. tostring(name))
        end
        CUR_FONT = name
    end,
    GetTextSize = function(text) return #tostring(text) * 8, 20 end,
    SetDrawColor = function() end,
    DrawRect = function() end,
}
draw = {
    RoundedBox = function(_, x, y, w, h) LOG.boxes[#LOG.boxes + 1] = { x = x, y = y, w = w, h = h } end,
    SimpleText = function(text, font) LOG.texts[#LOG.texts + 1] = { text = tostring(text), font = font } end,
}
cam = {
    Start3D2D = function() LOG.start = LOG.start + 1 end,
    End3D2D = function() LOG.stop = LOG.stop + 1 end,
}
local LP = { _valid = true }
function LP:EyePos() return Vector(0, 0, 0) end
function LP:EyeAngles() return Angle(0, 0, 0) end
function LocalPlayer() return LP end
GRM = {}

local function reset() LOG = { boxes = {}, texts = {}, start = 0, stop = 0 } end
local function textsJoined()
    local t = {}
    for _, e in ipairs(LOG.texts) do t[#t + 1] = e.text end
    return table.concat(t, " | ")
end

assert(loadfile("lua/autorun/client/cl_grm_sign.lua"))()
local S = GRM.Sign

local function mkEnt(x)
    local e = { _valid = true }
    function e:GetPos() return Vector(x or 0, 0, 0) end
    return e
end

print("\n=== 1. СЛОЙ НА МЕСТЕ ===")
ok(istable(S) and isfunction(S.Draw), "GRM.Sign.Draw объявлен")
ok(isfunction(S.EnsureFonts), "шрифты создаются через общий слой")
ok(isfunction(HOOKS["OnScreenSizeChanged"]["GRM_Sign_Fonts"]), "при смене разрешения шрифты пересоздаются")

print("\n=== 2. ЗАГОЛОВОК РИСУЕТСЯ ===")
reset()
S.Draw(mkEnt(50), { title = "СКУПЩИК РУДЫ", subtitle = "Приём руды", hint = "E — открыть" })
ok(LOG.start == 1 and LOG.stop == 1, "ровно один проход 3D2D за вызов", LOG.start .. "/" .. LOG.stop)
ok(#LOG.boxes == 2, "подложка и цветная полоса", #LOG.boxes)
ok(textsJoined():find("СКУПЩИК РУДЫ", 1, true) ~= nil, "заголовок попал в кадр", textsJoined())
ok(textsJoined():find("Приём руды", 1, true) ~= nil, "подпись тоже")
ok(textsJoined():find("E — открыть", 1, true) ~= nil, "подсказка вблизи показана")

print("\n=== 3. ПОДЛОЖКА РАСТЁТ ПОД ДЛИННЫЙ ЗАГОЛОВОК ===")
reset()
S.Draw(mkEnt(50), { title = "КОРОТКО" })
local narrow = LOG.boxes[1].w
reset()
S.Draw(mkEnt(50), { title = "ОЧЕНЬ ДЛИННОЕ НАЗВАНИЕ ТОРГОВОЙ ТОЧКИ ГОРОДА" })
local wide = LOG.boxes[1].w
ok(wide > narrow, "длинный заголовок расширяет плашку", narrow .. " → " .. wide)
ok(wide >= #"ОЧЕНЬ ДЛИННОЕ НАЗВАНИЕ ТОРГОВОЙ ТОЧКИ ГОРОДА" * 8, "текст помещается в подложку")

print("\n=== 4. ДАЛЬНОСТЬ ===")
reset()
S.Draw(mkEnt(4000), { title = "ДАЛЕКО" })
ok(LOG.start == 0, "дальше 400 юнитов вывеска не рисуется")
reset()
S.Draw(mkEnt(300), { title = "СРЕДНЕ", hint = "E — открыть" })
ok(textsJoined():find("E —", 1, true) == nil, "подсказка издалека не рисуется", textsJoined())
reset()
S.Draw(nil, { title = "НЕТ ЭНТИТИ" })
ok(LOG.start == 0, "без энтити ничего не рисуется")

print("\n=== 5. ШРИФТ НЕ СОЗДАЛСЯ — ЕСТЬ ЗАПАСНОЙ ===")
FONT_OK["GRM_Sign_Title"] = nil
local realCreate = surface.CreateFont
surface.CreateFont = function(name) if name ~= "GRM_Sign_Title" then FONT_OK[name] = true end end
S.EnsureFonts(true)
ok(S.Font.title == "DermaLarge", "заголовок падает на DermaLarge, а не в пустоту", S.Font.title)
reset()
S.Draw(mkEnt(50), { title = "ЗАПАСНОЙ ШРИФТ" })
ok(textsJoined():find("ЗАПАСНОЙ ШРИФТ", 1, true) ~= nil, "и всё равно пишет заголовок")
surface.CreateFont = realCreate
S.EnsureFonts(true)
ok(S.Font.title == "GRM_Sign_Title", "нормальный шрифт возвращается")

print("\n=== 6. ОШИБКА ВНУТРИ НЕ ЛОМАЕТ КАДР ===")
reset()
local realBox = draw.RoundedBox
draw.RoundedBox = function() error("нарочно") end
S.Draw(mkEnt(50), { title = "ПАДЕНИЕ" })
ok(LOG.start == 1 and LOG.stop == 1, "cam.End3D2D вызван даже при ошибке — матрица не утекает",
   LOG.start .. "/" .. LOG.stop)
draw.RoundedBox = realBox
CONVARS["grm_sign_debug"]:SetValue("1")
reset()
draw.RoundedBox = function() error("нарочно-2") end
S.Draw(mkEnt(50), { title = "ПАДЕНИЕ" })
draw.RoundedBox = realBox
ok(true, "grm_sign_debug печатает причину падения")
CONVARS["grm_sign_debug"]:SetValue("0")

print(("\nSIGN: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
