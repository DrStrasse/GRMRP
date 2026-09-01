ENT.Type="anim"
ENT.Base="base_gmodentity"
ENT.PrintName="Ядро Цитадели — тёмная материя"
ENT.Category="GRM — Энергетика"
ENT.Spawnable=true
ENT.AdminOnly=true
function ENT:SetupDataTables()
 self:NetworkVar("Float",0,"Energy"); self:NetworkVar("Float",1,"MaxEnergy"); self:NetworkVar("Float",2,"Output"); self:NetworkVar("Float",3,"Heat"); self:NetworkVar("Float",4,"Stability"); self:NetworkVar("Bool",0,"Active"); self:NetworkVar("Bool",1,"Installed"); self:NetworkVar("String",0,"CoreID")
end
