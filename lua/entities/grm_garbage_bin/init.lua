AddCSLuaFile("shared.lua");AddCSLuaFile("cl_init.lua");include("shared.lua")
function ENT:Initialize()self:SetModel("models/props_junk/trashdumpster01a.mdl");self:PhysicsInit(SOLID_VPHYSICS);self:SetMoveType(MOVETYPE_VPHYSICS);self:SetSolid(SOLID_VPHYSICS);self:SetUseType(SIMPLE_USE);if self:GetBinName()==""then self:SetBinName("Мусорный контейнер")end;local ph=self:GetPhysicsObject();if IsValid(ph)then ph:Wake()end end
function ENT:Use(ply)if GRM.Jobs and GRM.Jobs.SearchGarbageBin then GRM.Jobs.SearchGarbageBin(ply,self)end end
