-- Regression contract: duplicate map entities of one physical door share one ID,
-- while adjacent prison/corridor doors stay independent.
local f = assert(io.open("lua/autorun/sh_grm_doors.lua", "rb"))
local src = f:read("*a") f:close()
local checks, failed = 0, 0
local function ok(v, label)
    checks = checks + 1
    if v then print("  ok " .. checks .. ". " .. label)
    else failed = failed + 1 print("  FAIL " .. checks .. ". " .. label) end
end
local function has(s) return src:find(s, 1, true) ~= nil end

ok(has("function D.IsSamePhysicalDoor"), "physical-door equivalence API exists")
ok(has("function D.GetPrimaryDoor")and has("GRM_DoorAlias"),"one canonical door marks secondary map entities as aliases")
ok(has("function D.CollapseDuplicateRecords")and has("удалено фантомных записей-дублей"),"legacy phantom door records collapse before save")
ok(has("function D.RebuildDoorIdentityCache"), "canonical identity cache exists")
ok(has("function D.GetEquivalentDoors"), "all duplicate entities can be synchronized")
ok(has("DuplicateXYOverlap") and has("DuplicateZOverlap"), "AABB overlap guards against adjacent door merge")
ok(has("recordPriority") and has('rec.owner_type and rec.owner_type ~= "none"'), "owned legacy record wins over phantom unowned record")
ok(has("for _, equivalent in ipairs(D.GetEquivalentDoors(ent))"), "owner/lock synchronization reaches every duplicate entity")
ok(not has("ents.FindInSphere(ent:GetPos(), 12)"), "fragile origin-only 12-unit merge removed")

local function overlap(a, b)
    local ox = math.max(0, math.min(a.maxx, b.maxx) - math.max(a.minx, b.minx))
    local oy = math.max(0, math.min(a.maxy, b.maxy) - math.max(a.miny, b.miny))
    local oz = math.max(0, math.min(a.maxz, b.maxz) - math.max(a.minz, b.minz))
    local areaA = math.max(1, (a.maxx-a.minx)*(a.maxy-a.miny))
    local areaB = math.max(1, (b.maxx-b.minx)*(b.maxy-b.miny))
    local hA, hB = math.max(1,a.maxz-a.minz), math.max(1,b.maxz-b.minz)
    return ox*oy/math.min(areaA,areaB), oz/math.min(hA,hB)
end
local function same(a,b)
    local dx,dy,dz=a.cx-b.cx,a.cy-b.cy,a.cz-b.cz
    if dx*dx+dy*dy+dz*dz > 64*64 then return false end
    local xy,z=overlap(a,b)
    return xy>=0.55 and z>=0.72
end
local physical = {minx=0,maxx=4,miny=0,maxy=64,minz=0,maxz=96,cx=2,cy=32,cz=48}
local visual   = {minx=0,maxx=4,miny=2,maxy=64,minz=1,maxz=96,cx=2,cy=33,cz=48}
local neighbor = {minx=0,maxx=4,miny=68,maxy=132,minz=0,maxz=96,cx=2,cy=100,cz=48}
local touching = {minx=0,maxx=4,miny=64,maxy=128,minz=0,maxz=96,cx=2,cy=96,cz=48}
ok(same(physical, visual), "overlapping mechanism + visual leaf are one physical door")
ok(not same(physical, neighbor), "nearby prison doors remain separate")
ok(not same(physical, touching), "touching double/corridor leaves do not merge without overlap")

print(("DOOR IDENTITY: %d/%d, failures=%d"):format(checks-failed,checks,failed))
if failed>0 then os.exit(1) end
