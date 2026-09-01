AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback2 end
    if mdl ~= self.Model then
        print("[GRM Antenna] ВНИМАНИЕ: основная модель антенны не найдена, фолбэк на '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    self:SetNWBool("GRM_RN_Linked", false)
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 220 * 220 then return end
    local linked = self:GetNWBool("GRM_RN_Linked", false)
    local range = (GRM and GRM.RadioNet and GRM.RadioNet.AntennaRange) or 3200
    local link = (GRM and GRM.RadioNet and GRM.RadioNet.LinkDist) or 700
    if GRM.Notify then
        GRM.Notify(activator,
            linked and ("Антенна СВЯЗАНА с активной стойкой: усиливает сеть на " .. tostring(range) .. " юнитов вокруг.")
                or ("Антенна НЕ связана: поставьте в пределах " .. tostring(link) .. " юнитов от ВКЛЮЧЁННОЙ стойки (/rack_add)."),
            linked and 100 or 255, linked and 220 or 150, 90)
    end
end
