ENT.Type="anim"
ENT.Base="base_gmodentity"
ENT.PrintName="Гражданский транспортный компьютер"
ENT.Author="GRM"
ENT.Category="GRM — RP"
ENT.Spawnable=true
ENT.AdminSpawnable=true
ENT.RenderGroup=RENDERGROUP_BOTH
ENT.Model="models/props_lab/monitor02.mdl"
function ENT:SetupDataTables()self:NetworkVar("String",0,"ComputerName")end
