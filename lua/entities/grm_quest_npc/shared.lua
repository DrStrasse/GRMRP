ENT.Type="ai"
ENT.Base="base_ai"
ENT.PrintName="GRM Quest NPC"
ENT.Category="GRM — Quests"
ENT.Spawnable=false
ENT.AdminOnly=true
function ENT:SetupDataTables()
 self:NetworkVar("String",0,"QuestNPCID")
 self:NetworkVar("String",1,"QuestNPCName")
end
