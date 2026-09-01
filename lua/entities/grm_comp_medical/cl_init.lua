--[[--------------------------------------------------------------------
    grm_comp_medical — cl_init.lua (Интерфейс Медицинской службы и Госпиталя)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(18, 28, 24, 250),
    panel   = Color(24, 38, 32, 245),
    header  = Color(30, 52, 42, 255),
    accent  = Color(90, 220, 150),
    success = Color(50, 180, 95),
    danger  = Color(220, 70, 70),
    text    = Color(235, 248, 240),
    dim     = Color(160, 190, 175),
    gold    = Color(245, 205, 80),
}

net.Receive("GRM_CompMedical_Open", function()
    local ent          = net.ReadEntity()
    local onlineList   = net.ReadTable() or {}
    local medCards     = net.ReadTable() or {}
    local myFaction    = net.ReadString()
    local isSuperAdmin = net.ReadBool()

    local frame = vgui.Create("DFrame")
    -- Окно терминала тянется под экран: вкладок много, и на фиксированных
    -- 960x700 верхний ряд уезжал за край (заказ владельца 21.08).
    frame:SetSize(math.Clamp(ScrW() * 0.86, 1180, 1720), math.Clamp(ScrH() * 0.88, 760, 1080))
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, CC.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 40, CC.header, true, true, false, false)
        draw.SimpleText("МЕДИЦИНСКАЯ СЛУЖБА • ЭЛЕКТРОННЫЙ ГОСПИТАЛЬ И ВВК", "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕")
    btnClose:SetTextColor(CC.dim)
    btnClose.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(45, 60, 50))
        if s:IsHovered() then s:SetTextColor(color_white) else s:SetTextColor(CC.dim) end
    end
    btnClose.DoClick = function() frame:Close() end

    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(4, 38, 4, 4)
    if GRM.ServiceOrders and GRM.ServiceOrders.AttachTab then GRM.ServiceOrders.AttachTab(tabs) end
    -- Вкладка «Госбаза»: тот же /pcboard, что и по команде, одним кодом.
    if GRM.PCBoard and GRM.PCBoard.AttachTab then GRM.PCBoard.AttachTab(tabs) end
    -- Вкладка «Номерные знаки»: выдача и проверка регистрационных номеров.
    if GRM.Plates and GRM.Plates.AttachTab then GRM.Plates.AttachTab(tabs) end
    -- Вкладка «Автопарк»: закупка техники организацией и её выдача в гараже.
    if GRM.Fleet and GRM.Fleet.AttachTab then GRM.Fleet.AttachTab(tabs) end

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 1: КАРТОТЕКА ПАЦИЕНТОВ И ЭЛЕКТРОННЫЕ МЕДКАРТЫ
    -- ══════════════════════════════════════════════════════════════
    local medPnl = vgui.Create("DPanel", tabs)
    medPnl:DockPadding(16, 16, 16, 16)
    medPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblTarget = vgui.Create("DLabel", medPnl)
    lblTarget:SetPos(16, 12)
    lblTarget:SetText("Выберите пациента из списка онлайн:")
    lblTarget:SetFont("DermaDefaultBold")
    lblTarget:SetTextColor(CC.accent)
    lblTarget:SizeToContents()

    local comboTarget = vgui.Create("DComboBox", medPnl)
    comboTarget:SetPos(16, 32)
    comboTarget:SetSize(460, 28)
    comboTarget:AddChoice("— Выберите пациента онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.faction or "Гражданский"), pData)
    end

    -- Ряд 1: ФИО, Группа крови, Категория годности
    local lblName = vgui.Create("DLabel", medPnl)
    lblName:SetPos(16, 68)
    lblName:SetText("1. ФИО пациента (ручное):")
    lblName:SetTextColor(CC.text)
    lblName:SizeToContents()
    local entName = vgui.Create("DTextEntry", medPnl)
    entName:SetPos(16, 88)
    entName:SetSize(270, 26)

    local lblBlood = vgui.Create("DLabel", medPnl)
    lblBlood:SetPos(300, 68)
    lblBlood:SetText("2. Группа крови и резус-фактор:")
    lblBlood:SetTextColor(CC.text)
    lblBlood:SizeToContents()
    local bloodTypes = GRM.Medical and GRM.Medical.BloodTypes or { "O(I) Rh+", "O(I) Rh−", "A(II) Rh+", "A(II) Rh−", "B(III) Rh+", "B(III) Rh−", "AB(IV) Rh+", "AB(IV) Rh−" }
    local comboBlood = vgui.Create("DComboBox", medPnl)
    comboBlood:SetPos(300, 88)
    comboBlood:SetSize(170, 26)
    for _, b in ipairs(bloodTypes) do comboBlood:AddChoice(b) end
    comboBlood:SetValue(bloodTypes[1])

    local lblFit = vgui.Create("DLabel", medPnl)
    lblFit:SetPos(485, 68)
    lblFit:SetText("3. Категория годности к службе / работе (ВВК):")
    lblFit:SetTextColor(CC.text)
    lblFit:SizeToContents()
    local fitCats = GRM.Medical and GRM.Medical.FitnessCategories or { "А — Годен к военной службе и работе", "Б — Годен с незначительными ограничениями", "В — Ограниченно годен к службе", "Г — Временно не годен (на период лечения)", "Д — Не годен к военной службе" }
    local comboFit = vgui.Create("DComboBox", medPnl)
    comboFit:SetPos(485, 88)
    comboFit:SetSize(430, 26)
    for _, f in ipairs(fitCats) do comboFit:AddChoice(f) end
    comboFit:SetValue(fitCats[1])

    -- Ряд 2: Аллергии и Хронические заболевания
    local lblAllergies = vgui.Create("DLabel", medPnl)
    lblAllergies:SetPos(16, 122)
    lblAllergies:SetText("4. Аллергические реакции / непереносимость препаратов:")
    lblAllergies:SetTextColor(CC.text)
    lblAllergies:SizeToContents()
    local entAllergies = vgui.Create("DTextEntry", medPnl)
    entAllergies:SetPos(16, 142)
    entAllergies:SetSize(440, 26)
    entAllergies:SetText("Не выявлено")

    local lblChronic = vgui.Create("DLabel", medPnl)
    lblChronic:SetPos(470, 122)
    lblChronic:SetText("5. Хронические заболевания и патологии:")
    lblChronic:SetTextColor(CC.text)
    lblChronic:SizeToContents()
    local entChronic = vgui.Create("DTextEntry", medPnl)
    entChronic:SetPos(470, 142)
    entChronic:SetSize(445, 26)
    entChronic:SetText("Отсутствуют")

    -- Ряд 3: Добавление новой записи
    local lblNewEntry = vgui.Create("DLabel", medPnl)
    lblNewEntry:SetPos(16, 178)
    lblNewEntry:SetText("Добавление новой записи осмотра / диагноза:")
    lblNewEntry:SetFont("DermaDefaultBold")
    lblNewEntry:SetTextColor(CC.gold)
    lblNewEntry:SizeToContents()

    local entNewEntry = vgui.Create("DTextEntry", medPnl)
    entNewEntry:SetPos(16, 198)
    entNewEntry:SetSize(570, 26)
    entNewEntry:SetPlaceholderText("Текст записи осмотра, диагноз, назначение лекарств...")

    local comboEntryKind = vgui.Create("DComboBox", medPnl)
    comboEntryKind:SetPos(595, 198)
    comboEntryKind:SetSize(200, 26)
    comboEntryKind:AddChoice("Осмотр терапевта")
    comboEntryKind:AddChoice("Хирургическая перевязка")
    comboEntryKind:AddChoice("Вакцинация")
    comboEntryKind:AddChoice("Заключение ВВК")
    comboEntryKind:AddChoice("Выписка рецепта")
    comboEntryKind:AddChoice("Клинический диагноз")
    comboEntryKind:SetValue("Осмотр терапевта")

    local btnAddEntry = vgui.Create("DButton", medPnl)
    btnAddEntry:SetPos(805, 198)
    btnAddEntry:SetSize(110, 26)
    btnAddEntry:SetText("+ Запись")
    btnAddEntry:SetFont("DermaDefaultBold")
    btnAddEntry:SetTextColor(color_white)
    btnAddEntry.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(40, 170, 100) or Color(30, 135, 80)) end

    -- Ряд 4: Журнал записей
    local lblHistory = vgui.Create("DLabel", medPnl)
    lblHistory:SetPos(16, 234)
    lblHistory:SetText("Журнал записей приёмов и истории болезни пациента:")
    lblHistory:SetFont("DermaDefaultBold")
    lblHistory:SetTextColor(CC.accent)
    lblHistory:SizeToContents()

    local listEntries = vgui.Create("DListView", medPnl)
    listEntries:SetPos(16, 254)
    listEntries:SetSize(900, 275)
    listEntries:AddColumn("Дата и время"):SetFixedWidth(140)
    listEntries:AddColumn("Тип записи"):SetFixedWidth(160)
    listEntries:AddColumn("Заключение врача и назначения"):SetFixedWidth(420)
    listEntries:AddColumn("Лечащий врач"):SetFixedWidth(160)

    local currentEntries = {}
    local selKey = ""
    local selSid64 = "0"

    comboTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selKey = pData.key or ""
            selSid64 = pData.steamID64 or "0"
            entName:SetText(pData.rpName or "")
            listEntries:Clear()
            currentEntries = {}

            local card = medCards[selKey]
            if istable(card) then
                entName:SetText(card.name or pData.rpName or "")
                comboBlood:SetValue(card.blood or bloodTypes[1])
                comboFit:SetValue(card.fitnessCategory or fitCats[1])
                entAllergies:SetText(card.allergies or "Не выявлено")
                entChronic:SetText(card.chronic or "Отсутствуют")

                currentEntries = card.entries or {}
                for _, e in ipairs(currentEntries) do
                    local dStr = os.date("%d.%m.%Y %H:%M", e.ts or os.time())
                    listEntries:AddLine(dStr, e.kind or "Осмотр", e.text or "—", e.doctor or "Врач")
                end
            else
                comboBlood:SetValue(bloodTypes[1])
                comboFit:SetValue(fitCats[1])
                entAllergies:SetText("Не выявлено")
                entChronic:SetText("Отсутствуют")
            end
        end
    end

    btnAddEntry.DoClick = function()
        if string.Trim(entNewEntry:GetText()) == "" then
            notification.AddLegacy("Введите текст медицинской записи!", NOTIFY_ERROR, 3)
            return
        end
        local newE = {
            ts     = os.time(),
            kind   = comboEntryKind:GetValue(),
            text   = entNewEntry:GetText(),
            doctor = LocalPlayer():GetNWString("GRM_RPName", LocalPlayer():Nick()),
        }
        currentEntries[#currentEntries + 1] = newE
        local dStr = os.date("%d.%m.%Y %H:%M", newE.ts)
        listEntries:AddLine(dStr, newE.kind, newE.text, newE.doctor)
        entNewEntry:SetText("")
        notification.AddLegacy("Запись добавлена в список. Нажмите «Сохранить медкарту».", NOTIFY_GENERIC, 3)
    end

    -- Ряд 5: Кнопки сохранения и выдачи на руки
    local btnSaveCard = vgui.Create("DButton", medPnl)
    btnSaveCard:SetPos(16, 545)
    btnSaveCard:SetSize(440, 38)
    btnSaveCard:SetText("✔ Сохранить медицинскую карту пациента в базу")
    btnSaveCard:SetFont("DermaDefaultBold")
    btnSaveCard:SetTextColor(color_white)
    btnSaveCard.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(40, 175, 100) or Color(30, 140, 80))
    end
    btnSaveCard.DoClick = function()
        if selKey == "" then
            notification.AddLegacy("Выберите пациента из списка!", NOTIFY_ERROR, 3)
            return
        end

        local pack = {
            name            = entName:GetText(),
            blood           = comboBlood:GetValue(),
            fitnessCategory = comboFit:GetValue(),
            allergies       = entAllergies:GetText(),
            chronic         = entChronic:GetText(),
            entries         = currentEntries,
            updated         = os.time(),
            created         = (medCards[selKey] and medCards[selKey].created) or os.time(),
        }

        medCards[selKey] = pack

        net.Start("GRM_CompMedical_SaveCard")
            net.WriteString(selKey)
            net.WriteTable(pack)
        net.SendToServer()

        notification.AddLegacy("Медицинская карта успешно сохранена в базу данных!", NOTIFY_GENERIC, 3)
    end

    local btnIssueCard = vgui.Create("DButton", medPnl)
    btnIssueCard:SetPos(470, 545)
    btnIssueCard:SetSize(445, 38)
    btnIssueCard:SetText("📋 Выдать физическую медкарту пациенту на руки")
    btnIssueCard:SetFont("DermaDefaultBold")
    btnIssueCard:SetTextColor(color_white)
    btnIssueCard.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(35, 120, 190) or Color(25, 95, 155))
    end
    btnIssueCard.DoClick = function()
        if selKey == "" then
            notification.AddLegacy("Выберите пациента из списка!", NOTIFY_ERROR, 3)
            return
        end

        net.Start("GRM_CompMedical_IssuePhysical")
            net.WriteString(selKey)
        net.SendToServer()
    end

    tabs:AddSheet("Картотека пациентов", medPnl, "icon16/heart.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: АРХИВ И РЕЕСТР МЕДКАРТ ГОСПИТАЛЯ
    -- ══════════════════════════════════════════════════════════════
    local archPnl = vgui.Create("DPanel", tabs)
    archPnl:DockPadding(10, 10, 10, 10)
    archPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local listArch = vgui.Create("DListView", archPnl)
    listArch:Dock(FILL)
    listArch:AddColumn("Пациент (ФИО)"):SetFixedWidth(240)
    listArch:AddColumn("Группа крови"):SetFixedWidth(140)
    listArch:AddColumn("Категория годности"):SetFixedWidth(240)
    listArch:AddColumn("Записей"):SetFixedWidth(90)
    listArch:AddColumn("Ключ слота"):SetFixedWidth(200)

    for k, c in pairs(medCards) do
        if istable(c) and isstring(k) and (k:find(":char") or not k:find(":")) then
            local cnt = istable(c.entries) and #c.entries or 0
            listArch:AddLine(c.name or "Пациент", c.blood or "—", c.fitnessCategory or "А", tostring(cnt), k)
        end
    end

    tabs:AddSheet("Реестр пациентов госпиталя", archPnl, "icon16/folder_table.png")
end)
