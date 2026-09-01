AddCSLuaFile("shared.lua"); AddCSLuaFile("cl_init.lua"); include("shared.lua")
GRM=GRM or {}; GRM.DarkMatterCore=GRM.DarkMatterCore or {}
function ENT:Initialize()
 self:SetModel("models/props_combine/headcrabcannister01a.mdl"); self:PhysicsInit(SOLID_VPHYSICS); self:SetMoveType(MOVETYPE_NONE); self:SetSolid(SOLID_VPHYSICS); self:SetUseType(SIMPLE_USE); self:SetInstalled(false)
 self:SetMaxEnergy(100000); self:SetEnergy(75000); self:SetOutput(100); self:SetHeat(12); self:SetStability(98); self:SetActive(false); self:SetCoreID("CITADEL-"..self:EntIndex()); local p=self:GetPhysicsObject(); if IsValid(p) then p:EnableMotion(false); p:Sleep() end
end
function ENT:GetPermData() return {energy=self:GetEnergy(),maxEnergy=self:GetMaxEnergy(),output=self:GetOutput(),heat=self:GetHeat(),stability=self:GetStability(),active=self:GetActive(),installed=self:GetInstalled(),coreID=self:GetCoreID()} end
function ENT:ApplyPermData(d) if not istable(d) then return end; self:SetMaxEnergy(tonumber(d.maxEnergy) or self:GetMaxEnergy()); self:SetEnergy(math.Clamp(tonumber(d.energy) or self:GetEnergy(),0,self:GetMaxEnergy())); self:SetOutput(tonumber(d.output) or self:GetOutput()); self:SetHeat(math.Clamp(tonumber(d.heat) or self:GetHeat(),0,100)); self:SetStability(math.Clamp(tonumber(d.stability) or self:GetStability(),0,100)); self:SetInstalled(d.installed==true); self:SetActive(d.active==true and self:GetInstalled()); if self:GetInstalled() then self:SetModel("models/props_combine/coreball.mdl"); self:SetMoveType(MOVETYPE_NONE) else self:SetModel("models/props_combine/headcrabcannister01a.mdl") end end

function ENT:Install()
 if self:GetInstalled() then return end; self:SetInstalled(true); self:SetModel("models/props_combine/coreball.mdl"); self:PhysicsInit(SOLID_VPHYSICS); self:SetMoveType(MOVETYPE_NONE); self:SetActive(false); self:EmitSound("ambient/machines/combine_terminal_idle4.wav",70,90) end
function ENT:Think()
 if self:GetInstalled() and self:GetActive() then local o=math.Clamp(self:GetOutput(),0,1000); self:SetEnergy(math.min(self:GetMaxEnergy(),self:GetEnergy()+o*FrameTime())); self:SetHeat(math.Clamp(self:GetHeat()+o*.002*FrameTime()-.8*FrameTime(),0,100)); self:SetStability(math.Clamp(self:GetStability()-(self:GetHeat()>80 and .12 or -.04)*FrameTime(),0,100)); if self:GetHeat()>99 then self:SetActive(false); self:EmitSound("ambient/alarms/combine_bank_alarm_loop4.wav",75,100) end end; self:NextThink(CurTime()+.1); return true end
function ENT:ConsumeEnergy(a) a=math.max(0,tonumber(a) or 0); if not self:GetInstalled() or not self:GetActive() or self:GetEnergy()<a then return false end; self:SetEnergy(self:GetEnergy()-a); self:SetHeat(math.min(100,self:GetHeat()+a*.0005)); return true end
function ENT:AddEnergy(a) self:SetEnergy(math.Clamp(self:GetEnergy()+math.max(0,tonumber(a) or 0),0,self:GetMaxEnergy())) end
function ENT:Use(p) if IsValid(p) then local t=ents.FindByClass("grm_citadel_core_terminal")[1]; if IsValid(t) then t:Use(p) end end end
function GRM.DarkMatterCore.GetBest() local b; for _,e in ipairs(ents.FindByClass("grm_citadel_core")) do if e:GetInstalled() and e:GetActive() and (not b or e:GetEnergy()>b:GetEnergy()) then b=e end end; return b end
function GRM.DarkMatterCore.Request(a) local e=GRM.DarkMatterCore.GetBest(); return IsValid(e) and e:ConsumeEnergy(a) or false end
function GRM.DarkMatterCore.GetState() local e=GRM.DarkMatterCore.GetBest(); return IsValid(e) and {energy=e:GetEnergy(),max=e:GetMaxEnergy(),output=e:GetOutput(),heat=e:GetHeat(),stability=e:GetStability()} or nil end
