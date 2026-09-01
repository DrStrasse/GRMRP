--[[--------------------------------------------------------------------
    grm_money_press — банковский печатный станок (находка 178)
    Печатает деньги в ГОСБЮДЖЕТ (хранилище): базово 5000 GRM за 10 сек.
    Прокачка скорости увеличивает сумму за цикл. Перегрев — остановка,
    охлаждение через терминал. Управление — сотрудники банка
    (CanManageEconomy) и суперадмин.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Печатный станок (банк)"
ENT.Author    = "GRM"
ENT.Category  = "GRM — Банк"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/lt_c/sci_fi/hatch_frame.mdl"
ENT.ModelFallback = "models/props_lab/reciever01b.mdl"

ENT.BaseInterval  = 10     -- цикл печати, сек
ENT.BaseAmount    = 5000   -- 5000 GRM за цикл (минимум)
ENT.MaxSpeedLevel = 5
ENT.HeatPerPrint  = 6
ENT.OverheatAt    = 100
ENT.CoolPerSec    = 1
ENT.UpgradeBaseCost = 100000
ENT.CoolCost      = 5000
-- Находка 178b: станок печатает в БУФЕР и спавнит паллеты по 100.000
-- (максимум), игрок подносит паллету к хранилищу и загружает через E-меню.
ENT.BasePalletMax = 100000

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Broken")
    self:NetworkVar("Int", 0, "SpeedLevel")
    self:NetworkVar("Int", 1, "Heat")
    self:NetworkVar("Int", 2, "PrintAmount")
    self:NetworkVar("Int", 3, "TotalPrinted")
    self:NetworkVar("Int", 4, "PrintInterval")
    self:NetworkVar("Int", 5, "Buffer")
    self:NetworkVar("String", 0, "OwnerSID64")
    -- Находка 178d: точка выдачи паллет (суперадмин ставит тулом)
    self:NetworkVar("Vector", 0, "SpawnPos")
    self:NetworkVar("Angle", 0, "SpawnAngle")
    self:NetworkVar("Bool", 2, "HasCustomSpawn")
end
