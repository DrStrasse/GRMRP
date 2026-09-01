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
