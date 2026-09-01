-- Regression contract for functional GRM electro baton.
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local baton = read("lua/weapons/weapon_grm_electro_baton.lua")
local cuffs = read("lua/autorun/server/sv_grm_handcuffs.lua")
local checks, failed = 0, 0
local function ok(v, label)
    checks = checks + 1
    if v then print("  ok " .. checks .. ". " .. label)
    else failed = failed + 1 print("  FAIL " .. checks .. ". " .. label) end
end
local function has(s, needle) return s:find(needle, 1, true) ~= nil end

ok(has(baton, 'SWEP.HoldType = "melee"') and not has(baton, 'HoldType = "melee2"'), "one-handed stunstick hold pose")
ok(has(baton, "ACT_VM_HITCENTER"), "standard stunstick viewmodel strike animation")
ok(has(baton, "ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE"), "third-person melee strike gesture")
ok(has(baton, "vm:SetPlaybackRate(1.18)"), "strike animation playback tuned")
ok(has(baton, "Weapon_StunStick.Activate") and has(baton, "Weapon_StunStick.Deactivate"), "deploy/holster electrical sounds")
ok(has(baton, "Weapon_StunStick.Swing") and has(baton, "Weapon_StunStick.Melee_Hit"), "standard swing/impact sound script names")
ok(has(baton, "util.TraceHull") and has(baton, "owner:LagCompensation(true)"), "lag-compensated melee hull trace")
ok(has(baton, "ImpactDelay = 0.12") and has(baton, "timer.Simple(self.ImpactDelay"), "impact follows swing animation")
ok(has(baton, 'util.Effect("StunstickImpact"'), "electrical impact sparks")
ok(has(baton, "target:ViewPunch") and has(baton, "target:ScreenFade") and has(baton, "util.ScreenShake"), "target receives visible stun feedback")
ok(has(baton, "GRM.Handcuffs.StunPlayer") and has(baton, "silent = true, silentNotify = true"), "authoritative GRM stun without duplicate sound/notification")
ok(has(baton, "SWEP.StunSeconds = 20") and has(baton, "self.StunSeconds or 20"), "electro baton locks target for 20 seconds")
ok(has(cuffs, "function HC.StunPlayer(actor, target, seconds, options)"), "handcuffs stun API accepts sound options")
ok(has(cuffs, "1, 30"), "shared stun API permits requested 20-second duration")
ok(has(baton, 'hook.Add("StartCommand", "GRM_ElectroBaton_StunControls"'), "standalone control lock fallback")
ok(has(baton, 'hook.Add("SetupMove", "GRM_ElectroBaton_StunMovement"'), "standalone movement lock fallback")
ok(not has(baton, "TakeDamage") and not has(baton, "DamageInfo"), "baton stuns without health damage")

print(("ELECTRO BATON: %d/%d, failures=%d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
