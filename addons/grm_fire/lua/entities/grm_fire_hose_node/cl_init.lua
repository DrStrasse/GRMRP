include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-128, -128, -24), Vector(128, 128, 48))
end

function ENT:Draw()
end

function ENT:DrawTranslucent()
end
