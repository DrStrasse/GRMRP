-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: cl_grmrp_chat.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP модуль молча выключается
    целиком: чат режима — единственный владелец, дублей net-имён/cvar'ов/
    перехвата PlayerSay не возникает никогда.
]]
if SERVER then return end
if GRMRP and GRMRP.Version then return end

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
    for id, chan in pairs(GRMChat.Channels or {}) do
        if not chan.onlyDead then table.insert(list, { id = id, chan = chan }) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function commands()
    local out = { "/pm " }
    for _, chan in pairs(GRMChat.Channels or {}) do
        if chan.cmd then table.insert(out, "/" .. chan.cmd .. " ") end
    end
    table.sort(out)
    return out
end

local function send(text)
    text = GRMChat.Sanitize and GRMChat.Sanitize(text, 512) or text
    if #text == 0 then return end
    table.insert(history, text)
    if #history > 50 then table.remove(history, 1) end
    histIdx = 0

    -- локальный предпросмотр: своя строка печатается сразу; серверное
    -- состояние не меняется — молчаливый самообман исключён эхом «!»
    GRMChat.AddSelfLine(selChan, text)

    net.Start(GRMChat.Net.SAY)
        net.WriteString(selChan)
        net.WriteString(text)
    net.SendToServer()
end

local function closeInput()
    if IsValid(frame) then frame:Hide() end
    GRMChat.INPUT_OPEN = false
end

local function chanNow()
    return GRMChat.GetChannel and GRMChat.GetChannel(selChan)
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
        GRMChat.HIST_OPEN = false
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
    local lines = GRMChat.lines or {}
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
    GRMChat.HIST_OPEN = true
end


local function setChannel(id)
    if not (GRMChat.GetChannel and GRMChat.GetChannel(id)) then return end
    selChan = id
end

local function build()
    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:SetSizable(false)
    frame:SetSize(math.Clamp(ScrW() * 0.6, 460, 920), 56)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(8, 14, 23, 235))
    end
    frame.OnClose = function()
        GRMChat.INPUT_OPEN = false
    end

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
        btn.Paint = function(p, w, h)
            local isSel = p.chanId == selChan
            draw.RoundedBox(3, 0, 0, w, h, isSel and
                Color(col.r, col.g, col.b, 70) or Color(16, 27, 42, 220))
            draw.SimpleText(ent.chan.title, "GRMRP_ChatChip", w / 2, 3,
                isSel and color_white or Color(col.r, col.g, col.b, 200),
                TEXT_ALIGN_CENTER)
        end
        btn.DoClick = function(p) setChannel(p.chanId) end
        table.insert(chips, btn)
    end

    local more = vgui.Create("DButton", row)
    more:SetText("")
    more:Dock(LEFT)
    more:DockMargin(3, 3, 0, 1)
    more:SetWide(70)
    more.Paint = function(p, w, h)
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
        GRMChat.INPUT_OPEN = false
        if IsValid(frame) then frame:Hide() end
        toggleHistory()
    end

    entry = vgui.Create("DTextEntry", frame)
    entry:Dock(FILL)
    entry:SetFont("GRMRP_Chat14")
    if entry.SetHistoryDisabled then entry:SetHistoryDisabled(true) end
    entry.Paint = function(p)
        surface.SetDrawColor(16, 27, 42, 235)
        surface.DrawRect(0, 0, p:GetWide(), p:GetTall())
        p:DrawTextEntryText(Color(225, 238, 247), Color(48, 204, 255), Color(48, 204, 255))
        local chan = chanNow()
        if chan and #p:GetValue() == 0 then
            draw.SimpleText(chan.title .. ": скажите…", "GRMRP_Chat14", 4, 3,
                Color(132, 160, 178, 160))
        end
    end

    entry.OnTextChanged = function(p)
        p.tabIdx = nil
    end

    entry.OnEnter = function(p)
        local v = string.Trim(p:GetValue())
        p:SetText("")
        if #v == 0 then closeInput() return end
        if v:sub(1, 1) ~= "/" and selChan ~= "ic" then
            local chan = chanNow()
            if chan and chan.cmd then v = "/" .. chan.cmd .. " " .. v end
        end
        send(v)
        closeInput()
    end

    entry.OnKeyCodePressed = function(p, code)
        if code == KEY_UP then
            if histIdx < #history then
                histIdx = histIdx + 1
                p:SetText(history[#history - histIdx + 1])
            end
        elseif code == KEY_DOWN then
            if histIdx > 1 then
                histIdx = histIdx - 1
                p:SetText(history[#history - histIdx + 1])
            else
                histIdx = 0
                p:SetText("")
            end
        elseif code == KEY_TAB then
            local v = p:GetValue()
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
                    table.sort(cand, function(a2, b2) return #a2 < #b2 end)
                    p.tabIdx = (p.tabIdx or 0) % #cand + 1
                    p:SetText("/pm " .. cand[p.tabIdx])
                end
            elseif v:sub(1, 1) == "/" and #v > 1 then
                local low = v:lower()
                for _, c in ipairs(commands()) do
                    if c:lower():sub(1, #low) == low then
                        p:SetText(c)
                        break
                    end
                end
            end
        elseif code == KEY_ESCAPE then
            closeInput()
        end
    end
end

function GRMChat.OpenInput()
    if not (GRMChat.GetChannel and GRMChat.Sanitize) then
        -- ядро не загрузилось (битый install/ошибка файла) —Say тихо, но один раз
        -- в консоль: без ядра ввод рисовать нельзя, и молчание тут хуже ошибки.
        if not GRMChat._warned then
            GRMChat._warned = true
            GRMChat.ErrorNoHalt("чат: ядро не загружено — ввод отключён")
        end
        return
    end
    if not IsValid(frame) then build() end
    frame:Show()
    frame:SetPos(16, ScrH() - frame:GetTall() - 16)
    frame:MakePopup()
    GRMChat.INPUT_OPEN = true
    if IsValid(entry) then
        entry:RequestFocus()
        entry:SetValue(entry:GetValue() or "")
    end
end

hook.Add("OnScreenSizeChanged", "GRMChat_InputPos", function()
    if IsValid(frame) then
        frame:SetPos(16, ScrH() - frame:GetTall() - 16)
    end
end)

-- Y в песочнице: хук движковой клавиатуры + консольная команда для бинда.
hook.Add("HUDKeyPress", "GRMChat_Y", function(code, down, up, onlydown)
    if code == KEY_Y and GRMChat.Enabled and GRMChat.Enabled() then
        GRMChat.OpenInput()
        return true
    end
end)
concommand.Add("grm_chat_open", function()
    if GRMChat.OpenInput then GRMChat.OpenInput() end
end)
