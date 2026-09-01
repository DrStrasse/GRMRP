--[[--------------------------------------------------------------------
    grm_bank_vault — банковское хранилище (находка 178)
    Отражает ГОСБЮДЖЕТ сервера в реальном времени: дисплей «В ГОСБЮДЖЕТЕ
    СЕЙЧАС: N». Вместимость физических денег (паллет) — 500.000 GRM.
    Пополнение/изъятие гос.бюджета из панели «Экономика» и печать станка
    дропают паллеты денег (grm_vault_cash) в хранилище.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Банковское хранилище"
ENT.Author    = "GRM"
ENT.Category  = "GRM — Банк"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/lt_c/sci_fi/ground_locker_small.mdl"
ENT.ModelFallback = "models/props_lab/reciever_cart.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "StateBudget") -- зеркало гос.бюджета (сервер синкает)
    self:NetworkVar("Int", 1, "HeldCash")    -- физически лежащие паллеты
    self:NetworkVar("Int", 2, "Capacity")    -- вместимость (500.000)
end
