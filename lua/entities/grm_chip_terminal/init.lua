AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_ChipControl_Open")

function ENT:Initialize()
    self:SetModel("models/props_combine/combine_interface001.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetNWString("TerminalName", "Терминал контроля чипов")
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    if GRM.ChipControl and GRM.ChipControl.OpenTerminalMenu then
        -- клиентская функция откроет меню и запросит данные
        net.Start("GRM_ChipControl_Open")
        net.Send(ply)
    end
end

function ENT:OnTakeDamage(dmg)
    self:TakePhysicsDamage(dmg)
end
