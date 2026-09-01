--[[ ПОЛНЫЙ КРУГ «ГДЕ ВЫШЕЛ» (жалоба владельца 28.08).

     «Где вышел не работает. Спавнит на месте фракции. Он не запоминает
      точку выхода игрока и не задаёт координаты для его последующего
      появления.»

     Прошлые стенды проверяли КУСКИ (Remember отдельно, конвейер
     отдельно) и потому баг пропустили. Здесь честный круг:

        игра → выход → запись на диск → РЕСТАРТ СЕРВЕРА →
        загрузка файла → вход → конвейер → выбор «ГДЕ ВЫШЕЛ» → позиция

     с настоящей сериализацией JSON, а не с заглушкой, которая всегда
     возвращает то, что положили.

     Запуск: luajit tools/luatest/sim_lastpoint_roundtrip.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- ДВИЖОК
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
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function VecMT:Normalize() return self end
function VecMT:Angle() return Angle(0,0,0) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__unm(a) return Vector(-a.x,-a.y,-a.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function VecMT.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function VecMT.__tostring(a) return ("(%.0f %.0f %.0f)"):format(a.x,a.y,a.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt() end
MOVETYPE_WALK, MOVETYPE_NOCLIP = 2, 8
FL_FROZEN = 32
HUD_PRINTTALK = 3

local NOW, REALTIME = 100, 1700000000
CurTime = function() return NOW end
os.time = function() return REALTIME end

local MAP = "gm_construct"
game = { GetMap = function() return MAP end }

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end
local function runAll(e,...) for _,f in pairs(hook._t[e] or {}) do f(...) end end

timer = { _c = {} }
function timer.Create(id,_,_,f) timer._c[id]=f end
function timer.Simple(_,f) f() end
function timer.Remove(id) timer._c[id]=nil end
function timer.Exists(id) return timer._c[id]~=nil end
local function tick(id) if timer._c[id] then timer._c[id]() end end
local function pumpAll(n) for _=1,(n or 40) do tick("GRM_Entry_Pump") end end

concommand = { Add = function() end }
local SENT = {}
local buf
net = {
    AddNetworkString=function() end,
    Start=function(n) buf={name=n,args={}} end,
    WriteEntity=function(v) table.insert(buf.args,v) end,
    WriteTable=function(v) table.insert(buf.args,v) end,
    WriteString=function(v) table.insert(buf.args,v) end,
    WriteFloat=function(v) table.insert(buf.args,v) end,
    WriteUInt=function(v) table.insert(buf.args,v) end,
    WriteBool=function(v) table.insert(buf.args,v) end,
    Send=function(p) buf.to=p table.insert(SENT,buf) end,
    Receive=function(n,f) net["_h_"..n]=f end,
}

-----------------------------------------------------------------------
-- НАСТОЯЩАЯ СЕРИАЛИЗАЦИЯ.
-- Заглушка «вернуть что положили» скрывала бы ошибки формата, а именно
-- на них ломается сохранение между сессиями.
-----------------------------------------------------------------------
local function enc(v)
    local t = type(v)
    if t == "number" then return tostring(v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return '"' .. v:gsub('"', '\\"') .. '"' end
    if t == "table" then
        local isArr = #v > 0
        local out = {}
        if isArr then
            for _, x in ipairs(v) do out[#out+1] = enc(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, x in pairs(v) do out[#out+1] = '"'..tostring(k)..'":'..enc(x) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

local function dec(s)
    local pos = 1
    local function skip() while pos <= #s and s:sub(pos,pos):match("%s") do pos = pos + 1 end end
    local parseVal
    local function parseStr()
        pos = pos + 1
        local out = {}
        while pos <= #s do
            local c = s:sub(pos,pos)
            if c == '\\' then out[#out+1] = s:sub(pos+1,pos+1) pos = pos + 2
            elseif c == '"' then pos = pos + 1 break
            else out[#out+1] = c pos = pos + 1 end
        end
        return table.concat(out)
    end
    parseVal = function()
        skip()
        local c = s:sub(pos,pos)
        if c == '"' then return parseStr() end
        if c == '{' then
            pos = pos + 1
            local o = {}
            skip()
            if s:sub(pos,pos) == '}' then pos = pos + 1 return o end
            while true do
                skip()
                local k = parseStr()
                skip() pos = pos + 1          -- ':'
                o[k] = parseVal()
                skip()
                local d = s:sub(pos,pos) pos = pos + 1
                if d == '}' then break end
            end
            return o
        end
        if c == '[' then
            pos = pos + 1
            local a = {}
            skip()
            if s:sub(pos,pos) == ']' then pos = pos + 1 return a end
            while true do
                a[#a+1] = parseVal()
                skip()
                local d = s:sub(pos,pos) pos = pos + 1
                if d == ']' then break end
            end
            return a
        end
        local lit = s:match("^[%-%d%.eE%+]+", pos)
        if lit then pos = pos + #lit return tonumber(lit) end
        if s:sub(pos,pos+3) == "true" then pos = pos + 4 return true end
        if s:sub(pos,pos+4) == "false" then pos = pos + 5 return false end
        pos = pos + 4 return nil
    end
    local okp, res = pcall(parseVal)
    return okp and res or nil
end

util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) return enc(t) end,
    JSONToTable = function(s) return dec(s) end,
}

--- Диск, переживающий «рестарт сервера».
local DISK = {}
local WRITES = 0
file = {
    Exists = function(n) return DISK[n] ~= nil end,
    Read = function(n) return DISK[n] or "" end,
    Write = function(n,t) DISK[n] = t WRITES = WRITES + 1 end,
    CreateDir = function() end, IsDir = function() return true end,
}

local PLAYERS = {}
player = { GetAll = function() return PLAYERS end }
ents = { GetAll=function() return {} end, FindByClass=function() return {} end }
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,
    GetBool=function() return d~="0" end, GetString=function() return tostring(d) end,
    GetInt=function() return math.floor(tonumber(d) or 0) end} end

GRM = { Perf = { Players = function() return PLAYERS end } }
GRM.Notify = function() end

--- Коалесцирование как в проде: отложенная запись, flush вручную.
local coalesced = {}
GRM.Perf.Coalesce = function(k,_,fn) coalesced[k] = fn return true end
local function flushCoalesced()
    for k, fn in pairs(coalesced) do coalesced[k] = nil fn() end
end

GRM.Identity = { CharacterKey = function(p) return isstring(p) and p or p._key end }

local FACTION = Vector(500, 500, 64)
_G.GetSpawnPointForPlayer = function() return FACTION, Angle(0, 45, 0) end
_G.ApplyWeaponsToPlayer = function(p) p._weapons = (p._weapons or 0) + 1 end

GRM.Factions = { DisplayName = function(n) return n end }

local function mkPly(o)
    o = o or {}
    local nw, nwi = { GRM_Faction = o.faction or "", GRM_CharacterKey = o.key or "1:char1" }, {}
    local p
    p = {
        _valid = true, _key = o.key or "1:char1", _pos = o.pos or Vector(0,0,0),
        _spawns = 0, _frozen = false, _weapons = 0,
        SteamID64 = function() return "1" end,
        Nick = function() return o.nick or "tester" end,
        GetPos = function(s) return s._pos end,
        SetPos = function(s,v) s._pos = Vector(v.x, v.y, v.z) end,
        SetEyeAngles = function() end,
        EyeAngles = function() return Angle(0, 33, 0) end,
        GetVelocity = function() return Vector(0,0,0) end,
        SetVelocity = function() end,
        GetMoveType = function() return MOVETYPE_WALK end,
        SetMoveType = function() end,
        SetNoDraw = function() end, DrawShadow = function() end,
        SetNotSolid = function() end, SetNoTarget = function() end,
        GodEnable = function() end, GodDisable = function() end,
        Freeze = function(s,v) s._frozen = (v == true) end,
        IsFlagSet = function(s) return s._frozen end,
        StripWeapons = function() end, RemoveAllAmmo = function() end,
        Alive = function() return o.dead ~= true end,
        InVehicle = function() return false end,
        IsPlayer = function() return true end,
        PrintMessage = function() end,
        --[[ Настоящий Spawn дёргает PlayerSpawn — именно там живут хуки,
             которые перетирали позицию. ]]
        Spawn = function(s)
            s._spawns = s._spawns + 1
            runAll("PlayerSpawn", s)
        end,
        GetNWInt = function(_,k,d) return nwi[k] or d or 0 end,
        SetNWInt = function(_,k,v) nwi[k] = v end,
        GetNWBool = function(_,k,d) if nw[k] ~= nil then return nw[k] end return d or false end,
        SetNWBool = function(_,k,v) nw[k] = v end,
        GetNWString = function(_,k,d) return nw[k] or d or "" end,
        SetNWString = function(_,k,v) nw[k] = v end,
        _nw = nw,
    }
    return p
end

-----------------------------------------------------------------------
-- ЗАГРУЗКА МОДУЛЕЙ (как на сервере)
-----------------------------------------------------------------------
assert(loadfile("lua/autorun/sh_grm_entry.lua"))()
assert(loadfile("lua/autorun/sh_grm_spawnpick.lua"))()
local E, SP = GRM.Entry, GRM.SpawnPick

-- Модуль персонажей в этом стенде не нужен целиком: важен его контракт.
GRM.Char = {
    FinishEntry = function(p)
        p.GRMCharLimbo = nil
        p.GRMCharConfirmed = true
        p:Spawn()
        return true
    end,
    EnforceLimbo = function(p) p.GRMCharLimbo = true p:Freeze(true) end,
    IsPending = function(p) return p.GRMCharConfirmed ~= true end,
}

--[[ Хук точек спавна — ровно как в sh_spawn_points.lua. Он и был главным
     подозреваемым: ставит игрока на фракционную точку на каждом спавне. ]]
hook.Add("PlayerSpawn", "SpawnAtFactionPoint", function(ply)
    if IsValid(ply) and GRM.Char and GRM.Char.IsPending and GRM.Char.IsPending(ply) then return end
    if GRM.Entry and GRM.Entry.InProgress and GRM.Entry.InProgress(ply) then return end
    if IsValid(ply) and ply.GRMEntryPoint ~= nil then return end
    ply:SetPos(FACTION)
end)

-----------------------------------------------------------------------
print("\n=== 1. СЕССИЯ 1: ИГРАЕМ И ВЫХОДИМ ===")
-----------------------------------------------------------------------
local EXIT = Vector(-1234, 567, 32)
local ply = mkPly({ key = "1:char1", faction = "OrPo", pos = EXIT })
PLAYERS = { ply }
ply.GRMCharConfirmed = true

WRITES = 0
local remembered = SP.Remember(ply, true)
ok(remembered == true, "точка выхода запомнена")
ok(WRITES == 1, "и записана на диск немедленно", WRITES)
ok(DISK[SP.File] ~= nil, "файл создан", SP.File)

-- Через хук дисконнекта — как в жизни.
ply._pos = EXIT
runAll("PlayerDisconnected", ply)
ok(istable(SP.Data["1:char1"]), "в памяти запись есть")
ok(SP.Data["1:char1"].pos.x == EXIT.x, "координаты верные", SP.Data["1:char1"].pos.x)
ok(SP.Data["1:char1"].map == MAP, "карта записана", SP.Data["1:char1"].map)

local saved = DISK[SP.File]
ok(isstring(saved) and saved:find("1234", 1, true) ~= nil,
   "координаты реально попали в JSON, а не потерялись при сериализации")

-----------------------------------------------------------------------
print("\n=== 2. РЕСТАРТ СЕРВЕРА ===")
-----------------------------------------------------------------------
--[[ Полностью забываем всё, что было в памяти, и поднимаем модуль
     заново — ровно как при перезапуске сервера. ]]
SP.Data = {}
PLAYERS = {}
SP.Load()

ok(istable(SP.Data["1:char1"]),
   "ИСПРАВЛЕНО/ПРОВЕРЕНО: после рестарта запись поднялась с диска")
if istable(SP.Data["1:char1"]) then
    ok(tonumber(SP.Data["1:char1"].pos.x) == EXIT.x,
       "и координаты те же, что были при выходе", SP.Data["1:char1"].pos.x)
    ok(tostring(SP.Data["1:char1"].map) == MAP, "и карта та же")
    ok(tonumber(SP.Data["1:char1"].at) ~= nil, "и время сохранилось числом")
end

-----------------------------------------------------------------------
print("\n=== 3. СЕССИЯ 2: ВХОД И ВЫБОР «ГДЕ ВЫШЕЛ» ===")
-----------------------------------------------------------------------
local p2 = mkPly({ key = "1:char1", faction = "OrPo", pos = Vector(0,0,0) })
PLAYERS = { p2 }

-- Точка выхода должна предлагаться как вариант.
local last = SP.LastPoint(p2)
ok(last ~= nil, "вариант «ГДЕ ВЫШЕЛ» доступен после рестарта")
if last then
    ok(last.pos.x == EXIT.x and last.pos.y == EXIT.y,
       "и указывает на реальное место выхода", tostring(last.pos))
end

local opts = SP.Options(p2)
local hasLast = false
for _, o in ipairs(opts) do if o.id == "last" then hasLast = true end end
ok(hasLast, "«ГДЕ ВЫШЕЛ» есть в списке вариантов", #opts)
ok(#opts >= 2, "вариантов больше одного — экран покажется", #opts)

-- Прогоняем конвейер входа целиком.
E.Begin(p2) pumpAll()
E.ToCharacter(p2) pumpAll()
E.ToSpawnPoint(p2) pumpAll()
ok(E.StageOf(p2) == E.Stages.spawnpoint, "игрок на стадии выбора точки",
   E.StageName[E.StageOf(p2)])
ok(p2.GRMSpawnPickPending == true, "экран выбора реально предложен")

-- Игрок нажимает «ГДЕ ВЫШЕЛ».
local pick = net["_h_" .. SP.NET.PICK]
ok(isfunction(pick), "обработчик выбора зарегистрирован")
net.ReadString = function() return "last" end
pick(0, p2)
pumpAll()

ok(E.StageOf(p2) == E.Stages.world, "игрок доведён до мира",
   E.StageName[E.StageOf(p2)])
ok(p2._pos.x == EXIT.x and p2._pos.y == EXIT.y,
   "ГЛАВНОЕ: игрок стоит ТАМ, ГДЕ ВЫШЕЛ, а не на фракции",
   ("получили %s, ждали %s"):format(tostring(p2._pos), tostring(EXIT)))
ok(p2._pos ~= FACTION, "и это точно не фракционная точка")
ok(p2._frozen == false, "и не заморожен")

-----------------------------------------------------------------------
print("\n=== 4. АВТОСНИМОК НЕ ПОРТИТ ТОЧКУ ВЫХОДА ===")
-----------------------------------------------------------------------
--[[ Снимок раз в 30 с перезаписывает точку текущей позицией. Это верно
     для живого игрока, но НЕ должно срабатывать, пока человек ещё идёт
     по конвейеру входа: иначе его «место выхода» затрётся фракционным
     спавном ещё до того, как он выберет. ]]
local p3 = mkPly({ key = "3:char1", faction = "OrPo", pos = Vector(-900, -900, 10) })
PLAYERS = { p3 }
SP.Data["3:char1"] = { pos = { x = -900, y = -900, z = 10 }, ang = { y = 0 },
    at = REALTIME, map = MAP }

E.Begin(p3) pumpAll()
E.ToCharacter(p3) pumpAll()
-- Пока игрок в лимбе, его «позиция» — это лимб за картой.
p3._pos = Vector(0, 0, 15500)
p3.GRMCharLimbo = true
tick("GRM_SpawnPick_Snapshot")
ok(SP.Data["3:char1"].pos.x == -900,
   "во время входа снимок НЕ затирает точку выхода лимбом",
   SP.Data["3:char1"].pos.x)

-- А когда игрок в мире — снимок работает как надо.
p3.GRMCharLimbo = nil
p3.GRMCharConfirmed = true
p3._pos = Vector(77, 88, 12)
tick("GRM_SpawnPick_Snapshot")
ok(SP.Data["3:char1"].pos.x == 77, "в игре снимок обновляет точку", SP.Data["3:char1"].pos.x)
flushCoalesced()

-----------------------------------------------------------------------
print("\n=== 5. ЧАСТНЫЕ СЛУЧАИ ===")
-----------------------------------------------------------------------
-- Другая карта.
SP.Data["1:char1"].map = "rp_other"
ok(SP.LastPoint(p2) == nil, "точка с другой карты не предлагается")
SP.Data["1:char1"].map = MAP

-- Протухшая.
SP.Data["1:char1"].at = REALTIME - SP.LastLifetime - 100
ok(SP.LastPoint(p2) == nil, "протухшая точка не предлагается")
SP.Data["1:char1"].at = REALTIME

-- Единственный вариант: экран не нужен, но точка всё равно применяется.
local p4 = mkPly({ key = "4:char1", pos = Vector(0,0,0) })   -- без фракции
PLAYERS = { p4 }
local LONE = Vector(321, 654, 20)
SP.Data["4:char1"] = { pos = { x = LONE.x, y = LONE.y, z = LONE.z },
    ang = { y = 0 }, at = REALTIME, map = MAP }
ok(#SP.Options(p4) == 1, "у гражданского без дома вариант один — «где вышел»")

E.Begin(p4) pumpAll()
E.ToCharacter(p4) pumpAll()
E.ToSpawnPoint(p4) pumpAll()
ok(E.StageOf(p4) == E.Stages.world, "конвейер довёл до мира без лишнего окна")
ok(p4._pos.x == LONE.x,
   "и поставил на точку выхода, а не на фракционную",
   ("получили %s, ждали %s"):format(tostring(p4._pos), tostring(LONE)))

-----------------------------------------------------------------------
print("\n=== 6. ФРАКЦИОННЫЙ ВЫБОР НЕ СЛОМАН ===")
-----------------------------------------------------------------------
local p5 = mkPly({ key = "5:char1", faction = "OrPo", pos = Vector(0,0,0) })
PLAYERS = { p5 }
SP.Data["5:char1"] = { pos = { x = -50, y = -50, z = 5 }, ang = { y = 0 },
    at = REALTIME, map = MAP }
E.Begin(p5) pumpAll()
E.ToCharacter(p5) pumpAll()
E.ToSpawnPoint(p5) pumpAll()
net.ReadString = function() return "faction" end
net["_h_" .. SP.NET.PICK](0, p5)
pumpAll()
ok(p5._pos.x == FACTION.x and p5._pos.y == FACTION.y,
   "кто выбрал ФРАКЦИЮ — тот и стоит на фракции", tostring(p5._pos))

-----------------------------------------------------------------------
print("\n=== 7. ДИАГНОСТИКА ПРИЧИН ОТКАЗА ===")
-----------------------------------------------------------------------
--[[ Владелец сообщил «где вышел не работает», а понять почему было
     нечем: функция просто возвращала nil. Теперь причина называется. ]]
local dp = mkPly({ key = "70:char1" })
PLAYERS = { dp }

local pt, why = SP.LastPointWhy(dp)
ok(pt == nil and isstring(why) and why:find("нет записи", 1, true) ~= nil,
   "нет записи — так и сказано", why)

SP.Data["70:char1"] = { pos = { x = 1, y = 2, z = 3 }, ang = { y = 0 },
    at = REALTIME, map = "rp_another" }
pt, why = SP.LastPointWhy(dp)
ok(pt == nil and why:find("другой карты", 1, true) ~= nil,
   "чужая карта — причина названа", why)

SP.Data["70:char1"].map = MAP
SP.Data["70:char1"].at = REALTIME - SP.LastLifetime - 500
pt, why = SP.LastPointWhy(dp)
ok(pt == nil and why:find("протухла", 1, true) ~= nil, "протухание — причина названа", why)

SP.Data["70:char1"].at = REALTIME
pt, why = SP.LastPointWhy(dp)
ok(pt ~= nil, "исправная запись отдаёт точку")

--[[ РЕГИСТР КАРТЫ. Записи, сделанные раньше, могли лечь с исходным
     регистром имени карты. Сравнение шло без приведения — и точка молча
     отбраковывалась как «с другой карты». ]]
SP.Data["70:char1"].map = "GM_Construct"
pt, why = SP.LastPointWhy(dp)
ok(pt ~= nil,
   "ИСПРАВЛЕНО: запись со старым регистром имени карты больше не теряется",
   tostring(why))

-- Пустая карта в записи (совсем древний формат) тоже не должна ломать.
SP.Data["70:char1"].map = ""
pt = SP.LastPointWhy(dp)
ok(pt ~= nil, "запись без имени карты принимается, а не выбрасывается")

-- Координаты строками (после кривой сериализации) — приводим к числу.
SP.Data["70:char1"].map = MAP
SP.Data["70:char1"].pos = { x = "123", y = "456", z = "7" }
pt = SP.LastPointWhy(dp)
ok(pt ~= nil and pt.pos.x == 123,
   "координаты-строки из JSON приводятся к числам", pt and pt.pos.x)

-----------------------------------------------------------------------
print("\n=== 8. СМЕРТЬ НЕ ТЕРЯЕТ МЕСТО ===")
-----------------------------------------------------------------------
--[[ Мёртвый точку не сохраняет (иначе спавн на трупе), но и терять
     место гибели нельзя: вышел после смерти — и «где вышел» указывало
     бы в никуда. ]]
local dead = mkPly({ key = "80:char1", pos = Vector(-777, 111, 8) })
PLAYERS = { dead }
SP.Data["80:char1"] = nil
runAll("PlayerDeath", dead)
ok(istable(SP.Data["80:char1"]),
   "ИСПРАВЛЕНО: последнее живое положение запомнено перед смертью")
ok(SP.Data["80:char1"] and SP.Data["80:char1"].pos.x == -777,
   "и это именно место гибели", SP.Data["80:char1"] and SP.Data["80:char1"].pos.x)

-- Арестованный не должен «запоминать» камеру даже так.
local jailed = mkPly({ key = "81:char1", pos = Vector(10, 10, 10) })
jailed._nw.GRM_Arrested = true
SP.Data["81:char1"] = nil
runAll("PlayerDeath", jailed)
ok(SP.Data["81:char1"] == nil, "смерть в аресте камеру не запоминает")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
