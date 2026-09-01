ENT.Type="anim"; ENT.Base="base_gmodentity"; ENT.PrintName="Терминал Ядра Цитадели"; ENT.Category="GRM — Энергетика"; ENT.Spawnable=true; ENT.AdminOnly=true
function ENT:SetupDataTables() self:NetworkVar("Entity",0,"Core") end
