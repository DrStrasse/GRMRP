--[[--------------------------------------------------------------------
    grm_comp_military_police — init.lua (Серверная часть)

    Терминал Полевой жандармерии (Feldgendarmerie), военная юрисдикция.
    Общая серверная логика вынесена в
    lua/autorun/server/sv_grm_comp_terminal.lua.
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompMilPolice_Open")
util.AddNetworkString("GRM_CompMilPolice_Act")

ENT.Jurisdiction    = "military"
ENT.TerminalName    = "Полевая жандармерия"
ENT.AccessDeniedMsg = "Доступ к терминалу разрешён только служащим Feldgendarmerie / военной комендатуры."

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("ПОЛЕВАЯ ЖАНДАРМЕРИЯ (Feldgendarmerie)")
    end
    if self:GetServiceProfile() == "" then
        self:SetServiceProfile(self:IsArmyDesk() and "army" or "gendarmerie")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

function ENT:CanManage(ply)
    return GRM.CompTerminal and GRM.CompTerminal.CanManage(ply, self.Jurisdiction, self) or false
end

function ENT:Use(ply)
    if not GRM.CompTerminal then return end
    GRM.CompTerminal.Open(self, ply, "GRM_CompMilPolice_Open")
end
