--[[--------------------------------------------------------------------
    GRM Alarm Speaker — динамик сирены (Код 89)
    Звучит, пока активна тревога в его сети (NetworkID совпадает
    с блоком коммутации сигнализации). Active=false — динамик отключён.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Динамик сирены (сигнализация)"
ENT.Author    = "GRM"
ENT.Category  = "GRM Alarm"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/props_wasteland/speakercluster01a.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DeviceID")
    self:NetworkVar("String", 1, "Label")
    self:NetworkVar("String", 2, "NetworkID")
    self:NetworkVar("String", 3, "OwnerSteam")
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Permanent")
end
