--[[--------------------------------------------------------------------
    grm_comp_military_police — init.lua (Серверная часть)

    Терминал Полевой жандармерии (Feldgendarmerie), военная юрисдикция.
    Общая серверная логика вынесена в
    lua/autorun/server/sv_grm_comp_terminal.lua.
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

--[[ Профиль службы отличает армейский стол от жандармского и влияет на
     доступ и набор вкладок. Ставится один раз при появлении энтити, если
     его не задал инструмент размещения. Раньше это жило внутри копии
     ENT:Initialize; теперь Initialize общий, а специфика станции — здесь. ]]
function ENT:OnCompInit()
    if self:GetServiceProfile() == "" then
        self:SetServiceProfile(self:IsArmyDesk() and "army" or "gendarmerie")
    end
end

util.AddNetworkString("GRM_CompMilPolice_Open")
util.AddNetworkString("GRM_CompMilPolice_Act")

ENT.Jurisdiction    = "military"
ENT.TerminalName    = "Полевая жандармерия"
ENT.AccessDeniedMsg = "Доступ к терминалу разрешён только служащим Feldgendarmerie / военной комендатуры."

function ENT:CanManage(ply)
    return GRM.CompTerminal and GRM.CompTerminal.CanManage(ply, self.Jurisdiction, self) or false
end

function ENT:Use(ply)
    if not GRM.CompTerminal then return end
    GRM.CompTerminal.Open(self, ply, "GRM_CompMilPolice_Open")
end
