ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Блок коммутации сигнализации"
ENT.Author = "GRM"
ENT.Category = "GRM Alarm"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DeviceID")
    self:NetworkVar("String", 1, "Label")
    self:NetworkVar("String", 2, "NetworkID")
    self:NetworkVar("String", 3, "OwnerSteam")
    self:NetworkVar("Int", 0, "Mode") -- 1 off 2 armed 3 passive
    self:NetworkVar("Bool", 0, "AlarmActive")
    self:NetworkVar("Bool", 1, "Permanent")
    self:NetworkVar("Int", 1, "SensorCount")
end
