--[[--------------------------------------------------------------------
    Переносная пожарная лестница.
    ЛКМ — поставить на землю. ПКМ по машине — закрепить на борт.
    E на стоящей лестнице — взять в руки.
----------------------------------------------------------------------]]
AddCSLuaFile()

SWEP.PrintName = "Пожарная лестница"
SWEP.Author = "GRM"
SWEP.Category = "GRM Fire"
SWEP.Instructions = "ЛКМ: поставить  ПКМ по машине: закрепить  R: бросить"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/props/de_train/ladderaluminium.mdl"
if not util.IsValidModel(SWEP.WorldModel) then
    SWEP.WorldModel = "models/props_c17/metalladder002.mdl"
end
SWEP.ViewModelFOV = 54
SWEP.HoldType = "slam"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local function isCar(ent)
    if not IsValid(ent) then return false end
    if ent.IsVehicle and ent:IsVehicle() then return true end
    local cls = ent:GetClass() or ""
    return string.find(cls, "vehicle", 1, true)
        or string.StartWith(cls, "simfphys_")
        or string.StartWith(cls, "lvs_")
        or string.StartWith(cls, "glide_")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    return true
end

local function spawnLadder(ply, pos, ang)
    local ent = ents.Create("grm_fire_ladder")
    if not IsValid(ent) then return nil end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()
    if ent.SetDeployed then ent:SetDeployed(true) end
    hook.Run("GRM_FireAddon_Placed", ent, ply)
    return ent
end

function SWEP:PrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return end
    self:SetNextPrimaryFire(CurTime() + 0.4)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if hook.Run("GRM_FireAddon_LadderUse", ply, self) == false then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit then return end
    local ang = Angle(0, ply:EyeAngles().y, 0)
    local ent = spawnLadder(ply, tr.HitPos + tr.HitNormal * 2, ang)
    if not IsValid(ent) then return end
    ply:StripWeapon("weapon_grm_ladder")
    if ply.ChatPrint then ply:ChatPrint("[Лестница] Поставлена. E — взять снова. W у лестницы — залезть.") end
end

function SWEP:SecondaryAttack()
    if self:GetNextSecondaryFire() > CurTime() then return end
    self:SetNextSecondaryFire(CurTime() + 0.4)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if hook.Run("GRM_FireAddon_LadderUse", ply, self) == false then return end
    local tr = ply:GetEyeTrace()
    local veh = tr.Entity
    if not isCar(veh) then
        if ply.ChatPrint then ply:ChatPrint("[Лестница] Смотрите на машину, чтобы закрепить.") end
        return
    end
    local ent = spawnLadder(ply, veh:GetPos() + Vector(0, 0, 40), Angle(0, 0, 0))
    if not IsValid(ent) then return end
    if ent.AttachToVehicle then
        ent:AttachToVehicle(veh, Vector(0, 50, 12), Angle(0, 0, 0))
    end
    ply:StripWeapon("weapon_grm_ladder")
    if ply.ChatPrint then ply:ChatPrint("[Лестница] На борту. E — выдвинуть / убрать.") end
end

function SWEP:Reload()
    if (self._drop or 0) > CurTime() then return end
    self._drop = CurTime() + 0.5
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    spawnLadder(ply, tr.HitPos + tr.HitNormal * 2, Angle(0, ply:EyeAngles().y, 0))
    ply:StripWeapon("weapon_grm_ladder")
end

if CLIENT then
    function SWEP:DrawWorldModel()
        local ply = self:GetOwner()
        if IsValid(ply) then
            local att = ply:GetAttachment(ply:LookupAttachment("anim_attachment_RH"))
            if att then
                self:SetRenderOrigin(att.Pos)
                self:SetRenderAngles(att.Ang)
                self:DrawModel()
                self:SetRenderOrigin()
                self:SetRenderAngles()
                return
            end
        end
        self:DrawModel()
    end
end
