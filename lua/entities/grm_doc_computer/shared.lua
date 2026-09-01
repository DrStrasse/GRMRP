--[[--------------------------------------------------------------------
    grm_doc_computer — Служебный Компьютер Оформления Документов
    Модель: models/props/cs_office/computer.mdl

    Функционал:
      • Паспортный стол: Оформление и выдача паспортов гражданам
      • Отдел кадров: Оформление и выдача служебных удостоверений сотрудникам
      • Документы прикрытия: Фабрикация легендированных ксив для спецслужб
      • Реестр и архив: Просмотр базы документов, аннулирование, перевыпуск
      • Настройка корочки ведомства: Служебный префикс жетона, цвет, тиснение
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "base_gmodentity"
ENT.PrintName     = "Компьютер оформления документов"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props/cs_office/computer.mdl"
ENT.ModelFallback = "models/props_lab/monitor02.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ComputerName")
end
