--[[ Живой прогон конфорок плиты и прогресс-бара (заказ владельца 28.08).

     «models/hunter/blocks/cube025x025x025.mdl — на плите нужно четыре
      кубика, которые будут точками для установки кастрюли или иной
      тары. Нужно чтобы тара ставилась на плиту, притягивалась сразу.»

     «Прогресс бар готовки должен быть также как в меню и над плитой.»

     Запуск: luajit tools/luatest/sim_stove_slots.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function ErrorNoHalt() end
HUD_PRINTTALK = 3

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function VecMT.__tostring(a) return ("(%.1f %.1f %.1f)"):format(a.x,a.y,a.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end

-- Настоящая битовая арифметика: на ней держится маска занятости.
bit = {
    band = function(a,b) local r,m=0,1 while a>0 and b>0 do if a%2==1 and b%2==1 then r=r+m end a=math.floor(a/2) b=math.floor(b/2) m=m*2 end return r end,
    bor = function(a,b) local r,m=0,1 while a>0 or b>0 do if a%2==1 or b%2==1 then r=r+m end a=math.floor(a/2) b=math.floor(b/2) m=m*2 end return r end,
    lshift = function(a,n) return a * (2^n) end,
    bnot = function(a) return 15 - a end,   -- в пределах 4 бит, нам хватает
}

local REALTIME = 1700000000
os.time = function() return REALTIME end
CurTime = function() return 100 end

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end
local function runAll(e,...) for _,f in pairs(hook._t[e] or {}) do f(...) end end

timer = { Simple=function(_,f) f() end, Create=function() end, Remove=function() end }
local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }
util = { AddNetworkString=function() end, IsValidModel=function() return true end }
FCVAR_ARCHIVE = 128

--[[ Конвары подгонки: стенд гоняет значения ИЗ КОДА, поэтому все
     возвращают «не задано». Отдельно проверяем, что переопределение
     работает. ]]
local CVARS = {}
function CreateConVar(name, def)
    CVARS[name] = { v = def }
    return {
        GetFloat = function() return tonumber(CVARS[name].v) or 0 end,
        GetString = function() return tostring(CVARS[name].v) end,
        GetBool = function() return CVARS[name].v ~= "0" end,
        GetInt = function() return math.floor(tonumber(CVARS[name].v) or 0) end,
    }
end
function RunConsoleCommand(name, val) if CVARS[name] then CVARS[name].v = val end end
local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }

local WORLD = {}
ents = {
    GetAll = function() return WORLD end,
    FindByClass = function(c)
        local o = {}
        for _, e in ipairs(WORLD) do if e:GetClass() == c then o[#o+1] = e end end
        return o
    end,
}

local NOTIFIED = {}
GRM = { Perf = { Players = function() return PLAYERS end } }
GRM.Notify = function(p, msg) NOTIFIED[#NOTIFIED+1] = { to = p, msg = msg } end

assert(loadfile("lua/autorun/sh_grm_stove_slots.lua"))()
local SS = GRM.StoveSlots

-----------------------------------------------------------------------
-- ЗАГЛУШКИ
-----------------------------------------------------------------------
local function mkStove(pos)
    local e
    e = {
        _valid = true, _pos = pos or Vector(0,0,0), _slots = 0, _state = 0,
        GetClass = function() return "grm_food_stove" end,
        GetPos = function(s) return s._pos end,
        GetAngles = function() return Angle(0, 0, 0) end,
        OBBMins = function() return Vector(-24, -18, 0) end,
        OBBMaxs = function() return Vector(24, 18, 36) end,
        -- Плита не повёрнута: локальные координаты совпадают с мировыми.
        LocalToWorld = function(s, v) return s._pos + v end,
        SetStoveSlots = function(s, v) s._slots = v end,
        GetStoveSlots = function(s) return s._slots end,
        GetStoveState = function(s) return s._state end,
        EmitSound = function() end,
    }
    WORLD[#WORLD+1] = e
    return e
end

local function mkKettle(pos)
    local phys = { motion = true, awake = true }
    function phys:EnableMotion(v) self.motion = v end
    function phys:Sleep() self.awake = false end
    function phys:Wake() self.awake = true end
    local e
    e = {
        _valid = true, _pos = pos or Vector(0,0,0), _ang = Angle(0,0,0), _phys = phys,
        GetClass = function() return "grm_brew_kettle" end,
        GetModel = function() return "models/props/kettle.mdl" end,
        GetPos = function(s) return s._pos end,
        SetPos = function(s, v) s._pos = v end,
        SetAngles = function(s, a) s._ang = a end,
        OBBMins = function() return Vector(-8, -8, 0) end,
        OBBMaxs = function() return Vector(8, 8, 20) end,
        GetPhysicsObject = function(s) return s._phys end,
        EmitSound = function() end,
    }
    WORLD[#WORLD+1] = e
    return e
end

local function mkPot(pos)
    local e = mkKettle(pos)
    e.GetClass = function() return "prop_physics" end
    e.GetModel = function() return "models/props_c17/metalPot001a.mdl" end
    return e
end

local function mkJunk(pos)
    local e = mkKettle(pos)
    e.GetClass = function() return "prop_physics" end
    e.GetModel = function() return "models/props_junk/wood_crate001a.mdl" end
    return e
end

local function mkPly()
    return { _valid = true, IsPlayer = function() return true end,
             GetPos = function() return Vector(0,0,0) end,
             PrintMessage = function() end }
end

-----------------------------------------------------------------------
print("\n=== 1. ЧЕТЫРЕ КОНФОРКИ НА ПЛИТЕ ===")
-----------------------------------------------------------------------
ok(SS.CubeModel == "models/hunter/blocks/cube025x025x025.mdl",
   "модель кубика ровно та, что заказал владелец", SS.CubeModel)
ok(#SS.SlotOffsets == 4, "конфорок ровно четыре", #SS.SlotOffsets)

local stove = mkStove(Vector(0, 0, 0))
local positions = {}
for i = 1, 4 do positions[i] = SS.SlotPos(stove, i) end

ok(positions[1] ~= nil, "позиция конфорки считается")

-- Все четыре в разных местах.
local same = 0
for i = 1, 4 do
    for j = i + 1, 4 do
        if positions[i] == positions[j] then same = same + 1 end
    end
end
ok(same == 0, "все четыре конфорки в разных точках", same)

-- Кубики НА варочной поверхности, а не внутри и не в воздухе.
local topZ = stove:GetPos().z + stove:OBBMaxs().z
for i = 1, 4 do
    ok(positions[i].z >= topZ and positions[i].z <= topZ + 4,
       ("конфорка %d лежит на поверхности плиты"):format(i),
       ("z=%.1f, верх=%.1f"):format(positions[i].z, topZ))
end

-- И в пределах габарита плиты, а не за краем.
local mins, maxs = stove:OBBMins(), stove:OBBMaxs()
local inside = 0
for i = 1, 4 do
    local p = positions[i]
    if p.x >= mins.x and p.x <= maxs.x and p.y >= mins.y and p.y <= maxs.y then
        inside = inside + 1
    end
end
ok(inside == 4, "все конфорки в пределах плиты, ни одна не свисает", inside)

--[[ ПРОВЕРКА ПО СКРИНШОТУ ВЛАДЕЛЬЦА (28.08): «чуть-чуть свести бы на
     конфорки и поближе все четыре кубика».

     Мало попадать в габарит: OBB описывает плиту ЦЕЛИКОМ, вместе с
     нижней тумбой и ручками, которые шире столешницы. Кубики на 0.42
     формально были «внутри», но по факту висели за краем варочной
     поверхности. Требуем ЗАПАС от края — тогда они лягут на горелки. ]]
do
    local marginX = math.huge
    local marginY = math.huge
    for i = 1, 4 do
        local p = positions[i]
        marginX = math.min(marginX, math.min(p.x - mins.x, maxs.x - p.x))
        marginY = math.min(marginY, math.min(p.y - mins.y, maxs.y - p.y))
    end
    local halfX = (maxs.x - mins.x) * 0.5
    local halfY = (maxs.y - mins.y) * 0.5
    ok(marginX >= halfX * 0.4,
       "ИСПРАВЛЕНО: по X кубики отодвинуты от края вглубь столешницы",
       ("запас %.1f при полуширине %.1f"):format(marginX, halfX))
    ok(marginY >= halfY * 0.4,
       "и по Y тоже — не свисают, как было на 0.42",
       ("запас %.1f при полудлине %.1f"):format(marginY, halfY))

    -- Не сошлись в одну точку: между конфорками должен остаться зазор.
    local minGap = math.huge
    for i = 1, 4 do
        for j = i + 1, 4 do
            local d = math.sqrt(positions[i]:DistToSqr(positions[j]))
            minGap = math.min(minGap, d)
        end
    end
    ok(minGap > 8, "но и не слиплись в кучу — зазор сохранён",
       ("%.1f юнитов"):format(minGap))
end

--[[ Размер метки. Кубик 0.25-блока это 12 юнитов; масштаб должен
     оставлять его меньше самой горелки, иначе метка закрывает то, что
     размечает (владелец: кубики перекрывали конфорки). ]]
ok(SS.CubeScale < 0.5,
   "ИСПРАВЛЕНО: кубик уменьшен и не перекрывает горелку", SS.CubeScale)
ok(SS.CubeScale > 0.15, "но остался заметным", SS.CubeScale)

-----------------------------------------------------------------------
print("\n=== 1б. СИММЕТРИЯ И ФОРМА ЧЕТВЁРКИ (замечание 28.08) ===")
-----------------------------------------------------------------------
--[[ «Одни встали ровно, вторые не очень.» Причина была в одной доле на
     обе оси: плита прямоугольная (48x36), конфорки на ней — квадратом.
     0.24 от 48 это 11.5 юнита, от 36 — всего 8.6. Четвёрка получалась
     вытянутой, и половина кубиков мазала мимо горелок. ]]
do
    local L = SS.Layout()
    ok(L.spreadX ~= L.spreadY,
       "ИСПРАВЛЕНО: разброс по осям РАЗНЫЙ — плита же прямоугольная",
       ("X=%.3f Y=%.3f"):format(L.spreadX, L.spreadY))

    -- В ЮНИТАХ смещения должны быть сопоставимы: это и есть «квадратом».
    local sx = maxs.x - mins.x
    local sy = maxs.y - mins.y
    local offX = sx * L.spreadX
    local offY = sy * L.spreadY
    local ratio = offX / offY
    ok(ratio > 0.7 and ratio < 1.45,
       "ИСПРАВЛЕНО: в юнитах смещения близки — четвёрка стоит квадратом, а не полосой",
       ("%.1f и %.1f юн (отношение %.2f)"):format(offX, offY, ratio))

    --[[ Со старой единой долей 0.24 отношение было бы 48/36 = 1.33 —
         формально в допуске, но по короткой оси кубики уходили к самому
         краю. Поэтому отдельно проверяем ЗАПАС по короткой стороне. ]]
    ok(sy * 0.5 - offY >= sy * 0.5 * 0.4,
       "и по короткой оси остался запас до края",
       ("%.1f юн"):format(sy * 0.5 - offY))
end

-- Четыре точки должны быть симметричны относительно своего центра.
do
    local cx, cy = 0, 0
    for i = 1, 4 do cx = cx + positions[i].x cy = cy + positions[i].y end
    cx, cy = cx / 4, cy / 4
    local dx, dy = {}, {}
    for i = 1, 4 do
        dx[#dx + 1] = math.abs(positions[i].x - cx)
        dy[#dy + 1] = math.abs(positions[i].y - cy)
    end
    local okX = math.abs(dx[1] - dx[2]) < 0.01 and math.abs(dx[1] - dx[3]) < 0.01
    local okY = math.abs(dy[1] - dy[2]) < 0.01 and math.abs(dy[1] - dy[3]) < 0.01
    ok(okX and okY, "все четыре равноудалены от центра группы — перекоса нет")
end

-----------------------------------------------------------------------
print("\n=== 1в. ЖИВАЯ ПОДГОНКА КОНВАРАМИ ===")
-----------------------------------------------------------------------
--[[ Модель плиты сменная, и подбирать её вслепую по моим догадкам
     бесполезно: игру видит владелец, а не я. Конвары дают довести
     положение на сервере, без правки кода. ]]
do
    local base = SS.Layout()
    RunConsoleCommand("grm_stove_slot_x", "0.33")
    local tuned = SS.Layout()
    ok(tuned.spreadX == 0.33, "конвар переопределяет разброс из кода", tuned.spreadX)
    ok(tuned.spreadY == base.spreadY, "и не задевает вторую ось")

    local moved = SS.SlotPos(stove, 1)
    ok(math.abs(moved.x - positions[1].x) > 1,
       "позиция конфорки реально сдвинулась — подгонка работает")

    RunConsoleCommand("grm_stove_slot_cy", "0.1")
    ok(SS.Layout().centerY == 0.1, "центр тоже двигается", SS.Layout().centerY)

    -- Возврат к значениям из кода.
    RunConsoleCommand("grm_stove_slot_x", "-1")
    RunConsoleCommand("grm_stove_slot_cy", "-9")
    local back = SS.Layout()
    ok(back.spreadX == base.spreadX and back.centerY == base.centerY,
       "сброс возвращает значения из кода")
end

ok(isfunction(commands["grm_stove_calib"]), "есть команда подгонки grm_stove_calib")

--[[ Смещения заданы В ДОЛЯХ: плита другого размера должна получить
     конфорки по своему габариту, а не по чужим числам. ]]
do
    local big = mkStove(Vector(500, 0, 0))
    big.OBBMins = function() return Vector(-60, -40, 0) end
    big.OBBMaxs = function() return Vector(60, 40, 50) end
    local bp = SS.SlotPos(big, 1)
    local sp = SS.SlotPos(stove, 1)
    local bdx = math.abs(bp.x - big:GetPos().x)
    local sdx = math.abs(sp.x - stove:GetPos().x)
    ok(bdx > sdx, "на широкой плите конфорки разъезжаются шире",
       ("%.1f против %.1f"):format(bdx, sdx))
end

-----------------------------------------------------------------------
print("\n=== 2. МАСКА ЗАНЯТОСТИ ===")
-----------------------------------------------------------------------
local m = 0
ok(SS.SlotTaken(m, 1) == false, "пустая маска — все свободны")
m = SS.SetSlotBit(m, 2, true)
ok(SS.SlotTaken(m, 2) == true, "второй слот занят")
ok(SS.SlotTaken(m, 1) == false, "первый по-прежнему свободен")
ok(SS.SlotTaken(m, 3) == false, "и третий")
m = SS.SetSlotBit(m, 4, true)
ok(SS.SlotTaken(m, 2) and SS.SlotTaken(m, 4), "два занятых слота живут одновременно")
m = SS.SetSlotBit(m, 2, false)
ok(SS.SlotTaken(m, 2) == false and SS.SlotTaken(m, 4) == true,
   "снятие одного бита не трогает другой")

-----------------------------------------------------------------------
print("\n=== 3. ЧТО СЧИТАЕТСЯ ТАРОЙ ===")
-----------------------------------------------------------------------
local kettle = mkKettle(Vector(20, 0, 40))
local pot = mkPot(Vector(30, 0, 40))
local junk = mkJunk(Vector(40, 0, 40))

ok(SS.CookwareInfo(kettle) ~= nil, "котёл — тара (по классу)")
ok(SS.CookwareInfo(pot) ~= nil, "кастрюля — тара (по модели)")
ok(SS.CookwareInfo(junk) == nil, "деревянный ящик тарой НЕ считается")
ok(SS.CookwareInfo(nil) == nil, "мусор на входе не роняет проверку")

-----------------------------------------------------------------------
print("\n=== 4. ПРИТЯГИВАНИЕ ===")
-----------------------------------------------------------------------
local okSnap, idx = SS.Snap(kettle, stove)
ok(okSnap == true, "котёл встал на плиту", idx)
ok(idx and idx >= 1 and idx <= 4, "в один из четырёх слотов", idx)
ok(kettle.GRMStoveHost == stove, "котёл помнит свою плиту")
ok(SS.SlotTaken(stove._slots, idx) == true,
   "занятость ушла в сетевое поле — клиент подсветит кубик")

-- Стоит ровно на конфорке, не утоплен и не парит.
local slotPos = SS.SlotPos(stove, idx)
ok(math.abs(kettle._pos.x - slotPos.x) < 0.01
   and math.abs(kettle._pos.y - slotPos.y) < 0.01,
   "по горизонтали точно на конфорке", tostring(kettle._pos))
ok(kettle._pos.z >= slotPos.z,
   "и не утоплен в плиту — приподнят на свою высоту", kettle._pos.z - slotPos.z)

-- Физика выключена: посуда не съедет от толчка.
ok(kettle._phys.motion == false, "физика отключена — не съедет от взрыва")
ok(kettle._phys.awake == false, "и усыплена")

--[[ Родителем НЕ делаем: иначе игрок не снимет посуду физганом, а плиту
     начнёт таскать вместе с содержимым. ]]
local slotsSrc = readf("lua/autorun/sh_grm_stove_slots.lua")
ok(slotsSrc:find("SetParent", 1, true) == nil,
   "тара НЕ становится дочерней к плите — иначе её не снять")

-----------------------------------------------------------------------
print("\n=== 5. ЧЕТЫРЕ МЕСТА И НЕ БОЛЬШЕ ===")
-----------------------------------------------------------------------
local more = {}
for i = 1, 3 do
    more[i] = mkKettle(Vector(20 + i, 0, 40))
    SS.Snap(more[i], stove)
end
ok(SS.CountOn(stove) == 4, "на плите ровно четыре тары", SS.CountOn(stove))

local fifth = mkKettle(Vector(25, 0, 40))
local okFifth = SS.Snap(fifth, stove)
ok(okFifth == false, "пятая не влезает — свободных конфорок нет")
ok(fifth.GRMStoveHost == nil, "и она не считается стоящей на плите")
ok(SS.FreeSlot(stove, Vector(0,0,0)) == nil, "свободных слотов не осталось")

-----------------------------------------------------------------------
print("\n=== 6. СНЯТИЕ ОСВОБОЖДАЕТ МЕСТО ===")
-----------------------------------------------------------------------
SS.Release(kettle)
ok(kettle.GRMStoveHost == nil, "котёл больше не привязан к плите")
ok(SS.CountOn(stove) == 3, "занято три конфорки", SS.CountOn(stove))
ok(SS.SlotTaken(stove._slots, idx) == false, "и бит слота снят")
ok(SS.FreeSlot(stove, Vector(0,0,0)) ~= nil, "появилось свободное место")

-- Теперь пятая помещается.
ok(SS.Snap(fifth, stove) == true, "ранее лишняя тара встала на освободившееся место")

-- Уничтожение тары тоже освобождает слот.
local before = SS.CountOn(stove)
runAll("EntityRemoved", fifth)
ok(SS.CountOn(stove) == before - 1,
   "уничтоженная тара освобождает конфорку — «призраков» не остаётся")

-----------------------------------------------------------------------
print("\n=== 7. ОТПУСТИЛ ФИЗГАНОМ — ПРИТЯНУЛОСЬ ===")
-----------------------------------------------------------------------
do
    -- Чистая плита.
    WORLD = {}
    SS.Occupied = {}
    local st = mkStove(Vector(1000, 0, 0))
    local ply = mkPly()
    NOTIFIED = {}

    -- Тара рядом с плитой.
    local k = mkKettle(Vector(1030, 0, 40))
    runAll("PhysgunDrop", ply, k)
    ok(k.GRMStoveHost == st, "отпущенная рядом тара сама встала на плиту")
    ok(#NOTIFIED > 0, "игроку сообщили", NOTIFIED[1] and NOTIFIED[1].msg)

    -- Тара далеко — не притягивается.
    local far = mkKettle(Vector(3000, 0, 40))
    runAll("PhysgunDrop", ply, far)
    ok(far.GRMStoveHost == nil, "издалека не притягивается — телепорта нет")

    -- Не-тара рядом с плитой игнорируется.
    local box = mkJunk(Vector(1030, 0, 40))
    runAll("PhysgunDrop", ply, box)
    ok(box.GRMStoveHost == nil, "посторонний проп на плиту не лезет")

    -- Унесли далеко — слот освободился и физика вернулась.
    k._pos = Vector(3500, 0, 40)
    runAll("PhysgunDrop", ply, k)
    ok(k.GRMStoveHost == nil, "унесённая тара отвязалась от плиты")
    ok(k._phys.motion == true, "и физика ей вернулась — иначе висела бы в воздухе")
end

-----------------------------------------------------------------------
print("\n=== 8. ПРОГРЕСС-БАР НАД ПЛИТОЙ ===")
-----------------------------------------------------------------------
local sharedSrc = readf("lua/entities/grm_food_stove/shared.lua")
local clSrc = readf("lua/entities/grm_food_stove/cl_init.lua")
local initSrc = readf("lua/entities/grm_food_stove/init.lua")

ok(sharedSrc:find('NetworkVar("Int", 3, "StoveStart")', 1, true) ~= nil,
   "добавлено поле StoveStart — без него долю не посчитать")
ok(sharedSrc:find("function ENT:StoveProgress", 1, true) ~= nil,
   "доля считается ОДНОЙ функцией на окно и табличку")
ok(initSrc:find("self:SetStoveStart(os.time())", 1, true) ~= nil,
   "сервер пишет момент начала готовки")

ok(clSrc:find("StoveProgress()", 1, true) ~= nil,
   "ИСПРАВЛЕНО: табличка над плитой берёт долю готовности")
ok(clSrc:find("draw.RoundedBox(3, bx, by, math.max(2, bw * frac)", 1, true) ~= nil,
   "и рисует полосу, а не только секунды")
ok(clSrc:find('math.floor(frac * 100) .. "%"', 1, true) ~= nil,
   "с процентами — как в окне кухни")

-- Живая проверка формулы.
do
    local function progress(state, start, finish, now)
        if state ~= 1 then return 0 end
        local total = finish - start
        if total <= 0 then return 0 end
        return math.Clamp(1 - ((finish - now) / total), 0, 1)
    end
    ok(progress(1, 0, 100, 0) == 0, "в начале готовки 0%")
    ok(progress(1, 0, 100, 50) == 0.5, "на середине 50%", progress(1,0,100,50))
    ok(progress(1, 0, 100, 100) == 1, "в конце 100%")
    ok(progress(0, 0, 100, 50) == 0, "плита свободна — бара нет")
    ok(progress(1, 0, 0, 50) == 0, "нулевая длительность не делит на ноль")
    ok(progress(1, 0, 100, 500) == 1, "переработка не даёт больше 100%")

    --[[ Главное, ради чего вводился StoveStart: одинаковый остаток при
         разной длительности должен давать РАЗНЫЙ прогресс. ]]
    local shortR = progress(1, 0, 60, 50)      -- минутный рецепт, 10 сек до конца
    local longR  = progress(1, 0, 1800, 1790)  -- получасовой, тоже 10 сек
    ok(shortR > 0.8 and longR > 0.8,
       "при остатке в 10 секунд оба показывают «почти готово»",
       ("%.2f и %.2f"):format(shortR, longR))
    local shortMid = progress(1, 0, 60, 30)
    local longMid  = progress(1, 0, 1800, 30)
    ok(shortMid > longMid,
       "ИСПРАВЛЕНО: через 30 сек минутный рецепт готов наполовину, а получасовой почти не начат",
       ("%.2f против %.2f"):format(shortMid, longMid))
end

-- Восстановление после рестарта не сбрасывает бар в ноль.
ok(initSrc:find("self:SetStoveStart(os.time() - math.max(0, total - remain))", 1, true) ~= nil,
   "после рестарта прогресс сохраняется, а не начинается заново")

-----------------------------------------------------------------------
print("\n=== 9. КЛИЕНТСКАЯ ЧАСТЬ ===")
-----------------------------------------------------------------------
ok(slotsSrc:find("ClientsideModel(SS.CubeModel", 1, true) ~= nil,
   "кубики клиентские — не грузят сервер и их нельзя своровать")
ok(slotsSrc:find("if istable(stove.GRMSlotCubes) then return stove.GRMSlotCubes end", 1, true) ~= nil,
   "создаются один раз на плиту, а не каждый кадр")
ok(slotsSrc:find("SS.DrawDistance", 1, true) ~= nil,
   "далёкие плиты не рисуют конфорки — бережём кадр")
--[[ Хук уборки живёт в блоке `if CLIENT`, поэтому в исходнике он с
     отступом — прежний шаблон его не находил. Ищем по содержимому. ]]
local cleanup = slotsSrc:match('"GRM_StoveSlots_Cleanup".-\n    end%)')
ok(cleanup and cleanup:find("m:Remove()", 1, true) ~= nil,
   "при удалении плиты кубики убираются — не висят в мире")
ok(cleanup and cleanup:find("ent.GRMSlotCubes = nil", 1, true) ~= nil,
   "и ссылка на них очищается")
ok(slotsSrc:find("cooking and COL_COOK", 1, true) ~= nil,
   "занятая конфорка под готовкой подсвечена «горячим» цветом")

ok(isfunction(commands["grm_stove_slots"]), "есть команда диагностики")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
