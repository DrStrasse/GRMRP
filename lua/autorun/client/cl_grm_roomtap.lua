--[[--------------------------------------------------------------------
    GRM RoomTap — client UI
----------------------------------------------------------------------]]

if not CLIENT then return end

include("autorun/sh_grm_roomtap_config.lua")

GRM = GRM or {}
GRM.RoomTap = GRM.RoomTap or {}

local RT = GRM.RoomTap

local NET_RESULT          = "GRM_RoomTap_Result"
local NET_OPEN_CHIP       = "GRM_RoomTap_OpenChip"
local NET_OPEN_SERVER     = "GRM_RoomTap_OpenServer"
local NET_OPEN_TERMINAL   = "GRM_RoomTap_OpenTerminal"
local NET_DEVICE_ACTION   = "GRM_RoomTap_DeviceAction"
local NET_TERMINAL_DATA   = "GRM_RoomTap_TerminalData"
local NET_SHOP_OPEN       = "GRM_RoomTap_ShopOpen"
local NET_SHOP_DATA       = "GRM_RoomTap_ShopData"
local NET_SHOP_SPAWN      = "GRM_RoomTap_ShopSpawn"
local NET_SHOP_REMOVE     = "GRM_RoomTap_ShopRemove"
local NET_ACCESS_REQUEST  = "GRM_RoomTap_AccessRequest"
local NET_ACCESS_DATA     = "GRM_RoomTap_AccessData"
local NET_ACCESS_SAVE     = "GRM_RoomTap_AccessSave"
local NET_REQUESTS_OPEN   = "GRM_RoomTap_RequestsOpen"
local NET_REQUESTS_DATA   = "GRM_RoomTap_RequestsData"
local NET_REQUEST_APPROVE = "GRM_RoomTap_RequestApprove"

surface.CreateFont("GRMRoomTap_Title", { font = "Roboto", size = 20, weight = 700, extended = true })
surface.CreateFont("GRMRoomTap_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMRoomTap_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

local THEME = {
    background = Color(24, 26, 32, 245),
    panel = Color(37, 40, 50, 245),
    panelHover = Color(50, 54, 67, 245),
    accent = Color(73, 157, 240),
    green = Color(60, 180, 102),
    red = Color(202, 70, 62),
    yellow = Color(230, 173, 64),
    text = Color(235, 237, 243),
    dim = Color(166, 171, 184),
}

local function trim(value)
    return string.Trim(tostring(value or ""))
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function notify(message, success)
    notification.AddLegacy(tostring(message or ""), success and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    surface.PlaySound(success and "garrysmod/ui_click.wav" or "buttons/button10.wav")
end

local function createFrame(title, width, height)
    local frame = vgui.Create("DFrame")
    GRM.UI.Track("roomtap", frame)
    frame:SetTitle("")
    frame:SetSize(width, height)
    frame:Center()
    frame:MakePopup()

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.background)
        draw.RoundedBoxEx(8, 0, 0, w, 35, Color(34, 37, 47), true, true, false, false)
        draw.SimpleText(title, "GRMRoomTap_Title", 12, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    return frame
end

local function button(parent, text, color, width, height)
    local control = vgui.Create("DButton", parent)
    control:SetText(text)
    control:SetFont("GRMRoomTap_Normal")
    control:SetTextColor(color_white)
    if width then control:SetWide(width) end
    if height then control:SetTall(height) end

    control.Paint = function(self, w, h)
        local paint = self:IsEnabled() and (self:IsHovered() and Color(
            math.min(color.r + 24, 255), math.min(color.g + 24, 255), math.min(color.b + 24, 255)
        ) or color) or Color(70, 72, 80)
        draw.RoundedBox(5, 0, 0, w, h, paint)
    end

    return control
end

local function sendDeviceAction(action, ent, writer)
    if not IsValid(ent) then return end

    net.Start(NET_DEVICE_ACTION)
        net.WriteString(action)
        net.WriteEntity(ent)
        if writer then writer() end
    net.SendToServer()
end

-- DListView использует DLabel для каждой колонки. На части Derma-скинов
-- SetTextColor затем перезаписывается серым цветом. Поэтому текст строк
-- рисуется вручную: он всегда будет ярким и контрастным.
local function lineColor(line, color)
    if not IsValid(line) then return end

    line.GRMRoomTapTextColor = color or Color(255, 255, 255)

    for _, column in pairs(line.Columns or {}) do
        if IsValid(column) then
            column.GRMRoomTapTextColor = line.GRMRoomTapTextColor
            column:SetFont("GRMRoomTap_Normal")
            column:SetTextColor(column.GRMRoomTapTextColor)

            column.Paint = function(self, w, h)
                draw.SimpleText(
                    self:GetText() or "",
                    "GRMRoomTap_Normal",
                    5,
                    h / 2,
                    self.GRMRoomTapTextColor or Color(255, 255, 255),
                    TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER
                )
            end
        end
    end
end

local function styleList(list)
    list:SetDataHeight(26)
    list:SetHeaderHeight(28)

    list.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(29, 32, 40, 245))
    end

    -- Заголовки DListView также рисуем вручную белым, чтобы настройки
    -- активного Derma-скина не превращали их в серые.
    local function styleHeaders()
        for _, column in pairs(list.Columns or {}) do
            if IsValid(column) and column.SetTextColor then column:SetTextColor(Color(255, 255, 255)) end

            if IsValid(column) and IsValid(column.Header) then
                local header = column.Header
                header:SetFont("GRMRoomTap_Normal")
                header:SetTextColor(Color(255, 255, 255))
                header.Paint = function(self, w, h)
                    draw.RoundedBox(3, 0, 0, w, h, Color(47, 53, 67, 255))
                    draw.SimpleText(self:GetText() or "", "GRMRoomTap_Normal", 6, h / 2, Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end

    styleHeaders()
    timer.Simple(0, styleHeaders) -- после ApplySchemeSettings Derma
end

-- ============================================================
-- CHIP / SERVER CONFIGURATION
-- ============================================================

local function openChipMenu(ent, data, canMakePermanent, canRequestPermanent)
    if not IsValid(ent) then return end

    local frame = createFrame("Чип прослушки помещения", 500, 465)

    local notice = vgui.Create("DLabel", frame)
    notice:SetPos(16, 44)
    notice:SetSize(468, 35)
    notice:SetWrap(true)
    notice:SetFont("GRMRoomTap_Small")
    notice:SetTextColor(THEME.dim)
    notice:SetText("Фиксируются текстовые реплики и события присутствия. Радиус работает сквозь стены.")

    local y = 88
    local function addField(caption, value, placeholder)
        local label = vgui.Create("DLabel", frame)
        label:SetPos(16, y + 5)
        label:SetSize(125, 22)
        label:SetText(caption)
        label:SetFont("GRMRoomTap_Normal")
        label:SetTextColor(THEME.text)

        local entry = vgui.Create("DTextEntry", frame)
        entry:SetPos(145, y)
        entry:SetSize(339, 27)
        entry:SetText(tostring(value or ""))
        entry:SetPlaceholderText(placeholder or "")
        y = y + 37
        return entry
    end

    local label = addField("Подпись:", data.label, "Например: Допросная №2")
    local channel = addField("Канал сети:", data.channel, "Например: fbi_01")
    local sector = addField("Сектор вручную:", data.manualSector, "Например: Кабинет 101")

    local autoSector = vgui.Create("DLabel", frame)
    autoSector:SetPos(145, y - 2)
    autoSector:SetSize(330, 20)
    autoSector:SetText("Автосектор карты: " .. tostring(data.autoSector or "—"))
    autoSector:SetFont("GRMRoomTap_Small")
    autoSector:SetTextColor(THEME.dim)
    y = y + 25

    local radiusLabel = vgui.Create("DLabel", frame)
    radiusLabel:SetPos(16, y + 5)
    radiusLabel:SetSize(125, 22)
    radiusLabel:SetText("Радиус:")
    radiusLabel:SetFont("GRMRoomTap_Normal")
    radiusLabel:SetTextColor(THEME.text)

    local radius = vgui.Create("DNumberWang", frame)
    radius:SetPos(145, y)
    radius:SetSize(130, 27)
    radius:SetMin(RT.Config.MinChipRadius)
    radius:SetMax(RT.Config.MaxChipRadius)
    radius:SetValue(data.radius or RT.Config.DefaultChipRadius)

    local active = vgui.Create("DCheckBoxLabel", frame)
    active:SetPos(290, y + 3)
    active:SetSize(160, 22)
    active:SetText("Чип активен")
    active:SetFont("GRMRoomTap_Normal")
    active:SetTextColor(THEME.text)
    active:SetValue(data.active and 1 or 0)

    local status = vgui.Create("DLabel", frame)
    status:SetPos(16, y + 42)
    status:SetSize(468, 20)
    status:SetFont("GRMRoomTap_Small")
    status:SetTextColor(data.storageOnline and THEME.green or THEME.yellow)
    status:SetText(data.storageOnline and "Серверная стойка данного канала подключена." or "Нет активной серверной стойки этого канала: записи не сохраняются.")

    local save = button(frame, "Сохранить настройки", THEME.green, 225, 36)
    save:SetPos(16, 355)
    save.DoClick = function()
        local amount = math.Clamp(math.floor(tonumber(radius:GetValue()) or RT.Config.DefaultChipRadius), RT.Config.MinChipRadius, RT.Config.MaxChipRadius)
        sendDeviceAction("chip_set", ent, function()
            net.WriteString(string.sub(label:GetValue(), 1, 80))
            net.WriteString(string.sub(channel:GetValue(), 1, 50))
            net.WriteString(string.sub(sector:GetValue(), 1, 80))
            net.WriteUInt(amount, 16)
            net.WriteBool(active:GetChecked())
        end)
    end

    if canMakePermanent then
        local permanent = button(frame, data.permanent and "Уже сохранено для карты" or "Сохранить навсегда", THEME.accent, 225, 36)
        permanent:SetPos(259, 355)
        permanent:SetEnabled(not data.permanent)
        permanent.DoClick = function()
            sendDeviceAction("make_permanent", ent)
            frame:Close()
        end
    elseif canRequestPermanent then
        local request = button(frame, "Запросить постоянное сохранение", THEME.accent, 468, 34)
        request:SetPos(16, 401)
        request.DoClick = function()
            sendDeviceAction("request_permanent", ent)
            frame:Close()
        end
    end
end

local function openServerMenu(ent, data, canMakePermanent, canRequestPermanent)
    if not IsValid(ent) then return end

    local frame = createFrame("Серверная стойка записи", 480, 335)

    local hint = vgui.Create("DLabel", frame)
    hint:SetPos(16, 45)
    hint:SetSize(448, 40)
    hint:SetWrap(true)
    hint:SetFont("GRMRoomTap_Small")
    hint:SetTextColor(THEME.dim)
    hint:SetText("Стойка записывает журналы всех активных чипов с совпадающим каналом сети. Файлы лежат на сервере в data/grm_roomtap/records/.")

    local nameLabel = vgui.Create("DLabel", frame)
    nameLabel:SetPos(16, 98)
    nameLabel:SetSize(120, 24)
    nameLabel:SetText("Подпись:")
    nameLabel:SetFont("GRMRoomTap_Normal")
    nameLabel:SetTextColor(THEME.text)

    local name = vgui.Create("DTextEntry", frame)
    name:SetPos(140, 95)
    name:SetSize(324, 28)
    name:SetText(data.label or "")

    local channelLabel = vgui.Create("DLabel", frame)
    channelLabel:SetPos(16, 138)
    channelLabel:SetSize(120, 24)
    channelLabel:SetText("Канал сети:")
    channelLabel:SetFont("GRMRoomTap_Normal")
    channelLabel:SetTextColor(THEME.text)

    local channel = vgui.Create("DTextEntry", frame)
    channel:SetPos(140, 135)
    channel:SetSize(324, 28)
    channel:SetText(data.channel or "main")

    local active = vgui.Create("DCheckBoxLabel", frame)
    active:SetPos(140, 176)
    active:SetSize(200, 24)
    active:SetText("Стойка включена")
    active:SetFont("GRMRoomTap_Normal")
    active:SetTextColor(THEME.text)
    active:SetValue(data.active and 1 or 0)

    local save = button(frame, "Сохранить настройки", THEME.green, 220, 36)
    save:SetPos(16, 224)
    save.DoClick = function()
        sendDeviceAction("server_set", ent, function()
            net.WriteString(string.sub(name:GetValue(), 1, 80))
            net.WriteString(string.sub(channel:GetValue(), 1, 50))
            net.WriteBool(active:GetChecked())
        end)
    end

    if canMakePermanent then
        local permanent = button(frame, data.permanent and "Уже сохранено" or "Сохранить навсегда", THEME.accent, 220, 36)
        permanent:SetPos(244, 224)
        permanent:SetEnabled(not data.permanent)
        permanent.DoClick = function()
            sendDeviceAction("make_permanent", ent)
            frame:Close()
        end
    elseif canRequestPermanent then
        local request = button(frame, "Запросить постоянное сохранение", THEME.accent, 448, 33)
        request:SetPos(16, 270)
        request.DoClick = function()
            sendDeviceAction("request_permanent", ent)
            frame:Close()
        end
    end
end

-- ============================================================
-- TERMINAL
-- ============================================================

local function eventName(event)
    local names = {
        text = "Текст",
        enter = "Вход в зону",
        exit = "Выход из зоны",
        disconnect = "Отключение",
        chip_config = "Настройка чипа",
    }
    return names[event] or tostring(event or "Событие")
end

local function openRecordDetails(record)
    if not istable(record) then return end

    local subject = record.subject or {}
    local fullMessage = trim(record.message)
    if fullMessage == "" then fullMessage = "—" end

    local frame = createFrame("Полная запись прослушки", 760, 420)

    local meta = vgui.Create("DLabel", frame)
    meta:SetPos(16, 47)
    meta:SetSize(728, 92)
    meta:SetWrap(true)
    meta:SetFont("GRMRoomTap_Normal")
    meta:SetTextColor(THEME.text)
    meta:SetText(string.format(
        "Время: %s\nСобытие: %s\nКанал: %s | Сервер: %s\nЧип: %s (%s)\nСектор: %s | Автосектор: %s\nИгрок: %s [%s]",
        tostring(record.date or "—"),
        eventName(record.event),
        tostring(record.channel or "—"),
        tostring(record.serverLabel or record.serverID or "—"),
        tostring(record.chipLabel or "—"),
        tostring(record.chipID or "—"),
        tostring(record.sector or "—"),
        tostring(record.autoSector or "—"),
        tostring(subject.name or "Система"),
        tostring(subject.steamID or "—")
    ))

    local caption = vgui.Create("DLabel", frame)
    caption:SetPos(16, 148)
    caption:SetSize(300, 22)
    caption:SetText("Полный текст записи (можно выделить и скопировать):")
    caption:SetFont("GRMRoomTap_Normal")
    caption:SetTextColor(THEME.text)

    local text = vgui.Create("DTextEntry", frame)
    text:SetPos(16, 174)
    text:SetSize(728, 188)
    text:SetMultiline(true)
    text:SetText(fullMessage)
    text:SetFont("GRMRoomTap_Normal")
    text:SetTextColor(THEME.text)
    text:SetCursorColor(THEME.text)
    text:SetHighlightColor(Color(73, 157, 240, 140))
    text.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(32, 36, 46, 255))
        self:DrawTextEntryText(THEME.text, THEME.accent, THEME.text)
    end

    local close = button(frame, "Закрыть", THEME.panelHover, 130, 32)
    close:SetPos(614, 374)
    close.DoClick = function() frame:Close() end
end

local function openTerminal(ent, data, canMakePermanent, canRequestPermanent)
    if not IsValid(ent) then return end

    local frame = createFrame("Компьютер мониторинга прослушки", math.min(ScrW() - 80, 1100), math.min(ScrH() - 80, 700))
    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(6, 42, 6, 45)

    local recordsPanel = vgui.Create("DPanel", tabs)
    recordsPanel:SetPaintBackground(false)

    -- Отдельная видимая кнопка, помимо двойного клика по строке.
    -- Пользователь может выбрать запись и открыть полный текст в один клик.
    local list
    local recordsFooter = vgui.Create("DPanel", recordsPanel)
    recordsFooter:Dock(BOTTOM)
    recordsFooter:SetTall(38)
    recordsFooter.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 2, w, h - 2, Color(34, 38, 48, 255))
    end

    local expandRecord = button(recordsFooter, "Развернуть выбранную запись", THEME.accent, 250, 29)
    expandRecord:SetPos(6, 5)
    expandRecord.DoClick = function()
        local index = IsValid(list) and list:GetSelectedLine() or nil
        local line = index and list:GetLine(index)

        if not IsValid(line) or not line.Record then
            notify("Выберите запись журнала.", false)
            return
        end

        openRecordDetails(line.Record)
    end

    local footerHint = vgui.Create("DLabel", recordsFooter)
    footerHint:SetPos(268, 8)
    footerHint:SetSize(500, 22)
    footerHint:SetText("Также можно дважды нажать по строке. Полный текст доступен для копирования.")
    footerHint:SetFont("GRMRoomTap_Small")
    footerHint:SetTextColor(Color(235, 237, 243))

    list = vgui.Create("DListView", recordsPanel)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("Время")
    list:AddColumn("Событие")
    list:AddColumn("Канал")
    list:AddColumn("Сектор")
    list:AddColumn("Чип")
    list:AddColumn("Игрок")
    list:AddColumn("Сообщение — двойной клик для полного текста")
    styleList(list)

    for _, record in ipairs(data.records or {}) do
        local subject = record.subject or {}
        local line = list:AddLine(
            record.date or "—",
            eventName(record.event),
            record.channel or "—",
            record.sector ~= "" and (record.sector or "—") or "—",
            record.chipLabel or record.chipID or "—",
            subject.name or "Система",
            record.message or ""
        )

        -- Храним всю исходную запись у строки: текст не обрезается при
        -- двойном клике, даже если в таблице он визуально не поместился.
        line.Record = record

        if record.event == "enter" then
            lineColor(line, THEME.green)
        elseif record.event == "exit" or record.event == "disconnect" then
            lineColor(line, THEME.yellow)
        else
            lineColor(line, THEME.text)
        end
    end

    list.DoDoubleClick = function(_, _, line)
        if IsValid(line) and line.Record then openRecordDetails(line.Record) end
    end

    tabs:AddSheet("Журнал записей", recordsPanel, "icon16/page_white_text.png")

    local chipsPanel = vgui.Create("DPanel", tabs)
    chipsPanel:SetPaintBackground(false)

    local chipsList = vgui.Create("DListView", chipsPanel)
    chipsList:Dock(FILL)
    chipsList:AddColumn("Подпись")
    chipsList:AddColumn("ID")
    chipsList:AddColumn("Канал")
    chipsList:AddColumn("Сектор")
    chipsList:AddColumn("Автосектор")
    chipsList:AddColumn("Радиус")
    chipsList:AddColumn("Статус")
    chipsList:AddColumn("Сервер")
    styleList(chipsList)

    for _, chip in ipairs(data.chips or {}) do
        local line = chipsList:AddLine(
            chip.label or "—",
            chip.deviceID or "—",
            chip.channel or "main",
            chip.manualSector ~= "" and (chip.manualSector or "—") or "—",
            chip.autoSector or "—",
            tostring(chip.radius or 0),
            chip.active and "Активен" or "Выключен",
            chip.storageOnline and "Подключён" or "НЕТ"
        )
        lineColor(line, chip.active and (chip.storageOnline and THEME.text or THEME.yellow) or THEME.red)
    end

    tabs:AddSheet("Чипы / секторы", chipsPanel, "icon16/transmit.png")

    local serversPanel = vgui.Create("DPanel", tabs)
    serversPanel:SetPaintBackground(false)

    local serversList = vgui.Create("DListView", serversPanel)
    serversList:Dock(FILL)
    serversList:AddColumn("Подпись")
    serversList:AddColumn("ID")
    serversList:AddColumn("Канал")
    serversList:AddColumn("Статус")
    serversList:AddColumn("Постоянная")
    styleList(serversList)

    for _, server in ipairs(data.servers or {}) do
        local line = serversList:AddLine(
            server.label or "—",
            server.deviceID or "—",
            server.channel or "main",
            server.active and "Включена" or "Выключена",
            server.permanent and "Да" or "Нет"
        )
        lineColor(line, server.active and THEME.text or THEME.red)
    end

    tabs:AddSheet("Серверные стойки", serversPanel, "icon16/server.png")

    local refresh = button(frame, "↻ Обновить журнал", THEME.accent, 200, 32)
    refresh:SetPos(10, frame:GetTall() - 38)
    refresh.DoClick = function()
        net.Start(NET_TERMINAL_DATA)
            net.WriteEntity(ent)
        net.SendToServer()
        frame:Close()
    end

    if canMakePermanent then
        local permanent = button(frame, "Сохранить компьютер навсегда", THEME.green, 260, 32)
        permanent:SetPos(220, frame:GetTall() - 38)
        permanent.DoClick = function()
            sendDeviceAction("make_permanent", ent)
            frame:Close()
        end
    elseif canRequestPermanent then
        local request = button(frame, "Запросить постоянное сохранение", THEME.accent, 280, 32)
        request:SetPos(220, frame:GetTall() - 38)
        request.DoClick = function()
            sendDeviceAction("request_permanent", ent)
            frame:Close()
        end
    end
end

-- ============================================================
-- TEMPORARY SHOP
-- ============================================================

local shopItems = {}
local shopDurations = {}

local function openShop()
    local frame = createFrame("GRM Shop — оборудование прослушки", 700, 570)

    local durationLabel = vgui.Create("DLabel", frame)
    durationLabel:SetPos(14, 45)
    durationLabel:SetSize(130, 26)
    durationLabel:SetText("Срок установки:")
    durationLabel:SetFont("GRMRoomTap_Normal")
    durationLabel:SetTextColor(THEME.text)

    local durationCombo = vgui.Create("DComboBox", frame)
    durationCombo:SetPos(145, 42)
    durationCombo:SetSize(220, 28)

    for _, duration in ipairs(shopDurations or {}) do
        durationCombo:AddChoice(duration.name, duration.id)
    end
    if #(durationCombo.Choices or {}) > 0 then durationCombo:ChooseOptionID(1) end

    local hint = vgui.Create("DLabel", frame)
    hint:SetPos(380, 44)
    hint:SetSize(300, 31)
    hint:SetWrap(true)
    hint:SetText("Оборудование сохраняется на сервере до окончания срока, включая рестарты.")
    hint:SetFont("GRMRoomTap_Small")
    hint:SetTextColor(THEME.dim)

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(12, 82, 12, 52)

    for _, id in ipairs(sortedKeys(shopItems)) do
        local item = shopItems[id]
        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(116)
        row:DockMargin(0, 0, 0, 7)
        row.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
            draw.SimpleText(item.name or id, "GRMRoomTap_Normal", 12, 15, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(item.description or "", "GRMRoomTap_Small", 12, 39, THEME.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Цена за 1 час: " .. tostring(item.price or 0) .. " GRM", "GRMRoomTap_Small", 12, 65, THEME.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Установлено вами: " .. tostring(item.owned or 0) .. " / " .. tostring(item.maxOwned or "—"), "GRMRoomTap_Small", 12, 87, THEME.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local buy = button(row, item.canBuy and "Установить" or "Недоступно", item.canBuy and THEME.green or THEME.red, 145, 34)
        buy:SetPos(535, 16)
        buy:SetEnabled(item.canBuy == true)
        buy.DoClick = function()
            local selected = durationCombo:GetSelectedID()
            local durationID = selected and durationCombo:GetOptionData(selected) or ""
            if durationID == "" then notify("Выберите срок установки.", false) return end

            net.Start(NET_SHOP_SPAWN)
                net.WriteString(id)
                net.WriteString(durationID)
            net.SendToServer()
            frame:Close()
        end

        if not item.canBuy and item.reason and item.reason ~= "" then
            local reason = vgui.Create("DLabel", row)
            reason:SetPos(425, 60)
            reason:SetSize(255, 44)
            reason:SetWrap(true)
            reason:SetContentAlignment(6)
            reason:SetText(item.reason)
            reason:SetFont("GRMRoomTap_Small")
            reason:SetTextColor(THEME.red)
        end
    end

    local remove = button(frame, "Убрать ближайшее моё оборудование", THEME.red, 290, 34)
    remove:SetPos(12, 526)
    remove.DoClick = function()
        net.Start(NET_SHOP_REMOVE)
        net.SendToServer()
        frame:Close()
    end
end

-- ============================================================
-- ACCESS UI
-- ============================================================

local function normalizeAccess(data)
    data = istable(data) and data or {}
    data.Factions = istable(data.Factions) and data.Factions or {}
    data.Roles = istable(data.Roles) and data.Roles or {}
    data.Departments = istable(data.Departments) and data.Departments or {}
    return data
end

local function getValue(data, section, faction, key)
    if section == "Factions" then return data.Factions[faction] == true end
    return istable(data[section][faction]) and data[section][faction][key] == true
end

local function setValue(data, section, faction, key, value)
    if section == "Factions" then
        data.Factions[faction] = value and true or nil
        return
    end

    data[section][faction] = data[section][faction] or {}
    data[section][faction][key] = value and true or nil
    if table.Count(data[section][faction]) == 0 then data[section][faction] = nil end
end

local function openAccessMenu(factions, data)
    data = normalizeAccess(data)
    local frame = createFrame("Доступ к прослушке помещений", 860, 650)

    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(8, 42, 8, 52)

    local factionPanel = vgui.Create("DScrollPanel", tabs)
    local help = vgui.Create("DLabel", factionPanel)
    help:Dock(TOP)
    help:DockMargin(6, 5, 6, 7)
    help:SetTall(35)
    help:SetWrap(true)
    help:SetText("Отмеченная фракция получает полный доступ к чипам, стойкам, компьютерам и журналам всех каналов.")
    help:SetFont("GRMRoomTap_Small")
    help:SetTextColor(THEME.dim)

    for _, factionName in ipairs(sortedKeys(factions)) do
        local row = vgui.Create("DPanel", factionPanel)
        row:Dock(TOP)
        row:SetTall(34)
        row:DockMargin(4, 0, 4, 4)
        row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end

        local checkbox = vgui.Create("DCheckBoxLabel", row)
        checkbox:Dock(FILL)
        checkbox:DockMargin(10, 0, 0, 0)
        checkbox:SetText(factionName)
        checkbox:SetFont("GRMRoomTap_Normal")
        checkbox:SetTextColor(THEME.text)
        checkbox:SetValue(getValue(data, "Factions", factionName, nil) and 1 or 0)
        checkbox.OnChange = function(_, value)
            setValue(data, "Factions", factionName, nil, value)
        end
    end

    tabs:AddSheet("Фракции", factionPanel, "icon16/group.png")

    local function nestedTab(title, section, sourceKey, icon)
        local panel = vgui.Create("DPanel", tabs)
        panel:SetPaintBackground(false)

        local selector = vgui.Create("DComboBox", panel)
        selector:Dock(TOP)
        selector:SetTall(28)
        selector:DockMargin(6, 6, 6, 4)
        selector:SetValue("Выберите фракцию")

        local scroll = vgui.Create("DScrollPanel", panel)
        scroll:Dock(FILL)
        scroll:DockMargin(6, 0, 6, 6)

        local function rebuild(factionName)
            scroll:Clear()
            local source = factions[factionName] and factions[factionName][sourceKey] or {}
            if not istable(source) or #source == 0 then
                local empty = vgui.Create("DLabel", scroll)
                empty:Dock(TOP)
                empty:SetTall(34)
                empty:SetText("Нет данных для этой фракции.")
                empty:SetTextColor(THEME.dim)
                return
            end

            for _, key in ipairs(source) do
                local row = vgui.Create("DPanel", scroll)
                row:Dock(TOP)
                row:SetTall(34)
                row:DockMargin(0, 0, 0, 4)
                row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end

                local checkbox = vgui.Create("DCheckBoxLabel", row)
                checkbox:Dock(FILL)
                checkbox:DockMargin(10, 0, 0, 0)
                checkbox:SetText(tostring(key))
                checkbox:SetFont("GRMRoomTap_Normal")
                checkbox:SetTextColor(THEME.text)
                checkbox:SetValue(getValue(data, section, factionName, key) and 1 or 0)
                checkbox.OnChange = function(_, value)
                    setValue(data, section, factionName, key, value)
                end
            end
        end

        for _, factionName in ipairs(sortedKeys(factions)) do selector:AddChoice(factionName) end
        selector.OnSelect = function(_, _, value) rebuild(value) end

        tabs:AddSheet(title, panel, icon)
    end

    nestedTab("Роли", "Roles", "Roles", "icon16/user.png")
    nestedTab("Отделы", "Departments", "Departments", "icon16/brick.png")

    local save = button(frame, "Сохранить доступ", THEME.green, 190, 35)
    save:SetPos(660, 606)
    save.DoClick = function()
        net.Start(NET_ACCESS_SAVE)
            net.WriteTable(data)
        net.SendToServer()
    end
end

-- ============================================================
-- PERMANENT-SAVE REQUESTS
-- ============================================================

local function openRequests(requests)
    local frame = createFrame("Запросы на постоянное сохранение", 700, 470)

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:DockMargin(8, 42, 8, 52)
    list:SetMultiSelect(false)
    list:AddColumn("Игрок")
    list:AddColumn("Оборудование")
    list:AddColumn("Подпись")
    list:AddColumn("Истекает")
    list:AddColumn("Статус")

    for _, request in ipairs(requests or {}) do
        local line = list:AddLine(
            request.ownerName or "—",
            request.itemID or "—",
            request.label or "—",
            os.date("%Y-%m-%d %H:%M", request.expiresAt or 0),
            request.online and "На карте" or "Не найдено"
        )
        line.RequestID = request.id
        if not request.online then lineColor(line, THEME.red) end
    end

    local approve = button(frame, "Одобрить выбранное", THEME.green, 220, 34)
    approve:SetPos(472, 426)
    approve.DoClick = function()
        local index = list:GetSelectedLine()
        local line = index and list:GetLine(index)
        if not IsValid(line) or not line.RequestID then
            notify("Выберите запрос.", false)
            return
        end

        net.Start(NET_REQUEST_APPROVE)
            net.WriteString(line.RequestID)
        net.SendToServer()
        frame:Close()
    end
end

-- ============================================================
-- NETWORK RECEIVERS
-- ============================================================

net.Receive(NET_RESULT, function()
    local success = net.ReadBool()
    local message = net.ReadString()
    notify(message, success)
end)

net.Receive(NET_OPEN_CHIP, function()
    openChipMenu(net.ReadEntity(), net.ReadTable() or {}, net.ReadBool(), net.ReadBool())
end)

net.Receive(NET_OPEN_SERVER, function()
    openServerMenu(net.ReadEntity(), net.ReadTable() or {}, net.ReadBool(), net.ReadBool())
end)

net.Receive(NET_OPEN_TERMINAL, function()
    openTerminal(net.ReadEntity(), net.ReadTable() or {}, net.ReadBool(), net.ReadBool())
end)

net.Receive(NET_SHOP_DATA, function()
    shopItems = net.ReadTable() or {}
    shopDurations = net.ReadTable() or {}
end)

net.Receive(NET_SHOP_OPEN, function()
    openShop()
end)

net.Receive(NET_ACCESS_DATA, function()
    openAccessMenu(net.ReadTable() or {}, net.ReadTable() or {})
end)

net.Receive(NET_REQUESTS_DATA, function()
    openRequests(net.ReadTable() or {})
end)

-- Console aliases are useful when a chat addon consumes slash commands.
concommand.Add("roomtap_shop", function()
    net.Start(NET_SHOP_OPEN)
    net.SendToServer()
end)

concommand.Add("roomtap_access", function()
    net.Start(NET_ACCESS_REQUEST)
    net.SendToServer()
end)

concommand.Add("roomtap_requests", function()
    net.Start(NET_REQUESTS_OPEN)
    net.SendToServer()
end)

concommand.Add("roomtap_remove", function()
    net.Start(NET_SHOP_REMOVE)
    net.SendToServer()
end)

print("[GRM RoomTap] Client loaded")
