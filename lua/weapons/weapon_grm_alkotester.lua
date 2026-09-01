if SERVER then AddCSLuaFile() end

SWEP.PrintName = "Алкотестер"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ — продуть игрока в прицеле"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Category = "GRM Police"
SWEP.Slot = 2
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/coldwar_police/alkotester1.mdl"
SWEP.UseHands = true
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("slam")
    if util.IsValidModel("models/coldwar_police/alkotester1.mdl") then
        self.WorldModel = "models/coldwar_police/alkotester1.mdl"
    elseif util.IsValidModel("models/coldwar_police/alkotester2.mdl") then
        self.WorldModel = "models/coldwar_police/alkotester2.mdl"
    else
        self.WorldModel = "models/props_lab/reciever01b.mdl"
    end
end

function SWEP:PrimaryAttack()
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    self:SetNextPrimaryFire(CurTime() + 1.4)
    local tr = ply:GetEyeTrace()
    local t = tr.Entity
    if not (IsValid(t) and t:IsPlayer()) then
        if GRM.Notify then GRM.Notify(ply, "Наведитесь на человека.", 255, 180, 80) end
        return
    end
    if GRM.Alcohol and GRM.Alcohol.Test then
        ply:EmitSound("buttons/blip1.wav", 60, 110)
        GRM.Alcohol.Test(ply, t)
    end
end

function SWEP:SecondaryAttack()
    if CLIENT then return end
    self:SetNextSecondaryFire(CurTime() + 0.8)
    if util.IsValidModel("models/coldwar_police/alkotester2.mdl") then
        if self.WorldModel == "models/coldwar_police/alkotester2.mdl" then
            self.WorldModel = "models/coldwar_police/alkotester1.mdl"
        else
            self.WorldModel = "models/coldwar_police/alkotester2.mdl"
        end
        self:SetModel(self.WorldModel)
    end
end

function SWEP:DrawWorldModel()
    local mdl = self.WorldModel
    if not util.IsValidModel(mdl) then
        mdl = "models/props_lab/reciever01b.mdl"
    end
    self:SetModel(mdl)
    self:DrawModel()
end
