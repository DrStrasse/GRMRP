--[[--------------------------------------------------------------------
    GRM Jobs — терминал «Биржа труда» (Код 77)
    E → меню вакансий (курьер/патруль/грузчик/инспектор + заказы фракций).
    Лидер фракции с доступом «БИРЖА» (/factions → «Доступы») публикует
    собственные заказы — награда эскроуируется с бюджета фракции.
    Спавн: /jobcenter_add (суперадмин), автоперсистентность.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Биржа труда GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model          = "models/lt_c/holo_wall_unit.mdl"
ENT.ModelFallback  = "models/props_wasteland/controlroom_console001a.mdl"
ENT.ModelFallback2 = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables() end
