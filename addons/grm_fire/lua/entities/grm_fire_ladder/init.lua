AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local A = GRM and GRM.FireAddon
    self:SetModel(A and A.SafeModel(A.Models.ladder) or "models/props/de_train/ladderaluminium.mdl")
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(false)
    self:SetNotSolid(true)
    if not self:GetDeployed() then self:SetDeployed(true) end
end

function ENT:AttachToVehicle(veh, localPos, localAng)
    if not IsValid(veh) then return false end
    self:SetHostVehicle(veh)
    self:SetParent(veh)
    self:SetLocalPos(localPos or Vector(0, 50, 12))
    self:SetLocalAngles(localAng or Angle(0, 0, 0))
    self:SetDeployed(false)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetNotSolid(true)
    self._grmTruckGear = true
    self:SetNWBool("GRM_TruckGear", true)
    return true
end

function ENT:DetachFromVehicle()
    local veh = self:GetHostVehicle()
    self:SetParent(NULL)
    self:SetHostVehicle(NULL)
    self:SetDeployed(true)
    if IsValid(veh) then
        self:SetPos(veh:GetPos() + veh:GetRight() * 60 + Vector(0, 0, 8))
        self:SetAngles(Angle(0, veh:GetAngles().y, 0))
    end
    return true
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if hook.Run("GRM_FireAddon_LadderUse", ply, self) == false then return end

    if IsValid(self:GetHostVehicle()) then
        if ply:KeyDown(IN_SPEED) then
            self:DetachFromVehicle()
            if ply.ChatPrint then ply:ChatPrint("[Лестница] Снята с борта. E — взять в руки.") end
            return
        end
        local on = not self:GetDeployed()
        self:SetDeployed(on)
        if on then
            self:SetLocalPos(Vector(0, 78, 6))
            self:SetLocalAngles(Angle(-65, 0, 0))
        else
            self:SetLocalPos(Vector(0, 50, 12))
            self:SetLocalAngles(Angle(0, 0, 0))
        end
        self:EmitSound(on and "doors/door_metal_thin_open1.wav" or "doors/door_metal_thin_close2.wav", 65, 110)
        if ply.ChatPrint then
            ply:ChatPrint(on and "[Лестница] Выдвинута. W / прыжок — залезть. Shift+E — снять с борта."
                or "[Лестница] Убрана на борт.")
        end
        return
    end

    if ply:HasWeapon("weapon_grm_ladder") then
        if ply.ChatPrint then ply:ChatPrint("[Лестница] У вас уже есть лестница в руках.") end
        return
    end
    ply:Give("weapon_grm_ladder")
    ply:SelectWeapon("weapon_grm_ladder")
    self:Remove()
    if ply.ChatPrint then ply:ChatPrint("[Лестница] В руках. ЛКМ — поставить, ПКМ по машине — закрепить.") end
end
