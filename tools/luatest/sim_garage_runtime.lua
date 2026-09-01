--[[ Живой прогон модуля гаражей: создание зоны, места, доступ, выдача,
     уборка, привязка покупки к гаражу и строгий режим.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_garage_runtime.lua ]]
SERVER = true CLIENT = false
function AddCSLuaFile() end
NULL = { _valid = false }

local now = 100
function CurTime() return now end
function SysTime() return now end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" and v._valid ~= nil end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    setmetatable(v, { __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
                      __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
                      __mul = function(a, b) if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end return Vector(a.x * b.x, a.y * b.y, a.z * b.z) end })
    return v
end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.Copy(t) local o = {} for k, v in pairs(t) do o[k] = istable(v) and table.Copy(v) or v end return o end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1
MASK_SOLID = 1

local convars = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetBool() return tostring(self.value) == "1" end
    function cv:GetInt() return tonumber(self.value) or 0 end
    convars[name] = cv
    return cv
end

game = { GetMap = function() return "sim_map" end }

-- Файловая система в памяти.
local FS = {}
file = {
    IsDir = function() return true end,
    CreateDir = function() end,
    Write = function(p, s) FS[p] = s end,
    Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end,
}

-- Мини-JSON: хватает для круговорота таблиц в стенде.
local function encode(v)
    local t = type(v)
    if t == "number" then return tostring(v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local isArray = #v > 0
        local parts = {}
        if isArray then
            for _, item in ipairs(v) do parts[#parts + 1] = encode(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, item in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. encode(item) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
local decode
do
    local pos, str
    local function skip() while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end end
    local function value()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then
            pos = pos + 1 local out = {}
            skip()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return out end
            while true do
                skip()
                local k = value() skip() pos = pos + 1 -- ':'
                out[k] = value() skip()
                local sep = str:sub(pos, pos) pos = pos + 1
                if sep == "}" then break end
            end
            return out
        elseif c == "[" then
            pos = pos + 1 local out = {}
            skip()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return out end
            while true do
                out[#out + 1] = value() skip()
                local sep = str:sub(pos, pos) pos = pos + 1
                if sep == "]" then break end
            end
            return out
        elseif c == '"' then
            local out, i = {}, pos + 1
            while i <= #str do
                local ch = str:sub(i, i)
                if ch == "\\" then out[#out + 1] = str:sub(i + 1, i + 1) i = i + 2
                elseif ch == '"' then break
                else out[#out + 1] = ch i = i + 1 end
            end
            pos = i + 1
            return table.concat(out)
        else
            local s, e = str:find("[%-%d%.eE%+]+", pos)
            if s == pos then pos = e + 1 return tonumber(str:sub(s, e)) end
            if str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
            if str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
            pos = pos + 4 return nil
        end
    end
    decode = function(s) str, pos = s, 1 return value() end
end

util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) return encode(t) end,
    JSONToTable = function(s) return decode(s) end,
    CRC = function(s) return tostring(#tostring(s) * 7 + math.random(1000, 9999)) end,
    TraceLine = function(t) return { Hit = true, StartSolid = false, HitPos = Vector(t.start.x, t.start.y, 0) } end,
    TraceHull = function() return { Hit = false, StartSolid = false } end,
}

local entityList = {}
ents = {
    GetAll = function() return entityList end,
    FindByClass = function(cls) local out = {} for _, e in ipairs(entityList) do if e._class == cls then out[#out + 1] = e end end return out end,
    FindInSphere = function(pos, rad) local out = {} for _, e in ipairs(entityList) do if e._pos and e._pos:DistToSqr(pos) <= rad * rad then out[#out + 1] = e end end return out end,
    Create = function(cls)
        local e = { _valid = true, _class = cls, _pos = Vector(0, 0, 0), nw = {} }
        function e:SetPos(p) self._pos = p end
        function e:GetPos() return self._pos end
        function e:SetAngles() end
        function e:Spawn() end
        function e:Activate() end
        function e:Remove() self._valid = false for i, x in ipairs(entityList) do if x == self then table.remove(entityList, i) break end end end
        function e:IsVehicle() return false end
        -- габарит машины: занятость места считается пересечением коробок
        function e:WorldSpaceAABB()
            local p = self._pos or Vector(0, 0, 0)
            return Vector(p.x - 80, p.y - 45, p.z), Vector(p.x + 80, p.y + 45, p.z + 70)
        end
        function e:GetClass() return self._class end
        function e:SetTerminalID(v) self._term = v end
        function e:GetTerminalID() return self._term or "" end
        function e:SetGarageID(v) self._garage = v end
        function e:GetGarageID() return self._garage or "" end
        function e:SetGarageName(v) self._gname = v end
        function e:GetGarageName() return self._gname or "" end
        entityList[#entityList + 1] = e
        return e
    end,
}

local hooks = {}
hook = {
    Add = function(event, name, fn) hooks[event] = hooks[event] or {} hooks[event][name] = fn end,
    Run = function(event, ...) for _, fn in pairs(hooks[event] or {}) do fn(...) end end,
    Remove = function() end,
}
net = { Receive = function() end, Start = function() end, Send = function() end, WriteString = function() end,
        WriteUInt = function() end, WriteTable = function() end, WriteBool = function() end, ReadString = function() return "" end }
timer = { Simple = function(_, fn) fn() end, Create = function() end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end }

GRM = { Notify = function() end, Format = function(n) return tostring(n) .. " GRM" end }

-- Заглушки дверей и недвижимости: только то, чем пользуется гараж.
local doorsByID = {}
GRM.Doors = {
    IsDoor = function(e) return IsValid(e) and e._class == "sim_door" end,
    GetDoorID = function(e) return IsValid(e) and e._doorID or nil end,
    IsDoorLocked = function(e) return IsValid(e) and e._locked == true end,
    LockDoor = function(e, on) if IsValid(e) then e._locked = on == true end end,
}
GRM.Property = { Records = {}, GetByDoorID = function(id) return GRM.Property.ByDoor and GRM.Property.ByDoor[id] end }
local function mkDoor(id, pos)
    local e = ents.Create("sim_door")
    e._doorID = id e:SetPos(pos or Vector(0, 0, 0)) e._locked = false
    doorsByID[id] = e
    return e
end

-- Заглушка дилера: только тот слой, которым пользуется гараж.
local VD = { Active = {}, Garages = {}, MaxActive = 3 }
GRM.VehicleDealer = VD
local function key(ply) return ply._key end
function VD.GarageRecords(ply) VD.Garages[key(ply)] = VD.Garages[key(ply)] or {} return VD.Garages[key(ply)] end
function VD.SaveGarages() VD.saves = (VD.saves or 0) + 1 return true end
function VD.FindRecord(ply, id) return VD.GarageRecords(ply)[tostring(id)] end
function VD.SetRecordGarage(ply, id, gid) local r = VD.FindRecord(ply, id) if not r then return false end r.garageID = gid return true end
function VD.ActiveCount(ply) local n = 0 for _, e in pairs(VD.Active) do if IsValid(e) and e.GRMGarageOwner == ply then n = n + 1 end end return n end
function VD.IssueRecord(ply, id, place)
    local r = VD.FindRecord(ply, id)
    if not r then return nil, "Запись гаража не найдена" end
    if IsValid(VD.Active[id]) then return nil, "Транспорт уже выдан" end
    local ent = ents.Create("sim_vehicle")
    ent:SetPos(place and place.pos or Vector(0, 0, 0))
    ent.IsVehicle = function() return true end
    ent.GRMGarageID, ent.GRMGarageOwner = id, ply
    ent._place = place
    r.stored = false
    VD.Active[id] = ent
    return ent
end
function VD.StoreRecord(ply, id)
    local ent = VD.Active[tostring(id)]
    if not IsValid(ent) then return false, "Активный транспорт не найден" end
    ent:Remove() VD.Active[tostring(id)] = nil
    local r = VD.FindRecord(ply, id)
    if r then r.stored = true end
    return true, "Транспорт убран в гараж"
end

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_garage.lua"))()
local G = GRM.Garage

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(name, faction, key64)
    local p = { _valid = true, _key = key64 or (name .. ":char1"), _pos = Vector(0, 0, 0), nw = { GRM_Faction = faction or "" }, super = false }
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return self.super end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:Nick() return name end
    function p:ChatPrint() end
    function p:SteamID64() return name end
    return p
end

print("\n=== 1. СОЗДАНИЕ ЗОНЫ И МЕСТ ===")
local admin = mkPlayer("Admin") admin.super = true
local okCreate, small = G.Create(admin, Vector(0, 0, 0), Vector(50, 50, 10), { name = "Мелкий" })
ok(okCreate == false, "слишком маленькая зона отклоняется", small)

local created, rec = G.Create(admin, Vector(-600, -600, 0), Vector(600, 600, 300), { name = "Центральный", kind = "public", fee = 50 })
ok(created and istable(rec), "гараж создан")
ok(G.Get(rec.id) ~= nil and G.FindByPos(Vector(0, 0, 10)) ~= nil, "гараж находится по точке внутри зоны")
ok(G.FindByPos(Vector(5000, 0, 0)) == nil, "точка вне зоны гаражу не принадлежит")

local slotOK, slot = G.AddSlot(rec.id, Vector(100, 100, 0), Angle(0, 90, 0), 10, "Бокс 1")
ok(slotOK and slot.name == "Бокс 1", "место стоянки добавлено")
ok(select(1, G.AddSlot(rec.id, Vector(5000, 0, 0), Angle(), 10)) == false, "место вне зоны не принимается")
G.AddSlot(rec.id, Vector(-200, 100, 0), Angle(0, 270, 0), 10, "Бокс 2")
ok(#G.Get(rec.id).slots == 2, "в гараже два места")

print("\n=== 2. ХРАНЕНИЕ ===")
local saved = G.Save("test")
ok(saved, "файл гаражей записан")
G.Garages = {}
G.Load()
ok(table.Count(G.Garages) == 1 and G.Get(rec.id) and #G.Get(rec.id).slots == 2, "гараж и места читаются обратно")

print("\n=== 3. ДОСТУП ===")
local civ = mkPlayer("Civ")
ok(G.CanUse(civ, G.Get(rec.id)) == true, "городской гараж открыт всем")
local okFac = G.Update(rec.id, { kind = "faction", faction = "police" }, admin)
ok(okFac, "тип гаража меняется")
ok(G.CanUse(civ, G.Get(rec.id)) == false, "чужого в ведомственный не пускает")
local cop = mkPlayer("Cop", "police")
ok(G.CanUse(cop, G.Get(rec.id)) == true, "сотрудник организации проходит")
G.Update(rec.id, { kind = "private", owner = civ._key }, admin)
ok(G.CanUse(civ, G.Get(rec.id)) == true and G.CanUse(cop, G.Get(rec.id)) == false, "личный гараж — только владельцу")
G.Update(rec.id, { kind = "public" }, admin)

print("\n=== 4. СТОЙКА ВЫЗОВА ===")
G.AddTerminal(rec.id, Vector(300, 300, 0), Angle())
ok(#ents.FindByClass("grm_garage_terminal") == 1, "стойка появилась на карте")
local far = mkPlayer("Far") far:SetPos(Vector(5000, 5000, 0))
ok(G.GarageAt(far) == nil, "вне зоны и вдали от стойки гаража нет")
far:SetPos(Vector(300, 300, 60))
local atGarage, source = G.GarageAt(far)
ok(atGarage ~= nil, "у стойки гараж определяется", tostring(source))
G.Load()
ok(#ents.FindByClass("grm_garage_terminal") == 1, "повторная загрузка не плодит стойки")

print("\n=== 5. ВЫДАЧА И УБОРКА ===")
local drv = mkPlayer("Driver") drv:SetPos(Vector(0, 0, 10))
VD.GarageRecords(drv)["veh1"] = { id = "veh1", class = "sim_car", name = "Седан", price = 1000, stored = true }
local okRetr, msg = G.Retrieve(drv, "veh1")
ok(okRetr, "машина выдана на место", msg)
local ent = VD.Active["veh1"]
ok(IsValid(ent) and ent._place and ent._place.slot ~= nil, "выдача произошла именно на размеченное место")
ok(VD.FindRecord(drv, "veh1").garageID == rec.id, "машина без гаража закрепляется за тем, где её выдали")
local again, againMsg = G.Retrieve(drv, "veh1")
ok(again == false, "повторная выдача той же машины запрещена", againMsg)

-- Занимаем оба места: свободных не остаётся.
VD.GarageRecords(drv)["veh2"] = { id = "veh2", class = "sim_car", name = "Пикап", stored = true, garageID = rec.id }
local okSecond = G.Retrieve(drv, "veh2")
ok(okSecond, "вторая машина встаёт на второе место")
VD.GarageRecords(drv)["veh3"] = { id = "veh3", class = "sim_car", name = "Купе", stored = true, garageID = rec.id }
local okThird, thirdMsg = G.Retrieve(drv, "veh3")
ok(okThird == false and tostring(thirdMsg):find("занят"), "когда мест нет — честный отказ", thirdMsg)

local okStore, storeMsg = G.Store(drv, "veh1")
ok(okStore, "машина принимается обратно в гараж", storeMsg)
ok(VD.Active["veh1"] == nil and VD.FindRecord(drv, "veh1").stored == true, "запись помечена как «в гараже»")
local okThirdNow = G.Retrieve(drv, "veh3")
ok(okThirdNow, "освободившееся место сразу используется")

print("\n=== 6. ЧУЖОЙ ГАРАЖ И ПРИПИСКА ===")
local created2, rec2 = G.Create(admin, Vector(4000, 4000, 0), Vector(5000, 5000, 300), { name = "Северный" })
G.AddSlot(rec2.id, Vector(4500, 4500, 0), Angle(), 10, "Север 1")
ok(created2, "второй гараж создан")
drv:SetPos(Vector(4500, 4500, 10))
G.Store(drv, "veh2")
local okAlien, alienMsg = G.Retrieve(drv, "veh3")
ok(okAlien == false and tostring(alienMsg):find("стоит в гараже"), "машину из другого гаража здесь не выдают", alienMsg)
local okHome = G.SetHome(drv, "veh3")
ok(okHome and VD.FindRecord(drv, "veh3").garageID == rec2.id, "приписка к текущему гаражу работает")

print("\n=== 7. СТЫКОВКА С ДИЛЕРОМ ===")
local buyer = mkPlayer("Buyer") buyer:SetPos(Vector(0, 0, 10))
local record = { id = "veh9", class = "sim_car", name = "Новая", stored = false }
VD.GarageRecords(buyer)["veh9"] = record
local dealer = ents.Create("sent_vehicle_dealer")
dealer:SetPos(Vector(100, 0, 0))
dealer.GetDealerID = function() return "dealer_1" end
hook.Run("GRM_VehicleDealerSpawned", nil, buyer, "sim_car", record, dealer)
ok(record.garageID ~= nil and record.garageID ~= "", "покупка приписывается к гаражу")
ok(G.Get(record.garageID) ~= nil, "приписанный гараж существует")

local linked, linkMsg = G.LinkDealer(rec2.id, "dealer_1")
ok(linked, "дилер привязывается к гаражу", linkMsg)
local record2 = { id = "veh10", class = "sim_car", name = "Вторая", stored = false }
VD.GarageRecords(buyer)["veh10"] = record2
hook.Run("GRM_VehicleDealerSpawned", nil, buyer, "sim_car", record2, dealer)
ok(record2.garageID == rec2.id, "покупка у привязанного дилера уезжает в его гараж")

ok(G.DealerIssueBlocked(buyer, record2) == false, "по умолчанию дилер выдаёт как раньше")
convars["grm_garage_strict"].value = "1"
local blocked, why = G.DealerIssueBlocked(buyer, record2)
ok(blocked == true and tostring(why):find("гараже"), "строгий режим отправляет владельца в гараж", why)
convars["grm_garage_strict"].value = "0"

print("\n=== 8. УДАЛЕНИЕ ===")
local removed = G.Remove(rec2.id, admin)
ok(removed and G.Get(rec2.id) == nil, "гараж удаляется")
local slotRemoved = G.RemoveNearestSlot(Vector(100, 100, 0), 200)
ok(slotRemoved and #G.Get(rec.id).slots == 1, "место удаляется по близости")
local termRemoved = G.RemoveNearestTerminal(Vector(300, 300, 0), 200)
ok(termRemoved and #ents.FindByClass("grm_garage_terminal") == 0, "стойка удаляется вместе с записью")

-- Удаление стойки прицельно (R по самой стойке в туле).
G.AddTerminal(rec.id, Vector(320, 320, 0), Angle())
local termEnt = ents.FindByClass("grm_garage_terminal")[1]
ok(IsValid(termEnt), "стойка поставлена заново")
local byID, byIDMsg = G.RemoveTerminalByID(termEnt:GetTerminalID())
ok(byID and #ents.FindByClass("grm_garage_terminal") == 0 and #G.Get(rec.id).terminals == 0,
    "стойка удаляется по своему id — и с карты, и из записи", byIDMsg)
ok(select(1, G.RemoveTerminalByID("term_missing")) == false, "чужой id не удаляет ничего")

print("\n=== 9. ВОРОТА ГАРАЖА (ДВЕРИ) ===")
local gateA, gateB = mkDoor("door_a", Vector(120, 120, 0)), mkDoor("door_b", Vector(140, 120, 0))
local linkedA, linkMsgA = G.LinkDoor(rec.id, "door_a")
ok(linkedA, "дверь привязывается к гаражу", linkMsgA)
G.LinkDoor(rec.id, "door_b")
ok(#G.Get(rec.id).doors == 2 and G.GarageByDoorID("door_b") == G.Get(rec.id), "индекс дверей построен")
local _, other = G.Create(admin, Vector(-3000, -3000, 0), Vector(-2000, -2000, 300), { name = "Второй двор" })
local dup, dupMsg = G.LinkDoor(other.id, "door_a")
ok(dup == false and tostring(dupMsg):find("уже привязана") ~= nil, "одна дверь — один гараж", dupMsg)
G.Remove(other.id, admin)

local access = hooks["GRM_DoorAccessOverride"]["GRM_Garage_Doors"]
G.Update(rec.id, { kind = "private", owner = drv._key }, admin)
ok(select(1, access(drv, gateA)) == true, "владелец гаража открывает ворота")
ok(select(1, access(cop, gateA)) == false, "чужому ворота закрыты")
ok(gateA._locked == true and gateB._locked == true, "личный гараж запирает свои ворота")
G.Update(rec.id, { kind = "public" }, admin)
ok(gateA._locked == false, "общий гараж ворота отпирает")
ok(select(1, access(cop, gateA)) == true, "у общего гаража ворота открыты всем")

-- Дверь, принадлежащая недвижимости, остаётся её правилам.
GRM.Property.ByDoor = { door_b = { id = "prop_1" } }
ok(access(cop, gateB) == nil, "дверь объекта недвижимости гараж не перехватывает")
GRM.Property.ByDoor = nil

drv:SetPos(Vector(0, 0, 10))
local togOK, togMsg = G.ToggleDoors(drv)
ok(togOK and gateA._locked == true, "кнопка ворот закрывает их", togMsg)
local togOK2 = G.ToggleDoors(drv)
ok(togOK2 and gateA._locked == false, "повторное нажатие открывает")

print("\n=== 9.1 ВЫБОР ГАРАЖА ПРИ ПОКУПКЕ ===")
local _, garB = G.Create(admin, Vector(-4000, -4000, 0), Vector(-3000, -3000, 300), { name = "Южный парк" })
G.AddSlot(garB.id, Vector(-3500, -3500, 0), Angle(), 10, "Юг 1")
local buyer2 = mkPlayer("Buyer2") buyer2:SetPos(Vector(0, 0, 10))

local choices = G.ChoicesFor(buyer2, dealer)
ok(#choices >= 2, "игроку предлагается список гаражей", #choices)
local seesSouth = false
for _, c in ipairs(choices) do if c.id == garB.id then seesSouth = true end end
ok(seesSouth, "в списке есть дальний гараж — выбор не ограничен ближайшим")
ok(choices[1].suggested == true, "первым идёт рекомендованный (автоподбор)")

-- Покупка с явно выбранным гаражом.
local recPick = { id = "veh20", class = "sim_car", name = "Выбор", stored = false, requestedGarage = garB.id }
VD.GarageRecords(buyer2)["veh20"] = recPick
hook.Run("GRM_VehicleDealerSpawned", nil, buyer2, "sim_car", recPick, dealer)
ok(recPick.garageID == garB.id, "машина уехала именно в выбранный гараж", tostring(recPick.garageID))
ok(recPick.requestedGarage == nil, "разовый выбор не сохраняется в записи")

-- Выбор мусорного/чужого id — падаем на автоподбор, а не роняем покупку.
local recBad = { id = "veh21", class = "sim_car", name = "Мусор", stored = false, requestedGarage = "garage_nope" }
VD.GarageRecords(buyer2)["veh21"] = recBad
hook.Run("GRM_VehicleDealerSpawned", nil, buyer2, "sim_car", recBad, dealer)
ok(recBad.garageID ~= nil and recBad.garageID ~= "" and recBad.garageID ~= "garage_nope",
    "неверный выбор не ломает покупку — работает автоподбор", tostring(recBad.garageID))

-- Гараж без мест выбрать нельзя.
local _, garEmpty = G.Create(admin, Vector(7000, 7000, 0), Vector(8000, 8000, 300), { name = "Пустырь" })
ok(select(1, G.ValidateChoice(buyer2, garEmpty.id)) == nil, "гараж без размеченных мест не принимается")
G.Update(garEmpty.id, { kind = "private", owner = "someone:char1" }, admin)
G.AddSlot(garEmpty.id, Vector(7500, 7500, 0), Angle(), 10, "П1")
ok(select(1, G.ValidateChoice(buyer2, garEmpty.id)) == nil, "чужой личный гараж выбрать нельзя")
G.Remove(garEmpty.id, admin)
G.Remove(garB.id, admin)

print("\n=== 10. ГАРАЖ ВМЕСТЕ С ДОМОМ ===")
GRM.Property.Records["prop_home"] = { id = "prop_home", ownerType = "none", ownerKey = "" }
local linkedProp, linkedPropMsg = G.LinkProperty(rec.id, "prop_home")
ok(linkedProp, "гараж привязан к объекту недвижимости", linkedPropMsg)
ok(G.Get(rec.id).baseKind == "public", "исходный тип гаража запомнен")

GRM.Property.Records["prop_home"].ownerType = "character"
GRM.Property.Records["prop_home"].ownerKey = drv._key
hook.Run("GRM_PropertyOwnerChanged", GRM.Property.Records["prop_home"], "buy", drv)
ok(G.Get(rec.id).kind == "private" and G.Get(rec.id).owner == drv._key, "покупка дома делает гараж личным")
ok(G.CanUse(drv, G.Get(rec.id)) == true and G.CanUse(cop, G.Get(rec.id)) == false, "гараж отдан покупателю дома")
ok(select(1, access(drv, gateA)) == true and select(1, access(cop, gateA)) == false, "ворота дома-гаража слушают владельца")

GRM.Property.Records["prop_home"].ownerType = "faction"
GRM.Property.Records["prop_home"].ownerKey = "police"
hook.Run("GRM_PropertyOwnerChanged", GRM.Property.Records["prop_home"], "admin_update", admin)
ok(G.Get(rec.id).kind == "faction" and G.Get(rec.id).faction == "police", "ведомственный дом делает гараж ведомственным")

GRM.Property.Records["prop_home"].ownerType = "none"
GRM.Property.Records["prop_home"].ownerKey = ""
hook.Run("GRM_PropertyOwnerChanged", GRM.Property.Records["prop_home"], "release", drv)
ok(G.Get(rec.id).kind == "public" and G.Get(rec.id).owner == "", "освобождение дома возвращает гараж администрации")

local unlinked = G.LinkProperty(rec.id, "prop_home")
ok(unlinked and G.Get(rec.id).propertyID == "", "повторная привязка снимает связь")

print(("\nGARAGE RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
