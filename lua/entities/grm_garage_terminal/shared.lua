--[[--------------------------------------------------------------------
    grm_garage_terminal — стойка вызова гаража

    Ставится тулом «GRM: гаражи» и хранится ВНУТРИ записи гаража
    (data/grm_garage/<карта>.json), поэтому не требует перм-пропа: гараж
    поднимает свои стойки сам при старте карты и после очистки.
    E у стойки открывает меню гаража, к которому она привязана.
----------------------------------------------------------------------]]
ENT.Type           = "anim"
ENT.Base           = "base_gmodentity"
ENT.PrintName      = "Стойка гаража GRM"
ENT.Author         = "GRM"
ENT.Category       = "GRM — RP"
ENT.Spawnable      = false
ENT.AdminOnly      = true
ENT.RenderGroup    = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "GarageID")
    self:NetworkVar("String", 1, "GarageName")
    self:NetworkVar("String", 2, "TerminalID")
end
