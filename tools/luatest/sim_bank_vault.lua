-- sim_bank_vault.lua — функциональная проверка банковской системы (находка 178/178b):
--   • хранилище: реестр, Capacity=500000, синк госбюджета (StateBudget);
--   • паллеты НЕ пишутся в HeldCash до загрузки через E-меню (анти-двойной счёт);
--   • LoadNearCash: паллеты → HeldCash; деньги-пропы → HeldCash + госбюджет;
--   • UnloadCash: права (только CanManageEconomy/суперадмин), выгрузка с суммой,
--     ≥50к → паллеты (дробление по 100к), <50к → money.mdl; HeldCash/бюджет -;
--   • станок: печать в буфер, паллета 100.000 у станка, прокачка +50%/ур,
--     перегрев → стоп, охлаждение;
--   • процент со штрафа (statePercent) → гос.бюджет;
--   • save_entry: не-суперадмин меняет statePercent, но не систему;
--   • «Установить» в гос.бюджете — только суперадмин (статически);
--   • тул/Q-меню/PERM/модели.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
include = function(p)
  if p == "shared.lua" then return end -- shared грузится вручную (ENT-мок)
  dofile("lua/" .. p)
end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return _G.__now or 1000 end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b) return { r = r or 0, g = g or 0, b = b or 0 } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end

local VMT = {
  __index = function(t, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
  end,
  __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
  __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
  __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
  __mul = function(a, b) if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end return Vector(a.x * b, a.y * b, a.z * b) end,
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- ── мок окружения ──
local H = { hooks = {}, timers = {}, netrecv = {}, cmds = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
timer = { Create = function(n, _, _, fn) H.timers[n] = fn end, Simple = function() end }
concommand = { Add = function(n, fn) H.cmds[n] = fn end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return nil end, IsValidModel = function() return true end, TraceLine = function() return { Hit = false } end }
local FILES = {}
_G.__lastJson = nil
_G.__permBase = nil
file = { IsDir = function() return true end, CreateDir = function() end, Exists = function(p) return FILES[p] ~= nil end, Read = function(p) return FILES[p] end, Write = function(p, v) FILES[p] = v end, Find = function() return {} end }
util.TableToJSON = function(v) _G.__lastJson = v return "json" end
util.JSONToTable = function() return _G.__permBase end
os = { time = function() return 1700000000 end, date = function() return "2026-08-05" end }
game = { GetMap = function() return "rp_test" end }
player = { GetAll = function() return _G.__players or {} end }
net = {
  Start = function() end, WriteEntity = function() end, WriteString = function() end, WriteBool = function() end,
  WriteUInt = function() end, WriteTable = function() end, Send = function() end, Broadcast = function() end,
  Receive = function(n, fn) H.netrecv[n] = fn end, ReadEntity = function() return nil end, ReadString = function() return "" end,
  ReadBool = function() return false end, ReadTable = function() return {} end, ReadUInt = function() return _G.__readUInt or 0 end,
}
numpad = { Register = function() end, OnDown = function() end, OnUp = function() end, Remove = function() end, Activate = function() end, Deactivate = function() end }
duplicator = { StoreEntityModifier = function() end, RegisterEntityModifier = function() end }
_F = {}
Entity = function(idx) return _F[idx] end

local spawnedClasses = {}
GRM = {
  Notify = function() end,
  Format = function(n) return tostring(math.floor(tonumber(n) or 0)) .. " GRM" end,
  GiveMoney = function() end, TakeMoney = function() return true end, HasMoney = function() return true end,
  GetAllBalances = function() return {} end,
  Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end },
}


-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
-- ── мок энтити ──
local entClasses = {}
local EMT = {}
EMT.__index = function(t, k)
  local m = entClasses[t.__entClass]
  if m and m[k] then return m[k] end
  if k == "GetClass" then return function(s) return s.__cls end
  elseif k == "EntIndex" then return function(s) return s.__idx end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  elseif k == "GetForward" then return function() return Vector(1, 0, 0) end
  elseif k == "GetAngles" then return function() return Angle(0, 0, 0) end
  elseif k == "SetPos" then return function(s, v) s.pos = v end
  elseif k == "SetAngles" then return function() end
  elseif k == "SetModel" then return function() end
  elseif k == "SetSkin" then return function() end
  elseif k == "SetMaterial" then return function() end
  elseif k == "SetColor" then return function() end
  elseif k == "SetRenderMode" then return function() end
  elseif k == "SetLOD" then return function() end
  elseif k == "DrawShadow" then return function() end
  elseif k == "PhysicsInit" then return function() end
  elseif k == "SetMoveType" then return function() end
  elseif k == "SetSolid" then return function() end
  elseif k == "SetUseType" then return function() end
  elseif k == "SetCollisionGroup" then return function() end
  elseif k == "SetCreator" then return function() end
  elseif k == "SetOwner" then return function() end
  elseif k == "GetPhysicsObject" then return function() return { EnableMotion = function() end, Wake = function() end } end
  elseif k == "Spawn" then return function(s) spawnedClasses[s.__cls] = (spawnedClasses[s.__cls] or 0) + 1 end
  elseif k == "Activate" then return function() end
  elseif k == "Remove" then return function(s) if s.__valid ~= false and s.OnRemove then s:OnRemove() end s.__valid = false end
  elseif k == "EmitSound" then return function() end
  elseif k == "IsPlayer" then return function() return false end
  elseif k == "IsNPC" then return function() return false end
  elseif k == "IsWorld" then return function() return false end
  elseif k == "IsValid" then return function(s) return s.__valid ~= false end
  elseif k == "NextThink" then return function() end
  elseif k == "GetModel" then return function() return "models/x.mdl" end
  elseif k == "GetOwnerSID64" then return function(s) return s.ownerSID or "" end
  elseif k == "SetOwnerSID64" then return function(s, v) s.ownerSID = v end
  end
  return nil
end
local nextIdx = 1
local function mkEnt(cls)
  local e = setmetatable({ __cls = cls, __entClass = cls, __valid = true, __idx = nextIdx, nw = {} }, EMT)
  nextIdx = nextIdx + 1
  _F[e.__idx] = e
  return e
end

ents = {
  Create = function(cls)
    local e = mkEnt(cls)
    if cls == "grm_vault_cash" or cls == "grm_money_drop" then
      e.GetAmount = function() return e.__amt or 0 end
      e.SetAmount = function(_, v) e.__amt = v end
    end
    return e
  end,
  FindInSphere = function() return _G.__near or {} end,
}

-- ── мок игрока ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "IsSuperAdmin" then return function(s) return s.super == true end
  elseif k == "IsPlayer" then return function() return true end
  elseif k == "Alive" then return function() return true end
  elseif k == "Nick" then return function(s) return s.nick or "Игрок" end
  elseif k == "SteamID64" then return function(s) return s.sid64 end
  elseif k == "SteamID" then return function() return "STEAM_0:1:1" end
  elseif k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end
  end
  return nil
end
local function mkPly(super, nick)
  return setmetatable({ __valid = true, super = super == true, nick = nick or "Игрок", sid64 = super and "76561198000000001" or "76561198000000002", pos = Vector(0, 0, 0) }, PMT)
end

-- ══════════════ ЗАГРУЗКА ══════════════
dofile("lua/autorun/sh_grm_economy.lua")
local E = GRM.Economy
ok(E ~= nil and E.RegisterVault ~= nil and E.SpawnVaultCash ~= nil and E.SpawnCashAt ~= nil and E.DropCashToVault ~= nil, "economy: реестр хранилищ + спавн денег")

-- ══════════════ 1. ХРАНИЛИЩЕ ══════════════
ENT = {}
dofile("lua/entities/grm_bank_vault/shared.lua")
dofile("lua/entities/grm_bank_vault/init.lua")
entClasses["grm_bank_vault"] = {}
for k, v in pairs(ENT) do entClasses["grm_bank_vault"][k] = v end

local vault = mkEnt("grm_bank_vault")
vault:SetPos(Vector(0, 0, 0))
vault.GetCapacity = function() return vault.__cap or 500000 end
vault.SetCapacity = function(_, v) vault.__cap = v end
vault.GetHeldCash = function() return vault.__held or 0 end
vault.SetHeldCash = function(_, v) vault.__held = v end
vault.GetStateBudget = function() return vault.__sb or 0 end
vault.SetStateBudget = function(_, v) vault.__sb = v end
vault:Initialize()

ok(E.Vaults[vault:EntIndex()] == vault, "хранилище зарегистрировано в реестре")
ok(vault:GetCapacity() == 500000, "вместимость хранилища 500.000")

E.StateBudgetSet(1234567, "тест")
ok(vault:GetStateBudget() == 1234567, "дисплей хранилища обновился после StateBudgetSet (реальное время)")
E.StateBudgetAdd(5000, "печать")
ok(vault:GetStateBudget() == 1239567, "дисплей обновился после StateBudgetAdd")

-- ══════════════ 2. ПАЛЛЕТЫ: спавн НЕ пишет HeldCash (анти-двойной счёт) ══════════════
ENT = {}
dofile("lua/entities/grm_vault_cash/shared.lua")
dofile("lua/entities/grm_vault_cash/init.lua")
entClasses["grm_vault_cash"] = {}
for k, v in pairs(ENT) do entClasses["grm_vault_cash"][k] = v end

local function mkCashEnt()
  local e = mkEnt("grm_vault_cash")
  e.GetAmount = function() return e.__amt or 0 end
  e.SetAmount = function(_, v) e.__amt = v end
  e:Initialize()
  return e
end

local spawned = E.SpawnVaultCash(vault, 200000)
ok(spawned == 200000, "паллета на 200.000 заспавнена у хранилища")
ok(vault:GetHeldCash() == 0, "паллета НЕ в HeldCash до загрузки (анти-двойной счёт, находка 178b)")

-- ── LoadNearCash: загрузка паллеты ──
_G.__near = { mkCashEnt() }
_G.__near[1]:SetAmount(200000)
local bankier = mkPly(false, "Банкир")
local loaded = vault:LoadNearCash(bankier)
ok(loaded == 200000, "LoadNearCash загрузил паллету 200.000")
ok(vault:GetHeldCash() == 200000, "HeldCash = 200.000 после загрузки")
ok(_G.__near[1].__valid == false, "паллета удалена после загрузки")

-- ── вместимость 500.000 ──
_G.__near = { mkCashEnt() }
_G.__near[1]:SetAmount(400000)
loaded = vault:LoadNearCash(bankier)
ok(loaded == 300000, "вместимость: загружено только 300.000 (свободно)")
ok(vault:GetHeldCash() == 500000, "HeldCash упёрся в 500.000")
_G.__near = {}
loaded = vault:LoadNearCash(bankier)
ok(loaded == 0, "хранилище заполнено — загрузка не проходит")

-- ── деньги-проп (grm_money_drop): HeldCash + госбюджет ──
vault:SetHeldCash(0)
local md = mkEnt("grm_money_drop")
md.GetAmount = function() return md.__amt or 0 end
md.SetAmount = function(_, v) md.__amt = v end
md:SetAmount(70000)
_G.__near = { md }
local beforeLoad = E.StateBudgetGet()
loaded = vault:LoadNearCash(bankier)
ok(loaded == 70000, "деньги-проп 70.000 загружены")
ok(vault:GetHeldCash() == 70000, "HeldCash +70.000")
ok(E.StateBudgetGet() == beforeLoad + 70000, "взнос в казну: гос.бюджет +70.000")

-- ══════════════ 3. ВЫГРУЗКА (права + дробление) ══════════════
-- банкир без доступа (Factions нет → CanManageEconomy=false)
local okUn = vault:UnloadCash(bankier, 10000)
ok(okUn == false and vault:GetHeldCash() == 70000, "выгрузка без доступа отклонена (только CanManageEconomy/суперадмин)")
-- суперадмин
local admin = mkPly(true, "Владелец")
spawnedClasses = {}
local beforeUn = E.StateBudgetGet()
okUn = vault:UnloadCash(admin, 250000)
ok(okUn == true, "выгрузка 250.000 суперадмином прошла")
ok(vault:GetHeldCash() == 0, "HeldCash списан полностью (было 70к — выгружено 70к)")
ok(E.StateBudgetGet() == beforeUn - 70000, "гос.бюджет -70.000 (изъятие из казны)")
-- 70.000 ≥ 50.000 → одна паллета grm_vault_cash, money_drop не нужен
ok(spawnedClasses["grm_vault_cash"] == 1 and spawnedClasses["grm_money_drop"] == nil, "70.000 → одна паллета (≥50к), без money.mdl")

-- выгрузка с дроблением: 250.000 = 2×100.000 + 50.000
vault:SetHeldCash(250000)
spawnedClasses = {}
okUn = vault:UnloadCash(admin, 250000)
ok(okUn == true and vault:GetHeldCash() == 0, "выгрузка 250.000 списала HeldCash")
ok(spawnedClasses["grm_vault_cash"] == 3, "250.000 = 3 паллеты (100+100+50)")
ok(spawnedClasses["grm_money_drop"] == nil, "дробление без money.mdl (остаток 50к ≥ 50к)")

-- выгрузка < 50.000 → money.mdl
vault:SetHeldCash(30000)
spawnedClasses = {}
okUn = vault:UnloadCash(admin, 30000)
ok(okUn == true, "выгрузка 30.000 прошла")
ok(spawnedClasses["grm_money_drop"] == 1 and spawnedClasses["grm_vault_cash"] == nil, "30.000 < 50к → пачка money.mdl (grm_money_drop)")

-- ══════════════ 4. ПЕЧАТНЫЙ СТАНОК (буфер → паллеты 100к) ══════════════
ENT = {}
dofile("lua/entities/grm_money_press/shared.lua")
dofile("lua/entities/grm_money_press/init.lua")
entClasses["grm_money_press"] = {}
for k, v in pairs(ENT) do entClasses["grm_money_press"][k] = v end

local press = mkEnt("grm_money_press")
press:SetPos(Vector(50, 50, 0))
press.GetActive = function() return press.__active end
press.SetActive = function(_, v) press.__active = v end
press.GetBroken = function() return press.__broken end
press.SetBroken = function(_, v) press.__broken = v end
press.GetSpeedLevel = function() return press.__lvl or 0 end
press.SetSpeedLevel = function(_, v) press.__lvl = v end
press.GetHeat = function() return press.__heat or 0 end
press.SetHeat = function(_, v) press.__heat = v end
press.GetPrintInterval = function() return press.__pi or 10 end
press.SetPrintInterval = function(_, v) press.__pi = v end
press.GetPrintAmount = function() return press.__pa or 5000 end
press.SetPrintAmount = function(_, v) press.__pa = v end
press.GetTotalPrinted = function() return press.__tp or 0 end
press.SetTotalPrinted = function(_, v) press.__tp = v end
press.GetBuffer = function() return press.__buf or 0 end
press.SetBuffer = function(_, v) press.__buf = v end
press.GetHasCustomSpawn = function() return press.__customSpawn == true end
press.SetHasCustomSpawn = function(_, v) press.__customSpawn = v end
press.GetSpawnPos = function() return press.__sp or Vector(0, 0, 0) end
press.SetSpawnPos = function(_, v) press.__sp = v end
press.GetSpawnAngle = function() return press.__sa or Angle(0, 0, 0) end
press.SetSpawnAngle = function(_, v) press.__sa = v end
press.OwnerPlayer = function() return nil end
press:Initialize()
press:SetActive(true) press:SetBroken(false) press:SetSpeedLevel(0) press:SetHeat(0)
press:SetPrintInterval(10) press:SetPrintAmount(5000) press:SetTotalPrinted(0)
press:SetBuffer(0) press:SetOwnerSID64("")

ok(GRM.MoneyPress[press:EntIndex()] == press, "станок в реестре")
ok(press:AmountPerCycle() == 5000, "базовая печать 5000 GRM за цикл")
ok(press:GetPrintInterval() == 10, "цикл 10 секунд")

-- печать: бюджет +5000, буфер +5000 (паллета НЕ сразу)
spawnedClasses = {}
local beforePrint = E.StateBudgetGet()
press:PrintMoney()
ok(E.StateBudgetGet() == beforePrint + 5000, "печать добавила 5000 в гос.бюджет")
ok(press:GetBuffer() == 5000, "буфер = 5000 (паллета копится)")
ok(press:GetTotalPrinted() == 5000, "TotalPrinted = 5000")
ok(press:GetHeat() == 6, "нагрев +6 за цикл")
ok(spawnedClasses["grm_vault_cash"] == nil, "паллета ещё не спавнилась (буфер < 100к)")

-- докачиваем до 100.000 → паллета у станка
press:SetBuffer(95000)
press:PrintMoney()
ok(press:GetBuffer() == 0, "буфер обнулён после паллеты")
ok(spawnedClasses["grm_vault_cash"] == 1, "паллета на 100.000 заспавнена у станка")
ok(E.StateBudgetGet() == beforePrint + 10000, "бюджет: итого +10.000 (5000+5000)")

-- точка выдачи (находка 178d): SetSpawnPoint → паллета спавнится там
press:SetSpawnPoint(Vector(500, 500, 0), Angle(0, 90, 0))
ok(press:GetHasCustomSpawn() == true, "точка выдачи установлена (HasCustomSpawn)")
print("    debug sp=" .. tostring(press.__sp and press.__sp.x or "nil") .. "," .. tostring(press.__sp and press.__sp.y or "nil") .. " mt=" .. tostring(getmetatable(press.__sp)))
local sp = press:SpawnPos()
ok(sp.x == 500 and sp.y == 500, "SpawnPos() возвращает точку выдачи")
press:SetBuffer(95000)
spawnedClasses = {}
press:PrintMoney()
ok(press:GetBuffer() == 0 and spawnedClasses["grm_vault_cash"] == 1, "паллета спавнится в точке выдачи")
press:ClearSpawnPoint()
ok(press:GetHasCustomSpawn() == false, "точка выдачи сброшена (ClearSpawnPoint)")
local sp2 = press:SpawnPos()
ok(sp2.x == 110 and sp2.y == 50, "после сброса паллеты снова у станка (default forward: pos+forward*60)")

-- прокачка скорости: ур.1 → 7500
press:PressUpgrade(admin)
ok(press:GetSpeedLevel() == 1 and press:GetPrintAmount() == 7500, "прокачка: ур.1 = 7500 GRM/цикл")

-- перегрев → остановка
press:SetHeat(100)
press:Think()
ok(press:GetActive() == false, "перегрев → станок остановлен")

-- охлаждение
press:PressCool(admin)
ok(press:GetHeat() == 0, "охлаждение сбросило нагрев")
press:SetActive(true)
ok(press:GetActive() == true, "после охлаждения можно запустить")

-- ══════════════ 5. ПРОЦЕНТ СО ШТРАФА ══════════════
Factions = { Polizei = { Members = { ["STEAM_0:1:1"] = { Role = "Officer" } }, Leader = "STEAM_0:1:1", Roles = { "Officer" }, Departments = {} } }
local e = E._dev_entry and E._dev_entry("Polizei") or nil
ok(e ~= nil, "entry('Polizei') доступен")
e.finePerms.statePercent = 20
e.finePerms.enabled = true
e.finePerms.ownFaction = true

local target = mkPly(false, "Штрафуемый")
local issuer = mkPly(false, "Полицейский")
GRM.GetBalance = function() return 10000 end
local taken = 0
GRM.TakeMoney = function(_, amt) taken = amt return true end
local facAdded = 0
GRM.FactionBudgetAdd = function(_, amt) facAdded = amt end
local beforeFine = E.StateBudgetGet()
local okFine, issued = E.Fine(issuer, target, 1000, "нарушение")
ok(okFine == true and issued == 1000, "штраф 1000 выписан")
ok(facAdded == 800, "80% штрафа (800) ушло в бюджет фракции")
ok(E.StateBudgetGet() == beforeFine + 200, "20% штрафа (200) ушло в гос.бюджет (процент)")

-- ══════════════ 6. save_entry: statePercent от всех, система — суперадмин ══════════════
local econCode = assert(io.open("lua/autorun/sh_grm_economy.lua", "rb")):read("*a")
ok(econCode:find('fp.statePercent = math.Clamp(math.floor(tonumber(a.fine.statePercent) or (fp.statePercent or 0)), 0, 100)', 1, true) ~= nil, "сервер: statePercent сохраняется от всех с доступом")
ok(econCode:find('if ply:IsSuperAdmin() then', 1, true) ~= nil, "сервер: система штрафов — суперадмин")

-- ══════════════ 7. «Установить» — только суперадмин ══════════════
ok(econCode:find('«Установить» гос.бюджет — только суперадмин', 1, true) ~= nil, "клиент: ограничение «Установить»")
ok(econCode:find('if isSuper then', 1, true) ~= nil, "клиент: isSuper ветка для «Установить»")

-- ══════════════ 8. ХРАНИЛИЩЕ: меню Загрузить/Выгрузить (клиент, статически) ══════════════
local vcl = assert(io.open("lua/entities/grm_bank_vault/cl_init.lua", "rb")):read("*a")
ok(vcl:find('ЗАГРУЗИТЬ', 1, true) ~= nil and vcl:find('ВЫГРУЗИТЬ', 1, true) ~= nil, "клиент: кнопки Загрузить/Выгрузить")
ok(vcl:find('Derma_StringRequest', 1, true) ~= nil, "клиент: выгрузка с указанием суммы")
ok(vcl:find('d.canManage', 1, true) ~= nil, "клиент: выгрузка видна только с доступом")
local vin = assert(io.open("lua/entities/grm_bank_vault/init.lua", "rb")):read("*a")
ok(vin:find('LoadNearCash', 1, true) ~= nil and vin:find('grm_money_drop', 1, true) ~= nil, "сервер: загрузка паллет и денег-пропов")
ok(vin:find('UnloadCash', 1, true) ~= nil and vin:find('CanManage', 1, true) ~= nil, "сервер: выгрузка с правами")
-- находка 178e: /permadd сохраняет запас хранилища
ok(vin:find('PermData.Extract["grm_bank_vault"]', 1, true) ~= nil and vin:find('PermData.Apply["grm_bank_vault"]', 1, true) ~= nil, "перм: хранилище сохраняет HeldCash/Capacity (находка 178e)")
ok(vin:find('held = math.floor(ent:GetHeldCash() or 0)', 1, true) ~= nil, "перм: хранилище Extract пишет HeldCash")

-- ══════════════ 9. ТУЛ + Q-МЕНЮ + PERM + МОДЕЛИ ══════════════
local tool = assert(io.open("lua/weapons/gmod_tool/stools/grm_bank_tool.lua", "rb")):read("*a")
ok(tool:find('TOOL.Name = "#tool.grm_bank_tool.name"', 1, true) ~= nil, "тул grm_bank_tool существует")
ok(tool:find('spawnpoint', 1, true) ~= nil and tool:find('SetSpawnPoint', 1, true) ~= nil, "тул: режим «Точка выдачи» (находка 178d)")
ok(tool:find('ClearSpawnPoint', 1, true) ~= nil, "тул: R сбрасывает точку")
ok(tool:find('grm_bank_vault', 1, true) ~= nil and tool:find('grm_money_press', 1, true) ~= nil and tool:find('grm_money_press_terminal', 1, true) ~= nil, "тул: все три типа")
ok(tool:find('CanManageEconomy', 1, true) ~= nil, "тул: права CanManageEconomy")
local q = assert(io.open("lua/autorun/sh_grm_qmenu.lua", "rb")):read("*a")
ok(q:find('grm_bank_tool', 1, true) ~= nil, "Q-меню: банковский тул")
local perm = assert(io.open("lua/autorun/sh_grm_perm_entities.lua", "rb")):read("*a")
ok(perm:find('grm_bank_vault', 1, true) ~= nil and perm:find('grm_money_press', 1, true) ~= nil and perm:find('grm_money_press_terminal', 1, true) ~= nil, "PERM_CLASSES: все три класса")

local vsh = assert(io.open("lua/entities/grm_bank_vault/shared.lua", "rb")):read("*a")
ok(vsh:find('ground_locker_small.mdl', 1, true) ~= nil, "хранилище: модель ground_locker_small.mdl")
local pin2 = assert(io.open("lua/entities/grm_money_press/init.lua", "rb")):read("*a")
ok(pin2:find('PermData.Extract["grm_money_press"]', 1, true) ~= nil and pin2:find('PermData.Apply["grm_money_press"]', 1, true) ~= nil, "перм: станок переживает рестарт (находка 178d/178e)")
ok(pin2:find('speed = math.floor(ent:GetSpeedLevel() or 0)', 1, true) ~= nil and pin2:find('buffer = math.floor(ent:GetBuffer() or 0)', 1, true) ~= nil and pin2:find('printed = math.floor(ent:GetTotalPrinted() or 0)', 1, true) ~= nil, "перм: станок сохраняет скорость/буфер/статистику (находка 178e)")
ok(pin2:find('ent:SetPrintAmount(ent:AmountPerCycle())', 1, true) ~= nil, "перм: после восстановления скорости обновляется сумма цикла")
local psh = assert(io.open("lua/entities/grm_money_press/shared.lua", "rb")):read("*a")
ok(psh:find('hatch_frame.mdl', 1, true) ~= nil, "станок: модель hatch_frame.mdl")
ok(psh:find('BaseAmount    = 5000', 1, true) ~= nil and psh:find('BaseInterval  = 10', 1, true) ~= nil, "станок: 5000 GRM / 10 сек")
ok(psh:find('BasePalletMax = 100000', 1, true) ~= nil, "станок: паллета максимум 100.000")
local tsh = assert(io.open("lua/entities/grm_money_press_terminal/shared.lua", "rb")):read("*a")
ok(tsh:find('holo_wall_unit.mdl', 1, true) ~= nil, "терминал: модель holo_wall_unit.mdl")
local csh = assert(io.open("lua/entities/grm_vault_cash/shared.lua", "rb")):read("*a")
ok(csh:find('moneypalleta.mdl', 1, true) ~= nil, "паллета: модель moneypalleta.mdl")

-- Находка 178c: 3D2D-дисплеи на ЛИЦЕВОЙ стороне модели (не биллборд сверху)
local vcash = assert(io.open("lua/entities/grm_vault_cash/init.lua", "rb")):read("*a")
ok(vcash:find('loot_bag', 1, true) ~= nil and vcash:find('LootBagAdd', 1, true) ~= nil, "паллета: ветка сумки ограбления (поэтапный сбор, находка 178f)")
ok(vcash:find('EnableMotion(false)', 1, true) ~= nil, "паллета: неподвижна (не выбрасывается, находка 178f)")
local econ2 = assert(io.open("lua/autorun/sh_grm_economy.lua", "rb")):read("*a")
ok(econ2:find('SettleCashPos', 1, true) ~= nil, "economy: укладчик точки спавна денег (находка 178f)")
local vcl2 = assert(io.open("lua/entities/grm_bank_vault/cl_init.lua", "rb")):read("*a")
ok(vcl2:find("AngleEx(self:GetForward())", 1, true) ~= nil, "хранилище: дисплей на лицевой стороне (AngleEx GetForward, находка 178c)")
ok(vcl2:find("EyeAngles().y - 90", 1, true) == nil, "хранилище: нет биллборда-надписи над моделью")
local pcl = assert(io.open("lua/entities/grm_money_press/cl_init.lua", "rb")):read("*a")
ok(pcl:find("AngleEx(self:GetForward())", 1, true) ~= nil, "станок: дисплей на лицевой стороне (AngleEx GetForward, находка 178c)")
ok(pcl:find("EyeAngles().y - 90", 1, true) == nil, "станок: нет биллборда-надписи над моделью")

-- ══════════════ 10. UpdateEntry: автообновление перм-записи (находка 179d) ══════════════
-- грузим перм-модуль (нужен мок ents.FindByClass и пр.)
local realEmit = entClasses
-- заглушки для perm-модуля
local permEnts = { GetAll = function() return {} end }
local oldPly = ply
-- перм-база: запись с data.held=0 (как при /permadd ДО загрузки денег)
_G.__permBase = { { map = "rp_test", class = "grm_bank_vault", pos = { x = 0, y = 0, z = 0 }, data = { held = 0, capacity = 500000 } } }
FILES["grm_perm_entities.json"] = "json"
-- грузим модуль пермов (его concommand не трогаем)
local oldCon = concommand
concommand = { Add = function() end }
pcall(dofile, "lua/autorun/sh_grm_perm_entities.lua")
concommand = oldCon
-- загружаем деньги и проверяем, что UpdateEntry обновил запись
vault:SetHeldCash(250000)
-- перехватим timer.Simple, чтобы выполнить отложенное обновление
local deferred = {}
local oldTimerSimple = timer.Simple
timer.Simple = function(_, fn) deferred[#deferred + 1] = fn end
local okUpd = GRM.PermData.UpdateEntry and GRM.PermData.UpdateEntry(vault)
ok(okUpd == true, "UpdateEntry вызван (дебаунс принял)")
ok(#deferred == 1, "UpdateEntry запланировал отложенное обновление")
deferred[1]() -- выполняем
timer.Simple = oldTimerSimple
-- проверяем, что сохранённая запись содержит обновлённый held
local saved = _G.__lastJson or {}
local rec = saved[1]
ok(rec and rec.data and rec.data.held == 250000, "перм-запись обновлена: held = 250.000 (находка 179d)")

print(string.format("sim_bank_vault: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
