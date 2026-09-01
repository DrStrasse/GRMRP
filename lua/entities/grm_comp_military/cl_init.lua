--[[--------------------------------------------------------------------
    grm_comp_military — cl_init.lua (Интерфейс Военкомата)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(20, 26, 20, 250),
    panel   = Color(28, 36, 28, 245),
    header  = Color(36, 48, 36, 255),
    accent  = Color(110, 210, 120),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(230, 245, 230),
    dim     = Color(150, 175, 155),
    gold    = Color(245, 205, 80),
}

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -150, -50, 300, 100, Color(14, 20, 14, 240))
        draw.SimpleText("ВОЕННЫЙ КОМИССАРИАТ", "DermaDefaultBold", 0, -25, Color(110, 210, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Учёт, призыв и военные билеты", "DermaDefault", 0, -5, Color(220, 240, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] для входа в систему", "DermaDefault", 0, 20, Color(150, 185, 155), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

net.Receive("GRM_CompMilitary_Open", function()
    local ent          = net.ReadEntity()
    local onlineList   = net.ReadTable() or {}
    local tpls         = net.ReadTable() or {}
    local registry     = net.ReadTable() or {}
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
        draw.SimpleText("ВОЕННЫЙ КОМИССАРИАТ • УЧЁТ ПРИЗЫВНИКОВ И ВЫДАЧА ВОЕННЫХ БИЛЕТОВ", "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetPos(frame:GetWide() - 36, 8)
    btnClose:SetText("✕")
    btnClose:SetTextColor(CC.dim)
    btnClose.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(45, 55, 45))
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
    -- ВКЛАДКА 1: ОФОРМЛЕНИЕ И ВЫДАЧА ВОЕННЫХ БИЛЕТОВ
    -- ══════════════════════════════════════════════════════════════
    local milPnl = vgui.Create("DPanel", tabs)
    milPnl:DockPadding(16, 16, 16, 16)
    milPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblMilTarget = vgui.Create("DLabel", milPnl)
    lblMilTarget:SetPos(16, 16) lblMilTarget:SetText("Выберите военнообязанного гражданина:") lblMilTarget:SetFont("DermaDefaultBold") lblMilTarget:SetTextColor(Color(120, 220, 140)) lblMilTarget:SizeToContents()

    local comboMilTarget = vgui.Create("DComboBox", milPnl)
    comboMilTarget:SetPos(16, 36) comboMilTarget:SetSize(420, 28)
    comboMilTarget:AddChoice("— Выберите гражданина онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboMilTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.key or ""), pData)
    end

    --[[ Подписи к полям (заказ владельца 19.08): раньше вкладка выдачи была
         набором безымянных строк — не понять, куда вписывать звание. ]]
    local function fieldLabel(x, y, text)
        local lbl = vgui.Create("DLabel", milPnl)
        lbl:SetPos(x, y)
        lbl:SetText(text)
        lbl:SetTextColor(Color(215, 225, 235))
        lbl:SizeToContents()
        return lbl
    end

    fieldLabel(16, 75, "ФИО военнослужащего:")
    local entMilName = vgui.Create("DTextEntry", milPnl) entMilName:SetPos(16, 95) entMilName:SetSize(280, 26)

    fieldLabel(310, 75, "Воинское звание (выбор / ручной ввод):")
    local comboMilRank = vgui.Create("DComboBox", milPnl) comboMilRank:SetPos(310, 95) comboMilRank:SetSize(220, 26)
    for _, r in ipairs(GRM.Documents and GRM.Documents.MilitaryRanks or {}) do comboMilRank:AddChoice(r) end
    comboMilRank:SetValue("Рядовой")

    -- Звание можно вписать своё — как ВУС ниже: список не покрывает все
    -- звания сборки (гвардейские, ведомственные, специальные).
    local entMilRankCustom = vgui.Create("DTextEntry", milPnl)
    entMilRankCustom:SetPos(540, 95) entMilRankCustom:SetSize(250, 26)
    entMilRankCustom:SetPlaceholderText("или своё звание вручную")
    comboMilRank.OnSelect = function(_, _, value)
        if value and value ~= "" then entMilRankCustom:SetText(value) end
    end

    fieldLabel(16, 135, "Военно-учётная специальность (ВУС):")
    local comboMilVUS = vgui.Create("DComboBox", milPnl) comboMilVUS:SetPos(16, 155) comboMilVUS:SetSize(340, 26)
    for _, v in ipairs(GRM.Documents and GRM.Documents.MilitaryVUS or {}) do comboMilVUS:AddChoice(v) end
    comboMilVUS:SetValue("ВУС-100 (Стрелковая подготовка)")

    local entMilVUSCustom = vgui.Create("DTextEntry", milPnl) entMilVUSCustom:SetPos(365, 155) entMilVUSCustom:SetSize(220, 26) entMilVUSCustom:SetPlaceholderText("или свой ВУС")
    comboMilVUS.OnSelect = function(_, _, v) if v and v ~= "" then entMilVUSCustom:SetText(v) end end

    fieldLabel(600, 135, "Воинское формирование:")
    local entMilForm = vgui.Create("DTextEntry", milPnl) entMilForm:SetPos(600, 155) entMilForm:SetSize(190, 26) entMilForm:SetText("Вооружённые Силы")

    fieldLabel(16, 195, "Подразделение:")
    local entMilDept = vgui.Create("DTextEntry", milPnl) entMilDept:SetPos(16, 215) entMilDept:SetSize(240, 26) entMilDept:SetText("Мотострелковый батальон")

    fieldLabel(270, 195, "Должность:")
    local entMilPos  = vgui.Create("DTextEntry", milPnl) entMilPos:SetPos(270, 215) entMilPos:SetSize(240, 26) entMilPos:SetText("Стрелок")

    fieldLabel(525, 195, "Категория годности:")
    local comboMilFit = vgui.Create("DComboBox", milPnl) comboMilFit:SetPos(525, 215) comboMilFit:SetSize(265, 26)
    comboMilFit:AddChoice("А — Годен к военной службе без ограничений")
    comboMilFit:AddChoice("Б — Годен к военной службе с незначительными ограничениями")
    comboMilFit:AddChoice("В — Ограниченно годен к военной службе (запас)")
    comboMilFit:AddChoice("Г — Временно не годен к военной службе (отсрочка)")
    comboMilFit:AddChoice("Д — Не годен к военной службе (освобождён)")
    comboMilFit:SetValue("А — Годен к военной службе без ограничений")

    fieldLabel(16, 255, "Номер бланка:")
    local entMilNum = vgui.Create("DTextEntry", milPnl) entMilNum:SetPos(16, 275) entMilNum:SetSize(180, 26) entMilNum:SetText("ВБ-014289")

    fieldLabel(210, 255, "Кем выдан:")
    local entMilIssuer = vgui.Create("DTextEntry", milPnl) entMilIssuer:SetPos(210, 275) entMilIssuer:SetSize(380, 26) entMilIssuer:SetText("Военный комиссариат Центрального округа")

    local selectedMilKey = ""
    local selectedMilSid64 = "0"
    comboMilTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selectedMilKey = pData.key or ""
            selectedMilSid64 = pData.steamID64 or "0"
            entMilName:SetText(pData.rpName or "")
            local shortSid = selectedMilSid64:sub(-5)
            entMilNum:SetText("ВБ-" .. shortSid)

            if registry.military and registry.military[selectedMilKey] then
                local ex = registry.military[selectedMilKey]
                entMilName:SetText(ex.fullName or pData.rpName or "")
                comboMilRank:SetValue(ex.rank or "Рядовой")
                entMilRankCustom:SetText(ex.rank or "")
                entMilVUSCustom:SetText(ex.vus or "ВУС-100 (Стрелковая подготовка)")
                entMilForm:SetText(ex.formation or "Вооружённые Силы")
                entMilDept:SetText(ex.department or "Мотострелковый батальон")
                entMilPos:SetText(ex.position or "Стрелок")
                comboMilFit:SetValue(ex.fitness or "А — Годен к военной службе без ограничений")
                entMilNum:SetText(ex.number or ("ВБ-" .. shortSid))
                entMilIssuer:SetText(ex.issuedBy or "Военный комиссариат Центрального округа")
            end
        end
    end

    local btnIssueMil = vgui.Create("DButton", milPnl)
    btnIssueMil:SetPos(16, 325) btnIssueMil:SetSize(320, 36)
    btnIssueMil:SetText("✔ Оформить и выдать военный билет")
    btnIssueMil:SetFont("DermaDefaultBold")
    btnIssueMil:SetTextColor(color_white)
    btnIssueMil.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and CC.success or Color(35, 140, 75)) end
    btnIssueMil.DoClick = function()
        if selectedMilKey == "" then notification.AddLegacy("Выберите военнообязанного!", NOTIFY_ERROR, 3) return end
        local chosenVus = string.Trim(entMilVUSCustom:GetText())
        if chosenVus == "" then chosenVus = comboMilVUS:GetValue() end

        -- Ручное звание имеет приоритет над списком.
        local chosenRank = string.Trim(entMilRankCustom:GetText())
        if chosenRank == "" then chosenRank = comboMilRank:GetValue() end

        local pack = {
            fullName    = entMilName:GetText(),
            rank        = chosenRank,
            vus         = chosenVus,
            formation   = entMilForm:GetText(),
            department  = entMilDept:GetText(),
            position    = entMilPos:GetText(),
            fitness     = comboMilFit:GetValue(),
            number      = entMilNum:GetText(),
            issuedBy    = entMilIssuer:GetText(),
            issueDate   = os.date("%d.%m.%Y"),
            validUntil  = "Бессрочно",
            status      = "Действителен (в запасе)",
            steamID64   = selectedMilSid64,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("military")
            net.WriteString(selectedMilKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Выдача военных билетов", milPnl, "icon16/book_open.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: УЧЁТ ПРИЗЫВНИКОВ И МОБРЕЗЕРВА
    -- ══════════════════════════════════════════════════════════════
    local recPnl = vgui.Create("DPanel", tabs)
    recPnl:DockPadding(10, 10, 10, 10)
    recPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local listRec = vgui.Create("DListView", recPnl)
    listRec:Dock(FILL)
    listRec:AddColumn("Призывник / Военнообязанный"):SetFixedWidth(240)
    listRec:AddColumn("Военный билет"):SetFixedWidth(140)
    listRec:AddColumn("Звание / ВУС"):SetFixedWidth(220)
    listRec:AddColumn("Годность (ВВК)"):SetFixedWidth(180)
    listRec:AddColumn("Статус призыва"):SetFixedWidth(140)

    for _, pData in ipairs(onlineList) do
        local mil = registry.military and registry.military[pData.key]
        local med = medCards[pData.key] or medCards[pData.steamID64]
        local fit = (mil and mil.fitness) or (med and med.fitnessCategory) or "Не установлена"
        local milNum = mil and mil.number or "Не выдан"
        local rnk = mil and (mil.rank .. " (" .. (mil.vus or "—") .. ")") or "Призывник"
        local status = mil and mil.status or "Подлежит призыву"
        listRec:AddLine(pData.rpName or pData.nick or "?", milNum, rnk, fit, status)
    end

    tabs:AddSheet("Учёт призывников", recPnl, "icon16/user.png")
end)
