--[[ Живой прогон замков дверей (заказ 21.08: «двери автоблокируются через
     6-10 секунд после их открытия суперадмином», проверить ключи).
     Грузится РЕАЛЬНЫЙ lua/autorun/sh_grm_doors.lua (SERVER=true) с фейковыми
     дверьми: одностворчатая, двустворчатая (две записи!), категорийная.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_door_lock_sync.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function ErrorNoHalt() end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
local NOW = 100
function CurTime() return NOW end
function SysTime() return NOW end
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4
HUD_PRINTTALK, HUD_PRINTCONSOLE = 3, 2
IN_USE = 32

local VecMT = {}
VecMT.__index = VecMT
function VecMT:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx * dx + dy * dy + dz * dz end
function VecMT:Distance(o) return math.sqrt(self:DistToSqr(o)) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

local HOOKS = {}
hook = {
    Add = function(n, id, fn) HOOKS[n] = HOOKS[n] or {} HOOKS[n][id] = fn end,
    Remove = function(n, id) if HOOKS[n] then HOOKS[n][id] = nil end end,
    Run = function() end,
    Call = function() end,
}
local TIMERS = {}
timer = {
    Create = function(n, d, r, fn) TIMERS[n] = { delay = d, fn = fn, at = NOW + d } end,
    Simple = function() end,
    Remove = function(n) TIMERS[n] = nil end,
    Exists = function(n) return TIMERS[n] ~= nil end,
    Adjust = function() end,
}
local function runTimer(name)
    local t = TIMERS[name]
    if not t then return false end
    t.fn()
    return true
end

concommand = { Add = function() end }
util = { AddNetworkString = function() end }
net = { Receive = function() end, Start = function() end, WriteString = function() end,
        WriteBool = function() end, WriteTable = function() end, WriteInt = function() end,
        Send = function() end, Broadcast = function() end, ReadString = function() return "" end }
local CVARS = {}
CreateConVar = function(name, def)
    local cv = { _v = tostring(def) }
    function cv:GetInt() return math.floor(tonumber(self._v) or 0) end
    function cv:GetFloat() return tonumber(self._v) or 0 end
    function cv:GetBool() return self._v ~= "0" and self._v ~= "" end
    function cv:GetString() return self._v end
    function cv:SetValue(v) self._v = tostring(v) end
    CVARS[name] = cv
    return cv
end
GetConVar = function(n) return CVARS[n] end
game = { GetMap = function() return "sim_map" end }
player = { GetAll = function() return {} end }
bit = { bor = function(a) return a end }

-- ── файлы ───────────────────────────────────────────────────────────
local FILES = {}
file = {
    Exists = function(p) return FILES[p] ~= nil end,
    Read = function(p) return FILES[p] end,
    Write = function(p, s) FILES[p] = s end,
    IsDir = function() return true end,
    CreateDir = function() end,
    Find = function() return {}, {} end,
    Delete = function(p) FILES[p] = nil end,
}
local function encode(v)
    local t = type(v)
    if t == "number" then return string.format("%.14g", v)
    elseif t == "string" then return string.format("%q", v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "table" then
        local isArr = true
        for k in pairs(v) do if type(k) ~= "number" then isArr = false break end end
        local parts = {}
        if isArr then
            for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, val in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(val)) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
util.TableToJSON = function(t) return encode(t) end
util.JSONToTable = function() return nil end

-- ── энтити-двери ────────────────────────────────────────────────────
local WORLD = {}
ents = {
    GetAll = function() return WORLD end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(WORLD) do if e:GetClass() == cls then out[#out + 1] = e end end
        return out
    end,
    FindInSphere = function(pos, radius)
        local out = {}
        for _, e in ipairs(WORLD) do
            if e:GetPos():Distance(pos) <= radius then out[#out + 1] = e end
        end
        return out
    end,
}

local nextMCID = 0
local function mkDoor(x, y, z)
    nextMCID = nextMCID + 1
    local id = nextMCID
    local e = { _valid = true, _nw = {}, _locked = false, _fires = {}, _pos = Vector(x, y, z) }
    function e:GetClass() return "prop_door_rotating" end
    function e:MapCreationID() return id end
    function e:EntIndex() return id + 100 end
    function e:GetPos() return self._pos end
    function e:WorldSpaceCenter() return self._pos end
    function e:GetParent() return nil end
    function e:WorldSpaceAABB()
        local p = self._pos
        return Vector(p.x - 2, p.y - 32, p.z - 48), Vector(p.x + 2, p.y + 32, p.z + 48)
    end
    function e:GetInternalVariable(k) if k == "m_bLocked" then return self._locked end end
    function e:Fire(cmd)
        self._fires[#self._fires + 1] = cmd
        if cmd == "Lock" then self._locked = true elseif cmd == "Unlock" then self._locked = false end
    end
    function e:SetNWBool(k, v) self._nw[k] = v end
    function e:GetNWBool(k, d) local v = self._nw[k] if v == nil then return d end return v end
    function e:SetNWString(k, v) self._nw[k] = v end
    function e:GetNWString(k, d) local v = self._nw[k] if v == nil then return d end return v end
    function e:SetNWFloat(k, v) self._nw[k] = v end
    WORLD[#WORLD + 1] = e
    return e
end

GRM = GRM or {}
GRM.Perf = {
    Entities = function(cls) return ents.FindByClass(cls) end,
    Players = function() return {} end,
    Throttle = function() return true end,
    Coalesce = function(_, fn) if fn then fn() end end,
    Queue = function(_, fn) if fn then fn() end end,
}
GRM.Identity = { CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end }
GRM.Notify = function() end
GRM.Audit = { Log = function() end }

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_doors.lua"))()
local D = GRM.Doors

-- игроки
local function mkPly(sid, super, faction, role)
    local p = { _valid = true }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return super == true end
    function p:IsAdmin() return super == true end
    function p:SteamID() return sid end
    function p:SteamID64() return sid end
    function p:Nick() return sid end
    function p:GetNWString(_, d) return faction or d or "" end
    function p:GetPos() return Vector(0, 0, 0) end
    function p:ChatPrint() end
    function p:PrintMessage() end
    return p
end
local root = mkPly("root", true)
local civ = mkPly("civ", false)

print("\n=== 1. ЧИСТАЯ ЛОГИКА: ЧЬЁ СОСТОЯНИЕ ПОБЕЖДАЕТ ===")
ok(isfunction(D.ResolveGroupLock), "D.ResolveGroupLock объявлена")
local resolved = D.ResolveGroupLock({ a = { locked = true, lock_at = 10 }, b = { locked = false, lock_at = 25 } })
ok(resolved == false, "побеждает САМАЯ СВЕЖАЯ запись (отпирание после запирания)")
resolved = D.ResolveGroupLock({ a = { locked = false, lock_at = 30 }, b = { locked = true, lock_at = 41 } })
ok(resolved == true, "и наоборот: свежее запирание сильнее старого отпирания")
resolved = D.ResolveGroupLock({ a = { locked = true, lock_at = 0 }, b = { locked = false, lock_at = 0 } })
ok(resolved == true, "при равной давности дверь считается запертой (безопасный выбор)")
ok(D.GroupLockInSync({ a = { locked = true }, b = { locked = true } }) == true, "согласованная группа видна")
ok(D.GroupLockInSync({ a = { locked = true }, b = { locked = false } }) == false, "рассинхрон створок виден")

print("\n=== 2. ДВУСТВОРЧАТАЯ ДВЕРЬ: ОДНО СОСТОЯНИЕ НА ОБЕ СТВОРКИ ===")
local leafA = mkDoor(0, 0, 0)
local leafB = mkDoor(0, 40, 0)      -- вторая створка: 40 юнитов, тот же класс
D.RebuildDoorIdentityCache()
ok(D.GetPartnerDoor(leafA) == leafB, "створки распознаны как пара")
local group = D.DoorGroup(leafA)
ok(#group == 2, "в группу физической двери попали оба полотна", #group)

-- обе створки — ведомственные и заперты (как после назначения владельца)
local recA = select(1, D.GetRecord(leafA))
local recB = select(1, D.GetRecord(leafB))
local idA = select(2, D.GetRecord(leafA))
local idB = select(2, D.GetRecord(leafB))
for _, r in ipairs({ recA, recB }) do
    r.owner_type = "faction" r.owner_faction = "police" r.locked = true r.lock_at = 1 r._ephemeral = nil
end
D.LockDoor(leafA, true)
ok(leafA._locked == true and leafB._locked == true, "запирание доходит до обеих створок")

-- суперадмин отпирает по одной створке
D.LockDoor(leafA, false)
ok(leafA._locked == false and leafB._locked == false, "отпирание тоже доходит до обеих створок")
ok(D.Data.doors[idA].locked == false and D.Data.doors[idB].locked == false,
   "ОБЕ записи обновлены (раньше вторая оставалась «заперта»)")
ok((tonumber(D.Data.doors[idB].lock_at) or 0) > 0, "у записи створки проставлена метка времени")

print("\n=== 3. СТОРОЖ БОЛЬШЕ НЕ ЗАПИРАЕТ ДВЕРЬ САМ ===")
local reconciler = "GRM_Doors_LockReconciler"
ok(TIMERS[reconciler] ~= nil, "сторож замков запущен")
runTimer(reconciler)
runTimer(reconciler)
runTimer(reconciler)
ok(leafA._locked == false and leafB._locked == false,
   "после трёх проходов сторожа дверь всё ещё открыта", tostring(leafA._locked) .. "/" .. tostring(leafB._locked))
ok(leafA:GetNWBool("GRM_DoorLocked", false) == false, "сетевой флаг не мигает «заперто»")

print("\n=== 4. ЛЕЧЕНИЕ СТАРОГО РАССИНХРОНА ===")
-- эмулируем данные, сохранённые прежней версией: створки разошлись
D.Data.doors[idB].locked = true
D.Data.doors[idB].lock_at = 1
runTimer(reconciler)
ok(D.Data.doors[idB].locked == false, "сторож привёл отставшую запись к свежему состоянию")
ok(leafB._locked == false, "и не стал запирать дверь по устаревшей записи")

print("\n=== 5. ЯВНАЯ АВТОБЛОКИРОВКА (ПО ЖЕЛАНИЮ, ПО УМОЛЧАНИЮ ВЫКЛЮЧЕНА) ===")
local cv = GetConVar("grm_door_autolock")
ok(cv ~= nil and cv:GetInt() == 0, "конвар grm_door_autolock есть и по умолчанию 0")
D.LockDoor(leafA, true)
D.LockDoor(leafA, false)
ok(TIMERS["GRM_Doors_AutoLock_" .. idA] == nil, "при 0 никакой автоблокировки не заводится")
cv:SetValue("8")
ok(D.AutoLockDelay() == 8, "задержка читается из конвара")
D.LockDoor(leafA, false)
ok(TIMERS["GRM_Doors_AutoLock_" .. idA] ~= nil, "с включённым конваром таймер ставится")
runTimer("GRM_Doors_AutoLock_" .. idA)
ok(leafA._locked == true and leafB._locked == true, "по истечении задержки заперлись обе створки")
cv:SetValue("0")

print("\n=== 6. ВЗЛОМ НЕ ЗАПИРАЕТСЯ ОБРАТНО ===")
cv:SetValue("8")
D.BreachDoor(leafA, root, "battering_ram")
ok(TIMERS["GRM_Doors_AutoLock_" .. idA] == nil, "выбитая дверь не встаёт на автоблокировку")
cv:SetValue("0")

print("\n=== 7. ПРАВА КЛЮЧЕЙ НА ЗАМОК ===")
ok(isfunction(D.CanToggleLock), "D.CanToggleLock объявлена")
local canRoot = select(1, D.CanToggleLock(root, leafA, true))
ok(canRoot == true, "суперадмин управляет замком")
local canCiv, whyCiv = D.CanToggleLock(civ, leafA, true)
ok(canCiv == false and isstring(whyCiv), "чужому отказ с причиной", whyCiv)

-- общественная дверь: проход всем, замок — только администрации
D.Data.categories = D.Data.categories or {}
D.Data.categories["public"] = { id = "public", name = "Общественная", factions = {}, departments = {},
    subdepartments = {}, roles = {}, everyone = true, canLock = false }
local pubDoor = mkDoor(500, 0, 0)
D.RebuildDoorIdentityCache()
local pubRec, pubId = D.GetRecord(pubDoor)
pubRec.owner_type = "category" pubRec.owner_category = "public" pubRec._ephemeral = nil
local canPub, whyPub = D.CanToggleLock(civ, pubDoor, true)
ok(canPub == false and isstring(whyPub), "на общественной двери гражданский замком не щёлкает", whyPub)
ok(select(1, D.CanToggleLock(root, pubDoor, true)) == true, "администрации общественная дверь подчиняется")

-- «дверь всегда заперта»: отпирание честно отклоняется
D.Data.categories["vault"] = { id = "vault", name = "Хранилище", factions = { "police" }, departments = {},
    subdepartments = {}, roles = {}, keepLocked = true, canLock = true }
local vaultDoor = mkDoor(900, 0, 0)
D.RebuildDoorIdentityCache()
local vRec, vId = D.GetRecord(vaultDoor)
vRec.owner_type = "category" vRec.owner_category = "vault" vRec.locked = true vRec._ephemeral = nil
local okV, stateV, forcedV = D.LockDoor(vaultDoor, false)
ok(okV == true and stateV == true and forcedV == true,
   "«всегда заперта» не отпирается и об этом СООБЩАЕТСЯ вызывающему", tostring(stateV) .. "/" .. tostring(forcedV))
ok(vaultDoor._locked == true, "замок остался закрытым")

print("\n=== 8. СОХРАНЕНИЕ ЗАМКА ===")
ok(isfunction(D.SaveDoorsNow), "немедленная запись доступна отдельно")
D.SaveDoorsNow()
local raw = FILES["grm_doors/sim_map.json"] or FILES["grm_doors/doors_sim_map.json"]
if not raw then
    for k, v in pairs(FILES) do if tostring(k):find("door", 1, true) then raw = v end end
end
ok(raw ~= nil, "файл дверей записан")
ok(raw ~= nil and raw:find("lock_at", 1, true) ~= nil, "метка времени замка попадает в файл")

print("\n=== 9. ПОДПИСЬ ДАННЫХ МЕНЮ (ПРОТИВ ПРЫЖКА СПИСКА) ===")
ok(isfunction(D.MenuSignature), "D.MenuSignature объявлена")
local catsA = { { id = "gov", name = "Государственная" }, { id = "pub", name = "Общественная" } }
local facA = { { name = "police", departments = { 1, 2 }, subdepartments = { 1 }, roles = { 1, 2, 3 } } }
local sigA = D.MenuSignature(catsA, facA)
-- галочка «фракция входит в категорию» состава категорий НЕ меняет
local catsB = { { id = "gov", name = "Государственная", factions = { "police" } }, { id = "pub", name = "Общественная" } }
ok(D.MenuSignature(catsB, facA) == sigA, "простановка галочки не меняет подпись — окно не пересобирается")
ok(D.MenuSignature(catsA, facA) == D.MenuSignature({ catsA[2], catsA[1] }, facA),
   "порядок категорий в снимке не важен")
local catsC = { { id = "gov", name = "Государственная" }, { id = "pub", name = "Общественная" }, { id = "new", name = "Гаражи" } }
ok(D.MenuSignature(catsC, facA) ~= sigA, "новая категория подпись меняет — нужна пересборка")
local facB = { { name = "police", departments = { 1, 2, 3 }, subdepartments = { 1 }, roles = { 1, 2, 3 } } }
ok(D.MenuSignature(catsA, facB) ~= sigA, "новый отдел в организации подпись меняет")

print(("\nDOOR LOCK SYNC: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
