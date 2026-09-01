--[[--------------------------------------------------------------------
    grm_comp_police — cl_init.lua (Интерфейс Полиции Порядка)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(18, 24, 36, 250),
    panel   = Color(25, 34, 50, 245),
    header  = Color(28, 42, 68, 255),
    accent  = Color(70, 150, 255),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(230, 238, 250),
    dim     = Color(150, 165, 185),
    gold    = Color(245, 205, 80),
}

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -150, -50, 300, 100, Color(12, 18, 30, 240))
        draw.SimpleText("ПОЛИЦИЯ ПОРЯДКА", "DermaDefaultBold", 0, -25, Color(80, 160, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("OrdnungPolizei Terminal", "DermaDefault", 0, -5, Color(220, 230, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] для входа в систему", "DermaDefault", 0, 20, Color(150, 170, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

net.Receive("GRM_CompPolice_Open", function()
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

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, CC.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 40, CC.header, true, true, false, false)
        draw.SimpleText("ТЕРМИНАЛ УПРАВЛЕНИЯ • ПОЛИЦИЯ ПОРЯДКА (OrdnungPolizei)", "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕")
    btnClose:SetTextColor(CC.dim)
    btnClose.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(45, 55, 75))
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
    -- ВКЛАДКА 1: ОБЩАЯ БАЗА РОЗЫСКА (WANTED)
    -- ══════════════════════════════════════════════════════════════
    local wantPnl = vgui.Create("DPanel", tabs)
    wantPnl:DockPadding(12, 12, 12, 12)
    wantPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblWTarget = vgui.Create("DLabel", wantPnl)
    lblWTarget:SetPos(16, 12) lblWTarget:SetText("Объявление гражданина в розыск:") lblWTarget:SetFont("DermaDefaultBold") lblWTarget:SetTextColor(Color(255, 120, 100)) lblWTarget:SizeToContents()

    local comboWTarget = vgui.Create("DComboBox", wantPnl)
    comboWTarget:SetPos(16, 32) comboWTarget:SetSize(340, 26)
    comboWTarget:AddChoice("— Выберите гражданина онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboWTarget:AddChoice(string.format("%s  [%s]", pData.rpName or "?", pData.nick or "?"), pData)
    end

    local lblWReason = vgui.Create("DLabel", wantPnl)
    lblWReason:SetPos(366, 12) lblWReason:SetText("Статья / Причина розыска:") lblWReason:SetTextColor(CC.text) lblWReason:SizeToContents()
    local entWReason = vgui.Create("DTextEntry", wantPnl)
    entWReason:SetPos(366, 32) entWReason:SetSize(300, 26) entWReason:SetText("Нарушение общественного порядка")

    local lblWStars = vgui.Create("DLabel", wantPnl)
    lblWStars:SetPos(676, 12) lblWStars:SetText("Уровень опасности:") lblWStars:SetTextColor(CC.text) lblWStars:SizeToContents()
    local comboWStars = vgui.Create("DComboBox", wantPnl)
    comboWStars:SetPos(676, 32) comboWStars:SetSize(120, 26)
    comboWStars:AddChoice("★☆☆☆☆ (1 ур.)", 1)
    comboWStars:AddChoice("★★☆☆☆ (2 ур.)", 2)
    comboWStars:AddChoice("★★★☆☆ (3 ур.)", 3)
    comboWStars:AddChoice("★★★★☆ (4 ур.)", 4)
    comboWStars:AddChoice("★★★★★ (5 ур.)", 5)
    comboWStars:SetValue("★★☆☆☆ (2 ур.)")

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
    btnAddWanted:SetEnabled(true)
    btnAddWanted.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на изменение базы розыска!", NOTIFY_ERROR, 3) return end
        if selWKey == "" then notification.AddLegacy("Выберите гражданина!", NOTIFY_ERROR, 3) return end
        local _, lvl = comboWStars:GetSelected()
        -- Только серверный Result рисует тост. Раньше клиент сразу
        -- писал «ориентировка передана» и закрывал окно — при отказе
        -- ядра приходили два уведомления («нет прав» + «снят/передан»).
        GRM_CompTerminal_Send("wanted_add", selWKey, entWReason:GetText(), tonumber(lvl) or 2, "")
    end

    local listWanted = vgui.Create("DListView", wantPnl)
    listWanted:SetPos(16, 75)
    listWanted:SetSize(910, 480)
    listWanted:AddColumn("Уровень"):SetFixedWidth(84)
    -- Общий список: у каждой записи явно указан статус фигуранта.
    listWanted:AddColumn("Статус"):SetFixedWidth(104)
    listWanted:AddColumn("Разыскиваемый"):SetFixedWidth(210)
    listWanted:AddColumn("Статьи и ориентировки"):SetFixedWidth(370)
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
    btnClearWanted:SetText("✔ Снять с розыска (Задержан / Оправдан)")
    btnClearWanted:SetFont("DermaDefaultBold")
    btnClearWanted:SetTextColor(color_white)
    btnClearWanted.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnClearWanted.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на изменение базы розыска!", NOTIFY_ERROR, 3) return end
        local line = listWanted:GetSelectedLine()
        if not line then notification.AddLegacy("Выберите запись из списка!", NOTIFY_ERROR, 3) return end
        local row = listWanted:GetLine(line)
        if row and row._targetKey then
            -- Не снимаем строку и не рисуем тост до ответа сервера.
            GRM_CompTerminal_Send("wanted_clear", row._targetKey, "Снят с розыска в терминале OrdnungPolizei", 0, "")
        end
    end

    tabs:AddSheet("База розыска", wantPnl, "icon16/exclamation.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: ОБЩАЯ БАЗА ШТРАФОВ (FINES)
    -- ══════════════════════════════════════════════════════════════
    local finePnl = vgui.Create("DPanel", tabs)
    finePnl:DockPadding(16, 16, 16, 16)
    finePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblFTarget = vgui.Create("DLabel", finePnl)
    lblFTarget:SetPos(16, 16) lblFTarget:SetText("Оформление протокола о штрафе:") lblFTarget:SetFont("DermaDefaultBold") lblFTarget:SetTextColor(CC.gold) lblFTarget:SizeToContents()

    local comboFTarget = vgui.Create("DComboBox", finePnl)
    comboFTarget:SetPos(16, 38) comboFTarget:SetSize(360, 28)
    comboFTarget:AddChoice("— Выберите нарушителя онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboFTarget:AddChoice(string.format("%s  [%s]", pData.rpName or "?", pData.nick or "?"), pData)
    end

    local lblFAmount = vgui.Create("DLabel", finePnl)
    lblFAmount:SetPos(390, 16) lblFAmount:SetText("Сумма штрафа (GRM):") lblFAmount:SetTextColor(CC.text) lblFAmount:SizeToContents()
    local entFAmount = vgui.Create("DTextEntry", finePnl)
    entFAmount:SetPos(390, 38) entFAmount:SetSize(160, 28) entFAmount:SetText("2500")

    local lblFReason = vgui.Create("DLabel", finePnl)
    lblFReason:SetPos(16, 80) lblFReason:SetText("Основание / Статья правонарушения:") lblFReason:SetTextColor(CC.text) lblFReason:SizeToContents()
    local entFReason = vgui.Create("DTextEntry", finePnl)
    entFReason:SetPos(16, 102) entFReason:SetSize(534, 28) entFReason:SetText("Нарушение правил общественного порядка")

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
    btnIssueFine:SetText("Выписать электронный штраф")
    btnIssueFine:SetIcon("icon16/money.png")
    btnIssueFine:SetFont("DermaDefaultBold")
    btnIssueFine:SetTextColor(color_white)
    btnIssueFine.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(35, 140, 190) or Color(25, 110, 160)) end
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

    tabs:AddSheet("База штрафов", finePnl, "icon16/money.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 3: ПАСПОРТНЫЙ СТОЛ
    -- ══════════════════════════════════════════════════════════════
    local passPnl = vgui.Create("DPanel", tabs)
    passPnl:DockPadding(16, 16, 16, 16)
    passPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblP1 = vgui.Create("DLabel", passPnl)
    lblP1:SetPos(16, 16) lblP1:SetText("Оформление паспорта гражданина:") lblP1:SetFont("DermaDefaultBold") lblP1:SetTextColor(CC.accent) lblP1:SizeToContents()

    local comboPassTarget = vgui.Create("DComboBox", passPnl)
    comboPassTarget:SetPos(16, 38) comboPassTarget:SetSize(420, 28)
    comboPassTarget:AddChoice("— Выберите гражданина онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboPassTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.key or ""), pData)
    end

    local lblPName = vgui.Create("DLabel", passPnl)
    lblPName:SetPos(16, 75) lblPName:SetText("1. ФИО (ручной ввод):") lblPName:SetTextColor(CC.text) lblPName:SizeToContents()
    local entPassName = vgui.Create("DTextEntry", passPnl)
    entPassName:SetPos(16, 95) entPassName:SetSize(320, 26)

    local lblPGender = vgui.Create("DLabel", passPnl)
    lblPGender:SetPos(350, 75) lblPGender:SetText("2. Пол:") lblPGender:SetTextColor(CC.text) lblPGender:SizeToContents()
    local comboPassGender = vgui.Create("DComboBox", passPnl)
    comboPassGender:SetPos(350, 95) comboPassGender:SetSize(120, 26)
    comboPassGender:AddChoice("Мужской") comboPassGender:AddChoice("Женский") comboPassGender:SetValue("Мужской")

    local lblPBirth = vgui.Create("DLabel", passPnl)
    lblPBirth:SetPos(485, 75) lblPBirth:SetText("3. Дата рождения:") lblPBirth:SetTextColor(CC.text) lblPBirth:SizeToContents()
    local entPassBirth = vgui.Create("DTextEntry", passPnl)
    entPassBirth:SetPos(485, 95) entPassBirth:SetSize(140, 26) entPassBirth:SetText("12.04.1988")

    local lblPNat = vgui.Create("DLabel", passPnl)
    lblPNat:SetPos(16, 135) lblPNat:SetText("4. Гражданство (выбор / ручной ввод):") lblPNat:SetTextColor(CC.text) lblPNat:SizeToContents()
    local comboPassNat = vgui.Create("DComboBox", passPnl)
    comboPassNat:SetPos(16, 155) comboPassNat:SetSize(220, 26)
    comboPassNat:AddChoice("Гражданин Республики")
    comboPassNat:AddChoice("Иностранный гражданин")
    comboPassNat:AddChoice("Лицо без гражданства")
    comboPassNat:AddChoice("Подданный Королевства")
    comboPassNat:SetValue("Гражданин Республики")

    local entPassNat = vgui.Create("DTextEntry", passPnl)
    entPassNat:SetPos(245, 155) entPassNat:SetSize(225, 26)
    entPassNat:SetText("Гражданин Республики")

    comboPassNat.OnSelect = function(_, _, v)
        if v and v ~= "" then entPassNat:SetText(v) end
    end

    local lblPBPlace = vgui.Create("DLabel", passPnl)
    lblPBPlace:SetPos(485, 135) lblPBPlace:SetText("5. Место рождения (город / регион):") lblPBPlace:SetTextColor(CC.text) lblPBPlace:SizeToContents()
    local entPassBPlace = vgui.Create("DTextEntry", passPnl)
    entPassBPlace:SetPos(485, 155) entPassBPlace:SetSize(430, 26)
    entPassBPlace:SetText("г. Приморск, Республика Гранд")

    local lblPSeries = vgui.Create("DLabel", passPnl)
    lblPSeries:SetPos(16, 195) lblPSeries:SetText("6. Серия паспорта:") lblPSeries:SetTextColor(CC.text) lblPSeries:SizeToContents()
    local entPassSeries = vgui.Create("DTextEntry", passPnl)
    entPassSeries:SetPos(16, 215) entPassSeries:SetSize(120, 26) entPassSeries:SetText(tpls.passport and tpls.passport.defaultSeries or "GRM")

    local lblPNum = vgui.Create("DLabel", passPnl)
    lblPNum:SetPos(150, 195) lblPNum:SetText("7. Номер паспорта:") lblPNum:SetTextColor(CC.text) lblPNum:SizeToContents()
    local entPassNum = vgui.Create("DTextEntry", passPnl)
    entPassNum:SetPos(150, 215) entPassNum:SetSize(180, 26) entPassNum:SetText("01428901")

    local lblPIssuer = vgui.Create("DLabel", passPnl)
    lblPIssuer:SetPos(350, 195) lblPIssuer:SetText("8. Орган выдачи:") lblPIssuer:SetTextColor(CC.text) lblPIssuer:SizeToContents()
    local entPassIssuer = vgui.Create("DTextEntry", passPnl)
    entPassIssuer:SetPos(350, 215) entPassIssuer:SetSize(565, 26) entPassIssuer:SetText("Паспортный стол OrdnungPolizei")

    local selectedPassKey = ""
    local selectedPassSid64 = "0"
    comboPassTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selectedPassKey = pData.key or ""
            selectedPassSid64 = pData.steamID64 or "0"
            entPassName:SetText(pData.rpName or "")
            local shortSid = selectedPassSid64:sub(-6)
            entPassNum:SetText("01" .. shortSid)

            if registry.passports and registry.passports[selectedPassKey] then
                local ex = registry.passports[selectedPassKey]
                entPassName:SetText(ex.fullName or pData.rpName or "")
                entPassBirth:SetText(ex.birthDate or "12.04.1988")
                comboPassGender:SetValue(ex.gender or "Мужской")
                entPassNat:SetText(ex.nationality or "Гражданин Республики")
                entPassBPlace:SetText(ex.birthPlace or "г. Приморск, Республика Гранд")
                entPassSeries:SetText(ex.series or "GRM")
                entPassNum:SetText(ex.number or ("01" .. shortSid))
                entPassIssuer:SetText(ex.issuedBy or "Паспортный стол OrdnungPolizei")
            end
        end
    end

    local btnIssuePass = vgui.Create("DButton", passPnl)
    btnIssuePass:SetPos(16, 265) btnIssuePass:SetSize(360, 36)
    btnIssuePass:SetText("✔ Оформить и выдать паспорт")
    btnIssuePass:SetFont("DermaDefaultBold")
    btnIssuePass:SetTextColor(color_white)
    btnIssuePass.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnIssuePass.DoClick = function()
        if selectedPassKey == "" then notification.AddLegacy("Выберите гражданина!", NOTIFY_ERROR, 3) return end
        local pack = {
            fullName    = entPassName:GetText(),
            gender      = comboPassGender:GetValue(),
            birthDate   = entPassBirth:GetText(),
            nationality = entPassNat:GetText(),
            birthPlace  = entPassBPlace:GetText(),
            series      = entPassSeries:GetText(),
            number      = entPassNum:GetText(),
            issuedBy    = entPassIssuer:GetText(),
            issueDate   = os.date("%d.%m.%Y"),
            validUntil  = "Бессрочно",
            status      = "Действителен",
            steamID64   = selectedPassSid64,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("passport")
            net.WriteString(selectedPassKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Паспортный стол", passPnl, "icon16/book.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 4: ОТДЕЛ КАДРОВ ORDNUNGPOLIZEI
    -- ══════════════════════════════════════════════════════════════
    local badgePnl = vgui.Create("DPanel", tabs)
    badgePnl:DockPadding(16, 16, 16, 16)
    badgePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblBTarget = vgui.Create("DLabel", badgePnl)
    lblBTarget:SetPos(16, 16) lblBTarget:SetText("Служебные удостоверения сотрудников OrdnungPolizei:") lblBTarget:SetFont("DermaDefaultBold") lblBTarget:SetTextColor(CC.accent) lblBTarget:SizeToContents()

    local comboBadgeTarget = vgui.Create("DComboBox", badgePnl)
    comboBadgeTarget:SetPos(16, 36) comboBadgeTarget:SetSize(420, 28)
    comboBadgeTarget:AddChoice("— Выберите сотрудника полиции —", "")
    for _, pData in ipairs(onlineList) do
        if (pData.faction or ""):lower():find("ordnung") or (pData.faction or ""):lower():find("polizei") or isSuperAdmin then
            comboBadgeTarget:AddChoice(string.format("%s  [%s]  — %s", pData.rpName or "?", pData.nick or "?", pData.role or "Сотрудник"), pData)
        end
    end

    local lblBName = vgui.Create("DLabel", badgePnl)
    lblBName:SetPos(16, 75) lblBName:SetText("ФИО сотрудника:") lblBName:SetTextColor(CC.text) lblBName:SizeToContents()
    local entBadgeName = vgui.Create("DTextEntry", badgePnl)
    entBadgeName:SetPos(16, 95) entBadgeName:SetSize(280, 26)

    local lblBRole = vgui.Create("DLabel", badgePnl)
    lblBRole:SetPos(310, 75) lblBRole:SetText("Звание / Должность:") lblBRole:SetTextColor(CC.text) lblBRole:SizeToContents()
    local entBadgeRole = vgui.Create("DTextEntry", badgePnl)
    entBadgeRole:SetPos(310, 95) entBadgeRole:SetSize(200, 26)

    local lblBDept = vgui.Create("DLabel", badgePnl)
    lblBDept:SetPos(16, 135) lblBDept:SetText("Отдел полиции:") lblBDept:SetTextColor(CC.text) lblBDept:SizeToContents()
    local entBadgeDept = vgui.Create("DTextEntry", badgePnl)
    entBadgeDept:SetPos(16, 155) entBadgeDept:SetSize(280, 26) entBadgeDept:SetText("Патрульно-постовая служба")

    local lblBNum = vgui.Create("DLabel", badgePnl)
    lblBNum:SetPos(310, 135) lblBNum:SetText("Номер жетона:") lblBNum:SetTextColor(CC.text) lblBNum:SizeToContents()
    local entBadgeNum = vgui.Create("DTextEntry", badgePnl)
    entBadgeNum:SetPos(310, 155) entBadgeNum:SetSize(200, 26) entBadgeNum:SetText("POL-0001")

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
            entBadgeRole:SetText(pData.role or "Офицер полиции")
            entBadgeDept:SetText(pData.department or "Патрульная служба")
            local shortSid = selectedBadgeSid64:sub(-4)
            entBadgeNum:SetText("POL-" .. shortSid)

            if registry.badges and registry.badges[selectedBadgeKey] then
                local ex = registry.badges[selectedBadgeKey]
                entBadgeName:SetText(ex.fullName or pData.rpName or "")
                entBadgeRole:SetText(ex.role or pData.role or "")
                entBadgeDept:SetText(ex.department or "Патрульная служба")
                entBadgeNum:SetText(ex.number or ("POL-" .. shortSid))
                if istable(ex.permissions) then
                    for pId, cb in pairs(chkBoxes) do cb:SetValue(ex.permissions[pId] == true) end
                end
            end
        end
    end

    local btnIssueBadge = vgui.Create("DButton", badgePnl)
    btnIssueBadge:SetPos(16, yPos + 180) btnIssueBadge:SetSize(320, 36)
    btnIssueBadge:SetText("✔ Выдать удостоверение OrdnungPolizei")
    btnIssueBadge:SetFont("DermaDefaultBold")
    btnIssueBadge:SetTextColor(color_white)
    btnIssueBadge.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnIssueBadge.DoClick = function()
        if selectedBadgeKey == "" then notification.AddLegacy("Выберите сотрудника!", NOTIFY_ERROR, 3) return end
        local curPerms = {}
        for pId, cb in pairs(chkBoxes) do curPerms[pId] = cb:GetChecked() end
        local pack = {
            fullName    = entBadgeName:GetText(),
            faction     = "OrdnungPolizei",
            role        = entBadgeRole:GetText(),
            department  = entBadgeDept:GetText(),
            number      = entBadgeNum:GetText(),
            permissions = curPerms,
            issuedBy    = "Руководство OrdnungPolizei",
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

    tabs:AddSheet("Отдел кадров OrdnungPolizei", badgePnl, "icon16/shield.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 5: ЛИЦЕНЗИРОВАНИЕ ОРУЖИЯ (ОЛРР)
    -- ══════════════════════════════════════════════════════════════
    local licPnl=vgui.Create("DPanel",tabs); licPnl.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,CC.panel)end
    local title=vgui.Create("DLabel",licPnl); title:SetPos(16,16); title:SetSize(880,24); title:SetFont("DermaDefaultBold"); title:SetTextColor(CC.gold); title:SetText("ОЛРР • ВЫДАЧА ЛИЦЕНЗИИ НА ОРУЖИЕ")
    local target=vgui.Create("DComboBox",licPnl); target:SetPos(16,50); target:SetSize(420,28); target:AddChoice("— Выберите гражданина —","")
    for _,pd in ipairs(onlineList)do target:AddChoice((pd.rpName or"?").."  ["..(pd.nick or"?").."]",pd)end
    local selectedKey,selectedSid="","0"
    local name=vgui.Create("DTextEntry",licPnl); name:SetPos(16,94); name:SetSize(300,28); name:SetPlaceholderText("ФИО владельца")
    local birth=vgui.Create("DTextEntry",licPnl); birth:SetPos(330,94); birth:SetSize(150,28); birth:SetPlaceholderText("Дата рождения")
    local number=vgui.Create("DTextEntry",licPnl); number:SetPos(494,94); number:SetSize(180,28); number:SetPlaceholderText("ЛО-000000")
    local valid=vgui.Create("DTextEntry",licPnl); valid:SetPos(688,94); valid:SetSize(220,28); valid:SetText("5 лет")
    local cats={}; local x,y=16,150
    for _,cd in ipairs(GRM.Documents and GRM.Documents.WeaponCategories or{})do local cb=vgui.Create("DCheckBoxLabel",licPnl); cb:SetPos(x,y); cb:SetSize(280,24); cb:SetText(cd.name); cb:SetTextColor(CC.text); cats[cd.id]=cb; x=x+300;if x>650 then x=16;y=y+30 end end
    local restrictions=vgui.Create("DTextEntry",licPnl); restrictions:SetPos(16,250); restrictions:SetSize(892,70); restrictions:SetMultiline(true); restrictions:SetPlaceholderText("Особые условия хранения и ношения")
    target.OnSelect=function(_,_,_,pd)
        if not istable(pd)then return end; selectedKey=pd.key or"";selectedSid=pd.steamID64 or"0";name:SetText(pd.rpName or"");number:SetText("ЛО-"..selectedSid:sub(-6))
        local ex=registry.weaponLicenses and registry.weaponLicenses[selectedKey]
        if ex then name:SetText(ex.fullName or pd.rpName or"");birth:SetText(ex.birthDate or"");number:SetText(ex.number or"");valid:SetText(ex.validUntil or"5 лет");restrictions:SetText(ex.restrictions or"");for id,cb in pairs(cats)do cb:SetValue(ex.categories and ex.categories[id]==true)end end
    end
    local exam=vgui.Create("DButton",licPnl); exam:SetPos(16,340); exam:SetSize(280,38); exam:SetText("ПРОВЕСТИ ЭКЗАМЕН"); exam:SetTextColor(color_white); exam.Paint=function(s,w,h)draw.RoundedBox(5,0,0,w,h,s:IsHovered()and Color(80,130,210)or CC.accent)end
    exam.DoClick=function()if selectedKey==""then return end;if GRM.Documents and GRM.Documents.StartExam then GRM.Documents.StartExam("weaponLicense",selectedKey)end end
    local issue=vgui.Create("DButton",licPnl); issue:SetPos(310,340); issue:SetSize(360,38); issue:SetText("ВЫДАТЬ ЛИЦЕНЗИЮ И БЛАНК"); issue:SetTextColor(color_white); issue.Paint=function(s,w,h)draw.RoundedBox(5,0,0,w,h,s:IsHovered()and Color(70,210,120)or CC.success)end
    issue.DoClick=function()
        if selectedKey==""then notification.AddLegacy("Выберите гражданина",NOTIFY_ERROR,3)return end
        local selected={};for id,cb in pairs(cats)do selected[id]=cb:GetChecked()end
        net.Start("GRM_Doc_ComputerIssue");net.WriteString("weaponLicense");net.WriteString(selectedKey);net.WriteTable({fullName=name:GetValue(),birthDate=birth:GetValue(),number=number:GetValue(),categories=selected,restrictions=restrictions:GetValue(),issuedBy="ОЛРР OrdnungPolizei",issueDate=os.date("%d.%m.%Y"),validUntil=valid:GetValue(),status="Действительна",steamID64=selectedSid});net.SendToServer();frame:Close()
    end
    local revoke=vgui.Create("DButton",licPnl);revoke:SetPos(684,340);revoke:SetSize(224,38);revoke:SetText("АННУЛИРОВАТЬ");revoke:SetTextColor(color_white);revoke.Paint=function(s,w,h)draw.RoundedBox(5,0,0,w,h,s:IsHovered()and Color(235,80,80)or CC.danger)end
    revoke.DoClick=function()if selectedKey==""then return end;net.Start("GRM_Doc_ComputerRevoke");net.WriteString("weaponLicense");net.WriteString(selectedKey);net.SendToServer();frame:Close()end
    tabs:AddSheet("Лицензии на оружие",licPnl,"icon16/key.png")

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
