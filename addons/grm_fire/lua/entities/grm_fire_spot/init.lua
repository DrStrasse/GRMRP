AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_junk/PopCan01a.mdl")
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetCollisionBounds(Vector(-10, -10, -2), Vector(10, 10, 20))
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(false)
    -- без NoDraw: иначе клиент не рисует маркер, когда в руках тул
    -- без NotSolid: иначе R/ПКМ тула не попадают в точку
    if self:GetWeight() <= 0 then self:SetWeight(1) end
    if self:GetSpotLabel() == "" then self:SetSpotLabel("очаг") end
    if self:GetFeed() <= 0 then self:SetFeed(180) end
    if self.SetSpotOn then self:SetSpotOn(true) end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    hook.Run("GRM_FireAddon_SpotUse", ply, self)
end

function ENT:CanIgnite()
    if self.GetSpotOn and self:GetSpotOn() == false then return false, "точка выключена" end
    if GRM and GRM.Fire and GRM.Fire.IsBurning and GRM.Fire.IsBurning(self:GetPos()) then
        return false, "уже горит"
    end
    return true
end

function ENT:IgniteSpot(feed, starter)
    local ok, why = self:CanIgnite()
    if not ok then return nil, why end
    feed = tonumber(feed) or (self.GetFeed and self:GetFeed()) or 180
    if feed < 40 then feed = 180 end
    self:SetLastIgnite(os.time())
    hook.Run("GRM_FireAddon_SpotIgnite", self, feed, starter)
    if vFireInstalled and CreateVFire then
        local pos = self:GetPos()
        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 8),
            endpos = pos - Vector(0, 0, 48),
            filter = self,
        })
        local hit = tr.Hit and tr.HitPos or pos
        local nrm = tr.Hit and tr.HitNormal or Vector(0, 0, 1)
        local parent = (tr.Hit and IsValid(tr.Entity) and tr.Entity) or game.GetWorld()
        local fire = CreateVFire(parent, hit, nrm, feed, starter)
        if IsValid(fire) then
            fire._grmStarted = os.time()
            fire._grmSource = (starter == "system" or starter == "random") and "random" or "admin"
            fire._grmStarter = tostring(starter or "")
        end
        return fire
    end
    return nil, "vFire не загружен"
end
