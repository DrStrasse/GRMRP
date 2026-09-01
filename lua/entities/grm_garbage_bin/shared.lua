ENT.Type="anim";ENT.Base="base_gmodentity";ENT.PrintName="Мусорный контейнер GRM";ENT.Category="GRM — Работы";ENT.Spawnable=false;ENT.AdminOnly=true
function ENT:SetupDataTables()self:NetworkVar("Float",0,"ReadyAt");self:NetworkVar("String",0,"BinName")end
