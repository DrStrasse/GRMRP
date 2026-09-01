--[[
	GRM Augmentation Chips Tests
	Тесты системы программируемых чипов
]]

local function read(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local shared = read("lua/autorun/sh_grm_augmentation_chips.lua")
local client = read("lua/autorun/client/cl_grm_augmentation_chips.lua")

local pass, fail = 0, 0

local function has(s, n)
	return s:find(n, 1, true) ~= nil
end

local function ok(v, n)
	if v then
		pass = pass + 1
		print("  ok  " .. n)
	else
		fail = fail + 1
		print("  FAIL " .. n)
	end
end

-- Shared tests
ok(has(shared, "GRM.AugChips"), "augchips module exists")
ok(has(shared, "CHIPS.Config"), "configuration table exists")
ok(has(shared, "MaxChipsPerPlayer"), "max chips config exists")
ok(has(shared, "ImplantSuccessRate"), "implant success rate exists")
ok(has(shared, "RejectionChance"), "rejection chance exists")
ok(has(shared, "ComplicationChance"), "complication chance exists")
ok(has(shared, "Modifiers"), "modifiers config exists")
ok(has(shared, "speed"), "speed modifier exists")
ok(has(shared, "stamina"), "stamina modifier exists")
ok(has(shared, "carryWeight"), "carry weight modifier exists")
ok(has(shared, "health"), "health modifier exists")
ok(has(shared, "armor"), "armor modifier exists")
ok(has(shared, "vision"), "vision modifier exists")
ok(has(shared, "ChipCategories"), "chip categories exist")
ok(has(shared, "civilian"), "civilian category exists")
ok(has(shared, "service"), "service category exists")
ok(has(shared, "military"), "military category exists")
ok(has(shared, "experimental"), "experimental category exists")

-- Core functions
ok(has(shared, "CHIPS.PlayerChips"), "player chips storage exists")
ok(has(shared, "function CHIPS.GetPlayerChips"), "GetPlayerChips function exists")
ok(has(shared, "function CHIPS.CreateChip"), "CreateChip function exists")
ok(has(shared, "function CHIPS.RemoveChip"), "RemoveChip function exists")
ok(has(shared, "function CHIPS.ImplantChip"), "ImplantChip function exists")
ok(has(shared, "function CHIPS.ApplyChipEffects"), "ApplyChipEffects function exists")
ok(has(shared, "function CHIPS.RemoveChipEffects"), "RemoveChipEffects function exists")
ok(has(shared, "function CHIPS.SaveData"), "SaveData function exists")
ok(has(shared, "function CHIPS.LoadData"), "LoadData function exists")

-- Network
ok(has(shared, "util.AddNetworkString"), "network strings added")
ok(has(shared, "GRM_AugChip_Create"), "create network string exists")
ok(has(shared, "GRM_AugChip_Remove"), "remove network string exists")
ok(has(shared, "GRM_AugChip_Implant"), "implant network string exists")
ok(has(shared, "GRM_AugChip_GetList"), "get list network string exists")
ok(has(shared, "GRM_AugChip_SendList"), "send list network string exists")

-- Hooks
ok(has(shared, "PlayerSpawn"), "player spawn hook exists")
ok(has(shared, "grmBootStart(\"GRM_AugChips_Init\", \"normal\""), "старт подсистемы идёт через GRM.Boot (было Initialize)")
ok(has(shared, "ShutDown"), "shutdown hook exists")

-- Effects application
ok(has(shared, "ply:SetWalkSpeed"), "walk speed setting exists")
ok(has(shared, "ply:SetRunSpeed"), "run speed setting exists")
ok(has(shared, "ply:SetMaxHealth"), "max health setting exists")
ok(has(shared, "ply:SetHealth"), "health setting exists")
ok(has(shared, "ply:SetArmor"), "armor setting exists")
ok(has(shared, "ply:SetNWInt"), "network int setting exists")
ok(has(shared, "ply:SetNWFloat"), "network float setting exists")
ok(has(shared, "GRM.Inventory"), "inventory integration exists")
ok(has(shared, "GRM.Stamina"), "stamina integration exists")
ok(has(shared, "GRM_Augmentation_Update"), "augmentation update integration exists")

-- Implantation logic
ok(has(shared, "math.random()"), "random roll exists")
ok(has(shared, "ply:TakeDamage"), "damage on rejection exists")
ok(has(shared, "hasComplications"), "complications flag exists")
ok(has(shared, "implantTime"), "implant time tracking exists")

-- Client tests
ok(has(client, "GRM_COLORS"), "GRM color scheme exists")
ok(has(client, "GRMChip_Title"), "title font exists")
ok(has(client, "GRMChip_Sub"), "sub font exists")
ok(has(client, "GRMChip_Normal"), "normal font exists")
ok(has(client, "GRMChip_Bold"), "bold font exists")
ok(has(client, "function CHIPS.OpenProgrammer"), "OpenProgrammer function exists")
ok(has(client, "function CHIPS.OpenChipCreator"), "OpenChipCreator function exists")
ok(has(client, "GRM_AugChip_SendList"), "send list receive handler exists")
ok(has(client, "GRM_AugChip_Create"), "create receive handler exists")
ok(has(client, "GRM_AugChip_Remove"), "remove receive handler exists")
ok(has(client, "GRM_AugChip_Implant"), "implant receive handler exists")
ok(has(client, "DFrame"), "frame creation exists")
ok(has(client, "DListView"), "list view exists")
ok(has(client, "DButton"), "button creation exists")
ok(has(client, "DLabel"), "label creation exists")
ok(has(client, "DTextEntry"), "text entry exists")
ok(has(client, "DComboBox"), "combo box exists")
ok(has(client, "DNumSlider"), "num slider exists")
ok(has(client, "DCheckBoxLabel"), "checkbox exists")
ok(has(client, "DScrollPanel"), "scroll panel exists")
ok(has(client, "Derma_Query"), "confirmation dialog exists")
ok(has(client, "concommand.Add"), "console command registered")
ok(has(client, "grm_chips"), "chips console command name exists")

--[[ РЕЕСТР МОДИФИКАТОРОВ: apply/remove/fold — по одной строке на способность.

     Раньше `speed/health/armor/carryWeight/stamina/vision` разбирались
     тремя лестницами (применить / снять / пересчитать), то есть новая
     способность требовала трёх правок в разных концах файла. Цена такой
     схемы уже была видна: пересчёт эффектов лежал в файле ДВАЖДЫ, и Lua
     молча использовал вторую копию.

     Проверяем циклом по реестру: у каждой способности есть все три
     половины, и «применить → снять» возвращает игрока к базовым
     значениям (потерянная remove-половина = вечный бафф после снятия
     чипа, который заметят только по жалобе). ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 0 end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
CHAN_AUTO = 0
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
string.Trim = function(x) return (tostring(x):gsub("^%s+", ""):gsub("%s+$", "")) end
hook = { Add = function() end, Run = function() end, Remove = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end }
file = { Exists = function() return false end, Read = function() end, Write = function() end,
    CreateDir = function() end, Find = function() return {}, {} end, IsDir = function() return true end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end }
local NET_SENT = {}
net = setmetatable({ Start = function(n) NET_SENT[#NET_SENT + 1] = n end,
    Receive = function() end }, { __index = function() return function() end end })
GRM = { Notify = function() end }
dofile("tools/luatest/lib_grm_core.lua")()
GRM.Movement = { Config = { WalkSpeed = 160, RunSpeed = 220 } }
GRM.Augmentations = { Config = { DefaultHealth = 100, MaxHealth = 1000, DefaultArmor = 0 } }

assert(loadfile("lua/autorun/sh_grm_augmentation_chips.lua"))()
local CHIPS = GRM.AugChips or GRM.AugmentationChips or GRM.Chips
ok(istable(CHIPS) and istable(CHIPS.Modifiers), "реестр модификаторов доступен как CHIPS.Modifiers")

local MODS = (istable(CHIPS) and CHIPS.Modifiers) or {}
ok(shared:find("elseif modKey ==", 1, true) == nil, "лестница `elseif modKey ==` не вернулась")
ok(select(2, shared:gsub("function CHIPS%.RecomputeEffects", "")) == 1,
    "пересчёт эффектов объявлен ровно один раз (была вторая копия, затиравшая первую)")

-- Базовые значения игрока, к которым обязано вернуть снятие чипа.
local BASE = { walk = 160, run = 220, maxHealth = 100, health = 100, armor = 0 }
local function mkPly()
    local p = { __valid = true, _nwi = {}, _nwf = {} }
    p.walk, p.run, p.maxHealth, p.health, p.armor = BASE.walk, BASE.run, BASE.maxHealth, BASE.health, BASE.armor
    function p:SetWalkSpeed(v) self.walk = v end
    function p:SetRunSpeed(v) self.run = v end
    function p:SetMaxHealth(v) self.maxHealth = v end
    function p:GetMaxHealth() return self.maxHealth end
    function p:SetHealth(v) self.health = v end
    function p:Health() return self.health end
    function p:SetArmor(v) self.armor = v end
    function p:Armor() return self.armor end
    function p:SetNWInt(k, v) self._nwi[k] = v end
    function p:SetNWFloat(k, v) self._nwf[k] = v end
    function p:GetNWInt(k) return self._nwi[k] or 0 end
    function p:GetNWFloat(k) return self._nwf[k] or 0 end
    function p:EmitSound() end
    function p:ChatPrint() end
    function p:IsPlayer() return true end
    function p:SteamID64() return "1" end
    return p
end

-- Значения-образцы для проверки пары apply/remove.
local SAMPLE = { speed = 1.5, health = 50, armor = 40, carryWeight = 25,
    stamina = 1.4, vision = "nightvision" }

local expected = { "speed", "health", "armor", "carryWeight", "stamina", "vision" }
for _, key in ipairs(expected) do
    local mod = MODS[key]
    ok(istable(mod) and isfunction(mod.apply) and isfunction(mod.remove) and isfunction(mod.fold),
        ("модификатор %s: есть apply, remove и fold"):format(key))

    if istable(mod) and isfunction(mod.apply) and isfunction(mod.remove) then
        local ply = mkPly()
        mod.apply(ply, SAMPLE[key])
        mod.remove(ply, SAMPLE[key])
        local restored = ply.walk == BASE.walk and ply.run == BASE.run
            and ply.armor == BASE.armor
            and (key ~= "health" or ply.maxHealth == BASE.maxHealth)
            and ply:GetNWInt("GRM_ChipCarryWeight") == 0
            and (key ~= "stamina" or ply:GetNWFloat("GRM_ChipStamina") == 1.0)
        ok(restored, ("модификатор %s: снятие возвращает базовые значения"):format(key))
    end
end

-- Пересчёт складывает эффекты нескольких чипов по правилам fold.
CHIPS.GetPlayerChips = function()
    return {
        { implanted = true, modifiers = { armor = 30, speed = 1.2, carryWeight = 10 } },
        { implanted = true, modifiers = { armor = 25, speed = 1.1, carryWeight = 40 } },
        { implanted = true, active = false, modifiers = { armor = 100 } },
    }
end
local ply = mkPly()
CHIPS.RecomputeEffects(ply)
ok(ply.armor == 55, "пересчёт: броня складывается (30+25), выключенный чип не считается")
ok(math.abs(ply.walk - 160 * 1.2 * 1.1) < 0.01, "пересчёт: скорость перемножается")
ok(ply:GetNWInt("GRM_ChipCarryWeight") == 40, "пересчёт: вес берётся лучший, а не сумма")

print(("AUGCHIPS: %d/%d failures=%d"):format(pass, pass + fail, fail))

if fail > 0 then
	os.exit(1)
end
