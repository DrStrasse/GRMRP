--[[--------------------------------------------------------------------
    GRM Net Console — пульт радиосети (Код 87)
    Компьютер оператора: работает, только если рядом (GRM.RadioNet.LinkDist)
    есть АКТИВНАЯ серверная стойка. E → окно пульта (суперадмин):
    идентификация устройств (позывные SPK-001/RAX-001/…), точечное
    вкл/выкл вывода, группы громкоговорителей, цель ГРОМКОЙ СВЯЗИ
    микрофона, оповещение по группе/городу, пеленг (дистанция/азимут/
    качество) и журнал событий сети.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Пульт радиосети GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_lab/monitor01a.mdl"
ENT.ModelFallback = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
