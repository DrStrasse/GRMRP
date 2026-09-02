--[[ GRMRPChat ввод: полоса с чипами каналов, история (↑/↓), Tab-дополнение
    команд. Модель textentryx из EasyChat (4.21.4) в нативном Derma-виде,
    без DHTML. Enter при пустом поле закрывает окно (§5.7).
]]

if SERVER then return end

local history = {}
local histIdx = 0
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
    text = GRMRPChat.Sanitize and GRMRPChat.Sanitize(text, 512) or text
    if #text == 0 then return end
    table.insert(history, text)
    if #history > 50 then table.remove(history, 1) end
    histIdx = 0

    -- локальный предпросмотр: своя строка печатается сразу; серверное
    -- состояние не меняется — молчаливый самообман исключён эхом «!»
    GRMRPChat.AddSelfLine(selChan, text)

    net.Start(GRMRP.Net.SAY)
        net.WriteString(selChan)
        net.WriteString(text)
    net.SendToServer()
end

local function closeInput()
    if IsValid(frame) then frame:Hide() end
    GRMRPChat.INPUT_OPEN = false
end

local function setChannel(id)
    if not GRMRPChat.GetChannel(id) then return end
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
        GRMRPChat.INPUT_OPEN = false
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
        draw.SimpleText(GRMRPChat.GetChannel(selChan) and
            ("в " .. GRMRPChat.GetChannel(selChan).title) or "",
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

    entry = vgui.Create("DTextEntry", frame)
    entry:Dock(FILL)
    entry:SetFont("GRMRP_Chat14")
    if entry.SetHistoryDisabled then entry:SetHistoryDisabled(true) end
    entry.Paint = function(p)
        surface.SetDrawColor(16, 27, 42, 235)
        surface.DrawRect(0, 0, p:GetWide(), p:GetTall())
        p:DrawTextEntryText(Color(225, 238, 247), Color(48, 204, 255), Color(48, 204, 255))
        local chan = GRMRPChat.GetChannel(selChan)
        if chan and #p:GetValue() == 0 then
            draw.SimpleText(chan.title .. ": скажите…", "GRMRP_Chat14", 4, 3,
                Color(132, 160, 178, 160))
        end
    end

    entry.OnEnter = function(p)
        local v = string.Trim(p:GetValue())
        p:SetText("")
        if #v == 0 then closeInput() return end
        if v:sub(1, 1) ~= "/" and selChan ~= "ic" then
            local chan = GRMRPChat.GetChannel(selChan)
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
            if v:sub(1, 1) == "/" and #v > 1 then
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

function GRMRPChat.OpenInput()
    if not IsValid(frame) then build() end
    frame:Show()
    frame:SetPos(16, ScrH() - frame:GetTall() - 16)
    frame:MakePopup()
    GRMRPChat.INPUT_OPEN = true
    if IsValid(entry) then
        entry:RequestFocus()
        entry:SetValue(entry:GetValue() or "")
    end
end

hook.Add("OnScreenSizeChanged", "GRMRPChat_InputPos", function()
    if IsValid(frame) then
        frame:SetPos(16, ScrH() - frame:GetTall() - 16)
    end
end)
