ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM Насос (машина)"
ENT.Author = "GRM"
ENT.Category = "GRM Fire"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.AutomaticFrameAdvance = false

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "PumpOn")
    self:NetworkVar("Bool", 1, "Filling")
    self:NetworkVar("Bool", 2, "HydrantFeed")
    self:NetworkVar("Int", 0, "Tank")
    self:NetworkVar("Int", 1, "TankMax")
    self:NetworkVar("Int", 2, "MaxHose")
    self:NetworkVar("Int", 3, "HosesOut")
    self:NetworkVar("Int", 4, "HosesMax")
    self:NetworkVar("Int", 5, "Foam")
    self:NetworkVar("Int", 6, "FoamMax")
    self:NetworkVar("Int", 7, "Powder")
    self:NetworkVar("Int", 8, "PowderMax")
    self:NetworkVar("Entity", 0, "HostVehicle")
    self:NetworkVar("String", 0, "Agent")
end

function ENT:GetWater()
    return self:GetTank()
end

function ENT:SetWater(n)
    self:SetTank(n)
end

function ENT:GetWaterMax()
    return self:GetTankMax()
end

function ENT:SetWaterMax(n)
    self:SetTankMax(n)
end
