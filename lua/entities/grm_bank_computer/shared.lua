--[[--------------------------------------------------------------------
    grm_bank_computer — Компьютер Управления (Банк)
    Модель: models/props/cs_office/computer.mdl
    Связан с:
      • Хранилищами банка (grm_bank_vault)
      • Печатным станком (grm_money_press)
      • Терминалом станка (grm_money_press_terminal)
    Функции управляющего:
      • Зачисление средств из хранилищ в госбюджет
      • Выделение средств из госбюджета в хранилище (для инкассации/наличных)
      • Перевод из хранилища в бюджет конкретной фракции
      • Перевод из госбюджета в бюджет фракции (субсидия)
      • Мониторинг и управление печатным станком
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер Управления (Банк)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — Банк"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ComputerName")
end
