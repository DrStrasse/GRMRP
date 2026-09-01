--[[
    GRM Augmentation Station Client
    Клиентский интерфейс станции имплантации
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.AugStation = GRM.AugStation or {}
local STATION = GRM.AugStation

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
surface.CreateFont("GRMStation_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
surface.CreateFont("GRMStation_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })
surface.CreateFont("GRMStation_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMStation_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
surface.CreateFont("GRMStation_Bold", { font = "Roboto", size = 13, weight = 700, extended = true })

-- Обработка открытия станции
net.Receive("GRM_AugStation_Open", function()
    local station = net.ReadEntity()
    local config = net.ReadTable() or {}

    -- Значения по умолчанию если config пустой
    config.MaxChipsPerPlayer = config.MaxChipsPerPlayer or 5
    config.ImplantSuccessRate = config.ImplantSuccessRate or 0.85
    config.RejectionChance = config.RejectionChance or 0.10
    config.ComplicationChance = config.ComplicationChance or 0.05

    config.ChipCategories = config.ChipCategories or {
        civilian = {name = "Гражданская", color = Color(50, 200, 100), maxLevel = 2},
        service = {name = "Служебная", color = Color(0, 150, 255), maxLevel = 3},
        military = {name = "Военная", color = Color(255, 180, 50), maxLevel = 5},
        experimental = {name = "Экспериментальная", color = Color(255, 80, 80), maxLevel = 10}
    }

    config.Modifiers = config.Modifiers or {
        speed = {name = "Скорость", description = "Увеличение скорости передвижения", minValue = 1.0, maxValue = 2.0, defaultValue = 1.0, unit = "x"},
        stamina = {name = "Выносливость", description = "Увеличение выносливости", minValue = 1.0, maxValue = 3.0, defaultValue = 1.0, unit = "x"},
        health = {name = "Здоровье", description = "Увеличение максимального здоровья", minValue = 0, maxValue = 500, defaultValue = 0, unit = "HP"},
        armor = {name = "Броня", description = "Увеличение максимальной брони", minValue = 0, maxValue = 200, defaultValue = 0, unit = "AP"}
    }

    -- Гарантируем полный набор контролов даже если сервер прислал старый конфиг.
    config.Modifiers.carryWeight = config.Modifiers.carryWeight or {name="Грузоподъемность", description="Увеличение максимального веса", minValue=0, maxValue=100, defaultValue=0, unit="kg"}
    config.Modifiers.vision = config.Modifiers.vision or {name="Зрение", description="Инфракрасное / ночное / тактическое зрение", options={"обычное","инфракрасное","ночное","увеличение","рентген"}, defaultValue="normal"}
    config.Modifiers.doorHack = config.Modifiers.doorHack or {name="Взлом дверей", description="Временно открывает запертую дверь на 60 секунд", options={"отключен","включен"}, defaultValue="отключен"}
    local allowedByCategory = {civilian={"speed","stamina","carryWeight","health"}, service={"speed","stamina","carryWeight","health","armor","vision"}, military={"speed","stamina","carryWeight","health","armor","vision"}, experimental={"speed","stamina","carryWeight","health","armor","vision","doorHack"}}
    for key, cat in pairs(config.ChipCategories) do cat.allowed = cat.allowed or allowedByCategory[key] or allowedByCategory.civilian end

    -- Создание окна
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Станция аугментаций")
    frame:SetSize(math.min(1100, ScrW() - 80), math.min(820, ScrH() - 80))
    frame:Center()
    frame:MakePopup()

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawLine(0, 46, w, 46)

        draw.SimpleText("СТАНЦИЯ АУГМЕНТАЦИЙ", "GRMStation_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(station:GetStationName() or "Station", "GRMStation_Normal", w - 20, 23, GRM_COLORS.text_dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Вкладки
    local sheet = vgui.Create("DPropertySheet", frame)
    sheet:Dock(FILL)
    sheet:DockMargin(10, 56, 10, 10)

    -- Вкладка "Создать чип"
    local createPanel = vgui.Create("DPanel")
    createPanel:Dock(FILL)
    createPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
    end

    local scrollPanel = vgui.Create("DScrollPanel", createPanel)
    scrollPanel:Dock(FILL)
    scrollPanel:DockMargin(10, 10, 10, 10)

    local yPos = 0

    -- Название
    local nameLabel = vgui.Create("DLabel", scrollPanel)
    nameLabel:SetPos(10, yPos)
    nameLabel:SetSize(760, 30)
    nameLabel:SetText("Название чипа:")
    nameLabel:SetFont("GRMStation_Bold")
    nameLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local nameEntry = vgui.Create("DTextEntry", scrollPanel)
    nameEntry:SetPos(10, yPos)
    nameEntry:SetSize(760, 30)
    nameEntry:SetFont("GRMStation_Normal")
    nameEntry:SetPlaceholderText("Введите название...")
    yPos = yPos + 40

    -- Категория
    local catLabel = vgui.Create("DLabel", scrollPanel)
    catLabel:SetPos(10, yPos)
    catLabel:SetSize(760, 30)
    catLabel:SetText("Категория:")
    catLabel:SetFont("GRMStation_Bold")
    catLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local catCombo = vgui.Create("DComboBox", scrollPanel)
    catCombo:SetPos(10, yPos)
    catCombo:SetSize(760, 30)
    catCombo:SetFont("GRMStation_Normal")
    if config.ChipCategories then
        for catKey, catConfig in pairs(config.ChipCategories) do
            catCombo:AddChoice(catConfig.name, catKey)
        end
    end
    -- Безопасный выбор первой опции
    local ok, err = pcall(function() catCombo:ChooseOptionID(1) end)
    if not ok then
        -- Если не получилось, просто оставляем пустым
    end
    yPos = yPos + 40

    -- Уровень
    local levelLabel = vgui.Create("DLabel", scrollPanel)
    levelLabel:SetPos(10, yPos)
    levelLabel:SetSize(760, 30)
    levelLabel:SetText("Уровень:")
    levelLabel:SetFont("GRMStation_Bold")
    levelLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 30

    local levelSlider = vgui.Create("DNumSlider", scrollPanel)
    levelSlider:SetPos(10, yPos)
    levelSlider:SetSize(760, 30)
    levelSlider:SetMin(1)
    levelSlider:SetMax(10)
    levelSlider:SetDecimals(0)
    levelSlider:SetValue(1)
    levelSlider:SetText("")
    yPos = yPos + 50

    -- Модификаторы
    local modLabel = vgui.Create("DLabel", scrollPanel)
    modLabel:SetPos(10, yPos)
    modLabel:SetSize(760, 30)
    modLabel:SetText("Модификаторы:")
    modLabel:SetFont("GRMStation_Bold")
    modLabel:SetTextColor(GRM_COLORS.text)
    yPos = yPos + 40

    local modEntries = {}
    if config.Modifiers then
        for modKey, modConfig in pairs(config.Modifiers) do
            local modPanel = vgui.Create("DPanel", scrollPanel)
            modPanel:SetPos(10, yPos)
            modPanel:SetSize(760, 60)
            modPanel.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
            end

            local chk = vgui.Create("DCheckBoxLabel", modPanel)
            chk:SetPos(10, 10)
            chk:SetSize(350, 20)
            chk:SetText(modConfig.name)
            chk:SetFont("GRMStation_Normal")
            chk:SetTextColor(GRM_COLORS.text)

            local descLabel = vgui.Create("DLabel", modPanel)
            descLabel:SetPos(10, 35)
            descLabel:SetSize(350, 20)
            descLabel:SetText(modConfig.description)
            descLabel:SetFont("GRMStation_Small")
            descLabel:SetTextColor(GRM_COLORS.text_dim)

            local valueControl
            if modConfig.options then
                valueControl = vgui.Create("DComboBox", modPanel)
                valueControl:SetPos(400, 15)
                valueControl:SetSize(350, 30)
                valueControl:SetFont("GRMStation_Normal")
                for _, opt in ipairs(modConfig.options) do
                    valueControl:AddChoice(opt, opt)
                end
                -- Безопасный выбор первой опции
                local ok2, err2 = pcall(function() valueControl:ChooseOptionID(1) end)
                if not ok2 then
                    -- Если не получилось, просто оставляем пустым
                end
            else
                valueControl = vgui.Create("DNumSlider", modPanel)
                valueControl:SetPos(400, 15)
                valueControl:SetSize(350, 30)
                valueControl:SetMin(modConfig.minValue)
                valueControl:SetMax(modConfig.maxValue)
                valueControl:SetDecimals(2)
                valueControl:SetValue(modConfig.defaultValue)
                valueControl:SetText("")
            end

            modEntries[modKey] = { panel = modPanel, checkbox = chk, control = valueControl, config = modConfig }
            yPos = yPos + 70
        end
    end

    -- Категория определяет доступные параметры и предел уровня.
    local function refreshCategory()
        local selectedID = catCombo:GetSelectedID()
        local key = selectedID and catCombo:GetOptionData(selectedID)
        local category = key and config.ChipCategories[key]
        if category then
            levelSlider:SetMax(category.maxLevel or 5)
            levelSlider:SetValue(math.min(levelSlider:GetValue(), category.maxLevel or 5))
        end
        local allowed = {}
        local fallbackAllowed = {speed=true, stamina=true, carryWeight=true, health=true, armor=true, vision=true}
        for _, modKey in ipairs((category and category.allowed) or {}) do allowed[modKey] = true end
        if not category or not category.allowed then allowed = fallbackAllowed end
        for modKey, entry in pairs(modEntries) do
            entry.checkbox:SetEnabled(allowed[modKey] == true)
            entry.panel:SetVisible(allowed[modKey] == true)
            if not allowed[modKey] then entry.checkbox:SetChecked(false) end
        end
        scrollPanel:GetCanvas():InvalidateLayout(true)
    end
    catCombo.OnSelect = refreshCategory
    timer.Simple(0, refreshCategory)

    -- Кнопка создания
    yPos = yPos + 10
    local btnCreate = vgui.Create("DButton", scrollPanel)
    btnCreate:SetPos(10, yPos)
    btnCreate:SetSize(760, 50)
    btnCreate:SetText("СОЗДАТЬ ФИЗИЧЕСКИЙ ЧИП")
    btnCreate:SetFont("GRMStation_Bold")
    btnCreate:SetTextColor(GRM_COLORS.text)
    btnCreate.Paint = function(self, w, h)
        local col = self:IsHovered() and GRM_COLORS.accent_hover or GRM_COLORS.accent
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnCreate.DoClick = function()
        local selectedID = catCombo:GetSelectedID()
        local selectedCategory = selectedID and catCombo:GetOptionData(selectedID)
        if not selectedCategory or not config.ChipCategories[selectedCategory] then
            local selectedText = catCombo:GetSelected() or ""
            for key, cat in pairs(config.ChipCategories) do if cat.name == selectedText then selectedCategory = key break end end
        end
        selectedCategory = selectedCategory or "civilian"
        local chipData = {
            name = nameEntry:GetValue(),
            category = selectedCategory,
            level = levelSlider:GetValue(),
            modifiers = {}
        }

        for modKey, modEntry in pairs(modEntries) do
            if modEntry.checkbox:GetChecked() then
                local value = modEntry.control:GetValue()
                chipData.modifiers[modKey] = value
            end
        end

        net.Start("GRM_AugStation_SpawnChip")
        net.WriteTable(chipData)
        net.SendToServer()

        notification.AddLegacy("Создание чипа...", NOTIFY_GENERIC, 2)
        frame:Close()
    end

    -- Установка высоты скролла
    scrollPanel:GetCanvas():SetTall(yPos + 60)

    sheet:AddSheet("Создать чип", createPanel, "icon16/add.png")

    -- Вкладка "Информация"
    local infoPanel = vgui.Create("DPanel")
    infoPanel:Dock(FILL)
    infoPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
    end

    local infoLabel = vgui.Create("DLabel", infoPanel)
    infoLabel:Dock(FILL)
    infoLabel:DockMargin(20, 20, 20, 20)
    infoLabel:SetFont("GRMStation_Normal")
    infoLabel:SetTextColor(GRM_COLORS.text)
    infoLabel:SetWrap(true)
    infoLabel:SetText([[
📋 ИНСТРУКЦИЯ ПО ИСПОЛЬЗОВАНИЮ СТАНЦИИ:

1️⃣ СОЗДАНИЕ ЧИПА:
   • Перейдите на вкладку "Создать чип"
   • Введите название чипа
   • Выберите категорию (Гражданский/Служебный/Военный/Экспериментальный)
   • Установите уровень (1-5)
   • Выберите модификаторы (скорость, выносливость, здоровье и т.д.)
   • Нажмите "СОЗДАТЬ ФИЗИЧЕСКИЙ ЧИП"

2️⃣ ПОЛУЧЕНИЕ ЧИПА:
   • После создания чип появится как физический объект перед вами
   • Подойдите к чипу и нажмите E чтобы добавить его в инвентарь
   • Чип будет сохранен в вашем списке чипов

3️⃣ ИМПЛАНТАЦИЯ:
   • Откройте программатор чипов (через компьютер или команду grm_chips)
   • Выберите чип из списка
   • Нажмите "ИМПЛАНТИРОВАТЬ ЧИП"
   • Подтвердите имплантацию (есть шанс успеха/отторжения/осложнений)

4️⃣ ИЗВЛЕЧЕНИЕ:
   • В программаторе выберите имплантированный чип
   • Нажмите "ИЗВЛЕЧЬ ЧИП"
   • Чип можно будет имплантировать снова

💡 СОВЕТЫ:
   • Максимум чипов на игрока: ]] .. config.MaxChipsPerPlayer .. [[
   • Шанс успешной имплантации: ]] .. math.floor(config.ImplantSuccessRate * 100) .. [[%
   • Шанс отторжения: ]] .. math.floor(config.RejectionChance * 100) .. [[%
   • Шанс осложнений: ]] .. math.floor(config.ComplicationChance * 100) .. [[%
	]])

    sheet:AddSheet("Информация", infoPanel, "icon16/information.png")
end)

print("[GRM AugStation] Client loaded")
