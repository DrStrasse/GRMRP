if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_base"
SWEP.PrintName = "Электродубинка"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ — удар и оглушение без урона"
SWEP.Category = "GRM RP"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Модели и одноручная поза стандартного HL2/GMod stunstick.
SWEP.ViewModel = "models/weapons/v_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "melee"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.BobScale = 0.9
SWEP.SwayScale = 0.8

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1.05
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.HitDistance = 82
SWEP.HitHull = 10
SWEP.StunSeconds = 20
SWEP.ImpactDelay = 0.12

local SWING_SOUNDS = {
    "Weapon_StunStick.Swing",
    "weapons/stunstick/stunstick_swing1.wav",
    "weapons/stunstick/stunstick_swing2.wav",
}
local IMPACT_SOUNDS = {
    "Weapon_StunStick.Melee_Hit",
    "weapons/stunstick/stunstick_impact1.wav",
    "weapons/stunstick/stunstick_impact2.wav",
}
local WORLD_HIT_SOUND = "Weapon_StunStick.Melee_HitWorld"
local ACTIVATE_SOUND = "Weapon_StunStick.Activate"
local DEACTIVATE_SOUND = "Weapon_StunStick.Deactivate"

local function firstPredicted()
    return SERVER or not IsFirstTimePredicted or IsFirstTimePredicted()
end

local function emit(ent, soundName, level, pitch, volume)
    if not IsValid(ent) or not soundName or soundName == "" then return end
    ent:EmitSound(soundName, level or 72, pitch or 100, volume or 1, CHAN_WEAPON)
end

function SWEP:Initialize()
    self:SetHoldType("melee")
end

function SWEP:Deploy()
    self:SetHoldType("melee")
    self:SendWeaponAnim(ACT_VM_DRAW)
    self:SetNextPrimaryFire(CurTime() + 0.45)
    if firstPredicted() then emit(self, ACTIVATE_SOUND, 62, 100, 0.7) end
    local owner = self:GetOwner()
    if IsValid(owner) then
        local vm = owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(1) end
    end
    return true
end

function SWEP:Holster()
    if firstPredicted() then emit(self, DEACTIVATE_SOUND, 58, 100, 0.55) end
    return true
end

function SWEP:OnRemove()
    if SERVER then self:StopSound(ACTIVATE_SOUND) end
end

function SWEP:PlaySwingAnimation()
    self:SendWeaponAnim(ACT_VM_HITCENTER)
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    owner:SetAnimation(PLAYER_ATTACK1)
    owner:DoAnimationEvent(ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE)
    local vm = owner:GetViewModel()
    if IsValid(vm) then vm:SetPlaybackRate(1.18) end
end

local function impactEffect(tr)
    if not tr or not tr.Hit then return end
    local effect = EffectData()
    effect:SetOrigin(tr.HitPos)
    effect:SetNormal(tr.HitNormal)
    effect:SetMagnitude(2)
    effect:SetScale(1)
    util.Effect("StunstickImpact", effect, true, true)
end

function SWEP:TraceStrike(owner)
    if not IsValid(owner) then return nil end
    owner:LagCompensation(true)
    local startPos = owner:GetShootPos()
    local tr = util.TraceHull({
        start = startPos,
        endpos = startPos + owner:GetAimVector() * (self.HitDistance or 82),
        filter = { owner, self },
        mins = Vector(-(self.HitHull or 10), -(self.HitHull or 10), -(self.HitHull or 10)),
        maxs = Vector(self.HitHull or 10, self.HitHull or 10, self.HitHull or 10),
        mask = MASK_SHOT_HULL or MASK_SHOT,
    })
    owner:LagCompensation(false)
    return tr
end

function SWEP:ApplyStun(target, owner)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return false end

    if GRM.Handcuffs and GRM.Handcuffs.StunPlayer then
        return GRM.Handcuffs.StunPlayer(owner, target, self.StunSeconds or 20, { silent = true, silentNotify = true })
    end

    -- Fail-safe для установки SWEP без handcuffs core.
    local untilTime = CurTime() + math.Clamp(tonumber(self.StunSeconds) or 20, 1, 30)
    target.GRM_StunnedUntil = math.max(tonumber(target.GRM_StunnedUntil) or 0, untilTime)
    target:SetNWBool("GRM_Stunned", true)
    target:SetNWFloat("GRM_StunnedUntil", target.GRM_StunnedUntil)
    timer.Simple(self.StunSeconds or 20, function()
        if IsValid(target) and CurTime() >= (target.GRM_StunnedUntil or 0) then
            target:SetNWBool("GRM_Stunned", false)
            target:SetNWFloat("GRM_StunnedUntil", 0)
        end
    end)
    return true
end

function SWEP:ResolveStrike(owner)
    if not SERVER or not IsValid(self) or not IsValid(owner) or owner:GetActiveWeapon() ~= self then return end
    local tr = self:TraceStrike(owner)
    if not tr or not tr.Hit then return end

    impactEffect(tr)
    local target = tr.Entity
    if IsValid(target) and target:IsPlayer() then
        emit(self, IMPACT_SOUNDS[math.random(#IMPACT_SOUNDS)], 78, math.random(96, 104), 1)
        if self:ApplyStun(target, owner) then
            target:ViewPunch(Angle(-11, math.Rand(-4, 4), math.Rand(-2, 2)))
            target:ScreenFade(SCREENFADE.IN, Color(210, 235, 255, 75), 0.12, 0.18)
            util.ScreenShake(tr.HitPos, 4, 28, 0.25, 180)
            if GRM.Notify then GRM.Notify(target, "Вы оглушены электродубинкой.", 255, 180, 90) end
        end
    else
        emit(self, WORLD_HIT_SOUND, 72, math.random(96, 104), 0.9)
    end
end

function SWEP:PrimaryAttack()
    if not firstPredicted() then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    self:SetNextPrimaryFire(CurTime() + (self.Primary.Delay or 1.05))
    self:SetNextSecondaryFire(CurTime() + (self.Primary.Delay or 1.05))
    self:PlaySwingAnimation()
    emit(self, SWING_SOUNDS[math.random(#SWING_SOUNDS)], 68, math.random(97, 103), 0.9)

    if SERVER then
        timer.Simple(self.ImpactDelay or 0.12, function()
            if IsValid(self) and IsValid(owner) then self:ResolveStrike(owner) end
        end)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.4)
end

if SERVER and not GRM_ElectroBatonStunGuard then
    GRM_ElectroBatonStunGuard = true
    -- Самодостаточный блок управления: основной handcuffs hook делает то же,
    -- но этот guard оставляет SWEP функциональным и без модуля наручников.
    hook.Add("StartCommand", "GRM_ElectroBaton_StunControls", function(ply, cmd)
        if not IsValid(ply) or not ply:GetNWBool("GRM_Stunned", false) then return end
        if CurTime() >= ply:GetNWFloat("GRM_StunnedUntil", 0) then
            ply:SetNWBool("GRM_Stunned", false)
            return
        end
        cmd:ClearMovement()
        cmd:ClearButtons()
    end)
    hook.Add("SetupMove", "GRM_ElectroBaton_StunMovement", function(ply, mv)
        if not IsValid(ply) or not ply:GetNWBool("GRM_Stunned", false) then return end
        mv:SetMaxClientSpeed(0)
        mv:SetMaxSpeed(0)
        local velocity = mv:GetVelocity()
        mv:SetVelocity(Vector(0, 0, velocity.z))
    end)
end
