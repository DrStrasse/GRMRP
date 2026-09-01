ENT.Type="anim";ENT.Base="base_gmodentity";ENT.PrintName="Коробка с мусором";ENT.Category="GRM — Работы";ENT.Spawnable=false
function ENT:SetupDataTables()self:NetworkVar("Entity",0,"Carrier");self:NetworkVar("String",0,"SourcePointID")end
