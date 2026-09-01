-- Regression guard for smooth handcuff escort.
-- This test intentionally checks the production implementation for the
-- dangerous primitives that caused teleports/jitter, then exercises the
-- same horizontal smoothing contract numerically without GMod.

local path = "lua/autorun/server/sv_grm_handcuffs.lua"
local f = assert(io.open(path, "rb"))
local src = f:read("*a")
f:close()

local checks, failed = 0, 0
local function ok(cond, label)
    checks = checks + 1
    if cond then print("  ok " .. checks .. ". " .. label)
    else failed = failed + 1 print("  FAIL " .. checks .. ". " .. label) end
end

local startBlock = assert(src:match("function HC%.StartDragging%b()%s*(.-)function HC%.CuffPlayer"), "StartDragging block missing")
local moveBlock = assert(src:match('hook%.Add%(%"SetupMove%".-function%b()%s*(.-)hook%.Add%(%"CanPlayerEnterVehicle%"'), "SetupMove block missing")

ok(not startBlock:find("SetParent%(dragger%)"), "StartDragging never parents captive to escort")
ok(not startBlock:find("Freeze%(true%)"), "StartDragging never freezes captive")
ok(not startBlock:find("SetLocalPos"), "StartDragging never changes local/world position")
ok(not startBlock:find("SetLocalAngles"), "StartDragging never inherits escort angles")
ok(not moveBlock:find("ply:SetPos", 1, true), "SetupMove has no player teleport primitive")
ok(not moveBlock:find("ply:SetVelocity", 1, true), "SetupMove never uses Entity:SetVelocity physics impulses")
ok(moveBlock:find("mv:SetVelocity", 1, true) ~= nil, "escort velocity is applied through predicted MoveData")
ok(moveBlock:find("correction%.z%s*=%s*0") ~= nil, "position correction is horizontal only")
ok(moveBlock:find("currentVelocity%.z") ~= nil, "vertical velocity is preserved from player physics")
ok(moveBlock:find("EscortBreakVerticalDistance") ~= nil, "different floor/large vertical gap breaks escort")
ok(moveBlock:find("EscortBreakDistance") ~= nil, "large horizontal gap breaks escort")
ok(src:find('if IsValid(ply:GetNWEntity("GRM_CuffDragger"))', 1, true) ~= nil
    and src:find("cmd:ClearMovement()", 1, true) ~= nil,
    "captive input cannot fight escort movement")

local function smooth(current, wanted, dt, acceleration, maxSpeed)
    local len = math.sqrt(wanted.x * wanted.x + wanted.y * wanted.y)
    if len > maxSpeed then
        wanted = { x = wanted.x / len * maxSpeed, y = wanted.y / len * maxSpeed }
    end
    local blend = math.max(0, math.min(1, dt * acceleration))
    return {
        x = current.x + (wanted.x - current.x) * blend,
        y = current.y + (wanted.y - current.y) * blend,
        z = current.z,
    }
end

local v = smooth({ x = 0, y = 0, z = -123 }, { x = 1000, y = 0 }, 0.015, 8, 300)
ok(v.z == -123, "smoothing cannot pull captive upward/downward")
ok(v.x > 0 and v.x < 300, "first tick accelerates smoothly instead of snapping")
local horizontal = math.sqrt(v.x * v.x + v.y * v.y)
ok(horizontal <= 300, "escort speed is capped")

print(("HANDCUFF ESCORT: %d/%d, failures=%d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
