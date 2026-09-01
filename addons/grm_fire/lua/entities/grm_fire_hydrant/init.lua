AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local A = GRM and GRM.FireAddon
    self:SetModel(A and A.SafeModel(A.Models.hydrant) or "models/props_pipes/valvewheel001.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetMaxHose() <= 0 then self:SetMaxHose((A and A.HoseCfg and A.HoseCfg.MaxLength) or 2200) end
    if self:GetPortsMax() <= 0 then self:SetPortsMax((A and A.HoseCfg and A.HoseCfg.HydrantPorts) or 2) end
    self:SetOpen(false)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local A = GRM and GRM.FireAddon
    local hose = ply.GRM_FireHose

    if IsValid(hose) then
        if hook.Run("GRM_FireAddon_HydrantUse", ply, self, true) == false then return end
        if hose:GetStartEnt() == self then
            if A and A.ReturnHose then A.ReturnHose(ply, hose) end
            return
        end
        local ok, err = hose:DockTo(self, ply)
        if not ok and ply.ChatPrint then ply:ChatPrint("[Рукав] " .. tostring(err or "стык не вышел")) end
        return
    end

    if hook.Run("GRM_FireAddon_HydrantUse", ply, self, not self:GetOpen()) == false then return end

    if not self:GetOpen() then
        self:SetOpen(true)
        self:EmitSound("ambient/machines/floodgate_stop1.wav", 70, 100)
        return
    end

    if A and A.TakeHose then
        local h, err = A.TakeHose(ply, self)
        if not h then
            -- порты заняты — закрыть
            if err == "нет свободных рукавов" then
                self:SetOpen(false)
                self:EmitSound("buttons/lever4.wav", 70, 100)
            elseif ply.ChatPrint then
                ply:ChatPrint("[Рукав] " .. tostring(err))
            end
        end
    end
end
