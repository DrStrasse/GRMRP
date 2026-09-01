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

print(("AUGCHIPS: %d/%d failures=%d"):format(pass, pass + fail, fail))

if fail > 0 then
	os.exit(1)
end
