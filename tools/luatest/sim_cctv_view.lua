-- Contracts for CCTV live-view isolation and death fail-safe.
local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end
local client = read("lua/autorun/client/cl_grm_cctv.lua")
local server = read("lua/autorun/server/sv_grm_cctv.lua")
local pass, fail = 0, 0
local function has(text, needle) return text:find(needle, 1, true) ~= nil end
local function ok(value, label)
    if value then pass = pass + 1 print("  ok  " .. label)
    else fail = fail + 1 print("  FAIL " .. label) end
end

ok(has(client, "client v1.3.2") and has(server, "server v1.3.2"), "CCTV v1.3.2 client/server contract")
ok(has(client, "function CCTV.IsViewing()"), "client exposes authoritative local viewing state")
ok(has(client, "suppressOtherHUDPaint") and has(client, 'id ~= "GRM_CCTV_Overlay"'), "all foreign HUDPaint hooks are suppressed except CCTV overlay")
ok(has(client, "restoreOtherHUDPaint()") and has(client, 'hook.Add("HUDPaint", id, fn)'), "suppressed HUD hooks are restored on exit")
ok(has(client, "_drawHUDWasEnabled") and has(client, 'cl_drawhud 0') and has(client, 'cl_drawhud 1'), "original cl_drawhud preference is preserved")
ok(has(client, 'hook.Add("PlayerDeath", "GRM_CCTV_ClientDeathExit"') and has(client, "not ply:Alive()"), "client exits immediately on death with Think fallback")
ok(has(server, 'hook.Add("PlayerDeath", "GRM_CCTV_Death"') and has(server, 'hook.Add("PlayerSilentDeath", "GRM_CCTV_SilentDeath"'), "server handles normal and silent death")
ok(has(server, "local bad = not ply:Alive()") and has(server, "if bad then CCTV.StopView(ply) end"), "server view guard heals missed death hooks")
ok(has(server, "ply:SetViewEntity(nil)") and has(server, "ply:Freeze(false)") and has(server, "net.Start(NET_VIEW_STOP)"), "server stop restores view, movement, and client state")
ok(has(client, "GetSelectedLine()") and has(client, "line._camID") and has(client, "net.WriteString(tostring(camID"), "monitor selection uses stable DeviceID, not only a PVS entity")
ok(has(server, "function CCTV.FindDeviceByID") and has(server, 'CCTV.FindDeviceByID(camID, "grm_cctv_camera")'), "server resolves remote camera authoritatively by DeviceID")
ok(has(server, "function CCTV.RebuildRegistry()") and has(server, "created=%d healed=%d"), "restart load rebuilds registry and heals existing devices")
ok(has(server, "claimed[ent]") and has(server, "ent:SetNetworkID(CCTV.NormalizeNetwork(rec.network))"), "load reconciliation restores saved network without duplicate entities")
ok(has(server, "net.WriteVector(cam:GetPos())") and has(server, "net.WriteAngle(cam:GetAngles())") and has(client, "local basePos = net.ReadVector()"), "live view carries a transform fallback for cameras outside client PVS")
ok(has(client, "IsValid(cam) and cam:GetPos() or ViewState.basePos") and has(client, 'tostring(ViewState.camID or "") == ""'), "client keeps remote DeviceID view alive without a networked camera entity")
ok(has(server, 'active = (not ent.GetActive) or ent:GetActive() == true'), "offline camera/server state survives persistence")
ok(has(server, "GRM_CCTV_RemoteCameraPVS") and has(server, "AddOriginToPVS(ply._grmCCTVCam:GetPos())"), "remote camera receives full prop/NPC PVS")
ok(has(client, "zfar = 32768") and has(client, "znear = 2"), "CCTV view uses full map draw range")

print(("CCTV VIEW: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
