--[[
	GRM Augmentations Tests v2.0
	Тесты системы кибернетических аугментаций с категориями и правами доступа
]]

local function read(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local shared = read("lua/autorun/sh_grm_augmentations.lua")
local client = read("lua/autorun/client/cl_grm_augmentations.lua")
local admin = read("lua/autorun/client/cl_grm_augmentations_admin.lua")
local pod = read("lua/entities/grm_augmentation_pod/init.lua")

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
ok(has(shared, "GRM.Augmentations"), "augmentations module exists")
ok(has(shared, "AUG.Config"), "configuration table exists")
ok(has(shared, "MaxHealth"), "max health config exists")
ok(has(shared, "MaxArmor"), "max armor config exists")
ok(has(shared, "Categories"), "categories system exists")
ok(has(shared, "civilian"), "civilian category exists")
ok(has(shared, "service"), "service category exists")
ok(has(shared, "military"), "military category exists")
ok(has(shared, "experimental"), "experimental category exists")

-- Augmentation types
ok(has(shared, "InfraredVision"), "infrared vision augmentation exists")
ok(has(shared, "EnhancedArmor"), "enhanced armor augmentation exists")
ok(has(shared, "HealthBoost"), "health boost augmentation exists")
ok(has(shared, "HUDOverlay"), "HUD overlay augmentation exists")
ok(has(shared, "EnhancedSpeed"), "enhanced speed augmentation exists")
ok(has(shared, "Regeneration"), "regeneration augmentation exists")
ok(has(shared, "NightVision"), "night vision augmentation exists")
ok(has(shared, "EMPShield"), "EMP shield augmentation exists")

-- Access control
ok(has(shared, "function AUG.CanAccessAugmentation"), "CanAccessAugmentation function exists")
ok(has(shared, "function AUG.GetAvailableAugmentations"), "GetAvailableAugmentations function exists")
ok(has(shared, "ply:IsSuperAdmin()"), "superadmin bypass exists")
ok(has(shared, "access.everyone"), "everyone access flag exists")
ok(has(shared, "access.factions"), "factions access list exists")
ok(has(shared, "access.roles"), "roles access list exists")

-- Core functions
ok(has(shared, "AUG.PlayerData"), "player data storage exists")
ok(has(shared, "function AUG.GetPlayerData"), "GetPlayerData function exists")
ok(has(shared, "function AUG.HasAugmentation"), "HasAugmentation function exists")
ok(has(shared, "function AUG.ApplyAugmentation"), "ApplyAugmentation function exists")
ok(has(shared, "function AUG.RemoveAugmentation"), "RemoveAugmentation function exists")
ok(has(shared, "function AUG.SaveData"), "SaveData function exists")
ok(has(shared, "function AUG.LoadData"), "LoadData function exists")

-- Network
ok(has(shared, "util.AddNetworkString"), "network strings added")
ok(has(shared, "GRM_Augmentation_Update"), "update network string exists")
ok(has(shared, "GRM_Augmentation_Apply"), "apply network string exists")
ok(has(shared, "GRM_Augmentation_Remove"), "remove network string exists")
ok(has(shared, "GRM_Augmentation_Admin_Open"), "admin open network string exists")
ok(has(shared, "GRM_Augmentation_Admin_Save"), "admin save network string exists")
ok(has(shared, "GRM_Augmentation_Admin_GetList"), "admin get list network string exists")
ok(has(shared, "GRM_Augmentation_Admin_SendList"), "admin send list network string exists")

-- Hooks
ok(has(shared, "PlayerSpawn"), "player spawn hook exists")
ok(has(shared, "grmBootStart(\"GRM_Augmentations_Init\", \"normal\""), "старт подсистемы идёт через GRM.Boot (было Initialize)")
ok(has(shared, "ShutDown"), "shutdown hook exists")

-- Server-side operations
ok(has(shared, "ply:SetArmor"), "armor setting exists")
ok(has(shared, "ply:SetMaxHealth"), "max health setting exists")
ok(has(shared, "ply:SetHealth"), "health setting exists")
ok(has(shared, "ply:SetWalkSpeed"), "walk speed setting exists")
ok(has(shared, "ply:SetRunSpeed"), "run speed setting exists")
ok(has(shared, "file.Write"), "file saving exists")
ok(has(shared, "file.Read"), "file loading exists")

-- Client tests
ok(has(client, "infraredEnabled"), "infrared state variable exists")
ok(has(client, "hudEnabled"), "HUD state variable exists")
ok(has(client, "nightVisionEnabled"), "night vision state variable exists")
ok(has(client, "RenderScreenspaceEffects"), "screenspace effects hook exists")
ok(has(client, "DrawColorModify"), "color modify for infrared exists")
ok(has(client, "GRM_Augmentations_NightVision"), "night vision effect exists")
ok(has(client, "PrePlayerDraw"), "pre player draw hook exists")
ok(has(client, "PostPlayerDraw"), "post player draw hook exists")
ok(has(client, "render.SetColorModulation"), "color modulation for thermal vision exists")
ok(has(client, "HUDPaint"), "HUD paint hook exists")
ok(has(client, "scanlineOffset"), "scanline animation exists")
ok(has(client, "surface.DrawLine"), "HUD border lines exist")
ok(has(client, "draw.SimpleText"), "HUD text display exists")
ok(has(client, "ambientSound"), "ambient sound system exists")
ok(has(client, "CreateSound"), "sound creation exists")
ok(has(client, "net.Receive"), "network receive handler exists")
ok(has(client, "INFRARED: ACTIVE"), "infrared indicator exists")
ok(has(client, "NIGHT VISION: ACTIVE"), "night vision indicator exists")

-- Admin panel tests
ok(has(admin, "AUG.OpenAdminPanel"), "OpenAdminPanel function exists")
ok(has(admin, "GRM_COLORS"), "GRM color scheme exists")
ok(has(admin, "GRM_Augmentation_Admin_SendList"), "admin list receive handler exists")
ok(has(admin, "DListView"), "list view for augmentations exists")
ok(has(admin, "DCheckBoxLabel"), "checkbox for status exists")
ok(has(admin, "DTextEntry"), "text entry for cost exists")
ok(has(admin, "GRM_Augmentation_Admin_Save"), "admin save network send exists")
ok(has(admin, "concommand.Add"), "console command registered")
ok(has(admin, "grm_augmentations_admin"), "admin console command name exists")

-- Pod entity tests
ok(has(pod, "ENT.Type"), "entity type defined")
ok(has(pod, "ENT.Category"), "entity category defined")
ok(has(pod, "GRM — Аугментации"), "correct category (GRM — Аугментации)")
ok(has(pod, "function ENT:Initialize"), "initialize function exists")
ok(has(pod, "function ENT:Use"), "use function exists")
ok(has(pod, "function ENT:Think"), "think function exists")
ok(has(pod, "function ENT:Draw"), "draw function exists")
ok(has(pod, "SetupDataTables"), "data tables setup exists")
ok(has(pod, "SetActive"), "active state exists")
ok(has(pod, "SetOccupied"), "occupied state exists")
ok(has(pod, "SetOccupant"), "occupant tracking exists")
ok(has(pod, "PhysicsInit"), "physics initialization exists")
ok(has(pod, "SIMPLE_USE"), "simple use type exists")
ok(has(pod, "GRM_AugmentationPod_Open"), "pod open network string exists")
ok(has(pod, "GRM_AugmentationPod_Apply"), "pod apply network string exists")
ok(has(pod, "net.Receive"), "network receive handlers exist")
ok(has(pod, "GRM.Augmentations.ApplyAugmentation"), "augmentation application exists")
ok(has(pod, "GRM.Augmentations.CanAccessAugmentation"), "access check exists")
ok(has(pod, "GRM.Augmentations.GetAvailableAugmentations"), "get available augmentations exists")
ok(has(pod, "util.Effect"), "visual effects exist")
ok(has(pod, "EmitSound"), "sound effects exist")
ok(has(pod, "vgui.Create"), "client UI creation exists")
ok(has(pod, "DFrame"), "frame creation exists")
ok(has(pod, "DButton"), "button creation exists")
ok(has(pod, "DLabel"), "label creation exists")
ok(has(pod, "DScrollPanel"), "scroll panel exists")
ok(has(pod, "ДОСТУПНЫЕ АУГМЕНТАЦИИ"), "augmentation list UI exists")
ok(has(pod, "ГРАЖДАНСКИЕ"), "civilian category UI exists")
ok(has(pod, "СЛУЖЕБНЫЕ"), "service category UI exists")
ok(has(pod, "ВОЕННЫЕ"), "military category UI exists")
ok(has(pod, "ЭКСПЕРИМЕНТАЛЬНЫЕ"), "experimental category UI exists")
ok(has(pod, "HUDPaint"), "HUD paint hook exists")
ok(has(pod, "GetEyeTrace"), "eye trace for targeting exists")

print(("AUGMENTATIONS v2.0: %d/%d failures=%d"):format(pass, pass + fail, fail))

if fail > 0 then
	os.exit(1)
end
