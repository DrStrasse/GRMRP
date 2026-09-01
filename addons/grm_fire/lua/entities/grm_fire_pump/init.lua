AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local WATER_MAX, FOAM_MAX, POWDER_MAX = 4000, 500, 250

function ENT:Initialize()
    local A = GRM and GRM.FireAddon
    self:SetModel(A and A.SafeModel(A.Models.pump) or "models/props_lab/tpplugholder_single.mdl")
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-18, -18, -10), Vector(18, 18, 20))
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(false)
    self:SetNotSolid(false)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(70, 190, 255, 140))
    local tmax = self:GetTankMax()
    if tmax <= 0 or tmax > 20000 then self:SetTankMax(WATER_MAX) end
    if self:GetTank() < 0 or self:GetTank() > self:GetTankMax() then
        self:SetTank(self:GetTankMax())
    end
    if self:GetFoamMax() <= 0 or self:GetFoamMax() > 5000 then self:SetFoamMax(FOAM_MAX) end
    if self:GetFoam() < 0 or self:GetFoam() > self:GetFoamMax() then self:SetFoam(self:GetFoamMax()) end
    if self:GetPowderMax() <= 0 or self:GetPowderMax() > 5000 then self:SetPowderMax(POWDER_MAX) end
    if self:GetPowder() < 0 or self:GetPowder() > self:GetPowderMax() then self:SetPowder(self:GetPowderMax()) end
    if self:GetMaxHose() <= 0 then self:SetMaxHose((A and A.HoseCfg and A.HoseCfg.MaxLength) or 2200) end
    if self:GetHosesMax() <= 0 then self:SetHosesMax((A and A.HoseCfg and A.HoseCfg.TruckSlots) or 4) end
    self:SetHosesOut(0)
    if self:GetAgent() == "" then self:SetAgent("water") end
    self:SetPumpOn(false)
    self:SetFilling(false)
    self:SetHydrantFeed(false)
end

function ENT:AttachToVehicle(veh, localPos, localAng)
    if not IsValid(veh) then return false end
    self:SetHostVehicle(veh)
    self:SetParent(veh)
    self:SetLocalPos(localPos or Vector(0, -46, 16))
    self:SetLocalAngles(localAng or Angle(0, 90, 0))
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-18, -18, -10), Vector(18, 18, 20))
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetNotSolid(false)
    self:DrawShadow(false)
    return true
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if hook.Run("GRM_FireAddon_PumpUse", ply, self) == false then return end
    local A = GRM and GRM.FireAddon
    local hose = ply.GRM_FireHose

    if IsValid(hose) then
        if hose:GetStartEnt() == self then
            if A and A.ReturnHose then A.ReturnHose(ply, hose) end
            if ply.ChatPrint then ply:ChatPrint("[Рукав] Смотан на катушку.") end
            return
        end
        local ok, err = hose:DockTo(self, ply)
        if not ok and ply.ChatPrint then ply:ChatPrint("[Рукав] " .. tostring(err or "стык не вышел")) end
        return
    end

    if A and A.TakeHose then
        local h, err = A.TakeHose(ply, self)
        if h then
            self:SetHosesOut(A.HoseCountOn(self))
            return
        end
        if err == "нет свободных рукавов" then
            self:SetPumpOn(not self:GetPumpOn())
            self:EmitSound(self:GetPumpOn() and "ambient/machines/floodgate_stop1.wav" or "buttons/lever4.wav", 70, 95)
            return
        end
        if ply.ChatPrint then ply:ChatPrint("[Рукав] " .. tostring(err)) end
    end
end

function ENT:FindLinkedHydrant()
    for _, h in ipairs(ents.FindInSphere(self:GetPos(), 380)) do
        if IsValid(h) and h:GetClass() == "grm_fire_hydrant" and h.GetOpen and h:GetOpen() then
            return h
        end
    end
    for _, hose in ipairs(ents.FindByClass("grm_fire_hose")) do
        if not IsValid(hose) then
        else
            local start = hose.GetStartEnt and hose:GetStartEnt() or NULL
            local endN = hose.GetEndNode and hose:GetEndNode() or NULL
            local parent = IsValid(endN) and endN.GetParent and endN:GetParent() or NULL
            if start == self and IsValid(parent) and parent:GetClass() == "grm_fire_hydrant" and parent.GetOpen and parent:GetOpen() then
                return parent
            end
            if IsValid(start) and start:GetClass() == "grm_fire_hydrant" and start.GetOpen and start:GetOpen() then
                if parent == self then return start end
            end
        end
    end
    return nil
end

function ENT:FindLinkedCabinet()
    for _, c in ipairs(ents.FindInSphere(self:GetPos(), 160)) do
        if IsValid(c) and c:GetClass() == "grm_fire_cabinet" then return c end
    end
    return nil
end

function ENT:SyncHost()
    local veh = self:GetHostVehicle()
    if not IsValid(veh) then veh = self:GetParent() end
    if not IsValid(veh) or not veh.SetNWInt then return end
    veh:SetNWInt("GRM_FireTank", self:GetTank())
    veh:SetNWInt("GRM_FireTankMax", self:GetTankMax())
    veh:SetNWInt("GRM_FireFoam", self:GetFoam())
    veh:SetNWInt("GRM_FireFoamMax", self:GetFoamMax())
    veh:SetNWInt("GRM_FirePowder", self:GetPowder())
    veh:SetNWInt("GRM_FirePowderMax", self:GetPowderMax())
    veh:SetNWString("GRM_FireAgent", self:GetAgent() or "water")
end

function ENT:Consume(amount, agent)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true end
    agent = tostring(agent or self:GetAgent() or "water")
    if agent == "water" and self:GetHydrantFeed() and IsValid(self:FindLinkedHydrant()) then
        return true
    end
    local have, setfn
    if agent == "foam" then
        have, setfn = self:GetFoam(), function(n) self:SetFoam(n) end
    elseif agent == "powder" then
        have, setfn = self:GetPowder(), function(n) self:SetPowder(n) end
    else
        have, setfn = self:GetTank(), function(n) self:SetTank(n) end
        agent = "water"
    end
    have = math.max(0, tonumber(have) or 0)
    if have < amount then
        setfn(0)
        if have <= 0 then self:SetPumpOn(false) end
        self:SyncHost()
        return false
    end
    setfn(have - amount)
    self:SyncHost()
    return true
end

function ENT:FillAgent(agent, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    agent = tostring(agent or "water")
    if agent == "foam" then
        self:SetFoam(math.min(self:GetFoamMax(), self:GetFoam() + amount))
        return self:GetFoam()
    end
    if agent == "powder" then
        self:SetPowder(math.min(self:GetPowderMax(), self:GetPowder() + amount))
        return self:GetPowder()
    end
    self:SetTank(math.min(self:GetTankMax(), self:GetTank() + amount))
    return self:GetTank()
end

function ENT:DrainAgent(agent, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    agent = tostring(agent or "water")
    if agent == "foam" then
        self:SetFoam(math.max(0, self:GetFoam() - amount))
        return self:GetFoam()
    end
    if agent == "powder" then
        self:SetPowder(math.max(0, self:GetPowder() - amount))
        return self:GetPowder()
    end
    self:SetTank(math.max(0, self:GetTank() - amount))
    return self:GetTank()
end

function ENT:Fill(amount)
    return self:FillAgent("water", amount)
end

function ENT:OnRemove()
    local A = GRM and GRM.FireAddon
    if A and A.ClearHosesOn then A.ClearHosesOn(self) end
end

function ENT:Think()
    if self._grmTruckGear or self:GetNWBool("GRM_TruckGear", false) then
        local host = self:GetHostVehicle()
        if not IsValid(host) then host = self:GetParent() end
        if not IsValid(host) then
            self:Remove()
            return
        end
    end
    if self:GetFilling() then
        local agent = self:GetAgent()
        if agent == "" then agent = "water" end
        if agent == "powder" then
            if IsValid(self:FindLinkedCabinet()) then
                self:FillAgent("powder", 8)
            else
                self:SetFilling(false)
            end
        else
            if IsValid(self:FindLinkedHydrant()) then
                self:FillAgent(agent, agent == "foam" and 12 or 40)
            else
                self:SetFilling(false)
            end
        end
        self:SyncHost()
    end
    if GRM and GRM.FireAddon and GRM.FireAddon.HoseCountOn then
        self:SetHosesOut(GRM.FireAddon.HoseCountOn(self))
    end
    self:NextThink(CurTime() + 0.25)
    return true
end
