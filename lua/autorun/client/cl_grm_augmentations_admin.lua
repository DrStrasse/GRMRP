--[[
    GRM Augmentations Admin Panel
    Админ-панель для настройки аугментаций (только для суперадминов)
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.Augmentations = GRM.Augmentations or {}
local AUG = GRM.Augmentations

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

-- Создание GRM шрифтов
surface.CreateFont("GRMAug_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
surface.CreateFont("GRMAug_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })
surface.CreateFont("GRMAug_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMAug_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
surface.CreateFont("GRMAug_Bold", { font = "Roboto", size = 13, weight = 700, extended = true })

-- Создание админ-панели
function AUG.OpenAdminPanel()
    local ply = LocalPlayer()
    if not ply:IsSuperAdmin() then
        notification.AddLegacy("Только для суперадминов!", NOTIFY_ERROR, 5)
        return
    end

    -- Запрос данных с сервера
    net.Start("GRM_Augmentation_Admin_Open")
    net.SendToServer()
end

-- Получение данных от сервера
net.Receive("GRM_Augmentation_Admin_SendList", function()
    local augList = net.ReadTable()
    local categories = net.ReadTable()
    local factionData = net.ReadTable() or {}

    -- Создание окна
    local frame = vgui.Create("DFrame")
    frame:SetTitle("GRM Augmentations - Админ-панель")
    frame:SetSize(900, 650)
    frame:Center()
    frame:MakePopup()

    -- Стилизация
    frame.Paint = function(self, w, h)
        -- Фон
        draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)

        -- Заголовок
        draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawLine(0, 46, w, 46)

        draw.SimpleText("GRM AUGMENTATIONS", "GRMAug_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("v2.0 • Админ-панель", "GRMAug_Normal", w - 20, 23, GRM_COLORS.text_dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Левая панель - список аугментаций
    local leftPanel = vgui.Create("DPanel", frame)
    leftPanel:SetPos(10, 56)
    leftPanel:SetSize(300, 584)
    leftPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Заголовок списка
    local listTitle = vgui.Create("DLabel", leftPanel)
    listTitle:SetPos(10, 10)
    listTitle:SetSize(280, 30)
    listTitle:SetText("Аугментации")
    listTitle:SetFont("GRMAug_Sub")
    listTitle:SetTextColor(GRM_COLORS.text)

    -- Список аугментаций
    local augListView = vgui.Create("DListView", leftPanel)
    augListView:SetPos(10, 45)
    augListView:SetSize(280, 529)
    augListView:SetMultiSelect(false)
    augListView:AddColumn("Название"):SetFixedWidth(180)
    augListView:AddColumn("Категория"):SetFixedWidth(90)

    -- Стилизация списка
    augListView.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
    end

    -- Стилизация заголовков колонок
    for _, col in ipairs(augListView.Columns or {}) do
        col.Header:SetFont("GRMAug_Bold")
        col.Header:SetTextColor(GRM_COLORS.text_dim)
    end

    -- Заполнение списка
    local selectedItem = nil
    for _, aug in ipairs(augList) do
        local line = augListView:AddLine(aug.name, categories[aug.category] or aug.category)
        line.augData = aug

        -- Цвет в зависимости от категории
        if aug.category == "civilian" then
            line:SetColumnText(2, "● " .. (categories[aug.category] or aug.category))
            line.Columns[2]:SetTextColor(GRM_COLORS.success)
        elseif aug.category == "service" then
            line:SetColumnText(2, "● " .. (categories[aug.category] or aug.category))
            line.Columns[2]:SetTextColor(GRM_COLORS.accent)
        elseif aug.category == "military" then
            line:SetColumnText(2, "● " .. (categories[aug.category] or aug.category))
            line.Columns[2]:SetTextColor(GRM_COLORS.warning)
        elseif aug.category == "experimental" then
            line:SetColumnText(2, "● " .. (categories[aug.category] or aug.category))
            line.Columns[2]:SetTextColor(GRM_COLORS.error)
        end

        if not aug.enabled then
            for _, col in ipairs(line.Columns) do
                col:SetTextColor(GRM_COLORS.text_dim)
            end
        end
    end

    -- Правая панель - настройки
    local rightPanel = vgui.Create("DPanel", frame)
    rightPanel:SetPos(320, 56)
    rightPanel:SetSize(570, 584)
    rightPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
        surface.SetDrawColor(GRM_COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Заголовок настроек
    local settingsTitle = vgui.Create("DLabel", rightPanel)
    settingsTitle:SetPos(20, 20)
    settingsTitle:SetSize(530, 30)
    settingsTitle:SetText("Выберите аугментацию для настройки")
    settingsTitle:SetFont("GRMAug_Sub")
    settingsTitle:SetTextColor(GRM_COLORS.text)

    -- Функция обновления правой панели
    local function updateRightPanel(augData)
        if not augData then return end

        -- Очистка правой панели
        for _, child in ipairs(rightPanel:GetChildren()) do
            if child ~= settingsTitle then
                child:Remove()
            end
        end

        settingsTitle:SetText(augData.name)

        local yPos = 60

        -- Описание
        local descLabel = vgui.Create("DLabel", rightPanel)
        descLabel:SetPos(20, yPos)
        descLabel:SetSize(530, 40)
        descLabel:SetText(augData.description)
        descLabel:SetFont("GRMAug_Normal")
        descLabel:SetTextColor(GRM_COLORS.text_dim)
        descLabel:SetWrap(true)
        yPos = yPos + 50

        -- Разделитель
        local separator = vgui.Create("DPanel", rightPanel)
        separator:SetPos(20, yPos)
        separator:SetSize(530, 2)
        separator.Paint = function(self, w, h)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawRect(0, 0, w, h)
        end
        yPos = yPos + 20

        -- Статус
        local statusLabel = vgui.Create("DLabel", rightPanel)
        statusLabel:SetPos(20, yPos)
        statusLabel:SetSize(200, 30)
        statusLabel:SetText("Статус:")
        statusLabel:SetFont("GRMAug_Bold")
        statusLabel:SetTextColor(GRM_COLORS.text)

        local statusCheckbox = vgui.Create("DCheckBoxLabel", rightPanel)
        statusCheckbox:SetPos(220, yPos)
        statusCheckbox:SetSize(300, 30)
        statusCheckbox:SetText(augData.enabled and "Включена" or "Выключена")
        statusCheckbox:SetChecked(augData.enabled)
        statusCheckbox:SetTextColor(GRM_COLORS.text)
        statusCheckbox:SetFont("GRMAug_Normal")
        statusCheckbox.OnChange = function(self, val)
            self:SetText(val and "Включена" or "Выключена")
        end
        yPos = yPos + 40

        -- Стоимость
        local costLabel = vgui.Create("DLabel", rightPanel)
        costLabel:SetPos(20, yPos)
        costLabel:SetSize(200, 30)
        costLabel:SetText("Стоимость:")
        costLabel:SetFont("GRMAug_Bold")
        costLabel:SetTextColor(GRM_COLORS.text)

        local costEntry = vgui.Create("DTextEntry", rightPanel)
        costEntry:SetPos(220, yPos)
        costEntry:SetSize(200, 30)
        costEntry:SetValue(tostring(augData.cost))
        costEntry:SetNumeric(true)
        costEntry:SetFont("GRMAug_Normal")
        yPos = yPos + 40

        -- Разделитель
        local separator2 = vgui.Create("DPanel", rightPanel)
        separator2:SetPos(20, yPos)
        separator2:SetSize(530, 2)
        separator2.Paint = function(self, w, h)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawRect(0, 0, w, h)
        end
        yPos = yPos + 20

        -- Права доступа
        local accessLabel = vgui.Create("DLabel", rightPanel)
        accessLabel:SetPos(20, yPos)
        accessLabel:SetSize(530, 30)
        accessLabel:SetText("Права доступа:")
        accessLabel:SetFont("GRMAug_Bold")
        accessLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 35

        -- Доступно всем
        local everyoneCheckbox = vgui.Create("DCheckBoxLabel", rightPanel)
        everyoneCheckbox:SetPos(40, yPos)
        everyoneCheckbox:SetSize(500, 30)
        everyoneCheckbox:SetText("Доступно всем игрокам")
        everyoneCheckbox:SetChecked(augData.access.everyone or false)
        everyoneCheckbox:SetTextColor(GRM_COLORS.text)
        everyoneCheckbox:SetFont("GRMAug_Normal")
        yPos = yPos + 35

        -- Только суперадмин
        local superadminCheckbox = vgui.Create("DCheckBoxLabel", rightPanel)
        superadminCheckbox:SetPos(40, yPos)
        superadminCheckbox:SetSize(500, 30)
        superadminCheckbox:SetText("Только суперадмин")
        superadminCheckbox:SetChecked(augData.access.superadmin or false)
        superadminCheckbox:SetTextColor(GRM_COLORS.text)
        superadminCheckbox:SetFont("GRMAug_Normal")
        yPos = yPos + 40

        -- Фракции
        local factionsLabel = vgui.Create("DLabel", rightPanel)
        factionsLabel:SetPos(20, yPos)
        factionsLabel:SetSize(530, 30)
        factionsLabel:SetText("Разрешенные фракции:")
        factionsLabel:SetFont("GRMAug_Bold")
        factionsLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 30

        -- Получение списка фракций
        local factionsList = {}
        if factionData then
            for factionName, _ in pairs(factionData) do
                table.insert(factionsList, factionName)
            end
            table.sort(factionsList)
        end

        -- Множественный выбор фракций
        local factionsScroll = vgui.Create("DScrollPanel", rightPanel)
        factionsScroll:SetPos(20, yPos)
        factionsScroll:SetSize(530, 100)
        factionsScroll.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
        end

        local selectedFactions = {}
        for _, faction in ipairs(augData.access.factions or {}) do
            selectedFactions[faction] = true
        end

        local factionY = 5
        for _, faction in ipairs(factionsList) do
            local chk = vgui.Create("DCheckBoxLabel", factionsScroll)
            chk:SetPos(10, factionY)
            chk:SetSize(510, 20)
            chk:SetText(faction)
            chk:SetFont("GRMAug_Normal")
            chk:SetTextColor(GRM_COLORS.text)
            chk:SetChecked(selectedFactions[faction] or false)
            chk.factionName = faction
            chk.OnChange = function(self, val)
                selectedFactions[self.factionName] = val or nil
            end
            factionY = factionY + 22
        end

        factionsScroll:GetCanvas():SetTall(factionY)
        yPos = yPos + 110

        -- Роли
        local rolesLabel = vgui.Create("DLabel", rightPanel)
        rolesLabel:SetPos(20, yPos)
        rolesLabel:SetSize(530, 30)
        rolesLabel:SetText("Разрешенные роли:")
        rolesLabel:SetFont("GRMAug_Bold")
        rolesLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 30

        -- Получение списка ролей из всех фракций
        local rolesList = {}
        if factionData then
            for _, faction in pairs(factionData) do
                if faction.Roles then
                    for roleName, _ in pairs(faction.Roles) do
                        if not table.HasValue(rolesList, roleName) then
                            table.insert(rolesList, roleName)
                        end
                    end
                end
            end
            table.sort(rolesList)
        end

        -- Множественный выбор ролей
        local rolesScroll = vgui.Create("DScrollPanel", rightPanel)
        rolesScroll:SetPos(20, yPos)
        rolesScroll:SetSize(530, 100)
        rolesScroll.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
        end

        local selectedRoles = {}
        for _, role in ipairs(augData.access.roles or {}) do
            selectedRoles[role] = true
        end

        local roleY = 5
        for _, role in ipairs(rolesList) do
            local chk = vgui.Create("DCheckBoxLabel", rolesScroll)
            chk:SetPos(10, roleY)
            chk:SetSize(510, 20)
            chk:SetText(role)
            chk:SetFont("GRMAug_Normal")
            chk:SetTextColor(GRM_COLORS.text)
            chk:SetChecked(selectedRoles[role] or false)
            chk.roleName = role
            chk.OnChange = function(self, val)
                selectedRoles[self.roleName] = val or nil
            end
            roleY = roleY + 22
        end

        rolesScroll:GetCanvas():SetTall(roleY)
        yPos = yPos + 120

        -- Кнопка сохранения
        local saveButton = vgui.Create("DButton", rightPanel)
        saveButton:SetPos(20, yPos)
        saveButton:SetSize(530, 45)
        saveButton:SetText("СОХРАНИТЬ НАСТРОЙКИ")
        saveButton:SetFont("GRMAug_Bold")
        saveButton:SetTextColor(GRM_COLORS.text)

        saveButton.Paint = function(self, w, h)
            local col = self:IsHovered() and GRM_COLORS.accent_hover or GRM_COLORS.accent
            draw.RoundedBox(6, 0, 0, w, h, col)
        end

        saveButton.DoClick = function()
            -- Сбор выбранных фракций
            local factions = {}
            for faction, selected in pairs(selectedFactions) do
                if selected then
                    table.insert(factions, faction)
                end
            end

            -- Сбор выбранных ролей
            local roles = {}
            for role, selected in pairs(selectedRoles) do
                if selected then
                    table.insert(roles, role)
                end
            end

            -- Формирование таблицы доступа
            local accessTable = {
                everyone = everyoneCheckbox:GetChecked(),
                superadmin = superadminCheckbox:GetChecked(),
                factions = factions,
                roles = roles
            }

            -- Отправка на сервер
            net.Start("GRM_Augmentation_Admin_Save")
            net.WriteString(augData.type)
            net.WriteBool(statusCheckbox:GetChecked())
            net.WriteUInt(tonumber(costEntry:GetValue()) or 0, 32)
            net.WriteTable(accessTable)
            net.SendToServer()

            notification.AddLegacy("Настройки сохранены!", NOTIFY_GENERIC, 3)
        end
    end

    augListView.OnRowSelected = function(lst, rowIndex, line)
        selectedItem = line.augData
        updateRightPanel(selectedItem)
    end

    -- Автоматический выбор первой аугментации
    if #augListView:GetLines() > 0 then
        augListView:SelectItem(augListView:GetLine(1))
    end
end)

-- Консольная команда
concommand.Add("grm_augmentations_admin", AUG.OpenAdminPanel)

-- Обработка через PlayerSayTransform для интеграции с админ-меню
hook.Add("GRMRPChat_ClientCommand", "GRM_Augmentations_Admin_Cmd", function(ply, text)
    if ply ~= LocalPlayer() then return end
    local pack = { tostring(text or ""), SkipPlayerSay = false }
    if not istable(pack) then return end
    local cmd = string.lower(string.Trim(tostring(pack[1] or "")))
    if cmd == "grm_augmentations_admin" then
        AUG.OpenAdminPanel()
        pack[1] = ""
        pack.SkipPlayerSay = true
    end

    if pack.SkipPlayerSay == true then return true end
end)

print("[GRM Augmentations] Admin panel loaded")
