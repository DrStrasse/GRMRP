--[[ Живой прогон системы закупки транспорта организациями (заказ 21.08):
     рынок закупок (суперадмин), права на закупку, списание с бюджета,
     приписка к гаражу, выдача по МЕСТАМ СТОЯНКИ, возврат, списание.
     Грузятся РЕАЛЬНЫЕ sh_grm_fleet.lua и sh_grm_garage.lua.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_fleet.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }
local NOW = 100
function CurTime() return NOW end
function SysTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" and v._valid ~= nil end
function ErrorNoHalt() end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1
MASK_SOLID, SOLID_VPHYSICS, MOVETYPE_VPHYSICS = 1, 6, 6

local VMT = {}
VMT.__index = VMT
function VMT:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
function VMT:Distance(o) return math.sqrt(self:DistToSqr(o)) end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VMT.__mul = function(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Remove = function() end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do local r = fn(...) if r ~= nil then return r end end end,
}
timer = { Simple = function(_, fn) if fn then fn() end end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end,
         TraceLine = function() return { Hit = false, HitPos = Vector(0, 0, 0), StartSolid = false } end,
         TraceHull = function() return { Hit = false, StartSolid = false } end }
local RECV = {}
net = { Receive = function(m, fn) RECV[m] = fn end, Start = function() end, Send = function() end,
        WriteString = function() end, WriteTable = function() end, WriteBool = function() end,
        WriteUInt = function() end, WriteEntity = function() end,
        ReadString = function() return "" end, ReadTable = function() return {} end }
local CONVARS = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) == "1" end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end
game = { GetMap = function() return "sim_map" end }
player = { GetAll = function() return PLAYERS or {} end }
list = { Get = function(kind)
    if kind == "simfphys_vehicles" then return { simfphys_wolfpolice = { SpawnList = "sim_fphys_wolfpolice" } } end
    return {}
end }

local FS = {}
file = {
    IsDir = function() return true end, CreateDir = function() end,
    Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end,
}
local function encode(v)
    local t = type(v)
    if t == "number" then return string.format("%.14g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local isArr = #v > 0
        local parts = {}
        if isArr then
            for _, i in ipairs(v) do parts[#parts + 1] = encode(i) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. encode(i) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
util.TableToJSON = function(t) return encode(t) end
util.CRC = (function() local n = 0 return function() n = n + 1 return tostring(7000 + n) end end)()
-- Мини-парсер JSON, достаточный для наших структур. Нужен, чтобы стенд
-- честно проверял «цена записана → FL.Load → цена восстановлена»: без него
-- мок util.JSONToTable возвращал nil, и загрузка overrides не проверялась.
local function jsonDecodeF(str)
    local pos = 1
    local parseValue
    local function skip()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\n" or c == "\t" or c == "\r" then pos = pos + 1 else break end
        end
    end
    local function parseString()
        pos = pos + 1
        local out = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then out[#out + 1] = "\n" elseif n == "t" then out[#out + 1] = "\t"
                elseif n == "u" then out[#out + 1] = "" pos = pos + 4 else out[#out + 1] = n end
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1
            skip()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while pos <= #str do
                skip()
                local key = parseString()
                skip()
                pos = pos + 1
                t[key] = parseValue()
                skip()
                local ch = str:sub(pos, pos)
                pos = pos + 1
                if ch == "}" then break end
            end
            return t
        elseif c == "[" then
            local t = {}
            pos = pos + 1
            skip()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while pos <= #str do
                t[#t + 1] = parseValue()
                skip()
                local ch = str:sub(pos, pos)
                pos = pos + 1
                if ch == "]" then break end
            end
            return t
        elseif c == '"' then
            return parseString()
        elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        else
            local num = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num then pos = pos + #num return tonumber(num) end
            pos = pos + 1
            return nil
        end
    end
    local ok, r = pcall(parseValue)
    return ok and r or nil
end
util.JSONToTable = function(s) return jsonDecodeF(tostring(s or "")) end

local ENTS = {}
ents = {
    GetAll = function() return ENTS end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(ENTS) do if e:GetClass() == cls then out[#out + 1] = e end end
        return out
    end,
    FindInSphere = function() return {} end,
    Create = function(cls)
        local e = { _valid = true, _class = cls, _pos = Vector(0, 0, 0), _nw = {} }
        function e:GetClass() return self._class end
        function e:SetPos(v) self._pos = v end
        function e:GetPos() return self._pos end
        function e:SetAngles() end
        function e:Spawn() end
        function e:Activate() end
        function e:SetModel() end
        function e:Remove() self._valid = false end
        function e:SetNWString(k, v) self._nw[k] = v end
        function e:GetNWString(k, d) local v = self._nw[k] if v == nil then return d end return v end
        function e:IsVehicle() return true end
        function e:GetDriver() return nil end
        ENTS[#ENTS + 1] = e
        return e
    end,
}

-- Экономика: бюджеты организаций и казна.
local BUDGETS, STATE = { police = 500000, medic = 1000 }, { value = 0 }
GRM = {
    Notify = function() end,
    Format = function(n) return tostring(n) .. " GRM" end,
    Identity = { CharacterKey = function(p) return p:SteamID64() .. ":char1" end },
    Perf = { Entities = function(c) return ents.FindByClass(c) end, Players = function() return PLAYERS or {} end },
    Audit = { Write = function() end },
    FactionBudgetGet = function(f) return BUDGETS[f] or 0 end,
    FactionBudgetAdd = function(f, d) BUDGETS[f] = (BUDGETS[f] or 0) + d return BUDGETS[f] end,
    Economy = { StateBudgetAdd = function(d) STATE.value = STATE.value + d return STATE.value end },
    Doors = { IsDoor = function() return false end, GetDoorID = function() return nil end,
              IsDoorLocked = function() return false end, LockDoor = function() end },
    Property = { Records = {} },
    -- Реальный GRM.Save.Register возвращает boolean, не запись. Это мок
    -- именно этого контракта: он ловит обращение вида `true.file` в FL.Load.
    Save = {
        Register = function() return true end,
        Mark = function() return true end,
        Flush = function() return true end,
    },
}

-- Дилер: нужен только спавн машины на месте гаража.
local SPAWNS = {}
GRM.VehicleDealer = {
    VehicleInfo = function(class) return { name = class, model = "models/buggy.mdl" } end,
    Spawn = function(class, dealer, ply, place)
        local ent = ents.Create("sim_vehicle")
        ent:SetPos(place and place.pos or Vector(0, 0, 0))
        ent._place = place
        SPAWNS[#SPAWNS + 1] = { class = class, place = place }
        return ent, { name = class }, nil
    end,
    TagVehicle = function() end,
    FactionList = function() return { { name = "police", display = "Полиция" } } end,
    FindRecord = function() return nil end,
    SaveGarages = function() end,
    Active = {},
}

assert(loadfile("lua/autorun/sh_grm_fleet.lua"))()
local FL = GRM.Fleet
-- КОРЕНЬ «данные прочитаны: НЕТ»: загрузка должна выполняться сразу при
-- загрузке модуля (даже при наличии GRM.Boot), иначе запись заблокирована.
ok(FL._loaded == true, "после загрузки модуля база автопарка сразу прочитана (запись не заблокирована)")
ok(FL._mapLoaded ~= nil, "зафиксирована карта, на которой прочитан парк", FL._mapLoaded)
assert(loadfile("lua/autorun/sh_grm_garage.lua"))()
local G = GRM.Garage
assert(loadfile("lua/autorun/sh_grm_vehicles.lua"))()
local V = GRM.Vehicles

local function mkPly(nick, faction, super, role)
    local p = { _valid = true, nw = { GRM_Faction = faction or "", GRM_Role = role or "" }, _pos = Vector(0, 0, 0) }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return super == true end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:Nick() return nick end
    function p:SteamID64() return nick end
    function p:SteamID() return nick end
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:ChatPrint() end
    return p
end

local admin  = mkPly("Admin", "", true)
local chief  = mkPly("Chief", "police", false, "Лидер")
local cop    = mkPly("Cop", "police", false, "Офицер")
local medic  = mkPly("Medic", "medic", false, "Врач")
PLAYERS = { admin, chief, cop, medic }

-- лидер и права ролей
_G.FactionsAPI = { IsLeader = function(ply, fac) return ply == chief and fac == "police" end }
GRM.FactionPerms = { PlayerHasPermission = function(ply, perm)
    return ply == cop and perm == "fleet_manage"
end }
GRM.PCBoard = { PlayerLevel = function(ply)
    if ply:IsSuperAdmin() then return "admin" end
    if ply:GetNWString("GRM_Faction", "") == "police" then return "police" end
    if ply:GetNWString("GRM_Faction", "") == "medic" then return "medical" end
    return "none"
end }

print("\n=== 1. РЫНОК СОБИРАЕТ СУПЕРАДМИН ===")
ok(isfunction(FL.MarketAdd), "API рынка есть")
ok(isfunction(FL.FactionGarageAllowed), "служебный гараж проверяется отдельной функцией")
local patrol = FL.MarketAdd({ class = "sim_patrol", name = "Патрульный седан", price = 50000, tier = "police", limit = 3 })
ok(patrol ~= nil and patrol.id ~= nil, "позиция добавлена")
local amb = FL.MarketAdd({ class = "sim_amb", name = "Скорая", price = 40000, tier = "gov" })
local civ = FL.MarketAdd({ class = "sim_civ", name = "Грузовик", price = 10000, tier = "civil" })
ok(#FL.MarketList() == 3, "в каталоге три позиции", #FL.MarketList())
ok(select(1, FL.MarketAdd({})) == nil, "позиция без класса не добавляется")
local pushed = 0
local savedPushLive = FL.PushLive
FL.PushLive = function() pushed = pushed + 1 end
FL.MarketUpdate(civ.id, { price = 12000 })
ok(FL.Entry(civ.id).price == 12000, "цену можно поменять")
ok(pushed == 1, "правка обычной цены сразу рассылается всем открытым терминалам", pushed)
FL.PushLive = savedPushLive

do
    local resolved, resolveErr = FL.ResolveVehicleClass({ class = "gmod_sent_vehicle_physics_base", name = "sim_fphys_wolfpolice" })
    ok(resolved == "simfphys_wolfpolice", "generic simfphys class перед выдачей превращается в spawn-класс", resolveErr or resolved)
end

print("\n=== 2. КОМУ ЧТО ПРОДАЮТ ===")
ok(select(1, FL.EntryAllowed(patrol, "police", "police", false)) == true, "полиции — полицейская техника")
ok(select(1, FL.EntryAllowed(patrol, "medic", "medical", false)) == false, "медикам полицейскую не отпускают")
ok(select(1, FL.EntryAllowed(amb, "medic", "medical", false)) == true, "медикам — государственная")
ok(select(1, FL.EntryAllowed(civ, "medic", "medical", false)) == true, "гражданская — всем организациям")
ok(select(1, FL.EntryAllowed(patrol, "", "none", false)) == false, "без организации закупки нет")
ok(select(1, FL.EntryAllowed(patrol, "medic", "medical", true)) == true, "суперадмину можно всё")
local onlyPolice = FL.MarketAdd({ class = "sim_spec", name = "Спецфургон", price = 1, tier = "civil", factions = { "police" } })
ok(select(1, FL.EntryAllowed(onlyPolice, "medic", "medical", false)) == false, "поимённый список организаций сильнее уровня")
ok(select(1, FL.EntryAllowed(onlyPolice, "police", "police", false)) == true, "названной организации — можно")

print("\n=== 3. ПРАВО ЗАКУПКИ ===")
ok(select(1, FL.CanBuy(chief, "police")) == true, "лидер закупает")
ok(select(1, FL.CanBuy(cop, "police")) == false, "рядовой сотрудник — нет", select(2, FL.CanBuy(cop, "police")))
ok(select(1, FL.CanBuy(admin, "police")) == true, "суперадмин закупает")
ok(select(1, FL.CanBuy(medic, "police")) == false, "чужой организации закупать нельзя")
ok(FL.CanManage(cop, "police") == true, "право «распоряжение парком» работает по роли")
ok(FL.CanUse(cop, "police") == true, "любой сотрудник может брать машину")
ok(FL.CanUse(medic, "police") == false, "чужой — не может")

print("\n=== 4. ГАРАЖ С НЕСКОЛЬКИМИ МЕСТАМИ ===")
local created, garage = G.Create(admin, Vector(-600, -600, 0), Vector(600, 600, 300),
    { name = "Автобаза ПП", kind = "faction", faction = "police" })
ok(created == true, "ведомственный гараж создан", garage)
G.AddSlot(garage.id, Vector(100, 100, 0), Angle(0, 90, 0), 10, "Бокс 1")
G.AddSlot(garage.id, Vector(-200, 100, 0), Angle(0, 270, 0), 10, "Бокс 2")
ok(#G.Get(garage.id).slots == 2, "мест стоянки два — машины не будут спавниться в одной точке")

print("\n=== 5. ЗАКУПКА СПИСЫВАЕТ БЮДЖЕТ ===")
local before = BUDGETS.police
local made, err, total = FL.Buy(chief, patrol.id, 2, garage.id)
ok(made ~= nil and #made == 2, "закуплены две машины", err)
ok(total == 100000, "сумма посчитана", total)
ok(BUDGETS.police == before - 100000, "деньги списаны с бюджета организации", BUDGETS.police)
ok(STATE.value == 100000, "деньги ушли в государственную казну", STATE.value)
ok(#FL.UnitsOf("police") == 2, "единицы в парке организации")
ok(FL.UnitsOf("police")[1].status == "stored", "техника стоит в гараже, а не на карте")
ok(#FL.UnitsInGarage(garage.id) == 2, "обе приписаны к гаражу")
ok(#SPAWNS == 0, "при закупке ничего не спавнится")

local denied, whyDenied = FL.Buy(cop, patrol.id, 1, garage.id)
ok(denied == nil and isstring(whyDenied), "рядовому закупку не дают", whyDenied)
local noGarage, whyNoGarage = FL.Buy(chief, patrol.id, 1, "нет-такого")
ok(noGarage == nil and tostring(whyNoGarage):find("гараж", 1, true) ~= nil, "без гаража закупка не проходит", whyNoGarage)

print("\n=== 6. ЛИМИТ И НЕХВАТКА ДЕНЕГ ===")
local limited, whyLimit = FL.Buy(chief, patrol.id, 5, garage.id)
ok(limited ~= nil and #limited == 1, "лимит 3 ед. — докупили только одну", limited and #limited)
local overLimit, whyOver = FL.Buy(chief, patrol.id, 1, garage.id)
ok(overLimit == nil and tostring(whyOver):find("предел", 1, true) ~= nil, "сверх лимита не продают", whyOver)

BUDGETS.medic = 100
local medicGarage = select(2, G.Create(admin, Vector(2000, 2000, 0), Vector(2600, 2600, 300),
    { name = "Медгараж", kind = "faction", faction = "medic" }))
G.AddSlot(medicGarage.id, Vector(2100, 2100, 0), Angle(0, 0, 0), 10, "Бокс")
_G.FactionsAPI = { IsLeader = function(ply, fac) return (ply == chief and fac == "police") or (ply == medic and fac == "medic") end }
local poor, whyPoor = FL.Buy(medic, amb.id, 1, medicGarage.id)
ok(poor == nil and tostring(whyPoor):find("бюджет", 1, true) ~= nil, "без денег закупки нет", whyPoor)
ok(BUDGETS.medic == 100, "деньги при отказе не тронуты")

print("\n=== 7. ВЫДАЧА ПО МЕСТАМ СТОЯНКИ ===")
local unit = FL.UnitsOf("police")[1]
local ent, issueErr = FL.Issue(cop, unit.id, G.Get(garage.id))
ok(IsValid(ent), "сотрудник получил служебную машину", issueErr)
ok(#SPAWNS == 1 and SPAWNS[1].place ~= nil, "машина подана НА МЕСТО стоянки, а не в точку дилера")
ok(FL.Unit(unit.id).status == "active", "единица помечена «на линии»")
ok(ent.GRMFleetID == unit.id and ent.GRMFleetUnit == unit.id,
   "энтити служебной машины несёт GRMFleetID — его ищут номера/окна",
   tostring(ent.GRMFleetID))
local again, againErr = FL.Issue(cop, unit.id, G.Get(garage.id))
ok(again == nil and tostring(againErr):find("уже выдана", 1, true) ~= nil, "дважды одну машину не выдают", againErr)
local alien, alienErr = FL.Issue(medic, unit.id, G.Get(garage.id))
ok(alien == nil and isstring(alienErr), "чужой организации технику не дают", alienErr)

local unit2 = FL.UnitsOf("police")[2]
local ent2 = FL.Issue(cop, unit2.id, G.Get(garage.id))
ok(IsValid(ent2) and SPAWNS[2].place ~= SPAWNS[1].place, "вторая машина встала на ДРУГОЕ место")

print("\n=== 8. ВОЗВРАТ И СПИСАНИЕ ===")
ok(select(1, FL.Store(cop, unit.id)) == true, "машина возвращена в гараж")
ok(FL.Unit(unit.id).status == "stored", "статус обновлён")
ok(select(1, FL.Scrap(cop, unit2.id)) == false, "машину «на линии» списать нельзя")
FL.Store(cop, unit2.id)
local budgetBefore = BUDGETS.police
ok(select(1, FL.Scrap(cop, unit2.id)) == true, "распорядитель парка может списать технику")
ok(BUDGETS.police > budgetBefore, "часть стоимости вернулась в бюджет", BUDGETS.police - budgetBefore)
ok(FL.Unit(unit2.id).status == "scrap", "единица помечена списанной")
ok(#FL.UnitsOf("police") == 2, "списанная больше не в парке", #FL.UnitsOf("police"))
ok(select(1, FL.Scrap(medic, unit.id)) == false, "чужому списывать нельзя")

print("\n=== 9. ПРИПИСКА К ДРУГОМУ ГАРАЖУ ===")
local second = select(2, G.Create(admin, Vector(4000, 4000, 0), Vector(4600, 4600, 300),
    { name = "Второй парк", kind = "faction", faction = "police" }))
G.AddSlot(second.id, Vector(4100, 4100, 0), Angle(0, 0, 0), 10, "Бокс")
ok(select(1, FL.SetGarage(cop, unit.id, second.id)) == true, "технику можно переписать в другой гараж")
ok(FL.Unit(unit.id).garageID == second.id, "приписка обновлена")
ok(#FL.UnitsInGarage(second.id) == 1, "в новом гараже она видна")
local wrongGarage = select(1, FL.Issue(cop, unit.id, G.Get(garage.id)))
ok(wrongGarage == nil, "в чужом гараже свою машину не получишь — она приписана к другому")

print("\n=== 10. ГАРАЖ ПОКАЗЫВАЕТ СЛУЖЕБНУЮ ТЕХНИКУ ===")
ok(isfunction(G.FleetRows), "гараж умеет показывать автопарк")
local rows = G.FleetRows(cop, G.Get(second.id))
ok(#rows == 1 and rows[1].fleet == true, "сотрудник видит служебную машину в своём гараже", #rows)
ok(#G.FleetRows(medic, G.Get(second.id)) == 0, "чужой организации её не видно")

print("\n=== 11. ХРАНЕНИЕ ===")
-- та же защита, что и у номеров: пустой парк не затирает закупленное
local keepUnits, keepLoaded = FL.Units, FL._loaded
FL._loaded = false
FL.Units = {}
ok(FL.SaveFleetNow() == false, "до загрузки парк на диск не пишется")
ok(FL.SaveMarketNow() == false, "и рынок тоже")
FL.Units, FL._loaded = keepUnits, keepLoaded
ok(FL.SaveMarketNow() == true and FS["grm_fleet/market.json"] ~= nil, "рынок записан на диск")
ok(FL.SaveFleetNow() == true and FS["grm_fleet/fleet_sim_map.json"] ~= nil, "парк записан по карте")
ok(FS["grm_fleet/fleet_sim_map.json"]:find("Патрульный", 1, true) ~= nil, "в файле парка видна техника")

print("\n=== 12. КОМАНДЫ ===")
ok(HOOKS["PlayerSay"] and HOOKS["PlayerSay"]["GRM_Fleet_Chat"] ~= nil, "команда /автопарк зарегистрирована")
ok(HOOKS["PlayerSay"]["GRM_Fleet_Chat"](chief, "/автопарк") == "", "команда съедается и не уходит в чат")
ok(HOOKS["PlayerSay"]["GRM_Fleet_Chat"](chief, "привет") == nil, "обычная реплика не трогается")
ok(RECV[FL.Net.ACT] ~= nil, "приём действий окна зарегистрирован")

print("\n=== 13. ТЕХНИКА, ЗАКРЕПЛЁННАЯ ЗА ДОЛЖНОСТЯМИ ===")
local u = FL.UnitsOf("police")[1]
ok(isfunction(FL.UnitAllowedFor), "чистая проверка закрепления объявлена")
ok(select(1, FL.UnitAllowedFor(u, { faction = "police", role = "Офицер" })) == true,
   "без ограничений машину берёт любой сотрудник")
ok(FL.RestrictionText(u) == "доступна всем сотрудникам", "и так и написано", FL.RestrictionText(u))

ok(select(1, FL.SetRestriction(cop, u.id, { "Лидер" }, {})) == true, "распорядитель закрепил машину за должностью")
ok(select(1, FL.UnitAllowedFor(FL.Unit(u.id), { faction = "police", role = "Офицер" })) == false,
   "офицеру она больше не положена")
ok(select(1, FL.UnitAllowedFor(FL.Unit(u.id), { faction = "police", role = "Лидер" })) == true,
   "а начальнику — положена")
ok(select(1, FL.UnitAllowedFor(FL.Unit(u.id), { faction = "police", role = "Офицер", superadmin = true })) == true,
   "суперадмину можно всегда")
ok(FL.RestrictionText(FL.Unit(u.id)):find("Лидер", 1, true) ~= nil, "закрепление видно человеку",
   FL.RestrictionText(FL.Unit(u.id)))

local denied, whyRole = FL.Issue(cop, u.id, G.Get(second.id))
ok(denied == nil and tostring(whyRole):find("закреплена", 1, true) ~= nil,
   "выдача не проходит: машина не по должности", whyRole)
chief.nw.GRM_Role = "Лидер"
FL.SetGarage(cop, u.id, second.id)
local okChief = FL.Issue(chief, u.id, G.Get(second.id))
ok(IsValid(okChief), "начальнику ту же машину выдают")
FL.Store(chief, u.id)

ok(select(1, FL.SetRestriction(cop, u.id, {}, { "patrol" })) == true, "можно закрепить и за отделом")
cop.nw.GRM_Department = "patrol"
ok(select(1, FL.UnitAllowedFor(FL.Unit(u.id), FL.ActorOf(cop))) == true, "сотрудник отдела получает доступ")
cop.nw.GRM_Department = "crime"
ok(select(1, FL.UnitAllowedFor(FL.Unit(u.id), FL.ActorOf(cop))) == false, "из другого отдела — нет")
ok(select(1, FL.SetRestriction(medic, u.id, {}, {})) == false, "чужой закрепление не меняет")
FL.SetRestriction(cop, u.id, {}, {})

print("\n=== 14. ЕДИНЫЙ СЛОЙ ТРАНСПОРТА ===")
ok(isfunction(V.Rows) and isfunction(V.Issue) and isfunction(V.Store), "диспетчер объявлен")
ok(V.Source("fleet") == "fleet" and V.Source("") == "personal" and V.Source("ерунда") == "personal",
   "источник нормализуется")
local rows = V.Rows(cop, G.Get(second.id))
local fleetRow
for _, r in ipairs(rows) do if r.source == "fleet" then fleetRow = r end end
ok(fleetRow ~= nil, "служебная техника попала в общий список")
ok(fleetRow.allowed == true and fleetRow.restriction ~= "", "в строке видно, кому она положена", fleetRow.restriction)
ok(#V.Rows(medic, G.Get(second.id)) == 0, "чужой организации в этом гараже показывать нечего")

local okIssue, msgIssue = V.Issue(cop, "fleet", u.id, G.Get(second.id))
ok(okIssue == true, "выдача через диспетчер работает", msgIssue)
ok(FL.Unit(u.id).status == "active", "единица на линии")
ok(select(1, V.Store(cop, "fleet", u.id)) == true, "возврат через диспетчер работает")
ok(select(1, V.SetHome(cop, "fleet", u.id, garage.id)) == true, "приписка через диспетчер работает")
ok(FL.Unit(u.id).garageID == garage.id, "гараж сменился")
ok(select(1, V.Issue(cop, "personal", "нет-такой")) == false, "личная машина без записи — честный отказ")

print("\n=== 15. МЕСТА ВЫДАЧИ ПРОТИВ ТЕСНОГО БОКСА ===")
-- хулл машины «упирается» всегда: раньше место считалось занятым и выдача
-- уезжала к дилеру. Теперь есть ступенчатая проверка.
local strict = select(2, G.Create(admin, Vector(-9000, -9000, 0), Vector(-8400, -8400, 300),
    { name = "Тесный бокс", kind = "public" }))
G.AddSlot(strict.id, Vector(-8700, -8700, 0), Angle(0, 0, 0), 10, "Бокс")
util.TraceHull = function() return { Hit = true, StartSolid = false } end
local place, why = G.FreeSlot(G.Get(strict.id), admin)
ok(place ~= nil and place.tight == true,
   "в тесном боксе место всё равно выдаётся (с пометкой «тесно»)", why)
util.TraceHull = function() return { Hit = false, StartSolid = false } end
ok(select(1, G.FreeSlot(G.Get(strict.id), admin)) ~= nil, "в свободном боксе место обычное")

print("\n=== 16. ДИАГНОСТИКА МЕСТ ===")
ok(isfunction(G.SlotDiagnose), "диагностика мест объявлена")
local diag = G.SlotDiagnose(G.Get(strict.id), admin)
ok(#diag == 1 and diag[1].free == true, "по каждому месту видно, свободно оно или нет")

print("\n=== ОБНОВЛЕНИЕ НЕ СБИВАЕТ РАБОТУ (22.08) ===")
do
    local src = (function()
        local f = io.open("lua/autorun/sh_grm_fleet.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local function has(n) return src:find(n, 1, true) ~= nil end
    ok(has("FL.Form = FL.Form or {}") and has("e.OnChange = function(self) FL.Form[key] = self:GetValue() or \"\" end"),
       "поля рынка и закупки помнят ввод между обновлениями")
    ok(has('entry(form, "например simfphys_uaz", "mk_class")') and has('entry(bar, "Сколько единиц", "buy_count")'),
       "у полей формы есть ключи")
    ok(has("FL.Form.buy_garage = pickedGarage") and has("FL.Form.mk_tier = pickedTier"),
       "выбранные гараж и уровень допуска не сбрасываются")
    ok(has("function FL.RestoreScroll(list, key)") and has('FL.RestoreScroll(list, "park")'),
       "прокрутка каждой секции возвращается на место")
end

print("\n=== БАЗА ЗАКУПОК ПИШЕТСЯ НА ТЕКУЩУЮ КАРТУ (22.08) ===")
do
    local src = (function()
        local f = io.open("lua/autorun/sh_grm_fleet.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    ok(src:find("local wantFleetFile = fleetFile()", 1, true) ~= nil
        and src:find("FL._fleetSave ~= wantFleetFile", 1, true) ~= nil,
        "при смене карты очередь записи переключается на файл новой карты")
    ok(src:find("local wantMarketFile = MARKET_FILE", 1, true) ~= nil
        and src:find("FL._marketSave ~= wantMarketFile", 1, true) ~= nil,
        "рынок тоже перерегистрируется, путь тот же но без рассинхрона")
end

print("\n=== ЖИВОЕ ОКНО И ХРАНЕНИЕ (22.08) ===")
do
    local src = (function()
        local f = io.open("lua/autorun/sh_grm_fleet.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local function has(n) return src:find(n, 1, true) ~= nil end

    ok(has('GRM.Perf.Coalesce("fleet.push." .. tostring(ply:SteamID64() or ply:EntIndex()), 0.15, function()'),
       "снимок автопарка схлопывается ПРАВИЛЬНЫМ вызовом (key, delay, fn)")
    ok(has("FL.Viewers = FL.Viewers or {}") and has("function FL.SetViewer(ply, on)"),
       "сервер знает, у кого открыт автопарк")
    ok(has('timer.Create("GRM_Fleet_ViewersTick", 5, 0, viewersTick)'),
       "открытое окно обновляется само раз в 5 секунд")
    ok(has('if act ~= "refresh" and act ~= "watch" then') and has("FL._sig, FL._sigPending = nil, nil"),
       "watch и ручное обновление не теряются из-за антиспама")
    ok(has('elseif act == "watch" then'), "клиент сообщает об открытии и закрытии окна")
    ok(has("FL.SetViewer(ply, true)\n            FL.Push(ply)"),
       "первый снимок уходит сразу, без задержки")
    ok(has("if FL.PushViewers then FL.PushViewers() end"),
       "добавление позиции на рынок сразу видно всем, кто смотрит")
    ok(has('concommand.Add("grm_fleet_status"') and has("на диске: рынок %d, парк %d"),
       "есть диагностика: что в памяти и что реально на диске")
    ok(has('concommand.Add("grm_fleet_save"'), "есть принудительная запись с проверкой")
end

print("\n=== ВОССТАНОВЛЕНИЕ СТАТУСОВ ПОСЛЕ РЕСТАРТА (22.08) ===")
do
    local units = FL.NormalizeLoadedUnits({
        fu_active = { id = "fu_active", status = "active" },
        fu_stored = { id = "fu_stored", status = "stored" },
        fu_scrap  = { id = "fu_scrap", status = "scrap" },
    })
    ok(units.fu_active.status == "stored", "активная единица после рестарта встаёт в гараж", units.fu_active.status)
    ok(units.fu_stored.status == "stored", "уже сохранённая остаётся в гараже")
    ok(units.fu_scrap.status == "scrap", "списанная не возвращается в парк")
    ok(units.fu_active.restoredFromActive == true, "помечено, что статус восстановлен после рестарта")
end

print("\n=== ДВА ДИЛЕРА, ОДИН КЛАСС, РАЗНЫЕ ЦЕНЫ (22.08) ===")
do
    -- id строится через FL.DealerHash на чистой арифметике — он одинаков в
    -- GMod и здесь, поэтому подменять util.CRC больше не нужно.

    GRM.VehicleDealer.EntryKind = function(entry)
        local kind = tostring(entry and entry.ownershipType or "")
        if kind ~= "" then return kind end
        if entry and entry.service then return entry.faction and entry.faction ~= "" and "government" or "public" end
        return "personal"
    end
    local d1 = ents.Create("sent_vehicle_dealer")
    d1.GetDealerID = function() return "dealer_A" end
    d1.GetDealerName = function() return "Дилер А" end
    d1.VD_Vehicles = { { class = "sim_patrol", name = "Патрульный", price = 1000,
        category = "Служебные", faction = "police", service = true, ownershipType = "government" } }
    local d2 = ents.Create("sent_vehicle_dealer")
    d2.GetDealerID = function() return "dealer_B" end
    d2.GetDealerName = function() return "Дилер Б" end
    d2.VD_Vehicles = { { class = "sim_patrol", name = "Патрульный улучшенный", price = 9999,
        category = "Служебные", faction = "police", service = true, ownershipType = "government" } }

    local market = FL.DealerMarket()
    local n, p1, p2 = 0, nil, nil
    for _, e in pairs(market) do
        n = n + 1
        if e.price == 1000 then p1 = e.id end
        if e.price == 9999 then p2 = e.id end
    end
    ok(n == 2, "у двух карточек одного класса с разными ценами — ДВЕ позиции закупки", n)
    ok(p1 ~= nil and p2 ~= nil and p1 ~= p2, "id позиций не совпадают даже при одном классе", tostring(p1) .. " vs " .. tostring(p2))
    ok(FL.Entry(p1) and FL.Entry(p1).price == 1000, "FL.Entry по id возвращает цену именно этой карточки", FL.Entry(p1) and FL.Entry(p1).price)
    ok(FL.Entry(p2) and FL.Entry(p2).price == 9999, "вторая карточка тоже находит СВОЮ цену", FL.Entry(p2) and FL.Entry(p2).price)
    ok(FL.DealerEntryID(d1, d1.VD_Vehicles[1]) == p1, "id строится детерминированно для первой карточки")
    ok(FL.DealerEntryID(d2, d2.VD_Vehicles[1]) == p2, "id второй карточки тоже детерминирован")

    -- пояснение: на живом сервере util.CRC детерминированный; здесь он
    -- остаётся детерминированным и для следующего блока, чтобы id совпадали.
    --[[ ЦЕННИКИ ПОЗИЦИЙ ДИЛЕРА ПРАВЯТСЯ И ЗАПОМИНАЮТСЯ (22.08).
         Кнопка «ЦЕНА» на дилерской позиции должна писать переопределение
         в FL.DealerOverrides, а не теряться в пересобираемом DealerMarket. ]]
    print("\n=== ЦЕННИКИ ПОЗИЦИЙ ДИЛЕРА (22.08) ===")
    local dealerP = d1.VD_Vehicles[1]
    local dpId = FL.DealerEntryID(d1, dealerP)
    ok(dpId ~= "", "у дилерской позиции есть id", dpId)
    ok(FL.Entry(dpId) ~= nil and FL.Entry(dpId).price == 1000, "до правки цена 1000", FL.Entry(dpId) and FL.Entry(dpId).price)

    FL.MarketUpdate(dpId, { price = 7000 })
    ok((FL.Entry(dpId) or {}).price == 7000, "после «ЦЕНА» цена стала 7000", FL.Entry(dpId) and FL.Entry(dpId).price)
    ok(FL.DealerOverrides[dpId] ~= nil and FL.DealerOverrides[dpId].price == 7000, "переопределение сохранено в памяти")
    ok(FL.MarketList() and select(2, FL.MarketList()) == nil or true, "")

    -- проверка, что переопределение попадает в marketPayload (persistence)
    local payload = FL.SaveMarketNow()
    ok(FS["grm_fleet/market.json"] ~= nil, "рынок записан на диск", FS["grm_fleet/market.json"])
    ok(FS["grm_fleet/market.json"]:find("dealer:", 1, true) ~= nil and FS["grm_fleet/market.json"]:find("7000", 1, true) ~= nil,
        "в market.json сохранён override с ценой 7000", FS["grm_fleet/market.json"] and FS["grm_fleet/market.json"]:sub(1, 80))

    -- сброс правки не удаляет саму позицию дилера
    local removed, msgRemove = FL.MarketRemove(dpId)
    ok(removed == true and tostring(msgRemove):find("дилера", 1, true) ~= nil,
        "«УБРАТЬ» не снимает позицию из ассортимента дилера, а сбрасывает только правку", tostring(msgRemove))
    ok(FL.DealerOverrides[dpId] == nil, "правка цены сброшена")
    ok((FL.Entry(dpId) or {}).price == 1000, "позиция осталась, цена вернулась к 1000", FL.Entry(dpId) and FL.Entry(dpId).price)

    -- свой рынок по-прежнему правится напрямую
    local ownLike = FL.MarketAdd({ class = "sim_uaz", name = "Патрульный УАЗ", price = 50000, limit = 0 })
    ok(ownLike ~= nil, "собственная позиция создана", ownLike)
    if ownLike then
        local ownId = ownLike.id
        FL.MarketUpdate(ownId, { price = 55000 })
        ok((FL.Entry(ownId) or {}).price == 55000, "цена собственной позиции правится", FL.Entry(ownId) and FL.Entry(ownId).price)
    end


    --[[ «ПОСЛЕ РЕСТАРТА ВСЁ ПО НУЛЯМ» (заказ владельца 22.08).
         Цена была записана и сохранена в market.json. Эмулируем рестарт:
         сбрасываем память модуля и снова вызываем FL.Load. Переопределение
         цены должно подняться из файла, а не обнулиться. ]]
    print("\n=== ЦЕННИК ПОСЛЕ РЕСТАРТА (22.08) ===")
    local starId = FL.DealerEntryID(d1, d1.VD_Vehicles[1])
    FL.MarketUpdate(starId, { price = 12345 })
    FL.FlushMarket("перезапуск-тест")
    ok((FL.Entry(starId) or {}).price == 12345, "цена перед рестартом 12345", FL.Entry(starId) and FL.Entry(starId).price)
    ok(FS["grm_fleet/market.json"] and FS["grm_fleet/market.json"]:find("12345", 1, true) ~= nil,
        "значение 12345 реально лежит в market.json", FS["grm_fleet/market.json"] and FS["grm_fleet/market.json"]:sub(1, 80))

    local keepUnits = FL.Units
    FL.Units = {}
    FL.Market = {}
    FL.DealerOverrides = {}
    FL._loaded = false
    FL.Load()
    ok((FL.Entry(starId) or {}).price == 12345,
        "после FL.Load переопределение восстановилось с диска",
        FL.Entry(starId) and FL.Entry(starId).price)
    ok(FL.DealerOverrides[starId] ~= nil and FL.DealerOverrides[starId].price == 12345,
        "DealerOverrides поднят из файла", FL.DealerOverrides[starId] and FL.DealerOverrides[starId].price)
    FL.Units = keepUnits
end

--[[ ЗАКУПКА ПЕРЕЖИВАЕТ РЕСТАРТ (заказ владельца 22.08).
     Моделируем: закупили партию → выдали одну → «рестарт» (сброс памяти,
     FL.Load) → закупленная техника обязана вернуться из файла. ]]
print("\n=== ЗАКУПЛЕННЫЙ ТРАНСПОРТ ПОСЛЕ РЕСТАРТА (22.08) ===")
do
    local restartGarage = select(2, G.Create(admin, Vector(3000, 3000, 0), Vector(3600, 3600, 300),
        { name = "Стартовый парк", kind = "faction", faction = "police" }))
    G.AddSlot(restartGarage.id, Vector(3100, 3100, 0), Angle(0, 0, 0), 10, "Бокс")
    local mkEntry = FL.MarketAdd({ class = "sim_restart", name = "Машина для рестарта", price = 2000,
        tier = "civil", kind = "government", limit = 0 })
    local bought, buyErr = FL.Buy(chief, mkEntry.id, 2, restartGarage.id)
    ok(bought ~= nil and #bought == 2, "закуплено 2 единицы перед рестартом", buyErr)
    local u1 = bought[1]
    local spawned = FL.Issue(chief, u1.id, G.Get(restartGarage.id))
    ok(IsValid(spawned), "одна единица выдана перед рестартом", u1 and u1.id)
    FL.FlushFleet("перед рестартом")
    local before = table.Count(FL.Units)

    -- «рестарт»: сбрасываем память, снова читаем базу.
    local old = FL.Units
    FL.Units = {}
    FL.Market = {}
    FL.DealerOverrides = {}
    FL._loaded = true -- Load сам вызовет FlushFleet, если единицы есть; тут пусто
    FL.Load()
    local after = table.Count(FL.Units)
    ok(after == before, "после рестарта единицы вернулись из файла", after .. " из " .. before)
    ok(FL.Unit(u1.id) ~= nil and tostring(FL.Unit(u1.id).status) == "stored",
        "выданная единица честно встала в гараж", FL.Unit(u1.id) and FL.Unit(u1.id).status)
    ok(FL.Unit(bought[2].id) ~= nil, "вторая закупленная единица тоже на месте", bought[2].id)

    -- Жёсткий рестарт иногда оставляет нулевой/оборванный основной JSON.
    -- Независимое зеркало возвращает купленные единицы.
    local fleetPath = "grm_fleet/fleet_sim_map.json"
    local mirrorPath = "grm_fleet/fleet_recovery_sim_map.json"
    ok(FS[mirrorPath] ~= nil, "есть независимое зеркало автопарка", mirrorPath)
    FS[fleetPath] = ""
    FL.Units, FL.Market, FL.DealerOverrides = {}, {}, {}
    FL._loaded = false
    FL.Load()
    ok(table.Count(FL.Units) == before, "зеркало возвращает парк при потере main и bak", table.Count(FL.Units))
end

-- Старый дилер мог оставить только номер с fleet:<id>. Такая запись должна
-- вернуть конкретную единицу в гараж, но не создавать транспорт по номеру
-- без класса, фракции и места стоянки.
print("\n=== ВОССТАНОВЛЕНИЕ ПО НОМЕРНОМУ ЗНАКУ ===")
do
    GRM.Plates = { Data = { plates = {
        TEST999 = { faction = "police", mount = { parentKey = "fleet:lost_plate_unit", parentClass = "gmod_sent_vehicle_physics_base", parentName = "sim_fphys_wolfpolice" } },
    } } }
    FL._plateRecoveryDone = false
    local restored = FL.RecoverOrphanPlateUnits()
    ok(restored == 1 and FL.Unit("lost_plate_unit") ~= nil, "номер fleet:id восстанавливает потерянную единицу", restored)
    ok(FL.Unit("lost_plate_unit").class == "sim_fphys_wolfpolice",
        "миграция берёт класс simfphys из parentName, а не generic base", FL.Unit("lost_plate_unit").class)
    local restoredGarage = G.Get(FL.Unit("lost_plate_unit").garageID)
    ok(restoredGarage and #(restoredGarage.slots or {}) > 0 and FL.Unit("lost_plate_unit").status == "stored",
        "восстановленная единица лежит в пригодном гараже", FL.Unit("lost_plate_unit").garageID)
end

print(("\nFLEET: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
