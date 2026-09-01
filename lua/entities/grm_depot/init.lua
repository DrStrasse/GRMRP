AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Jobs] ВНИМАНИЕ: модель точки не найдена, фолбэк '" .. tostring(mdl) .. "'")
        if not util.IsValidModel(mdl) then
            mdl = self.ModelFallback2
            print("[GRM Jobs] ВНИМАНИЕ: и фолбэк-1 не найден, фолбэк '" .. tostring(mdl) .. "'")
        end
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end
