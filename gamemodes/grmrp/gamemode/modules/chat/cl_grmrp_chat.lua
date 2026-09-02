--[[ GRMRPChat ввод: полоса с чипами каналов, история (↑/↓), Tab-дополнение
    команд. Модель textentryx из EasyChat (4.21.4) в нативном Derma-виде,
    без DHTML. Enter при пустом поле закрывает окно (§5.7).
]]

if SERVER then return end

local history = {}
local histIdx = 0
local histPanel = nil
local frame = nil
local entry = nil
local chips = nil
local selChan = "ic"

local function channelsOrdered()
    local list = {}
    for id, chan in pairs(GRMRPChat.Channels or {}) do
        if not chan.onlyDead then table.insert(list, { id = id, chan = chan }) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function commands()
    local out = { "/pm " }
    for _, chan in pairs(GRMRPChat.Channels or {}) do
        if chan.cmd then table.insert(out, "/" .. chan.cmd .. " ") end
    end
    table.sort(out)
    return out
end

local function send(text)
    -- ОДИН владелец sanitize — сервер (ядро парсит и чистит там); клиент
    -- печатает и шлёт сырьё, иначе превью/эхо показывают «［текст］＜» и
    -- выглядит как «плохо обрабатывает текст» (скрин 03.09).
    text = string.Trim(tostring(text or ""))
    if #text == 0 then return end
    if string.lower(text) == "/chatdiag" then
        -- Самодиагностика ленты (вечер-8): строку-диагностику печатает в
        -- ту же ленту — видно её = чат рендерит; не видно = сборка старая.
        if GRMRPChat.Diagnose then GRMRPChat.Diagnose() end
        return
    end
    if #text > 512 then text = string.sub(text, 1, 512) end
    table.insert(history, text)
    if #history > 50 then table.remove(history, 1) end
    histIdx = 0

    -- Локальный эхо-каст форматром ядра; для rand-действий (try/roll) и
    -- /it результат знает только сервер — там ждём настоящую строку
    -- (echo-флаг в RP-таблице, §5.1.3).
    local first = string.match(text, "^/([%w_]+)")
    local def = first and GRMRPChat.RP and GRMRPChat.RP[string.lower(first)]
    if not (def and def.echo) then
        GRMRPChat.AddSelfLine(text, selChan)
    end

    net.Start(GRMRP.Net.SAY)
        net.WriteString(selChan)
        net.WriteString(text)
    net.SendToServer()
end

local function closeInput()
    if IsValid(frame) then frame:Hide() end
    GRMRPChat.INPUT_OPEN = false
end

local function chanNow()
    return GRMRPChat.GetChannel and GRMRPChat.GetChannel(selChan)
end

local function toggleHistory()
    if IsValid(histPanel) then histPanel:Close() return end
    local win = vgui.Create("EditablePanel")
    histPanel = win
    win:SetSize(600, 400)
    win:Center()
    win:MakePopup()
    win.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(8, 14, 23, 245))
        surface.SetDrawColor(40, 62, 92, 140)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("История чата · выделения копируются Ctrl+C", "GRMRP_ChatChip",
            14, 8, Color(132, 160, 178))
    end
    win.OnRemove = function()
        GRMRPChat.HIST_OPEN = false
        histPanel = nil
    end
    win.OnKeyCodeTyped = function(_, code)
        if code == KEY_ESCAPE then win:Close() end
    end
    local scroll = vgui.Create("DScrollPanel", win)
    scroll:SetPos(10, 28)
    scroll:SetSize(win:GetWide() - 20, win:GetTall() - 38)
    local body = vgui.Create("DPanel", scroll)
    body:SetPaintBackground(false)
    body:Dock(TOP)
    local y = 0
    local lines = GRMRPChat.lines or {}
    local shift = RealTime() - CurTime()
    for i = 1, #lines do
        local ln = lines[i]
        local chan = ln.chan or { title = "·", color = { r = 200, g = 200, b = 200 } }
        local line = vgui.Create("DLabel", body)
        line:SetText(os.date("%H:%M", math.max(0, math.ceil(ln.t + shift))) ..
            "  [" .. (chan.title or "·") .. "]  " ..
            ((ln.name and #ln.name > 0) and (ln.name .. ": ") or "") .. (ln.text or ""))
        line:SetFont("GRMRP_Chat14")
        line:SetTextColor(Color(225, 238, 247))
        line:SetWrap(true)
        line:SetSelectable(true)
        line:SetWide(scroll:GetWide() - 24)
        line:SetPos(0, y)
        line:SizeToContents()
        local hh = math.max(18, line:GetTall())
        line:SetTall(hh)
        y = y + hh
    end
    body:SetTall(y + 4)
    timer.Simple(0.02, function()
        if IsValid(scroll) and IsValid(scroll.VBar) then
            scroll.VBar:SetY(scroll.VBar:GetCanvas():GetTall())
        end
    end)
    GRMRPChat.HIST_OPEN = true
end


local function setChannel(id)
    if not (GRMRPChat.GetChannel and GRMRPChat.GetChannel(id)) then return end
    selChan = id
    if IsValid(entry) and entry.updatePreview then entry:updatePreview() end
end

local function build()
    -- EditablePanel, не DFrame: у DFrame заголовок+поля съедали ~30 из 76 px,
    -- строка ввода схлопывалась в 0 и «уходила за нижний край» (скрин 03.09).
    frame = vgui.Create("EditablePanel")
    frame:SetSize(math.Clamp(ScrW() * 0.55, 460, 900), 66)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(5, 0, 0, w, h, Color(8, 14, 23, 242))
        surface.SetDrawColor(40, 62, 92, 110)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    frame.OnRemove = function()
        GRMRPChat.INPUT_OPEN = false
    end

    local preview = vgui.Create("DLabel", frame)
    preview:Dock(BOTTOM)
    preview:SetTall(16)
    preview:SetFont("GRMRP_Chat14")
    preview:SetTextColor(Color(132, 160, 178))
    preview:SetContentAlignment(4)
    frame.preview = preview

    local row = vgui.Create("DPanel", frame)
    row:Dock(TOP)
    row:SetTall(22)
    row:SetPaintBackground(false)

    chips = {}
    for _, ent in ipairs(channelsOrdered()) do
        local btn = vgui.Create("DButton", row)
        btn:SetText("")
        btn:Dock(LEFT)
        btn:DockMargin(3, 3, 0, 1)
        btn:SetWide(#ent.chan.title * 8 + 18)
        btn.chanId = ent.id
        local col = ent.chan.color
        btn.Paint = function(pp, w, h)
            local isSel = pp.chanId == selChan
            draw.RoundedBox(3, 0, 0, w, h, isSel and
                Color(col.r, col.g, col.b, 70) or Color(16, 27, 42, 220))
            draw.SimpleText(ent.chan.title, "GRMRP_ChatChip", w / 2, 3,
                isSel and color_white or Color(col.r, col.g, col.b, 200),
                TEXT_ALIGN_CENTER)
        end
        btn.DoClick = function(pp)
            setChannel(pp.chanId)
            if IsValid(entry) then entry:RequestFocus() end
        end
        table.insert(chips, btn)
    end

    local more = vgui.Create("DButton", row)
    more:SetText("")
    more:Dock(LEFT)
    more:DockMargin(3, 3, 0, 1)
    more:SetWide(70)
    more.Paint = function(pp, w, h)
        local ch = chanNow()
        draw.SimpleText(ch and ("в " .. ch.title) or "",
            "GRMRP_ChatChip", w / 2, 3, Color(132, 160, 178), TEXT_ALIGN_CENTER)
    end
    more.DoClick = function()
        local order = {}
        for _, e in ipairs(channelsOrdered()) do
            if e.id ~= "pm" then table.insert(order, e.id) end
        end
        for i = 1, #order do
            if order[i] == selChan then
                setChannel(order[i % #order + 1])
                break
            end
        end
        if IsValid(entry) then entry:RequestFocus() end
    end

    local hbtn = vgui.Create("DButton", row)
    hbtn:SetText("")
    hbtn:Dock(LEFT)
    hbtn:DockMargin(3, 3, 0, 1)
    hbtn:SetWide(64)
    hbtn.Paint = function(_, w, h)
        draw.SimpleText("история", "GRMRP_ChatChip", w / 2, 3,
            Color(132, 160, 178), TEXT_ALIGN_CENTER)
    end
    hbtn.DoClick = function()
        GRMRPChat.INPUT_OPEN = false
        if IsValid(frame) then frame:Hide() end
        toggleHistory()
    end

    -- 66 = 22 (чипы) + 28 (ввод) + 16 (превью): FILL ровно 28 px — поле
    -- ввода видимое и кликабельное целиком.
    entry = vgui.Create("DTextEntry", frame)
    entry:Dock(FILL)
    entry:SetFont("GRMRP_Chat14")
    entry.Paint = function(pp)
        surface.SetDrawColor(16, 27, 42, 235)
        surface.DrawRect(0, 0, pp:GetWide(), pp:GetTall())
        pp:DrawTextEntryText(Color(225, 238, 247), Color(48, 204, 255), Color(48, 204, 255))
        local chan = chanNow()
        if chan and #pp:GetValue() == 0 then
            draw.SimpleText(chan.title .. ": скажите…", "GRMRP_Chat14", 4, 5,
                Color(132, 160, 178, 160))
        end
    end

    local function updatePreview(pp)
        if not IsValid(preview) then return end
        if GRMRPChat.PreviewText then
            preview:SetText(GRMRPChat.PreviewText(LocalPlayer():Name(), pp:GetValue(), selChan))
        end
    end
    entry.updatePreview = updatePreview

    entry.OnTextChanged = function(pp)
        pp.tabIdx = nil
        updatePreview(pp)
    end

    local function doComplete(pp)
        local v = pp:GetValue()
        if v:lower():sub(1, 4) == "/pm " then
            local partial = string.lower(string.sub(v, 5))
            local cand = {}
            for _, tgt in ipairs(player.GetAll()) do
                if tgt ~= LocalPlayer() then
                    local n = tgt:Nick()
                    if string.lower(n):sub(1, #partial) == partial then
                        table.insert(cand, n)
                    end
                end
            end
            if #cand > 0 then
                table.sort(cand, function(a2, b2)
                    if #a2 == #b2 then return a2 < b2 end
                    return #a2 < #b2
                end)
                pp.tabIdx = (pp.tabIdx or 0) % #cand + 1
                pp:SetText("/pm " .. cand[pp.tabIdx])
            end
        elseif v:sub(1, 1) == "/" and #v > 1 then
            local low = v:lower()
            for _, c in ipairs(commands()) do
                if c:lower():sub(1, #low) == low then
                    pp:SetText(c)
                    break
                end
            end
        end
    end

    entry.OnEnter = function(pp)
        local v = string.Trim(pp:GetValue())
        pp:SetText("")
        if IsValid(preview) then preview:SetText("") end
        if #v == 0 then closeInput() return end
        if v:sub(1, 1) ~= "/" and selChan ~= "ic" then
            local chan = chanNow()
            if chan and chan.cmd then v = "/" .. chan.cmd .. " " .. v end
        end
        send(v)
        closeInput()
    end

    -- Enter порождает DTextEntry:OnEnter ВНУТРИ базового OnKeyCodeTyped.
    -- Прежний полный переопределитель проглотил его — «Enter ничего не
    -- делает» (скрин 03.09). Цепляем базу: себе — Tab/стрелки/Escape,
    -- остальное — базовой обработке (Enter, редактирование, вставка).
    local baseTyped = entry.OnKeyCodeTyped
    entry.OnKeyCodeTyped = function(pp, code)
        if code == KEY_ENTER or code == KEY_RETURN or
            (KEY_KP_ENTER and code == KEY_KP_ENTER) then
            pp:OnEnter(pp:GetValue()) -- явный Enter: не зависим от базы
            return true
        end
        if code == KEY_TAB then
            doComplete(pp)
            return true -- съедаем: иначе фокус упрыгивает на чипы
        elseif code == KEY_UP then
            if histIdx < #history then
                histIdx = histIdx + 1
                pp:SetText(history[#history - histIdx + 1])
                updatePreview(pp)
            end
            return true
        elseif code == KEY_DOWN then
            if histIdx > 1 then
                histIdx = histIdx - 1
                pp:SetText(history[#history - histIdx + 1])
            else
                histIdx = 0
                pp:SetText("")
            end
            updatePreview(pp)
            return true
        elseif code == KEY_ESCAPE then
            closeInput()
            return true
        end
        if baseTyped then return baseTyped(pp, code) end
    end
end

function GRMRPChat.OpenInput()
    if not (GRMRPChat.GetChannel and GRMRPChat.Sanitize) then
        -- ядро не загрузилось (битый install/ошибка файла) —Say тихо, но один раз
        -- в консоль: без ядра ввод рисовать нельзя, и молчание тут хуже ошибки.
        if not GRMRPChat._warned then
            GRMRPChat._warned = true
            GRMRP.ErrorNoHalt("чат: ядро не загружено — ввод отключён")
        end
        return
    end
    if not IsValid(frame) then build() end
    frame:Show()
    frame:SetPos(16, ScrH() - frame:GetTall() - 196)
    frame:MakePopup()
    GRMRPChat.INPUT_OPEN = true
    if IsValid(entry) then
        entry:RequestFocus()
        entry:SetValue(entry:GetValue() or "")
    end
end

hook.Add("OnScreenSizeChanged", "GRMRPChat_InputPos", function()
    if IsValid(frame) then
        frame:SetPos(16, ScrH() - frame:GetTall() - 196)
    end
end)
