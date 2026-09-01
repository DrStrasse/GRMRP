--[[--------------------------------------------------------------------
    grm_comp_cityhall — cl_init.lua (Клиентская часть компьютера мэрии)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(20, 28, 32, 250),
    panel   = Color(26, 36, 40, 245),
    header  = Color(30, 44, 50, 255),
    accent  = Color(80, 200, 200),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(230, 238, 240),
    dim     = Color(150, 165, 170),
    gold    = Color(245, 200, 70),
}

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

local function money(v)
    v = tonumber(v) or 0
    local s = tostring(math.floor(v))
    local out = ""
    while #s > 3 do out = " " .. s:sub(-3) .. out s = s:sub(1, -4) end
    return s .. out .. " GRM"
end

net.Receive("GRM_CityHall_Open", function()
    local ent = net.ReadEntity()
    local onlineList = net.ReadTable() or {}
    local bizTpl = net.ReadTable() or {}
    local ov = net.ReadTable() or {}
    local isSuper = net.ReadBool()

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
        draw.SimpleText("МЭРИЯ • ГОРОДСКАЯ АДМИНИСТРАЦИЯ", "DermaDefaultBold", 16, 21, CC.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Бизнес-лицензии и городская казна", "DermaDefault", w - 16, 21, CC.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24) btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕") btnClose:SetTextColor(CC.dim) btnClose:SetFont("DermaDefaultBold")
    btnClose.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(40, 50, 55)) end
    btnClose.DoClick = function() frame:Close() end

    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL) tabs:DockMargin(6, 46, 6, 6)
    if GRM.ServiceOrders and GRM.ServiceOrders.AttachTab then GRM.ServiceOrders.AttachTab(tabs) end
    -- Вкладка «Госбаза»: тот же /pcboard, что и по команде, одним кодом.
    if GRM.PCBoard and GRM.PCBoard.AttachTab then GRM.PCBoard.AttachTab(tabs) end
    -- Вкладка «Номерные знаки»: выдача и проверка регистрационных номеров.
    if GRM.Plates and GRM.Plates.AttachTab then GRM.Plates.AttachTab(tabs) end
    -- Вкладка «Автопарк»: закупка техники организацией и её выдача в гараже.
    if GRM.Fleet and GRM.Fleet.AttachTab then GRM.Fleet.AttachTab(tabs) end

    -- ════════════ ВКЛАДКА 1: ВЫДАЧА ЛИЦЕНЗИИ НА БИЗНЕС ════════════
    local issuePnl = vgui.Create("DPanel", tabs)
    issuePnl:DockPadding(12, 12, 12, 12)
    issuePnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblTarget = vgui.Create("DLabel", issuePnl)
    lblTarget:SetPos(16, 10) lblTarget:SetText("Владелец бизнеса (онлайн):") lblTarget:SetFont("DermaDefaultBold") lblTarget:SetTextColor(CC.accent) lblTarget:SizeToContents()
    local comboTarget = vgui.Create("DComboBox", issuePnl)
    comboTarget:SetPos(16, 32) comboTarget:SetSize(460, 28)
    comboTarget:AddChoice("— выберите владельца —", "")
    for _, pData in ipairs(onlineList) do
        comboTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.key or ""), pData)
    end

    local selKey, selSid = "", "0"

    local lblName = vgui.Create("DLabel", issuePnl)
    lblName:SetPos(16, 74) lblName:SetText("Наименование бизнеса:") lblName:SetTextColor(CC.text) lblName:SizeToContents()
    local entName = vgui.Create("DTextEntry", issuePnl)
    entName:SetPos(16, 94) entName:SetSize(360, 26)

    local lblOwner = vgui.Create("DLabel", issuePnl)
    lblOwner:SetPos(390, 74) lblOwner:SetText("ФИО владельца:") lblOwner:SetTextColor(CC.text) lblOwner:SizeToContents()
    local entOwner = vgui.Create("DTextEntry", issuePnl)
    entOwner:SetPos(390, 94) entOwner:SetSize(360, 26)

    local pfx = bizTpl.prefix or "БЛ-"
    local lblNum = vgui.Create("DLabel", issuePnl)
    lblNum:SetPos(16, 130) lblNum:SetText("Номер лицензии:") lblNum:SetTextColor(CC.text) lblNum:SizeToContents()
    local entNum = vgui.Create("DTextEntry", issuePnl)
    entNum:SetPos(16, 150) entNum:SetSize(200, 26) entNum:SetText(pfx .. "000000")

    local lblType = vgui.Create("DLabel", issuePnl)
    lblType:SetPos(230, 130) lblType:SetText("Вид деятельности:") lblType:SetTextColor(CC.text) lblType:SizeToContents()
    local comboType = vgui.Create("DComboBox", issuePnl)
    comboType:SetPos(230, 150) comboType:SetSize(340, 26)
    for _, bt in ipairs((GRM.Documents and GRM.Documents.BusinessTypes) or {}) do
        comboType:AddChoice(bt.name .. " — " .. bt.desc, bt.id)
    end
    comboType:ChooseOptionID(1)

    local lblAddr = vgui.Create("DLabel", issuePnl)
    lblAddr:SetPos(16, 186) lblAddr:SetText("Адрес / объект:") lblAddr:SetTextColor(CC.text) lblAddr:SizeToContents()
    local entAddr = vgui.Create("DTextEntry", issuePnl)
    entAddr:SetPos(16, 206) entAddr:SetSize(460, 26)

    local lblYears = vgui.Create("DLabel", issuePnl)
    lblYears:SetPos(16, 242) lblYears:SetText("Срок (лет):") lblYears:SetTextColor(CC.text) lblYears:SizeToContents()
    local entYears = vgui.Create("DNumberWang", issuePnl)
    entYears:SetPos(100, 240) entYears:SetSize(80, 26) entYears:SetMin(1) entYears:SetMax(10) entYears:SetValue(1)

    comboTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selKey = pData.key or ""
            selSid = pData.steamID64 or "0"
            entOwner:SetText(pData.rpName or "")
            entNum:SetText(pfx .. selSid:sub(-5))
        end
    end

    local fee = tonumber(bizTpl.fee) or 3000
    local lblFee = vgui.Create("DLabel", issuePnl)
    lblFee:SetPos(16, 280) lblFee:SetText("Госпошлина (спишется при выдаче): " .. money(fee)) lblFee:SetFont("DermaDefaultBold") lblFee:SetTextColor(CC.gold) lblFee:SizeToContents()

    local btnExam = mkBtn(issuePnl, "📝 Экзамен (теория бизнеса)", Color(150, 110, 60), function()
        if GRM.Documents and GRM.Documents.StartExam then GRM.Documents.StartExam("businessLicense", selKey) end
    end)
    btnExam:SetPos(16, 316) btnExam:SetSize(220, 34)

    local btnIssue = mkBtn(issuePnl, "✔ Выдать лицензию", Color(30, 140, 120), function()
        if selKey == "" then notification.AddLegacy("Выберите владельца из списка!", NOTIFY_ERROR, 3) return end
        if entName:GetText() == "" then notification.AddLegacy("Укажите наименование бизнеса!", NOTIFY_ERROR, 3) return end
        local _, bType = comboType:GetSelected()
        local years = entYears:GetValue() or 1
        local typeName = bType or "other"
        for _, bt in ipairs((GRM.Documents and GRM.Documents.BusinessTypes) or {}) do if bt.id == bType then typeName = bt.name end end
        local pack = {
            businessName = entName:GetText(),
            fullName = entOwner:GetText(),
            number = entNum:GetText(),
            businessType = bType or "other",
            businessTypeName = typeName,
            address = entAddr:GetText(),
            restrictions = "",
            issuedBy = bizTpl.issuer or "Экономическое управление",
            issueDate = os.date("%d.%m.%Y"),
            validUntil = tostring(years) .. " год(а)",
            expiry = os.time() + years * 365 * 24 * 3600,
            status = "Действительна",
            steamID64 = selSid,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("businessLicense")
            net.WriteString(selKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end)
    btnIssue:SetPos(246, 316) btnIssue:SetSize(220, 34)

    tabs:AddSheet("Выдача лицензий", issuePnl, "icon16/money.png")

    -- ════════════ ВКЛАДКА 2: ОБЗОР / КАЗНА / РЕЕСТР ════════════
    local ovPnl = vgui.Create("DPanel", tabs)
    ovPnl:DockPadding(12, 12, 12, 12)
    ovPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local stats = vgui.Create("DPanel", ovPnl)
    stats:Dock(TOP) stats:SetTall(64)
    stats.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(24, 40, 44))
        draw.SimpleText("Городская казна: " .. money(ov.budget), "DermaDefaultBold", 14, 12, CC.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.format("Бизнес-лицензий: %d   ·   Услуг в каталоге: %d   ·   Счетов: %d (неоплачено: %d)",
            tonumber(ov.businessCount) or 0, tonumber(ov.servicesCount) or 0, tonumber(ov.invoicesCount) or 0, tonumber(ov.unpaidCount) or 0),
            "DermaDefault", 14, 36, CC.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local list = vgui.Create("DListView", ovPnl)
    list:Dock(FILL) list:DockMargin(0, 8, 0, 0)
    list:AddColumn("Бизнес"):SetFixedWidth(220)
    list:AddColumn("Владелец"):SetFixedWidth(160)
    list:AddColumn("Вид"):SetFixedWidth(160)
    list:AddColumn("Номер"):SetFixedWidth(90)
    list:AddColumn("Статус"):SetFixedWidth(110)

    for _, rec in ipairs(ov.business or {}) do
        local line = list:AddLine(rec.name, rec.owner, rec.type, rec.number, rec.status)
        line._key = rec.key
    end

    local btnRevoke = mkBtn(ovPnl, "✕ Отозвать выбранную лицензию", CC.danger, function()
        local l = list:GetSelectedLine()
        if not l then notification.AddLegacy("Выберите лицензию в реестре!", NOTIFY_ERROR, 3) return end
        local row = list:GetLine(l)
        if row and row._key then
            net.Start("GRM_Doc_ComputerRevoke")
                net.WriteString("businessLicense")
                net.WriteString(row._key)
            net.SendToServer()
            row:SetColumnText(5, "Отозвана")
        end
    end)
    btnRevoke:Dock(BOTTOM) btnRevoke:SetTall(32) btnRevoke:DockMargin(0, 8, 0, 0)

    tabs:AddSheet("Казна и реестр", ovPnl, "icon16/chart_organisation.png")
end)
