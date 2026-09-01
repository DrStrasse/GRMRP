-- Симуляция сервера GMod для sh_grm_trunk.lua (Код 80)
-- Крышка/доступ по VK-владению, переносы с анти-дюп клэмпом, вес-кап,
-- сессионные багажники без владельца, персист roundtrip (reload из «диска»).
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
local H = { hooks = {}, netrecv = {}, concommands = {}, timers = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end

_G._SIM = H
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false end
table.Count = function(t) local n = 0 for k in pairs(t or {}) do n = n + 1 end return n end
table.Copy = function(t)
    local r = {}
    for k, v in pairs(t or {}) do r[k] = istable(v) and table.Copy(v) or v end
    return r
end

local VMT = {}
VMT.__index = function(self, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    if k == "Length" then return function(s) return math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z) end end
    return nil
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- «диск»: снапшот TableToJSON → чтение JSONToTable (ровно как jsonT 3-им аргументом)
local savedSnap = nil
util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) savedSnap = table.Copy(t) return "{}" end,
    JSONToTable = function(txt) if txt == "" then return nil end return table.Copy(savedSnap or {}) end,
}
local written = {}
file = { Read = function(n) return written[n] end,
         Write = function(n, txt) written[n] = txt end,
         Exists = function(n) return written[n] ~= nil end,
         IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end,
         Call = function(name, gm, ...) return hook.Run(name, ...) end }
timer = { Create = function(name, d, r, fn) if type(name) == "function" then fn = name end if fn then H.timers[tostring(name)] = fn end end,
          Simple = function(d, fn) if type(d) == "function" then d() elseif fn then fn() end end,
          Remove = function(name) H.timers[tostring(name)] = nil end }
local sphere = {}
ents = { FindInSphere = function() return sphere end, FindByClass = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return H.players or {} end, GetBySteamID = function() return nil end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "gm_test" end }
function CurTime() return 1000 end
HUD_PRINTTALK = 3

local netlog = {}
net = { Start = function(m) netlog.cur = { msg = m } end,
        WriteString = function() end, WriteUInt = function() end, WriteInt = function() end,
        WriteBool = function() end, WriteTable = function() end, WriteVector = function() end,
        WriteEntity = function() end, WriteFloat = function() end,
        ReadFloat = function() return 0 end,
        Send = function(tg) netlog.sent = netlog.sent or {} table.insert(netlog.sent, netlog.cur and netlog.cur.msg) netlog.cur = nil end,
        Broadcast = function() end, SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
local function lastMsgs(n)
    local out = {}
    local s = netlog.sent or {}
    for i = math.max(1, #s - n + 1), #s do out[#out + 1] = s[i] end
    return table.concat(out, ",")
end
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
AddCSLuaFile = function() end

-- инъекция входящих net-полей (порядок Read* = порядок fields)
local function netInject(msg, fields)
    local i = 0
    local function pop() i = i + 1 return fields[i] end
    net.ReadString = pop net.ReadUInt = pop net.ReadInt = pop
    net.ReadBool = pop net.ReadTable = pop net.ReadEntity = pop net.ReadFloat = pop
    local fn = H.netrecv[msg]
    assert(fn, "нет receiver для " .. tostring(msg))
    fn(0, H._curPly)
    return i
end

-- VK-стаб: владение и классификация транспорта
VK = VK or {}
VK.IsVehicle = function(v) return istable(v) and v._isVeh == true end
VK.GetVehicleDisplayName = function() return "Wartburg 353" end

-- фракции
local OWNER_SID, MEMBER_SID = "STEAM_0:1:111", "STEAM_0:2:222"
Factions = { ["Мэрия"] = { Members = { [MEMBER_SID] = true }, Leader = MEMBER_SID } }
_G.FactionsAPI = { GetFactionOf = function(sid) return sid == MEMBER_SID and "Мэрия" or nil end }

-- GRM-стабы
GRM = GRM or {}
local notifylog = {}
GRM.Notify = function(ply, msg) notifylog[#notifylog + 1] = tostring(msg) P("NOTIFY[" .. ply:Nick() .. "]: " .. tostring(msg)) end

-- РЕАЛЬНАЯ семантика инвентаря (копия правил sh_grm_inventory, MaxSlots=8)
GRM.Inventory = GRM.Inventory or {}
local INV = GRM.Inventory
INV.Config = { MaxSlots = 8 }
INV._defs = {
    scrap = { type = "material", weight = 2,  maxStack = 20 },
    brick = { type = "material", weight = 100, maxStack = 5 },
}
INV._byPl = {}
function INV.GetItemDef(id) return INV._defs[id] end
function INV.GetMaxStack(id) local d = INV._defs[id] return (d and d.maxStack) or 1 end
function INV.GetPlayerInv(ply)
    local sid = ply:SteamID64()
    INV._byPl[sid] = INV._byPl[sid] or { slots = {} }
    return INV._byPl[sid]
end
function INV.AddItem(ply, itemID, count)
    local inv = INV.GetPlayerInv(ply)
    local def = INV.GetItemDef(itemID)
    if not def then return count end
    local maxStack = INV.GetMaxStack(itemID)
    local remaining = count or 1
    if def.type ~= "weapon" then
        for i = 1, INV.Config.MaxSlots do
            if remaining <= 0 then break end
            local slot = inv.slots[i]
            if slot and slot.id == itemID and (slot.count or 0) < maxStack then
                local canAdd = math.min(remaining, maxStack - (slot.count or 0))
                slot.count = slot.count + canAdd
                remaining = remaining - canAdd
            end
        end
    end
    while remaining > 0 do
        local emptySlot = nil
        for i = 1, INV.Config.MaxSlots do
            if not inv.slots[i] or not inv.slots[i].id then emptySlot = i break end
        end
        if not emptySlot then break end
        local toAdd = math.min(remaining, maxStack)
        inv.slots[emptySlot] = { id = itemID, count = toAdd }
        remaining = remaining - toAdd
    end
    return remaining
end
function INV.AddWeapon(ply, cls, c1, c2)
    local inv = INV.GetPlayerInv(ply)
    for i = 1, INV.Config.MaxSlots do
        if not inv.slots[i] or not inv.slots[i].id then
            inv.slots[i] = { id = "weapon:" .. cls, count = 1, data = { class = cls, clip1 = c1 or 0, clip2 = c2 or 0 } }
            return true
        end
    end
    return false
end
function INV.RemoveFromSlot(ply, slotIdx, count)
    local inv = INV.GetPlayerInv(ply)
    local slot = inv.slots[slotIdx]
    if not slot or not slot.id then return false end
    slot.count = (slot.count or 1) - (count or 1)
    if slot.count <= 0 then inv.slots[slotIdx] = nil end
    return true
end

-- игроки
local function mkPly(nick, sid, s64, super)
    return {
        _pos = Vector(0, 0, 0), _aim = nil,
        SteamID = function() return sid end,
        SteamID64 = function() return s64 end,
        Nick = function() return nick end,
        IsSuperAdmin = function() return super end,
        IsPlayer = function() return true end,
        Alive = function() return true end,
        GetPos = function(self) return self._pos end,
        GetEyeTrace = function(self) return { Entity = self._aim, HitPos = self._pos } end,
        PrintMessage = function(_, ch, txt) P("CHAT[" .. nick .. "]: " .. tostring(txt)) end,
    }
end
local owner    = mkPly("Овнер",   OWNER_SID,  "76000000000000001", false)
local stranger = mkPly("Чужой",   "STEAM_0:9:999", "76000000000000999", false)
local member   = mkPly("Мэрский", MEMBER_SID, "76000000000000222", false)
H.players = { owner, stranger, member }

-- машины
local function mkVeh(cls, otype, osteam, fac, locked)
    local nw = { VK_Locked = locked and true or false }
    return {
        _isVeh = true, _class = cls, _pos = Vector(50, 0, 0),
        VK_OwnerType = otype, VK_OwnerSteam = osteam, VK_FactionName = fac, VK_Locked = locked and true or false,
        GetClass = function(self) return self._class end,
        GetPos = function(self) return self._pos end,
        GetVelocity = function() return Vector(0, 0, 0) end,
        GetNW2String = function(self, k, d) return nw[k] ~= nil and nw[k] or d end,
        GetNW2Bool = function(self, k, d) return nw[k] ~= nil and nw[k] or d end,
        SetNW2Bool = function(self, k, v) nw[k] = v end,
        EmitSound = function() end,
    }
end
local carMine   = mkVeh("prop_vehicle_jeep", "player", OWNER_SID, "", true)   -- моя, заблокирована
local carLocked = mkVeh("prop_vehicle_jeep", "player", "STEAM_0:8:888", "", true)  -- чужая, заблокирована
local carOpen   = mkVeh("prop_vehicle_jeep", "player", "STEAM_0:8:888", "", false) -- чужая, открыта
local carFac    = mkVeh("simfphys_truck",    "faction", "", "Мэрия", true)    -- фракционная
local carWild   = mkVeh("lvs_wheeldrive",    "", "", "", false)               -- без владельца
sphere = { carMine, carLocked, carOpen, carFac, carWild }

SERVER = true
CLIENT = false

P("=== Загрузка sh_grm_trunk.lua ===")
dofile("lua/autorun/sh_grm_trunk.lua")
local TK = GRM.Trunk
assert(TK, "модуль не поднялся")

local fails = 0
local function CHECK(name, cond)
    if cond then P("OK: " .. name) else fails = fails + 1 P("FAIL: " .. name) end
end
local function invCount(ply, id)
    local n = 0
    for _, s in pairs(INV.GetPlayerInv(ply).slots) do if s.id == id then n = n + (s.count or 1) end end
    return n
end
local function trunkCount(slots, id)
    local n = 0 for _, s in pairs(slots or {}) do if s.id == id then n = n + (s.count or 1) end end return n
end
local function storeKeyOf(veh) -- зеркало серверного storeKey
    if veh.VK_OwnerType == "player" then return "ply|" .. veh.VK_OwnerSteam .. "|" .. veh._class end
    if veh.VK_OwnerType == "faction" then return "fac|" .. veh.VK_FactionName .. "|" .. veh._class end
    return nil
end

-- 1) владелец открывает ЗАБЛОКИРОВАННУЮ свою машину (/trunk по прицелу)
H._curPly = owner
owner._pos = Vector(60, 0, 0)
owner._aim = carMine
TK.RequestToggle(owner)
CHECK("крышка открылась", carMine:GetNW2Bool("VK_TrunkOpen", false) == true)
CHECK("владелец среди зрителей", TK.Viewers[carMine] and TK.Viewers[carMine][owner] == true)
CHECK("снапшот ушёл владельцу", string.find(lastMsgs(1), "GRM_Trunk_Open") ~= nil)
CHECK("создана запись персиста", istable(TK.Store[storeKeyOf(carMine)]))

-- 2) deposit: 10 scrap из инвентаря владельца (maxStack 20, вес 2 кг)
INV.AddItem(owner, "scrap", 10)
CHECK("в инвентаре 10 scrap", invCount(owner, "scrap") == 10)
netInject("GRM_Trunk_Xfer", { carMine, true, 1, 10 })
local mSlots = TK.Store[storeKeyOf(carMine)].slots
CHECK("багажник получил 10 scrap", istable(mSlots[1]) and mSlots[1].id == "scrap" and mSlots[1].count == 10)
CHECK("инвентарь опустел", invCount(owner, "scrap") == 0)

-- 3) deposit dobивкой стака: ещё 15 → стак 20 (кап стака), остаток 5 новым слотом
INV.AddItem(owner, "scrap", 15)
netInject("GRM_Trunk_Xfer", { carMine, true, 1, 15 })
CHECK("стак добит до 20", mSlots[1].count == 20)
CHECK("остаток 5 новым слотом", istable(mSlots[2]) and mSlots[2].count == 5)
CHECK("инвентарь снова пуст", invCount(owner, "scrap") == 0)

-- 4) withdraw части: 6 обратно
netInject("GRM_Trunk_Xfer", { carMine, false, 2, 5 })
CHECK("из слота взяли 5 (осталось 0 → слот снят)", mSlots[2] == nil)
CHECK("в инвентаре 5 scrap", invCount(owner, "scrap") == 5)

-- 5) оружие: положить и забрать (поштучно, с обоймами)
INV.AddWeapon(owner, "weapon_pistol", 12, 0)
local wSlot = nil
for i, s in pairs(INV.GetPlayerInv(owner).slots) do if s.id == "weapon:weapon_pistol" then wSlot = i break end end
CHECK("пистолет в инвентаре (слот " .. tostring(wSlot) .. ")", wSlot ~= nil)
netInject("GRM_Trunk_Xfer", { carMine, true, wSlot, 1 })
local tSlot = nil
for i, s in pairs(mSlots) do if s.id == "weapon:weapon_pistol" then tSlot = i break end end
CHECK("пистолет уложен в багажник с обоймой", tSlot ~= nil and mSlots[tSlot].data and mSlots[tSlot].data.clip1 == 12)
CHECK("пистолета больше нет в инвентаре", invCount(owner, "weapon:weapon_pistol") == 0)
netInject("GRM_Trunk_Xfer", { carMine, false, tSlot, 1 })
CHECK("пистолет возвращён в инвентарь", invCount(owner, "weapon:weapon_pistol") == 1)
CHECK("слот оружия в багажнике освобождён", mSlots[tSlot] == nil)

-- 6) вес-кап: освобождаем место (забираем весь scrap: 20+5... реально стак 20), brick 100 кг
--    пустой багажник: brick влезает; в переполненный — НЕТ (120 кг лимит)
netInject("GRM_Trunk_Xfer", { carMine, false, 1, 20 })
CHECK("scrap выгружен обратно в инвентарь", invCount(owner, "scrap") >= 20 and trunkCount(mSlots, "scrap") == 0)
INV.AddItem(owner, "brick", 2)
local bSlot = nil
for i, s in pairs(INV.GetPlayerInv(owner).slots) do if s.id == "brick" then bSlot = i break end end
netInject("GRM_Trunk_Xfer", { carMine, true, bSlot, 1 })
CHECK("первый brick улёгся (100/120 кг)", trunkCount(mSlots, "brick") == 1)
bSlot = nil
for i, s in pairs(INV.GetPlayerInv(owner).slots) do if s.id == "brick" then bSlot = i break end end
netInject("GRM_Trunk_Xfer", { carMine, true, bSlot, 1 })
CHECK("второй brick ОТКЛОНЁН (перегруз 200/120)", trunkCount(mSlots, "brick") == 1 and invCount(owner, "brick") == 1)
CHECK("уведомление о перегрузе", string.find(table.concat(notifylog, "|"), "перегруз") ~= nil)
-- persist-проверка ниже использует содержимое: brick (100 кг), scrap остаётся в инвентаре

-- 7) чужой на заблокированной — отказ; на открытой — RP-кража разрешена
H._curPly = stranger
stranger._pos = Vector(60, 0, 0)
stranger._aim = carLocked
TK.RequestToggle(stranger)
CHECK("заблокированная чужая: крышка НЕ открылась", carLocked:GetNW2Bool("VK_TrunkOpen", false) == false)
CHECK("отказ озвучен", string.find(table.concat(notifylog, "|"), "Багажник недоступен") ~= nil)
stranger._aim = carOpen
TK.RequestToggle(stranger)
CHECK("разблокированная чужая: открыто (риск владельца)", carOpen:GetNW2Bool("VK_TrunkOpen", false) == true)

-- 8) фракционная: член фракции — да, чужак — нет (заблокирована)
H._curPly = member
member._pos = Vector(60, 0, 0)
member._aim = carFac
TK.RequestToggle(member)
CHECK("фракционная крышка открылась члену фракции", carFac:GetNW2Bool("VK_TrunkOpen", false) == true)
CHECK("ключ fac|Мэрия| класс создан", istable(TK.Store["fac|Мэрия|simfphys_truck"]))
stranger._aim = carFac
H._curPly = stranger
carFac:SetNW2Bool("VK_TrunkOpen", false) -- захлопнули для чистоты
TK.Viewers[carFac] = nil
TK.RequestToggle(stranger)
CHECK("чужаку на заблокированной фракционной — отказ", carFac:GetNW2Bool("VK_TrunkOpen", false) == false)

-- 9) машина без владельца: слоты только на сессию (в персист не пишутся)
H._curPly = owner
owner._aim = carWild
TK.RequestToggle(owner)
CHECK("дикая машина открылась", carWild:GetNW2Bool("VK_TrunkOpen", false) == true)
INV.AddItem(owner, "scrap", 3)
local wildInv = nil
for i, s in pairs(INV.GetPlayerInv(owner).slots) do if s.id == "scrap" then wildInv = i break end end
netInject("GRM_Trunk_Xfer", { carWild, true, wildInv, 3 })
CHECK("слоты на энтити (сессия)", istable(carWild.TK_Slots) and trunkCount(carWild.TK_Slots, "scrap") == 3)
CHECK("в TK.Store диких ключей нет", TK.Store["|lvs_wheeldrive"] == nil and TK.Store["lvs_wheeldrive"] == nil)
local storeKeys = 0 for k in pairs(TK.Store) do storeKeys = storeKeys + 1 end
CHECK("в Store ровно 3 легальные записи (моя+фрак+открытая чужая)", storeKeys == 3)

-- 10) повторный /trunk владельцем-зрителем = захлопнуть общую крышку
H._curPly = owner
owner._aim = carMine
netlog.sent = {}
TK.RequestToggle(owner)
CHECK("крышка захлопнулась", carMine:GetNW2Bool("VK_TrunkOpen", false) == false)
CHECK("зрители очищены", TK.Viewers[carMine] == nil)
CHECK("NET_CLOSE разослан", string.find(lastMsgs(1), "GRM_Trunk_Close") ~= nil)

-- 11) дальность: далеко — отказ
owner._pos = Vector(9999, 9999, 0)
carMine:SetNW2Bool("VK_TrunkOpen", false)
sphere = {} -- FindInSphere ничего не даст; прицел тоже в никуда
owner._aim = nil
TK.RequestToggle(owner)
CHECK("издалека багажник не открыть", carMine:GetNW2Bool("VK_TrunkOpen", false) == false)
owner._pos = Vector(60, 0, 0)
sphere = { carMine }

-- 12) персист roundtrip: флаш дебаунса → «рестарт» (повторный dofile) → данные на месте
if H.timers["GRM_Trunk_Debounce"] then H.timers["GRM_Trunk_Debounce"]() end
CHECK("файл grm_trunks.json записан", file.Exists("grm_trunks.json"))
TK.Store = {}
dofile("lua/autorun/sh_grm_trunk.lua")
local rSlots = TK.Store[storeKeyOf(carMine)] and TK.Store[storeKeyOf(carMine)].slots or {}
CHECK("после рестарта brick на месте", trunkCount(rSlots, "brick") == 1)
CHECK("багажник моей машины пережил рестарт", istable(TK.Store[storeKeyOf(carMine)]))
CHECK("фракционная запись пережила рестарт", istable(TK.Store["fac|Мэрия|simfphys_truck"]))

-- 13) чат-контракт: /trunk и /багажник поглощаются, чужое — мимо
owner._aim = carMine
local c1 = H.hooks["PlayerSay"]["GRM_Trunk_ChatCmds"](owner, "/багажник")
CHECK("/багажник поглощена и крышка открылась", c1 == "" and carMine:GetNW2Bool("VK_TrunkOpen", false) == true)
local c2 = H.hooks["PlayerSay"]["GRM_Trunk_ChatCmds"](owner, "/trunk")
CHECK("/trunk повтор захлопнул", c2 == "" and carMine:GetNW2Bool("VK_TrunkOpen", false) == false)
local c3 = H.hooks["PlayerSay"]["GRM_Trunk_ChatCmds"](owner, "/jobs")
CHECK("чужая команда не поглощена", c3 == nil)

P("=== ИТОГ: " .. (fails == 0 and "ВСЕ ПРОВЕРКИ ПРОШЛИ" or ("ПРОВАЛОВ: " .. tostring(fails))) .. " ===")
os.exit(fails == 0 and 0 or 1)
