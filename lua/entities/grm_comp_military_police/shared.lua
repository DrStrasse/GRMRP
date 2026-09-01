--[[--------------------------------------------------------------------
    grm_comp_military_police — Компьютер Полевой Жандармерии (Feldgendarmerie)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер Полевой Жандармерии (Feldgendarmerie)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ComputerName")
    self:NetworkVar("String", 1, "ServiceProfile")
end

function ENT:IsArmyDesk()
    local p = tostring(self.GetServiceProfile and self:GetServiceProfile() or "")
    if p == "army" then return true end
    local n = string.upper(tostring(self.GetComputerName and self:GetComputerName() or ""))
    return n:find("ВООРУЖ", 1, true) ~= nil or n:find("ARMED", 1, true) ~= nil
end
