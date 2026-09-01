--[[--------------------------------------------------------------------
    grm_comp_court — cl_init.lua (Клиентская часть компьютера юстиции)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(22, 24, 34, 250),
    panel   = Color(28, 32, 46, 245),
    header  = Color(36, 40, 58, 255),
    accent  = Color(200, 170, 255),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    gold    = Color(245, 200, 70),
    text    = Color(235, 238, 245),
    dim     = Color(150, 158, 175),
}

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -150, -50, 300, 100, Color(20, 20, 32, 240))
        draw.SimpleText("ЮСТИЦИЯ", "DermaDefaultBold", 0, -24, Color(200, 170, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Суд и прокуратура", "DermaDefault", 0, -4, Color(225, 230, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] для входа", "DermaDefault", 0, 20, Color(165, 175, 185), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

local function money(v)
    v = tonumber(v) or 0
    local s = tostring(math.floor(v))
    local out = ""
    while #s > 3 do out = " " .. s:sub(-3) .. out s = s:sub(1, -4) end
    return s .. out
end

local function levelShort(levels, lvl)
    local l = levels[tonumber(lvl) or 0] or levels[0]
    return (l and l.short) or tostring(lvl or 0)
end

local function mkBtn(parent, text, col, doClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetFont("DermaDefaultBold")
    b:SetTextColor(color_white)
    b.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(col.r + 20, col.g + 20, col.b + 20) or col)
        surface.SetDrawColor(255, 255, 255, 40)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(text, "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() surface.PlaySound("buttons/button15.wav") if doClick then doClick() end end
    return b
end

net.Receive("GRM_CompCourt_Open", function()
    local ent = net.ReadEntity()
    local info = net.ReadTable() or {}
    local wanted = net.ReadTable() or {}
    local catalog = net.ReadTable() or {}
    local levels = net.ReadTable() or {}
    local fines = net.ReadTable() or {}
    local online = net.ReadTable() or {}
    local warrants = net.ReadTable() or {}

    if not IsValid(ent) then return end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("")
    -- Окно терминала тянется под экран: вкладок много, и на фиксированных
    -- 960x700 верхний ряд уезжал за край (заказ владельца 21.08).
    frame:SetSize(math.Clamp(ScrW() * 0.86, 1180, 1720), math.Clamp(ScrH() * 0.88, 760, 1080))
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, CC.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 42, CC.header, true, true, false, false)
        draw.SimpleText(info.name or "ЮСТИЦИЯ", "DermaDefaultBold", 16, 21, CC.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Суд · прокуратура · реестр штрафов", "DermaDefault", w - 16, 21, CC.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24) btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕") btnClose:SetTextColor(CC.dim) btnClose:SetFont("DermaDefaultBold")
    btnClose.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(45, 50, 60)) end
    btnClose.DoClick = function() frame:Close() end

    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL) tabs:DockMargin(6, 46, 6, 6)
    if GRM.ServiceOrders and GRM.ServiceOrders.AttachTab then GRM.ServiceOrders.AttachTab(tabs) end
    -- Вкладка «Госбаза»: тот же /pcboard, что и по команде, одним кодом.
    if GRM.PCBoard and GRM.PCBoard.AttachTab then GRM.PCBoard.AttachTab(tabs) end
    -- Вкладка «Автопарк»: закупка техники организацией и её выдача в гараже.
    if GRM.Fleet and GRM.Fleet.AttachTab then GRM.Fleet.AttachTab(tabs) end
    -- Вкладка «Номерные знаки»: выдача и проверка регистрационных номеров.
    if GRM.Plates and GRM.Plates.AttachTab then GRM.Plates.AttachTab(tabs) end

    -- ════════════ ВКЛАДКА 1: ЗАКОНЫ И СТАТЬИ ════════════
    local lawPnl = vgui.Create("DPanel", tabs)
    lawPnl:DockPadding(8, 8, 8, 8)
    lawPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
    local lawList = vgui.Create("DListView", lawPnl)
    lawList:Dock(FILL)
    lawList:AddColumn("Код"):SetFixedWidth(70)
    lawList:AddColumn("Статья"):SetFixedWidth(320)
    lawList:AddColumn("Тип"):SetFixedWidth(120)
    lawList:AddColumn("Штраф"):SetFixedWidth(110)
    lawList:AddColumn("Уровень"):SetFixedWidth(80)
    for _, a in ipairs(catalog) do
        lawList:AddLine(a.code or a.id, a.title or "?", (a.type == "crime" and "Уголовное") or "Админ.", money(a.fine), levelShort(levels, a.defaultLevel))
    end
    tabs:AddSheet("Законы и статьи", lawPnl, "icon16/book.png")

    -- ════════════ ВКЛАДКА 2: РОЗЫСК ════════════
    local wanPnl = vgui.Create("DPanel", tabs)
    wanPnl:DockPadding(8, 8, 8, 8)
    wanPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
    local wanList = vgui.Create("DListView", wanPnl)
    wanList:Dock(FILL)
    wanList:AddColumn("Имя"):SetFixedWidth(220)
    wanList:AddColumn("Уровень"):SetFixedWidth(140)
    wanList:AddColumn("Статей"):SetFixedWidth(80)
    wanList:AddColumn("Штрафы"):SetFixedWidth(120)
    for _, r in ipairs(wanted) do
        wanList:AddLine(r.name, levelShort(levels, r.level) .. " (" .. tostring(r.level) .. ")", tostring(r.reasons), money(r.totalFine))
    end
    tabs:AddSheet("Розыск", wanPnl, "icon16/user_red.png")

    -- ════════════ ВКЛАДКА 3: ШТРАФЫ ════════════
    local finPnl = vgui.Create("DPanel", tabs)
    finPnl:DockPadding(8, 8, 8, 8)
    finPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local finList = vgui.Create("DListView", finPnl)
    finList:Dock(TOP) finList:SetTall(280)
    finList:AddColumn("№"):SetFixedWidth(60)
    finList:AddColumn("Имя"):SetFixedWidth(180)
    finList:AddColumn("Сумма"):SetFixedWidth(100)
    finList:AddColumn("Оплачено"):SetFixedWidth(100)
    finList:AddColumn("Статус"):SetFixedWidth(120)
    finList:AddColumn("Причина"):SetFixedWidth(280)
    for _, rec in ipairs(fines) do
        local st = rec.status == "paid" and "Оплачен" or (rec.status == "cancelled" and "Аннулирован" or "Не оплачен")
        local line = finList:AddLine(tostring(rec.id), rec.targetName or "?", money(rec.amount), money(rec.paid), st, rec.reason or "")
        line._id = rec.id
    end

    -- Форма выписки судебного штрафа.
    local formPnl = vgui.Create("DPanel", finPnl)
    formPnl:Dock(TOP) formPnl:DockMargin(0, 8, 0, 8) formPnl:SetTall(150)
    formPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(24, 30, 44)) end

    local lblT = vgui.Create("DLabel", formPnl)
    lblT:SetPos(12, 10) lblT:SetText("Гражданин (онлайн):") lblT:SetFont("DermaDefaultBold") lblT:SetTextColor(CC.accent) lblT:SizeToContents()
    local comboT = vgui.Create("DComboBox", formPnl)
    comboT:SetPos(12, 30) comboT:SetSize(300, 26)
    comboT:AddChoice("— выберите гражданина —", "")
    for _, p in ipairs(online) do comboT:AddChoice(string.format("%s [%s]", p.rpName or "?", p.nick or "?"), p) end
    local selKey = ""

    local lblA = vgui.Create("DLabel", formPnl)
    lblA:SetPos(330, 10) lblA:SetText("Сумма штрафа:") lblA:SetFont("DermaDefaultBold") lblA:SetTextColor(CC.accent) lblA:SizeToContents()
    local entA = vgui.Create("DNumberWang", formPnl)
    entA:SetPos(330, 30) entA:SetSize(140, 26) entA:SetMin(1) entA:SetMax(100000000) entA:SetValue(5000)

    local lblArt = vgui.Create("DLabel", formPnl)
    lblArt:SetPos(12, 64) lblArt:SetText("Статья (основание):") lblArt:SetFont("DermaDefaultBold") lblArt:SetTextColor(CC.accent) lblArt:SizeToContents()
    local comboArt = vgui.Create("DComboBox", formPnl)
    comboArt:SetPos(12, 84) comboArt:SetSize(300, 26)
    comboArt:AddChoice("— без статьи —", "")
    for _, a in ipairs(catalog) do comboArt:AddChoice((a.code or a.id) .. " " .. (a.title or ""), a.id) end

    local lblR = vgui.Create("DLabel", formPnl)
    lblR:SetPos(330, 64) lblR:SetText("Причина (текст решения):") lblR:SetFont("DermaDefaultBold") lblR:SetTextColor(CC.accent) lblR:SizeToContents()
    local entR = vgui.Create("DTextEntry", formPnl)
    entR:SetPos(330, 84) entR:SetSize(480, 26) entR:SetText("Судебное решение")

    comboT.OnSelect = function(_, _, _, pData) if istable(pData) then selKey = pData.key or "" end end

    local btnIssue = mkBtn(formPnl, "⚖ Выписать судебный штраф", Color(120, 90, 180), function()
        if selKey == "" then notification.AddLegacy("Выберите гражданина!", NOTIFY_ERROR, 3) return end
        local _, artID = comboArt:GetSelected()
        net.Start("GRM_CompCourt_Action")
            net.WriteEntity(ent)
            net.WriteString("fine_issue")
            net.WriteString(selKey)
            net.WriteString(tostring(entA:GetValue()))
            net.WriteString(entR:GetText())
            net.WriteString(artID or "")
        net.SendToServer()
    end)
    btnIssue:SetPos(12, 118) btnIssue:SetSize(240, 28)

    local btnCancel = mkBtn(formPnl, "✕ Аннулировать выбранный", CC.danger, function()
        local l = finList:GetSelectedLine()
        if not l then notification.AddLegacy("Выберите штраф в реестре!", NOTIFY_ERROR, 3) return end
        local row = finList:GetLine(l)
        if row and row._id then
            net.Start("GRM_CompCourt_Action")
                net.WriteEntity(ent)
                net.WriteString("fine_cancel")
                net.WriteString(tostring(row._id))
                net.WriteString("решение суда")
            net.SendToServer()
        end
    end)
    btnCancel:SetPos(264, 118) btnCancel:SetSize(240, 28)

    tabs:AddSheet("Штрафы", finPnl, "icon16/money.png")

    -- ════════════ ВКЛАДКА 4: СУДЕБНЫЕ ОРДЕРА И ХОДАТАЙСТВА ════════════
    local warPnl = vgui.Create("DPanel", tabs)
    warPnl:DockPadding(8, 8, 8, 8)
    warPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local warList = vgui.Create("DListView", warPnl)
    warList:Dock(TOP) warList:SetTall(250)
    warList:AddColumn("№ ордера"):SetFixedWidth(90)
    warList:AddColumn("Тип ордера"):SetFixedWidth(140)
    warList:AddColumn("Фигурант / Адрес"):SetFixedWidth(200)
    warList:AddColumn("Статус"):SetFixedWidth(100)
    warList:AddColumn("Инициатор / Судья"):SetFixedWidth(160)
    warList:AddColumn("Срок действия"):SetFixedWidth(120)

    local warrantTypeLabels = {
        search = "Обыск жилища",
        arrest = "Арест и захват",
        wiretap_judge = "Надзор за судьёй",
        eviction = "Опечатывание",
    }

    for _, w in ipairs(warrants) do
        local tLabel = warrantTypeLabels[w.type or "search"] or tostring(w.type or "Ордер")
        local statusLabel = (w.status == "pending") and "ХОДАТАЙСТВО" or ((w.status == "active") and "АКТИВЕН" or tostring(w.status or "—"))
        local exp = tonumber(w.expires or w.expiresAt) or 0
        local timeLeft = exp > os.time() and (tostring(math.ceil((exp - os.time()) / 60)) .. " мин.") or "Истёк"
        local targetText = tostring(w.name or w.sid or "?")
        if w.propertyId and w.propertyId ~= "" then targetText = targetText .. " (" .. w.propertyId .. ")" end
        local byText = tostring(w.byNick or w.by or "?")
        if w.approvedByName and w.approvedByName ~= "" then byText = byText .. " / " .. w.approvedByName end

        local line = warList:AddLine(tostring(w.id or w.sid), tLabel, targetText, statusLabel, byText, timeLeft)
        line._warrant = w
    end

    local warFormPnl = vgui.Create("DPanel", warPnl)
    warFormPnl:Dock(FILL) warFormPnl:DockMargin(0, 8, 0, 0)
    warFormPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(24, 30, 44)) end

    local lblWTarget = vgui.Create("DLabel", warFormPnl)
    lblWTarget:SetPos(12, 10) lblWTarget:SetText("Фигурант (гражданин):") lblWTarget:SetFont("DermaDefaultBold") lblWTarget:SetTextColor(CC.gold) lblWTarget:SizeToContents()
    local comboWTarget = vgui.Create("DComboBox", warFormPnl)
    comboWTarget:SetPos(12, 28) comboWTarget:SetSize(240, 24)
    comboWTarget:AddChoice("— выберите гражданина —", "")
    for _, p in ipairs(online) do comboWTarget:AddChoice(string.format("%s [%s]", p.rpName or "?", p.nick or "?"), p) end
    local selWKey = ""
    comboWTarget.OnSelect = function(_, _, _, pData) if istable(pData) then selWKey = pData.key or "" end end

    local lblWType = vgui.Create("DLabel", warFormPnl)
    lblWType:SetPos(265, 10) lblWType:SetText("Тип судебного ордера:") lblWType:SetFont("DermaDefaultBold") lblWType:SetTextColor(CC.gold) lblWType:SizeToContents()
    local comboWType = vgui.Create("DComboBox", warFormPnl)
    comboWType:SetPos(265, 28) comboWType:SetSize(180, 24)
    comboWType:AddChoice("Обыск жилища (Search)", "search", true)
    comboWType:AddChoice("Принудительный арест", "arrest")
    comboWType:AddChoice("Надзор за судьёй", "wiretap_judge")
    comboWType:AddChoice("Опечатывание помещения", "eviction")

    local lblWMins = vgui.Create("DLabel", warFormPnl)
    lblWMins:SetPos(460, 10) lblWMins:SetText("Срок (мин):") lblWMins:SetFont("DermaDefaultBold") lblWMins:SetTextColor(CC.gold) lblWMins:SizeToContents()
    local entWMins = vgui.Create("DNumberWang", warFormPnl)
    entWMins:SetPos(460, 28) entWMins:SetSize(70, 24) entWMins:SetMin(10) entWMins:SetMax(1440) entWMins:SetValue(60)

    local lblWReason = vgui.Create("DLabel", warFormPnl)
    lblWReason:SetPos(12, 60) lblWReason:SetText("Основание / Статья / Помещение:") lblWReason:SetFont("DermaDefaultBold") lblWReason:SetTextColor(CC.gold) lblWReason:SizeToContents()
    local entWReason = vgui.Create("DTextEntry", warFormPnl)
    entWReason:SetPos(12, 78) entWReason:SetSize(520, 24) entWReason:SetText("Подозрение в совершении тяжкого преступления")

    local btnReq = mkBtn(warFormPnl, "⚖ Подать ходатайство", Color(80, 140, 220), function()
        if selWKey == "" then notification.AddLegacy("Выберите фигуранта!", NOTIFY_ERROR, 3) return end
        local _, wType = comboWType:GetSelected()
        net.Start("GRM_CompCourt_Action")
            net.WriteEntity(ent)
            net.WriteString("warrant_request")
            net.WriteString(selWKey)
            net.WriteString(tostring(wType or "search"))
            net.WriteUInt(math.floor(entWMins:GetValue() or 60), 16)
            net.WriteString(entWReason:GetText())
            net.WriteString("")
        net.SendToServer()
    end)
    btnReq:SetPos(12, 112) btnReq:SetSize(170, 28)

    local btnApprove = mkBtn(warFormPnl, "✔ Утвердить ордер", CC.success, function()
        local l = warList:GetSelectedLine()
        if not l then notification.AddLegacy("Выберите ходатайство в списке!", NOTIFY_ERROR, 3) return end
        local row = warList:GetLine(l)
        local w = row and row._warrant
        if w and w.id then
            net.Start("GRM_CompCourt_Action")
                net.WriteEntity(ent)
                net.WriteString("warrant_approve")
                net.WriteString(tostring(w.id))
                net.WriteUInt(math.floor(entWMins:GetValue() or 60), 16)
            net.SendToServer()
        end
    end)
    btnApprove:SetPos(190, 112) btnApprove:SetSize(160, 28)

    local btnReject = mkBtn(warFormPnl, "✕ Отклонить", CC.danger, function()
        local l = warList:GetSelectedLine()
        if not l then notification.AddLegacy("Выберите ходатайство в списке!", NOTIFY_ERROR, 3) return end
        local row = warList:GetLine(l)
        local w = row and row._warrant
        if w and w.id then
            net.Start("GRM_CompCourt_Action")
                net.WriteEntity(ent)
                net.WriteString("warrant_reject")
                net.WriteString(tostring(w.id))
                net.WriteString("Отклонено судом")
            net.SendToServer()
        end
    end)
    btnReject:SetPos(360, 112) btnReject:SetSize(140, 28)

    local btnRevoke = mkBtn(warFormPnl, "Отозвать ордер", Color(120, 120, 130), function()
        local l = warList:GetSelectedLine()
        if not l then notification.AddLegacy("Выберите ордер в списке!", NOTIFY_ERROR, 3) return end
        local row = warList:GetLine(l)
        local w = row and row._warrant
        if w and w.sid then
            net.Start("GRM_CompCourt_Action")
                net.WriteEntity(ent)
                net.WriteString("warrant_revoke")
                net.WriteString(tostring(w.sid))
            net.SendToServer()
        end
    end)
    btnRevoke:SetPos(510, 112) btnRevoke:SetSize(140, 28)

    tabs:AddSheet("Судебные ордера", warPnl, "icon16/page_white_star.png")
end)
