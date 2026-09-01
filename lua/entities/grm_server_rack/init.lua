AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Rack] ВНИМАНИЕ: модель стойки не найдена, фолбэк на '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end

    if self:GetNWBool("GRM_RN_Set", false) == false then
        self:SetNWBool("GRM_RN_On", true)       -- по умолчанию питание включено
        self:SetNWBool("GRM_RN_Set", true)
    end
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    local on = not self:GetNWBool("GRM_RN_On", true)
    self:SetNWBool("GRM_RN_On", on)
    self:EmitSound(on and "buttons/button9.wav" or "buttons/button18.wav", 65, 100)
    if GRM and GRM.RadioNet and GRM.RadioNet.Recompute then GRM.RadioNet.Recompute() end
    if GRM.Notify then
        GRM.Notify(activator,
            on and "Стойка ВКЛЮЧЕНА: сеть активна, оборудование в радиусе связи работает."
                or "Стойка ВЫКЛЮЧЕНА: антенны/передатчики/громкоговорители рядом — вне сети!",
            on and 100 or 255, on and 220 or 140, 90)
    end
end
