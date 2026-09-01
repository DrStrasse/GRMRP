--[[--------------------------------------------------------------------
    grm_comp_security — cl_init.lua (Интерфейс Gestapo / Komitet)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(16, 18, 24, 252),
    panel   = Color(24, 26, 36, 248),
    header  = Color(38, 22, 28, 255),
    accent  = Color(240, 90, 80),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(240, 240, 245),
    dim     = Color(160, 160, 175),
    gold    = Color(245, 205, 80),
}

net.Receive("GRM_CompSecurity_Open", function()
    local ent          = net.ReadEntity()
    local onlineList   = net.ReadTable() or {}
    local tpls         = net.ReadTable() or {}
    local registry     = net.ReadTable() or {}
    local wantedRecs   = net.ReadTable() or {}
    local medCards     = net.ReadTable() or {}
    local diplomas     = net.ReadTable() or {}
    local caseRows     = net.ReadTable() or {}
    local myFaction    = net.ReadString()
    local isSuperAdmin = net.ReadBool()

    -- Дела по ключу субъекта — для быстрого поиска в редакторе
    local casesByKey = {}
    for _, c in ipairs(caseRows) do
        if istable(c) and c.key then casesByKey[c.key] = c end
    end

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
        draw.SimpleText("ГЛАВНЫЙ СЕРВЕР НАДЗОРА • СЛУЖБА ГОСУДАРСТВЕННОЙ БЕЗОПАСНОСТИ", "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕")
    btnClose:SetTextColor(CC.dim)
    btnClose.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(55, 30, 35))
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
    -- ВКЛАДКА 1: ОПЕРАТИВНО-РОЗЫСКНОЕ ДОСЬЕ НА ГРАЖДАНИНА
    -- ══════════════════════════════════════════════════════════════
    local dosPnl = vgui.Create("DPanel", tabs)
    dosPnl:DockPadding(12, 12, 12, 12)
    dosPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblDTarget = vgui.Create("DLabel", dosPnl)
    lblDTarget:SetPos(16, 12) lblDTarget:SetText("Выберите гражданина для выгрузки полного оперативного досье:") lblDTarget:SetFont("DermaDefaultBold") lblDTarget:SetTextColor(CC.accent) lblDTarget:SizeToContents()

    local comboDTarget = vgui.Create("DComboBox", dosPnl)
    comboDTarget:SetPos(16, 32) comboDTarget:SetSize(420, 28)
    comboDTarget:AddChoice("— Выберите субъект оперативного учёта —", "")
    for _, pData in ipairs(onlineList) do
        comboDTarget:AddChoice(string.format("%s  [%s]  — %s", pData.rpName or "?", pData.nick or "?", pData.faction or "Гражданский"), pData)
    end

    local dText = vgui.Create("DTextEntry", dosPnl)
    dText:SetPos(16, 75)
    dText:SetSize(920, 520)
    dText:SetMultiline(true)
    dText:SetVerticalScrollbarEnabled(true)
    dText:SetFont("DermaDefault")
    dText:SetText("Выберите субъекта в верхнем списке для получения исчерпывающего оперативно-розыскного досье (Паспорт, Военный билет, Водительские удостоверения, Медкарта, Розыск, Фракционный статус).")

    comboDTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            local k = pData.key or ""
            local sid64 = pData.steamID64 or ""
            local pass = registry.passports and registry.passports[k]
            local badge = registry.badges and registry.badges[k]
            local mil = registry.military and registry.military[k]
            local lic = registry.licenses and registry.licenses[k]
            local milLic = registry.milLicenses and registry.milLicenses[k]
            local med = medCards[k] or medCards[sid64]
            local w = wantedRecs[k] or wantedRecs[sid64]

            local lines = {
                "══════════════════════════════════════════════════════════════════════════════════════════",
                "  ОПЕРАТИВНО-РОЗЫСКНОЕ ДОСЬЕ СЛУЖБЫ ГОСУДАРСТВЕННОЙ БЕЗОПАСНОСТИ",
                "  ГРИФ СЕКРЕТНОСТИ: СОВЕРШЕННО СЕКРЕТНО // ОСОБАЯ ПАПКА",
                "══════════════════════════════════════════════════════════════════════════════════════════",
                string.format("  ФИО СУБЪЕКТА: %s  |  SteamID64: %s  |  Ключ слота: %s", pData.rpName or "?", sid64, k),
                string.format("  ТЕКУЩАЯ ФРАКЦИЯ: %s  |  ДОЛЖНОСТЬ: %s  |  ОТДЕЛ: %s", pData.faction or "Гражданский", pData.role or "—", pData.department or "—"),
                "",
                "1. ПАСПОРТ ГРАЖДАНИНА:",
                pass and string.format("   • Серия и №: %s №%s | ФИО: %s | Гражданство: %s | Место рожд.: %s | Пол: %s | Дата рожд.: %s | Кем выдан: %s | Статус: %s", pass.series or "GRM", pass.number or "—", pass.fullName or "—", pass.nationality or "Гражданин", pass.birthPlace or "г. Приморск", pass.gender or "—", pass.birthDate or "—", pass.issuedBy or "—", pass.status or "Действителен") or "   • Паспорт в реестре НЕ ОФОРМЛЕН",
                "",
                "2. СЛУЖЕБНОЕ УДОСТОВЕРЕНИЕ (КСИВА):",
                badge and string.format("   • Ведомство: %s | Звание: %s | Отдел: %s | Жетон: %s | Статус: %s", badge.faction or "—", badge.role or "—", badge.department or "—", badge.number or "—", badge.status or "Действителен") or "   • Служебное удостоверение отсутствует",
                "",
                "3. ВОЕННЫЙ БИЛЕТ И ВОИНСКИЙ УЧЁТ:",
                mil and string.format("   • Билет №: %s | Звание: %s | ВУС: %s | Часть: %s | Должность: %s | Годность: %s | Статус: %s", mil.number or "—", mil.rank or "—", mil.vus or "—", mil.formation or "—", mil.position or "—", mil.fitness or "—", mil.status or "Действителен") or "   • Военный билет не выдавался",
                "",
                "4. ВОДИТЕЛЬСКИЕ УДОСТОВЕРЕНИЯ (ГАИ И ВАИ):",
                lic and string.format("   • Гражданские права: № %s | Категории: %s | Орган: %s | Статус: %s", lic.number or "—", lic.categoriesStr or "B", lic.issuedBy or "—", lic.status or "Действительно") or "   • Гражданские права отсутствуют",
                milLic and string.format("   • Военные права ВАИ: № %s | Звание: %s | ВУС: %s | Военные категории: %s | Статус: %s", milLic.number or "—", milLic.rank or "—", milLic.vus or "—", milLic.categoriesStr or "B-В", milLic.status or "Действительно") or "   • Военные права ВАИ не выдавались",
                "",
                "5. МЕДИЦИНСКАЯ КАРТА И СОСТОЯНИЕ ЗДОРОВЬЯ:",
                med and string.format("   • Категория годности: %s | Группа крови: %s | Аллергии: %s | Хронические заболевания: %s", med.fitnessCategory or "А", med.blood or "Не установлена", med.allergies or "Нет", med.chronic or "Нет") or "   • Медкарта не заведена",
                "",
                "6. КРИМИНАЛЬНЫЙ СТАТУС И ОРИЕНТИРОВКИ РОЗЫСКА:",
                (w and (w.level or 0) > 0) and string.format("   • ВНИМАНИЕ: СУБЪЕКТ НАХОДИТСЯ В РОЗЫСКЕ! Уровень опасности: %d звёзд", w.level or 1) or "   • В розыске не числится (чист перед законом)",
                "",
                "7. ОБРАЗОВАНИЕ И КВАЛИФИКАЦИЯ:",
            }

            -- Образование: диплом — установочный признак не хуже военного билета
            local dips = diplomas[k]
            if istable(dips) and #dips > 0 then
                for _, dp in ipairs(dips) do
                    lines[#lines + 1] = string.format(
                        "   • %s | %s | Специальность: %s | Уровень: %s | Форма: %s | Выдан: %s%s",
                        dp.number or "—", dp.institution or "—", dp.specialty or "—",
                        dp.levelName or "—", dp.formName or "—",
                        dp.issued and os.date("%d.%m.%Y", dp.issued) or "—",
                        dp.revoked and "  [АННУЛИРОВАН]" or "")
                end
            else
                lines[#lines + 1] = "   • Сведения о дипломах отсутствуют"
            end

            -- Оперативное дело: фабула и последние пометки
            local kase = casesByKey[k]
            lines[#lines + 1] = ""
            lines[#lines + 1] = "8. ОПЕРАТИВНОЕ ДЕЛО:"
            if istable(kase) then
                lines[#lines + 1] = string.format("   • Статус: %s | Уровень угрозы: %d/5 | Обновлено: %s",
                    kase.statusName or "—", kase.threat or 0,
                    kase.updated and os.date("%d.%m.%Y %H:%M", kase.updated) or "—")
                if kase.summary and kase.summary ~= "" then
                    lines[#lines + 1] = "   • Фабула: " .. kase.summary
                end
                local notes = istable(kase.notes) and kase.notes or {}
                if #notes > 0 then
                    lines[#lines + 1] = "   • Пометки (последние):"
                    for i = math.max(1, #notes - 9), #notes do
                        local nt = notes[i]
                        lines[#lines + 1] = string.format("      [%s] %s: %s",
                            nt.t and os.date("%d.%m.%Y %H:%M", nt.t) or "—",
                            nt.authorName or "—", nt.text or "")
                    end
                end
            else
                lines[#lines + 1] = "   • Дело не заводилось"
            end

            dText:SetText(table.concat(lines, "\n"))
        end
    end

    tabs:AddSheet("Оперативное досье", dosPnl, "icon16/magnifier.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА: РЕДАКТОР ОПЕРАТИВНОГО ДЕЛА
    --
    -- Сотрудник выбирает субъекта, правит фабулу/статус/угрозу и
    -- вносит пометки. Всё уходит в базу спецслужбы (special.json)
    -- и становится видно остальным агентам.
    -- ══════════════════════════════════════════════════════════════
    local casePnl = vgui.Create("DPanel", tabs)
    casePnl:DockPadding(16, 16, 16, 16)
    casePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local caseKey = ""

    local lblCaseT = vgui.Create("DLabel", casePnl)
    lblCaseT:SetPos(16, 16)
    lblCaseT:SetText("Субъект оперативного учёта:")
    lblCaseT:SetFont("DermaDefaultBold") lblCaseT:SetTextColor(CC.accent) lblCaseT:SizeToContents()

    local comboCase = vgui.Create("DComboBox", casePnl)
    comboCase:SetPos(16, 36) comboCase:SetSize(420, 28)
    comboCase:SetValue("— Выберите субъекта —")
    for _, pd in ipairs(onlineList) do
        comboCase:AddChoice(string.format("%s  [%s]  — %s",
            pd.rpName or "?", pd.nick or "?", pd.faction or "Гражданский"), pd.key)
    end
    -- Дела на офлайн-субъектов тоже должны открываться
    for _, c in ipairs(caseRows) do
        local online = false
        for _, pd in ipairs(onlineList) do
            if pd.key == c.key then online = true break end
        end
        if not online then comboCase:AddChoice((c.name or c.key) .. " [дело, офлайн]", c.key) end
    end

    local lblCaseStatus = vgui.Create("DLabel", casePnl)
    lblCaseStatus:SetPos(452, 16)
    lblCaseStatus:SetText("Статус дела:")
    lblCaseStatus:SetFont("DermaDefaultBold") lblCaseStatus:SetTextColor(CC.accent) lblCaseStatus:SizeToContents()

    local comboStatus = vgui.Create("DComboBox", casePnl)
    comboStatus:SetPos(452, 36) comboStatus:SetSize(200, 28)
    comboStatus:SetValue("В работе")
    local statuses = (GRM.SpecialService and GRM.SpecialService.CaseStatuses) or {
        { id = "open", name = "В работе" }, { id = "watch", name = "Наблюдение" },
        { id = "suspended", name = "Приостановлено" }, { id = "closed", name = "Закрыто" },
        { id = "archived", name = "В архиве" },
    }
    for _, s in ipairs(statuses) do comboStatus:AddChoice(s.name, s.id) end

    local lblThreat = vgui.Create("DLabel", casePnl)
    lblThreat:SetPos(668, 16)
    lblThreat:SetText("Уровень угрозы (0-5):")
    lblThreat:SetFont("DermaDefaultBold") lblThreat:SetTextColor(CC.accent) lblThreat:SizeToContents()

    local numThreat = vgui.Create("DNumSlider", casePnl)
    numThreat:SetPos(660, 32) numThreat:SetSize(280, 28)
    numThreat:SetMin(0) numThreat:SetMax(5) numThreat:SetDecimals(0)
    numThreat:SetText("")
    numThreat:SetValue(0)

    local lblSummary = vgui.Create("DLabel", casePnl)
    lblSummary:SetPos(16, 74)
    lblSummary:SetText("Фабула дела (основания разработки, установленные связи, задачи):")
    lblSummary:SetFont("DermaDefaultBold") lblSummary:SetTextColor(CC.accent) lblSummary:SizeToContents()

    local caseSummary = vgui.Create("DTextEntry", casePnl)
    caseSummary:SetPos(16, 94) caseSummary:SetSize(924, 150)
    caseSummary:SetMultiline(true)
    caseSummary:SetFont("DermaDefault")
    caseSummary:SetDrawLanguageID(false)

    local lblNotes = vgui.Create("DLabel", casePnl)
    lblNotes:SetPos(16, 254)
    lblNotes:SetText("Хронология пометок:")
    lblNotes:SetFont("DermaDefaultBold") lblNotes:SetTextColor(CC.accent) lblNotes:SizeToContents()

    local notesList = vgui.Create("DListView", casePnl)
    notesList:SetPos(16, 274) notesList:SetSize(924, 220)
    notesList:AddColumn("Дата"):SetFixedWidth(130)
    notesList:AddColumn("Сотрудник"):SetFixedWidth(200)
    notesList:AddColumn("Содержание пометки")

    local entryNote = vgui.Create("DTextEntry", casePnl)
    entryNote:SetPos(16, 504) entryNote:SetSize(700, 28)
    entryNote:SetPlaceholderText("Новая пометка: наблюдение, контакт, результат мероприятия…")

    local function ssAct(a, target, text, num, extra)
        if GRM.SpecialService and isfunction(GRM.SpecialService.Act) then
            GRM.SpecialService.Act(a, target, text, num, extra)
            return true
        end
        return false
    end

    local function fillCase(key)
        caseKey = key or ""
        local c = casesByKey[caseKey]
        notesList:Clear()
        if istable(c) then
            caseSummary:SetText(c.summary or "")
            comboStatus:SetValue(c.statusName or "В работе")
            numThreat:SetValue(c.threat or 0)
            for _, nt in ipairs(istable(c.notes) and c.notes or {}) do
                notesList:AddLine(
                    nt.t and os.date("%d.%m.%Y %H:%M", nt.t) or "—",
                    nt.authorName or "—", nt.text or "")
            end
        else
            caseSummary:SetText("")
            comboStatus:SetValue("В работе")
            numThreat:SetValue(0)
        end
    end

    comboCase.OnSelect = function(_, _, _, key) fillCase(key) end

    local function mkCaseBtn(label, x, y, w, col, fn)
        local b = vgui.Create("DButton", casePnl)
        b:SetPos(x, y) b:SetSize(w, 30)
        b:SetText(label) b:SetFont("DermaDefaultBold") b:SetTextColor(CC.text)
        b.Paint = function(self, bw, bh)
            draw.RoundedBox(4, 0, 0, bw, bh, self:IsHovered() and CC.accent or col)
        end
        b.DoClick = fn
        return b
    end

    mkCaseBtn("ДОБАВИТЬ ПОМЕТКУ", 724, 504, 216, CC.success, function()
        if caseKey == "" then
            chat.AddText(CC.danger, "[СГБ] Не выбран субъект оперативного учёта.")
            return
        end
        local txt = string.Trim(entryNote:GetValue() or "")
        if txt == "" then
            chat.AddText(CC.danger, "[СГБ] Пометка пуста.")
            return
        end
        if ssAct("case_note", caseKey, txt) then
            -- Локально показываем сразу; сервер пришлёт канонический список
            notesList:AddLine(os.date("%d.%m.%Y %H:%M"), LocalPlayer():Nick(), txt)
            entryNote:SetText("")
        end
    end)

    mkCaseBtn("СОХРАНИТЬ ДЕЛО В БАЗУ СПЕЦСЛУЖБЫ", 16, 542, 380, CC.success, function()
        if caseKey == "" then
            chat.AddText(CC.danger, "[СГБ] Не выбран субъект оперативного учёта.")
            return
        end
        local _, statusID = comboStatus:GetSelected()
        ssAct("case_save", caseKey, "", math.floor(numThreat:GetValue() or 0), {
            summary = caseSummary:GetValue() or "",
            status  = statusID or "open",
            threat  = math.floor(numThreat:GetValue() or 0),
        })
    end)

    mkCaseBtn("ОБНОВИТЬ ИЗ БАЗЫ", 404, 542, 200, CC.header, function()
        ssAct("refresh", "", "", 0)
        chat.AddText(CC.accent, "[СГБ] Запрошены актуальные данные. Переоткройте терминал.")
    end)

    if isSuperAdmin then
        mkCaseBtn("УДАЛИТЬ ДЕЛО", 612, 542, 180, CC.danger, function()
            if caseKey == "" then return end
            Derma_Query("Удалить оперативное дело безвозвратно?", "Подтверждение",
                "Удалить", function() ssAct("case_delete", caseKey, "", 0) end,
                "Отмена", function() end)
        end)
    end

    tabs:AddSheet("Редактор дела", casePnl, "icon16/report_edit.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: ДОКУМЕНТЫ ПРИКРЫТИЯ (COVER LAB)
    -- ══════════════════════════════════════════════════════════════
    local coverPnl = vgui.Create("DPanel", tabs)
    coverPnl:DockPadding(16, 16, 16, 16)
    coverPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblCTarget = vgui.Create("DLabel", coverPnl)
    lblCTarget:SetPos(16, 16) lblCTarget:SetText("Выберите агента спецслужб под прикрытием:") lblCTarget:SetFont("DermaDefaultBold") lblCTarget:SetTextColor(CC.accent) lblCTarget:SizeToContents()

    local comboCoverTarget = vgui.Create("DComboBox", coverPnl)
    comboCoverTarget:SetPos(16, 36) comboCoverTarget:SetSize(420, 28)
    comboCoverTarget:AddChoice("— Выберите оперативного сотрудника —", "")
    for _, pData in ipairs(onlineList) do
        comboCoverTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.key or ""), pData)
    end

    local entCoverFacManual = vgui.Create("DTextEntry", coverPnl) entCoverFacManual:SetPos(16, 95) entCoverFacManual:SetSize(320, 26) entCoverFacManual:SetText("OrdnungPolizei")
    local entCoverName = vgui.Create("DTextEntry", coverPnl) entCoverName:SetPos(350, 95) entCoverName:SetSize(280, 26)
    local entCoverRole = vgui.Create("DTextEntry", coverPnl) entCoverRole:SetPos(16, 155) entCoverRole:SetSize(280, 26) entCoverRole:SetText("Специальный инспектор")
    local entCoverDept = vgui.Create("DTextEntry", coverPnl) entCoverDept:SetPos(310, 155) entCoverDept:SetSize(240, 26) entCoverDept:SetText("Отдел специального расследования")
    local entCoverNum  = vgui.Create("DTextEntry", coverPnl) entCoverNum:SetPos(560, 155) entCoverNum:SetSize(180, 26) entCoverNum:SetText("SEC-0077")

    local chkCoverBoxes = {}
    local yCPos = 210
    local xCPos = 16
    for i, pDef in ipairs(GRM.Documents and GRM.Documents.PermissionsList or {}) do
        local chk = vgui.Create("DCheckBoxLabel", coverPnl)
        chk:SetPos(xCPos, yCPos) chk:SetText(pDef.title) chk:SetTextColor(CC.text) chk:SetValue(true) chk:SizeToContents()
        chkCoverBoxes[pDef.id] = chk
        if i % 2 == 1 then xCPos = 420 else xCPos = 16 yCPos = yCPos + 24 end
    end

    local selectedCoverKey = ""
    local selectedCoverSid64 = "0"
    comboCoverTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selectedCoverKey = pData.key or ""
            selectedCoverSid64 = pData.steamID64 or "0"
            entCoverName:SetText(pData.rpName or "")
            if registry.coverBadges and registry.coverBadges[selectedCoverKey] then
                local ex = registry.coverBadges[selectedCoverKey]
                entCoverName:SetText(ex.fullName or pData.rpName or "")
                entCoverRole:SetText(ex.role or "Инспектор")
                entCoverDept:SetText(ex.department or "Оперативный отдел")
                entCoverNum:SetText(ex.number or "SEC-0077")
                entCoverFacManual:SetText(ex.faction or "OrdnungPolizei")
            end
        end
    end

    local btnIssueCover = vgui.Create("DButton", coverPnl)
    btnIssueCover:SetPos(16, yCPos + 25) btnIssueCover:SetSize(360, 36)
    btnIssueCover:SetText("✔ Сфабриковать легендированное удостоверение")
    btnIssueCover:SetFont("DermaDefaultBold")
    btnIssueCover:SetTextColor(color_white)
    btnIssueCover.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(210, 80, 50) or Color(170, 55, 35)) end
    btnIssueCover.DoClick = function()
        if selectedCoverKey == "" then notification.AddLegacy("Выберите агента!", NOTIFY_ERROR, 3) return end
        local curPerms = {}
        for pId, cb in pairs(chkCoverBoxes) do curPerms[pId] = cb:GetChecked() end
        local pack = {
            fullName    = entCoverName:GetText(),
            faction     = entCoverFacManual:GetText(),
            role        = entCoverRole:GetText(),
            department  = entCoverDept:GetText(),
            number      = entCoverNum:GetText(),
            permissions = curPerms,
            issuedBy    = "Руководство ведомства " .. entCoverFacManual:GetText(),
            issueDate   = os.date("%d.%m.%Y"),
            validUntil  = "Бессрочно",
            status      = "Действителен",
            steamID64   = selectedCoverSid64,
            isCover     = true,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("badge")
            net.WriteString(selectedCoverKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Фабрикация прикрытия", coverPnl, "icon16/mask.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 3: ОТДЕЛ КАДРОВ СПЕЦСЛУЖБ (GESTAPO / KOMITET)
    -- ══════════════════════════════════════════════════════════════
    local badgePnl = vgui.Create("DPanel", tabs)
    badgePnl:DockPadding(16, 16, 16, 16)
    badgePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblBTarget = vgui.Create("DLabel", badgePnl)
    lblBTarget:SetPos(16, 16) lblBTarget:SetText("Оформление удостоверений сотрудников Gestapo / Komitet:") lblBTarget:SetFont("DermaDefaultBold") lblBTarget:SetTextColor(CC.accent) lblBTarget:SizeToContents()

    local comboBadgeTarget = vgui.Create("DComboBox", badgePnl)
    comboBadgeTarget:SetPos(16, 36) comboBadgeTarget:SetSize(420, 28)
    comboBadgeTarget:AddChoice("— Выберите офицера госбезопасности —", "")
    for _, pData in ipairs(onlineList) do
        comboBadgeTarget:AddChoice(string.format("%s  [%s]  — %s", pData.rpName or "?", pData.nick or "?", pData.faction or "СГБ"), pData)
    end

    local entBadgeName = vgui.Create("DTextEntry", badgePnl) entBadgeName:SetPos(16, 95) entBadgeName:SetSize(280, 26)
    local entBadgeFac  = vgui.Create("DTextEntry", badgePnl) entBadgeFac:SetPos(310, 95) entBadgeFac:SetSize(200, 26) entBadgeFac:SetText("Gestapo")
    local entBadgeRole = vgui.Create("DTextEntry", badgePnl) entBadgeRole:SetPos(525, 95) entBadgeRole:SetSize(200, 26) entBadgeRole:SetText("Офицер безопасности")
    local entBadgeDept = vgui.Create("DTextEntry", badgePnl) entBadgeDept:SetPos(16, 155) entBadgeDept:SetSize(280, 26) entBadgeDept:SetText("Главное Управление Госбезопасности")
    local entBadgeNum  = vgui.Create("DTextEntry", badgePnl) entBadgeNum:SetPos(310, 155) entBadgeNum:SetSize(200, 26) entBadgeNum:SetText("GST-0001")

    local chkBoxes = {}
    local yPos = 210
    local xPos = 16
    for i, pDef in ipairs(GRM.Documents and GRM.Documents.PermissionsList or {}) do
        local chk = vgui.Create("DCheckBoxLabel", badgePnl)
        chk:SetPos(xPos, yPos) chk:SetText(pDef.title) chk:SetTextColor(CC.text) chk:SetValue(true) chk:SizeToContents()
        chkBoxes[pDef.id] = chk
        if i % 2 == 1 then xPos = 420 else xPos = 16 yPos = yPos + 24 end
    end

    local selectedBadgeKey = ""
    local selectedBadgeSid64 = "0"
    comboBadgeTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selectedBadgeKey = pData.key or ""
            selectedBadgeSid64 = pData.steamID64 or "0"
            entBadgeName:SetText(pData.rpName or "")
            entBadgeFac:SetText(pData.faction or "Gestapo")
            entBadgeRole:SetText(pData.role or "Офицер безопасности")
            local shortSid = selectedBadgeSid64:sub(-4)
            entBadgeNum:SetText("GST-" .. shortSid)
        end
    end

    local btnIssueBadge = vgui.Create("DButton", badgePnl)
    btnIssueBadge:SetPos(16, yPos + 180) btnIssueBadge:SetSize(340, 36)
    btnIssueBadge:SetText("✔ Выдать удостоверение Госбезопасности")
    btnIssueBadge:SetFont("DermaDefaultBold")
    btnIssueBadge:SetTextColor(color_white)
    btnIssueBadge.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(210, 60, 60) or Color(160, 40, 40)) end
    btnIssueBadge.DoClick = function()
        if selectedBadgeKey == "" then notification.AddLegacy("Выберите сотрудника!", NOTIFY_ERROR, 3) return end
        local curPerms = {}
        for pId, cb in pairs(chkBoxes) do curPerms[pId] = cb:GetChecked() end
        local pack = {
            fullName    = entBadgeName:GetText(),
            faction     = entBadgeFac:GetText(),
            role        = entBadgeRole:GetText(),
            department  = entBadgeDept:GetText(),
            number      = entBadgeNum:GetText(),
            permissions = curPerms,
            issuedBy    = "Высшее руководство " .. entBadgeFac:GetText(),
            issueDate   = os.date("%d.%m.%Y"),
            validUntil  = "Бессрочно",
            status      = "Действителен",
            steamID64   = selectedBadgeSid64,
            isCover     = false,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("badge")
            net.WriteString(selectedBadgeKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Отдел кадров Спецслужб", badgePnl, "icon16/shield.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА: ТАЙНЫЕ ОПЕРАЦИИ
    -- Правки, которых не видят ведомства: обычная история розыска
    -- не пополняется, ориентировки не рассылаются, всё пишется только
    -- в закрытый журнал спецслужбы (см. sh_grm_special_service.lua).
    -- ══════════════════════════════════════════════════════════════
    local covPnl = vgui.Create("DPanel", tabs)
    covPnl:DockPadding(12, 12, 12, 12)
    covPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblCov = vgui.Create("DLabel", covPnl)
    lblCov:SetPos(16, 8)
    lblCov:SetFont("DermaDefaultBold")
    lblCov:SetTextColor(CC.accent)
    lblCov:SetText("Оперативные материалы — обе юрисдикции. Правки в журнал ведомств не попадают.")
    lblCov:SizeToContents()

    local listCov = vgui.Create("DListView", covPnl)
    listCov:SetPos(16, 32)
    listCov:SetSize(930, 400)
    listCov:AddColumn("Статус"):SetFixedWidth(120)
    listCov:AddColumn("Фигурант"):SetFixedWidth(230)
    listCov:AddColumn("Ур."):SetFixedWidth(44)
    listCov:AddColumn("Статьи"):SetFixedWidth(400)
    listCov:AddColumn("Ключ")

    local function fillCovert(recs)
        listCov:Clear()
        for k, r in pairs(recs or {}) do
            if istable(r) then
                local status = (r.jurisdiction == "military") and "ВОЕННЫЙ" or "ГРАЖДАНСКИЙ"
                if r.covert then status = "СКРЫТО • " .. status end
                local reas = {}
                for _, rc in ipairs(r.reasons or {}) do
                    reas[#reas + 1] = tostring(rc.code or "") .. " " .. tostring(rc.title or "")
                end
                local line = listCov:AddLine(status, r.name or k, tostring(r.level or 0),
                    table.concat(reas, ", "), k)
                line._targetKey = k
                line._covert = r.covert == true
            end
        end
    end
    fillCovert(wantedRecs)
    frame._fillCovert = fillCovert
    -- Модуль спецслужбы обновляет этот список после каждой операции.
    _G.GRM_CompSecurity_ActiveFrame = frame
    frame.OnClose = function() _G.GRM_CompSecurity_ActiveFrame = nil end

    local entCovNote = vgui.Create("DTextEntry", covPnl)
    entCovNote:SetPos(16, 440)
    entCovNote:SetSize(500, 26)
    entCovNote:SetPlaceholderText("Основание операции (пишется только в закрытый журнал)…")

    local function covSelected()
        local id = listCov:GetSelectedLine()
        if not id then
            notification.AddLegacy("Выберите материал из списка.", NOTIFY_ERROR, 3)
            return nil
        end
        local row = listCov:GetLine(id)
        return row and row._targetKey, row and row._covert
    end

    local function covAct(action, target, note, num)
        net.Start("GRM_SpecService_Act")
            net.WriteString(action)
            net.WriteString(tostring(target or ""))
            net.WriteString(tostring(note or ""))
            net.WriteInt(math.floor(tonumber(num) or 0), 32)
        net.SendToServer()
    end

    local function covBtn(label, x, y, w, col, fn)
        local b = vgui.Create("DButton", covPnl)
        b:SetPos(x, y) b:SetSize(w, 30)
        b:SetText(label) b:SetFont("DermaDefaultBold") b:SetTextColor(color_white)
        b.Paint = function(sf, bw, bh)
            draw.RoundedBox(4, 0, 0, bw, bh, sf:IsHovered() and col
                or Color(col.r * 0.7, col.g * 0.7, col.b * 0.7))
        end
        b.DoClick = function() surface.PlaySound("ui/buttonclick.wav") fn() end
        return b
    end

    covBtn("Снять розыск тайно", 16, 474, 170, CC.success, function()
        local key = covSelected()
        if key then covAct("level", key, entCovNote:GetValue(), 0) end
    end)

    covBtn("Понизить уровень", 194, 474, 160, CC.gold, function()
        local id = listCov:GetSelectedLine()
        if not id then notification.AddLegacy("Выберите материал.", NOTIFY_ERROR, 3) return end
        local row = listCov:GetLine(id)
        local lvl = math.max(0, (tonumber(row:GetColumnText(3)) or 0) - 1)
        covAct("level", row._targetKey, entCovNote:GetValue(), lvl)
    end)

    covBtn("Скрыть от ведомств", 362, 474, 170, Color(150, 110, 220), function()
        local key, covert = covSelected()
        if key then covAct("hide", key, entCovNote:GetValue(), covert and 0 or 1) end
    end)

    covBtn("Изъять дело", 540, 474, 150, CC.danger, function()
        local key = covSelected()
        if not key then return end
        Derma_Query("Изъять материал из базы розыска без следа?", "Оперативная санкция",
            "Изъять", function() covAct("wipe", key, entCovNote:GetValue(), 0) end,
            "Отмена", function() end)
    end)

    covBtn("Обновить", 698, 474, 120, Color(70, 76, 96), function()
        net.Start("GRM_SpecService_Open") net.SendToServer()
    end)

    covBtn("Полный терминал", 826, 474, 120, CC.accent, function()
        net.Start("GRM_SpecService_Open") net.SendToServer()
        frame:Close()
    end)

    local lblCovHint = vgui.Create("DLabel", covPnl)
    lblCovHint:SetPos(16, 512)
    lblCovHint:SetSize(930, 40)
    lblCovHint:SetTextColor(CC.dim)
    lblCovHint:SetWrap(true)
    lblCovHint:SetText("«Полный терминал» открывает оперативную панель /spec: штрафы, аресты, "
        .. "документы прикрытия и закрытый журнал операций.")

    tabs:AddSheet("Тайные операции", covPnl, "icon16/user_gray.png")
end)
