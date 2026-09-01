--[[--------------------------------------------------------------------
    GRM Mobile Line — виртуальная сотовая линия игрока (Код 88)
    Эндпоинт телефонной системы (sv_grm_phone) для мобильного телефона:
    существует, пока владелец онлайн И держит телефон в инвентаре.
    Позиция следует за владельцем (таймер модуля), визуала нет
    (SetNoDraw). Номер — 5-значный (мобильный диапазон), АТС = "cell".
    Прослушка (grm_phone_wiretap) ловит его звонки по номеру, как обычно.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Сотовая линия GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM Phone"
ENT.Spawnable = false
ENT.IsMobile  = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PhoneNumber")
    self:NetworkVar("String", 1, "DisplayName")
    self:NetworkVar("String", 2, "ExchangeID")
    self:NetworkVar("String", 3, "LineState")
    self:NetworkVar("String", 4, "OwnerSID64")
    self:NetworkVar("Entity", 0, "OtherPhone")
    self:NetworkVar("Int", 0, "CallID")
end
