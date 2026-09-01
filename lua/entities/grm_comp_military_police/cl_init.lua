--[[--------------------------------------------------------------------
    grm_comp_military_police — cl_init.lua (Интерфейс Feldgendarmerie)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(20, 28, 22, 250),
    panel   = Color(28, 38, 30, 245),
    header  = Color(35, 52, 38, 255),
    accent  = Color(100, 210, 120),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(230, 245, 230),
    dim     = Color(150, 175, 155),
    gold    = Color(245, 205, 80),
}

net.Receive("GRM_CompMilPolice_Open", function()
    local ent          = net.ReadEntity()
    local onlineList   = net.ReadTable() or {}
    local tpls         = net.ReadTable() or {}
    local registry     = net.ReadTable() or {}
    local wantedRecs   = net.ReadTable() or {}
    local myFaction    = net.ReadString()
    local isSuperAdmin = net.ReadBool()
    -- расширение протокола v1.1 (см. sv_grm_comp_terminal.lua)
    local jurisdiction = net.ReadString()
    local canEdit      = net.ReadBool()
    local finesList    = net.ReadTable() or {}
    local catalog      = net.ReadTable() or {}
    -- v1.2: заявки соседнего ведомства на передачу сведений.
    -- Старый сервер их не шлёт — ReadTable вернёт пустую таблицу.
    local requests     = net.ReadTable() or {}
    local warrants     = net.ReadTable() or {}
    GRM_CompTerminal_ActiveJur = jurisdiction

    local frame = vgui.Create("DFrame")
    -- Окно терминала тянется под экран: вкладок много, и на фиксированных
    -- 960x700 верхний ряд уезжал за край (заказ владельца 21.08).
    frame:SetSize(math.Clamp(ScrW() * 0.86, 1180, 1720), math.Clamp(ScrH() * 0.88, 760, 1080))
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)

    local isArmy = IsValid(ent) and ent.IsArmyDesk and ent:IsArmyDesk()
    local deskTitle = (IsValid(ent) and ent.GetComputerName and ent:GetComputerName()) or ""
    if deskTitle == "" then
        deskTitle = isArmy and "ВООРУЖЁННЫЕ СИЛЫ • СЛУЖЕБНЫЙ ТЕРМИНАЛ" or "ТЕРМИНАЛ КОМЕНДАТУРЫ • ПОЛЕВАЯ ЖАНДАРМЕРИЯ"
    end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, CC.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 40, CC.header, true, true, false, false)
        draw.SimpleText(deskTitle, "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕")
    btnClose:SetTextColor(CC.dim)
    btnClose.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(45, 60, 48))
        if s:IsHovered() then s:SetTextColor(color_white) else s:SetTextColor(CC.dim) end
    end
    btnClose.DoClick = function() frame:Close() end

    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(4, 38, 4, 4)
    if GRM.ServiceOrders and GRM.ServiceOrders.AttachTab then GRM.ServiceOrders.AttachTab(tabs) end
    -- Вкладка «Госбаза»: тот же /pcboard, что и по команде, одним кодом.
    if GRM.PCBoard and GRM.PCBoard.AttachTab then GRM.PCBoard.AttachTab(tabs) end
    -- Вкладка «Автопарк»: закупка техники организацией и её выдача в гараже.
    if GRM.Fleet and GRM.Fleet.AttachTab then GRM.Fleet.AttachTab(tabs) end
    -- Вкладка «Номерные знаки»: выдача и проверка регистрационных номеров.
    if GRM.Plates and GRM.Plates.AttachTab then GRM.Plates.AttachTab(tabs) end
    -- фоторобот / печать ориентировок сняты со сборки

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 1: БАЗА РОЗЫСКА — только жандармерия, не ПК Вооружённых сил
    -- ══════════════════════════════════════════════════════════════
    local wantPnl = (not isArmy) and vgui.Create("DPanel", tabs) or nil
    if wantPnl then
    wantPnl:DockPadding(12, 12, 12, 12)
    wantPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblWTarget = vgui.Create("DLabel", wantPnl)
    lblWTarget:SetPos(16, 12) lblWTarget:SetText("Военный розыск (дезертирство / СОЧ / трибунал):") lblWTarget:SetFont("DermaDefaultBold") lblWTarget:SetTextColor(Color(255, 120, 100)) lblWTarget:SizeToContents()

    local comboWTarget = vgui.Create("DComboBox", wantPnl)
    comboWTarget:SetPos(16, 32) comboWTarget:SetSize(340, 26)
    comboWTarget:AddChoice("— Выберите военнослужащего онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboWTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.faction or "ВС"), pData)
    end

    local entWReason = vgui.Create("DTextEntry", wantPnl)
    entWReason:SetPos(366, 32) entWReason:SetSize(300, 26) entWReason:SetText("Самовольное оставление части (СОЧ / Дезертирство)")

    local comboWStars = vgui.Create("DComboBox", wantPnl)
    comboWStars:SetPos(676, 32) comboWStars:SetSize(120, 26)
    comboWStars:AddChoice("★☆☆☆☆ (1 ур.)", 1)
    comboWStars:AddChoice("★★☆☆☆ (2 ур.)", 2)
    comboWStars:AddChoice("★★★☆☆ (3 ур.)", 3)
    comboWStars:AddChoice("★★★★☆ (4 ур.)", 4)
    comboWStars:AddChoice("★★★★★ (5 ур.)", 5)
    comboWStars:SetValue("★★★☆☆ (3 ур.)")

    local selWKey = ""
    comboWTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then selWKey = pData.key or pData.steamID64 or "" end
    end

    local btnAddWanted = vgui.Create("DButton", wantPnl)
    btnAddWanted:SetPos(806, 32) btnAddWanted:SetSize(120, 26)
    btnAddWanted:SetText("[!] В розыск")
    btnAddWanted:SetIcon("icon16/exclamation.png")
    btnAddWanted:SetFont("DermaDefaultBold")
    btnAddWanted:SetTextColor(color_white)
    btnAddWanted.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(230, 60, 60) or Color(180, 40, 40)) end
    btnAddWanted.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на изменение базы розыска!", NOTIFY_ERROR, 3) return end
        if selWKey == "" then notification.AddLegacy("Выберите военнослужащего!", NOTIFY_ERROR, 3) return end
        local _, lvl = comboWStars:GetSelected()
        -- Только серверный Result рисует тост. Раньше клиент сразу
        -- писал «ориентировка передана» и закрывал окно — при отказе
        -- ядра приходили два уведомления («нет прав» + «снят/передан»).
        GRM_CompTerminal_Send("wanted_add", selWKey, entWReason:GetText(), tonumber(lvl) or 3, "")
    end

    local listWanted = vgui.Create("DListView", wantPnl)
    listWanted:SetPos(16, 75)
    listWanted:SetSize(910, 480)
    listWanted:AddColumn("Уровень"):SetFixedWidth(84)
    -- Общий список: у каждой записи явно указан статус фигуранта.
    listWanted:AddColumn("Статус"):SetFixedWidth(104)
    listWanted:AddColumn("Военнослужащий / Гражданин"):SetFixedWidth(210)
    listWanted:AddColumn("Воинские статьи и ориентировки"):SetFixedWidth(370)
    listWanted:AddColumn("Ключ")

    local function fillWanted(recs)
        listWanted:Clear()
        for k, r in pairs(recs or {}) do
            if istable(r) and (r.level or 0) > 0 then
                local starStr = string.rep("★", math.Clamp(r.level or 1, 1, 5))
                local reas = {}
                for _, rc in ipairs(r.reasons or {}) do reas[#reas+1] = (rc.code or "") .. " " .. (rc.title or "") end
                local status = (r.jurisdiction == "military") and "ВОЕННЫЙ" or "ГРАЖДАНСКИЙ"
                if r.foreign then status = status .. " •перед." end
                local line = listWanted:AddLine(starStr, status, r.name or k, table.concat(reas, ", "), k)
                line._targetKey = k
            end
        end
    end
    fillWanted(wantedRecs)
    frame._fillWanted = fillWanted

    local btnClearWanted = vgui.Create("DButton", wantPnl)
    btnClearWanted:SetPos(16, 565)
    btnClearWanted:SetSize(300, 34)
    btnClearWanted:SetText("✔ Снять с розыска (Задержан / Доставлен)")
    btnClearWanted:SetFont("DermaDefaultBold")
    btnClearWanted:SetTextColor(color_white)
    btnClearWanted.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnClearWanted.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на изменение базы розыска!", NOTIFY_ERROR, 3) return end
        local line = listWanted:GetSelectedLine()
        if not line then notification.AddLegacy("Выберите запись!", NOTIFY_ERROR, 3) return end
        local row = listWanted:GetLine(line)
        if row and row._targetKey then
            GRM_CompTerminal_Send("wanted_clear", row._targetKey, "Снят с розыска комендатурой Feldgendarmerie", 0, "")
        end
    end

    tabs:AddSheet("Военный розыск", wantPnl, "icon16/exclamation.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: ВЗЫСКАНИЯ И ШТРАФЫ КОМЕНДАТУРЫ
    -- ══════════════════════════════════════════════════════════════
    local finePnl = vgui.Create("DPanel", tabs)
    finePnl:DockPadding(16, 16, 16, 16)
    finePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblFTarget = vgui.Create("DLabel", finePnl)
    lblFTarget:SetPos(16, 16) lblFTarget:SetText("Дисциплинарное взыскание / Комендантский штраф:") lblFTarget:SetFont("DermaDefaultBold") lblFTarget:SetTextColor(CC.gold) lblFTarget:SizeToContents()

    local comboFTarget = vgui.Create("DComboBox", finePnl)
    comboFTarget:SetPos(16, 38) comboFTarget:SetSize(360, 28)
    comboFTarget:AddChoice("— Выберите военнослужащего —", "")
    for _, pData in ipairs(onlineList) do
        comboFTarget:AddChoice(string.format("%s  [%s]", pData.rpName or "?", pData.nick or "?"), pData)
    end

    local lblFAmount = vgui.Create("DLabel", finePnl)
    lblFAmount:SetPos(390, 16) lblFAmount:SetText("Сумма взыскания (GRM):") lblFAmount:SetTextColor(CC.text) lblFAmount:SizeToContents()
    local entFAmount = vgui.Create("DTextEntry", finePnl)
    entFAmount:SetPos(390, 38) entFAmount:SetSize(160, 28) entFAmount:SetText("3000")

    local lblFReason = vgui.Create("DLabel", finePnl)
    lblFReason:SetPos(16, 80) lblFReason:SetText("Статья устава / Нарушение комендантского часа:") lblFReason:SetTextColor(CC.text) lblFReason:SizeToContents()
    local entFReason = vgui.Create("DTextEntry", finePnl)
    entFReason:SetPos(16, 102) entFReason:SetSize(534, 28) entFReason:SetText("Нарушение формы одежды и воинской дисциплины")

    local selFKey, selFName = "", ""
    comboFTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selFKey  = pData.key or pData.steamID64 or ""
            selFName = pData.rpName or pData.nick or ""
        end
    end

    -- Статья каталога: сумма подставляется автоматически (Д12).
    local lblFArticle = vgui.Create("DLabel", finePnl)
    lblFArticle:SetPos(570, 16) lblFArticle:SetText("Статья каталога:") lblFArticle:SetTextColor(CC.text) lblFArticle:SizeToContents()
    local comboFArticle = vgui.Create("DComboBox", finePnl)
    comboFArticle:SetPos(570, 38) comboFArticle:SetSize(356, 28)
    comboFArticle:SetValue("— Без статьи (произвольно) —")
    comboFArticle:AddChoice("— Без статьи (произвольно) —", "")
    for _, a in ipairs(catalog) do
        comboFArticle:AddChoice(string.format("%s  %s", a.code or "", a.title or ""), a)
    end
    local selFArticle = ""
    comboFArticle.OnSelect = function(_, _, _, aData)
        if istable(aData) then
            selFArticle = aData.id or ""
            if (tonumber(aData.fine) or 0) > 0 then entFAmount:SetText(tostring(aData.fine)) end
            entFReason:SetText(string.format("%s %s", aData.code or "", aData.title or ""))
        else
            selFArticle = ""
        end
    end

    -- Реестр выписанных квитанций (Д3): раньше вкладка только слала
    -- «say /fine» и ничего не показывала.
    local listFines = vgui.Create("DListView", finePnl)
    listFines:SetPos(16, 200)
    listFines:SetSize(910, 330)
    listFines:AddColumn("№"):SetFixedWidth(60)
    listFines:AddColumn("Нарушитель"):SetFixedWidth(220)
    listFines:AddColumn("Сумма"):SetFixedWidth(120)
    listFines:AddColumn("Статус"):SetFixedWidth(120)
    listFines:AddColumn("Основание")

    local function fineStatus(s)
        if s == "paid" then return "оплачен" end
        if s == "cancelled" then return "аннулирован" end
        return "не оплачен"
    end

    local function fillFines(rows)
        listFines:Clear()
        for _, r in ipairs(rows or {}) do
            local line = listFines:AddLine(
                tostring(r.id or "?"),
                r.targetName or r.target or "?",
                tostring(math.floor(tonumber(r.amount) or 0)),
                fineStatus(r.status),
                r.reason or "—")
            line._fineID = r.id
        end
    end
    fillFines(finesList)

    local function sendAct(action, target, text, num, extra)
        net.Start("GRM_CompTerminal_Act")
            net.WriteString(action)
            net.WriteString(jurisdiction)
            net.WriteString(tostring(target or ""))
            net.WriteString(tostring(text or ""))
            net.WriteUInt(math.max(0, math.floor(tonumber(num) or 0)), 32)
            net.WriteString(tostring(extra or ""))
        net.SendToServer()
    end

    local btnIssueFine = vgui.Create("DButton", finePnl)
    btnIssueFine:SetPos(16, 150) btnIssueFine:SetSize(320, 36)
    btnIssueFine:SetText("Наложить комендантское взыскание")
    btnIssueFine:SetIcon("icon16/money.png")
    btnIssueFine:SetFont("DermaDefaultBold")
    btnIssueFine:SetTextColor(color_white)
    btnIssueFine.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(45, 140, 60) or Color(35, 110, 48)) end
    btnIssueFine.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на выписку штрафов!", NOTIFY_ERROR, 3) return end
        if selFKey == "" then notification.AddLegacy("Выберите нарушителя!", NOTIFY_ERROR, 3) return end
        local amt = math.floor(tonumber(entFAmount:GetText()) or 0)
        if amt <= 0 then notification.AddLegacy("Укажите сумму больше нуля!", NOTIFY_ERROR, 3) return end
        sendAct("fine_issue", selFKey, entFReason:GetText(), amt, selFArticle)
    end

    local btnCancelFine = vgui.Create("DButton", finePnl)
    btnCancelFine:SetPos(350, 150) btnCancelFine:SetSize(240, 36)
    btnCancelFine:SetText("Аннулировать выбранный")
    btnCancelFine:SetIcon("icon16/cancel.png")
    btnCancelFine:SetFont("DermaDefaultBold")
    btnCancelFine:SetTextColor(color_white)
    btnCancelFine.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(170, 70, 70) or Color(130, 50, 50)) end
    btnCancelFine.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав!", NOTIFY_ERROR, 3) return end
        local idx = listFines:GetSelectedLine()
        if not idx then notification.AddLegacy("Выберите квитанцию в реестре!", NOTIFY_ERROR, 3) return end
        local row = listFines:GetLine(idx)
        if row and row._fineID then sendAct("fine_cancel", "", "решение органа", row._fineID, "") end
    end

    local btnRefresh = vgui.Create("DButton", finePnl)
    btnRefresh:SetPos(604, 150) btnRefresh:SetSize(160, 36)
    btnRefresh:SetText("Обновить реестр")
    btnRefresh:SetIcon("icon16/arrow_refresh.png")
    btnRefresh:SetFont("DermaDefaultBold")
    btnRefresh:SetTextColor(color_white)
    btnRefresh.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(60, 90, 120) or Color(45, 70, 95)) end
    btnRefresh.DoClick = function() sendAct("refresh", "", "", 0, "") end

    frame._fillFines = fillFines
    GRM_CompTerminal_ActiveFrame = frame

    tabs:AddSheet("Взыскания комендатуры", finePnl, "icon16/money.png")
    end

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 3: БАЗА ВОЕННЫХ БИЛЕТОВ (РЕЕСТР ВС)
    -- ══════════════════════════════════════════════════════════════
    local milListPnl = vgui.Create("DPanel", tabs)
    milListPnl:DockPadding(10, 10, 10, 10)
    milListPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local listMil = vgui.Create("DListView", milListPnl)
    listMil:Dock(FILL)
    listMil:AddColumn("№ Билета"):SetFixedWidth(120)
    listMil:AddColumn("Военнослужащий"):SetFixedWidth(200)
    listMil:AddColumn("Звание"):SetFixedWidth(140)
    listMil:AddColumn("Формирование / Часть"):SetFixedWidth(200)
    listMil:AddColumn("ВУС"):SetFixedWidth(180)
    listMil:AddColumn("Статус"):SetFixedWidth(120)

    for k, m in pairs(registry.military or {}) do
        if istable(m) then
            listMil:AddLine(m.number or "—", m.fullName or "?", m.rank or "Рядовой", m.formation or "ВС", m.vus or "ВУС-100", m.status or "Действителен")
        end
    end

    tabs:AddSheet("Реестр военных билетов", milListPnl, "icon16/book_open.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 4: ОТДЕЛ КАДРОВ FELDGENDARMERIE
    -- ══════════════════════════════════════════════════════════════
    local badgePnl = vgui.Create("DPanel", tabs)
    badgePnl:DockPadding(16, 16, 16, 16)
    badgePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblBTarget = vgui.Create("DLabel", badgePnl)
    lblBTarget:SetPos(16, 16) lblBTarget:SetText(isArmy and "Служебные удостоверения Вооружённых сил:" or "Служебные удостоверения жандармов (Feldgendarmerie):") lblBTarget:SetFont("DermaDefaultBold") lblBTarget:SetTextColor(CC.accent) lblBTarget:SizeToContents()

    local comboBadgeTarget = vgui.Create("DComboBox", badgePnl)
    comboBadgeTarget:SetPos(16, 36) comboBadgeTarget:SetSize(420, 28)
    comboBadgeTarget:AddChoice("— Выберите сотрудника жандармерии —", "")
    for _, pData in ipairs(onlineList) do
        if (pData.faction or ""):lower():find("feldgendarmerie") or (pData.faction or ""):lower():find("жандарм") or isSuperAdmin then
            comboBadgeTarget:AddChoice(string.format("%s  [%s]  — %s", pData.rpName or "?", pData.nick or "?", pData.role or "Жандарм"), pData)
        end
    end

    local entBadgeName = vgui.Create("DTextEntry", badgePnl) entBadgeName:SetPos(16, 95) entBadgeName:SetSize(280, 26)
    local entBadgeRole = vgui.Create("DTextEntry", badgePnl) entBadgeRole:SetPos(310, 95) entBadgeRole:SetSize(200, 26) entBadgeRole:SetText("Полевой жандарм")
    local entBadgeDept = vgui.Create("DTextEntry", badgePnl) entBadgeDept:SetPos(16, 155) entBadgeDept:SetSize(280, 26) entBadgeDept:SetText("Военная комендатура")
    local entBadgeNum  = vgui.Create("DTextEntry", badgePnl) entBadgeNum:SetPos(310, 155) entBadgeNum:SetSize(200, 26) entBadgeNum:SetText("FELD-0001")

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
            entBadgeRole:SetText(pData.role or "Полевой жандарм")
            local shortSid = selectedBadgeSid64:sub(-4)
            entBadgeNum:SetText("FELD-" .. shortSid)

            if registry.badges and registry.badges[selectedBadgeKey] then
                local ex = registry.badges[selectedBadgeKey]
                entBadgeName:SetText(ex.fullName or pData.rpName or "")
                entBadgeRole:SetText(ex.role or pData.role or "")
                entBadgeDept:SetText(ex.department or "Военная комендатура")
                entBadgeNum:SetText(ex.number or ("FELD-" .. shortSid))
                if istable(ex.permissions) then
                    for pId, cb in pairs(chkBoxes) do cb:SetValue(ex.permissions[pId] == true) end
                end
            end
        end
    end

    local btnIssueBadge = vgui.Create("DButton", badgePnl)
    btnIssueBadge:SetPos(16, yPos + 180) btnIssueBadge:SetSize(340, 36)
    btnIssueBadge:SetText("✔ Выдать удостоверение Feldgendarmerie")
    btnIssueBadge:SetFont("DermaDefaultBold")
    btnIssueBadge:SetTextColor(color_white)
    btnIssueBadge.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnIssueBadge.DoClick = function()
        if selectedBadgeKey == "" then notification.AddLegacy("Выберите сотрудника!", NOTIFY_ERROR, 3) return end
        local curPerms = {}
        for pId, cb in pairs(chkBoxes) do curPerms[pId] = cb:GetChecked() end
        local pack = {
            fullName    = entBadgeName:GetText(),
            faction     = "Feldgendarmerie",
            role        = entBadgeRole:GetText(),
            department  = entBadgeDept:GetText(),
            number      = entBadgeNum:GetText(),
            permissions = curPerms,
            issuedBy    = "Комендатура Feldgendarmerie",
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

    tabs:AddSheet(isArmy and "Кадровый отдел ВС" or "Отдел кадров Feldgendarmerie", badgePnl, "icon16/shield.png")
    GRM_CompTerminal_ActiveFrame = frame

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА: МЕЖВЕДОМСТВЕННЫЙ ОБМЕН СВЕДЕНИЯМИ
    -- Общий конструктор живёт в autorun/client/cl_grm_comp_terminal.lua,
    -- чтобы оба терминала были одинаковыми и правились в одном месте.
    -- ══════════════════════════════════════════════════════════════
    if isfunction(GRM_CompTerminal_BuildExchangeTab) then
        GRM_CompTerminal_BuildExchangeTab(tabs, frame, CC, wantedRecs, requests, jurisdiction, canEdit)
    end
    if isfunction(GRM_CompTerminal_BuildWarrantTab) then
        GRM_CompTerminal_BuildWarrantTab(tabs, frame, CC, onlineList, warrants, canEdit)
    end
end)
