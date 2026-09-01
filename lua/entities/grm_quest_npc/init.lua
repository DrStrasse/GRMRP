AddCSLuaFile("shared.lua");AddCSLuaFile("cl_init.lua");include("shared.lua")
function ENT:Initialize()
 if self:GetModel()==""or self:GetModel()=="models/error.mdl"then self:SetModel("models/Humans/Group01/Male_07.mdl")end
 self:SetHullType(HULL_HUMAN);self:SetHullSizeNormal();self:SetNPCState(NPC_STATE_SCRIPT);self:SetSolid(SOLID_BBOX);self:SetMoveType(MOVETYPE_NONE);self:SetUseType(SIMPLE_USE);self:CapabilitiesClear();self:SetMaxHealth(1000000);self:SetHealth(1000000);self:DropToFloor()
 if self:GetQuestNPCID()==""then self:SetQuestNPCID("npc_"..self:EntIndex())end;if self:GetQuestNPCName()==""then self:SetQuestNPCName("Персонаж")end
end
function ENT:Use(ply)if GRM and GRM.Quests then GRM.Quests.OpenNPC(ply,self)end end
function ENT:OnTakeDamage(dmg)if dmg and dmg.SetDamage then dmg:SetDamage(0)end;return 0 end
