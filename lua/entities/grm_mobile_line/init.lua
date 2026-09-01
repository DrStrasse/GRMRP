AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetNoDraw(true)
    -- Код 88.3 (находка 105): константы NO_USE в GLua НЕ существует —
    -- SetUseType(nil) ронял Initialize, линия оставалась с LineState=""
    -- и все звонки вставали на «линия занята». Реальная константа: SIMPLE_USE.
    self:SetUseType(SIMPLE_USE)
    if self:GetExchangeID() == "" then self:SetExchangeID("cell") end
    if self:GetLineState() == "" then self:SetLineState("idle") end
    self.CurrentUser = nil -- держатель трубки (владелец с телефоном в руках/вызове)
end
