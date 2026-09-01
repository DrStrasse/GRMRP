--[[--------------------------------------------------------------------
    sim_interact_abuse — случайный человек не должен через E открывать
    чужие двери; свой транспорт фракции должен открываться.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08):
      1) «Надо предусмотреть, чтобы каждый случайный рандомный человек
         через Е не мог заабузить двери, открыть допустим чужие
         фракционные двери и т.д.»
      2) «пытаюсь через Е отпереть дверь машины, пишет нет ключа или
         доступа, хотя машина фракционная».

    ПРИЧИНА БАГА №2. VK.CanInteract объявлена ТОЛЬКО на сервере
    (sv_vehicle_keys.lua) и читает серверные поля veh.VK_*. Модуль
    взаимодействия звал её и на клиенте, чтобы нарисовать меню: там её
    просто нет, вызов возвращал nil, и все пункты гасли с «Нет ключа
    или доступа» — даже у своей фракции. На сервере при этом права
    считались верно, то есть ломался только показ.

    ЧТО ПРОВЕРЯЕМ ПО БЕЗОПАСНОСТИ. Клиент присылает лишь «объект + id
    действия». Стенд подделывает пакеты так, как это сделал бы игрок с
    правленым клиентом, и смотрит, что сервер РЕАЛЬНО выполнил.

    Запуск: luajit tools/luatest/sim_interact_abuse.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Мок GMod (сервер).
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return istable(v) and v._valid ~= false end

local NOW = 100
function CurTime() return NOW end
function RealTime() return NOW end
function FrameTime() return 0.016 end

local VMeta = {}
VMeta.__index = VMeta
function VMeta:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
VMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMeta.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMeta) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.Approach = function(c, t, i) return t end

hook = { Add = function() end, Remove = function() end, Run = function() end, Call = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = {
    AddNetworkString = function() end,
    TraceLine = function() return { Entity = _G.__TRACE_HIT or { _valid = false } } end,
}
MASK_SHOT = 1
local NETRECV = {}
net = {
    Receive = function(n, f) NETRECV[n] = f end,
    Start = function() end, Send = function() end, Broadcast = function() end,
    SendToServer = function() end, WriteEntity = function() end, WriteString = function() end,
    ReadEntity = function() return _G.__NET_ENT end,
    ReadString = function() return _G.__NET_STR or "" end,
}
concommand = { Add = function() end }
function CreateClientConVar() end
function GetConVarNumber() return 1 end
surface = setmetatable({}, { __index = function() return function() return 10, 10 end end })
draw = setmetatable({}, { __index = function() return function() end end })
gui = { MousePos = function() return 0, 0 end, EnableScreenClicker = function() end,
        IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end }
input = { IsKeyDown = function() return false end }
vgui = { Create = function() return { _valid = false } end }
function ScrW() return 1920 end
function ScrH() return 1080 end
KEY_E = 22
MOUSE_LEFT, MOUSE_RIGHT = 107, 108
IN_ATTACK, IN_ATTACK2, IN_USE = 1, 2, 32
bit = { bor = function(a, b) if a % (b * 2) >= b then return a end return a + b end }

local NOTIFIED = {}
GRM = { Notify = function(_, msg) NOTIFIED[#NOTIFIED + 1] = tostring(msg) end }
GRM.Net = { Guard = function() return true end }
GRM.Utf8Ellipsis = function(s) return s end

-----------------------------------------------------------------------
-- Ядро дверей: повторяем ТОЛЬКО контракт, которым пользуется модуль.
-- Права считает оно, и подменять их логику нельзя — иначе стенд
-- проверял бы выдумку.
-----------------------------------------------------------------------
local LOCKED = {}
local MENU_OPENED = {}

local function mkDoor(opts)
    opts = opts or {}
    local d = { _valid = true, _locked = opts.locked ~= false, _nw = {}, _nwb = {} }
    d._ownerFaction = opts.faction        -- дверь принадлежит фракции
    d._ownerKey = opts.ownerKey           -- или игроку
    function d:GetNWString(k, def) return self._nw[k] or def or "" end
    function d:GetNWBool(k, def) if self._nwb[k] == nil then return def or false end return self._nwb[k] end
    function d:GetParent() return { _valid = false } end
    function d:NearestPoint() return Vector(0, 0, 0) end
    function d:EmitSound() end
    return d
end

GRM.Doors = {
    IsDoor = function(e) return istable(e) and e._locked ~= nil end,
    IsDoorLocked = function(e) return e._locked == true end,
    --[[ Настоящее правило доступа: суперадмин, свой ключ или своя
         фракция. Ровно так рассуждает D.CanToggleLock в ядре. ]]
    CanToggleLock = function(ply, e)
        if ply._super then return true end
        if e._ownerFaction then
            if ply._faction == e._ownerFaction then return true end
            return false, "У вас нет ключей от этой двери."
        end
        if e._ownerKey then
            if ply._key == e._ownerKey then return true end
            return false, "У вас нет ключей от этой двери."
        end
        return true
    end,
    LockDoor = function(e, want)
        LOCKED[#LOCKED + 1] = want
        e._locked = want
        return true, want, false
    end,
    OpenDoorMenu = function(p) MENU_OPENED[#MENU_OPENED + 1] = p end,
}

local VEH_ACTS = {}
local function mkVeh(opts)
    opts = opts or {}
    local v = { _valid = true, VK_Locked = opts.locked ~= false }
    v.VK_OwnerType = opts.ownerType
    v.VK_FactionName = opts.faction
    v.VK_OwnerSteam = opts.ownerSteam
    v._nw2 = { VK_OwnerType = opts.ownerType or "", VK_FactionName = opts.faction or "",
               VK_OwnerSteam = opts.ownerSteam or "" }
    v._nw2b = { VK_Locked = opts.locked ~= false }
    function v:GetNW2Bool(k, d) if self._nw2b[k] == nil then return d or false end return self._nw2b[k] end
    function v:GetNW2String(k, d) return self._nw2[k] or d or "" end
    function v:GetParent() return { _valid = false } end
    function v:NearestPoint() return Vector(0, 0, 0) end
    function v:EmitSound() end
    return v
end

_G.VK = {
    OWNER_TYPE = { PLAYER = "player", FACTION = "faction" },
    IsVehicle = function(e) return istable(e) and e.VK_Locked ~= nil end,
    GetVehicleDisplayName = function() return "Волга" end,
    GetOwnerState = function(veh)
        if CLIENT then
            return veh:GetNW2String("VK_OwnerType", ""), veh:GetNW2String("VK_OwnerSteam", ""),
                "", veh:GetNW2String("VK_FactionName", ""), veh:GetNW2Bool("VK_Locked", false)
        end
        return veh.VK_OwnerType or "", veh.VK_OwnerSteam or "", "",
            veh.VK_FactionName or "", veh.VK_Locked == true
    end,
    -- Серверное правило: владелец или своя фракция.
    CanInteract = function(veh, ply)
        if ply._super then return true end
        if veh.VK_OwnerType == "faction" then return ply._faction == veh.VK_FactionName end
        if veh.VK_OwnerType == "player" then return ply._sid64 == veh.VK_OwnerSteam end
        return true
    end,
    ToggleLock = function(_, v) VEH_ACTS[#VEH_ACTS + 1] = "lock" v.VK_Locked = not v.VK_Locked end,
    ToggleDoors = function() VEH_ACTS[#VEH_ACTS + 1] = "doors" end,
}

local function mkPly(opts)
    opts = opts or {}
    local p = { _valid = true }
    p._faction = opts.faction or ""
    p._key = opts.key
    p._super = opts.super == true
    p._sid64 = opts.sid64 or "76561100000000001"
    function p:IsPlayer() return true end
    function p:Alive() return true end
    function p:InVehicle() return false end
    function p:IsSuperAdmin() return self._super end
    function p:SteamID64() return self._sid64 end
    function p:SteamID() return "STEAM_0:1:1" end
    function p:GetShootPos() return Vector(0, 0, 0) end
    function p:GetAimVector() return Vector(1, 0, 0) end
    function p:GetNWString(k, d)
        if k == "GRM_Faction" then return self._faction end
        return d or ""
    end
    function p:EmitSound() end
    return p
end

assert(loadfile("lua/autorun/sh_grm_interact.lua"))()
local I = GRM.Interact
assert(I, "модуль не загрузился")

local recv = NETRECV["GRM_Interact_Act"]
assert(recv, "обработчик действия не зарегистрирован")

local function send(ply, ent, id)
    _G.__NET_ENT, _G.__NET_STR = ent, id
    LOCKED, VEH_ACTS, MENU_OPENED, NOTIFIED = {}, {}, {}, {}
    NOW = NOW + 5      -- уводим время, чтобы не мешал кулдаун стука
    recv(64, ply)
end

-----------------------------------------------------------------------
print("\n=== 1. ЧУЖАК НЕ ОТКРОЕТ ФРАКЦИОННУЮ ДВЕРЬ ===")
-----------------------------------------------------------------------
do
    local facDoor = mkDoor({ locked = true, faction = "Полиция" })
    local rando = mkPly({ faction = "" })

    send(rando, facDoor, "door_unlock")
    ok(#LOCKED == 0, "случайный игрок не отпер фракционную дверь", #LOCKED)
    ok(facDoor._locked == true, "дверь осталась запертой")
    ok(#NOTIFIED > 0, "ему объяснили причину", NOTIFIED[1])

    -- И запереть чужую тоже не может.
    send(rando, facDoor, "door_lock")
    ok(#LOCKED == 0, "и запереть чужую не может")

    -- Игрок ЧУЖОЙ фракции — тоже посторонний.
    local other = mkPly({ faction = "Медики" })
    send(other, facDoor, "door_unlock")
    ok(#LOCKED == 0, "член другой фракции тоже не проходит", #LOCKED)
end

-----------------------------------------------------------------------
print("\n=== 2. СВОЙ ФРАКЦИОНЕР И АДМИН ПРОХОДЯТ ===")
-----------------------------------------------------------------------
do
    local facDoor = mkDoor({ locked = true, faction = "Полиция" })

    local cop = mkPly({ faction = "Полиция" })
    send(cop, facDoor, "door_unlock")
    ok(#LOCKED == 1 and LOCKED[1] == false, "свой фракционер отпирает дверь", #LOCKED)

    local locked2 = mkDoor({ locked = true, faction = "Полиция" })
    local admin = mkPly({ faction = "", super = true })
    send(admin, locked2, "door_unlock")
    ok(#LOCKED == 1, "суперадмин проходит", #LOCKED)
end

-----------------------------------------------------------------------
print("\n=== 3. ЧУЖАЯ ЛИЧНАЯ ДВЕРЬ ===")
-----------------------------------------------------------------------
do
    local mine = mkDoor({ locked = true, ownerKey = "OWNER_A" })

    local thief = mkPly({ key = "OWNER_B" })
    send(thief, mine, "door_unlock")
    ok(#LOCKED == 0, "чужую личную дверь не открыть", #LOCKED)

    local owner = mkPly({ key = "OWNER_A" })
    send(owner, mine, "door_unlock")
    ok(#LOCKED == 1, "владелец открывает свою", #LOCKED)
end

-----------------------------------------------------------------------
print("\n=== 4. ПОДДЕЛКА ПАКЕТА НЕ ПОМОГАЕТ ===")
-----------------------------------------------------------------------
do
    --[[ Игрок с правленым клиентом может прислать что угодно. Сервер
         обязан перепроверять всё сам. ]]
    local facDoor = mkDoor({ locked = true, faction = "Полиция" })
    local rando = mkPly({ faction = "" })

    -- Действие транспорта по двери.
    send(rando, facDoor, "veh_unlock")
    ok(#LOCKED == 0 and #VEH_ACTS == 0, "действие ТС по двери отброшено")

    -- Выдуманное действие.
    send(rando, facDoor, "door_open_please")
    ok(#LOCKED == 0, "неизвестное действие отброшено")

    -- Пустая строка и мусор.
    send(rando, facDoor, "")
    ok(#LOCKED == 0, "пустой id отброшен")

    -- Далёкая дверь: подошёл к одной, шлёт по другой на карте.
    local far = mkDoor({ locked = true, faction = "Полиция" })
    function far:NearestPoint() return Vector(9000, 0, 0) end
    local cop = mkPly({ faction = "Полиция" })
    send(cop, far, "door_unlock")
    ok(#LOCKED == 0, "дверь через полкарты не открыть даже своему", #LOCKED)
    ok(NOTIFIED[1] and NOTIFIED[1]:find("далеко", 1, true) ~= nil,
        "и причина названа", NOTIFIED[1])

    -- Мёртвый игрок.
    local dead = mkPly({ faction = "Полиция" })
    dead.Alive = function() return false end
    local d2 = mkDoor({ locked = true, faction = "Полиция" })
    send(dead, d2, "door_unlock")
    ok(#LOCKED == 0, "мёртвый не взаимодействует")
end

-----------------------------------------------------------------------
print("\n=== 5. МЕНЮ УПРАВЛЕНИЯ И СТУК ===")
-----------------------------------------------------------------------
do
    --[[ «Управление» доступно всем — но само меню фильтрует данные по
         правам (packDoorData отдаёт owner_key только владельцу и
         админу). Проверяем, что модуль зовёт именно ядро, а не строит
         свой ответ. ]]
    local src = readf("lua/autorun/sh_grm_interact.lua")
    ok(src:find("D.OpenDoorMenu(ply)", 1, true) ~= nil,
        "меню двери открывает ядро — оно и решает, что показать")

    local doors = readf("lua/autorun/sh_grm_doors.lua")
    ok(doors:find("if acc.own or acc.admin then", 1, true) ~= nil,
        "ядро отдаёт чувствительные поля только владельцу и админу")

    --[[ Стук слышен вокруг. Общий ограничитель даёт серию из 4 действий,
         и без своего кулдауна ими можно шуметь на весь квартал. ]]
    local knock = src:match("if id == \"door_knock\" then.-\n    end")
    ok(knock and knock:find("_grmKnockAt", 1, true) ~= nil,
        "у стука свой кулдаун против спама звуком")
end

do
    -- Кулдаун стука работает на деле.
    local door = mkDoor({ locked = true })
    local ply = mkPly({})
    local sounds = 0
    door.EmitSound = function() sounds = sounds + 1 end

    _G.__NET_ENT, _G.__NET_STR = door, "door_knock"
    NOW = NOW + 5
    recv(64, ply)
    local first = sounds
    -- Тут же ещё три раза, без паузы.
    for _ = 1, 3 do recv(64, ply) end
    ok(first == 1, "первый стук прошёл", first)
    ok(sounds == 1, "подряд идущие удары обрезаны кулдауном", sounds)

    NOW = NOW + 2
    recv(64, ply)
    ok(sounds == 2, "через паузу стучать можно снова", sounds)
end

-----------------------------------------------------------------------
print("\n=== 6. ТРАНСПОРТ: ПРАВА НА СЕРВЕРЕ ===")
-----------------------------------------------------------------------
do
    local facVeh = mkVeh({ locked = true, ownerType = "faction", faction = "Полиция" })

    local rando = mkPly({ faction = "" })
    send(rando, facVeh, "veh_unlock")
    ok(#VEH_ACTS == 0, "чужак не отпирает фракционную машину", #VEH_ACTS)

    send(rando, facVeh, "veh_doors")
    ok(#VEH_ACTS == 0, "и двери не открывает")

    local cop = mkPly({ faction = "Полиция" })
    send(cop, facVeh, "veh_unlock")
    ok(#VEH_ACTS == 1, "свой фракционер отпирает", #VEH_ACTS)

    local pveh = mkVeh({ locked = true, ownerType = "player", ownerSteam = "76561100000000009" })
    send(cop, pveh, "veh_unlock")
    ok(#VEH_ACTS == 0, "чужую личную машину не открыть", #VEH_ACTS)

    local owner = mkPly({ sid64 = "76561100000000009" })
    send(owner, pveh, "veh_unlock")
    ok(#VEH_ACTS == 1, "владелец открывает свою", #VEH_ACTS)
end

-----------------------------------------------------------------------
print("\n=== 7. БАГ: ФРАКЦИОННАЯ МАШИНА ПОКАЗЫВАЛАСЬ НЕДОСТУПНОЙ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ. На клиенте VK.CanInteract не существует —
         модуль звал её и получал nil, поэтому все пункты гасли даже у
         своей фракции. Теперь клиент считает по сетевым полям. ]]
    ok(isfunction(I.ClientCanVehicle), "появилась клиентская оценка доступа")

    local facVeh = mkVeh({ locked = true, ownerType = "faction", faction = "Полиция" })
    local cop = mkPly({ faction = "Полиция" })
    local rando = mkPly({ faction = "" })

    -- На сервере GetOwnerState отдаёт серверные поля — они заполнены.
    ok(I.ClientCanVehicle(facVeh, cop) == true,
        "ИСПРАВЛЕНО: своей фракции пункт показывается живым")
    ok(I.ClientCanVehicle(facVeh, rando) == false,
        "чужаку — приглушённым")

    local admin = mkPly({ faction = "", super = true })
    ok(I.ClientCanVehicle(facVeh, admin) == true, "админу живым")

    local free = mkVeh({ locked = true, ownerType = nil })
    ok(I.ClientCanVehicle(free, rando) == true, "бесхозная машина доступна всем")

    --[[ Показ НИ НА ЧТО не влияет: даже если клиент нарисовал пункт
         живым, сервер откажет. Это главное свойство схемы. ]]
    local src = readf("lua/autorun/sh_grm_interact.lua")
    ok(src:find("if SERVER then\n            can = V.CanInteract", 1, true) ~= nil,
        "на сервере права спрашиваются у ядра, а не у клиентской прикидки")

    --[[ КЛЮЧЕВАЯ ПРОВЕРКА БАГА. На КЛИЕНТЕ функции VK.CanInteract не
         существует — она объявлена только в sv_vehicle_keys.lua.
         Раньше модуль звал её и там, получал nil, и пункты гасли даже
         у своей фракции.

         Проверяем это буквально: убираем CanInteract, как её «не
         видит» клиент, и строим меню клиентской веткой. Пункты обязаны
         остаться живыми. ]]
    local savedCan = _G.VK.CanInteract
    _G.VK.CanInteract = nil
    local savedServer = SERVER
    SERVER, CLIENT = false, true

    local acts = I.Actions(cop, facVeh, "vehicle")
    ok(acts[1] and acts[1].enabled == true,
        "ИСПРАВЛЕНО: без серверной CanInteract пункт своей фракции живой",
        acts[1] and tostring(acts[1].enabled))

    local actsBad = I.Actions(rando, facVeh, "vehicle")
    ok(actsBad[1] and actsBad[1].enabled == false,
        "и чужак при этом всё равно видит пункт серым")

    SERVER, CLIENT = savedServer, false
    _G.VK.CanInteract = savedCan

    -- И проверка в runAction осталась на месте.
    local run = src:match("local function runAction.-\n    if id == \"veh_trunk\"")
    ok(src:find("if allowed.enabled == false then", 1, true) ~= nil,
        "сервер отклоняет недоступное действие независимо от клиента")
end

-----------------------------------------------------------------------
print("\n=== 8. ОГРАНИЧИТЕЛЬ ЧАСТОТЫ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_interact.lua")
    ok(src:find("GRM.Net.Guard(ply, \"interact.act\"", 1, true) ~= nil,
        "обработчик под общим ограничителем")
    ok(src:find("maxBits = 256", 1, true) ~= nil,
        "размер пакета ограничен — распухшим не завалить")
    ok(src:find("string.sub(tostring(net.ReadString() or \"\"), 1, 32)", 1, true) ~= nil,
        "id действия обрезается по длине")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
