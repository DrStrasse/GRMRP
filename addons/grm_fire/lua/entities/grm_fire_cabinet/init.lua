AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local A = GRM and GRM.FireAddon
    self:SetModel(A and A.SafeModel(A.Models.cabinet) or "models/props_c17/canister01a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetStock() <= 0 then self:SetStock(8) end
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if hook.Run("GRM_FireAddon_CabinetUse", ply, self) == false then return end
    local A = GRM and GRM.FireAddon
    if not A then return end
    if ply:HasWeapon("weapon_extinguisher") then
        A.Refill(ply, 250)
        self:EmitSound("ambient/water/leak_1.wav", 60, 120)
        return
    end
    if self:GetStock() <= 0 then
        self:EmitSound("buttons/button10.wav", 60, 90)
        return
    end
    if A.GiveExtinguisher(ply) then
        self:SetStock(math.max(0, self:GetStock() - 1))
        self:EmitSound("items/ammo_pickup.wav", 65, 100)
    end
end
