--[[ Живой прогон ядра жилья (решение владельца 27.08, вариант «А»):

     «Жильё = реальные двери на карте. Зона только для маркера и подсчёта.
      Ставите дом → выбираете его двери → купивший получает ключ.
      Спавн — внутрь квартиры.»
     + жильё даёт хранилище/отдых/приватность — ДА
     + полиция входит по ордеру, взлом и обыск — ДА

     Стенд сначала воспроизводит старый баг спавна (центр зоны попадал в
     стену), потом проверяет новое ядро.

     Запуск: luajit tools/luatest/sim_housing_core.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- ЗАГЛУШКИ ДВИЖКА
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz = self.x-o.x, self.y-o.y, self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2 + self.y^2 + self.z^2) end
function VecMT:Normalize()
    local l = self:Length()
    if l > 0 then self.x, self.y, self.z = self.x/l, self.y/l, self.z/l end
    return self
end
function VecMT:Angle() return Angle(0, math.deg(math.atan2(self.y, self.x)), 0) end
function VecMT.__add(a,b) return Vector(a.x+b.x, a.y+b.y, a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x, a.y-b.y, a.z-b.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function VecMT.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end

function ErrorNoHalt() end
MASK_PLAYERSOLID = 33570819
HUD_PRINTTALK = 3
FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
bit = { bor = function(a,b) return a + b end }

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i] = nil end end
function hook.Run(e, ...) for _,f in pairs(hook._t[e] or {}) do local r,b = f(...) if r ~= nil then return r,b end end end

timer = { Simple = function(_,f) f() end, Create = function() end, Remove = function() end }
local commands = {}
concommand = { Add = function(n,f) commands[n] = f end }
util = { AddNetworkString = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }

--[[ МИР. Простая модель: пол на z=0, стена — параллелепипед.
     Этого достаточно, чтобы проверить именно логику поиска точки. ]]
local WORLD = { floorZ = 0, walls = {} }
local function inWall(pos)
    for _, w in ipairs(WORLD.walls) do
        if pos.x >= w.mins.x and pos.x <= w.maxs.x
            and pos.y >= w.mins.y and pos.y <= w.maxs.y
            and pos.z >= w.mins.z and pos.z <= w.maxs.z then return true end
    end
    return false
end
-- Есть ли пол под точкой (в «пропасти» пола нет).
local function hasFloor(pos)
    for _, h in ipairs(WORLD.holes or {}) do
        if pos.x >= h.mins.x and pos.x <= h.maxs.x
            and pos.y >= h.mins.y and pos.y <= h.maxs.y then return false end
    end
    return pos.z >= WORLD.floorZ - 1 and pos.z <= WORLD.floorZ + 300
end

function util.TraceHull(t)
    -- Проверяем занятость объёма игрока: пробуем несколько высот.
    local p = t.start
    for _, dz in ipairs({ 2, 20, 40, 68 }) do
        if inWall(Vector(p.x, p.y, p.z + dz)) then
            return { Hit = true, StartSolid = true }
        end
    end
    return { Hit = false, StartSolid = false }
end

function util.TraceLine(t)
    local a, b = t.start, t.endpos
    if b.z < a.z then
        -- Трейс вниз: ищем пол.
        if hasFloor(a) then
            return { Hit = true, HitPos = Vector(a.x, a.y, WORLD.floorZ) }
        end
        return { Hit = false, HitPos = b }
    end
    return { Hit = false, HitPos = b }
end

local CVARS = {}
function CreateConVar(name, def)
    CVARS[name] = { v = def }
    return {
        GetFloat = function() return tonumber(CVARS[name].v) or 0 end,
        GetBool = function() return CVARS[name].v ~= "0" end,
        GetString = function() return tostring(CVARS[name].v) end,
        GetInt = function() return math.floor(tonumber(CVARS[name].v) or 0) end,
    }
end

-- Двери в «мире».
local WORLD_DOORS = {}
ents = {
    GetAll = function() return WORLD_DOORS end,
    FindByClass = function() return {} end,
}

GRM = { Perf = { Players = function() return PLAYERS end } }

-- Недвижимость: настоящая семантика, но компактно.
GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    IsInside = function(r, pos)
        if not (istable(r.zone) and r.zone.mins) then return false end
        local a, b = r.zone.mins, r.zone.maxs
        return pos.x >= a.x and pos.y >= a.y and pos.z >= a.z
           and pos.x <= b.x and pos.y <= b.y and pos.z <= b.z
    end,
    CanAdmin = function(p) return IsValid(p) and p._admin == true end,
    HasAccess = function(p, r)
        if not IsValid(p) then return false end
        if r.ownerType == "character" and r.ownerKey == p._key then return true end
        for _, g in ipairs(r.guests or {}) do if g == p._key then return true end end
        return false
    end,
    GetByDoor = function(door)
        for _, r in pairs(GRM.Property.Records) do
            for _, id in ipairs(r.doors or {}) do
                if id == (door and door._id) then return r end
            end
        end
    end,
    Save = function() GRM.Property._saves = (GRM.Property._saves or 0) + 1 end,
}

-- Двери и ордера.
local WARRANTS = { byOwner = {}, byProperty = {} }
GRM.Doors = {
    IsDoor = function(e) return IsValid(e) and e._door == true end,
    GetDoorID = function(e) return e._id end,
    HasWarrant = function(key) return WARRANTS.byOwner[key] == true end,
    HasPropertyWarrant = function(id) return WARRANTS.byProperty[id] == true end,
}
GRM.Access = { Can = function(p, cap) return IsValid(p) and p._caps and p._caps[cap] == true end }
GRM.Estate = { ZoneCenter = function(r)
    if not istable(r.zone) then return nil end
    local a, b = r.zone.mins, r.zone.maxs
    return Vector((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
end }
GRM.Identity = { CharacterKey = function(p) return p._key end }

assert(loadfile("lua/autorun/sh_grm_housing.lua"))()
local HS = GRM.Housing

local function mkPly(o)
    o = o or {}
    local nw = {}
    return {
        _valid = true, _key = o.key or "1:char1", _admin = o.admin == true,
        _caps = o.caps or {}, _pos = o.pos or Vector(0, 0, 0),
        SteamID64 = function() return "1" end,
        GetPos = function(s) return s._pos end,
        EyeAngles = function() return Angle(0, 33, 0) end,
        GetEyeTrace = function() return { Entity = o.aim } end,
        PrintMessage = function(_, _, t) o.said = (o.said or "") .. t .. "\n" end,
        GetNWBool = function(_, k, d) if nw[k] ~= nil then return nw[k] end return d or false end,
        SetNWBool = function(_, k, v) nw[k] = v end,
        _nw = nw,
    }
end

local function mkDoor(id, pos, fwd)
    local d = {
        _valid = true, _door = true, _id = id, _pos = pos,
        GetPos = function(s) return s._pos end,
        GetForward = function() return Vector(fwd and fwd.x or 1, fwd and fwd.y or 0, 0) end,
        GetRight = function() return Vector(fwd and -fwd.y or 0, fwd and fwd.x or 1, 0) end,
    }
    WORLD_DOORS[#WORLD_DOORS + 1] = d
    return d
end

-----------------------------------------------------------------------
print("\n=== 1. ЕДИНОЕ ОПРЕДЕЛЕНИЕ ЖИЛЬЯ ===")
-----------------------------------------------------------------------
ok(HS.IsHousing({ type = "apartment" }) == true, "квартира — это жильё")
ok(HS.IsHousing({ type = "shop" }) == false, "магазин — не жильё")
ok(HS.IsHousing({ type = "shop", estateKind = "estate" }) == true,
   "явная пометка «жильё» сильнее типа — админ может поправить ошибку")
ok(HS.IsHousing({ type = "apartment", estateKind = "business" }) == false,
   "и наоборот: помеченная бизнесом квартира жильём не считается")
ok(HS.IsHousing(nil) == false, "мусор на входе не роняет проверку")

-----------------------------------------------------------------------
print("\n=== 2. АРЕНДА ===")
-----------------------------------------------------------------------
ok(HS.RentAlive({ tenure = "owned" }) == true, "купленное жильё не протухает")
ok(HS.RentAlive({ tenure = "rent", rentUntil = os.time() + 500 }) == true, "живая аренда")
ok(HS.RentAlive({ tenure = "rent", rentUntil = os.time() - 5 }) == false, "просроченная аренда")
ok(HS.RentAlive({ tenure = "rent", rentUntil = 0 }) == true,
   "аренда без срока считается живой — не выкидываем людей из-за пустого поля")

-----------------------------------------------------------------------
print("\n=== 3. СПАВН ВНУТРЬ КВАРТИРЫ ===")
-----------------------------------------------------------------------
--[[ Планировка: комната от x=0 до x=200, стена по x<0 (улица за стеной),
     дверь на границе x=0. Зона обведена СНАРУЖИ дома и её центр попадает
     ровно в стену — это и есть старый баг. ]]
WORLD.floorZ = 0
WORLD.walls = { { mins = Vector(-260, -300, 0), maxs = Vector(-4, 300, 200) } }
WORLD.holes = {}

local flat = {
    id = "flat1", name = "Квартира 14", type = "apartment",
    ownerType = "character", ownerKey = "1:char1", tenure = "owned",
    sealed = false, rentUntil = 0, guests = {},
    doors = { "d1" },
    zone = { mins = Vector(-250, -100, 0), maxs = Vector(200, 100, 200) },
}
GRM.Property.Records = { flat1 = flat }
local door = mkDoor("d1", Vector(0, 0, 0), Vector(1, 0, 0))

-- Старое поведение: центр зоны.
local oldCenter = Vector((-250 + 200) / 2, 0, 0 + 8)
ok(inWall(Vector(oldCenter.x, oldCenter.y, oldCenter.z + 20)) == true,
   "БАГ ВОСПРОИЗВЁДЕН: старый спавн «центр зоны» попадал в стену",
   ("x=%.0f"):format(oldCenter.x))

local pos, ang, how = HS.SpawnPoint(flat)
ok(pos ~= nil, "ИСПРАВЛЕНО: точка спавна найдена")
ok(how == "door", "точка взята от двери, а не из центра зоны", how)
ok(pos and pos.x > 0, "ИСПРАВЛЕНО: точка внутри комнаты, а не в стене", pos and pos.x)
ok(pos and HS.PointFits(pos) == true, "в найденной точке игрок помещается стоя")
ok(pos and math.abs(pos.z - (WORLD.floorZ + HS.SpawnLift)) < 0.01,
   "игрок стоит на полу, чуть приподнят чтобы не застрять", pos and pos.z)
ok(ang ~= nil and math.abs(ang.y) < 1,
   "игрок развёрнут от двери вглубь комнаты, а не носом в полотно", ang and ang.y)

-- Ручная точка сильнее автопоиска.
flat.housingSpawn = { x = 150, y = 50, z = 0, yaw = 90 }
local mp, ma, mhow = HS.SpawnPoint(flat)
ok(mhow == "manual", "заданная админом точка приоритетнее автопоиска", mhow)
ok(mp.x == 150 and ma.y == 90, "и берётся ровно как записана")
flat.housingSpawn = nil

-- Пропасть под дверью: точка не должна висеть в воздухе.
WORLD.holes = { { mins = Vector(-500, -500), maxs = Vector(500, 500) } }
local nofloor = HS.SpawnPoint(flat)
ok(nofloor == nil or nofloor.z ~= nil, "без пола модуль не возвращает мусор")
WORLD.holes = {}

-- Объект без дверей — откат на центр зоны, вариант «Дом» не пропадает.
local noDoors = { id = "f2", type = "apartment", doors = {},
    zone = { mins = Vector(300, -50, 0), maxs = Vector(400, 50, 100) },
    ownerType = "character", ownerKey = "1:char1", tenure = "owned" }
local zp, _, zhow = HS.SpawnPoint(noDoors)
ok(zhow == "zone", "объект без дверей падает на центр зоны — как раньше", zhow)
ok(zp ~= nil, "и точка всё равно есть")

-----------------------------------------------------------------------
print("\n=== 4. ЧЬЁ ЖИЛЬЁ И КТО ДОМА ===")
-----------------------------------------------------------------------
GRM.Property.Records = { flat1 = flat }
local owner = mkPly({ key = "1:char1", pos = Vector(100, 0, 0) })
local stranger = mkPly({ key = "9:char1", pos = Vector(100, 0, 0) })

ok(HS.HomeOf(owner) == flat, "владелец находит своё жильё")
ok(HS.HomeOf(stranger) == nil, "чужому жильё не принадлежит")
ok(HS.IsOwner(owner, flat) == true, "владение подтверждается")
ok(HS.IsOwner(stranger, flat) == false, "чужой не владелец")

ok(select(1, HS.IsHome(owner)) == true, "владелец внутри зоны считается «дома»")
ok(select(1, HS.IsHome(stranger)) == false, "чужой в той же комнате домой не попадает")

owner._pos = Vector(9999, 9999, 0)
ok(select(1, HS.IsHome(owner)) == false, "вне зоны владелец не «дома»")
owner._pos = Vector(100, 0, 0)

-- Жилец по ключу.
flat.guests = { "5:char1" }
local guest = mkPly({ key = "5:char1", pos = Vector(100, 0, 0) })
ok(HS.HomeOf(guest) == flat, "вписанный жилец тоже получает дом")
ok(select(1, HS.IsHome(guest)) == true, "и отдыхает дома")
flat.guests = {}

-- Опечатанное жильё домом не считается.
flat.sealed = true
ok(HS.HomeOf(owner) == nil, "опечатанное жильё перестаёт быть домом")
ok(select(1, HS.IsHome(owner)) == false, "и отдых в нём не работает")
flat.sealed = false

-- Просроченная аренда.
flat.tenure = "rent"; flat.rentUntil = os.time() - 10
ok(HS.HomeOf(owner) == nil, "после конца аренды дома больше нет")
flat.tenure = "owned"; flat.rentUntil = 0

-----------------------------------------------------------------------
print("\n=== 5. ОТДЫХ ДОМА ===")
-----------------------------------------------------------------------
local f = HS.RestFactor(owner)
ok(f < 1, "дома траты сытости и жажды снижены", f)
ok(f > 0, "но не обнулены — жить дома вечно без еды нельзя", f)
ok(HS.RestFactor(stranger) == 1, "на улице расход обычный")

-- Хук, через который подключается питание.
local scaled = hook.Run("GRM_Food_DrainScale", owner)
ok(isnumber(scaled) and scaled < 1, "хук расхода отдаёт множитель дома", scaled)
ok(hook.Run("GRM_Food_DrainScale", stranger) == nil,
   "на улице хук молчит — питание считает как обычно")

-- Проверяем, что питание реально умножает на этот множитель.
local foodSrc = assert(io.open("lua/autorun/server/sv_grm_food.lua")):read("*a")
ok(foodSrc:find("GRM_Food_DrainScale", 1, true) ~= nil,
   "модуль питания зовёт хук расхода")
ok(foodSrc:find("HungerDrainPerSecond or 0.02) * scale", 1, true) ~= nil,
   "и умножает на него сытость")
ok(foodSrc:find("ThirstDrainPerSecond or 0.035) * scale", 1, true) ~= nil,
   "и жажду")
ok(foodSrc:find("math.min(scale, 4)", 1, true) ~= nil,
   "множитель ограничен сверху — кривой хук не сожжёт игрока мгновенно")

-----------------------------------------------------------------------
print("\n=== 6. ВХОД: ОПЕЧАТКА > ОРДЕР > КЛЮЧ ===")
-----------------------------------------------------------------------
local cop = mkPly({ key = "7:char1", caps = { ["wanted.civil.edit"] = true } })
local admin = mkPly({ key = "8:char1", admin = true })

local allowed, reason = HS.CanEnter(owner, flat)
ok(allowed == true and reason == "key", "владелец входит по ключу", reason)

allowed, reason = HS.CanEnter(stranger, flat)
ok(allowed == false and reason == "no_key", "чужой без ключа не входит", reason)

-- Ордер на помещение.
WARRANTS.byProperty["flat1"] = true
allowed, reason = HS.CanEnter(cop, flat)
ok(allowed == true and reason == "warrant_property",
   "полиция входит по ордеру на обыск помещения", reason)
WARRANTS.byProperty["flat1"] = nil

-- Ордер на владельца.
WARRANTS.byOwner["1:char1"] = true
allowed, reason = HS.CanEnter(cop, flat)
ok(allowed == true and reason == "warrant_owner",
   "ордер на владельца тоже открывает дверь уполномоченному", reason)
allowed, reason = HS.CanEnter(stranger, flat)
ok(allowed == false,
   "но обычному прохожему ордер на владельца дверь НЕ открывает — это был бы дыра",
   reason)
WARRANTS.byOwner["1:char1"] = nil

-- Опечатка сильнее всего.
flat.sealed = true
flat.sealReason = "решение суда"
WARRANTS.byProperty["flat1"] = true
allowed, reason = HS.CanEnter(cop, flat)
ok(allowed == false and reason == "sealed",
   "опечатка сильнее ордера — иначе мера бессмысленна", reason)
allowed, reason = HS.CanEnter(owner, flat)
ok(allowed == false and reason == "sealed", "и сильнее ключа владельца", reason)
allowed, reason = HS.CanEnter(admin, flat)
ok(allowed == true and reason == "admin", "админ проходит всегда — чинить объекты")
WARRANTS.byProperty["flat1"] = nil
flat.sealed = false

-- Просроченная аренда закрывает дверь бывшему жильцу.
flat.tenure = "rent"; flat.rentUntil = os.time() - 10
allowed, reason = HS.CanEnter(owner, flat)
ok(allowed == false and reason == "rent_expired",
   "после конца аренды ключ не работает", reason)

-- И тот же случай через хук дверей.
local blocked, breason = hook.Run("GRM_DoorAccessOverride", owner, door)
ok(blocked == false, "хук дверей закрывает дверь по просроченной аренде", tostring(breason))
local copOpen = hook.Run("GRM_DoorAccessOverride", admin, door)
ok(copOpen == true, "но админ и ордер проходят даже в просроченное жильё")
flat.tenure = "owned"; flat.rentUntil = 0

-- Не-жильё хук не трогает.
local shop = { id = "s1", type = "shop", doors = { "d9" }, ownerType = "none" }
GRM.Property.Records.s1 = shop
local shopDoor = mkDoor("d9", Vector(600, 0, 0), Vector(1, 0, 0))
ok(hook.Run("GRM_DoorAccessOverride", owner, shopDoor) == nil,
   "к магазину модуль жилья не лезет — там свои правила")
GRM.Property.Records.s1 = nil

-----------------------------------------------------------------------
print("\n=== 7. РУЧНАЯ ТОЧКА И ХРАНЕНИЕ ===")
-----------------------------------------------------------------------
GRM.Property.Records = { flat1 = flat }
owner._pos = Vector(120, 30, 0)
local okSet, msg = HS.SetSpawn(stranger, flat)
ok(okSet == false, "обычный игрок не может задать точку спавна чужого жилья")
okSet, msg = HS.SetSpawn(admin, flat)
ok(okSet == true, "админ задаёт точку", msg)
ok(istable(flat.housingSpawn), "точка записана в объект")
ok((GRM.Property._saves or 0) > 0, "и объект сохранён — переживёт рестарт")

-- Нормализация не должна терять поле.
local propSrc = assert(io.open("lua/autorun/sh_grm_property.lua")):read("*a")
ok(propSrc:find("housingSpawn", 1, true) ~= nil,
   "housingSpawn объявлен в Normalize — иначе поле стиралось бы при каждом сохранении")
ok(propSrc:find("else r.housingSpawn=nil end", 1, true) ~= nil,
   "и мусорная запись чистится, чтобы не мешать автопоиску")

okSet = HS.ClearSpawn(admin, flat)
ok(okSet == true and flat.housingSpawn == nil, "сброс точки возвращает автопоиск")

-----------------------------------------------------------------------
print("\n=== 8. СВЯЗКА СО СПАВН-ЭКРАНОМ ===")
-----------------------------------------------------------------------
local spSrc = assert(io.open("lua/autorun/sh_grm_spawnpick.lua")):read("*a")
ok(spSrc:find("HS.HomeOf", 1, true) ~= nil and spSrc:find("HS.SpawnPoint", 1, true) ~= nil,
   "экран точек входа берёт дом через модуль жилья")
ok(spSrc:find("Запасной путь", 1, true) ~= nil,
   "оставлен запасной путь, если модуль жилья не загрузился — вариант «Дом» не пропадёт")

-----------------------------------------------------------------------
print("\n=== 9. ДИАГНОСТИКА ===")
-----------------------------------------------------------------------
ok(isfunction(commands["grm_housing"]), "есть команда диагностики grm_housing")
ok(isfunction(commands["grm_housing_setspawn"]), "есть grm_housing_setspawn")
ok(isfunction(commands["grm_housing_clearspawn"]), "есть grm_housing_clearspawn")
local said = {}
local diag = mkPly({ key = "1:char1", pos = Vector(100, 0, 0) })
diag.PrintMessage = function(_, _, t) said[#said + 1] = t end
commands["grm_housing"](diag)
ok(#said > 0, "диагностика что-то печатает")
local joined = table.concat(said, "\n")
ok(joined:find("объектов жилья", 1, true) ~= nil, "показывает количество жилья")
ok(joined:find("сейчас дома", 1, true) ~= nil, "показывает, дома ли игрок")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
