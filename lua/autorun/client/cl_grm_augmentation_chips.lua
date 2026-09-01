--[[
    GRM Augmentation Chip Programmer
    Интерфейс программирования чипов аугментаций
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.AugChips = GRM.AugChips or {}
local CHIPS = GRM.AugChips

-- GRM UI Style
local GRM_COLORS = {
    bg = Color(15, 20, 30, 250),
    panel = Color(25, 35, 50, 240),
    panel2 = Color(20, 28, 40, 235),
    accent = Color(0, 150, 255),
    accent_hover = Color(50, 180, 255),
    text = Color(220, 230, 240),
    text_dim = Color(140, 150, 170),
    success = Color(50, 200, 100),
    warning = Color(255, 180, 50),
    error = Color(255, 80, 80),
    border = Color(60, 80, 110, 150),
    head = Color(18, 22, 30, 255)
}

-- GRM Fonts
surface.CreateFont("GRMChip_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
surface.CreateFont("GRMChip_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })
surface.CreateFont("GRMChip_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMChip_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
surface.CreateFont("GRMChip_Bold", { font = "Roboto", size = 13, weight = 700, extended = true })

-- Открытие программатора
function CHIPS.OpenProgrammer()
    net.Start("GRM_AugChip_GetList")
    net.SendToServer()
end

-- Получение данных
net.Receive("GRM_AugChip_SendList", function()
    local chips = net.ReadTable()
    local config = net.ReadTable()

    -- Создание окна
    local frame = vgui.Create("DFrame")
    frame:SetTitle("GRM Chip Programmer")
    frame:SetSize(950, 700)
    frame:Center()
    frame:MakePopup()

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawLine(0, 46, w, 46)

        draw.SimpleText("GRM CHIP PROGRAMMER", "GRMChip_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("v1.0 • Программатор чипов", "GRMChip_Normal", w - 20, 23, GRM_COLORS.text_dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Левая панель - список чипов
    local leftPanel = vgui.Create("DPanel", frame)
    leftPanel:SetPos(10, 56)
    leftPanel:SetSize(320, 634)
    leftPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local listTitle = vgui.Create("DLabel", leftPanel)
    listTitle:SetPos(10, 10)
    listTitle:SetSize(300, 30)
    listTitle:SetText("Мои чипы (" .. #chips .. "/" .. config.MaxChipsPerPlayer .. ")")
    listTitle:SetFont("GRMChip_Sub")
    listTitle:SetTextColor(GRM_COLORS.text)

    -- Список чипов
    local chipList = vgui.Create("DListView", leftPanel)
    chipList:SetPos(10, 45)
    chipList:SetSize(300, 520)
    chipList:SetMultiSelect(false)
    chipList:AddColumn("Название"):SetFixedWidth(180)
    chipList:AddColumn("Статус"):SetFixedWidth(110)

    chipList.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
    end

    for _, col in ipairs(chipList.Columns or {}) do
        col.Header:SetFont("GRMChip_Bold")
        col.Header:SetTextColor(GRM_COLORS.text_dim)
    end

    for _, chip in ipairs(chips) do
        local status = chip.implanted and (chip.hasComplications and "[!] Осложнения" or "[OK] Имплантирован") or "Готов"
        local line = chipList:AddLine(chip.name, status)
        line.chipData = chip

        if chip.implanted then
            line.Columns[2]:SetTextColor(chip.hasComplications and GRM_COLORS.warning or GRM_COLORS.success)
        else
            line.Columns[2]:SetTextColor(GRM_COLORS.text_dim)
        end
    end

    -- Кнопки управления
    local btnCreate = vgui.Create("DButton", leftPanel)
    btnCreate:SetPos(10, 575)
    btnCreate:SetSize(145, 40)
    btnCreate:SetText("СОЗДАТЬ ЧИП")
    btnCreate:SetFont("GRMChip_Bold")
    btnCreate:SetTextColor(GRM_COLORS.text)
    btnCreate.Paint = function(self, w, h)
        local col = self:IsHovered() and GRM_COLORS.accent_hover or GRM_COLORS.accent
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnCreate.DoClick = function()
        CHIPS.OpenChipCreator(config)
    end

    local btnDelete = vgui.Create("DButton", leftPanel)
    btnDelete:SetPos(165, 575)
    btnDelete:SetSize(145, 40)
    btnDelete:SetText("УДАЛИТЬ")
    btnDelete:SetFont("GRMChip_Bold")
    btnDelete:SetTextColor(GRM_COLORS.text)
    btnDelete.Paint = function(self, w, h)
        local col = self:IsHovered() and Color(255, 100, 100) or GRM_COLORS.error
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnDelete.DoClick = function()
        local selected = chipList:GetSelectedLine()
        if selected then
            local line = chipList:GetLine(selected)
            net.Start("GRM_AugChip_Remove")
            net.WriteString(line.chipData.id)
            net.SendToServer()
        end
    end

    -- Правая панель - информация и действия
    local rightPanel = vgui.Create("DPanel", frame)
    rightPanel:SetPos(340, 56)
    rightPanel:SetSize(600, 634)
    rightPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local infoTitle = vgui.Create("DLabel", rightPanel)
    infoTitle:SetPos(20, 20)
    infoTitle:SetSize(560, 30)
    infoTitle:SetText("Выберите чип для просмотра")
    infoTitle:SetFont("GRMChip_Sub")
    infoTitle:SetTextColor(GRM_COLORS.text)

    local infoPanel = vgui.Create("DPanel", rightPanel)
    infoPanel:SetPos(20, 60)
    infoPanel:SetSize(560, 500)
    infoPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
    end

    chipList.OnRowSelected = function(lst, rowIndex, line)
        local chip = line.chipData
        infoPanel:Clear()

        infoTitle:SetText(chip.name)

        local yPos = 10

        -- Категория с иконкой
        local catConfig = config.ChipCategories[chip.category]
        local catPanel = vgui.Create("DPanel", infoPanel)
        catPanel:SetPos(10, yPos)
        catPanel:SetSize(540, 40)
        catPanel.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
            local catColor = catConfig and catConfig.color or GRM_COLORS.text
            draw.RoundedBox(4, 0, 0, 4, h, catColor)
        end

        local catLabel = vgui.Create("DLabel", catPanel)
        catLabel:SetPos(15, 5)
        catLabel:SetSize(510, 15)
        catLabel:SetText("[ITEM] " .. (catConfig and catConfig.name or chip.category))
        catLabel:SetFont("GRMChip_Bold")
        catLabel:SetTextColor(catConfig and catConfig.color or GRM_COLORS.text)

        local levelLabel = vgui.Create("DLabel", catPanel)
        levelLabel:SetPos(15, 22)
        levelLabel:SetSize(510, 15)
        levelLabel:SetText("Уровень: " .. chip.level .. " / " .. (catConfig and catConfig.maxLevel or 5))
        levelLabel:SetFont("GRMChip_Small")
        levelLabel:SetTextColor(GRM_COLORS.text_dim)
        yPos = yPos + 50

        -- Статус с иконкой
        local statusPanel = vgui.Create("DPanel", infoPanel)
        statusPanel:SetPos(10, yPos)
        statusPanel:SetSize(540, 35)

        local statusText, statusColor, statusIcon
        if chip.implanted then
            if chip.hasComplications then
                statusText = "Имплантирован с осложнениями"
                statusColor = GRM_COLORS.warning
                statusIcon = "[!]"
            else
                statusText = "Имплантирован"
                statusColor = GRM_COLORS.success
                statusIcon = "[OK]"
            end
        else
            statusText = "Готов к имплантации"
            statusColor = GRM_COLORS.text_dim
            statusIcon = "[CFG]"
        end

        statusPanel.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
            draw.RoundedBox(4, 0, 0, 4, h, statusColor)
        end

        local statusLabel = vgui.Create("DLabel", statusPanel)
        statusLabel:SetPos(15, 8)
        statusLabel:SetSize(510, 20)
        statusLabel:SetText(statusIcon .. " " .. statusText)
        statusLabel:SetFont("GRMChip_Normal")
        statusLabel:SetTextColor(statusColor)
        yPos = yPos + 45

        -- Разделитель
        local sep = vgui.Create("DPanel", infoPanel)
        sep:SetPos(10, yPos)
        sep:SetSize(540, 2)
        sep.Paint = function(self, w, h)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawRect(0, 0, w, h)
        end
        yPos = yPos + 15

        -- Модификаторы с визуальными индикаторами
        local modTitle = vgui.Create("DLabel", infoPanel)
        modTitle:SetPos(10, yPos)
        modTitle:SetSize(540, 30)
        modTitle:SetText("МОДИФИКАТОРЫ:")
        modTitle:SetFont("GRMChip_Bold")
        modTitle:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 35

        for modKey, modValue in pairs(chip.modifiers or {}) do
            local modConfig = config.Modifiers[modKey]
            if modConfig then
                local modPanel = vgui.Create("DPanel", infoPanel)
                modPanel:SetPos(10, yPos)
                modPanel:SetSize(540, 50)
                modPanel.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
                end

                local modLabel = vgui.Create("DLabel", modPanel)
                modLabel:SetPos(10, 5)
                modLabel:SetSize(250, 20)
                modLabel:SetText(modConfig.name)
                modLabel:SetFont("GRMChip_Bold")
                modLabel:SetTextColor(GRM_COLORS.text)

                local valueText = modConfig.options and modValue or (modValue .. " " .. modConfig.unit)
                local valueLabel = vgui.Create("DLabel", modPanel)
                valueLabel:SetPos(270, 5)
                valueLabel:SetSize(260, 20)
                valueLabel:SetText(valueText)
                valueLabel:SetFont("GRMChip_Normal")
                valueLabel:SetTextColor(GRM_COLORS.accent)
                valueLabel:SetContentAlignment(6)

                -- Прогресс-бар для числовых значений
                if not modConfig.options then
                    local progressPanel = vgui.Create("DPanel", modPanel)
                    progressPanel:SetPos(10, 30)
                    progressPanel:SetSize(520, 12)
                    progressPanel.Paint = function(self, w, h)
                        draw.RoundedBox(3, 0, 0, w, h, Color(10, 15, 25))

                        local maxValue = modConfig.maxValue * (chip.level / 5)
                        local progress = math.Clamp(modValue / maxValue, 0, 1)

                        local barColor = progress < 0.5 and GRM_COLORS.warning or
                                        progress < 0.8 and GRM_COLORS.accent or
                                        GRM_COLORS.success

                        draw.RoundedBox(3, 0, 0, w * progress, h, barColor)
                    end
                end

                yPos = yPos + 55
            end
        end

        -- Кнопки действий
        yPos = yPos + 15

        if not chip.implanted then
            -- Кнопка имплантации
            local btnImplant = vgui.Create("DButton", infoPanel)
            btnImplant:SetPos(10, yPos)
            btnImplant:SetSize(540, 50)
            btnImplant:SetText("ИМПЛАНТИРОВАТЬ ЧИП")
            btnImplant:SetFont("GRMChip_Bold")
            btnImplant:SetTextColor(GRM_COLORS.text)
            btnImplant.Paint = function(self, w, h)
                local col = self:IsHovered() and GRM_COLORS.success or Color(40, 160, 80)
                draw.RoundedBox(6, 0, 0, w, h, col)
            end
            btnImplant.DoClick = function()
                Derma_Query(
                    "Имплантировать чип '" .. chip.name .. "'?\n\nШанс успеха: " .. math.floor(config.ImplantSuccessRate * 100) .. "%\nШанс отторжения: " .. math.floor(config.RejectionChance * 100) .. "%\nШанс осложнений: " .. math.floor(config.ComplicationChance * 100) .. "%",
                    "Имплантация",
                    "Имплантировать",
                    function()
                        net.Start("GRM_AugChip_Implant")
                        net.WriteString(chip.id)
                        net.SendToServer()
                    end,
                    "Отмена",
                    function() end
                )
            end
        else
            -- Кнопка извлечения
            local btnExtract = vgui.Create("DButton", infoPanel)
            btnExtract:SetPos(10, yPos)
            btnExtract:SetSize(540, 50)
            btnExtract:SetText("ИЗВЛЕЧЬ ЧИП")
            btnExtract:SetFont("GRMChip_Bold")
            btnExtract:SetTextColor(GRM_COLORS.text)
            btnExtract.Paint = function(self, w, h)
                local col = self:IsHovered() and Color(255, 150, 50) or GRM_COLORS.warning
                draw.RoundedBox(6, 0, 0, w, h, col)
            end
            btnExtract.DoClick = function()
                Derma_Query(
                    "Извлечь чип '" .. chip.name .. "'?\n\nВсе эффекты будут сняты.\nЧип можно будет имплантировать снова.",
                    "Извлечение чипа",
                    "Извлечь",
                    function()
                        net.Start("GRM_AugChip_Extract")
                        net.WriteString(chip.id)
                        net.SendToServer()
                    end,
                    "Отмена",
                    function() end
                )
            end
        end
    end

    -- Обработка ответов сервера
    net.Receive("GRM_AugChip_Create", function()
        local success = net.ReadBool()
        if success then
            local chip = net.ReadTable()
            notification.AddLegacy("Чип '" .. chip.name .. "' создан!", NOTIFY_GENERIC, 3)
            frame:Close()
            CHIPS.OpenProgrammer()
        else
            local error = net.ReadString()
            notification.AddLegacy("Ошибка: " .. error, NOTIFY_ERROR, 4)
        end
    end)

    net.Receive("GRM_AugChip_Remove", function()
        local success = net.ReadBool()
        if success then
            notification.AddLegacy("Чип удален", NOTIFY_GENERIC, 3)
            frame:Close()
            CHIPS.OpenProgrammer()
        else
            notification.AddLegacy("Ошибка удаления чипа", NOTIFY_ERROR, 4)
        end
    end)

    net.Receive("GRM_AugChip_Implant", function()
        local success = net.ReadBool()
        local message = net.ReadString()
        notification.AddLegacy(message, success and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
        frame:Close()
        CHIPS.OpenProgrammer()
    end)
end)

-- Создание нового чипа
function CHIPS.OpenChipCreator(config)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Создать чип")
    frame:SetSize(700, 600)
    frame:Center()
    frame:MakePopup()

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
        draw.SimpleText("СОЗДАНИЕ НОВОГО ЧИПА", "GRMChip_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local scrollPanel = vgui.Create("DScrollPanel", frame)
    scrollPanel:Dock(FILL)
    scrollPanel:DockMargin(10, 56, 10, 10)

    local yPos = 0

    -- Название
    local nameLabel = vgui.Create("DLabel", scrollPanel)
    nameLabel:SetPos(10, yPos)
    nameLabel:SetSize(660, 30)
    nameLabel:SetText("Название чипа:")
    nameLabel:SetFont("GRMChip_Bold")
    nameLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local nameEntry = vgui.Create("DTextEntry", scrollPanel)
    nameEntry:SetPos(10, yPos)
    nameEntry:SetSize(660, 30)
    nameEntry:SetFont("GRMChip_Normal")
    nameEntry:SetPlaceholderText("Введите название...")
    yPos = yPos + 40

    -- Категория
    local catLabel = vgui.Create("DLabel", scrollPanel)
    catLabel:SetPos(10, yPos)
    catLabel:SetSize(660, 30)
    catLabel:SetText("Категория:")
    catLabel:SetFont("GRMChip_Bold")
    catLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local catCombo = vgui.Create("DComboBox", scrollPanel)
    catCombo:SetPos(10, yPos)
    catCombo:SetSize(660, 30)
    catCombo:SetFont("GRMChip_Normal")
    for catKey, catConfig in pairs(config.ChipCategories) do
        catCombo:AddChoice(catConfig.name, catKey)
    end
    catCombo:ChooseOptionID(1)
    yPos = yPos + 40

    -- Уровень
    local levelLabel = vgui.Create("DLabel", scrollPanel)
    levelLabel:SetPos(10, yPos)
    levelLabel:SetSize(660, 30)
    levelLabel:SetText("Уровень:")
    levelLabel:SetFont("GRMChip_Bold")
    levelLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local levelSlider = vgui.Create("DNumSlider", scrollPanel)
    levelSlider:SetPos(10, yPos)
    levelSlider:SetSize(660, 30)
    levelSlider:SetMin(1)
    levelSlider:SetMax(5)
    levelSlider:SetDecimals(0)
    levelSlider:SetValue(1)
    levelSlider:SetText("")
    yPos = yPos + 50

    -- Модификаторы
    local modLabel = vgui.Create("DLabel", scrollPanel)
    modLabel:SetPos(10, yPos)
    modLabel:SetSize(660, 30)
    modLabel:SetText("Модификаторы:")
    modLabel:SetFont("GRMChip_Bold")
    modLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 40

    local modEntries = {}
    for modKey, modConfig in pairs(config.Modifiers) do
        local modPanel = vgui.Create("DPanel", scrollPanel)
        modPanel:SetPos(10, yPos)
        modPanel:SetSize(660, 60)
        modPanel.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
        end

        local chk = vgui.Create("DCheckBoxLabel", modPanel)
        chk:SetPos(10, 10)
        chk:SetSize(300, 20)
        chk:SetText(modConfig.name)
        chk:SetFont("GRMChip_Normal")
        chk:SetTextColor(GRM_COLORS.text)

        local descLabel = vgui.Create("DLabel", modPanel)
        descLabel:SetPos(10, 35)
        descLabel:SetSize(300, 20)
        descLabel:SetText(modConfig.description)
        descLabel:SetFont("GRMChip_Small")
        descLabel:SetTextColor(GRM_COLORS.text_dim)

        local valueControl
        if modConfig.options then
            valueControl = vgui.Create("DComboBox", modPanel)
            valueControl:SetPos(350, 15)
            valueControl:SetSize(300, 30)
            valueControl:SetFont("GRMChip_Normal")
            for _, opt in ipairs(modConfig.options) do
                valueControl:AddChoice(opt, opt)
            end
            valueControl:ChooseOptionID(1)
        else
            valueControl = vgui.Create("DNumSlider", modPanel)
            valueControl:SetPos(350, 15)
            valueControl:SetSize(300, 30)
            valueControl:SetMin(modConfig.minValue)
            valueControl:SetMax(modConfig.maxValue)
            valueControl:SetDecimals(2)
            valueControl:SetValue(modConfig.defaultValue)
            valueControl:SetText("")
        end

        modEntries[modKey] = { checkbox = chk, control = valueControl, config = modConfig }
        yPos = yPos + 70
    end

    -- Кнопка создания
    yPos = yPos + 10
    local btnCreate = vgui.Create("DButton", scrollPanel)
    btnCreate:SetPos(10, yPos)
    btnCreate:SetSize(660, 50)
    btnCreate:SetText("СОЗДАТЬ ЧИП")
    btnCreate:SetFont("GRMChip_Bold")
    btnCreate:SetTextColor(GRM_COLORS.text)
    btnCreate.Paint = function(self, w, h)
        local col = self:IsHovered() and GRM_COLORS.accent_hover or GRM_COLORS.accent
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnCreate.DoClick = function()
        local chipData = {
            name = nameEntry:GetValue(),
            category = catCombo:GetSelected(),
            level = levelSlider:GetValue(),
            modifiers = {}
        }

        for modKey, modEntry in pairs(modEntries) do
            if modEntry.checkbox:GetChecked() then
                local value = modEntry.control:GetValue()
                chipData.modifiers[modKey] = value
            end
        end

        net.Start("GRM_AugChip_Create")
        net.WriteTable(chipData)
        net.SendToServer()
    end

    -- Установка высоты скролла
    scrollPanel:GetCanvas():SetTall(yPos + 60)
end

-- Консольная команда
concommand.Add("grm_chips", CHIPS.OpenProgrammer)

-- Обработка через PlayerSayTransform для интеграции с админ-меню
hook.Add("PlayerSayTransform", "GRM_AugChips_Cmd", function(ply, pack)
    if not istable(pack) then return end
    local cmd = string.lower(string.Trim(tostring(pack[1] or "")))
    if cmd == "grm_chips" then
        CHIPS.OpenProgrammer()
        pack[1] = ""
        pack.SkipPlayerSay = true
    end
end)

-- Обработка открытия меню имплантации из инвентаря
net.Receive("GRM_AugChip_ImplantMenu", function()
    local chipData = net.ReadTable()

    -- Создание окна подтверждения имплантации
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Имплантация чипа")
    frame:SetSize(math.min(620, ScrW() - 80), math.min(520, ScrH() - 80))
    frame:Center()
    frame:MakePopup()

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawLine(0, 46, w, 46)

        draw.SimpleText("ИМПЛАНТАЦИЯ ЧИПА", "GRMChip_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Информация о чипе
    local yPos = 60
    local nameLabel = vgui.Create("DLabel", frame)
    nameLabel:SetPos(20, yPos)
    nameLabel:SetSize(360, 30)
    nameLabel:SetText("Чип: " .. (chipData.chipName or "Неизвестный"))
    nameLabel:SetFont("GRMChip_Bold")
    nameLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 35

    local catLabel = vgui.Create("DLabel", frame)
    catLabel:SetPos(20, yPos)
    catLabel:SetSize(360, 25)
    catLabel:SetText("Категория: " .. (chipData.chipCategory or "civilian"))
    catLabel:SetFont("GRMChip_Normal")
    catLabel:SetTextColor(GRM_COLORS.text_dim)
    yPos = yPos + 30

    local levelLabel = vgui.Create("DLabel", frame)
    levelLabel:SetPos(20, yPos)
    levelLabel:SetSize(360, 25)
    levelLabel:SetText("Уровень: " .. (chipData.chipLevel or 1))
    levelLabel:SetFont("GRMChip_Normal")
    levelLabel:SetTextColor(GRM_COLORS.text_dim)
    yPos = yPos + 40

    -- Шансы имплантации
    local chancesLabel = vgui.Create("DLabel", frame)
    chancesLabel:SetPos(20, yPos)
    chancesLabel:SetSize(360, 25)
    chancesLabel:SetText("Шансы имплантации:")
    chancesLabel:SetFont("GRMChip_Bold")
    chancesLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local successLabel = vgui.Create("DLabel", frame)
    successLabel:SetPos(40, yPos)
    successLabel:SetSize(320, 20)
    successLabel:SetText("[OK] Успех: 85%")
    successLabel:SetFont("GRMChip_Normal")
    successLabel:SetTextColor(GRM_COLORS.success)
    yPos = yPos + 25

    local rejectLabel = vgui.Create("DLabel", frame)
    rejectLabel:SetPos(40, yPos)
    rejectLabel:SetSize(320, 20)
    rejectLabel:SetText("✗ Отторжение: 10% (урон 20-40 HP)")
    rejectLabel:SetFont("GRMChip_Normal")
    rejectLabel:SetTextColor(GRM_COLORS.error)
    yPos = yPos + 25

    local compLabel = vgui.Create("DLabel", frame)
    compLabel:SetPos(40, yPos)
    compLabel:SetSize(320, 20)
    compLabel:SetText("[!] Осложнения: 5% (урон 10-25 HP)")
    compLabel:SetFont("GRMChip_Normal")
    compLabel:SetTextColor(GRM_COLORS.warning)
    yPos = yPos + 40

    -- Кнопки
    local btnImplant = vgui.Create("DButton", frame)
    btnImplant:SetPos(20, yPos)
    btnImplant:SetSize(170, 40)
    btnImplant:SetText("ИМПЛАНТИРОВАТЬ")
    btnImplant:SetFont("GRMChip_Bold")
    btnImplant:SetTextColor(GRM_COLORS.text)
    btnImplant.Paint = function(self, w, h)
        local col = self:IsHovered() and GRM_COLORS.success or Color(40, 160, 80)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnImplant.DoClick = function()
        -- Отправка запроса на имплантацию
        net.Start("GRM_AugChip_ImplantFromInventory")
        net.WriteTable(chipData)
        net.WriteUInt(chipData.slotIdx or 1, 8)
        net.SendToServer()
        frame:Close()
    end

    local btnCancel = vgui.Create("DButton", frame)
    btnCancel:SetPos(210, yPos)
    btnCancel:SetSize(170, 40)
    btnCancel:SetText("ОТМЕНА")
    btnCancel:SetFont("GRMChip_Bold")
    btnCancel:SetTextColor(GRM_COLORS.text)
    btnCancel.Paint = function(self, w, h)
        local col = self:IsHovered() and GRM_COLORS.error or Color(160, 60, 60)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnCancel.DoClick = function()
        frame:Close()
    end
end)

-- Обработка результата имплантации
net.Receive("GRM_AugChip_ImplantResult", function()
    local success = net.ReadBool()
    local message = net.ReadString()

    notification.AddLegacy(message, success and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
end)

print("[GRM AugChips] Client programmer loaded")
