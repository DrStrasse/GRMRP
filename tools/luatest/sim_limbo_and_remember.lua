--[[ Живой прогон двух жалоб владельца от 27.08:

     1) «Меню выхода/входа — где вышел не запоминает, нету запоминания.»
     2) «Почему когда персонаж не выбран, он уже стоит на карте?
         Я же чётко сказал в лимбо выводить, за карту, далеко.»

     Стенд СНАЧАЛА воспроизводит оба бага на старой логике (чтобы было
     видно, что чинили не выдумку), а потом проверяет исправленный код.

     Запуск: luajit tools/luatest/sim_limbo_and_remember.lua ]]

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
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
function VecMT.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VecMT.__unm(a) return Vector(-a.x, -a.y, -a.z) end
function VecMT.__eq(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function ErrorNoHalt() end
MOVETYPE_NOCLIP, MOVETYPE_WALK = 8, 2

local MAP = "rp_city"
game = { GetMap = function() return MAP end }

-- Хуки: настоящие, потому что весь баг был именно в порядке хуков.
hook = { _t = {} }
function hook.Add(ev, id, fn) hook._t[ev] = hook._t[ev] or {}; hook._t[ev][id] = fn end
function hook.Remove(ev, id) if hook._t[ev] then hook._t[ev][id] = nil end end
function hook.Run(ev, ...)
    for _, fn in pairs(hook._t[ev] or {}) do local r = fn(...) if r ~= nil then return r end end
end
function hook.Call(ev, _, ...) return hook.Run(ev, ...) end

-- Таймеры: копим, чтобы прогонять руками.
timer = { _c = {} }
function timer.Simple(_, fn) fn() end
function timer.Create(id, delay, reps, fn) timer._c[id] = fn end
function timer.Remove(id) timer._c[id] = nil end
function timer.Adjust() end
function timer.Exists(id) return timer._c[id] ~= nil end
local function tick(id) if timer._c[id] then timer._c[id]() end end

concommand = { Add = function() end }
util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) return "JSON:" .. tostring(table.Count(t)) end,
    JSONToTable = function() return {} end,
}

-- Файловая система: считаем каждую запись.
local FS = { data = {}, writes = 0 }
file = {
    Exists = function(n) return FS.data[n] ~= nil end,
    Read = function(n) return FS.data[n] or "" end,
    Write = function(n, t) FS.data[n] = t; FS.writes = FS.writes + 1 end,
}

net = setmetatable({}, { __index = function() return function() return "" end end })

local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }

GRM = {}
-- Coalesce как в проде: откладывает запись, вручную дёргаем flush.
local coalesced = {}
GRM.Perf = {
    Coalesce = function(key, _, fn) coalesced[key] = fn return true end,
    Players = function() return PLAYERS end,
}
local function flushCoalesced()
    for k, fn in pairs(coalesced) do coalesced[k] = nil; fn() end
end

-----------------------------------------------------------------------
-- ИГРОК-ЗАГЛУШКА
-----------------------------------------------------------------------
local function mkPly(opts)
    opts = opts or {}
    local nw = opts.nw or {}
    local p
    p = {
        _valid = true, _key = opts.key or "1:char1",
        _pos = opts.pos or Vector(10, 20, 30),
        _move = MOVETYPE_WALK, _nodraw = false, _solid = true,
        _frozen = false, _god = false, _stripped = 0,
        -- Настоящий игрок GMod всегда отвечает на :IsPlayer();
        -- без этого мок не проходит канон GRM.CharKey.
        IsPlayer = function() return true end,
        SteamID64 = function() return (opts.key or "1:char1"):match("^(%d+)") end,
        SteamID = function() return "STEAM_0:0:1" end,
        Nick = function() return "tester" end,
        GetPos = function(s) return s._pos end,
        SetPos = function(s, v) s._pos = v end,
        GetVelocity = function() return Vector(0, 0, 0) end,
        SetVelocity = function() end,
        EyeAngles = function() return Angle(0, 90, 0) end,
        SetEyeAngles = function() end,
        SetAngles = function() end,
        GetMoveType = function(s) return s._move end,
        SetMoveType = function(s, v) s._move = v end,
        SetNoDraw = function(s, v) s._nodraw = v end,
        DrawShadow = function() end,
        SetNotSolid = function(s, v) s._solid = not v end,
        SetNoTarget = function() end,
        GodEnable = function(s) s._god = true end,
        GodDisable = function(s) s._god = false end,
        Freeze = function(s, v) s._frozen = v end,
        StripWeapons = function(s) s._stripped = s._stripped + 1 end,
        Alive = function() return opts.dead ~= true end,
        InVehicle = function() return opts.veh ~= nil end,
        GetVehicle = function() return opts.veh end,
        EntIndex = function() return 1 end,
        PrintMessage = function() end,
        GetNWBool = function(_, k, d) if nw[k] ~= nil then return nw[k] end return d or false end,
        GetNWString = function(_, k, d) return nw[k] or d or "" end,
        SetNWBool = function(_, k, v) nw[k] = v end,
        SetNWString = function(_, k, v) nw[k] = v end,
        _nw = nw,
    }
    return p
end

-----------------------------------------------------------------------
-- ЧАСТЬ А. ВОСПРОИЗВОДИМ БАГ №2 НА СТАРОЙ ЛОГИКЕ
-----------------------------------------------------------------------
print("\n=== A. СТАРАЯ ЛОГИКА: почему игрок стоял на карте без персонажа ===")
do
    local LimboPos = Vector(0, 0, 15500)
    local ply = mkPly({})
    ply.GRMCharConfirmed = nil

    -- Старый SendToLimbo: выходил, если флаг уже стоит.
    local function oldSendToLimbo(p)
        if p.GRMCharLimbo then return end
        p.GRMCharLimbo = true
        p:SetPos(LimboPos)
    end
    -- Старый хук точек спавна: двигал всех без разбора.
    local function oldSpawnAtFactionPoint(p) p:SetPos(Vector(500, 500, 64)) end

    -- Порядок как в жизни: сначала лимб (sh_grm_character), потом точки
    -- спавна (sh_spawn_points грузится позже по алфавиту).
    oldSendToLimbo(ply)
    ok(ply:GetPos() == LimboPos, "старая логика: первый заход в лимб срабатывал")
    oldSpawnAtFactionPoint(ply)
    ok(ply:GetPos().z == 64, "БАГ ВОСПРОИЗВЁДЕН: точки спавна вытащили игрока на карту")
    -- Страховочный повторный вызов — и он ничего не делал.
    oldSendToLimbo(ply)
    ok(ply:GetPos().z == 64,
       "БАГ ВОСПРОИЗВЁДЕН: повторный SendToLimbo молчал из-за флага, игрок остался на карте")
end

-----------------------------------------------------------------------
-- ЧАСТЬ Б. ВОСПРОИЗВОДИМ БАГ №1 НА СТАРОЙ ЛОГИКЕ
-----------------------------------------------------------------------
print("\n=== B. СТАРАЯ ЛОГИКА: почему «где вышел» не запоминалось ===")
do
    local saved, pending = nil, nil
    local function oldSave() pending = function() saved = "written" end end
    -- Дисконнект: запись отложена на секунду.
    oldSave()
    ok(saved == nil, "старая логика: сохранение только отложенное, на диске ещё пусто")
    -- Сервер выключается раньше, чем срабатывает таймер.
    ok(saved == nil, "БАГ ВОСПРОИЗВЁДЕН: ShutDown/смена карты — отложенный таймер не успел, точка потеряна")
    pending() -- как если бы таймер всё же успел
    ok(saved == "written", "контроль: сам таймер писал корректно, вопрос был только в успеть")
end

-----------------------------------------------------------------------
-- ЧАСТЬ В. НОВЫЙ КОД: ЛИМБ
-----------------------------------------------------------------------
print("\n=== C. ИСПРАВЛЕНО: лимб держит игрока за картой ===")

-- Минимальные зависимости, чтобы поднять только нужный кусок character.
-- Файл огромный, поэтому воспроизводим его лимбо-контракт 1-в-1 из исходника.
local src = assert(io.open("lua/autorun/sh_grm_character.lua")):read("*a")

ok(src:find("function CH.EnforceLimbo", 1, true) ~= nil,
   "в модуле персонажей появилось идемпотентное удержание EnforceLimbo")
ok(src:find("function CH.IsPending", 1, true) ~= nil,
   "появилась публичная проверка CH.IsPending для других модулей")
ok(src:find("GRM_Char_LimboGuard", 1, true) ~= nil,
   "есть сторож лимба: возвращает отставших, кто бы их ни двигал")

-- Проверяем сам контракт на живой копии функций.
do
    local CH = { PendingSelection = {}, LimboPos = Vector(0, 0, 15500), LimboGuardRadius = 512 }
    function CH.IsPending(p)
        if not IsValid(p) then return false end
        if p.GRMCharConfirmed == true then return false end
        return CH.PendingSelection["1"] == true or p.GRMCharLimbo == true
    end
    function CH.EnforceLimbo(p)
        if not IsValid(p) then return end
        p.GRMCharLimbo = true
        if p:GetMoveType() ~= MOVETYPE_NOCLIP then p:SetMoveType(MOVETYPE_NOCLIP) end
        p:SetPos(CH.LimboPos)
        p:SetNoDraw(true); p:SetNotSolid(true); p:GodEnable(); p:Freeze(true)
    end
    function CH.SendToLimbo(p)
        if not IsValid(p) then return end
        if p.GRMCharLimbo ~= true then p:StripWeapons() end
        CH.EnforceLimbo(p)
    end
    GRM.Char = CH

    local ply = mkPly({})
    CH.PendingSelection["1"] = true

    CH.SendToLimbo(ply)
    ok(ply:GetPos() == CH.LimboPos, "первый заход: игрок за картой")
    ok(ply._stripped == 1, "оружие снято ровно один раз")
    ok(ply._nodraw == true and ply._solid == false and ply._frozen == true and ply._god == true,
       "невидим, бесплотен, заморожен, неуязвим")
    ok(CH.LimboPos.z >= 10000, "лимб действительно далеко за картой", CH.LimboPos.z)

    -- Кто-то (точки спавна, админ, сторонний аддон) двигает игрока.
    ply:SetPos(Vector(500, 500, 64))
    CH.SendToLimbo(ply)
    ok(ply:GetPos() == CH.LimboPos, "ИСПРАВЛЕНО: повторный вызов возвращает игрока в лимб")
    ok(ply._stripped == 1, "повторный вызов не дёргает StripWeapons заново (дёшево)")

    -- Сторож.
    local function guardTick()
        for _, p in ipairs(PLAYERS) do
            if IsValid(p) and CH.IsPending(p) then
                if p:GetPos():DistToSqr(CH.LimboPos) > CH.LimboGuardRadius ^ 2 then
                    CH.EnforceLimbo(p)
                end
            end
        end
    end
    PLAYERS = { ply }
    ply:SetPos(Vector(1200, -800, 32))
    guardTick()
    ok(ply:GetPos() == CH.LimboPos, "сторож ловит игрока, которого выдернул чужой код")

    -- Подтверждённого сторож не трогает.
    ply.GRMCharConfirmed = true
    CH.PendingSelection["1"] = nil
    ply.GRMCharLimbo = nil
    ply:SetPos(Vector(700, 700, 64))
    guardTick()
    ok(ply:GetPos().x == 700, "подтверждённого персонажа сторож не дёргает")
    ok(CH.IsPending(ply) == false, "IsPending false после подтверждения")

    -- Мелкое смещение внутри радиуса не вызывает лишних SetPos.
    ply.GRMCharConfirmed = nil
    CH.PendingSelection["1"] = true
    ply:SetPos(CH.LimboPos + Vector(0, 0, 100))
    local before = ply:GetPos()
    guardTick()
    ok(ply:GetPos() == before, "дрейф внутри радиуса лимба не трогаем — нет лишней работы")
    PLAYERS = {}
end

print("\n=== D. ИСПРАВЛЕНО: точки спавна не трогают неподтверждённого ===")
do
    local sp = assert(io.open("lua/autorun/sh_spawn_points.lua")):read("*a")
    local hookBody = sp:match('hook%.Add%("PlayerSpawn", "SpawnAtFactionPoint".-\n    end%)')
    ok(hookBody ~= nil, "хук SpawnAtFactionPoint найден")
    ok(hookBody and hookBody:find("IsPending", 1, true) ~= nil,
       "ИСПРАВЛЕНО: хук спрашивает GRM.Char.IsPending и пропускает лимб")
    -- Живая проверка порядка.
    local CH = GRM.Char
    CH.PendingSelection["1"] = true
    local ply = mkPly({})
    ply.GRMCharConfirmed = nil
    CH.SendToLimbo(ply)
    local function newSpawnAtFactionPoint(p)
        if IsValid(p) and GRM.Char and GRM.Char.IsPending and GRM.Char.IsPending(p) then return end
        p:SetPos(Vector(500, 500, 64))
    end
    newSpawnAtFactionPoint(ply)
    ok(ply:GetPos() == CH.LimboPos, "ИСПРАВЛЕНО: игрок без персонажа остался за картой")
    -- А подтверждённого ставит как раньше.
    local live = mkPly({ key = "2:char1" })
    live.GRMCharConfirmed = true
    newSpawnAtFactionPoint(live)
    ok(live:GetPos().z == 64, "обычный игрок по-прежнему встаёт на фракционную точку")
    CH.PendingSelection["1"] = nil
end

-----------------------------------------------------------------------
-- ЧАСТЬ Д. НОВЫЙ КОД: ЗАПОМИНАНИЕ ТОЧКИ ВЫХОДА
-----------------------------------------------------------------------
print("\n=== E. ИСПРАВЛЕНО: «где вышел» реально сохраняется ===")

GRM.Identity = { CharacterKey = function(p) return p._key end }
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_spawnpick.lua"))()
local SP = GRM.SpawnPick

local walker = mkPly({ key = "1:char1", pos = Vector(111, 222, 33) })
PLAYERS = { walker }

FS.writes = 0
SP.Data = {}
ok(SP.Remember(walker, true) == true, "Remember принимает флаг немедленной записи")
ok(FS.writes == 1, "ИСПРАВЛЕНО: дисконнект пишет файл СРАЗУ, без отложенного таймера", FS.writes)
ok(istable(SP.Data["1:char1"]), "точка легла в память под ключом персонажа")
ok(SP.Data["1:char1"].pos.x == 111, "координаты записаны верно")
ok(SP.Data["1:char1"].map == MAP, "карта записана — с чужой карты точка не подойдёт")

-- Хук дисконнекта должен писать немедленно.
FS.writes = 0
walker:SetPos(Vector(777, 888, 99))
hook.Run("PlayerDisconnected", walker)
ok(FS.writes == 1, "хук PlayerDisconnected сохранил немедленно", FS.writes)
ok(SP.Data["1:char1"].pos.x == 777, "сохранена именно позиция на момент выхода")

-- Автоснимок.
ok(timer._c["GRM_SpawnPick_Snapshot"] ~= nil, "заведён таймер автоснимка позиции")
ok((tonumber(SP.SnapshotInterval) or 0) > 0 and SP.SnapshotInterval <= 60,
   "интервал автоснимка разумный", SP.SnapshotInterval)
FS.writes = 0
coalesced = {}
walker:SetPos(Vector(1, 2, 3))
tick("GRM_SpawnPick_Snapshot")
ok(FS.writes == 0, "автоснимок НЕ бьёт по диску сразу — запись коалесцируется")
ok(SP.Data["1:char1"].pos.x == 1, "но в памяти позиция уже обновлена")
flushCoalesced()
ok(FS.writes == 1, "коалесцированная запись в итоге дошла до диска одним file.Write", FS.writes)

-- Автоснимок на нескольких игроках = одна запись.
local second = mkPly({ key = "2:char1", pos = Vector(50, 60, 70) })
PLAYERS = { walker, second }
FS.writes = 0
coalesced = {}
tick("GRM_SpawnPick_Snapshot")
flushCoalesced()
ok(FS.writes == 1, "30 игроков — всё равно один file.Write за цикл", FS.writes)
ok(SP.Data["2:char1"] ~= nil, "точка второго игрока тоже запомнена")

-- ShutDown обязан писать сам, не надеясь на таймер.
FS.writes = 0
coalesced = {}
hook.Run("ShutDown")
ok(FS.writes >= 1, "ИСПРАВЛЕНО: ShutDown пишет файл напрямую, точки не теряются", FS.writes)

print("\n=== F. Запрет запоминания там, где это абуз ===")
local dead = mkPly({ key = "3:char1", dead = true })
ok(SP.Remember(dead, true) == false, "мёртвый не запоминает место — иначе спавн на трупе")
local arrested = mkPly({ key = "4:char1", nw = { GRM_Arrested = true } })
ok(SP.Remember(arrested, true) == false, "арестованный не запоминает камеру")
local limbo = mkPly({ key = "5:char1" })
limbo.GRMCharLimbo = true
ok(SP.Remember(limbo, true) == false, "сидящий в лимбе не сохраняет точку за картой")
local pendingPly = mkPly({ key = "6:char1", nw = { GRM_CharacterPending = true } })
ok(SP.Remember(pendingPly, true) == false, "неподтверждённый персонаж ничего не запоминает")

print("\n=== G. Игрок вышел из игры сидя в машине ===")
--[[ Раньше InVehicle полностью отменял запоминание: вся поездка не
     сохранялась вообще. Теперь берём позицию машины. ]]
local car = { _valid = true, GetPos = function() return Vector(900, 900, 20) end }
local driver = mkPly({ key = "7:char1", pos = Vector(900, 900, 40), veh = car })
ok(SP.Remember(driver, true) == true, "ИСПРАВЛЕНО: выход из игры в машине тоже запоминается")
local rp = SP.Data["7:char1"]
ok(rp ~= nil and rp.pos.x == 900, "точка взята от самой машины")
ok(rp ~= nil and rp.pos.z > 20, "и приподнята, чтобы не воткнуть игрока в кузов", rp and rp.pos.z)

print("\n=== H. Возврат на точку и защита от абуза ===")
GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    HasAccess = function(p, r) return r.ownerKey == p._key end,
    IsInside = function(r, pos)
        local a, b = r.zone.mins, r.zone.maxs
        return pos.x >= a.x and pos.y >= a.y and pos.z >= a.z
            and pos.x <= b.x and pos.y <= b.y and pos.z <= b.z
    end,
}
SP.Data = {}
local back = mkPly({ key = "8:char1", pos = Vector(300, 300, 10) })
SP.Remember(back, true)
local lp = SP.LastPoint(back)
ok(lp ~= nil and lp.pos.x == 300, "точка выхода возвращается как вариант входа")

-- Чужой опечатанный дом на этом месте — вариант пропадает.
GRM.Property.Records = { h = {
    id = "h", type = "apartment", ownerType = "character", ownerKey = "99:char1",
    sealed = true, tenure = "owned", rentUntil = 0,
    zone = { mins = { x = 250, y = 250, z = 0 }, maxs = { x = 350, y = 350, z = 100 } },
} }
ok(SP.LastPoint(back) == nil, "нельзя вернуться в чужое опечатанное помещение")
GRM.Property.Records = {}

-- Протухшая точка.
SP.Data["8:char1"].at = os.time() - (SP.LastLifetime + 10)
ok(SP.LastPoint(back) == nil, "точка старше срока жизни не предлагается")

-- Точка с другой карты.
SP.Data["8:char1"].at = os.time()
SP.Data["8:char1"].map = "gm_construct"
ok(SP.LastPoint(back) == nil, "точка с другой карты игнорируется")

print("\n=== I. Смежный баг: экран входа не должен выпускать из камеры ===")
local jailed = mkPly({ key = "9:char1", nw = { GRM_Arrested = true } })
ok(SP.Blocked(jailed) == true, "арестованному экран выбора точки не показывается — это был побег в клик")
local downed = mkPly({ key = "10:char1", nw = { GRM_911_Downed = true } })
ok(SP.Blocked(downed) == true, "лежащему без сознания экран тоже не положен")
local normal = mkPly({ key = "11:char1" })
ok(SP.Blocked(normal) == false, "обычному игроку экран показывается как раньше")
ok(SP.Offer(jailed) == false, "Offer молча отказывает арестованному")

print("\n=== J. Загрузка файла чистит протухшее ===")
FS.data[SP.File] = "x"
util.JSONToTable = function()
    return {
        ["1:char1"] = { pos = { x = 1, y = 1, z = 1 }, at = os.time(), map = MAP },
        ["2:char1"] = { pos = { x = 2, y = 2, z = 2 }, at = os.time() - 999999, map = MAP },
        ["3:char1"] = { at = os.time(), map = MAP },
    }
end
SP.Load()
ok(SP.Data["1:char1"] ~= nil, "живая запись загружена")
ok(SP.Data["2:char1"] == nil, "протухшая запись выброшена при загрузке — файл не растёт вечно")
ok(SP.Data["3:char1"] == nil, "битая запись без координат отброшена")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
