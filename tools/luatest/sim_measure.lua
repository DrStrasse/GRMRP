--[[ Живой прогон инструмента замеров GRM (заказ владельца 22.08:
     «инструмент координат, считывающий позицию, стороны объекта, его углы,
     всё что касаемо пропа»).
     Грузится РЕАЛЬНЫЙ lua/weapons/gmod_tool/stools/grm_measure.lua
     (SERVER=false, CLIENT=false — берём чистую часть).
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_measure.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
TOOL = {}
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
hook = { Add = function() end, Run = function() end }
GRM = {}

assert(loadfile("lua/weapons/gmod_tool/stools/grm_measure.lua"))()
local M = GRM.Measure

local function joined(lines) return table.concat(lines or {}, " | ") end

print("\n=== 1. ОКРУГЛЕНИЕ ===")
ok(M.Round(12.3456, 1) == 12.3, "один знак после запятой", M.Round(12.3456, 1))
ok(M.Round(12.3456, 0) == 12, "целое", M.Round(12.3456, 0))
ok(M.Round(-0.04, 1) == 0 or M.Round(-0.04, 1) == -0.0, "мелочь у нуля не пугает", M.Round(-0.04, 1))

print("\n=== 2. СТОРОНЫ ОБЪЕКТА ===")
local sides = M.SideList({ x = -10, y = -30, z = -2 }, { x = 10, y = 30, z = 2 })
ok(sides.x == 20 and sides.y == 60 and sides.z == 4, "размеры сторон считаются по мин/макс")
ok(sides.thin == "z", "тонкая ось найдена — по ней идёт нормаль лицевой стороны", sides.thin)
ok(sides.long == "y", "длинная ось найдена — вдоль неё ставят надпись", sides.long)
ok(sides.volume == 20 * 60 * 4, "объём считается")

print("\n=== 3. РАССТОЯНИЯ И КУРС ===")
local d = M.Delta({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 12 })
ok(d.flat == 5, "по земле — теорема Пифагора", d.flat)
ok(d.length == 13, "по прямой с учётом высоты", d.length)
ok(math.abs(d.yaw - 53.13) < 0.01, "курс в градусах", d.yaw)

print("\n=== 4. ЧИТАЕМЫЙ ЗАМЕР ===")
local lines = M.Describe({
    class = "prop_physics", model = "models/props/x.mdl",
    pos = { x = 100.123, y = -50.456, z = 12.5 },
    ang = { p = 0, y = 90.4, r = 0 },
    mins = { x = -10, y = -30, z = -2 }, maxs = { x = 10, y = 30, z = 2 },
    hit = { x = 101, y = -50, z = 14 },
    normal = { x = 0, y = 0, z = 1 },
    localHit = { x = 1, y = 0, z = 2 },
    distance = 84.2,
}, 1)
local text = joined(lines)
ok(text:find("prop_physics", 1, true) ~= nil, "класс объекта")
ok(text:find("Позиция: 100.1 -50.5 12.5", 1, true) ~= nil, "позиция округляется", text)
ok(text:find("Углы (p y r): 0 90.4 0", 1, true) ~= nil, "углы")
ok(text:find("Габарит: 20 × 60 × 4", 1, true) ~= nil, "габарит по сторонам")
ok(text:find("Тонкая ось: z", 1, true) ~= nil, "подсказка про оси — под номерные знаки и щиты")
ok(text:find("Нормаль поверхности: 0 0 1", 1, true) ~= nil, "нормаль поверхности")
ok(text:find("Локально в объекте: 1 0 2", 1, true) ~= nil, "локальные координаты точки попадания")
ok(text:find("Расстояние от вас: 84.2", 1, true) ~= nil, "дистанция")

local world = joined(M.Describe({ class = "мир (браш карты)", pos = { x = 0, y = 0, z = 0 },
    ang = { p = 0, y = 0, r = 0 } }, 0))
ok(world:find("мир (браш карты)", 1, true) ~= nil, "по брашу карты тоже отдаёт замер")

print("\n=== 5. МЕТКИ ===")
local one = joined(M.DescribeMarks({ x = 0, y = 0, z = 0 }, nil, 1))
ok(one:find("Метка B: не поставлена", 1, true) ~= nil, "одна метка — подсказка про вторую")
local two = joined(M.DescribeMarks({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 0 }, 1))
ok(two:find("Расстояние: 5", 1, true) ~= nil, "две метки дают расстояние", two)
ok(two:find("Разница: X 3   Y 4   Z 0", 1, true) ~= nil, "и разницу по осям")
ok(#M.DescribeMarks(nil, nil, 1) == 0, "без меток строк нет")

print("\n=== 6. КОНТРАКТ ИНСТРУМЕНТА ===")
local src = (function()
    local f = io.open("lua/weapons/gmod_tool/stools/grm_measure.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function has(n) return src:find(n, 1, true) ~= nil end
ok(has("function TOOL:LeftClick(trace)") and has("function TOOL:RightClick(trace)")
   and has("function TOOL:Reload(trace)"), "ЛКМ, ПКМ и R расписаны")
ok(has('concommand.Add("grm_coords"') and has('["/координаты"]'), "команда в чат и в консоль")
ok(has("GRM.Perf.EyeTrace"), "трассировка идёт через кэш GRM.Perf")
ok(has("info.localNormalAng"), "углы поверхности считаются в системе объекта")

print(("\nMEASURE: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
