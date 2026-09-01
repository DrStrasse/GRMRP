AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Console] ВНИМАНИЕ: модель пульта не найдена, фолбэк на '" .. tostring(mdl) .. "'")
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
    if activator:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    if not (GRM and GRM.RadioNet and GRM.RadioNet.ConsoleOpen) then return end
    if not activator:IsSuperAdmin() then
        if GRM.Notify then GRM.Notify(activator, "Доступ к пульту радиосети — только у суперадмина.", 255, 140, 110) end
        self:EmitSound("buttons/button10.wav", 60, 100)
        return
    end
    if not self:GetNWBool("GRM_RN_Online", false) then
        if GRM.Notify then GRM.Notify(activator, "Пульт ВНЕ СЕТИ: рядом нет активной серверной стойки — поставьте её рядом и включите (E).", 255, 140, 110) end
        self:EmitSound("buttons/button10.wav", 60, 100)
        return
    end
    self:EmitSound("buttons/button14.wav", 60, 100)
    GRM.RadioNet.ConsoleOpen(activator, self)
end
