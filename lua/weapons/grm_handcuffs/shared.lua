if SERVER then
    AddCSLuaFile()
end

SWEP.PrintName = "Наручники"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ: надеть/снять | ПКМ: вести | R: кляп | ALT+R: повязка"
SWEP.Category = "GRM RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/handcuffs_grm/c_handcuffs_grm.mdl"
SWEP.WorldModel = "models/handcuffs_grm/w_handcuffs_grm.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

local function cfg()
    return GRM and GRM.Handcuffs and GRM.Handcuffs.Config or {}
end

local function HC()
    return GRM and GRM.Handcuffs
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType)

    if SERVER and HC() then
        local ok, reason = HC().HasAccess(self:GetOwner())
        if not ok then
            HC().Notify(self:GetOwner(), "[Наручники] " .. tostring(reason or "Нет доступа."))
            HC().Emit(self:GetOwner(), "Error")
            return false
        end
    end

    return true
end

function SWEP:CanUseCuffs()
    if not SERVER then return false end
    if not HC() then return false end

    local ok, reason = HC().HasAccess(self:GetOwner())
    if not ok then
        HC().Notify(self:GetOwner(), "[Наручники] " .. tostring(reason or "Нет доступа."))
        HC().Emit(self:GetOwner(), "Error")
        return false
    end

    return true
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
    self:SetNextSecondaryFire(CurTime() + 0.5)

    if CLIENT then return end
    if not self:CanUseCuffs() then return end

    local owner = self:GetOwner()
    local target = HC().GetTracePlayer(owner, cfg().CuffDistance or 110)

    if not IsValid(target) then
        HC().Notify(owner, "[Наручники] Наведитесь на игрока.")
        HC().Emit(owner, "Error")
        return
    end

    if HC().IsCuffed(target) then
        HC().Emit(owner, "CuffStart")
        HC().Notify(owner, "[Наручники] Снимаем наручники...")
        HC().BeginTimedAction(owner, target, "uncuff", cfg().UncuffTime or 1.5, function(actor, ply)
            local ok = HC().HasAccess(actor)
            if not ok then return end
            HC().UncuffPlayer(actor, ply)
        end)
        return
    end

    local ok, reason = HC().CanCuffTarget(owner, target)
    if not ok then
        HC().Notify(owner, "[Наручники] " .. tostring(reason))
        HC().Emit(owner, "Error")
        return
    end

    HC().Emit(owner, "CuffStart")
    HC().Notify(owner, "[Наручники] Надеваем наручники...")
    HC().BeginTimedAction(owner, target, "cuff", cfg().CuffTime or 1.2, function(actor, ply)
        HC().CuffPlayer(actor, ply)
    end)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.6)

    if CLIENT then return end
    if not self:CanUseCuffs() then return end

    local owner = self:GetOwner()
    local target
    if owner.GRM_Captives then
        for captive in pairs(owner.GRM_Captives) do if IsValid(captive) and HC().IsCuffed(captive) then target = captive break end end
    end
    target = target or HC().GetTracePlayer(owner, cfg().DragDistance or 145)

    if not IsValid(target) or not HC().IsCuffed(target) then
        HC().Notify(owner, "[Наручники] Наведитесь на задержанного игрока.")
        return
    end

    if target:GetNWEntity("GRM_CuffDragger") == owner then
        HC().StopDragging(owner, target)
        HC().Notify(owner, "[Наручники] Вы отпустили задержанного.")
        return
    end

    HC().StartDragging(owner, target)
end

function SWEP:Reload()
    if (self.NextReload or 0) > CurTime() then return end
    self.NextReload = CurTime() + 0.8

    if CLIENT then return end
    if not self:CanUseCuffs() then return end

    local owner = self:GetOwner()
    local target = HC().GetTracePlayer(owner, cfg().CuffDistance or 110)

    if not IsValid(target) or not HC().IsCuffed(target) then
        HC().Notify(owner, "[Наручники] Наведитесь на задержанного игрока.")
        return
    end

    if owner:KeyDown(IN_WALK) then
        HC().ToggleBlindfold(owner, target)
    else
        HC().ToggleGag(owner, target)
    end
end
