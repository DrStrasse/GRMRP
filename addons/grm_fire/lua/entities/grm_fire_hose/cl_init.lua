include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-2200, -2200, -128), Vector(2200, 2200, 256))
end

function ENT:Draw()
    local A = GRM and GRM.FireAddon
    if A and A.DrawAllHoses then return end
end

function ENT:OnRemove()
    local A = GRM and GRM.FireAddon
    if A and A.HosePaths then A.HosePaths[self:EntIndex()] = nil end
end
