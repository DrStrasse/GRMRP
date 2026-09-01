--[[--------------------------------------------------------------------
    grm_comp_traffic — cl_init.lua (Интерфейс Автоинспекции)
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg      = Color(20, 24, 34, 250),
    panel   = Color(26, 32, 46, 245),
    header  = Color(32, 44, 64, 255),
    accent  = Color(80, 180, 255),
    success = Color(60, 190, 100),
    danger  = Color(220, 70, 70),
    text    = Color(230, 240, 250),
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
        draw.RoundedBox(6, -150, -50, 300, 100, Color(14, 18, 26, 240))
        draw.SimpleText("АВТОИНСПЕКЦИЯ", "DermaDefaultBold", 0, -25, Color(80, 180, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Автошкола / ВАИ / Дорожная Инспекция", "DermaDefault", 0, -5, Color(220, 235, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] для входа в систему", "DermaDefault", 0, 20, Color(150, 175, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

net.Receive("GRM_CompTraffic_Open", function()
    local ent          = net.ReadEntity()
    local onlineList   = net.ReadTable() or {}
    local tpls         = net.ReadTable() or {}
    local registry     = net.ReadTable() or {}
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
        draw.SimpleText("ЭКЗАМЕНАЦИОННЫЙ ТЕРМИНАЛ • АВТОШКОЛА / ВАИ / ДОРОЖНАЯ ИНСПЕКЦИЯ ПП", "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 1: ДОРОЖНАЯ ИНСПЕКЦИЯ ПП (ГРАЖДАНСКИЕ ПРАВА / АВТОШКОЛА)
    -- ══════════════════════════════════════════════════════════════
    local civPnl = vgui.Create("DPanel", tabs)
    civPnl:DockPadding(14, 14, 14, 14)
    civPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblCTarget = vgui.Create("DLabel", civPnl)
    lblCTarget:SetPos(16, 12) lblCTarget:SetText("Выдача водительского удостоверения (Дорожная Инспекция ПП / Автошкола):") lblCTarget:SetFont("DermaDefaultBold") lblCTarget:SetTextColor(Color(80, 190, 240)) lblCTarget:SizeToContents()

    local comboCTarget = vgui.Create("DComboBox", civPnl)
    comboCTarget:SetPos(16, 32) comboCTarget:SetSize(420, 28)
    comboCTarget:AddChoice("— Выберите гражданина онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboCTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.key or ""), pData)
    end

    local entCName = vgui.Create("DTextEntry", civPnl) entCName:SetPos(16, 90) entCName:SetSize(300, 26)
    local entCBirth = vgui.Create("DTextEntry", civPnl) entCBirth:SetPos(330, 90) entCBirth:SetSize(140, 26) entCBirth:SetText("12.04.1988")
    local entCNum = vgui.Create("DTextEntry", civPnl) entCNum:SetPos(485, 90) entCNum:SetSize(180, 26) entCNum:SetText("ВУ-000000")
    local entCIssuer = vgui.Create("DTextEntry", civPnl) entCIssuer:SetPos(16, 145) entCIssuer:SetSize(450, 26) entCIssuer:SetText("Дорожная Инспекция Полиции Порядка (OrdnungPolizei)")

    local chkCats = {}
    local yCat = 205
    local xCat = 16
    for i, cat in ipairs(GRM.Documents and GRM.Documents.DriveCategories or {}) do
        local chk = vgui.Create("DCheckBoxLabel", civPnl)
        chk:SetPos(xCat, yCat)
        chk:SetText(cat.icon .. " " .. cat.name .. " (" .. cat.desc .. ")")
        chk:SetTextColor(CC.text)
        chk:SetValue(cat.id == "B")
        chk:SizeToContents()
        chkCats[cat.id] = chk

        if i % 2 == 1 then xCat = 440 else xCat = 16 yCat = yCat + 24 end
    end

    local btnP1 = vgui.Create("DButton", civPnl)
    btnP1:SetPos(460, 32) btnP1:SetSize(110, 28) btnP1:SetText("Кат. B (Легк.)")
    btnP1.DoClick = function() for id, cb in pairs(chkCats) do cb:SetValue(id == "B") end end

    local btnP2 = vgui.Create("DButton", civPnl)
    btnP2:SetPos(578, 32) btnP2:SetSize(120, 28) btnP2:SetText("Кат. B + C (Груз.)")
    btnP2.DoClick = function() for id, cb in pairs(chkCats) do cb:SetValue(id == "B" or id == "C") end end

    local btnP3 = vgui.Create("DButton", civPnl)
    btnP3:SetPos(706, 32) btnP3:SetSize(150, 28) btnP3:SetText("Все категории (A-E+Спец)")
    btnP3.DoClick = function() for _, cb in pairs(chkCats) do cb:SetValue(true) end end

    local entCRestr = vgui.Create("DTextEntry", civPnl) entCRestr:SetPos(16, yCat + 30) entCRestr:SetSize(520, 26) entCRestr:SetText("Стаж вождения подтверждён")

    local selCKey = ""
    local selCSid64 = "0"
    comboCTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selCKey = pData.key or ""
            selCSid64 = pData.steamID64 or "0"
            entCName:SetText(pData.rpName or "")
            entCNum:SetText("ВУ-" .. selCSid64:sub(-5))
            if registry.licenses and registry.licenses[selCKey] then
                local ex = registry.licenses[selCKey]
                entCName:SetText(ex.fullName or pData.rpName or "")
                entCBirth:SetText(ex.birthDate or "12.04.1988")
                entCNum:SetText(ex.number or ("ВУ-" .. selCSid64:sub(-5)))
                entCRestr:SetText(ex.restrictions or "Стаж вождения подтверждён")
                entCIssuer:SetText(ex.issuedBy or "Дорожная Инспекция Полиции Порядка")
                if istable(ex.categories) then
                    for cId, cb in pairs(chkCats) do cb:SetValue(ex.categories[cId] == true) end
                end
            end
        end
    end

    local btnExamCiv = vgui.Create("DButton", civPnl)
    btnExamCiv:SetPos(16, yCat + 35) btnExamCiv:SetSize(210, 30)
    btnExamCiv:SetText("📝 Экзамен (теория ПДД)")
    btnExamCiv:SetFont("DermaDefaultBold") btnExamCiv:SetTextColor(color_white)
    btnExamCiv.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(150, 110, 60) or Color(120, 88, 48)) end
    btnExamCiv.DoClick = function() if GRM.Documents and GRM.Documents.StartExam then GRM.Documents.StartExam("license", selCKey) end end

    local btnIssueCiv = vgui.Create("DButton", civPnl)
    btnIssueCiv:SetPos(16, yCat + 75) btnIssueCiv:SetSize(360, 36)
    btnIssueCiv:SetText("✔ Выдать водительское удостоверение (Дорожная Инспекция)")
    btnIssueCiv:SetFont("DermaDefaultBold")
    btnIssueCiv:SetTextColor(color_white)
    btnIssueCiv.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(35, 150, 180) or Color(25, 120, 150)) end
    btnIssueCiv.DoClick = function()
        if selCKey == "" then notification.AddLegacy("Выберите гражданина!", NOTIFY_ERROR, 3) return end
        local curCats, catStrList = {}, {}
        for cId, cb in pairs(chkCats) do
            curCats[cId] = cb:GetChecked()
            if cb:GetChecked() then catStrList[#catStrList + 1] = cId end
        end
        local pack = {
            fullName      = entCName:GetText(),
            birthDate     = entCBirth:GetText(),
            number        = entCNum:GetText(),
            categories    = curCats,
            categoriesStr = table.concat(catStrList, " "),
            restrictions  = entCRestr:GetText(),
            issuedBy      = entCIssuer:GetText(),
            issueDate     = os.date("%d.%m.%Y"),
            validUntil    = "10 лет",
            status        = "Действительно",
            steamID64     = selCSid64,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("license")
            net.WriteString(selCKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Дорожная Инспекция ПП", civPnl, "icon16/car.png")

    -- ══════════════════════════════════════════════════════════════
    -- ВКЛАДКА 2: ВОЕННАЯ АВТОМОБИЛЬНАЯ ИНСПЕКЦИЯ (ВАИ)
    -- ══════════════════════════════════════════════════════════════
    local milPnl = vgui.Create("DPanel", tabs)
    milPnl:DockPadding(14, 14, 14, 14)
    milPnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end

    local lblMTarget = vgui.Create("DLabel", milPnl)
    lblMTarget:SetPos(16, 12) lblMTarget:SetText("Удостоверение военного водителя (ВАИ Полевой Жандармерии):") lblMTarget:SetFont("DermaDefaultBold") lblMTarget:SetTextColor(Color(120, 220, 140)) lblMTarget:SizeToContents()

    local comboMTarget = vgui.Create("DComboBox", milPnl)
    comboMTarget:SetPos(16, 32) comboMTarget:SetSize(420, 28)
    comboMTarget:AddChoice("— Выберите военнослужащего онлайн —", "")
    for _, pData in ipairs(onlineList) do
        comboMTarget:AddChoice(string.format("%s  [%s]  (%s)", pData.rpName or "?", pData.nick or "?", pData.faction or "ВС"), pData)
    end

    local entMName = vgui.Create("DTextEntry", milPnl) entMName:SetPos(16, 85) entMName:SetSize(250, 26)
    local comboMRank = vgui.Create("DComboBox", milPnl) comboMRank:SetPos(275, 85) comboMRank:SetSize(160, 26)
    for _, r in ipairs(GRM.Documents and GRM.Documents.MilitaryRanks or {}) do comboMRank:AddChoice(r) end
    comboMRank:SetValue("Рядовой")

    local entMUnit = vgui.Create("DTextEntry", milPnl) entMUnit:SetPos(445, 85) entMUnit:SetSize(180, 26) entMUnit:SetText("В/Ч 00000 (Автобат)")
    local entMNum  = vgui.Create("DTextEntry", milPnl) entMNum:SetPos(635, 85) entMNum:SetSize(150, 26) entMNum:SetText("ВАИ-000000")

    local comboMVUS = vgui.Create("DComboBox", milPnl) comboMVUS:SetPos(16, 135) comboMVUS:SetSize(340, 26)
    for _, v in ipairs(GRM.Documents and GRM.Documents.MilitaryDriverVUS or {}) do comboMVUS:AddChoice(v) end
    comboMVUS:SetValue("ВУС-837 (Водитель транспортных средств категории C)")

    local entMVUSCustom = vgui.Create("DTextEntry", milPnl) entMVUSCustom:SetPos(365, 135) entMVUSCustom:SetSize(180, 26)
    comboMVUS.OnSelect = function(_, _, v) if v and v ~= "" then entMVUSCustom:SetText(v) end end

    local entMIssuer = vgui.Create("DTextEntry", milPnl) entMIssuer:SetPos(555, 135) entMIssuer:SetSize(320, 26) entMIssuer:SetText("101-я Военная автомобильная инспекция (ВАИ)")

    local chkMilCats = {}
    local yMCat = 185
    local xMCat = 16
    for i, cat in ipairs(GRM.Documents and GRM.Documents.MilDriveCategories or {}) do
        local chk = vgui.Create("DCheckBoxLabel", milPnl)
        chk:SetPos(xMCat, yMCat)
        chk:SetText(cat.icon .. " " .. cat.name .. " (" .. cat.desc .. ")")
        chk:SetTextColor(CC.text)
        chk:SetValue(cat.id == "B-В" or cat.id == "C-В")
        chk:SizeToContents()
        chkMilCats[cat.id] = chk

        if i % 2 == 1 then xMCat = 440 else xMCat = 16 yMCat = yMCat + 22 end
    end

    local chkEnds = {}
    local yEnd = yMCat + 26
    local xEnd = 16
    for i, endDef in ipairs(GRM.Documents and GRM.Documents.MilEndorsements or {}) do
        local chk = vgui.Create("DCheckBoxLabel", milPnl)
        chk:SetPos(xEnd, yEnd)
        chk:SetText(endDef.icon .. " " .. endDef.title .. " (" .. endDef.desc .. ")")
        chk:SetTextColor(CC.text)
        chk:SetValue(endDef.id == "convoy" or endDef.id == "march")
        chk:SizeToContents()
        chkEnds[endDef.id] = chk

        if i % 2 == 1 then xEnd = 440 else xEnd = 16 yEnd = yEnd + 22 end
    end

    local entMRestr = vgui.Create("DTextEntry", milPnl) entMRestr:SetPos(16, yEnd + 26) entMRestr:SetSize(520, 26) entMRestr:SetText("Норматив вождения сдан. Стажировка пройдена.")

    local selMKey = ""
    local selMSid64 = "0"
    comboMTarget.OnSelect = function(_, _, _, pData)
        if istable(pData) then
            selMKey = pData.key or ""
            selMSid64 = pData.steamID64 or "0"
            entMName:SetText(pData.rpName or "")
            entMNum:SetText("ВАИ-" .. selMSid64:sub(-5))
            entMUnit:SetText(pData.faction or "В/Ч 00000 (Автобат)")

            if registry.milLicenses and registry.milLicenses[selMKey] then
                local ex = registry.milLicenses[selMKey]
                entMName:SetText(ex.fullName or pData.rpName or "")
                comboMRank:SetValue(ex.rank or "Рядовой")
                entMUnit:SetText(ex.formation or "В/Ч 00000 (Автобат)")
                entMNum:SetText(ex.number or ("ВАИ-" .. selMSid64:sub(-5)))
                entMVUSCustom:SetText(ex.vus or "ВУС-837 (Водитель спецтранспорта)")
                entMRestr:SetText(ex.restrictions or "Норматив вождения сдан. Стажировка пройдена.")
                if istable(ex.categories) then
                    for cId, cb in pairs(chkMilCats) do cb:SetValue(ex.categories[cId] == true) end
                end
                if istable(ex.endorsements) then
                    for eId, cb in pairs(chkEnds) do cb:SetValue(ex.endorsements[eId] == true) end
                end
            end
        end
    end

    local btnIssueMil = vgui.Create("DButton", milPnl)
    btnIssueMil:SetPos(16, yEnd + 60) btnIssueMil:SetSize(380, 36)
    btnIssueMil:SetText("✔ Выдать удостоверение военного водителя (ВАИ)")
    btnIssueMil:SetFont("DermaDefaultBold")
    btnIssueMil:SetTextColor(color_white)
    btnIssueMil.Paint = function(s, w, h) draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(45, 145, 65) or Color(35, 115, 50)) end
    btnIssueMil.DoClick = function()
        if selMKey == "" then notification.AddLegacy("Выберите военнослужащего!", NOTIFY_ERROR, 3) return end
        local curCats, catStrList = {}, {}
        for cId, cb in pairs(chkMilCats) do
            curCats[cId] = cb:GetChecked()
            if cb:GetChecked() then catStrList[#catStrList + 1] = cId end
        end
        local curEnds = {}
        for eId, cb in pairs(chkEnds) do curEnds[eId] = cb:GetChecked() end
        local chosenVus = string.Trim(entMVUSCustom:GetText())
        if chosenVus == "" then chosenVus = comboMVUS:GetValue() end
        local pack = {
            fullName      = entMName:GetText(),
            rank          = comboMRank:GetValue(),
            formation     = entMUnit:GetText(),
            vus           = chosenVus,
            number        = entMNum:GetText(),
            categories    = curCats,
            categoriesStr = table.concat(catStrList, " "),
            endorsements  = curEnds,
            specialNotes  = entMRestr:GetText(),
            restrictions  = entMRestr:GetText(),
            issuedBy      = entMIssuer:GetText(),
            issueDate     = os.date("%d.%m.%Y"),
            validUntil    = "На срок военной службы",
            status        = "Действительно (на службе)",
            steamID64     = selMSid64,
        }
        net.Start("GRM_Doc_ComputerIssue")
            net.WriteString("milLicense")
            net.WriteString(selMKey)
            net.WriteTable(pack)
        net.SendToServer()
        frame:Close()
    end

    tabs:AddSheet("Военная Автоинспекция (ВАИ)", milPnl, "icon16/car.png")
end)
