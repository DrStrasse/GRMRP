--[[ Живой прогон обыска и журнала входов (жильё, фаза 3).

     Владелец ответил «да» на «может ли полиция попасть в жильё: ордер,
     взлом, обыск». Фазы 1-2 научились ПУСКАТЬ по ордеру. Здесь главное,
     ради чего ордер вообще нужен в РП: владелец УЗНАЁТ, что у него были,
     и может это оспорить.

     Проверяется:
       1) вход по ордеру пишется в журнал с номером, судьёй и причиной;
       2) взлом отличается от ордера — в суде это разные вещи;
       3) владельцу приходит уведомление, себе о себе — нет;
       4) офлайн-владелец узнаёт при входе в игру;
       5) одно нажатие двери = одна запись, а не пять;
       6) журнал не растёт вечно и не виден посторонним;
       7) данные ордера остаются в записи, даже когда ордер истёк.

     Запуск: luajit tools/luatest/sim_housing_search.lua ]]

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

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx,dy,dz=self.x-o.x,self.y-o.y,self.z-o.z return dx*dx+dy*dy+dz*dz end
function VecMT:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function VecMT:Normalize() return self end
function VecMT:Angle() return Angle(0,0,0) end
function VecMT.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function VecMT.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function VecMT.__mul(a,s) if isnumber(s) then return Vector(a.x*s,a.y*s,a.z*s) end return Vector(a.x*s.x,a.y*s.y,a.z*s.z) end
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, VecMT) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function ErrorNoHalt() end

-- Управляемое время: обязательно для проверки кулдаунов и склейки.
local NOW = 1000
CurTime = function() return NOW end
local REALTIME = 1700000000
local realOsTime = os.time
os.time = function() return REALTIME end

HUD_PRINTTALK = 3
MASK_PLAYERSOLID = 33570819
FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
bit = { bor = function(a,b) return a+b end }

hook = { _t = {} }
function hook.Add(e,i,f) hook._t[e]=hook._t[e] or {}; hook._t[e][i]=f end
function hook.Remove(e,i) if hook._t[e] then hook._t[e][i]=nil end end
function hook.Run(e,...)
    for _,f in pairs(hook._t[e] or {}) do local r,b=f(...) if r~=nil then return r,b end end
end
-- Вызвать ВСЕ обработчики (нужно, чтобы наблюдатель отработал даже когда
-- другой хук вернул значение) — так делает сам GMod для не-возвращающих.
local function runAll(e, ...)
    for _,f in pairs(hook._t[e] or {}) do f(...) end
end

timer = { _c = {} }
function timer.Simple(_,f) f() end
function timer.Create(id,_,_,f) timer._c[id]=f end
function timer.Remove(id) timer._c[id]=nil end

local commands = {}
concommand = { Add = function(n,f) commands[n]=f end }

local SENT = {}
local buf
net = {
    AddNetworkString = function() end,
    Start = function(n) buf = { name=n, args={} } end,
    WriteEntity=function(v) table.insert(buf.args,v) end,
    WriteTable =function(v) table.insert(buf.args,v) end,
    WriteFloat =function(v) table.insert(buf.args,v) end,
    WriteUInt  =function(v) table.insert(buf.args,v) end,
    WriteString=function(v) table.insert(buf.args,v) end,
    WriteBool  =function(v) table.insert(buf.args,v) end,
    Send = function(p) buf.to=p table.insert(SENT,buf) end,
    Receive = function(n,f) net["_h_"..n]=f end,
}
util = {
    AddNetworkString=function() end,
    TableToJSON=function() return "J" end,
    JSONToTable=function() return {} end,
    IsValidModel=function() return true end,
}
local FS = { data={}, writes=0 }
file = {
    Exists=function(n) return FS.data[n]~=nil end,
    Read=function(n) return FS.data[n] or "" end,
    Write=function(n,t) FS.data[n]=t FS.writes=FS.writes+1 end,
    Append=function() end, CreateDir=function() end, IsDir=function() return true end,
}
local PLAYERS = {}
player = { GetAll=function() return PLAYERS end }
ents = { GetAll=function() return {} end, FindByClass=function() return {} end, FindInSphere=function() return {} end }
function CreateConVar(_,d) return {GetFloat=function() return tonumber(d) or 0 end,GetBool=function() return d~="0" end,GetString=function() return tostring(d) end,GetInt=function() return math.floor(tonumber(d) or 0) end} end

local NOTIFIED = {}
GRM = { Perf = { Players=function() return PLAYERS end } }
GRM.Notify = function(p, msg) NOTIFIED[#NOTIFIED+1] = { to=p, msg=msg } end
local AUDIT = {}
GRM.Audit = { Write=function(cat,act,ply,ids,d) AUDIT[#AUDIT+1]={cat=cat,act=act,ids=ids,d=d} end }

local SAVES = 0
GRM.Property = {
    Records = {},
    Normalize=function(r) return r end,
    IsInside=function(r,pos)
        if not istable(r.zone) then return false end
        local a,b=r.zone.mins,r.zone.maxs
        return pos.x>=a.x and pos.y>=a.y and pos.z>=a.z and pos.x<=b.x and pos.y<=b.y and pos.z<=b.z
    end,
    CanAdmin=function(p) return IsValid(p) and p._admin==true end,
    HasAccess=function(p,r)
        if not IsValid(p) then return false end
        if r.ownerType=="character" and r.ownerKey==p._key then return true end
        for _,g in ipairs(r.guests or {}) do if g==p._key then return true end end
        return false
    end,
    GetByDoor=function(d)
        for _,r in pairs(GRM.Property.Records) do
            for _,id in ipairs(r.doors or {}) do if id==(d and d._id) then return r end end
        end
    end,
    Save=function() SAVES = SAVES + 1 end,
}

-- Ордера: настоящая структура из sh_grm_doors.
local WDATA = { warrants = {} }
GRM.Doors = {
    Data = WDATA,
    IsDoor=function(e) return IsValid(e) and e._door==true end,
    GetDoorID=function(e) return e._id end,
    HasWarrant=function(k)
        local w = WDATA.warrants[k]
        return istable(w) and (not w.status or w.status=="active")
    end,
    HasPropertyWarrant=function(id)
        for _,w in pairs(WDATA.warrants) do
            if istable(w) and tostring(w.propertyId or "")==tostring(id) and id~="" then
                if not w.status or w.status=="active" then return true end
            end
        end
        return false
    end,
}
GRM.Access = { Can=function(p,c) return IsValid(p) and p._caps and p._caps[c]==true end }
GRM.Estate = { ZoneCenter=function(r)
    if not istable(r.zone) then return nil end
    local a,b=r.zone.mins,r.zone.maxs
    return Vector((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
end }

local ONLINE = {}
GRM.Identity = {
    CharacterKey=function(p) return p._key end,
    ResolveCharacter=function(k) return ONLINE[k] end,
}

-- Ядро грузится первым и на живом сервере (sh_01_grm_core.lua), и здесь:
-- модули ниже берут из него канон GRM.CharKey (§5.2.6, одна реализация).
assert(loadfile("lua/autorun/sh_01_grm_core.lua"))()
assert(loadfile("lua/autorun/sh_grm_housing.lua"))()
assert(loadfile("lua/autorun/sh_grm_housing_search.lua"))()
local HS, SR = GRM.Housing, GRM.HousingSearch

local function mkPly(o)
    o = o or {}
    local said = {}
    local p
    p = {
        _valid=true, _key=o.key or "1:char1", _admin=o.admin==true,
        _caps=o.caps or {}, _pos=o.pos or Vector(0,0,0), _said=said,
        _nw = { GRM_RPName = o.name or "", GRM_Faction = o.faction or "" },
        SteamID64=function() return "1" end,
        Nick=function() return o.nick or "tester" end,
        GetPos=function(s) return s._pos end,
        EyeAngles=function() return Angle(0,0,0) end,
        GetEyeTrace=function() return { Entity=o.aim } end,
        IsPlayer=function() return true end,
        PrintMessage=function(_,_,t) said[#said+1]=t end,
        GetNWString=function(s,k,d) return s._nw[k] or d or "" end,
        GetNWBool=function(_,_,d) return d or false end,
    }
    return p
end

local function mkDoor(id) return { _valid=true, _door=true, _id=id } end

local flat = {
    id="flat1", name="Квартира 14", type="apartment",
    ownerType="character", ownerKey="1:char1", tenure="owned",
    sealed=false, rentUntil=0, doors={"d1"}, guests={},
    zone={mins=Vector(-100,-100,-50),maxs=Vector(200,100,200)},
}
GRM.Property.Records = { flat1 = flat }
local door = mkDoor("d1")

local owner = mkPly({ key="1:char1", name="Иван Петров" })
local cop = mkPly({ key="7:char1", name="Сержант Ким", faction="OrPo",
                    caps={["wanted.civil.edit"]=true} })
local thief = mkPly({ key="5:char1", name="Вор" })
local admin = mkPly({ key="8:char1", name="Админ", admin=true })
ONLINE["1:char1"] = owner

--- Сбросить состояние между сценариями.
local function reset()
    flat.entryLog = nil
    flat._entrySeen = nil
    NOTIFIED = {}
    for i = #NOTIFIED, 1, -1 do NOTIFIED[i] = nil end
    owner._grmHousingTold = nil
    NOW = NOW + 10000
    REALTIME = REALTIME + 10000
end

-----------------------------------------------------------------------
print("\n=== 1. ВХОД ПО ОРДЕРУ ПОПАДАЕТ В ЖУРНАЛ ===")
-----------------------------------------------------------------------
reset()
WDATA.warrants["w1"] = {
    id="w1", number="2026-0042", propertyId="flat1", type="search",
    reason="подозрение в хранении оружия", byNick="Сержант Ким",
    approvedByName="Судья Вебер", status="active",
}

runAll("GRM_DoorAccessOverride", cop, door)

ok(istable(flat.entryLog) and #flat.entryLog == 1, "вход по ордеру записан",
   flat.entryLog and #flat.entryLog)
local e = flat.entryLog and flat.entryLog[1]
ok(e and e.kind == "warrant", "вид записи — ордер", e and e.kind)
ok(e and e.who == "Сержант Ким", "записано РП-имя вошедшего", e and e.who)
ok(e and e.warrantNo == "2026-0042", "номер ордера сохранён", e and e.warrantNo)
ok(e and e.judge == "Судья Вебер", "судья сохранён — есть что оспаривать", e and e.judge)
ok(e and e.reason:find("оружия", 1, true) ~= nil, "основание сохранено", e and e.reason)
ok(e and e.faction == "OrPo", "фракция вошедшего видна")
ok(SAVES > 0, "объект сохранён — журнал переживёт рестарт")

--[[ Ключевое: данные ордера лежат В ЗАПИСИ. Ордер истечёт и удалится,
     а доказательство должно остаться. ]]
WDATA.warrants = {}
local still = flat.entryLog[1]
ok(still.warrantNo == "2026-0042" and still.judge == "Судья Вебер",
   "ордер истёк и удалён, но запись в журнале сохранила его данные")

-----------------------------------------------------------------------
print("\n=== 2. УВЕДОМЛЕНИЕ ВЛАДЕЛЬЦУ ===")
-----------------------------------------------------------------------
ok(#NOTIFIED > 0, "владельцу пришло уведомление об обыске")
ok(NOTIFIED[1] and NOTIFIED[1].to == owner, "именно владельцу")
ok(NOTIFIED[1] and NOTIFIED[1].msg:find("ордер", 1, true) ~= nil,
   "в тексте сказано, что это ордер", NOTIFIED[1] and NOTIFIED[1].msg)
ok(NOTIFIED[1] and NOTIFIED[1].msg:find("2026-0042", 1, true) ~= nil,
   "и указан номер — владелец сможет проверить законность")

-- Себе о себе не сообщаем.
reset()
WDATA.warrants = {}
runAll("GRM_DoorAccessOverride", owner, door)
ok(#NOTIFIED == 0, "владелец не получает уведомление о собственном входе")
ok(flat.entryLog == nil or #flat.entryLog == 0,
   "и свой вход в журнал не пишется — иначе журнал был бы мусором")

-----------------------------------------------------------------------
print("\n=== 3. ВЗЛОМ ОТЛИЧАЕТСЯ ОТ ОРДЕРА ===")
-----------------------------------------------------------------------
reset()
runAll("GRM_OnDoorLockpicked", thief, door)
e = flat.entryLog and flat.entryLog[1]
ok(e and e.kind == "breach", "взлом записан отдельным видом", e and e.kind)
ok(e and (e.warrantNo == nil or e.warrantNo == ""), "у взлома нет номера ордера")
ok(#NOTIFIED > 0 and NOTIFIED[1].msg:find("ВЗЛОМ", 1, true) ~= nil,
   "владельцу прямо сказано, что это взлом, а не законный обыск",
   NOTIFIED[1] and NOTIFIED[1].msg)

reset()
runAll("GRM_DoorHacked", thief, door)
ok(flat.entryLog and flat.entryLog[1].kind == "breach",
   "взлом кейпадом тоже считается взломом")

-----------------------------------------------------------------------
print("\n=== 4. ГОСТЬ ПО КЛЮЧУ ===")
-----------------------------------------------------------------------
reset()
flat.guests = { "5:char1" }
runAll("GRM_DoorAccessOverride", thief, door)
e = flat.entryLog and flat.entryLog[1]
ok(e and e.kind == "guest", "вход по выданному ключу отмечен как гость", e and e.kind)
ok(#NOTIFIED > 0, "владелец видит, что его ключом пользовались")
flat.guests = {}

-----------------------------------------------------------------------
print("\n=== 5. ОДНО НАЖАТИЕ = ОДНА ЗАПИСЬ ===")
-----------------------------------------------------------------------
--[[ Дверь в GMod дёргается несколько раз за нажатие: полотна, дубли,
     партнёрская створка. Без склейки журнал забился бы повторами. ]]
reset()
WDATA.warrants["w2"] = { id="w2", number="7", propertyId="flat1", status="active" }
for i = 1, 5 do runAll("GRM_DoorAccessOverride", cop, door) end
ok(#flat.entryLog == 1, "пять срабатываний хука дали одну запись", #flat.entryLog)

-- А через время — уже новый визит.
REALTIME = REALTIME + SR.RecentWindow + 5
runAll("GRM_DoorAccessOverride", cop, door)
ok(#flat.entryLog == 2, "повторный визит позже пишется отдельно", #flat.entryLog)

-- Кулдаун уведомлений: журнал пишем, но владельца не спамим.
ok(#NOTIFIED == 1, "владелец получил ОДНО уведомление, а не два подряд", #NOTIFIED)
WDATA.warrants = {}

-----------------------------------------------------------------------
print("\n=== 6. ОБЫСК ШКАФА ===")
-----------------------------------------------------------------------
reset()
WDATA.warrants["w3"] = { id="w3", number="99", propertyId="flat1",
    reason="изъятие", approvedByName="Судья", status="active" }
hook.Run("GRM_HomeStorageSearched", cop, flat, nil, "warrant_property")
e = flat.entryLog and flat.entryLog[1]
ok(e ~= nil, "осмотр шкафа записан")
ok(e and e.what:find("шкаф", 1, true) ~= nil,
   "и отмечен именно как осмотр шкафа, а не просто вход", e and e.what)
ok(e and e.warrantNo == "99", "с номером ордера")
WDATA.warrants = {}

-----------------------------------------------------------------------
print("\n=== 7. ОФЛАЙН-ВЛАДЕЛЕЦ ===")
-----------------------------------------------------------------------
reset()
ONLINE["1:char1"] = nil     -- владелец вышел
SR.Pending = {}
WDATA.warrants["w4"] = { id="w4", number="55", propertyId="flat1", status="active" }
runAll("GRM_DoorAccessOverride", cop, door)

ok(istable(SR.Pending["1:char1"]) and #SR.Pending["1:char1"] == 1,
   "обыск в отсутствие владельца копится — иначе пришли в 4 утра и он не узнал")
ok(FS.data[SR.PendingFile] ~= nil, "и сохраняется на диск: переживёт рестарт сервера")

-- Владелец вернулся.
ONLINE["1:char1"] = owner
local n = #owner._said
local delivered = SR.FlushPending(owner)
ok(delivered == 1, "при входе накопленное выдано", delivered)
ok(#owner._said > n, "и напечатано игроку")
ok(SR.Pending["1:char1"] == nil, "очередь очищена — второй раз не покажем")
WDATA.warrants = {}

-- Лимит офлайн-очереди.
SR.Pending = {}
ONLINE["1:char1"] = nil
for i = 1, 15 do
    SR.NotifyOwner(flat, { at = REALTIME, kind = "breach", who = "Вор"..i, whoKey = "9:char"..i }, thief)
end
ok(#SR.Pending["1:char1"] <= 10,
   "очередь ограничена: недельное отсутствие не превратится в стену текста",
   #SR.Pending["1:char1"])
ONLINE["1:char1"] = owner
SR.Pending = {}

-----------------------------------------------------------------------
print("\n=== 8. ЖУРНАЛ НЕ РАСТЁТ ВЕЧНО ===")
-----------------------------------------------------------------------
reset()
flat.entryLog = {}
for i = 1, SR.MaxEntries + 15 do
    flat.entryLog[i] = { at = REALTIME, kind = "guest", who = "гость" .. i }
end
SR.Trim(flat)
ok(#flat.entryLog == SR.MaxEntries, "журнал обрезан до лимита", #flat.entryLog)
ok(flat.entryLog[#flat.entryLog].who == "гость" .. (SR.MaxEntries + 15),
   "остались САМЫЕ СВЕЖИЕ записи, а не первые попавшиеся")

-- Протухшие.
flat.entryLog = {
    { at = REALTIME - SR.EntryLifetime - 100, kind = "guest", who = "древний" },
    { at = REALTIME, kind = "guest", who = "свежий" },
}
SR.Trim(flat)
ok(#flat.entryLog == 1 and flat.entryLog[1].who == "свежий",
   "записи старше срока хранения удаляются")

-----------------------------------------------------------------------
print("\n=== 9. КТО МОЖЕТ СМОТРЕТЬ ЖУРНАЛ ===")
-----------------------------------------------------------------------
ok(SR.CanViewLog(owner, flat) == true, "владелец видит свой журнал")
ok(SR.CanViewLog(cop, flat) == true, "следствие видит — ему нужна история")
ok(SR.CanViewLog(admin, flat) == true, "админ видит")
ok(SR.CanViewLog(thief, flat) == false,
   "посторонний НЕ видит — иначе журнал сам стал бы слежкой за жильцом")

-- Сортировка и выдача.
flat.entryLog = {
    { at = REALTIME - 500, kind = "guest", who = "старый" },
    { at = REALTIME, kind = "warrant", who = "новый" },
}
local rows = SR.LogFor(flat)
ok(#rows == 2, "журнал отдаётся целиком")
ok(rows[1].who == "новый", "свежие записи сверху — это то, что интересно первым")

-- Открытие окна.
SENT = {}
for i = #SENT, 1, -1 do SENT[i] = nil end
owner._pos = Vector(50, 0, 0)
ok(SR.Open(owner) == true, "владелец открывает журнал")
ok(#SENT > 0 and SENT[#SENT].name == SR.NET.LOG, "окно отправлено клиенту")

thief._pos = Vector(50, 0, 0)
ok(SR.Open(thief) == false, "посторонний в чужой квартире журнал не откроет")

ok(isfunction(commands["grm_housing_log"]), "есть команда grm_housing_log")

-----------------------------------------------------------------------
print("\n=== 10. НАБЛЮДАТЕЛЬ НЕ ЛОМАЕТ ДОСТУП ===")
-----------------------------------------------------------------------
--[[ Самое опасное место: мы слушаем тот же хук, который РЕШАЕТ, пускать
     или нет. Если бы наблюдатель что-то возвращал, он переопределил бы
     чужое решение и, например, открыл опечатанную квартиру. ]]
local src = assert(io.open("lua/autorun/sh_grm_housing_search.lua")):read("*a")
local watch = src:match('hook%.Add%("GRM_DoorAccessOverride", "GRM_HousingSearch_Watch".-\n    end%)')
ok(watch ~= nil, "наблюдатель за дверьми найден")
ok(watch and watch:find("Ничего не возвращаем", 1, true) ~= nil,
   "и явно документировано, что он ничего не возвращает")
ok(watch and watch:find("return true", 1, true) == nil
        and watch:find("return false", 1, true) == nil,
   "наблюдатель не возвращает решений — не может открыть опечатанное жильё")

-- Проверяем живьём: опечатанная квартира остаётся закрытой.
reset()
flat.sealed = true
WDATA.warrants = {}
local allowed = HS.CanEnter(cop, flat)
ok(allowed == false, "опечатанная квартира закрыта, наблюдатель это не изменил")
ok(flat.entryLog == nil or #flat.entryLog == 0,
   "и запись о входе не появилась — входа-то не было")
flat.sealed = false

-- Не-жильё модуль не трогает.
reset()
local shop = { id="s1", type="shop", doors={"d9"}, ownerType="none" }
GRM.Property.Records.s1 = shop
runAll("GRM_DoorAccessOverride", cop, mkDoor("d9"))
ok(shop.entryLog == nil, "в магазине журнала входов нет — это только для жилья")
GRM.Property.Records.s1 = nil

-----------------------------------------------------------------------
print("\n=== 11. ИНТЕГРАЦИЯ ===")
-----------------------------------------------------------------------
local prop = assert(io.open("lua/autorun/sh_grm_property.lua")):read("*a")
ok(prop:find("r.entryLog", 1, true) ~= nil,
   "entryLog объявлен в Normalize — журнал не сотрётся при сохранении")
ok(prop:find("r._entrySeen=nil", 1, true) ~= nil,
   "а сессионная защита от повторов в файл не пишется")

local hub = assert(io.open("lua/autorun/sh_grm_admin_hub.lua")):read("*a")
ok(hub:find("Жильё: журнал входов", 1, true) ~= nil, "журнал есть в админ-хабе")

ok(#AUDIT > 0, "события пишутся и в общий аудит для админов")
local found = false
for _, a in ipairs(AUDIT) do
    if a.cat == "housing" and tostring(a.act):find("entry.") then found = true break end
end
ok(found, "с доменом housing и действием entry.*")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
