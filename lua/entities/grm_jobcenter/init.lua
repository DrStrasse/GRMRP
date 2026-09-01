AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Jobs] ВНИМАНИЕ: модель терминала не найдена, фолбэк '" .. tostring(mdl) .. "'")
        if not util.IsValidModel(mdl) then
            mdl = self.ModelFallback2
            print("[GRM Jobs] ВНИМАНИЕ: и фолбэк-1 не найден, фолбэк '" .. tostring(mdl) .. "'")
        end
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    if (self._grmJobsUseT or 0) > CurTime() then return end -- антиспам E 0.8 с
    self._grmJobsUseT = CurTime() + 0.8
    if not (GRM and GRM.Jobs and GRM.Jobs.OpenMenu) then return end
    GRM.Jobs.OpenMenu(activator, self)
end
