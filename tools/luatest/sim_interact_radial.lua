--[[--------------------------------------------------------------------
    sim_interact_radial — интерактивное взаимодействие с дверями и
    транспортом: точка, подсказка и кольцевое меню по удержанию E.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «при подходе к двери у персонажа появлялась
    точка маленькая, и подсказка нажмите Е для взаимодействия, возникает
    возле двери круговое интерактивное живое меню с функцией
    открыть/закрыть… тоже самое касается двери машины… нужно соблюсти
    стилистику проекта, и при этом чтобы текст не был чёрным как иногда
    вы выдаёте, что фон меню тёмный, текст чёрный и ничего нечитабельно».

    ЧТО ПРОВЕРЯЕМ (боевой модуль, а не пересказ логики):

      * СЕРВЕР НЕ ВЕРИТ КЛИЕНТУ. Пакет содержит только «объект + id
        действия»; сервер сам ищет цель, меряет дистанцию и спрашивает
        права у профильных модулей. Подделанный пакет не должен
        открывать чужую дверь;
      * набор действий зависит от состояния: у запертой двери «Отпереть»,
        у открытой «Запереть»;
      * недоступные действия не исчезают, а гаснут с причиной — иначе
        игрок не понимает, чего ему не хватает;
      * геометрия кольца: подпись лежит там, куда ведёт курсор, и в
        центре есть мёртвая зона (там название объекта);
      * ЧИТАЕМОСТЬ: в модуле нет тёмного текста — отдельная жалоба
        владельца;
      * короткое нажатие E остаётся обычным «использовать», кольцо
        приходит только по удержанию.

    Запуск: luajit tools/luatest/sim_interact_radial.lua
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
-- Мок GMod (серверная сторона модуля).
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return istable(v) and v._valid ~= false end
function CurTime() return 100 end
function RealTime() return 100 end
function FrameTime() return 0.016 end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.Approach = function(cur, target, inc)
    inc = math.abs(inc)
    if cur < target then return math.min(cur + inc, target) end
    if cur > target then return math.max(cur - inc, target) end
    return target
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

local VMeta = {}
VMeta.__index = VMeta
function VMeta:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
VMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMeta.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMeta) end

local HOOKS = {}
hook = {
    Add = function(e, n, f) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = f end,
    Remove = function() end, Run = function() end, Call = function() end,
}
timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = {
    AddNetworkString = function() end,
    TraceLine = function(t) return { Entity = _G.__TRACE_HIT or { _valid = false } } end,
}
MASK_SHOT = 1
local NETRECV = {}
net = {
    Receive = function(n, f) NETRECV[n] = f end,
    Start = function() end, SendToServer = function() end, Send = function() end,
    Broadcast = function() end, WriteEntity = function() end, WriteString = function() end,
    ReadEntity = function() return _G.__NET_ENT end,
    ReadString = function() return _G.__NET_STR or "" end,
}
concommand = { Add = function() end }
function CreateClientConVar() end
function GetConVarNumber() return 1 end
surface = setmetatable({}, { __index = function() return function() end end })
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

local NOTIFIED = {}
GRM = { Notify = function(_, msg) NOTIFIED[#NOTIFIED + 1] = tostring(msg) end }
GRM.Net = { Guard = function() return true end }

-----------------------------------------------------------------------
-- Поддельные модули дверей и транспорта: повторяют ТОЛЬКО контракт,
-- который использует проверяемый модуль.
-----------------------------------------------------------------------
local LOCK_CALLS, DOORS_CALLS = {}, {}

local function mkDoor(locked, canLock, why)
    local d = { _valid = true, _locked = locked, _nw = {}, _nwb = {} }
    function d:GetNWString(k, def) return self._nw[k] or def or "" end
    function d:GetNWBool(k, def) if self._nwb[k] == nil then return def or false end return self._nwb[k] end
    function d:GetParent() return { _valid = false } end
    function d:NearestPoint() return Vector(0, 0, 0) end
    function d:EmitSound() end
    d._canLock, d._why = canLock, why
    return d
end

GRM.Doors = {
    IsDoor = function(e) return istable(e) and e._locked ~= nil end,
    IsDoorLocked = function(e) return e._locked == true end,
    CanToggleLock = function(_, e) return e._canLock ~= false, e._why end,
    LockDoor = function(e, want)
        LOCK_CALLS[#LOCK_CALLS + 1] = want
        if e._keepLocked and not want then return true, true, true end
        e._locked = want
        return true, want, false
    end,
    OpenDoorMenu = function() DOORS_CALLS[#DOORS_CALLS + 1] = "menu" end,
}

local VEH_CALLS = {}
local function mkVeh(locked, can)
    local v = { _valid = true, VK_Locked = locked, _nw2 = {}, _nw2b = { VK_Locked = locked } }
    function v:GetNW2Bool(k, def) if self._nw2b[k] == nil then return def or false end return self._nw2b[k] end
    function v:GetNW2String(k, def) return self._nw2[k] or def or "" end
    function v:GetParent() return { _valid = false } end
    function v:NearestPoint() return Vector(0, 0, 0) end
    function v:EmitSound() end
    v._can = can
    return v
end
_G.VK = {
    IsVehicle = function(e) return istable(e) and e.VK_Locked ~= nil end,
    CanInteract = function(e) return e._can == true end,
    GetVehicleDisplayName = function() return "Волга" end,
    ToggleLock = function(_, e) VEH_CALLS[#VEH_CALLS + 1] = "lock" e.VK_Locked = not e.VK_Locked end,
    ToggleDoors = function() VEH_CALLS[#VEH_CALLS + 1] = "doors" end,
}

local ply = { _valid = true }
function ply:IsPlayer() return true end
function ply:Alive() return true end
function ply:GetShootPos() return Vector(0, 0, 0) end
function ply:GetAimVector() return Vector(1, 0, 0) end
function ply:EmitSound() end
function ply:IsSuperAdmin() return false end

assert(loadfile("lua/autorun/sh_grm_interact.lua"))()
local I = GRM.Interact
assert(I, "модуль взаимодействия не загрузился")

-----------------------------------------------------------------------
print("\n=== 1. ПОИСК ЦЕЛИ ===")
-----------------------------------------------------------------------
do
    _G.__TRACE_HIT = mkDoor(true, true)
    local ent, kind = I.FindTarget(ply)
    ok(ent ~= nil and kind == "door", "дверь перед игроком опознана", kind)

    _G.__TRACE_HIT = mkVeh(false, true)
    local e2, k2 = I.FindTarget(ply)
    ok(e2 ~= nil and k2 == "vehicle", "транспорт опознан", k2)

    _G.__TRACE_HIT = { _valid = true, GetParent = function() return { _valid = false } end }
    ok(I.FindTarget(ply) == nil, "посторонний объект целью не считается")

    _G.__TRACE_HIT = nil
    ok(I.FindTarget(ply) == nil, "пустой трейс не роняет поиск")
end

-----------------------------------------------------------------------
print("\n=== 2. ДЕЙСТВИЯ ЗАВИСЯТ ОТ СОСТОЯНИЯ ===")
-----------------------------------------------------------------------
do
    local locked = mkDoor(true, true)
    local acts = I.Actions(ply, locked, "door")
    ok(acts[1] and acts[1].id == "door_unlock",
        "у ЗАПЕРТОЙ двери первым идёт «Отпереть»", acts[1] and acts[1].id)

    local open = mkDoor(false, true)
    local acts2 = I.Actions(ply, open, "door")
    ok(acts2[1] and acts2[1].id == "door_lock",
        "у открытой — «Запереть»", acts2[1] and acts2[1].id)

    ok(#acts >= 3, "есть и другие действия (стук, управление)", #acts)
end

do
    --[[ Недоступное действие должно ОСТАВАТЬСЯ в списке, но гаснуть с
         причиной: если его прятать, игрок не поймёт, чего не хватает. ]]
    local denied = mkDoor(true, false, "У вас нет ключей от этой двери.")
    local acts = I.Actions(ply, denied, "door")
    ok(acts[1] and acts[1].enabled == false, "без прав пункт замка выключен")
    ok(acts[1] and acts[1].why ~= nil, "и показывает причину", acts[1] and acts[1].why)
    ok(#acts >= 3, "остальные действия при этом доступны", #acts)
end

do
    local veh = mkVeh(true, true)
    local acts = I.Actions(ply, veh, "vehicle")
    ok(acts[1] and acts[1].id == "veh_unlock", "у запертой машины «Отпереть»")
    local names = {}
    for _, a in ipairs(acts) do names[a.id] = true end
    ok(names["veh_doors"], "есть открытие дверей")
    ok(names["veh_trunk"], "есть багажник")

    local noKey = mkVeh(true, false)
    local acts2 = I.Actions(ply, noKey, "vehicle")
    for _, a in ipairs(acts2) do
        if a.enabled ~= false then
            ok(false, "без ключа все действия должны быть выключены", a.id)
            break
        end
    end
    ok(acts2[1].enabled == false, "без ключа действия выключены")
end

-----------------------------------------------------------------------
print("\n=== 3. СЕРВЕР НЕ ВЕРИТ КЛИЕНТУ ===")
-----------------------------------------------------------------------
local recv = NETRECV["GRM_Interact_Act"]
ok(recv ~= nil, "обработчик действия зарегистрирован")

local function send(ent, id)
    _G.__NET_ENT, _G.__NET_STR = ent, id
    LOCK_CALLS, VEH_CALLS, DOORS_CALLS, NOTIFIED = {}, {}, {}, {}
    recv(64, ply)
end

do
    local door = mkDoor(true, true)
    send(door, "door_unlock")
    ok(#LOCK_CALLS == 1 and LOCK_CALLS[1] == false, "отпирание проходит", #LOCK_CALLS)

    -- Действие для ЧУЖОГО типа цели должно отбрасываться.
    send(door, "veh_lock")
    ok(#LOCK_CALLS == 0 and #VEH_CALLS == 0,
        "действие транспорта на двери отброшено")

    -- Выдуманный id.
    send(door, "door_explode")
    ok(#LOCK_CALLS == 0, "неизвестное действие отброшено")

    --[[ ГЛАВНОЕ: у клиента может быть пропатчен интерфейс, и он
         пришлёт действие, которого ему НЕ разрешено. Сервер обязан
         перепроверить права сам. ]]
    local denied = mkDoor(true, false, "нет ключей")
    send(denied, "door_unlock")
    ok(#LOCK_CALLS == 0, "без прав замок не открывается, даже если пакет пришёл")
    ok(#NOTIFIED > 0, "игроку сообщают причину", NOTIFIED[1])
end

do
    -- Дистанция: далёкая цель отбрасывается.
    local far = mkDoor(true, true)
    function far:NearestPoint() return Vector(9000, 0, 0) end
    send(far, "door_unlock")
    ok(#LOCK_CALLS == 0, "слишком далёкая дверь не поддаётся")
    ok(NOTIFIED[1] and NOTIFIED[1]:find("далеко", 1, true) ~= nil,
        "и об этом говорят", NOTIFIED[1])
end

do
    local veh = mkVeh(true, true)
    send(veh, "veh_unlock")
    ok(VEH_CALLS[1] == "lock", "транспорт: переключение замка проходит")
    send(veh, "veh_doors")
    ok(VEH_CALLS[1] == "doors", "двери транспорта открываются")

    local noKey = mkVeh(true, false)
    send(noKey, "veh_unlock")
    ok(#VEH_CALLS == 0, "без ключа транспорт не поддаётся")
end

do
    -- Мёртвый игрок и мусор вместо цели не должны ничего ломать.
    local door = mkDoor(true, true)
    ply.Alive = function() return false end
    send(door, "door_unlock")
    ok(#LOCK_CALLS == 0, "мёртвый игрок не взаимодействует")
    ply.Alive = function() return true end

    send({ _valid = false }, "door_unlock")
    ok(#LOCK_CALLS == 0, "невалидная сущность не роняет обработчик")
end

-----------------------------------------------------------------------
print("\n=== 4. ГЕОМЕТРИЯ КОЛЬЦА ===")
-----------------------------------------------------------------------
do
    --[[ 31.08 кольцо заменено ПРЯМОУГОЛЬНОЙ панелью (заказ владельца:
         «меню чем-то похожее на круговое, но только прямоугольное»).
         Проверяем то же свойство, что и раньше: раскладка кнопок и
         выбор мышью обязаны совпадать, иначе игрок жмёт одно, а
         срабатывает другое.

         Сами формулы живут в модуле; здесь берём их оттуда, чтобы
         стенд не проверял собственную копию. ]]
    local src = readf("lua/autorun/sh_grm_interact.lua")
    local rectSrc = src:match("(function P%.Rect.-\nend)")
    local itemSrc = src:match("(function P%.ItemRect.-\nend)")
    local pickSrc = src:match("(function P%.Pick.-\nend)")
    ok(rectSrc and itemSrc and pickSrc, "формулы панели найдены в модуле")

    local env = { math = math, P = { W = 268, H = 46, Gap = 8, HeadH = 54 },
        ScrW = function() return 1920 end, ScrH = function() return 1080 end }
    local chunk = assert(loadstring(
        "local P = P\n" .. rectSrc .. "\n" .. itemSrc .. "\n" .. pickSrc .. "\nreturn P"))
    setfenv(chunk, env)
    local PP = chunk()

    local bad = {}
    for count = 1, 6 do
        for i = 1, count do
            local ix, iy, iw, ih = PP.ItemRect(i, count, 1920, 1080)
            if PP.Pick(ix + iw * 0.5, iy + ih * 0.5, count, 1920, 1080) ~= i then
                bad[#bad + 1] = count .. "/" .. i
            end
        end
    end
    ok(#bad == 0, "клик в центр кнопки выбирает именно её", bad[1])
    ok(PP.Pick(5, 5, 4, 1920, 1080) == nil, "клик мимо панели ничего не выбирает")
    ok(PP.Pick(960, 540, 0, 1920, 1080) == nil, "пустой список не роняет выбор")
end

-----------------------------------------------------------------------
print("\n=== 5. ЧИТАЕМОСТЬ (отдельная жалоба владельца) ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_interact.lua")

    --[[ «чтобы текст не был чёрным как иногда вы выдаёте, что фон меню
         тёмный, текст чёрный и ничего нечитабельно».

         Собираем ВСЕ цвета текста из палитры и проверяем яркость.
         Чёрный допустим только как обводка (shadow). ]]
    local pal = src:match("local C = {(.-)\n}")
    ok(pal ~= nil, "палитра найдена")

    local dark = {}
    for name, r, g, b in pal:gmatch("(%w+)%s*=%s*Color%((%d+),%s*(%d+),%s*(%d+)") do
        local lum = (tonumber(r) * 0.299 + tonumber(g) * 0.587 + tonumber(b) * 0.114)
        -- Фоны и обводка обязаны быть тёмными, текстовые цвета — нет.
        local isText = (name == "text" or name == "dim" or name == "gold"
            or name == "good" or name == "warn" or name == "bad")
        if isText and lum < 110 then dark[#dark + 1] = name .. "(" .. math.floor(lum) .. ")" end
    end
    ok(#dark == 0, "ни один цвет ТЕКСТА не тёмный", table.concat(dark, ","))

    ok(pal:find("shadow", 1, true) ~= nil,
        "есть чёрная обводка — светлый текст поверх мира иначе теряется")
    --[[ Обводка была нужна кольцу: текст лежал прямо на мире и терялся
         на светлой стене. У прямоугольной панели весь текст стоит на
         СВОЕЙ непрозрачной подложке с рамкой, поэтому обводка больше не
         требуется. Проверяем то, что важно на деле: под текстом всегда
         есть подложка. ]]
    ok(src:find("draw.RoundedBox(8, x, y, pw, ph", 1, true) ~= nil,
        "у панели есть непрозрачная подложка под текстом")
    ok(src:find("surface.DrawOutlinedRect(x, y, pw, ph, 1)", 1, true) ~= nil,
        "и обводка по краю, как просил владелец")
    ok(src:find("draw.RoundedBox(6, x, y - bh * 0.5, bw, bh", 1, true) ~= nil,
        "у подсказки рядом с объектом тоже своя плашка")

    -- Стилистика проекта: та же тёмная подложка, что у прочих окон GRM.
    ok(pal:find("bg", 1, true) ~= nil and pal:find("card", 1, true) ~= nil,
        "палитра в общей стилистике (тёмный фон, светлый текст)")
end

-----------------------------------------------------------------------
print("\n=== 6. КЛАВИША E: УДЕРЖАНИЕ, А НЕ НАЖАТИЕ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_interact.lua")

    --[[ Короткое E обязано остаться обычным «использовать»: им
         открывают двери, садятся в машину, поднимают предметы. Кольцо
         только по удержанию. ]]
    ok(src:find("I.HoldTime", 1, true) ~= nil, "порог удержания задан")

    --[[ Логика E переехала в StartCommand (31.08): PlayerButtonDown
         опаздывает на кадр относительно потока команд, и первый тик
         с «использовать» успевал уйти на сервер — дверь открывалась.
         Проверяем ту же суть, но в новом месте. ]]
    local sc = src:match("hook%.Add%(\"StartCommand\", \"GRM_Interact_Use\".-\nend%)")
    ok(sc ~= nil, "обработчик команды найден")
    ok(sc and sc:find("RealTime() - holdStart >= I.HoldTime", 1, true) ~= nil,
        "кольцо открывается только после порога")
    ok(sc and sc:find("I.FindTarget", 1, true) ~= nil,
        "цель определяется в том же тике, что и команда")

    local up = src:match("hook%.Add%(\"PlayerButtonUp\", \"GRM_Interact_UseUp\".-\nend%)")
    ok(up and up:find("I.Apply()", 1, true) ~= nil, "отпускание применяет выбор")

    --[[ IN_USE снимается и во время удержания, и при открытом кольце:
         иначе дверь откроется обычным способом до выбора пункта. ]]
    ok(sc and sc:find("cmd:RemoveKey(IN_USE)", 1, true) ~= nil,
        "обычное «использовать» на время кольца отключено")
    ok(sc and sc:find("SetMouseX(0)", 1, true) ~= nil,
        "мышь не крутит игрока, пока он выбирает")

    -- Клавиатуру у панели не забираем — иначе не придёт отпускание.
    ok(src:find("f:SetKeyboardInputEnabled(false)", 1, true) ~= nil,
        "панель не забирает клавиатуру (иначе кольцо зависнет)")

    ok(src:find("grm_cl_interact", 1, true) ~= nil, "подсказку можно отключить конваром")
end

-----------------------------------------------------------------------
print("\n=== 7. ИНТЕГРАЦИЯ С СУЩЕСТВУЮЩИМИ МОДУЛЯМИ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_interact.lua")

    --[[ Свои проверки прав писать нельзя: правила категорий,
         совладельцев и ордеров живут в ядре дверей, вторая копия
         разошлась бы с первой. ]]
    ok(src:find("D.CanToggleLock", 1, true) ~= nil,
        "права на дверь спрашиваются у ядра дверей")
    ok(src:find("V.CanInteract", 1, true) ~= nil,
        "права на транспорт — у модуля ключей ТС")
    ok(src:find("GRM.Trunk.RequestToggle", 1, true) ~= nil,
        "багажник открывается его же точкой входа, что и в C-меню")

    -- Модуль ключей ТС лежит в глобальной VK, а не в GRM.VehicleKeys.
    ok(src:find("_G.VK", 1, true) ~= nil, "используется настоящая таблица VK")

    -- Состояние замка ТС синхронизируется через NW2.
    ok(src:find("GetNW2Bool(\"VK_Locked\"", 1, true) ~= nil,
        "замок ТС читается из NW2, как его пишет сервер")

    ok(src:find("GRM.Net.Guard", 1, true) ~= nil,
        "обработчик под ограничителем частоты")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
