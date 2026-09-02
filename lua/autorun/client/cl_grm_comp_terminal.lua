--[[--------------------------------------------------------------------
    GRM Comp Terminal — клиентская часть общих ответов терминалов
    Полиции Порядка и Полевой жандармерии.

    Раньше терминалы работали «вслепую»: команда уходила на сервер и
    никакого подтверждения не приходило (Д5). Теперь сервер отвечает
    результатом, а реестр обновляется без переоткрытия окна.
----------------------------------------------------------------------]]

if SERVER then return end

net.Receive("GRM_CompTerminal_Result", function()
    local ok  = net.ReadBool()
    local msg = net.ReadString()
    if msg == "" then return end

    notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
    surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")

    -- Успешное действие меняет реестр — просим свежий срез.
    if ok and IsValid(GRM_CompTerminal_ActiveFrame) then
        net.Start("GRM_CompTerminal_Act")
            net.WriteString("refresh")
            net.WriteString(GRM_CompTerminal_ActiveJur or "civil")
            net.WriteString("")
            net.WriteString("")
            net.WriteUInt(0, 32)
            net.WriteString("")
        net.SendToServer()
    end
end)

net.Receive("GRM_CompTerminal_Fines", function()
    local wanted = net.ReadTable() or {}
    local fines  = net.ReadTable() or {}
    -- v1.2: третьим блоком идут заявки соседнего ведомства. Старый
    -- сервер их не шлёт — net.ReadTable() вернёт пустую таблицу, поэтому
    -- клиент совместим с обеими версиями.
    local requests = net.ReadTable() or {}
    local warrants = net.ReadTable() or {}

    local frame = GRM_CompTerminal_ActiveFrame
    if not IsValid(frame) then return end

    if isfunction(frame._fillFines) then frame._fillFines(fines) end
    if isfunction(frame._fillWanted) then frame._fillWanted(wanted) end
    if isfunction(frame._fillWantedExchange) then frame._fillWantedExchange(wanted) end
    if isfunction(frame._fillRequests) then frame._fillRequests(requests) end
    if isfunction(frame._fillWarrants) then frame._fillWarrants(warrants) end
end)

--- Человеческое имя структуры по коду юрисдикции.
--- Наполнение списка розыска (полицейский и жандармский терминалы имели
-- по копии этого тела; §5.4 п.12).
function GRM_CompTerminal_FillWanted(list, recs)
    if not IsValid(list) then return end
    list:Clear()
    for k, r in pairs(recs or {}) do
        if istable(r) and (r.level or 0) > 0 then
            local starStr = string.rep("★", math.Clamp(r.level or 1, 1, 5))
            local reas = {}
            for _, rc in ipairs(r.reasons or {}) do reas[#reas+1] = (rc.code or "") .. " " .. (rc.title or "") end
            local status = (r.jurisdiction == "military") and "ВОЕННЫЙ" or "ГРАЖДАНСКИЙ"
            if r.foreign then status = status .. " •перед." end
            local line = list:AddLine(starStr, status, r.name or k, table.concat(reas, ", "), k)
            line._targetKey = k
        end
    end
end

--- Статус штрафа для реестра квитанций.
function GRM_CompTerminal_FineStatus(s)
    if s == "paid" then return "оплачен" end
    if s == "cancelled" then return "аннулирован" end
    return "не оплачен"
end

function GRM_CompTerminal_FillFines(list, rows)
    if not IsValid(list) then return end
    list:Clear()
    for _, r in ipairs(rows or {}) do
        local line = list:AddLine(
            tostring(r.id or "?"),
            r.targetName or r.target or "?",
            tostring(math.floor(tonumber(r.amount) or 0)),
            GRM_CompTerminal_FineStatus(r.status),
            r.reason or "—")
        line._fineID = r.id
    end
end

function GRM_CompTerminal_JurName(j)
    return j == "military" and "Полевая жандармерия" or "Полиция Порядка"
end

--- Короткая метка статуса разыскиваемого для таблиц.
function GRM_CompTerminal_JurTag(j)
    return j == "military" and "ВОЕННЫЙ" or "ГРАЖДАНСКИЙ"
end

--- Единая обёртка для отправки команд терминала: все кнопки любого
-- терминала обязаны ходить через неё, чтобы протокол не разъезжался.
-- @param action  строка действия (см. sv_grm_comp_terminal.lua)
-- @param target  ключ персонажа или ""
-- @param text    произвольный текст (причина, примечание)
-- @param num     число (уровень, сумма, номер записи)
-- @param extra   дополнительный строковый параметр (id статьи, режим)
function GRM_CompTerminal_Send(action, target, text, num, extra)
    net.Start("GRM_CompTerminal_Act")
        net.WriteString(tostring(action or ""))
        net.WriteString(GRM_CompTerminal_ActiveJur or "civil")
        net.WriteString(tostring(target or ""))
        net.WriteString(tostring(text or ""))
        net.WriteUInt(math.max(0, math.floor(tonumber(num) or 0)), 32)
        net.WriteString(tostring(extra or ""))
    net.SendToServer()
end

-----------------------------------------------------------------------
-- Вкладка «Межведомственный обмен»
--
-- Одинаковая для полицейского и жандармского терминалов, поэтому живёт
-- здесь, а не дублируется в двух cl_init.lua. Всё, что ей нужно, —
-- список записей розыска (тот же, что уже пришёл терминалу) и заявки.
-----------------------------------------------------------------------
--- @param tabs         DPropertySheet терминала
-- @param frame        окно терминала (в него ставятся _fill*-хуки)
-- @param colors       палитра терминала {panel,text,dim,accent,gold,...}
-- @param wantedRecs   МАП key → запись розыска
-- @param requests     массив заявок соседнего ведомства
-- @param jurisdiction "civil" | "military"
-- @param canEdit      разрешены ли операции
function GRM_CompTerminal_BuildExchangeTab(tabs, frame, colors, wantedRecs, requests, jurisdiction, canEdit)
    if not IsValid(tabs) then return end
    local CC = colors or {}
    local panel  = CC.panel  or Color(25, 34, 50, 245)
    local text   = CC.text   or Color(230, 238, 250)
    local dim    = CC.dim    or Color(150, 165, 185)
    local accent = CC.accent or Color(70, 150, 255)
    local gold   = CC.gold   or Color(245, 205, 80)
    local danger = CC.danger or Color(220, 70, 70)
    local okCol  = CC.success or Color(60, 190, 100)

    local pnl = vgui.Create("DPanel", tabs)
    pnl:DockPadding(12, 12, 12, 12)
    pnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, panel) end

    local function styled(parent, label, x, y, w, h, col, fn)
        local b = vgui.Create("DButton", parent)
        b:SetPos(x, y) b:SetSize(w, h)
        b:SetText(label) b:SetFont("DermaDefaultBold") b:SetTextColor(color_white)
        b.Paint = function(s, bw, bh)
            draw.RoundedBox(4, 0, 0, bw, bh, s:IsHovered() and col or Color(col.r * 0.72, col.g * 0.72, col.b * 0.72))
        end
        b.DoClick = function()
            if not canEdit then
                notification.AddLegacy("У вас нет прав на эту операцию.", NOTIFY_ERROR, 4)
                return
            end
            surface.PlaySound("ui/buttonclick.wav")
            if fn then fn() end
        end
        return b
    end

    -- ── Левая колонка: наши и переданные дела ───────────────────────
    local lblCases = vgui.Create("DLabel", pnl)
    lblCases:SetPos(16, 8)
    lblCases:SetFont("DermaDefaultBold")
    lblCases:SetTextColor(accent)
    lblCases:SetText("Дела в производстве — можно передать соседнему ведомству")
    lblCases:SizeToContents()

    local listCases = vgui.Create("DListView", pnl)
    listCases:SetPos(16, 30)
    listCases:SetSize(560, 300)
    listCases:AddColumn("Статус"):SetFixedWidth(110)
    listCases:AddColumn("Разыскиваемый"):SetFixedWidth(200)
    listCases:AddColumn("Ур."):SetFixedWidth(44)
    listCases:AddColumn("Ключ")

    local function fillCases(recs)
        listCases:Clear()
        for k, r in pairs(recs or {}) do
            if istable(r) then
                local tag = GRM_CompTerminal_JurTag(r.jurisdiction)
                if r.foreign then tag = tag .. " •перед." end
                local line = listCases:AddLine(tag, r.name or k, tostring(r.level or 0), k)
                line._targetKey = k
                line._foreign = r.foreign == true
            end
        end
    end
    fillCases(wantedRecs)
    frame._fillWantedExchange = fillCases

    local entNote = vgui.Create("DTextEntry", pnl)
    entNote:SetPos(16, 338)
    entNote:SetSize(560, 26)
    entNote:SetPlaceholderText("Примечание к передаче (необязательно)…")

    local function selectedKey()
        local id = listCases:GetSelectedLine()
        if not id then
            notification.AddLegacy("Выберите дело из списка.", NOTIFY_ERROR, 3)
            return nil
        end
        local row = listCases:GetLine(id)
        return row and row._targetKey, row and row._foreign
    end

    local other = jurisdiction == "military" and "Полиции Порядка" or "Жандармерии"

    styled(pnl, "Передать дело " .. other, 16, 372, 200, 30, accent, function()
        local key = selectedKey()
        if key then GRM_CompTerminal_Send("case_transfer", key, entNote:GetValue(), 0, "") end
    end)

    styled(pnl, "Поделиться сведениями", 224, 372, 180, 30, gold, function()
        local key = selectedKey()
        if key then GRM_CompTerminal_Send("case_share", key, entNote:GetValue(), 0, "") end
    end)

    styled(pnl, "Запросить дело себе", 412, 372, 164, 30, okCol, function()
        local key = selectedKey()
        if key then GRM_CompTerminal_Send("case_request", key, entNote:GetValue(), 0, "transfer") end
    end)

    styled(pnl, "Ориентировка своим (/fr)", 16, 410, 200, 30, accent, function()
        local key = selectedKey()
        if key then GRM_CompTerminal_Send("bulletin_fr", key, entNote:GetValue(), 0, "") end
    end)

    styled(pnl, "На волну (/dep)", 224, 410, 180, 30, gold, function()
        local key = selectedKey()
        if key then GRM_CompTerminal_Send("bulletin_dep", key, entNote:GetValue(), 0, "") end
    end)

    styled(pnl, "Обновить", 412, 410, 164, 30, Color(70, 84, 108), function()
        GRM_CompTerminal_Send("refresh", "", "", 0, "")
    end)

    -- ── Правая колонка: входящие заявки ─────────────────────────────
    local lblReq = vgui.Create("DLabel", pnl)
    lblReq:SetPos(592, 8)
    lblReq:SetFont("DermaDefaultBold")
    lblReq:SetTextColor(gold)
    lblReq:SetText("Заявки соседнего ведомства")
    lblReq:SizeToContents()

    local listReq = vgui.Create("DListView", pnl)
    listReq:SetPos(592, 30)
    listReq:SetSize(336, 300)
    listReq:AddColumn("№"):SetFixedWidth(38)
    listReq:AddColumn("Дело"):SetFixedWidth(140)
    listReq:AddColumn("Просит")

    local function fillRequests(list)
        listReq:Clear()
        for _, r in ipairs(list or {}) do
            local line = listReq:AddLine(tostring(r.id), tostring(r.targetName or "?"),
                (r.kind == "share" and "копию • " or "дело • ") .. tostring(r.fromName or "?"))
            line._reqID = r.id
            line._note  = r.note
        end
    end
    fillRequests(requests)
    frame._fillRequests = function(list)
        fillRequests(list)
    end

    local lblHint = vgui.Create("DLabel", pnl)
    lblHint:SetPos(592, 338)
    lblHint:SetSize(336, 26)
    lblHint:SetTextColor(dim)
    lblHint:SetText("Решение принимает та структура, которая ведёт дело.")

    local function selectedReq()
        local id = listReq:GetSelectedLine()
        if not id then
            notification.AddLegacy("Выберите заявку.", NOTIFY_ERROR, 3)
            return nil
        end
        local row = listReq:GetLine(id)
        return row and row._reqID
    end

    styled(pnl, "Удовлетворить", 592, 372, 160, 30, okCol, function()
        local id = selectedReq()
        if id then GRM_CompTerminal_Send("case_accept", "", entNote:GetValue(), id, "") end
    end)

    styled(pnl, "Отклонить", 760, 372, 168, 30, danger, function()
        local id = selectedReq()
        if id then GRM_CompTerminal_Send("case_decline", "", entNote:GetValue(), id, "") end
    end)

    if not canEdit then
        local lblRO = vgui.Create("DLabel", pnl)
        lblRO:SetPos(592, 412)
        lblRO:SetSize(336, 26)
        lblRO:SetTextColor(Color(240, 140, 120))
        lblRO:SetText("Режим чтения: операции обмена недоступны.")
    end

    tabs:AddSheet("Обмен сведениями", pnl, "icon16/arrow_switch.png")
    return pnl
end


function GRM_CompTerminal_BuildWarrantTab(tabs, frame, colors, onlineList, warrants, canEdit)
    if not IsValid(tabs) then return end
    local CC = colors or {}
    local panel  = CC.panel  or Color(25, 34, 50, 245)
    local dim    = CC.dim    or Color(150, 165, 185)
    local gold   = CC.gold   or Color(245, 205, 80)
    local okCol  = CC.success or Color(60, 190, 100)

    local pnl = vgui.Create("DPanel", tabs)
    pnl:DockPadding(12, 12, 12, 12)
    pnl.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, panel) end

    local hint = vgui.Create("DLabel", pnl)
    hint:SetPos(16, 8)
    hint:SetFont("DermaDefaultBold")
    hint:SetTextColor(gold)
    hint:SetText("Ходатайство уходит в Компьютер юстиции. Утверждает прокурор.")
    hint:SizeToContents()

    local list = vgui.Create("DListView", pnl)
    list:SetPos(16, 32)
    list:SetSize(910, 280)
    list:AddColumn("№"):SetFixedWidth(60)
    list:AddColumn("Тип"):SetFixedWidth(140)
    list:AddColumn("Фигурант"):SetFixedWidth(200)
    list:AddColumn("Статус"):SetFixedWidth(110)
    list:AddColumn("Основание")

    local typeLab = {
        search = "Обыск", arrest = "Арест",
        wiretap_judge = "Надзор", eviction = "Опечатывание",
    }
    local function fill(rows)
        list:Clear()
        for _, w in ipairs(rows or {}) do
            local st = w.status == "pending" and "ХОДАТАЙСТВО" or (w.status == "active" and "УТВЕРЖДЁН" or tostring(w.status or "—"))
            list:AddLine(tostring(w.number or w.id or "?"), typeLab[w.type] or tostring(w.type or "ордер"),
                tostring(w.name or w.sid or "?"), st, tostring(w.reason or ""))
        end
    end
    fill(warrants)
    if IsValid(frame) then frame._fillWarrants = fill end

    local combo = vgui.Create("DComboBox", pnl)
    combo:SetPos(16, 326) combo:SetSize(300, 26)
    combo:AddChoice("— фигурант онлайн —", "")
    for _, pl in ipairs(onlineList or {}) do
        combo:AddChoice(string.format("%s  [%s]", pl.rpName or "?", pl.nick or "?"), pl)
    end
    local selKey = ""
    combo.OnSelect = function(_, _, _, pd) if istable(pd) then selKey = pd.key or "" end end

    local comboT = vgui.Create("DComboBox", pnl)
    comboT:SetPos(326, 326) comboT:SetSize(200, 26)
    comboT:AddChoice("Обыск жилища", "search", true)
    comboT:AddChoice("Принудительный арест", "arrest")
    comboT:AddChoice("Опечатывание", "eviction")

    local mins = vgui.Create("DNumberWang", pnl)
    mins:SetPos(536, 326) mins:SetSize(70, 26)
    mins:SetMin(10) mins:SetMax(1440) mins:SetValue(60)

    local reason = vgui.Create("DTextEntry", pnl)
    reason:SetPos(616, 326) reason:SetSize(310, 26)
    reason:SetPlaceholderText("Основание ходатайства")

    local btn = vgui.Create("DButton", pnl)
    btn:SetPos(16, 366) btn:SetSize(280, 32)
    btn:SetText("Подать ходатайство в Прокуратуру")
    btn:SetFont("DermaDefaultBold") btn:SetTextColor(color_white)
    btn.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and okCol or Color(okCol.r * 0.7, okCol.g * 0.7, okCol.b * 0.7))
    end
    btn.DoClick = function()
        if not canEdit then notification.AddLegacy("Нет прав на ходатайство.", NOTIFY_ERROR, 3) return end
        if selKey == "" then notification.AddLegacy("Выберите фигуранта.", NOTIFY_ERROR, 3) return end
        local txt = string.Trim(reason:GetText() or "")
        if txt == "" then notification.AddLegacy("Укажите основание.", NOTIFY_ERROR, 3) return end
        local _, wType = comboT:GetSelected()
        GRM_CompTerminal_Send("warrant_request", selKey, txt, math.floor(mins:GetValue() or 60), wType or "search")
    end

    local note = vgui.Create("DLabel", pnl)
    note:SetPos(310, 370) note:SetSize(600, 24)
    note:SetTextColor(dim)
    note:SetText("После утверждения на волне /dep: [Правосудие] Прокурор (РП имя) утвердил ордер №…")

    tabs:AddSheet("Ордера и ходатайства", pnl, "icon16/page_white_star.png")
    return pnl
end
