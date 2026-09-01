--[[--------------------------------------------------------------------
    grm_comp_police — init.lua (Серверная часть)

    Терминал Полиции Порядка (Ordnungspolizei), гражданская юрисдикция.
    Общая серверная логика терминалов вынесена в
    lua/autorun/server/sv_grm_comp_terminal.lua — здесь только
    привязка сущности к юрисдикции "civil".
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompPolice_Open")
util.AddNetworkString("GRM_CompPolice_WantedAct")

-- Юрисдикция терминала: читается общим модулем sv_grm_comp_terminal.
ENT.Jurisdiction   = "civil"
ENT.TerminalName   = "Полиция Порядка"
ENT.AccessDeniedMsg = "Доступ к терминалу разрешён только служащим Ordnungspolizei."

function ENT:CanManage(ply)
    return GRM.CompTerminal and GRM.CompTerminal.CanManage(ply, self.Jurisdiction, self) or false
end

function ENT:Use(ply)
    if not GRM.CompTerminal then return end
    GRM.CompTerminal.Open(self, ply, "GRM_CompPolice_Open")
end
