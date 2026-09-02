--[[--------------------------------------------------------------------
    grm_lab_base — серверная часть базы лабораторий.
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(self.LabModel or "models/props_wasteland/laundry_washer003.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    -- Тип задаётся профилем станции в shared.lua; фолбэк — на случай
    -- сущности без профиля (ни одна штатная лаборатория в него не попадает)
    if not self.LabType then
        self.LabType = "narc"
    end
    self:SetNWString("LabType", self.LabType)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local labType = self.LabType or "narc"
    if GRM and GRM.NarcCraft and GRM.NarcCraft.OpenLab then
        GRM.NarcCraft.OpenLab(ply, labType, self)
    else
        ply:ChatPrint("[Лаборатория] Модуль крафта ещё не загружен")
    end
end
