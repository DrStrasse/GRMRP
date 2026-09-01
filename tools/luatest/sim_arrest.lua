-- Regression contract for GRM Arrest v1.1.0.
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a") f:close()
    return s
end

local arrest = read("lua/autorun/sh_grm_arrest.lua")
local factions = read("lua/autorun/sh_faction_fixes.lua")
local inventory = read("lua/autorun/sh_grm_inventory.lua")
local cuffs = read("lua/autorun/server/sv_grm_handcuffs.lua")
local checks, failed = 0, 0
local function ok(value, label)
    checks = checks + 1
    if value then print("  ok " .. checks .. ". " .. label)
    else failed = failed + 1 print("  FAIL " .. checks .. ". " .. label) end
end
local function has(s, needle) return s:find(needle, 1, true) ~= nil end

print("== arrest: full confiscation and permanent unarmed gate ==")
ok(has(arrest, "function A.EnforceUnarmed"), "authoritative unarmed API exists")
ok(has(arrest, "target:StripWeapons()") and has(arrest, "target:RemoveAllAmmo()"), "arrest strips weapons and ammunition")
ok(has(arrest, "function A.Confiscate") and has(arrest, "invAPI.RemoveFromSlot"), "GRM Inventory slots are confiscated")
ok(has(arrest, "target.GRM_CuffStoredWeapons = nil"), "handcuff loadout cannot resurrect confiscated weapons")
ok(has(arrest, 'timer.Create("GRM_Arrest_EnforceUnarmed"'), "periodic fail-safe removes external weapon grants")
ok(has(arrest, 'hook.Add("PlayerLoadout"') and has(arrest, 'hook.Add("WeaponEquip"'), "loadout and equip paths are blocked")
ok(has(factions, 'ply:GetNWBool("GRM_Arrested", false) then return {}'), "/weapons_admin resolves no weapons for arrested players")
ok(has(factions, "ply:RemoveAllAmmo()"), "faction application strips ammo too")
ok(has(inventory, 'ply:GetNWBool("GRM_Arrested", false) then return count or 1'), "items cannot be added while arrested")
ok(has(inventory, 'ply:GetNWBool("GRM_Arrested", false) then return false'), "inventory weapons cannot be added while arrested")
ok(has(cuffs, 'ply:GetNWBool("GRM_Arrested", false)') and has(cuffs, "ply.GRM_CuffStoredWeapons = nil"), "cuffs never issue restrained SWEP to arrested player")

print("== arrest: category routing and cameras ==")
ok(has(arrest, "cameraIDs = {}") and has(arrest, 'action == "set_group_cameras"'), "categories own configurable camera lists")
ok(has(arrest, "openGroupCameraEditor"), "admin UI edits cameras from category card")
ok(not has(arrest, "return A.Cfg.cameras[1]"), "no fallback into unrelated first camera")
ok(not has(arrest, "return A.Cfg.spawns[1]"), "no fallback into unrelated first spawn")
ok(has(arrest, "GRM_ArrestCameraID"), "assigned camera is tracked per prisoner")
ok(has(arrest, 'hook.Add("PlayerSpawn", "GRM_Arrest_AppearanceAfterSpawn"')
    and has(arrest, "if cam and sp then"), "arrested player respawns in an assigned category camera")
ok(has(arrest, "item.occupied = item.occupied + 1"), "least occupied category camera is selected")
ok(has(arrest, "autoPriority") and has(arrest, "table.sort(candidates"), "auto category resolution is deterministic")
ok(not has(arrest, "render.DrawWireframeSphere"), "large arrest camera spheres are removed")
ok(has(arrest, "not lp:IsSuperAdmin()"), "subtle camera marker is visible only to superadmins")

-- Numerical model of the production selection rules.
local groups = {
    criminals = { autoPriority = 1000, allowedFactions = {}, cameraIDs = { "crime_a", "crime_b" } },
    political = { autoPriority = 20, allowedFactions = { Government = true }, cameraIDs = { "pol" } },
    guardhouse = { autoPriority = 10, allowedFactions = { Army = true }, cameraIDs = { "guard" } },
}
local function resolve(faction, requested)
    requested = requested or "auto"
    if requested ~= "auto" and requested ~= "" then return groups[requested] and requested or nil end
    if not faction or faction == "" then return "criminals" end
    local list = {}
    for id, g in pairs(groups) do
        if id ~= "criminals" and g.allowedFactions[faction] then list[#list + 1] = { id = id, p = g.autoPriority } end
    end
    table.sort(list, function(a, b) return a.p == b.p and a.id < b.id or a.p < b.p end)
    return list[1] and list[1].id or "criminals"
end
ok(resolve("Army", "auto") == "guardhouse", "army faction routes to guardhouse")
ok(resolve("Government", "auto") == "political", "configured faction routes to political category")
ok(resolve("", "auto") == "criminals" and resolve("Civil", "auto") == "criminals", "no faction/civil fallback routes to criminals")
ok(resolve("Army", "criminals") == "criminals", "explicit valid category is respected")
ok(resolve("Army", "missing") == nil, "invalid category is rejected")

local cameras = {
    crime_a = { spawn = true, occupied = 2 },
    crime_b = { spawn = true, occupied = 0 },
    broken = { spawn = false, occupied = 0 },
}
local function choose(ids)
    local list = {}
    for _, id in ipairs(ids) do
        local c = cameras[id]
        if c and c.spawn then list[#list + 1] = { id = id, occupied = c.occupied } end
    end
    table.sort(list, function(a, b) return a.occupied == b.occupied and a.id < b.id or a.occupied < b.occupied end)
    return list[1] and list[1].id
end
ok(choose({ "crime_a", "crime_b", "broken" }) == "crime_b", "least occupied valid camera wins")
ok(choose({ "broken" }) == nil, "camera without spawn cannot receive prisoner")

print(("ARREST: %d/%d, failures=%d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
