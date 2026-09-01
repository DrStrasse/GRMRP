--[[--------------------------------------------------------------------
    grm_comp_military_police — Компьютер Полевой Жандармерии (Feldgendarmerie)
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
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

--[[ Станция описывается данными, механика — в grm_comp_base. ]]
ENT.DefaultComputerName = "ПОЛЕВАЯ ЖАНДАРМЕРИЯ (Feldgendarmerie)"
ENT.CompTitle    = "ПОЛЕВАЯ ЖАНДАРМЕРИЯ"
ENT.CompSubtitle = "Feldgendarmerie"
ENT.CompHint     = "Нажмите [E] для входа в систему"
ENT.CompColors = {
    bg    = Color(14, 22, 16, 240),
    title = Color(110, 220, 130),
    sub   = Color(220, 240, 225),
    hint  = Color(150, 190, 160),
}

--[[ Один класс обслуживает два стола: армейский и жандармский —
     их отличает IsArmyDesk(), и подписи должны отличаться тоже. ]]
function ENT:CompLabels()
    local army = self.IsArmyDesk and self:IsArmyDesk()
    local subtitle = tostring(self:GetComputerName() or "")
    if subtitle == "" then
        subtitle = army and "Служебный терминал" or self.CompSubtitle
    end
    return army and "ВООРУЖЁННЫЕ СИЛЫ" or self.CompTitle, subtitle, self.CompHint
end
