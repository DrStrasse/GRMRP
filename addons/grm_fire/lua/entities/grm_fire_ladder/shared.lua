ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM Пожарная лестница"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Deployed")
    self:NetworkVar("Entity", 0, "HostVehicle")
end

function ENT:LadderSegment()
    local mins, maxs = self:OBBMins(), self:OBBMaxs()
    local bottom = self:LocalToWorld(Vector(0, 0, mins.z))
    local top = self:LocalToWorld(Vector(0, 0, maxs.z))
    if top:DistToSqr(bottom) < 40 * 40 then
        top = self:GetPos() + self:GetUp() * 140
        bottom = self:GetPos()
    end
    if self.GetDeployed and self:GetDeployed() and IsValid(self:GetHostVehicle()) then
        bottom = self:GetPos()
        top = self:GetPos() + self:GetForward() * 80 + self:GetUp() * 130
    end
    return bottom, top
end
