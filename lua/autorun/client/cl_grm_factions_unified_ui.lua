--[[--------------------------------------------------------------------
    GRM Factions Unified UI v3.0.0 (Код 112 / Structure v5.0)
    Единый полнофункциональный центр управления организациями:
      • Широкий адаптивный Singleton XUI (без сломанных emoji);
      • Левая навигация со всеми 12 разделами:
          1. «Обзор» — сводка, параметры, лидер, цвет, тэг, удаление;
          2. «Сотрудники» — интерактивный состав, поиск, приглашение v2,
             смена должности, перевод в отдел/подотдел, увольнение;
          3. «Структура» — должности (ключи/display), дерево отделов и подотделов
             с квотами, тегами и полным управлением;
          4. «Кадровые дела» — личные досье, журнал, взыскания, благодарности,
             испытательный срок, архив уволенных;
          5. «Доступы и связь» — волна департамента, госновости, доска,
             эфир, оповещения, биржа, госуслуги, счета, дипломы;
          6. «Вооружение и форма» — арсенал и гардероб по ролям/отделам;
          7. «Маскировка» — маскировка по отделам, легенды прикрытия;
          8. «Комендантский час» — запуск, отмена, роли с допуском, таймер;
          9. «Казна и финансы» — бюджет, налоги, инкассация;
          10. «Создать организацию» — создание новой фракции v2;
          11. «Спецслужбы» — CCTV, прослушка (RoomTap), розыск и штрафы;
          12. «Служебные системы» — логистика, экономика, аугментации, телефония;
      • Полная поддержка двойных имён (DisplayName + SystemKey).
----------------------------------------------------------------------]]

if not CLIENT then return end

GRM = GRM or {}
GRM.Factions = GRM.Factions or {}
GRM.Factions.UnifiedUI = GRM.Factions.UnifiedUI or {}
local UI = GRM.Factions.UnifiedUI
UI.Version = "3.2.1"

surface.CreateFont("GRMFac_Title",   { font = "Roboto", size = 20, weight = 800, extended = true })
surface.CreateFont("GRMFac_Sub",     { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMFac_Normal",  { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMFac_Small",   { font = "Roboto", size = 11, weight = 400, extended = true })
surface.CreateFont("GRMFac_Btn",     { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRMFac_StatVal", { font = "Roboto", size = 22, weight = 800, extended = true })

local C = {
    bg         = Color(16, 20, 28, 252),
    sidebar    = Color(12, 15, 22, 255),
    card       = Color(22, 28, 38, 240),
    cardLight  = Color(28, 36, 48, 240),
    cardHover  = Color(36, 46, 62, 240),
    border     = Color(38, 48, 66, 200),
    borderLight= Color(55, 68, 92, 200),
    accent     = Color(65, 145, 235),
    accentDark = Color(40, 100, 180),
    accentHover= Color(85, 165, 255),
    gold       = Color(245, 195, 65),
    green      = Color(55, 185, 110),
    greenHover = Color(70, 210, 125),
    teal       = Color(75, 195, 170),
    red        = Color(225, 70, 70),
    redHover   = Color(245, 90, 90),
    text       = Color(240, 244, 250),
    dim        = Color(155, 170, 190),
}

local currentFrame = nil

-- Состояние, доступное извне UI.Open (чтобы хук обновления данных мог
-- перерисовать ТЕКУЩУЮ вкладку, не сбрасывая её на «Обзор»).
local currentTab = nil
local currentTargetFac = nil
local currentContent = nil
local currentTabButtons = nil
-- Парковка панелей навесных разделов: задаётся при открытии окна, нужна и
-- автосинку (rebuildCurrentTab), а он живёт вне UI.Open.
local currentParkHooked = nil
-- Селектор организаций в шапке: живёт дольше одного открытия, потому что
-- данные фракций прилетают ПОЗЖЕ окна (полный снимок идёт частями через
-- GRM.Net.Stream). Держим ссылку, чтобы пересобрать список, когда данные
-- наконец пришли.
local currentFacCombo = nil
local currentIsSA = false
local currentFacNames = nil

-- Тёмная тема для полей ввода (DTextEntry) в духе XUI.
--[[ ЗАЩИТА ВВОДА ОТ АВТООБНОВЛЕНИЯ.

     Синк фракций (GRM_FactionUIRefreshed) прилетает каждые несколько секунд и
     раньше БЕЗУСЛОВНО пересобирал текущую вкладку через content:Clear().
     Если в этот момент админ печатал название новой организации — панель
     уничтожалась вместе с DTextEntry, и текст «сам собой исчезал».

     Теперь: пока в открытой вкладке есть поле в фокусе (или ввод был меньше
     трёх секунд назад), обновление откладывается; когда пользователь
     закончил — вкладка перерисовывается уже свежими данными. Плюс значения
     помеченных полей (GRMFormKey) переносятся через пересборку, а позиция
     прокрутки восстанавливается. ]]
local formValues = {}
local lastTypedAt = 0

local function eachChild(panel, fn)
    if not IsValid(panel) then return end
    for _, child in ipairs(panel:GetChildren() or {}) do
        if IsValid(child) then
            fn(child)
            eachChild(child, fn)
        end
    end
end

local function hasActiveInput(panel)
    if RealTime() - lastTypedAt < 3 then return true end
    local found = false
    eachChild(panel, function(child)
        if found then return end
        if child.HasFocus and child:HasFocus() and child.GetText then found = true end
    end)
    return found
end

local function collectFormValues(panel)
    eachChild(panel, function(child)
        if child.GRMFormKey and child.GetText then
            formValues[child.GRMFormKey] = child:GetText()
        end
    end)
end

-- Поле формы, значение которого переживает автообновление вкладки.
local function bindFormField(te, key)
    if not IsValid(te) then return te end
    te.GRMFormKey = key
    if formValues[key] and formValues[key] ~= "" then te:SetText(formValues[key]) end
    te.OnChange = function(s)
        lastTypedAt = RealTime()
        formValues[key] = s:GetText()
    end
    te.OnGetFocus = function() lastTypedAt = RealTime() end
    return te
end

local function skinTextEntry(te)
    if not IsValid(te) then return end
    te:SetFont("GRMFac_Normal")
    te:SetTextColor(C.text)
    te.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(24, 30, 40, 245))
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        s:DrawTextEntryText(C.text, C.accent, C.text)
    end
end

-- Тёмная тема для выпадающих списков (DComboBox).
local function skinCombo(cb)
    if not IsValid(cb) then return end
    cb:SetFont("GRMFac_Normal")
    cb:SetTextColor(C.text)
    cb.Paint = function(s, w, h)
        local isHov = s:IsHovered()
        draw.RoundedBox(4, 0, 0, w, h, isHov and Color(30, 38, 52, 245) or Color(24, 30, 40, 245))
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    -- Тёмное оформление выпадающего меню
    cb.OnMenuOpened = function(s, menu)
        if not IsValid(menu) then return end
        menu.Paint = function(_, mw, mh)
            draw.RoundedBox(6, 0, 0, mw, mh, Color(22, 28, 38, 252))
            surface.SetDrawColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, C.borderLight.a)
            surface.DrawOutlinedRect(0, 0, mw, mh)
        end
        for _, opt in ipairs(menu:GetChildren() or {}) do
            if IsValid(opt) then
                if isfunction(opt.SetTextColor) then opt:SetTextColor(C.text) end
                if isfunction(opt.SetFont) then opt:SetFont("GRMFac_Normal") end
                if isfunction(opt.Paint) and not opt.__grmfaced then
                    opt.__grmfaced = true
                    local old = opt.Paint
                    opt.Paint = function(sel, ow, oh)
                        if sel:IsHovered() then
                            draw.RoundedBox(4, 0, 0, ow, oh, Color(40, 62, 96, 240))
                        end
                        if old then old(sel, ow, oh) end
                    end
                end
            end
        end
    end
end

--[[ ОТВЕТ СЕРВЕРА (фикс 21.08 по жалобе «приглашение не приходит»).

     Меню отправляло действие и само рисовало «Готово», а канал
     `Factions_ActionResult`, в который сервер пишет настоящий результат,
     никто не слушал. Поэтому отказы — «Недостаточно прав», «Недопустимая
     стартовая должность», «Персонаж уже состоит во фракции», «У персонажа
     уже есть активное приглашение» — были не видны: лидер думал, что
     приглашение ушло, а его не было вовсе. ]]
net.Receive("Factions_ActionResult", function()
    local ok = net.ReadBool()
    local msg = net.ReadString()
    if msg == nil or msg == "" then msg = ok and "Готово" or "Не выполнено" end
    notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
    surface.PlaySound(ok and "buttons/button15.wav" or "buttons/button10.wav")
    chat.AddText(ok and Color(120, 220, 140) or Color(225, 90, 80), "[Организации] ", Color(235, 235, 240), msg)
end)

local function sendAction(action, args, cb)
    net.Start("Factions_Action")
        net.WriteString(action)
        net.WriteTable(args or {})
    net.SendToServer()
    if cb then timer.Simple(0.25, cb) end
end

local function sendExtAction(action, args, cb)
    net.Start("FactionsExt_Action")
        net.WriteString(action)
        net.WriteTable(args or {})
    net.SendToServer()
    if cb then timer.Simple(0.25, cb) end
end

local function sendBridgeAction(kind, fname, allow, cb)
    net.Start("GRM_FAcc_Set")
        net.WriteString(kind)
        net.WriteString(fname)
        net.WriteBool(allow == true)
    net.SendToServer()
    if cb then timer.Simple(0.25, cb) end
end

local function mkBtn(parent, text, col, hoverCol, doClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetFont("GRMFac_Btn")
    b:SetCursor("hand")
    b.Paint = function(s, w, h)
        local isHov = s:IsHovered()
        local isDown = s:IsDown()
        local isDis = not s:IsEnabled()
        if isHov and not isDis and s._hov ~= true then
            if surface and surface.PlaySound then surface.PlaySound("garrysmod/ui_hover.wav") end
        end
        s._hov = isHov
        local bgCol = col or C.accent
        if isDis then bgCol = Color(34, 40, 52)
        elseif isDown then bgCol = Color(math.max(bgCol.r - 30, 0), math.max(bgCol.g - 30, 0), math.max(bgCol.b - 30, 0))
        elseif isHov then bgCol = hoverCol or C.accentHover end
        draw.RoundedBox(5, 0, isDown and 1 or 0, w, h - (isDown and 1 or 0), bgCol)
        if isHov and not isDown and not isDis then
            draw.RoundedBox(5, 1, 1, w - 2, 2, Color(255, 255, 255, 38))
        end
        surface.SetDrawColor(255, 255, 255, isDis and 10 or 25)
        surface.DrawOutlinedRect(0, isDown and 1 or 0, w, h - (isDown and 1 or 0))
        draw.SimpleText(text, "GRMFac_Btn", w / 2, h / 2 + (isDown and 1 or 0), isDis and C.dim or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        if doClick then doClick() end
    end
    return b
end

-- Карточка-запуск внешней админ-панели модуля (подход «launch»).
local function launchCard(parent, title, desc, iconPath, cmd, color)
    local card = vgui.Create("DPanel", parent)
    card:Dock(TOP)
    card:SetTall(64)
    card:DockMargin(0, 0, 0, 8)
    local iconMat = nil
    if iconPath then
        local m = Material(iconPath, "smooth")
        if m and not m:IsError() then iconMat = m end
    end
    card.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        local iconX = 16
        if iconMat then
            surface.SetMaterial(iconMat)
            surface.SetDrawColor(color or C.accent)
            surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)
            iconX = 40
        end
        draw.SimpleText(title, "GRMFac_Sub", iconX, 15, C.text, TEXT_ALIGN_LEFT)
        draw.SimpleText(desc, "GRMFac_Small", iconX, 37, C.dim, TEXT_ALIGN_LEFT)
    end
    local btn = mkBtn(card, "Открыть", color or C.accent, C.accentHover, function()
        RunConsoleCommand(cmd)
    end)
    btn:Dock(RIGHT)
    btn:DockMargin(0, 17, 12, 0)
    btn:SetSize(150, 30)
    return card
end

-- Стилизация строки DListView: светлый читаемый текст вместо чёрного
-- стандартного скина, и шрифт размера интерфейса (а не DermaDefault 13px).
local function skinListViewLine(line)
    if not IsValid(line) then return end
    for _, col in pairs(line.Columns or {}) do
        if IsValid(col) then
            col:SetFont("GRMFac_Normal")
            col:SetTextColor(C.text)
        end
    end
    -- Тёмный фон строки вместо яркой подсветки стандартного скина.
    line.Paint = function(s, w, h)
        if s:IsLineSelected() then
            draw.RoundedBox(4, 0, 0, w, h, Color(40, 62, 96, 240))
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 110)
            surface.DrawOutlinedRect(0, 0, w, h)
        elseif s.Hovered then
            draw.RoundedBox(4, 0, 0, w, h, Color(30, 40, 56, 220))
        end
    end
end

local function skinListView(lv)
    if not IsValid(lv) then return end
    lv:SetPaintBackground(false)
    lv:SetDataHeight(26)
    lv:SetHeaderHeight(30)
    lv.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    if lv.Columns then
        for _, col in ipairs(lv.Columns) do
            if col.Header then
                col.Header:SetTall(30)
                col.Header:SetFont("GRMFac_Btn")
                col.Header:SetTextColor(C.gold)
                col.Header.Paint = function(s, w, h)
                    draw.RoundedBox(0, 0, 0, w, h, Color(28, 35, 48))
                    surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 80)
                    surface.DrawLine(0, h - 1, w, h - 1)
                    surface.DrawLine(w - 1, 0, w - 1, h)
                end
            end
        end
    end
    -- Перекрашиваем уже добавленные строки (если skin вызывается позже AddLine)
    for _, line in ipairs(lv:GetLines() or {}) do
        skinListViewLine(line)
    end
end

local function promptInput(title, defaultVal, cb)
    local modal = vgui.Create("DFrame")
    modal:SetTitle("")
    modal:SetSize(380, 160)
    modal:Center()
    modal:MakePopup()
    modal:ShowCloseButton(false)
    modal.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 38, C.sidebar)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(title, "GRMFac_Sub", 16, 19, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local te = vgui.Create("DTextEntry", modal)
    te:SetPos(16, 56)
    te:SetSize(348, 32)
    skinTextEntry(te)
    te:SetText(tostring(defaultVal or ""))
    te:RequestFocus()

    local btnCancel = mkBtn(modal, "Отмена", C.cardLight, C.cardHover, function() modal:Close() end)
    btnCancel:SetPos(16, 106) btnCancel:SetSize(165, 36)

    local btnOk = mkBtn(modal, "Подтвердить", C.accent, C.accentHover, function()
        local val = string.Trim(te:GetText())
        if val ~= "" and cb then cb(val) end
        modal:Close()
    end)
    btnOk:SetPos(199, 106) btnOk:SetSize(165, 36)
    te.OnEnter = function() btnOk:DoClick() end
end

local function getLeaderFactionName(data)
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(lp)) or ""
    local sid = lp:SteamID()
    local sid64 = lp:SteamID64()
    for name, f in pairs(data or {}) do
        if istable(f) then
            local ldr = tostring(f.Leader or "")
            if ldr ~= "" and (ldr == charKey or ldr == sid or ldr == sid64) then return name, f end
            if istable(f.Members) then
                local m = f.Members[charKey] or f.Members[sid] or f.Members[sid64]
                if istable(m) and (m.Role == f.LeaderRoleName or m.Role == "Лидер") then return name, f end
            end
        end
    end
    return nil
end

local function getPlayerFactionName(data)
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(lp)) or ""
    local sid = lp:SteamID()
    local sid64 = lp:SteamID64()
    for name, f in pairs(data or {}) do
        if istable(f) and istable(f.Members) then
            if f.Members[charKey] or f.Members[sid] or f.Members[sid64] then return name, f end
        end
    end
    return nil
end

function UI.Open(requestedFaction, requestedTab)
    if IsValid(currentFrame) then
        currentFrame:Remove()
        currentFrame = nil
    end
    currentFacCombo = nil
    currentFacNames = nil

    local data = FactionsData or {}
    local lp = LocalPlayer()
    local isSA = IsValid(lp) and lp.IsSuperAdmin and lp:IsSuperAdmin()

    local targetFac = requestedFaction or getLeaderFactionName(data) or getPlayerFactionName(data)
    if not targetFac and not isSA then
        if GRM.Notify then
            GRM.Notify(lp, "Вы не состоите ни в одной государственной или частной организации.", 255, 160, 80)
        else
            chat.AddText(Color(255, 160, 80), "[Фракции] Вы не состоите ни в одной организации.")
        end
        return
    end

    if not targetFac and isSA then
        -- Первая по алфавиту, а не случайная из pairs().
        local best = nil
        for name in pairs(data) do
            if not best or string.lower(GRM.Factions.DisplayName(name)) < string.lower(GRM.Factions.DisplayName(best)) then
                best = name
            end
        end
        targetFac = best
    end

    local f = vgui.Create("DFrame")
    -- Фракционные вкладки — информационный F2-контур, бан-сторож их не закрывает.
    f.GRM_BanAllowed = true
    currentFrame = f
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_factions_unified", f) end

    -- Заказ владельца 19.08: окно шире и выше — часть кнопок в разделах
    -- (структура, доступы, вооружение) не влезала на 1560 px.
    f:SetSize(math.Clamp(ScrW() * 0.95, 1280, 1920), math.Clamp(ScrH() * 0.92, 760, 1120))
    f:Center()
    f:SetTitle("")
    f:SetDraggable(true)
    f:SetSizable(true)
    f:ShowCloseButton(false)
    f:MakePopup()

    f.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.sidebar)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)

        local dispName = targetFac and GRM.Factions.DisplayName(targetFac) or "Центр управления организациями"
        draw.SimpleText(dispName, "GRMFac_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        if targetFac and targetFac ~= dispName then
            draw.SimpleText("[" .. targetFac .. "]", "GRMFac_Small", 26 + surface.GetTextSize(dispName) + 12, 23, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    --[[ СЕЛЕКТОР ОРГАНИЗАЦИЙ (шапка, суперадмин).

         Две причины, по которым он «ломался»:
           1) он создавался ОДИН раз и только если FactionsData уже был
              заполнен. Но полный снимок организаций теперь приходит частями
              (GRM.Net.Stream) и запрашивается в конце UI.Open — при первом
              открытии список пуст, селектор не появлялся вовсе и больше
              никогда не создавался;
           2) выбор организации удалял окно ПРЯМО из OnSelect, то есть внутри
              обработчика самого выпадающего списка — Derma после этого
              трогала уже удалённую панель (классический «NULL Panel»).

         Теперь селектор пересобирается при каждом синке данных, а
         переключение уходит в следующий кадр и сохраняет открытый раздел. ]]
    currentIsSA = isSA

    local function switchFaction(val)
        if not val or val == targetFac then return end
        local keepTab = currentTab
        timer.Simple(0, function()
            if IsValid(currentFrame) and currentFrame ~= f then return end
            if IsValid(f) then f:Remove() end
            UI.Open(val, keepTab)
        end)
    end

    local function buildSelector()
        if not currentIsSA then return end
        local src = FactionsData or {}
        local fnames = {}
        for fname in pairs(src) do fnames[#fnames + 1] = fname end
        if #fnames == 0 then return end
        -- Список сортируем по публичному имени — иначе pairs() даёт
        -- недетерминированный (и меняющийся между пересборками) порядок.
        table.sort(fnames, function(a, b)
            return string.lower(GRM.Factions.DisplayName(a)) < string.lower(GRM.Factions.DisplayName(b))
        end)

        local signature = table.concat(fnames, "\30") .. "\31" .. tostring(targetFac)
        if IsValid(currentFacCombo) and currentFacNames == signature then return end
        currentFacNames = signature

        if IsValid(currentFacCombo) then currentFacCombo:Remove() end
        local comboFac = vgui.Create("DComboBox", f)
        currentFacCombo = comboFac
        comboFac:SetSize(260, 28)
        comboFac:SetPos(f:GetWide() - 430, 9)
        skinCombo(comboFac)
        comboFac._grmSilent = true
        local keep = currentTargetFac or targetFac
        for _, fname in ipairs(fnames) do
            local disp = GRM.Factions.DisplayName(fname)
            comboFac:AddChoice(disp .. " [" .. fname .. "]", fname, fname == keep)
        end
        if keep then
            comboFac:SetValue(GRM.Factions.DisplayName(keep) .. " [" .. keep .. "]")
        else
            comboFac:SetValue("— выберите организацию —")
        end
        comboFac.OnSelect = function(_, _, value, val)
            if comboFac._grmSilent then return end
            switchFaction(val or value)
        end
        timer.Simple(0, function() if IsValid(comboFac) then comboFac._grmSilent = false end end)
    end

    UI.RebuildSelector = function() if IsValid(f) then buildSelector() end end
    buildSelector()

    local btnClose = vgui.Create("DButton", f)
    btnClose:SetSize(34, 30)
    btnClose:SetPos(f:GetWide() - 44, 8)
    btnClose:SetText("✕")
    btnClose:SetFont("GRMFac_Btn")
    btnClose:SetTextColor(C.dim)
    btnClose.Paint = function(self, w, h)
        if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end
    end
    btnClose.DoClick = function() f:Remove() end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(0, 46, 0, 0)
    body:SetPaintBackground(false)

    -- Боковое меню: список разделов растёт (навесные вкладки модулей), поэтому
    -- он ПРОКРУЧИВАЕТСЯ и при переполнении автоматически становится в два
    -- столбца — раньше нижние разделы уходили за нижнюю кромку окна.
    local sidebarHost = vgui.Create("DPanel", body)
    sidebarHost:Dock(LEFT)
    sidebarHost:SetWide(228)
    sidebarHost.Paint = function(self, w, h)
        draw.RoundedBoxEx(0, 0, 0, w, h, C.sidebar, false, false, true, false)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 80)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end

    local sidebarScroll = vgui.Create("DScrollPanel", sidebarHost)
    sidebarScroll:Dock(FILL)
    local sbar = sidebarScroll:GetVBar()
    if IsValid(sbar) then
        sbar:SetWide(6)
        sbar.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, Color(18, 22, 32)) end
        sbar.btnUp.Paint, sbar.btnDown.Paint = function() end, function() end
        sbar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, C.borderLight) end
    end

    local sidebar = vgui.Create("DPanel", sidebarScroll)
    sidebar:Dock(TOP)
    sidebar:SetTall(10)
    sidebar:SetPaintBackground(false)

    -- Раскладка кнопок: один столбец, а если не помещается по высоте — два.
    local navRows = {}
    local function relayoutNav()
        if not IsValid(sidebar) then return end
        local visible = {}
        for _, btn in ipairs(navRows) do
            if IsValid(btn) then visible[#visible + 1] = btn end
        end
        local count = #visible
        if count == 0 then sidebar:SetTall(10) return end

        local hostH = math.max(120, sidebarHost:GetTall())
        local rowH, gap = 38, 4
        local perColumn = math.floor((hostH - 8) / (rowH + gap))
        local columns = (perColumn > 0 and count > perColumn) and 2 or 1

        if columns == 1 then
            sidebarHost:SetWide(228)
            local w = sidebar:GetWide() - 12
            for i, btn in ipairs(visible) do
                btn:SetPos(6, (i - 1) * (rowH + gap) + 4)
                btn:SetSize(w, rowH)
            end
            sidebar:SetTall(count * (rowH + gap) + 8)
        else
            sidebarHost:SetWide(360)
            local colW = math.floor((sidebar:GetWide() - 18) / 2)
            local rows = math.ceil(count / 2)
            for i, btn in ipairs(visible) do
                local col = (i <= rows) and 0 or 1
                local row = (i <= rows) and (i - 1) or (i - rows - 1)
                btn:SetPos(6 + col * (colW + 6), row * (rowH + gap) + 4)
                btn:SetSize(colW, rowH)
            end
            sidebar:SetTall(rows * (rowH + gap) + 8)
        end
    end
    sidebar.PerformLayout = function() relayoutNav() end
    sidebarHost.PerformLayout = function() relayoutNav() end

    local content = vgui.Create("DPanel", body)
    content:Dock(FILL)
    content:DockMargin(12, 10, 12, 10)
    content:SetPaintBackground(false)

    currentContent = content
    currentTargetFac = targetFac

    local tabButtons = {}
    currentTabButtons = tabButtons

    -- Форвард-декларация: parkHookedPanels объявлена ниже, но нужна уже в
    -- refreshView. Без неё замыкание читало бы глобал и падало.
    local parkHookedPanels

    -- Поиск скролла внутри вкладки: вкладки строят свой DScrollPanel сами.
    local function findScroll(panel)
        if not IsValid(panel) then return nil end
        for _, child in ipairs(panel:GetChildren() or {}) do
            if IsValid(child) and child.GetClassName and child:GetClassName() == "DScrollPanel" then return child end
            local nested = findScroll(child)
            if nested then return nested end
        end
    end

    -- Пересборка вкладки С СОХРАНЕНИЕМ ПРОКРУТКИ. Раньше любое переключение
    -- галочки доступа звало refreshView, вкладка собиралась заново вместе с
    -- новым DScrollPanel, и список отщёлкивал в самое начало — на длинных
    -- списках доступов настраивать было невозможно.
    local function refreshView()
        if currentTab and tabButtons[currentTab] and tabButtons[currentTab].builder then
            local keep = 0
            local oldScroll = findScroll(content)
            if IsValid(oldScroll) and IsValid(oldScroll.VBar) then keep = oldScroll.VBar:GetScroll() end

            -- Введённый в форму текст переносим через пересборку.
            collectFormValues(content)
            if parkHookedPanels then parkHookedPanels() end
            content:Clear()
            tabButtons[currentTab].builder(content, targetFac, FactionsData or {})

            if keep > 0 then
                timer.Simple(0, function()
                    if not IsValid(content) then return end
                    local newScroll = findScroll(content)
                    if IsValid(newScroll) and IsValid(newScroll.VBar) then newScroll.VBar:SetScroll(keep) end
                end)
            end
        end
    end

    -- ── МОСТ НАВЕСНЫХ ВКЛАДОК ────────────────────────────────────────────
    -- Сторонние модули (арест, экономика, кадры, образование, мост доступов)
    -- добавляют свои разделы хуком GRM_FactionsAdmin_BuildTabs. Раньше хук
    -- звало только СТАРОЕ меню, поэтому в /factions эти разделы пропадали.
    -- Панели модулей живут дольше одной вкладки, поэтому перед content:Clear()
    -- их «паркуем» в невидимый контейнер — иначе Clear() их удалит и данные,
    -- запрошенные по сети при открытии, некуда будет положить.
    local hookedPanels = {}
    local hookHost = vgui.Create("DPanel", f)
    hookHost:SetVisible(false)
    hookHost:SetSize(0, 0)
    hookHost:SetPaintBackground(false)

    parkHookedPanels = function()
        for _, row in ipairs(hookedPanels) do
            if IsValid(row.panel) and row.panel:GetParent() == content then
                row.panel:SetVisible(false)
                row.panel:SetParent(hookHost)
            end
        end
    end

    -- Автосинк живёт в другой функции (rebuildCurrentTab) — ему тоже нужна
    -- парковка, иначе Clear() убивает панели навесных разделов и вкладка
    -- «то появляется, то пустая».
    currentParkHooked = parkHookedPanels

    local function selectTab(tabKey, builderFn)
        currentTab = tabKey
        for k, btn in pairs(tabButtons) do
            btn.isActive = (k == tabKey)
        end
        parkHookedPanels()
        content:Clear()
        if builderFn then builderFn(content, targetFac, FactionsData or {}) end
    end

    -- Видимость раздела решает GRM.MenuAccess: по умолчанию всё
    -- чувствительное — только суперадмину, остальное настраивает он сам
    -- в разделе «Права меню». Суперадмин видит всё всегда.
    local function tabVisible(tabKey)
        if isSA then return true end
        local MA = GRM.MenuAccess
        if not (MA and MA.CanSeeLocal) then
            -- Модуль прав не загружен — безопасный режим: чувствительное скрыто.
            local safe = { overview = true, members = true, structure = true, positions = true,
                personnel = true, finance = true }
            return safe[tabKey] == true
        end
        return MA.CanSeeLocal(tabKey, targetFac) == true
    end

    local function addTabBtn(tabKey, label, iconPath, builderFn)
        if not tabVisible(tabKey) then return end
        local btn = vgui.Create("DButton", sidebar)
        btn:SetTall(38)
        btn:SetText("")
        navRows[#navRows + 1] = btn
        btn.isActive = false
        btn.builder = builderFn

        local iconMat = iconPath and Material(iconPath, "smooth") or nil

        btn.Paint = function(self, w, h)
            local isHov = self:IsHovered()
            local isDown = self:IsDown()
            local isAct = self.isActive
            if isHov and self._hov ~= true then surface.PlaySound("garrysmod/ui_hover.wav") end
            self._hov = isHov
            local oy = isDown and 1 or 0
            if isAct then
                draw.RoundedBox(6, 0, oy, w, h - oy, C.accent)
            elseif isDown then
                draw.RoundedBox(6, 0, oy, w, h - oy, Color(28, 38, 54))
            elseif isHov then
                draw.RoundedBox(6, 0, 0, w, h, C.cardHover)
                draw.RoundedBox(6, 1, 1, w - 2, 2, Color(255, 255, 255, 28))
            end
            if iconMat then
                surface.SetMaterial(iconMat)
                surface.SetDrawColor(isAct and color_white or (isHov and C.text or C.dim))
                surface.DrawTexturedRect(12, h / 2 - 8 + oy, 16, 16)
            end
            local col = isAct and color_white or (isHov and C.text or C.dim)
            draw.SimpleText(label, "GRMFac_Btn", iconMat and 36 or 16, h / 2 + oy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        btn.DoClick = function() selectTab(tabKey, builderFn) end
        tabButtons[tabKey] = btn
        relayoutNav()
    end

    -- ════════════ 1. ОБЗОР ════════════
    local function buildOverviewTab(pnl, facName, facData)
        -- Снимок фракций может прийти раньше выбранного узла после live-sync.
        -- Overview обязан показать пустую карточку, а не падать на nil
        -- конкатенации и не ломать всё меню.
        facName = tostring(facName or "")
        local fac = facData and facData[facName] or {}
        local dispName = GRM.Factions.DisplayName(facName)
        local ldrKey = tostring(fac.Leader or "Не назначен")
        local memCount = fac.Members and table.Count(fac.Members) or 0
        local deptCount = fac.Departments and #fac.Departments or 0
        local subCount = fac.Subdepartments and table.Count(fac.Subdepartments) or 0
        local roleCount = fac.Roles and #fac.Roles or 0
        local budget = fac.Budget or 0

        local topCard = vgui.Create("DPanel", pnl)
        topCard:Dock(TOP)
        topCard:SetTall(105)
        topCard:SetPaintBackground(false)

        local function addStat(idx, title, val, color)
            local card = vgui.Create("DPanel", topCard)
            card:SetPos((idx - 1) * ((pnl:GetWide() - 40) / 4) + (idx > 1 and 8 or 0), 0)
            card:SetSize(((pnl:GetWide() - 40) / 4) - 8, 100)
            card.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
                surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText(title, "GRMFac_Small", 14, 16, C.dim, TEXT_ALIGN_LEFT)
                draw.SimpleText(tostring(val), "GRMFac_StatVal", 14, 44, color or C.text, TEXT_ALIGN_LEFT)
            end
        end

        --[[ Укомплектованность штата (ось v5): сколько мест по должностям
             занято и сколько свободно. Свободные места — это и есть
             вакансии организации, видные без захода в раздел должностей. ]]
        local posTaken, posSlots, posFree, posUnlimited = 0, 0, 0, false
        if GRM.Positions and GRM.Positions.List then
            for _, pos in ipairs(GRM.Positions.List(fac)) do
                local st = GRM.Positions.Staffing(fac, pos.id)
                posTaken = posTaken + st.taken
                if st.unlimited then posUnlimited = true
                else
                    posSlots = posSlots + st.slots
                    posFree = posFree + st.free
                end
            end
        end

        addStat(1, "СОТРУДНИКОВ В ШТАТЕ", memCount, C.accent)
        addStat(2, "ОТДЕЛОВ / ПОДОТДЕЛОВ", tostring(deptCount) .. " / " .. tostring(subCount), C.green)
        if posSlots > 0 or posTaken > 0 then
            addStat(3, posFree > 0 and "ШТАТ · СВОБОДНО МЕСТ" or "ШТАТ УКОМПЛЕКТОВАН",
                tostring(posTaken) .. " / " .. (posUnlimited and "∞" or tostring(posSlots)),
                posFree > 0 and C.green or C.gold)
        else
            addStat(3, "ЗВАНИЙ", roleCount, C.gold)
        end
        -- Валюта сборки — GRM (Groennerland Reich Money), рублей на сервере нет.
        addStat(4, "КАЗНА И БЮДЖЕТ",
            (GRM.Format and GRM.Format(budget)) or (tostring(budget) .. " GRM"), C.gold)

        local infoPanel = vgui.Create("DPanel", pnl)
        infoPanel:Dock(FILL)
        infoPanel:DockMargin(0, 16, 0, 0)
        infoPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText("Информация об организации", "GRMFac_Sub", 18, 18, C.text)
            draw.SimpleText("Публичное название: " .. dispName, "GRMFac_Normal", 18, 50, C.text)
            draw.SimpleText("Системный идентификатор: " .. facName, "GRMFac_Normal", 18, 76, C.dim)
            draw.SimpleText("Руководитель: " .. ldrKey, "GRMFac_Normal", 18, 102, C.dim)
            draw.SimpleText("Тэг волны: " .. (fac.Tag and fac.Tag ~= "" and fac.Tag or "—"), "GRMFac_Normal", 18, 128, C.dim)
        end

        local bBar = vgui.Create("DPanel", infoPanel)
        bBar:Dock(BOTTOM)
        bBar:SetTall(46)
        bBar:DockMargin(16, 0, 16, 16)
        bBar:SetPaintBackground(false)

        mkBtn(bBar, "Изменить название", C.accent, C.accentHover, function()
            promptInput("Новое публичное название", dispName, function(val)
                sendAction("setDisplayName", { facName, val }, refreshView)
            end)
        end):Dock(LEFT); bBar:GetChildren()[1]:SetWide(180)

        mkBtn(bBar, "Тэг волны", C.cardLight, C.cardHover, function()
            promptInput("Тэг волны фракции", fac.Tag or "", function(val)
                sendAction("setTag", { facName, val }, refreshView)
            end)
        end):Dock(LEFT); bBar:GetChildren()[2]:DockMargin(10, 0, 0, 0); bBar:GetChildren()[2]:SetWide(130)

        mkBtn(bBar, "Цвет фракции", C.cardLight, C.cardHover, function()
            local cModal = vgui.Create("DFrame")
            cModal:SetTitle(""); cModal:SetSize(320, 280); cModal:Center(); cModal:MakePopup()
            cModal.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.bg)
                draw.RoundedBox(8, 0, 0, w, 36, C.sidebar)
                draw.SimpleText("Выбор цвета", "GRMFac_Sub", 14, 18, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local mixer = vgui.Create("DColorMixer", cModal)
            mixer:SetPos(16, 48); mixer:SetSize(288, 170)
            local curCol = fac.Color or { r=255, g=200, b=50 }
            mixer:SetColor(Color(curCol.r or 255, curCol.g or 200, curCol.b or 50))
            local btnSaveCol = mkBtn(cModal, "Сохранить цвет", C.accent, C.accentHover, function()
                local c = mixer:GetColor()
                sendAction("setColor", { facName, c.r, c.g, c.b }, refreshView)
                cModal:Close()
            end)
            btnSaveCol:SetPos(16, 230); btnSaveCol:SetSize(288, 36)
        end):Dock(LEFT); bBar:GetChildren()[3]:DockMargin(10, 0, 0, 0); bBar:GetChildren()[3]:SetWide(130)

        if isSA then
            mkBtn(bBar, "Удалить фракцию", C.red, C.redHover, function()
                Derma_Query("Удалить фракцию «" .. dispName .. "»?", "Подтверждение удаления", "Удалить", function()
                    sendAction("deleteFaction", { facName }, function()
                        f:Remove()
                        UI.Open()
                    end)
                end, "Отмена")
            end):Dock(RIGHT); bBar:GetChildren()[4]:SetWide(160)
        end
    end

    -- ════════════ 2. СОТРУДНИКИ ════════════
    local function buildMembersTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}

        local topBar = vgui.Create("DPanel", pnl)
        topBar:Dock(TOP)
        topBar:SetTall(34)
        topBar:DockMargin(0, 0, 0, 8)
        topBar:SetPaintBackground(false)

        local searchBox = vgui.Create("DTextEntry", topBar)
        searchBox:Dock(LEFT)
        searchBox:SetWide(300)
        searchBox:SetPlaceholderText("Поиск по имени, номеру (ГР-…) или SteamID...")
        skinTextEntry(searchBox)

        local list = vgui.Create("DListView", pnl)
        list:Dock(FILL)
        list:SetMultiSelect(false)
        list:AddColumn("Имя / Идентификатор"):SetFixedWidth(230)
        -- Номер персонажа в госреестре: по нему кадровик находит человека и
        -- по нему же пробивают через планшет госслужб.
        list:AddColumn("ID"):SetFixedWidth(90)
        --[[ Звание и должность — две независимые оси (ось v5). Раньше колонка
             «Должность» показывала ЗВАНИЕ, и отличить начальника отдела от
             рядового с тем же званием было нельзя. ]]
        list:AddColumn("Звание"):SetFixedWidth(150)
        list:AddColumn("Должность"):SetFixedWidth(190)
        list:AddColumn("Отдел / Подотдел"):SetFixedWidth(240)
        list:AddColumn("Статус службы"):SetFixedWidth(120)
        list:AddColumn("Локация"):SetFixedWidth(130)
        skinListView(list)

        local function populateMembers(filter)
            list:Clear()
            filter = filter and string.Trim(filter):lower() or ""
            for key, rec in pairs(fac.Members or {}) do
                local rp = rec._rpName or tostring(key)
                local cidLower = string.lower(tostring(rec._cid or ""))
                if filter == "" or rp:lower():find(filter, 1, true) or tostring(key):lower():find(filter, 1, true)
                    or (cidLower ~= "" and cidLower:find(filter, 1, true)) then
                    local roleDisplay = GRM.Factions.RoleDisplayName(fac, rec.Role)
                    local deptDisplay = GRM.Factions.DepartmentDisplayName(fac, rec.Department)
                    local subDisplay = GRM.Factions.SubdepartmentDisplayName(fac, rec.Subdepartment)
                    local branchText = deptDisplay
                    if subDisplay ~= "" and subDisplay ~= deptDisplay then
                        branchText = deptDisplay .. " [" .. subDisplay .. "]"
                    end
                    local onDuty = GRM.FactionDuty and GRM.FactionDuty.State and GRM.FactionDuty.State[key]
                    -- Корректный статус службы синхронизируется сервером в _dutyStatus
                    -- (НА СЛУЖБЕ / ВНЕ СЛУЖБЫ / ВЫХОДНОЙ / НЕ В СЕТИ) — см. buildMemberSync
                    -- в sh_factions.lua. На клиенте GRM.FactionDuty.State не существует.
                    local dutyText = rec._dutyStatus or (onDuty and "НА СЛУЖБЕ" or "ВНЕ СЛУЖБЫ")
                    local dutyCol = C.dim
                    if dutyText == "НА СЛУЖБЕ" then dutyCol = C.green
                    elseif dutyText == "ВЫХОДНОЙ" then dutyCol = C.gold
                    elseif dutyText == "ВНЕ СЛУЖБЫ" then dutyCol = C.teal end
                    local loc = rec._location or "—"
                    local cid = tostring(rec._cid or "")
                    -- Должность сотрудника: пусто = человек на одном звании.
                    local posDisplay = "—"
                    local posObj = (GRM.Positions and GRM.Positions.OfMember)
                        and GRM.Positions.OfMember(fac, rec) or nil
                    if posObj then
                        local kindName = (GRM.Positions.KindName or {})[posObj.kind] or ""
                        posDisplay = posObj.name
                        if kindName ~= "" and kindName ~= posObj.name then
                            posDisplay = posObj.name .. " (" .. kindName .. ")"
                        end
                    end
                    local ln = list:AddLine(rp, cid ~= "" and cid or "—", roleDisplay, posDisplay,
                        branchText, dutyText, loc)
                    skinListViewLine(ln)
                    if ln.Columns and IsValid(ln.Columns[6]) then
                        ln.Columns[6]:SetTextColor(dutyCol)
                    end
                    -- Должность подсвечена: начальника видно в списке сразу.
                    if ln.Columns and IsValid(ln.Columns[4]) then
                        ln.Columns[4]:SetTextColor(posObj and C.gold or C.dim)
                    end
                    if ln.Columns and IsValid(ln.Columns[2]) then
                        ln.Columns[2]:SetTextColor(C.gold)
                    end
                    ln.memberKey = key
                end
            end
        end

        searchBox.OnChange = function(s) populateMembers(s:GetText()) end
        populateMembers("")

        local bBar = vgui.Create("DPanel", pnl)
        bBar:Dock(BOTTOM)
        bBar:SetTall(44)
        bBar:DockMargin(0, 8, 0, 0)
        bBar:SetPaintBackground(false)

        mkBtn(bBar, "+ Пригласить игрока", C.green, C.greenHover, function()
            local invModal = vgui.Create("DFrame")
            invModal:SetTitle(""); invModal:SetSize(420, isSA and 350 or 270); invModal:Center(); invModal:MakePopup()
            invModal.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.bg)
                draw.RoundedBox(8, 0, 0, w, 38, C.sidebar)
                draw.SimpleText("Приглашение во фракцию", "GRMFac_Sub", 14, 19, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local comboPly = vgui.Create("DComboBox", invModal)
            comboPly:SetPos(16, 52); comboPly:SetSize(388, 28); skinCombo(comboPly)
            comboPly:AddChoice("— Выберите игрока онлайн —", "")
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and p ~= LocalPlayer() then
                    local n = p:GetNWString("GRM_RPName", "")
                    comboPly:AddChoice(string.format("%s [%s]", n ~= "" and n or p:Nick(), p:Nick()), p:SteamID())
                end
            end

            local comboRole = vgui.Create("DComboBox", invModal)
            comboRole:SetPos(16, 90); comboRole:SetSize(388, 28); skinCombo(comboRole)
            -- Первое звание выбирается сразу: раньше можно было отправить
            -- приглашение с пустым званием и получить молчаливый отказ.
            local firstRole = true
            for _, rKey in ipairs(fac.Roles or {}) do
                if rKey ~= fac.LeaderRoleName then
                    comboRole:AddChoice(GRM.Factions.RoleDisplayName(fac, rKey) .. " [" .. rKey .. "]", rKey, firstRole)
                    firstRole = false
                end
            end

            local comboDept = vgui.Create("DComboBox", invModal)
            comboDept:SetPos(16, 128); comboDept:SetSize(388, 28); skinCombo(comboDept)
            local firstDept = true
            for _, dKey in ipairs(fac.Departments or {}) do
                comboDept:AddChoice(GRM.Factions.DepartmentDisplayName(fac, dKey) .. " [" .. dKey .. "]", dKey, firstDept)
                firstDept = false
            end

            local comboSub = vgui.Create("DComboBox", invModal)
            comboSub:SetPos(16, 166); comboSub:SetSize(388, 28); skinCombo(comboSub)
            local function fillSub(dept)
                comboSub:Clear(); comboSub:AddChoice("Без подотдела", "", true)
                for _, sub in ipairs(GRM.Factions.GetSubdepartments(fac, dept)) do
                    comboSub:AddChoice(sub.name .. " [" .. sub.id .. "]", sub.id)
                end
            end
            local _, initialDept = comboDept:GetSelected(); fillSub(initialDept)
            comboDept.OnSelect = function(_, _, _, dept) fillSub(dept) end

            if isSA then
                local btnSelf = mkBtn(invModal, "★ Назначить себя", C.green, C.greenHover, function()
                    local _, roleKey = comboRole:GetSelected(); local _, deptKey = comboDept:GetSelected(); local _, subKey = comboSub:GetSelected()
                    sendAction("assignSelf", { facName, roleKey or "", deptKey or "", subKey or "", false }, refreshView)
                    invModal:Close()
                end)
                btnSelf:SetPos(16, 204); btnSelf:SetSize(190, 34)
                local btnLeader = mkBtn(invModal, "★ Сделать лидером", C.gold, C.cardHover, function()
                    local _, deptKey = comboDept:GetSelected(); local _, subKey = comboSub:GetSelected()
                    sendAction("assignSelf", { facName, "", deptKey or "", subKey or "", true }, refreshView)
                    invModal:Close()
                end)
                btnLeader:SetPos(214, 204); btnLeader:SetSize(190, 34)
            end

            local btnSend = mkBtn(invModal, "Отправить приглашение", C.accent, C.accentHover, function()
                local _, targetSid = comboPly:GetSelected()
                local _, roleKey = comboRole:GetSelected()
                local _, deptKey = comboDept:GetSelected()
                if not targetSid or targetSid == "" then notification.AddLegacy("Выберите игрока!", NOTIFY_ERROR, 3) return end
                -- Результат придёт с сервера (Factions_ActionResult) — своих
                -- «отправлено» больше не выдумываем.
                sendAction("inviteMember", { isSA and facName or targetSid, isSA and targetSid or roleKey, isSA and roleKey or deptKey, isSA and deptKey or nil }, refreshView)
                invModal:Close()
            end)
            btnSend:SetPos(16, isSA and 260 or 190); btnSend:SetSize(388, 38)
        end):Dock(LEFT); bBar:GetChildren()[1]:SetWide(190)

        --[[ Кнопка называлась «Изменить должность», а меняла ЗВАНИЕ. После
             разделения осей это две разные кнопки. ]]
        mkBtn(bBar, "Изменить звание", C.cardLight, C.cardHover, function()
            local l = list:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите сотрудника в списке!", NOTIFY_ERROR, 3) return end
            local memKey = list:GetLine(l).memberKey
            local rMenu = DermaMenu()
            for _, rKey in ipairs(fac.Roles or {}) do
                local rDisp = GRM.Factions.RoleDisplayName(fac, rKey)
                rMenu:AddOption(rDisp .. " [" .. rKey .. "]", function()
                    sendAction("setRole", { isSA and facName or memKey, isSA and memKey or rKey, isSA and rKey or nil }, refreshView)
                end)
            end
            rMenu:Open()
        end):Dock(LEFT); bBar:GetChildren()[2]:DockMargin(8, 0, 0, 0); bBar:GetChildren()[2]:SetWide(150)

        --- Назначение на должность прямо из личного состава.
        mkBtn(bBar, "Назначить должность", C.accent, C.accentHover, function()
            local l = list:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите сотрудника в списке!", NOTIFY_ERROR, 3) return end
            local memKey = list:GetLine(l).memberKey
            local POS = GRM.Positions
            if not (POS and POS.List) then
                notification.AddLegacy("Модуль должностей не загружен", NOTIFY_ERROR, 4)
                return
            end
            local positions = POS.List(fac)
            local pMenu = DermaMenu()
            pMenu:AddOption("— снять с должности —", function()
                sendAction("positionAssign",
                    isSA and { facName, memKey, "" } or { memKey, "" }, refreshView)
            end)
            if #positions == 0 then
                local none = pMenu:AddOption("Должностей нет — создайте в разделе «Должности»", function() end)
                none:SetTextColor(C.dim)
            end
            local rec = fac.Members and fac.Members[memKey]
            local own = rec and POS.OfMember(fac, rec) or nil
            for _, pos in ipairs(positions) do
                local st = POS.Staffing(fac, pos.id)
                local free = st.unlimited and "без лимита" or (st.free .. " своб.")
                local opt = pMenu:AddOption(
                    pos.name .. "  (" .. POS.NodeDisplayName(fac, pos.node) .. " · " .. free .. ")",
                    function()
                        sendAction("positionAssign",
                            isSA and { facName, memKey, pos.id } or { memKey, pos.id }, refreshView)
                    end)
                -- Занятые места видно до клика, а не отказом сервера после.
                if not st.unlimited and st.free <= 0 and (not own or own.id ~= pos.id) then
                    opt:SetTextColor(C.dim)
                end
            end
            pMenu:Open()
        end):Dock(LEFT); bBar:GetChildren()[3]:DockMargin(8, 0, 0, 0); bBar:GetChildren()[3]:SetWide(170)

        mkBtn(bBar, "Перевести в отдел / подотдел", C.cardLight, C.cardHover, function()
            local l = list:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите сотрудника в списке!", NOTIFY_ERROR, 3) return end
            local memKey = list:GetLine(l).memberKey
            local dMenu = DermaMenu()
            for _, dKey in ipairs(fac.Departments or {}) do
                local dDisp = GRM.Factions.DepartmentDisplayName(fac, dKey)
                local subMenu, subMenuBtn = dMenu:AddSubMenu(dDisp)
                subMenu:AddOption("Прямой член отдела (без подотдела)", function()
                    sendAction("setDepartment", { isSA and facName or memKey, isSA and memKey or dKey, isSA and dKey or nil }, function()
                        sendAction("setSubdepartment", { isSA and facName or memKey, isSA and memKey or "", isSA and "" or nil }, refreshView)
                    end)
                end)
                for _, sub in ipairs(GRM.Factions.GetSubdepartments(fac, dKey)) do
                    subMenu:AddOption(sub.name .. " [" .. sub.id .. "]", function()
                        sendAction("setSubdepartment", { isSA and facName or memKey, isSA and memKey or sub.id, isSA and sub.id or nil }, refreshView)
                    end)
                end
            end
            dMenu:Open()
        end):Dock(LEFT); bBar:GetChildren()[4]:DockMargin(8, 0, 0, 0); bBar:GetChildren()[4]:SetWide(210)

        if isSA then
            mkBtn(bBar, "Назначить лидером", C.gold, C.cardHover, function()
                local l = list:GetSelectedLine()
                if not l then return end
                local memKey = list:GetLine(l).memberKey
                Derma_Query("Сделать " .. memKey .. " лидером организации?", "Смена лидера", "Назначить", function()
                    sendAction("changeLeader", { facName, memKey }, refreshView)
                end, "Отмена")
            end):Dock(LEFT); bBar:GetChildren()[5]:DockMargin(8, 0, 0, 0); bBar:GetChildren()[5]:SetWide(150)
        end

        mkBtn(bBar, "Уволить", C.red, C.redHover, function()
            local l = list:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите сотрудника в списке!", NOTIFY_ERROR, 3) return end
            local memKey = list:GetLine(l).memberKey
            Derma_Query("Уволить сотрудника " .. memKey .. " из организации?", "Подтверждение", "Уволить", function()
                sendAction("removeMember", { isSA and facName or memKey, isSA and memKey or nil }, refreshView)
            end, "Отмена")
        end):Dock(RIGHT); bBar:GetChildren()[isSA and 6 or 5]:SetWide(120)
    end

    -- ════════════ 3. СТРУКТУРА И ШТАТ ════════════
    local function buildStructureTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}

        local split = vgui.Create("DPanel", pnl)
        split:Dock(FILL)
        split:SetPaintBackground(false)

        -- Левая колонка: ДОЛЖНОСТИ (ROLES)
        local left = vgui.Create("DPanel", split)
        left:Dock(LEFT)
        left:SetWide((pnl:GetWide() - 30) * 0.40)
        left.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Звания и ранги (Roles)", "GRMFac_Sub", 14, 16, C.gold)
        end

        local rList = vgui.Create("DListView", left)
        rList:Dock(FILL)
        rList:DockMargin(10, 42, 10, 50)
        rList:AddColumn("Системный ключ"):SetFixedWidth(120)
        rList:AddColumn("Публичное название (RU)")
        skinListView(rList)

        for _, rKey in ipairs(fac.Roles or {}) do
            local rDisp = GRM.Factions.RoleDisplayName(fac, rKey)
            local line = rList:AddLine(rKey, rDisp)
            skinListViewLine(line)
            line.roleKey = rKey
        end

        local rBar = vgui.Create("DPanel", left)
        rBar:Dock(BOTTOM)
        rBar:SetTall(36)
        rBar:DockMargin(10, 0, 10, 8)
        rBar:SetPaintBackground(false)

        mkBtn(rBar, "+ Добавить", C.accent, C.accentHover, function()
            promptInput("Системный ключ нового звания (eng)", "sergeant", function(kVal)
                promptInput("Публичное название звания (RU)", "Сержант", function(dVal)
                    sendAction("addRole", { isSA and facName or kVal, isSA and kVal or nil }, function()
                        sendAction("renameRole", { isSA and facName or kVal, isSA and kVal or dVal, isSA and dVal or nil }, refreshView)
                    end)
                end)
            end)
        end):Dock(LEFT); rBar:GetChildren()[1]:SetWide(105)

        mkBtn(rBar, "Переименовать", C.cardLight, C.cardHover, function()
            local l = rList:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите звание в списке!", NOTIFY_ERROR, 3) return end
            local rKey = rList:GetLine(l).roleKey
            local curDisp = GRM.Factions.RoleDisplayName(fac, rKey)
            promptInput("Новое публичное название звания", curDisp, function(val)
                sendAction("renameRole", { isSA and facName or rKey, isSA and rKey or val, isSA and val or nil }, refreshView)
            end)
        end):Dock(LEFT); rBar:GetChildren()[2]:DockMargin(6, 0, 0, 0); rBar:GetChildren()[2]:SetWide(125)

        --[[ Смена СИСТЕМНОГО ключа звания (заказ владельца 19.08): ключ
             тянется через права, двери и кадровые записи, поэтому меняем его
             отдельной кнопкой и с предупреждением. ]]
        mkBtn(rBar, "Ключ", C.gold, C.cardHover, function()
            local l = rList:GetSelectedLine()
            if not l then notification.AddLegacy("Выберите звание в списке!", NOTIFY_ERROR, 3) return end
            local rKey = rList:GetLine(l).roleKey
            promptInput("Новый системный ключ звания (eng)", rKey, function(val)
                val = string.Trim(tostring(val or ""))
                if val == "" or val == rKey then return end
                Derma_Query("Сменить ключ «" .. rKey .. "» на «" .. val .. "»?\nСотрудники, права, двери и списки будут переведены автоматически.",
                    "Системный ключ звания", "Сменить", function()
                        sendAction("setRoleKey", { isSA and facName or rKey, isSA and rKey or val, isSA and val or nil }, refreshView)
                    end, "Отмена")
            end)
        end):Dock(LEFT); rBar:GetChildren()[3]:DockMargin(6, 0, 0, 0); rBar:GetChildren()[3]:SetWide(70)

        mkBtn(rBar, "▲", C.cardLight, C.cardHover, function()
            local l = rList:GetSelectedLine()
            if not l then return end
            local rKey = rList:GetLine(l).roleKey
            sendAction("moveRole", { isSA and facName or rKey, isSA and rKey or "up", isSA and "up" or nil }, refreshView)
        end):Dock(LEFT); rBar:GetChildren()[4]:DockMargin(6, 0, 0, 0); rBar:GetChildren()[4]:SetWide(30)

        mkBtn(rBar, "▼", C.cardLight, C.cardHover, function()
            local l = rList:GetSelectedLine()
            if not l then return end
            local rKey = rList:GetLine(l).roleKey
            sendAction("moveRole", { isSA and facName or rKey, isSA and rKey or "down", isSA and "down" or nil }, refreshView)
        end):Dock(LEFT); rBar:GetChildren()[5]:DockMargin(4, 0, 0, 0); rBar:GetChildren()[5]:SetWide(30)

        mkBtn(rBar, "Удалить", C.red, C.redHover, function()
            local l = rList:GetSelectedLine()
            if not l then return end
            local rKey = rList:GetLine(l).roleKey
            sendAction("removeRole", { isSA and facName or rKey, isSA and rKey or nil }, refreshView)
        end):Dock(RIGHT); rBar:GetChildren()[6]:SetWide(75)

        -- Правая колонка: ИЕРАРХИЯ ОТДЕЛОВ И ПОДОТДЕЛОВ
        local right = vgui.Create("DPanel", split)
        right:Dock(RIGHT)
        right:SetWide((pnl:GetWide() - 30) * 0.58)
        right.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Иерархия отделов и подотделов", "GRMFac_Sub", 14, 16, C.green)
        end

        local deptScroll = vgui.Create("DScrollPanel", right)
        deptScroll:Dock(FILL)
        deptScroll:DockMargin(10, 42, 10, 50)

        --[[ Карточка отдела 19.08: кнопки больше НЕ расставляются абсолютными
             координатами от ширины панели (при сборке она ещё 0 — кнопки
             улетали за край). Теперь шапка отдела и строка подотдела —
             докнутые ряды, кнопки прижаты вправо и всегда влезают.
             Добавлено редактирование ТЕГА отдела и подотдела: именно эти теги
             печатаются в /fr, /frb, /dep, /d, /depb, /db. ]]
        for _, dKey in ipairs(fac.Departments or {}) do
            local dDisp = GRM.Factions.DepartmentDisplayName(fac, dKey)
            local dTag  = GRM.Factions.DepartmentTag and GRM.Factions.DepartmentTag(fac, dKey) or ""
            local subList = GRM.Factions.GetSubdepartments(fac, dKey)

            local dCard = vgui.Create("DPanel", deptScroll)
            dCard:Dock(TOP)
            dCard:DockMargin(0, 0, 0, 8)
            dCard:SetTall(52 + #subList * 34)
            dCard.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(30, 38, 52, 230))
                surface.SetDrawColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 100)
                surface.DrawOutlinedRect(0, 0, w, h)
            end

            local dHead = vgui.Create("DPanel", dCard)
            dHead:Dock(TOP)
            dHead:SetTall(34)
            dHead:DockMargin(8, 8, 8, 0)
            dHead:SetPaintBackground(false)
            dHead.Paint = function(_, w, h)
                local caption = dDisp .. "  [" .. dKey .. "]"
                draw.SimpleText(caption, "GRMFac_Sub", 6, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local tagText = dTag ~= "" and ("тег: " .. dTag) or "тег не задан"
                draw.SimpleText(tagText, "GRMFac_Small", 10 + surface.GetTextSize(caption) + 10, h / 2,
                    dTag ~= "" and C.gold or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local dBtnDel = mkBtn(dHead, "✕", C.red, C.redHover, function()
                Derma_Query("Удалить отдел «" .. dDisp .. "»?", "Подтверждение", "Удалить", function()
                    sendAction("removeDepartment", { isSA and facName or dKey, isSA and dKey or nil }, refreshView)
                end, "Отмена")
            end)
            dBtnDel:Dock(RIGHT) dBtnDel:SetWide(30) dBtnDel:DockMargin(6, 3, 0, 3)

            local dBtnRename = mkBtn(dHead, "Переименовать", C.cardLight, C.cardHover, function()
                promptInput("Новое название отдела", dDisp, function(val)
                    sendAction("renameDepartment", { isSA and facName or dKey, isSA and dKey or val, isSA and val or nil }, refreshView)
                end)
            end)
            dBtnRename:Dock(RIGHT) dBtnRename:SetWide(130) dBtnRename:DockMargin(6, 3, 0, 3)

            local dBtnTag = mkBtn(dHead, "Тег в рацию", C.gold, C.cardHover, function()
                promptInput("Тег отдела для /fr и /dep (пусто — убрать)", dTag, function(val)
                    sendAction("setDepartmentTag", { isSA and facName or dKey, isSA and dKey or val, isSA and val or nil }, refreshView)
                end)
            end)
            dBtnTag:Dock(RIGHT) dBtnTag:SetWide(110) dBtnTag:DockMargin(6, 3, 0, 3)

            local dBtnAddSub = mkBtn(dHead, "+ Подотдел", C.teal, C.accentHover, function()
                promptInput("Системный ключ подотдела (eng)", "sub_1", function(subKey)
                    promptInput("Публичное название подотдела (RU)", "1-й Взвод", function(subName)
                        promptInput("Тег подотдела в рацию (например ППС-1)", "", function(subTag)
                            sendAction("addSubdepartment", { isSA and facName or dKey, isSA and dKey or subKey, isSA and subKey or subName, isSA and subName or subTag, isSA and subTag or 0, isSA and 0 or nil }, refreshView)
                        end)
                    end)
                end)
            end)
            dBtnAddSub:Dock(RIGHT) dBtnAddSub:SetWide(110) dBtnAddSub:DockMargin(6, 3, 0, 3)

            local subContainer = vgui.Create("DPanel", dCard)
            subContainer:Dock(FILL)
            subContainer:DockMargin(20, 4, 8, 6)
            subContainer:SetPaintBackground(false)

            for _, sub in ipairs(subList) do
                local subRow = vgui.Create("DPanel", subContainer)
                subRow:Dock(TOP)
                subRow:SetTall(30)
                subRow:DockMargin(0, 2, 0, 0)
                subRow.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(22, 28, 38, 220))
                    local tag = (sub.tag ~= "") and ("  •  тег: " .. sub.tag) or "  •  тег не задан"
                    draw.SimpleText(sub.name .. tag, "GRMFac_Normal", 10, h / 2, C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    local quotaText = sub.quota > 0 and ("лимит: " .. tostring(sub.quota)) or "без лимита"
                    draw.SimpleText("[" .. sub.id .. " • " .. quotaText .. "]", "GRMFac_Small", w - 250, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                local sBtnDel = mkBtn(subRow, "✕", C.red, C.redHover, function()
                    Derma_Query("Удалить подотдел «" .. sub.name .. "»?", "Подтверждение", "Удалить", function()
                        sendAction("removeSubdepartment", { isSA and facName or sub.id, isSA and sub.id or nil }, refreshView)
                    end, "Отмена")
                end)
                sBtnDel:Dock(RIGHT) sBtnDel:SetWide(26) sBtnDel:DockMargin(4, 4, 6, 4)

                local sBtnTag = mkBtn(subRow, "Тег", C.gold, C.cardHover, function()
                    promptInput("Тег подотдела для /fr и /dep (пусто — убрать)", sub.tag, function(val)
                        sendAction("setSubdepartmentTag", { isSA and facName or sub.id, isSA and sub.id or val, isSA and val or nil }, refreshView)
                    end)
                end)
                sBtnTag:Dock(RIGHT) sBtnTag:SetWide(52) sBtnTag:DockMargin(4, 4, 0, 4)

                local sBtnRename = mkBtn(subRow, "Имя", C.cardLight, C.cardHover, function()
                    promptInput("Новое название подотдела", sub.name, function(val)
                        sendAction("renameSubdepartment", { isSA and facName or sub.id, isSA and sub.id or val, isSA and val or nil }, refreshView)
                    end)
                end)
                sBtnRename:Dock(RIGHT) sBtnRename:SetWide(52) sBtnRename:DockMargin(4, 4, 0, 4)
            end
        end

        local dBar = vgui.Create("DPanel", right)
        dBar:Dock(BOTTOM)
        dBar:SetTall(36)
        dBar:DockMargin(10, 0, 10, 8)
        dBar:SetPaintBackground(false)

        mkBtn(dBar, "+ Создать новый отдел", C.green, C.greenHover, function()
            promptInput("Системный ключ отдела (eng)", "patrol", function(kVal)
                promptInput("Публичное название отдела (RU)", "Патрульная служба", function(dVal)
                    sendAction("addDepartment", { isSA and facName or kVal, isSA and kVal or nil }, function()
                        sendAction("renameDepartment", { isSA and facName or kVal, isSA and kVal or dVal, isSA and dVal or nil }, refreshView)
                    end)
                end)
            end)
        end):Dock(LEFT); dBar:GetChildren()[1]:SetWide(190)
    end

    -- ════════════ 3б. ДОЛЖНОСТИ (ось v5) ════════════
    --[[ Ранг отвечает на вопрос «какое звание», должность — «какое место в
         штате и что человеку можно». Две независимые оси: лейтенант может
         быть рядовым инспектором, а сержант — начальником отдела.

         Вес власти не задаётся руками — он следует из вида должности
         (начальник / заместитель / старший / сотрудник). Из веса система
         сама выводит вертикаль подчинения. ]]
    local function buildPositionsTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local POS = GRM.Positions

        if not (POS and POS.List) then
            local lbl = vgui.Create("DLabel", pnl)
            lbl:Dock(TOP) lbl:SetTall(24) lbl:SetFont("GRMFac_Normal") lbl:SetTextColor(C.dim)
            lbl:SetText("Модуль должностей не загружен.")
            return
        end

        --- Узлы структуры: организация, отделы, подотделы.
        local function nodeChoices()
            local out = { { key = "root", label = "Организация целиком" } }
            for _, dKey in ipairs(fac.Departments or {}) do
                out[#out + 1] = { key = "dept:" .. dKey,
                    label = "Отдел: " .. GRM.Factions.DepartmentDisplayName(fac, dKey) }
            end
            for _, sub in ipairs(GRM.Factions.GetSubdepartments(fac)) do
                out[#out + 1] = { key = "sub:" .. sub.id, label = "Подотдел: " .. sub.name }
            end
            return out
        end

        --[[ Окно создания и правки должности. Одно на оба случая: при правке
             ключ показан, но не меняется — иначе назначенные люди потеряли бы
             свою должность. ]]
        local function openEditor(existing)
            local isNew = existing == nil
            local modal = vgui.Create("DFrame")
            modal:SetTitle("") modal:SetSize(460, 420) modal:Center() modal:MakePopup()
            modal:ShowCloseButton(false)
            modal.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.bg)
                draw.RoundedBox(8, 0, 0, w, 38, C.sidebar)
                draw.SimpleText(isNew and "Новая должность" or "Правка должности",
                    "GRMFac_Sub", 16, 19, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local function label(text, y)
                local l = vgui.Create("DLabel", modal)
                l:SetPos(16, y) l:SetSize(428, 18)
                l:SetFont("GRMFac_Small") l:SetTextColor(C.dim) l:SetText(text)
            end

            label("Системный ключ (eng, менять нельзя после создания)", 48)
            local keyEntry = vgui.Create("DTextEntry", modal)
            keyEntry:SetPos(16, 68) keyEntry:SetSize(428, 28) skinTextEntry(keyEntry)
            keyEntry:SetText(existing and existing.id or "")
            if not isNew then keyEntry:SetEditable(false) end

            label("Публичное название", 104)
            local nameEntry = vgui.Create("DTextEntry", modal)
            nameEntry:SetPos(16, 124) nameEntry:SetSize(428, 28) skinTextEntry(nameEntry)
            nameEntry:SetText(existing and existing.name or "")

            label("Подразделение", 160)
            local nodeCombo = vgui.Create("DComboBox", modal)
            nodeCombo:SetPos(16, 180) nodeCombo:SetSize(428, 28) skinCombo(nodeCombo)
            local curNode = existing and existing.node or "root"
            for _, n in ipairs(nodeChoices()) do
                nodeCombo:AddChoice(n.label, n.key, n.key == curNode)
            end

            label("Вид должности — от него зависит старшинство", 216)
            local kindCombo = vgui.Create("DComboBox", modal)
            kindCombo:SetPos(16, 236) kindCombo:SetSize(428, 28) skinCombo(kindCombo)
            local curKind = existing and existing.kind or "staff"
            for _, k in ipairs(POS.Kinds) do
                kindCombo:AddChoice(k.name .. "  (вес " .. k.weight .. ")", k.id, k.id == curKind)
            end

            label("Мест в штате (0 — без лимита)", 272)
            local slotsEntry = vgui.Create("DTextEntry", modal)
            slotsEntry:SetPos(16, 292) slotsEntry:SetSize(206, 28) skinTextEntry(slotsEntry)
            slotsEntry:SetNumeric(true)
            slotsEntry:SetText(tostring(existing and existing.slots or 0))

            label("Тег в эфире", 272)
            local tagEntry = vgui.Create("DTextEntry", modal)
            tagEntry:SetPos(238, 292) tagEntry:SetSize(206, 28) skinTextEntry(tagEntry)
            tagEntry:SetText(existing and existing.tag or "")

            local btnCancel = mkBtn(modal, "Отмена", C.cardLight, C.cardHover, function() modal:Close() end)
            btnCancel:SetPos(16, 348) btnCancel:SetSize(206, 38)

            local btnSave = mkBtn(modal, isNew and "Создать" or "Сохранить", C.green, C.greenHover, function()
                local key = string.Trim(keyEntry:GetText() or "")
                local nm = string.Trim(nameEntry:GetText() or "")
                if key == "" then
                    notification.AddLegacy("Укажите системный ключ", NOTIFY_ERROR, 4)
                    return
                end
                local _, node = nodeCombo:GetSelected()
                local _, kind = kindCombo:GetSelected()
                local data = {
                    name = nm ~= "" and nm or key,
                    node = tostring(node or "root"),
                    kind = tostring(kind or "staff"),
                    slots = math.max(0, math.floor(tonumber(slotsEntry:GetText()) or 0)),
                    tag = string.Trim(tagEntry:GetText() or ""),
                }
                sendAction("positionSave",
                    isSA and { facName, key, data } or { key, data }, refreshView)
                modal:Close()
            end)
            btnSave:SetPos(238, 348) btnSave:SetSize(206, 38)
        end

        -- ── ЛЕВО: список должностей ────────────────────────────────
        local left = vgui.Create("DPanel", pnl)
        left:Dock(LEFT)
        left:SetWide((pnl:GetWide() - 30) * 0.52)
        left.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Штатное расписание", "GRMFac_Sub", 14, 16, C.gold)
        end

        local pScroll = vgui.Create("DScrollPanel", left)
        pScroll:Dock(FILL) pScroll:DockMargin(10, 42, 10, 50)

        local positions = POS.List(fac)
        if #positions == 0 then
            local empty = vgui.Create("DLabel", pScroll)
            empty:Dock(TOP) empty:SetTall(40) empty:SetFont("GRMFac_Normal") empty:SetTextColor(C.dim)
            empty:SetWrap(true) empty:SetAutoStretchVertical(true)
            empty:SetText("Должностей нет. Организация работает на одних званиях — как раньше.\n"
                .. "Создайте должности, чтобы отделить начальника от рядового с тем же званием.")
        end

        local lastNode
        for _, pos in ipairs(positions) do
            -- Заголовок подразделения: должности сгруппированы по узлам.
            if pos.node ~= lastNode then
                lastNode = pos.node
                local hdr = vgui.Create("DLabel", pScroll)
                hdr:Dock(TOP) hdr:SetTall(24) hdr:DockMargin(0, 6, 0, 2)
                hdr:SetFont("GRMFac_Small") hdr:SetTextColor(C.accent)
                hdr:SetText(string.upper(POS.NodeDisplayName(fac, pos.node)))
            end

            local st = POS.Staffing(fac, pos.id)
            local row = vgui.Create("DPanel", pScroll)
            row:Dock(TOP) row:SetTall(46) row:DockMargin(0, 0, 0, 4)
            row.Paint = function(_, w, h)
                draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
                -- Полоса слева тем ярче, чем выше должность.
                local weight = POS.Weight(pos)
                local col = weight >= 80 and C.gold or (weight >= 60 and C.accent or C.dim)
                draw.RoundedBox(2, 0, 0, 4, h, col)
                draw.SimpleText(pos.name, "GRMFac_Normal", 14, 13, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local staffText = st.unlimited
                    and ("занято " .. st.taken .. " · без лимита")
                    or ("занято " .. st.taken .. " из " .. st.slots)
                local kindName = POS.KindName[pos.kind] or pos.kind
                draw.SimpleText(kindName .. " · " .. staffText .. " · [" .. pos.id .. "]"
                    .. (pos.tag ~= "" and (" · тег " .. pos.tag) or ""),
                    "GRMFac_Small", 14, 32, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local bDel = mkBtn(row, "Удалить", C.red, C.redHover, function()
                Derma_Query("Удалить должность «" .. pos.name .. "»?\n"
                    .. "Сотрудники останутся в организации, но без должности.",
                    "Должности", "Удалить", function()
                        sendAction("positionDelete", isSA and { facName, pos.id } or { pos.id }, refreshView)
                    end, "Отмена", function() end)
            end)
            bDel:Dock(RIGHT) bDel:SetWide(74) bDel:DockMargin(4, 7, 8, 7)

            local bEdit = mkBtn(row, "Правка", C.cardLight, C.cardHover, function() openEditor(pos) end)
            bEdit:Dock(RIGHT) bEdit:SetWide(70) bEdit:DockMargin(4, 7, 0, 7)
        end

        local pBar = vgui.Create("DPanel", left)
        pBar:Dock(BOTTOM) pBar:SetTall(36) pBar:DockMargin(10, 0, 10, 8)
        pBar:SetPaintBackground(false)
        local bAdd = mkBtn(pBar, "+ Создать должность", C.green, C.greenHover, function() openEditor(nil) end)
        bAdd:Dock(LEFT) bAdd:SetWide(190)

        -- ── ПРАВО: назначение сотрудников ──────────────────────────
        local right = vgui.Create("DPanel", pnl)
        right:Dock(FILL) right:DockMargin(10, 0, 0, 0)
        right.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Назначение сотрудников", "GRMFac_Sub", 14, 16, C.gold)
        end

        local mScroll = vgui.Create("DScrollPanel", right)
        mScroll:Dock(FILL) mScroll:DockMargin(10, 42, 10, 10)

        --- Кто где служит: имя, звание и текущая должность.
        local memberKeys = {}
        for key in pairs(fac.Members or {}) do memberKeys[#memberKeys + 1] = key end
        table.sort(memberKeys)

        if #memberKeys == 0 then
            local empty = vgui.Create("DLabel", mScroll)
            empty:Dock(TOP) empty:SetTall(24) empty:SetFont("GRMFac_Normal") empty:SetTextColor(C.dim)
            empty:SetText("В организации нет сотрудников.")
        end

        for _, key in ipairs(memberKeys) do
            local mem = fac.Members[key]
            if istable(mem) then
                local own = POS.OfMember(fac, mem)
                local row = vgui.Create("DPanel", mScroll)
                row:Dock(TOP) row:SetTall(48) row:DockMargin(0, 0, 0, 4)
                local rpName = tostring(mem._rpName or "")
                if rpName == "" then rpName = key end
                local roleName = GRM.Factions.RoleDisplayName(fac, mem.Role or "")
                row.Paint = function(_, w, h)
                    draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
                    draw.SimpleText(rpName, "GRMFac_Normal", 12, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    -- Звание и должность — рядом, чтобы разница была видна сразу.
                    local posText = own and own.name or "без должности"
                    local posCol = own and C.gold or C.dim
                    draw.SimpleText("звание: " .. roleName, "GRMFac_Small", 12, 33, C.dim,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(posText, "GRMFac_Small", w - 150, 33, posCol,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                local bSet = mkBtn(row, "Назначить", C.accent, C.accentHover, function()
                    local menu = DermaMenu()
                    menu:AddOption("— снять с должности —", function()
                        sendAction("positionAssign",
                            isSA and { facName, key, "" } or { key, "" }, refreshView)
                    end)
                    for _, pos in ipairs(POS.List(fac)) do
                        local st = POS.Staffing(fac, pos.id)
                        local free = st.unlimited and "без лимита" or (st.free .. " своб.")
                        local title = pos.name .. "  (" .. POS.NodeDisplayName(fac, pos.node) .. " · " .. free .. ")"
                        local opt = menu:AddOption(title, function()
                            sendAction("positionAssign",
                                isSA and { facName, key, pos.id } or { key, pos.id }, refreshView)
                        end)
                        -- Занятые места видно до клика, а не после отказа сервера.
                        if not st.unlimited and st.free <= 0 and (not own or own.id ~= pos.id) then
                            opt:SetTextColor(C.dim)
                        end
                    end
                    menu:Open()
                end)
                bSet:Dock(RIGHT) bSet:SetWide(96) bSet:DockMargin(4, 8, 8, 8)
            end
        end
    end

    -- ════════════ 4. КАДРОВЫЕ ДЕЛА ════════════
    local function buildPersonnelTab(pnl, facName, facData)
        if GRM.FactionPersonnel and GRM.FactionPersonnel.OpenTab then
            GRM.FactionPersonnel.OpenTab(pnl, facName)
        else
            local lbl = vgui.Create("DLabel", pnl)
            lbl:Dock(TOP)
            lbl:SetText("Кадровый модуль GRM.FactionPersonnel активен.")
            lbl:SetFont("GRMFac_Normal")
            lbl:SetTextColor(C.dim)
        end
    end

    -- ════════════ 5. ДОСТУПЫ И СВЯЗЬ ════════════
    local function buildAccessTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local scroll = vgui.Create("DScrollPanel", pnl)
        scroll:Dock(FILL)

        -- Полные доступы к экономическим функциям ПО РОЛЯМ (отдельная панель).
        launchCard(scroll, "Доступы по ролям (экономика)",
            "Бюджеты, налоги, штрафы, законы, инкассация — по должностям.",
            "icon16/table_key.png", "grm_faction_perms", C.gold)

        -- Тумблеры доступов НЕ пересобирают вкладку: чекбокс сам меняет свой
        -- текст и цвет, а серверный ответ приходит отдельным синком. Раньше
        -- каждый клик звал refreshView -> content:Clear() -> новый скролл,
        -- из-за чего список прыгал в начало.
        local function addAccessToggle(title, desc, getVal, onToggle)
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP)
            row:SetTall(52)
            row:DockMargin(0, 0, 0, 6)
            row.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(title, "GRMFac_Sub", 14, 14, C.text)
                draw.SimpleText(desc, "GRMFac_Small", 14, 32, C.dim)
            end

            local chk = vgui.Create("DCheckBoxLabel", row)
            chk:SetPos(pnl:GetWide() - 150, 14)
            chk:SetSize(120, 24)
            local cur = getVal()
            chk:SetText(cur and "РАЗРЕШЕНО" or "ЗАПРЕЩЕНО")
            chk:SetFont("GRMFac_Btn")
            chk:SetTextColor(cur and C.green or C.dim)
            chk:SetValue(cur and 1 or 0)
            chk.OnChange = function(_, v)
                onToggle(v == true)
                chk:SetText(v and "РАЗРЕШЕНО" or "ЗАПРЕЩЕНО")
                chk:SetTextColor(v and C.green or C.dim)
            end
        end

        addAccessToggle("Волна департамента (/dep, /depb)", "Право служебной радиосвязи между всеми ведомствами",
            function() return fac.DepAccess == true end,
            function(v) sendAction("setDepAccess", { facName, v }) end)

        addAccessToggle("Государственные новости (/gnews)", "Право трансляции официальных новостей лидером",
            function() return fac.GNewsAccess == true end,
            function(v) sendExtAction("setGNewsAccess", { facName, v }) end)

        addAccessToggle("Доска объявлений (/board)", "Право публикации объявлений о наборе сотрудников",
            function() return (GRM.FAcc and GRM.FAcc.board and GRM.FAcc.board[facName]) == true end,
            function(v) sendBridgeAction("board", facName, v) end)

        addAccessToggle("Радиовещание у микрофонов (/bcast)", "Право проведения городских радиоэфиров",
            function() return (GRM.FAcc and GRM.FAcc.journ and GRM.FAcc.journ[facName]) == true end,
            function(v) sendBridgeAction("journ", facName, v) end)

        addAccessToggle("Оповещения тревоги (/alert, /alertall)", "Право запуска тревожных сирен и оповещений",
            function() return (GRM.FAcc and GRM.FAcc.alert and GRM.FAcc.alert[facName]) == true end,
            function(v) sendBridgeAction("alert", facName, v) end)

        addAccessToggle("Биржа труда (/jobs)", "Публикация оплачиваемых государственных заказов",
            function() return (GRM.FAcc and GRM.FAcc.jobs and GRM.FAcc.jobs[facName]) == true end,
            function(v) sendBridgeAction("jobs", facName, v) end)

        addAccessToggle("Государственные услуги (каталог)", "Оказание платных услуг населению",
            function() return fac.ServiceAccess == true end,
            function(v) sendAction("setServiceAccess", { facName, "service", v }) end)

        addAccessToggle("Выписка счетов и квитанций", "Формирование счетов на оплату в банкоматах",
            function() return fac.InvoiceAccess == true end,
            function(v) sendAction("setServiceAccess", { facName, "invoice", v }) end)

        addAccessToggle("Государственный реестр дипломов", "Выдача официальных дипломов об образовании",
            function() return fac.DiplomaAccess == true end,
            function(v) sendAction("setServiceAccess", { facName, "diploma", v }) end)
    end

    -- ════════════ 6. ВООРУЖЕНИЕ И ФОРМА ════════════
    local function buildWeaponsModelsTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local split = vgui.Create("DPanel", pnl)
        split:Dock(FILL); split:SetPaintBackground(false)

        local left = vgui.Create("DPanel", split)
        left:Dock(LEFT); left:SetWide((pnl:GetWide() - 30) * 0.49)
        left.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Табельное вооружение организации", "GRMFac_Sub", 16, 16, C.gold)
            draw.SimpleText("Оружие настраивается по фракции, ролям и отделам.", "GRMFac_Small", 16, 40, C.dim)
        end

        local right = vgui.Create("DPanel", split)
        right:Dock(RIGHT); right:SetWide((pnl:GetWide() - 30) * 0.49)
        right.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Служебная форма и гардероб", "GRMFac_Sub", 16, 16, C.green)
            draw.SimpleText("Модели и бодигруппы назначаются по должностям и отделам.", "GRMFac_Small", 16, 40, C.dim)
        end

        mkBtn(left, "Открыть редактор арсенала (/weapons_admin)", C.accent, C.accentHover, function()
            RunConsoleCommand("weapons_admin")
        end):Dock(BOTTOM); left:GetChildren()[1]:DockMargin(16, 0, 16, 16); left:GetChildren()[1]:SetTall(40)

        mkBtn(right, "Открыть редактор гардероба (/models_admin)", C.green, C.greenHover, function()
            RunConsoleCommand("models_admin")
        end):Dock(BOTTOM); right:GetChildren()[1]:DockMargin(16, 0, 16, 16); right:GetChildren()[1]:SetTall(40)
    end

    -- ════════════ 7. МАСКИРОВКА И СПЕЦНАСТРОЙКИ ════════════
    local function buildMaskTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local panel = vgui.Create("DPanel", pnl)
        panel:Dock(FILL)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Маскировка и работа под прикрытием", "GRMFac_Sub", 16, 16, C.teal)
            draw.SimpleText("Назначение отделов разведки, выбор поддельной формы и документов прикрытия.", "GRMFac_Normal", 16, 44, C.dim)
        end

        mkBtn(panel, "Открыть панель маскировки (/grm_mask_admin)", C.teal, C.accentHover, function()
            RunConsoleCommand("grm_mask_admin")
        end):Dock(BOTTOM); panel:GetChildren()[1]:DockMargin(16, 0, 16, 16); panel:GetChildren()[1]:SetTall(42)
    end

    -- ════════════ 8. КОМЕНДАНТСКИЙ ЧАС ════════════
    local function buildCurfewTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local cState = CurfewState or { active = false, endTime = 0, faction = "" }
        local p = vgui.Create("DPanel", pnl)
        p:Dock(FILL)
        p.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Комендантский час", "GRMFac_Sub", 16, 16, C.red)
            local rem = math.max(0, (cState.endTime or 0) - CurTime())
            local stText = cState.active and ("АКТИВЕН — осталось: " .. string.format("%02d:%02d", math.floor(rem / 60), math.floor(rem % 60))) or "НЕ АКТИВЕН"
            draw.SimpleText("Текущий статус: " .. stText, "GRMFac_Normal", 16, 46, cState.active and C.red or C.green)
        end

        local bBar = vgui.Create("DPanel", p)
        bBar:Dock(BOTTOM); bBar:SetTall(42); bBar:DockMargin(16, 0, 16, 16); bBar:SetPaintBackground(false)

        mkBtn(bBar, "Объявить на 10 мин", C.red, C.redHover, function()
            sendExtAction("startCurfew", { 600 }, refreshView)
        end):Dock(LEFT); bBar:GetChildren()[1]:SetWide(180)

        mkBtn(bBar, "Объявить на 20 мин", C.red, C.redHover, function()
            sendExtAction("startCurfew", { 1200 }, refreshView)
        end):Dock(LEFT); bBar:GetChildren()[2]:DockMargin(8, 0, 0, 0); bBar:GetChildren()[2]:SetWide(180)

        mkBtn(bBar, "Отменить комендантский час", C.green, C.greenHover, function()
            sendExtAction("stopCurfew", {}, refreshView)
        end):Dock(RIGHT); bBar:GetChildren()[3]:SetWide(220)
    end

    -- ════════════ 9. КАЗНА И ЭКОНОМИКА ════════════
    local function buildFinanceTab(pnl, facName, facData)
        local fac = facData and facData[facName] or {}
        local eco = GRM.Economy and GRM.Economy.Local
        local fromEco = (eco and eco.faction == facName and istable(eco.data)) and tonumber(eco.data.budget) or nil
        local treasury = math.max(0, math.floor(fromEco or fac.Budget or 0))
        local taxPct = math.floor((tonumber(fac.TaxRate) or (eco and eco.data and eco.data.taxRate) or 0.05) * 100)
        local stateBud = (GRM.StateBudgetGet and GRM.StateBudgetGet()) or 0
        local fmt = function(n) return (GRM.Format and GRM.Format(n)) or (tostring(n) .. " GRM") end

        local scroll = vgui.Create("DScrollPanel", pnl)
        scroll:Dock(FILL)

        local cards = vgui.Create("DPanel", scroll)
        cards:Dock(TOP)
        cards:SetTall(118)
        cards:SetPaintBackground(false)
        cards.Paint = function(self, w, h)
            local cw = math.floor((w - 16) / 3)
            local function box(x, title, val, col)
                draw.RoundedBox(6, x, 0, cw, h, C.card)
                surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
                surface.DrawOutlinedRect(x, 0, cw, h)
                draw.SimpleText(title, "GRMFac_Small", x + 14, 16, C.dim)
                draw.SimpleText(val, "GRMFac_StatVal", x + 14, 48, col)
            end
            box(0, "КАЗНА ФРАКЦИИ", fmt(treasury), C.gold)
            box(cw + 8, "ГОСБЮДЖЕТ", fmt(stateBud), C.accent)
            box((cw + 8) * 2, "НАЛОГ С ЗП", tostring(taxPct) .. "%", C.green)
        end

        local help = vgui.Create("DPanel", scroll)
        help:Dock(TOP)
        help:SetTall(86)
        help:DockMargin(0, 10, 0, 8)
        help.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Единая казна GRM", "GRMFac_Sub", 16, 14, C.text)
            draw.SimpleText("Субсидии с банковского ПК и /feco_admin пишутся сюда же. Закупка транспорта списывает эту казну.", "GRMFac_Small", 16, 40, C.dim)
            draw.SimpleText("Пополнение: госбюджет → фракция. Снятие лидером: банкомат / !fwithdraw.", "GRMFac_Small", 16, 58, C.dim)
        end

        launchCard(scroll, "Полная панель экономики",
            "Госбюджет, казны фракций, зарплаты, налоги, фин.лог.",
            "icon16/money.png", "grm_salary_admin", C.gold)
        launchCard(scroll, "Автопарк организации",
            "Закупка техники из казны фракции.",
            "icon16/lorry.png", "grm_fleet", C.accent)
    end

    -- ════════════ 10. СОЗДАТЬ ОРГАНИЗАЦИЮ (SUPERADMIN) ════════════
    local function buildCreateTab(pnl, facName, facData)
        local form = vgui.Create("DPanel", pnl)
        form:Dock(FILL)
        form.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Регистрация новой государственной или частной организации", "GRMFac_Sub", 16, 16, C.gold)
        end

        local lbl1 = vgui.Create("DLabel", form)
        lbl1:SetPos(20, 50); lbl1:SetText("Регистрационный системный ключ (eng):"); lbl1:SetFont("GRMFac_Normal"); lbl1:SetTextColor(C.dim); lbl1:SizeToContents()
        local entKey = vgui.Create("DTextEntry", form)
        entKey:SetPos(20, 72); entKey:SetSize(400, 28); skinTextEntry(entKey); entKey:SetPlaceholderText("police_department")
        bindFormField(entKey, "create.key")

        local lbl2 = vgui.Create("DLabel", form)
        lbl2:SetPos(20, 110); lbl2:SetText("Публичное название организации (RU):"); lbl2:SetFont("GRMFac_Normal"); lbl2:SetTextColor(C.dim); lbl2:SizeToContents()
        local entDisp = vgui.Create("DTextEntry", form)
        entDisp:SetPos(20, 132); entDisp:SetSize(400, 28); skinTextEntry(entDisp); entDisp:SetPlaceholderText("Полицейский Департамент")
        bindFormField(entDisp, "create.display")

        local lbl3 = vgui.Create("DLabel", form)
        lbl3:SetPos(20, 170); lbl3:SetText("Тэг радиоволны:"); lbl3:SetFont("GRMFac_Normal"); lbl3:SetTextColor(C.dim); lbl3:SizeToContents()
        local entTag = vgui.Create("DTextEntry", form)
        entTag:SetPos(20, 192); entTag:SetSize(400, 28); skinTextEntry(entTag); entTag:SetPlaceholderText("PD")
        bindFormField(entTag, "create.tag")

        local btnCreate = mkBtn(form, "+ Создать организацию", C.green, C.greenHover, function()
            local kVal = string.Trim(entKey:GetText())
            local dVal = string.Trim(entDisp:GetText())
            local tVal = string.Trim(entTag:GetText())
            if kVal == "" or dVal == "" then notification.AddLegacy("Заполните ключ и название!", NOTIFY_ERROR, 3) return end
            sendAction("createFactionV2", { kVal, dVal, "", tVal, 255, 200, 50 }, function()
                -- черновик формы больше не нужен
                formValues["create.key"], formValues["create.display"], formValues["create.tag"] = nil, nil, nil
                f:Remove()
                UI.Open(kVal)
                notification.AddLegacy("Организация создана!", NOTIFY_GENERIC, 3)
            end)
        end)
        btnCreate:SetPos(20, 250); btnCreate:SetSize(400, 38)
    end

    -- ════════════ 11. СПЕЦСЛУЖБЫ И НАБЛЮДЕНИЕ ════════════
    local function buildSecurityTab(pnl, facName, facData)
        local scroll = vgui.Create("DScrollPanel", pnl)
        scroll:Dock(FILL)
        launchCard(scroll, "CCTV — камеры и наблюдение",
            "Назначение фракций с доступом к городской системе видеонаблюдения.",
            "icon16/camera.png", "grm_cctv_access", C.accent)
        launchCard(scroll, "Прослушка помещений (RoomTap)",
            "Управление доступом к прослушке и запросами на установку «жучков».",
            "icon16/sound.png", "roomtap_access", C.teal)
        launchCard(scroll, "Магазин оборудования прослушки",
            "Выдача аппаратуры прослушки оперативным сотрудникам.",
            "icon16/cart.png", "roomtap_shop", C.teal)
        launchCard(scroll, "Розыск и штрафы",
            "Каталог статей, вменение нарушений и выписка штрафов.",
            "icon16/page_white_edit.png", "grm_wanted", C.gold)
        launchCard(scroll, "Доступы к розыску",
            "Какие фракции и роли могут вести розыск, ориентировки и обмен сведениями.",
            "icon16/key.png", "grm_wanted_access", C.gold)
    end

    -- ════════════ 12. СЛУЖЕБНЫЕ СИСТЕМЫ ════════════
    local function buildServiceSystemsTab(pnl, facName, facData)
        local scroll = vgui.Create("DScrollPanel", pnl)
        scroll:Dock(FILL)
        launchCard(scroll, "Логистика и снабжение",
            "Доступ фракций к матовозкам, точкам погрузки и складам.",
            "icon16/lorry.png", "grm_logistics_admin_menu", C.green)
        launchCard(scroll, "Экономика и казна",
            "Бюджеты, налоги, переводы средств (полная панель).",
            "icon16/money.png", "grm_feco", C.gold)
        launchCard(scroll, "Аугментации и импланты",
            "Управление киберимплантами и их выдачей.",
            "icon16/wrench.png", "grm_augmentations_admin", C.accent)
        launchCard(scroll, "Доступы к аугментациям",
            "Кто может выдавать и снимать импланты по фракциям и ролям.",
            "icon16/key.png", "grm_augmentation_access_admin", C.accent)
        launchCard(scroll, "Магазин телефонии",
            "Управление ассортиментом телефонов и смартфонов.",
            "icon16/phone.png", "grm_phone_shop_admin", C.green)
    end

    -- ════════════ ПРАВА МЕНЮ (только суперадмин) ════════════
    local function buildMenuAccessTab(pnl)
        local MA = GRM.MenuAccess
        local scroll = vgui.Create("DScrollPanel", pnl)
        scroll:Dock(FILL)

        if not MA then
            local warn = vgui.Create("DLabel", scroll)
            warn:Dock(TOP) warn:SetTall(40) warn:SetFont("GRMFac_Sub") warn:SetTextColor(C.red)
            warn:SetText("Модуль прав меню не загружен (sh_grm_faction_menu_access.lua).")
            return
        end

        local head = vgui.Create("DPanel", scroll)
        head:Dock(TOP) head:SetTall(62) head:DockMargin(0, 0, 0, 8)
        head.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("КТО ВИДИТ РАЗДЕЛЫ ЭТОГО МЕНЮ", "GRMFac_Sub", 14, 12, C.gold)
            draw.SimpleText("Суперадмин видит всё всегда. Здесь решается, что показывать лидерам и сотрудникам.",
                "GRMFac_Small", 14, 36, C.dim)
        end

        -- Рабочая копия: правки применяются только по кнопке «Сохранить».
        local levels = table.Copy(MA.Config.levels or {})
        local overrides = table.Copy(MA.Config.overrides or {})

        local knownKeys, seen = {}, {}
        for _, row in ipairs(MA.Tabs) do
            knownKeys[#knownKeys + 1] = { key = row.key, name = row.name }
            seen[row.key] = true
        end
        for _, row in ipairs(hookedPanels) do
            local key = "ext:" .. row.label
            if not seen[key] then
                seen[key] = true
                knownKeys[#knownKeys + 1] = { key = key, name = row.label .. "  (модуль)" }
            end
        end
        for key in pairs(levels) do
            if not seen[key] then
                seen[key] = true
                knownKeys[#knownKeys + 1] = { key = key, name = MA.TabName(key) }
            end
        end

        for _, row in ipairs(knownKeys) do
            local line = vgui.Create("DPanel", scroll)
            line:Dock(TOP) line:SetTall(54) line:DockMargin(0, 0, 0, 6)
            line.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(row.name, "GRMFac_Sub", 14, 12, C.text)
                local lvl = levels[row.key] or MA.DefaultLevel(row.key)
                draw.SimpleText("по умолчанию: " .. (MA.LevelNames[MA.DefaultLevel(row.key)] or "?"),
                    "GRMFac_Small", 14, 32, C.dim)
                if lvl == "admin" or lvl == "off" then
                    draw.SimpleText("ЗАКРЫТО", "GRMFac_Small", 300, 20, C.gold)
                end
            end

            local combo = vgui.Create("DComboBox", line)
            combo:Dock(RIGHT) combo:SetWide(230) combo:DockMargin(8, 13, 12, 13)
            skinCombo(combo)
            local cur = levels[row.key] or MA.DefaultLevel(row.key)
            for _, lvl in ipairs(MA.LevelOrder) do
                combo:AddChoice(MA.LevelNames[lvl] or lvl, lvl, lvl == cur)
            end
            combo.OnSelect = function(_, _, _, value)
                levels[row.key] = value
            end
        end

        local note = vgui.Create("DPanel", scroll)
        note:Dock(TOP) note:SetTall(52) note:DockMargin(0, 6, 0, 6)
        note.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Исключение для текущей организации: " .. tostring(targetFac or "—"),
                "GRMFac_Small", 14, 10, C.dim)
            draw.SimpleText("Позволяет открыть раздел одной организации, не открывая его всем.",
                "GRMFac_Small", 14, 30, C.dim)
        end

        local exRow = vgui.Create("DPanel", scroll)
        exRow:Dock(TOP) exRow:SetTall(44) exRow:DockMargin(0, 0, 0, 8)
        exRow:SetPaintBackground(false)

        local exTab = vgui.Create("DComboBox", exRow)
        exTab:Dock(LEFT) exTab:SetWide(300) exTab:DockMargin(0, 6, 8, 6)
        skinCombo(exTab)
        for _, row in ipairs(knownKeys) do exTab:AddChoice(row.name, row.key, false) end
        exTab:SetValue("Раздел…")

        local exLevel = vgui.Create("DComboBox", exRow)
        exLevel:Dock(LEFT) exLevel:SetWide(230) exLevel:DockMargin(0, 6, 8, 6)
        skinCombo(exLevel)
        for _, lvl in ipairs(MA.LevelOrder) do exLevel:AddChoice(MA.LevelNames[lvl] or lvl, lvl, false) end
        exLevel:SetValue("Уровень…")

        local exAdd = vgui.Create("DButton", exRow)
        exAdd:Dock(LEFT) exAdd:SetWide(170) exAdd:DockMargin(0, 6, 0, 6)
        exAdd:SetText("")
        exAdd.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and C.accentHover or C.accent)
            draw.SimpleText("ДОБАВИТЬ ИСКЛЮЧЕНИЕ", "GRMFac_Btn", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local exList = vgui.Create("DPanel", scroll)
        exList:Dock(TOP) exList:SetTall(150) exList:DockMargin(0, 0, 0, 8)
        exList:SetPaintBackground(false)

        local rebuildEx
        rebuildEx = function()
            exList:Clear()
            local y = 0
            for fac, rows in pairs(overrides) do
                for key, lvl in pairs(rows) do
                    local item = vgui.Create("DPanel", exList)
                    item:Dock(TOP) item:SetTall(30) item:DockMargin(0, 0, 0, 4)
                    item.Paint = function(_, w, h)
                        draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
                        draw.SimpleText(fac .. "  ·  " .. MA.TabName(key) .. "  →  " .. (MA.LevelNames[lvl] or lvl),
                            "GRMFac_Small", 12, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                    local del = vgui.Create("DButton", item)
                    del:Dock(RIGHT) del:SetWide(90) del:SetText("")
                    del.Paint = function(self, w, h)
                        draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and C.redHover or C.red)
                        draw.SimpleText("УБРАТЬ", "GRMFac_Small", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                    del.DoClick = function()
                        overrides[fac][key] = nil
                        if not next(overrides[fac]) then overrides[fac] = nil end
                        rebuildEx()
                    end
                    y = y + 34
                end
            end
            exList:SetTall(math.max(40, y))
        end
        rebuildEx()

        exAdd.DoClick = function()
            local _, tabKey = exTab:GetSelected()
            local _, lvl = exLevel:GetSelected()
            if not isstring(tabKey) or not isstring(lvl) or not targetFac then return end
            overrides[targetFac] = overrides[targetFac] or {}
            overrides[targetFac][tabKey] = lvl
            rebuildEx()
        end

        local save = vgui.Create("DButton", scroll)
        save:Dock(TOP) save:SetTall(42) save:DockMargin(0, 4, 0, 12)
        save:SetText("")
        save.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and C.greenHover or C.green)
            draw.SimpleText("СОХРАНИТЬ ПРАВА РАЗДЕЛОВ", "GRMFac_Btn", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        save.DoClick = function()
            if MA.RequestSave then MA.RequestSave(levels, overrides) end
            surface.PlaySound("buttons/button15.wav")
        end
    end

    -- Добавление вкладок в боковое меню
    addTabBtn("overview", "Обзор", "icon16/application_home.png", buildOverviewTab)
    addTabBtn("members", "Личный состав", "icon16/group.png", buildMembersTab)
    addTabBtn("structure", "Структура и штат", "icon16/chart_organisation.png", buildStructureTab)
    addTabBtn("positions", "Должности", "icon16/award_star_gold_1.png", buildPositionsTab)
    addTabBtn("personnel", "Кадровые дела", "icon16/book.png", buildPersonnelTab)
    addTabBtn("access", "Доступы и связь", "icon16/key.png", buildAccessTab)
    addTabBtn("gear", "Вооружение и форма", "icon16/shield.png", buildWeaponsModelsTab)
    addTabBtn("mask", "Маскировка", "icon16/user_suit.png", buildMaskTab)
    addTabBtn("curfew", "Комендантский час", "icon16/clock.png", buildCurfewTab)
    addTabBtn("finance", "Казна и финансы", "icon16/money.png", buildFinanceTab)
    addTabBtn("security", "Спецслужбы", "icon16/camera.png", buildSecurityTab)
    addTabBtn("service", "Служебные системы", "icon16/wrench.png", buildServiceSystemsTab)
    if isSA then
        addTabBtn("create", "Создать организацию", "icon16/add.png", buildCreateTab)
        addTabBtn("menuaccess", "Права меню", "icon16/lock_edit.png", buildMenuAccessTab)
    end

    -- ── Разделы от других модулей ────────────────────────────────────────
    -- Прокси с методом AddSheet: модулям он выглядит как DPropertySheet,
    -- а на деле каждая «страница» превращается в кнопку бокового меню GRM.
    do
        local proxy = hookHost
        local order = 0
        proxy.AddSheet = function(_, label, panel, icon)
            if not IsValid(panel) then return end
            order = order + 1
            label = tostring(label or ("Раздел " .. order))
            -- Ключ прав для навесного раздела — по его названию, чтобы
            -- суперадмин мог выдать, например, «Логистику» лидерам, оставив
            -- «Доступ к аресту» только себе.
            local key = "ext:" .. label
            if not tabVisible(key) then
                if IsValid(panel) then panel:Remove() end
                return
            end

            panel:SetParent(hookHost)
            panel:SetVisible(false)
            hookedPanels[#hookedPanels + 1] = { key = key, panel = panel, label = label }

            addTabBtn(key, label, isstring(icon) and icon or "icon16/plugin.png", function(parent)
                if not IsValid(panel) then return end
                panel:SetParent(parent)
                panel:SetVisible(true)
                panel:Dock(FILL)
                panel:DockMargin(0, 0, 0, 0)
                panel:InvalidateLayout(true)
            end)

            return { Name = label, Panel = panel, Tab = tabButtons[key] }
        end

        if hook and hook.Call then
            pcall(hook.Call, "GRM_FactionsAdmin_BuildTabs", nil, proxy)
        end
    end

    -- Панели модулей не должны исчезнуть вместе с окном раньше времени.
    f.OnRemove = function()
        for _, row in ipairs(hookedPanels) do
            if IsValid(row.panel) then row.panel:Remove() end
        end
        hookedPanels = {}
    end

    -- Открываем первый ДОСТУПНЫЙ раздел: у сотрудника без прав «Обзора» может
    -- не быть вовсе, и окно не должно оставаться пустым без объяснения.
    if requestedTab and tabButtons[requestedTab] and tabButtons[requestedTab].builder then
        -- Переключение организации не должно выкидывать в «Обзор»:
        -- возвращаемся в тот же раздел, где админ работал.
        selectTab(requestedTab, tabButtons[requestedTab].builder)
    elseif tabButtons["overview"] then
        selectTab("overview", buildOverviewTab)
    else
        local firstKey, firstBtn
        for key, btn in pairs(tabButtons) do
            if IsValid(btn) and (not firstBtn or btn:GetY() < firstBtn:GetY()) then
                firstKey, firstBtn = key, btn
            end
        end
        if firstKey and tabButtons[firstKey].builder then
            selectTab(firstKey, tabButtons[firstKey].builder)
        else
            local empty = vgui.Create("DPanel", content)
            empty:Dock(FILL)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("Разделы этого меню закрыты вашей должности.", "GRMFac_Sub",
                    w / 2, h / 2 - 12, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("Доступ выдаёт суперадминистратор: /factions → «Права меню».", "GRMFac_Small",
                    w / 2, h / 2 + 12, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end
    net.Start("Factions_GetData")
    net.SendToServer()
    -- Подтянуть свежие флаги доступов (доска/эфир/оповещения/биржа).
    net.Start("GRM_FAcc_Get")
    net.SendToServer()
    -- Подтянуть доступы по ролям (FactionPerms).
    if GRM.FactionPerms and GRM.FactionPerms.Request then
        GRM.FactionPerms.Request()
    end
end

function OpenUnifiedFactionsMenu(fname)
    UI.Open(fname)
end

concommand.Add("grm_factions_menu", function() UI.Open() end)
concommand.Add("grm_faction", function() UI.Open() end)
concommand.Add("factions_unified", function() UI.Open() end)

-- Общая точка пересборки вкладки: с сохранением введённого текста и прокрутки.
local pendingRefreshData = nil

local function findScrollPanel(panel)
    local found = nil
    eachChild(panel, function(child)
        if not found and child.GetClassName and child:GetClassName() == "DScrollPanel" then found = child end
    end)
    return found
end

local function rebuildCurrentTab(data)
    if not (IsValid(currentFrame) and IsValid(currentContent)) then return end
    local btn = currentTabButtons and currentTabButtons[currentTab]
    if not (btn and btn.builder) then return end

    -- Разделы других модулей (арест, экономика, логистика, пожарные…)
    -- обновляют себя сами по своим сетевым каналам. Пересобирать их при
    -- каждом автосинке фракций нельзя: панель модуля живёт дольше вкладки,
    -- и Clear() просто оставлял пустой экран.
    if isstring(currentTab) and currentTab:sub(1, 4) == "ext:" then return end

    collectFormValues(currentContent)

    local keep = 0
    local oldScroll = findScrollPanel(currentContent)
    if IsValid(oldScroll) and IsValid(oldScroll.VBar) then keep = oldScroll.VBar:GetScroll() end

    if currentParkHooked then currentParkHooked() end
    currentContent:Clear()
    btn.builder(currentContent, currentTargetFac, data or FactionsData or {})

    if keep > 0 then
        timer.Simple(0, function()
            if not IsValid(currentContent) then return end
            local newScroll = findScrollPanel(currentContent)
            if IsValid(newScroll) and IsValid(newScroll.VBar) then newScroll.VBar:SetScroll(keep) end
        end)
    end
end

hook.Add("GRM_FactionUIRefreshed", "GRM_FactionUnified_AutoRefresh", function(data)
    if not IsValid(currentFrame) or not IsValid(currentContent) then return end

    -- Полный снимок организаций приходит частями и уже ПОСЛЕ открытия окна,
    -- поэтому список организаций в шапке дозаполняется здесь, а не только
    -- при открытии (раньше при первом заходе он оставался пустым до
    -- переоткрытия меню).
    if UI.RebuildSelector then pcall(UI.RebuildSelector) end

    -- НЕ переключаем организацию при обновлении данных: пользователь мог сам
    -- выбрать фракцию для просмотра (особенно суперадмин).
    -- И НЕ пересобираем панель, пока в ней печатают: иначе введённый текст
    -- (например, ключ и название новой организации) исчезает на глазах.
    if hasActiveInput(currentContent) then
        pendingRefreshData = data or FactionsData or {}
        return
    end
    rebuildCurrentTab(data)
end)

-- Отложенное обновление применяется, когда ввод закончен.
hook.Add("Think", "GRM_FactionUnified_PendingRefresh", function()
    if not pendingRefreshData then return end
    if not (IsValid(currentFrame) and IsValid(currentContent)) then pendingRefreshData = nil return end
    if hasActiveInput(currentContent) then return end
    local data = pendingRefreshData
    pendingRefreshData = nil
    rebuildCurrentTab(data)
end)

hook.Add("GRM_FAccDataUpdated", "GRM_FactionUnified_AccessRefresh", function()
    -- Обновить вкладку «Доступы и связь», если она открыта и флаги пришли.
    if IsValid(currentFrame) and IsValid(currentContent) and currentTab == "access" then
        if hasActiveInput(currentContent) then
            pendingRefreshData = FactionsData or {}
            return
        end
        rebuildCurrentTab(FactionsData or {})
    end
end)

hook.Add("GRMRPChat_ClientCommand", "GRM_FactionUnified_ChatCommand", function(ply, text)
    if ply ~= LocalPlayer() then return end
    local datapack = { tostring(text or ""), SkipPlayerSay = false }
    if not istable(datapack) then return end
    local text = datapack[1]
    if not isstring(text) then return end
    local lower = string.lower(string.Trim(text))
    if lower == "/fmenu" or lower == "/фракция" or lower == "/состав" or lower == "/factions" then
        if CLIENT then UI.Open() end
    end

    if datapack.SkipPlayerSay == true then return true end
end)

print("[GRM Factions Unified UI] v" .. UI.Version .. " fully initialized with all 12 management domains")
