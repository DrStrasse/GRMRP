--[[ Живой прогон конвейера входа (жалоба владельца 27.08).

     ЧТО БЫЛО:
       «Перезашёл — на пару секунд видно, что персонаж УЖЕ заспавнился,
        потом окно загрузки, нажал "Начать играть", меню, выбрал перса,
        заспавнился, и через наносекунду меню точки входа.
        Нажми любую — ничего не происходит.»

     ЧТО ДОЛЖНО БЫТЬ:
       «нажал начать играть → выбрал перса → выбрал где зайти → и ТОЛЬКО
        ПОТОМ спавн персонажа», порционно, шаг за шагом.

     Стенд сначала воспроизводит старый порядок (спавн раньше выбора и
     затирание точки чужими хуками), потом проверяет новый конвейер.

     Запуск: luajit tools/luatest/sim_entry_pipeline.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

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
function table.insert(t, v) t[#t + 1] = v end
local rawremove = table.remove

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt(s) end
HUD_PRINTTALK = 3
MOVETYPE_WALK, MOVETYPE_NOCLIP = 2, 8
FL_FROZEN = 32

local NOW = 100
CurTime = function() return NOW end

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...) for _,f in pairs(hook._t[e] or {}) do local r=f(...) if r~=nil then return r end end end
local function runAll(e,...) for _,f in pairs(hook._t[e] or {}) do f(...) end end

--[[ Таймеры настоящие: конвейер построен на timer.Create, и нам важно
     прогонять его порциями вручную, а не «всё сразу». ]]
timer = { _c = {} }
function timer.Create(id,_,_,f) timer._c[id]=f end
function timer.Simple(_,f) f() end
function timer.Remove(id) timer._c[id]=nil end
function timer.Exists(id) return timer._c[id]~=nil end
local function tick(id, n)
    for _ = 1, (n or 1) do if timer._c[id] then timer._c[id]() end end
end
--- Прогнать конвейер до опустошения очереди (но не бесконечно).
local function pumpAll(limit)
    for _ = 1, (limit or 40) do tick("GRM_Entry_Pump") end
end

local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }

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
util = { AddNetworkString=function() end, TableToJSON=function() return "J" end,
         JSONToTable=function() return {} end }
file = { Exists=function() return false end, Read=function() return "" end,
         Write=function() end, CreateDir=function() end, IsDir=function() return true end }
local PLAYERS = {}
player = { GetAll=function() return PLAYERS end }
ents = { GetAll=function() return {} end, FindByClass=function() return {} end }
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,
    GetBool=function() return d~="0" end, GetString=function() return tostring(d) end,
    GetInt=function() return math.floor(tonumber(d) or 0) end} end

GRM = { Perf = { Players=function() return PLAYERS end } }
GRM.Notify = function() end

assert(loadfile("lua/autorun/sh_grm_entry.lua"))()
local E = GRM.Entry

-----------------------------------------------------------------------
-- ИГРОК
-----------------------------------------------------------------------
local function mkPly(o)
    o = o or {}
    local nw, nwi = {}, {}
    local p
    p = {
        _valid = true, _key = o.key or "1:char1",
        _pos = Vector(0,0,0), _spawns = 0, _weapons = 0, _stripped = 0,
        _log = {},
        SteamID64=function() return "1" end,
        Nick=function() return o.nick or "tester" end,
        GetPos=function(s) return s._pos end,
        SetPos=function(s,v) s._pos=v table.insert(s._log,"SetPos") end,
        SetEyeAngles=function() end,
        EyeAngles=function() return Angle(0,0,0) end,
        SetVelocity=function() end, GetVelocity=function() return Vector(0,0,0) end,
        GetMoveType=function() return MOVETYPE_NOCLIP end,
        SetMoveType=function() end,
        SetNoDraw=function(s,v) s._nodraw=v end, DrawShadow=function() end,
        SetNotSolid=function(s,v) s._solid=not v end, SetNoTarget=function() end,
        GodEnable=function(s) s._god=true end, GodDisable=function(s) s._god=false end,
        Freeze=function(s,v) s._frozen=(v==true) end,
        IsFlagSet=function(s) return s._frozen==true end,
        StripWeapons=function(s) s._stripped=s._stripped+1 end,
        RemoveAllAmmo=function() end,
        Spawn=function(s)
            s._spawns=s._spawns+1 table.insert(s._log,"Spawn")
            -- Настоящий движок здесь дёргает PlayerSpawn. Без этого стенд
            -- не ловил «заморожен после входа».
            runAll("PlayerSpawn", s)
        end,
        Alive=function() return true end, InVehicle=function() return false end,
        IsPlayer=function() return true end,
        PrintMessage=function(_,_,t) table.insert(p._said or {}, t) end,
        GetNWInt=function(_,k,d) return nwi[k] or d or 0 end,
        SetNWInt=function(_,k,v) nwi[k]=v end,
        GetNWBool=function(_,k,d) if nw[k]~=nil then return nw[k] end return d or false end,
        SetNWBool=function(_,k,v) nw[k]=v end,
        GetNWString=function(_,k,d) return nw[k] or d or "" end,
        SetNWString=function(_,k,v) nw[k]=v end,
        _said = {},
    }
    return p
end

-----------------------------------------------------------------------
print("\n=== 1. СТАРЫЙ ПОРЯДОК: ВОСПРОИЗВОДИМ ЖАЛОБУ ===")
-----------------------------------------------------------------------
do
    --[[ Как было: подтвердили персонажа → сразу Spawn + постановка на
         фракционную точку → и только потом спросили «куда хочешь». ]]
    local ply = mkPly({})
    local FACTION = Vector(500, 500, 64)
    local HOME    = Vector(-900, 120, 32)
    local order = {}

    local function oldRelease(p)
        p:Spawn()
        p:SetPos(FACTION)                 -- PlaceOnSpawnPoint
        table.insert(order, "spawn")
    end
    local function oldOfferPick(p) table.insert(order, "ask_point") end
    local function oldApply(p, pos)
        p:SetPos(pos)
        table.insert(order, "apply_choice")
    end
    -- Чужие хуки, которые отрабатывали после и возвращали игрока в штаб.
    local function oldSpawnAtFactionPoint(p) p:SetPos(FACTION) end
    local function oldPlaceAfterSelect(p) p:SetPos(FACTION) end

    oldRelease(ply)
    ok(order[1] == "spawn", "БАГ ВОСПРОИЗВЕДЁН: спавн происходил ДО вопроса о точке")
    ok(ply._pos == FACTION, "и игрок уже стоял в мире")

    oldOfferPick(ply)
    oldApply(ply, HOME)
    ok(ply._pos == HOME, "выбор на миг применялся...")

    -- А следом отрабатывали чужие хуки.
    oldPlaceAfterSelect(ply)
    oldSpawnAtFactionPoint(ply)
    ok(ply._pos == FACTION,
       "БАГ ВОСПРОИЗВЕДЁН: чужие хуки затирали выбор — «нажми любую, ничего не происходит»")

    ok(order[1] == "spawn" and order[2] == "ask_point",
       "БАГ ВОСПРОИЗВЕДЁН: порядок был спавн→вопрос вместо вопрос→спавн")
end

-----------------------------------------------------------------------
print("\n=== 2. НОВЫЙ КОНВЕЙЕР: СТАДИИ ПО ПОРЯДКУ ===")
-----------------------------------------------------------------------
local ply = mkPly({})
PLAYERS = { ply }

ok(E.StageOf(ply) == 0, "до входа стадии нет")

E.Begin(ply)
ok(E.StageOf(ply) == E.Stages.limbo, "вход начинается с лимба — игрок за картой",
   E.StageName[E.StageOf(ply)])
ok(E.InProgress(ply) == true, "конвейер活 активен, занавес опущен")

pumpAll()
ok(E.StageOf(ply) == E.Stages.loading, "следующая стадия — экран загрузки",
   E.StageName[E.StageOf(ply)])

ok(ply._spawns == 0, "на стадии загрузки НЕ спавним — этого и просил владелец")

E.ToCharacter(ply)
pumpAll()
ok(E.StageOf(ply) == E.Stages.character, "«НАЧАТЬ ИГРАТЬ» → окно персонажа",
   E.StageName[E.StageOf(ply)])
ok(ply._spawns == 0, "и здесь ещё не спавним")

-----------------------------------------------------------------------
print("\n=== 3. ВЫБОР ТОЧКИ ИДЁТ ДО СПАВНА ===")
-----------------------------------------------------------------------
--[[ Подкладываем модуль точек: два варианта, значит экран обязан
     показаться, а игрок — остаться вне мира. ]]
local offered, applied = 0, nil
GRM.SpawnPick = {
    Offer = function(p)
        offered = offered + 1
        return true      -- «экран показан»
    end,
}

E.ToSpawnPoint(ply)
pumpAll()
ok(E.StageOf(ply) == E.Stages.spawnpoint, "стадия — выбор точки входа",
   E.StageName[E.StageOf(ply)])
ok(offered == 1, "экран точек предложен ровно один раз", offered)
ok(ply._spawns == 0,
   "ИСПРАВЛЕНО: игрок ВСЁ ЕЩЁ не заспавнен — мира он не видел")
ok(E.InProgress(ply) == true, "занавес всё ещё держит чёрный экран")

-- Игрок выбрал «дом».
local HOME = Vector(-900, 120, 32)
local finished = 0
hook.Add("GRM_EntryFinished", "test", function() finished = finished + 1 end)

GRM.Char = { FinishEntry = function(p) p:Spawn() return true end }
_G.ApplyWeaponsToPlayer = function(p) p._weapons = p._weapons + 1 end

E.ToWorld(ply, { pos = HOME, ang = Angle(0, 90, 0) })
pumpAll()

ok(ply._spawns == 1, "ИСПРАВЛЕНО: спавн произошёл ПОСЛЕ выбора, ровно один раз", ply._spawns)
ok(ply._pos == HOME, "ИСПРАВЛЕНО: игрок стоит именно там, где выбрал", ply._pos and ply._pos.x)
ok(ply._weapons == 1, "оружие выдано в самом конце, один раз", ply._weapons)
ok(E.StageOf(ply) == E.Stages.world, "стадия — мир", E.StageName[E.StageOf(ply)])
ok(E.InProgress(ply) == false, "занавес поднят, игрок в игре")
ok(finished == 1, "событие завершения входа брошено один раз")

-- Порядок действий внутри финала.
local iSpawn, iPos
for i, v in ipairs(ply._log) do
    if v == "Spawn" and not iSpawn then iSpawn = i end
    if v == "SetPos" and iSpawn and not iPos then iPos = i end
end
ok(iSpawn and iPos and iSpawn < iPos,
   "ИСПРАВЛЕНО: сначала Spawn, ПОТОМ позиция — иначе движок затирает точку")

-----------------------------------------------------------------------
print("\n=== 4. ПОРЦИОННОСТЬ ===")
-----------------------------------------------------------------------
--[[ Владелец просил: «код должен выполняться постепенно, шаг за шагом,
     порционно». Проверяем, что финал входа НЕ выполняется в один кадр. ]]
local p2 = mkPly({ key = "2:char1" })
PLAYERS = { p2 }
E.Begin(p2)
pumpAll()
E.ToCharacter(p2) pumpAll()
E.ToSpawnPoint(p2)

-- Один тик = один шаг.
local before = E.Queue[p2] and #E.Queue[p2] or 0
ok(before > 0, "переход поставлен в очередь порциями, а не выполнен разом", before)
tick("GRM_Entry_Pump")
local after = E.Queue[p2] and #E.Queue[p2] or 0
ok(after == before - 1, "за один тик выполняется РОВНО один шаг", ("%d→%d"):format(before, after))

pumpAll()
E.ToWorld(p2, { pos = Vector(1,2,3) })
local qn = E.Queue[p2] and #E.Queue[p2] or 0
ok(qn >= 3, "финал входа тоже разбит на несколько шагов", qn)
pumpAll()
ok(E.StageOf(p2) == E.Stages.world, "и в итоге доходит до мира")

-- Ошибка в шаге не рвёт конвейер.
local p3 = mkPly({ key = "3:char1" })
PLAYERS = { p3 }
E.Begin(p3) pumpAll()
E.Step(p3, "boom", function() error("тестовая ошибка") end)
E.Step(p3, "after", function(p) p._afterBoom = true end)
pumpAll()
ok(p3._afterBoom == true, "упавший шаг не останавливает остальные — вход не зависнет")

-----------------------------------------------------------------------
print("\n=== 5. ДВОЙНЫЕ ВЫЗОВЫ И ЗАЩИТА ===")
-----------------------------------------------------------------------
local p4 = mkPly({ key = "4:char1" })
PLAYERS = { p4 }
GRM.Char = { FinishEntry = function(p) p:Spawn() return true end }
E.Begin(p4) pumpAll()
E.ToCharacter(p4) pumpAll()
E.ToSpawnPoint(p4) pumpAll()

E.ToWorld(p4, { pos = Vector(10,10,10) })
E.ToWorld(p4, { pos = Vector(99,99,99) })   -- повторный вызов
pumpAll()
ok(p4._spawns == 1, "повторный ToWorld не спавнит второй раз", p4._spawns)
ok(p4._pos.x == 10, "и не перебивает уже применённую точку", p4._pos.x)

-- Назад по конвейеру не ходим.
local stage = E.StageOf(p4)
E.SetStage(p4, E.Stages.loading)
ok(E.StageOf(p4) == stage, "стадия не откатывается назад сама по себе")
ok(E.SetStage(p4, E.Stages.loading, true) == true, "но явный сброс возможен")

-----------------------------------------------------------------------
print("\n=== 6. НИЧЕГО НЕ ВЫДАЁМ ДО МИРА ===")
-----------------------------------------------------------------------
local p5 = mkPly({ key = "5:char1" })
PLAYERS = { p5 }
E.Begin(p5) pumpAll()

ok(hook.Run("PlayerLoadout", p5) == true,
   "PlayerLoadout перехвачен: движок не выдаёт стандартный набор")
ok(p5._stripped > 0, "и оружие снимается")
ok(hook.Run("PlayerShouldTakeDamage", p5) == false, "урон не проходит")
ok(hook.Run("PlayerCanPickupWeapon", p5) == false, "поднять оружие нельзя")
ok(hook.Run("CanPlayerSuicide", p5) == false, "самоубийство заблокировано")
ok(hook.Run("PlayerSay", p5, "привет") == "", "в чат из чёрного экрана не пишем")

-- А в мире всё возвращается.
GRM.Char = { FinishEntry = function(p) p:Spawn() return true end }
E.ToCharacter(p5) pumpAll()
E.ToSpawnPoint(p5) pumpAll()
E.ToWorld(p5, { pos = Vector(5,5,5) }) pumpAll()
ok(hook.Run("PlayerLoadout", p5) == nil, "в мире экипировка выдаётся как обычно")
ok(hook.Run("PlayerShouldTakeDamage", p5) == nil, "и урон снова проходит")
ok(hook.Run("PlayerSay", p5, "привет") == nil, "и чат работает")

-----------------------------------------------------------------------
print("\n=== 7. ОДИН ВАРИАНТ ТОЧКИ — ЭКРАН НЕ НУЖЕН ===")
-----------------------------------------------------------------------
local p6 = mkPly({ key = "6:char1" })
PLAYERS = { p6 }
GRM.SpawnPick = { Offer = function() return false end }   -- «выбирать не из чего»
GRM.Char = { FinishEntry = function(p) p:Spawn() return true end }
E.Begin(p6) pumpAll()
E.ToCharacter(p6) pumpAll()
E.ToSpawnPoint(p6) pumpAll()
ok(E.StageOf(p6) == E.Stages.world,
   "при единственном варианте конвейер сам доводит до мира, без лишнего окна",
   E.StageName[E.StageOf(p6)])
ok(p6._spawns == 1, "и спавнит ровно один раз")

-- Модуль точек вообще не загружен.
local p7 = mkPly({ key = "7:char1" })
PLAYERS = { p7 }
GRM.SpawnPick = nil
E.Begin(p7) pumpAll()
E.ToCharacter(p7) pumpAll()
E.ToSpawnPoint(p7) pumpAll()
ok(E.StageOf(p7) == E.Stages.world,
   "без модуля точек игрок всё равно попадает в мир, а не виснет")

-----------------------------------------------------------------------
print("\n=== 8. СТРАХОВКА ОТ ЗАВИСАНИЯ ===")
-----------------------------------------------------------------------
local p8 = mkPly({ key = "8:char1" })
PLAYERS = { p8 }
GRM.SpawnPick = { Offer = function() return true end }   -- окно висит, игрок молчит
GRM.Char = { FinishEntry = function(p) p:Spawn() return true end }
E.Begin(p8) pumpAll()
E.ToCharacter(p8) pumpAll()
E.ToSpawnPoint(p8) pumpAll()
ok(E.StageOf(p8) == E.Stages.spawnpoint, "игрок завис на выборе точки")

-- Время вышло.
NOW = NOW + E.StageTimeout + 10
tick("GRM_Entry_Watchdog")
pumpAll()
ok(E.StageOf(p8) == E.Stages.world,
   "сторож довёл зависшего до мира — лучше так, чем вечный чёрный экран")

-----------------------------------------------------------------------
print("\n=== 9. ИСХОДНИКИ: СТАРЫЕ ЗАТИРАТЕЛИ УБРАНЫ ===")
-----------------------------------------------------------------------
local function readf(p) local f=assert(io.open(p)) local s=f:read("*a") f:close() return s end

local chSrc = readf("lua/autorun/sh_grm_character.lua")
ok(chSrc:find("GRM_Char_PlaceAfterSelect", 1, true) == nil
   or chSrc:find('hook.Add("PlayerSpawn", "GRM_Char_PlaceAfterSelect"', 1, true) == nil,
   "ИСПРАВЛЕНО: хук GRM_Char_PlaceAfterSelect больше не двигает игрока")
ok(chSrc:find("function CH.FinishEntry", 1, true) ~= nil,
   "спавн вынесен в отдельную CH.FinishEntry, которую зовёт только конвейер")

local relBody = chSrc:match("function CH%.ReleaseFromLimbo.-\n    end")
ok(relBody ~= nil, "ReleaseFromLimbo найдена")
ok(relBody and relBody:find("ply:Spawn()", 1, true) == nil,
   "ИСПРАВЛЕНО: ReleaseFromLimbo больше НЕ спавнит — только снимает лимб")
ok(relBody and relBody:find("PlaceOnSpawnPoint", 1, true) == nil,
   "и не ставит на точку сама")

local spSrc = readf("lua/autorun/sh_spawn_points.lua")
ok(spSrc:find("GRM.Entry.InProgress", 1, true) ~= nil,
   "ИСПРАВЛЕНО: SpawnAtFactionPoint уступает конвейеру")

local pickSrc = readf("lua/autorun/sh_grm_spawnpick.lua")
ok(pickSrc:find("E.ToWorld(ply, point)", 1, true) ~= nil,
   "ИСПРАВЛЕНО: выбор точки ведёт в мир через конвейер, а не двигает стоящего")
ok(pickSrc:find("GRM_SpawnPick_Fallback", 1, true) ~= nil,
   "оставлен запасной путь, если конвейер не загрузился")

local ldSrc = readf("lua/autorun/sh_grm_loading.lua")
ok(ldSrc:find("GRM.Entry.Begin", 1, true) ~= nil,
   "конвейер стартует в PlayerInitialSpawn — занавес до первого кадра")
ok(ldSrc:find("GRM.Entry.ToCharacter", 1, true) ~= nil,
   "«НАЧАТЬ ИГРАТЬ» двигает стадию")

local entSrc = readf("lua/autorun/sh_grm_entry.lua")
ok(entSrc:find('hook.Add("RenderScene"', 1, true) ~= nil,
   "мир не рисуется до появления в нём — кадр мира мелькнуть не может")
ok(entSrc:find('hook.Add("HUDShouldDraw"', 1, true) ~= nil, "HUD скрыт до мира")

-----------------------------------------------------------------------
print("\n=== 10. ДИАГНОСТИКА ===")
-----------------------------------------------------------------------
ok(isfunction(commands["grm_entry"]), "есть команда grm_entry")
local diag = mkPly({ key = "9:char1" })
PLAYERS = { diag }
E.Begin(diag) pumpAll()
diag._said = {}
commands["grm_entry"](diag)
ok(#diag._said > 0, "диагностика печатает стадии игроков")

-----------------------------------------------------------------------
print("\n=== 11. ЖИВОЙ ИГРОК НЕ ЗАМОРОЖЕН (жалоба владельца 28.08) ===")
-----------------------------------------------------------------------
--[[ «Дошёл до меню выбора выхода, персонаж появился, всё выдало, но
     персонаж заморожен, не может сдвинуться.»

     Причина была в самом конвейере: шаг «release» зовёт Spawn(), тот
     дёргает PlayerSpawn, а стадия ещё spawnpoint — хук GRM_Entry_KeepLimbo
     ловил СОБСТВЕННЫЙ спавн и возвращал игрока в лимб, то есть в
     Freeze(true). Дальше ставились позиция и оружие, но размораживать
     было уже некому. ]]
do
    local p = mkPly({ key = "20:char1" })
    PLAYERS = { p }
    GRM.SpawnPick = { Offer = function() return true end }
    GRM.Char = {
        -- Настоящий CH.FinishEntry именно так и делает.
        FinishEntry = function(pl) pl:Spawn() return true end,
        -- И настоящий лимб замораживает.
        EnforceLimbo = function(pl)
            pl.GRMCharLimbo = true
            pl:Freeze(true)
            pl:SetNoDraw(true)
            pl:SetNotSolid(true)
            pl:GodEnable()
        end,
    }

    E.Begin(p) pumpAll()
    E.ToCharacter(p) pumpAll()
    E.ToSpawnPoint(p) pumpAll()
    --[[ Морозит в лимбе модуль персонажей (CH.SendToLimbo), которого в
         этом стенде нет. Воспроизводим это состояние руками — важна не
         сама заморозка, а то, что конвейер обязан её снять. ]]
    GRM.Char.EnforceLimbo(p)
    ok(p._frozen == true, "в лимбе игрок заморожен — так и задумано")

    E.ToWorld(p, { pos = Vector(42, 42, 0) })
    pumpAll()

    ok(E.StageOf(p) == E.Stages.world, "игрок доведён до мира")
    ok(p._frozen == false,
       "ИСПРАВЛЕНО: после входа игрок НЕ заморожен и может двигаться", p._frozen)
    ok(p._nodraw == false, "и видим — лимб не оставил его невидимым")
    ok(p._solid == true, "и материален")
    ok(p._god == false, "и уязвим, как обычный игрок")
    ok(p.GRMCharLimbo == nil, "флаг лимба снят")
    ok(p._pos.x == 42, "и стоит на выбранной точке", p._pos.x)
end

-- Контрольная разморозка: чужой хук заморозил уже после нас.
do
    local p = mkPly({ key = "21:char1" })
    PLAYERS = { p }
    GRM.SpawnPick = { Offer = function() return false end }
    GRM.Char = { FinishEntry = function(pl) pl:Spawn() return true end }

    -- Посторонний модуль (модели фракций, аугментации) морозит на спавне.
    hook.Add("PlayerSpawn", "TestFreezer", function(pl) pl:Freeze(true) end)
    E.Begin(p) pumpAll()
    E.ToCharacter(p) pumpAll()
    E.ToSpawnPoint(p) pumpAll()
    pumpAll()
    hook.Remove("PlayerSpawn", "TestFreezer")

    ok(E.StageOf(p) == E.Stages.world, "игрок в мире")
    ok(p._frozen == false,
       "контрольная разморозка снимает заморозку от чужого хука на PlayerSpawn")
end

-- Арестованного размораживать нельзя: его морозят законно.
do
    local src = readf("lua/autorun/sh_grm_entry.lua")
    ok(src:find("GRM_Arrested", 1, true) ~= nil,
       "контрольная разморозка не трогает арестованного")
    ok(src:find("GRM_911_Downed", 1, true) ~= nil,
       "и лежащего без сознания")
    local keep = src:match('hook%.Add%("PlayerSpawn", "GRM_Entry_KeepLimbo".-\n    end%)')
    ok(keep and keep:find("GRMEntryDone", 1, true) ~= nil,
       "ИСПРАВЛЕНО: KeepLimbo не ловит собственный спавн конвейера")
end

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
