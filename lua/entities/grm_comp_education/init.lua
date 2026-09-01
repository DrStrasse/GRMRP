--[[--------------------------------------------------------------------
    grm_comp_education — init.lua (Серверная часть)

    Компьютер деканата: открывает рабочее место учреждения образования.
    Права и данные — GRM.Education (lua/autorun/sh_grm_education.lua),
    источник истины по дипломам — GRM.Diplomas. Своей копии прав здесь
    намеренно нет.
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

--- Электроника: если компьютер обесточен, рабочее место не открывается.
function ENT:PoweredOn()
    if isfunction(self.GetDeviceActive) and self:GetDeviceActive() == false then return false end
    return true
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:PoweredOn() then
        if GRM.Notify then GRM.Notify(ply, "Компьютер обесточен", 255, 160, 90)
        else ply:ChatPrint("[Учреждение] Компьютер обесточен") end
        return
    end
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" and not GRM.CompAccess.Allowed(self, ply) then
        if GRM.Notify then GRM.Notify(ply, "Доступ к этому компьютеру закрыт для вашей организации.", 255, 120, 100) end
        return
    end
    if not (GRM.Education and isfunction(GRM.Education.Open)) then
        ply:ChatPrint("[Учреждение] Модуль образования не загружен")
        return
    end
    GRM.Education.Open(ply, self)
end
