AddCSLuaFile("shared.lua");AddCSLuaFile("cl_init.lua");include("shared.lua")
function ENT:Initialize()self:SetModel("models/props/cs_office/cardboard_box03.mdl");self:SetMoveType(MOVETYPE_NONE);self:SetSolid(SOLID_NONE);self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)end
function ENT:AttachTo(ply)if not IsValid(ply)then return false end;self:SetCarrier(ply);self:SetParent(ply);self:SetLocalPos(Vector(22,0,42));self:SetLocalAngles(Angle(0,90,0));ply:SetNWEntity("GRM_GarbageBox",self);return true end
function ENT:Think()local p=self:GetCarrier();if not IsValid(p)or not p:Alive()then self:Remove()return end;self:NextThink(CurTime()+.5);return true end
function ENT:OnRemove()local p=self:GetCarrier();if IsValid(p)and p:GetNWEntity("GRM_GarbageBox")==self then p:SetNWEntity("GRM_GarbageBox",NULL)end end
