if SERVER then
    AddCSLuaFile()
end

SWEP.PrintName = "В наручниках"
SWEP.Author = "GRM"
SWEP.Instructions = "Вы задержаны."
SWEP.Category = "GRM RP"

SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.IsRestraints = true

SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.UseHands = false
SWEP.HoldType = "normal"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy()
    return true
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
end

function SWEP:Reload()
end

function SWEP:Holster()
    local owner = self:GetOwner()
    if IsValid(owner) and owner:GetNWBool("GRM_Cuffed", false) then
        return false
    end
    return true
end
