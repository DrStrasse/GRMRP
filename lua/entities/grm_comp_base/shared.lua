--[[--------------------------------------------------------------------
    grm_comp_base — база служебных компьютеров GRM.

    Одиннадцать станций (мэрия, юстиция, полиция, медицина, армия,
    жандармерия, госбезопасность, пожарные, образование, автоинспекция,
    гражданский терминал) были одиннадцатью копиями одного и того же:
      * ENT:Initialize — модель, физика, SIMPLE_USE, имя по умолчанию;
      * ENT:Draw — DrawModel + табличка 3D2D из трёх строк;
      * ENT:SetupDataTables — NetworkVar ComputerName.
    Отличались только подписями и цветами.

    Отдельно про кадры (§6.1.8): каждая копия `Draw` создавала по ЧЕТЫРЕ
    `Color()` на кадр, а `RenderGroup = RENDERGROUP_BOTH` рисует энтити
    дважды. Одиннадцать станций на карте — под сотню лишних таблиц в
    кадр на пустом месте. Здесь цвета создаются ОДИН раз при загрузке
    файла, а в кадре остаётся только чтение полей.

    Как заводится новая станция:
        ENT.Base = "grm_comp_base"
        ENT.DefaultComputerName = "…"        -- имя, если не задано инструментом
        ENT.CompTitle / CompSubtitle / CompHint
        ENT.CompColors = { bg =, title =, sub =, hint = }
    Динамические подписи — переопределить ENT:CompLabels().
----------------------------------------------------------------------]]
ENT.Type           = "anim"
ENT.Base           = "base_gmodentity"
ENT.PrintName      = "GRM — служебный компьютер (база)"
ENT.Author         = "GRM"
ENT.Category       = "GRM — RP"
ENT.Spawnable      = false
ENT.AdminSpawnable = false
ENT.RenderGroup    = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor02.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

ENT.DefaultComputerName = ""
ENT.CompTitle    = "СЛУЖЕБНЫЙ ТЕРМИНАЛ"
ENT.CompSubtitle = ""
ENT.CompHint     = "Нажмите [E] для входа в систему"

-- Палитра по умолчанию. Создаётся один раз на файл, не на кадр.
ENT.CompColors = {
    bg    = Color(18, 22, 32, 240),
    title = Color(120, 200, 255),
    sub   = Color(225, 230, 235),
    hint  = Color(160, 175, 190),
}

function ENT:SetupDataTables()
    -- Слот 0 занят именем во ВСЕХ станциях — наследники со своими полями
    -- обязаны начинать со слота 1 (жандармерия: ServiceProfile).
    self:NetworkVar("String", 0, "ComputerName")
end

--- Подписи таблички. Переопределяется станцией, если они динамические.
-- @return заголовок, подзаголовок, подсказка
function ENT:CompLabels()
    return self.CompTitle, self.CompSubtitle, self.CompHint
end
