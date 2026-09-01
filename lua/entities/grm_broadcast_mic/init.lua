AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Mic] ВНИМАНИЕ: модель микрофона не найдена (нет аддона Black Ops Interrogation Room), фолбэк на '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end

    self.BCLive = false
    self.BCSpeaker = nil
    local station = (GRM and GRM.Broadcast and GRM.Broadcast.MicName) and GRM.Broadcast.MicName(self) or "ГРМ-Радио"
    self:SetNWString("GRM_BC_Station", station)
    self:SetNWBool("GRM_BC_Live", false)
    self:SetNWString("GRM_BC_Speaker", "")
    self:SetNWString("GRM_BC_Last", "")
    self:SetNWBool("GRM_BC_PA", false)   -- режим громкой связи (Код 85)
    self:SetNWInt("GRM_RN_Link", -1)     -- -1 = радиосеть не отвечала (модуль снят)
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > 200 * 200 then return end
    if not (GRM and GRM.Broadcast) then return end
    if not GRM.Broadcast.IsJournalist(activator) then
        if GRM.Notify then GRM.Notify(activator, "Нет доступа к микрофону (СМИ/журналисты; доступ: /bcast_allow Фракция у суперадмина).", 255, 120, 90) end
        return
    end
    GRM.Broadcast.OpenMicMenu(activator, self)
end

function ENT:OnRemove()
    if GRM and GRM.Broadcast and GRM.Broadcast.StopLive and self.BCLive then
        GRM.Broadcast.StopLive(self, "микрофон демонтирован")
    end
end
