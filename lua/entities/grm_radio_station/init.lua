AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM RStation] ВНИМАНИЕ: модель передатчика не найдена, фолбэк на '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    self:SetNWBool("GRM_RN_Online", false)
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local on = self:GetNWBool("GRM_RN_Online", false)
    local link = (GRM and GRM.RadioNet and GRM.RadioNet.LinkDist) or 700
    if GRM.Notify then
        GRM.Notify(activator,
            on and "Передатчик В СЕТИ: микрофоны в радиусе связи могут вещать на город."
                or ("Передатчик ВНЕ СЕТИ: нужна ВКЛЮЧЁННАЯ стойка в пределах " .. tostring(link) .. " юнитов."),
            on and 100 or 255, on and 220 or 150, 90)
    end
end
