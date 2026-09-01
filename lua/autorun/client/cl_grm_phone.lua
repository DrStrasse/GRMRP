--[[--------------------------------------------------------------------
    GRM Phone Lines — клиент, стиль фракционного центра (золотая шапка,
    тёмный корпус, карточки). Стационар, АТС, прослушка, терминал.
----------------------------------------------------------------------]]
if not CLIENT then return end

include("autorun/sh_grm_phone_config.lua")

GRM = GRM or {}
GRM.Phone = GRM.Phone or {}

local NET_OPEN_PHONE    = "GRM_Phone_OpenPhone"
local NET_OPEN_PBX      = "GRM_Phone_OpenPBX"
local NET_OPEN_WIRETAP  = "GRM_Phone_OpenWiretap"
local NET_OPEN_TERMINAL = "GRM_Phone_OpenTerminal"
local NET_ACTION        = "GRM_Phone_Action"
local NET_INFO          = "GRM_Phone_Info"
local NET_TEXT          = "GRM_Phone_Text"

local C = {
    bg         = Color(16, 20, 28, 252),
    sidebar    = Color(12, 15, 22, 255),
    card       = Color(22, 28, 38, 240),
    cardLight  = Color(28, 36, 48, 240),
    border     = Color(38, 48, 66, 200),
    accent     = Color(65, 145, 235),
    gold       = Color(245, 195, 65),
    green      = Color(55, 185, 110),
    red        = Color(225, 70, 70),
    teal       = Color(75, 195, 170),
    text       = Color(240, 244, 250),
    dim        = Color(155, 170, 190),
}

surface.CreateFont("GRMPhone_Title", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMPhone_Sub",   { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRMPhone_Body",  { font = "Roboto", size = 13, weight = 500, extended = true })

local function action(ent, name, writer)
    if not IsValid(ent) then return end
    net.Start(NET_ACTION)
        net.WriteString(name)
        net.WriteEntity(ent)
        if writer then writer() end
    net.SendToServer()
end

local function skinEntry(te)
    te:SetFont("GRMPhone_Body")
    te:SetTextColor(C.text)
    te.Paint = function(s, w, h)
        draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        s:DrawTextEntryText(C.text, C.accent, C.text)
    end
end

local function uiSound(kind)
    local path = kind == "hover" and "garrysmod/ui_hover.wav"
        or kind == "down" and "ui/buttonclick.wav"
        or kind == "up" and "ui/buttonclickrelease.wav"
        or "buttons/button15.wav"
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path, 0.04) else surface.PlaySound(path) end
end

local function btn(parent, text, color)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetCursor("hand")
    b._press = 0
    b._hov = 0
    b.OnCursorEntered = function(s)
        s._wasHover = true
        uiSound("hover")
    end
    b.OnDepressed = function() uiSound("down") end
    b.OnReleased = function() uiSound("up") end
    b.Paint = function(s, w, h)
        local dt = FrameTime() * 14
        s._hov = Lerp(dt, s._hov or 0, s:IsHovered() and 1 or 0)
        s._press = Lerp(dt, s._press or 0, s:IsDown() and 1 or 0)
        local c = color or C.accent
        local lift = 18 * s._hov
        c = Color(
            math.min(255, c.r + lift),
            math.min(255, c.g + lift),
            math.min(255, c.b + lift)
        )
        local inset = math.floor(s._press * 2)
        draw.RoundedBox(6, inset, inset + 1, w - inset * 2, h - inset * 2, Color(0, 0, 0, 70))
        draw.RoundedBox(6, inset, inset, w - inset * 2, h - inset * 2, c)
        surface.SetDrawColor(255, 255, 255, 18 + s._hov * 28)
        surface.DrawOutlinedRect(inset, inset, w - inset * 2, h - inset * 2)
        draw.SimpleText(text, "GRMPhone_Sub", w / 2, h / 2 + inset, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function paintFrame(title, sub)
    return function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, C.sidebar, true, true, false, false)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(title, "GRMPhone_Title", 16, 16, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if sub and sub ~= "" then
            draw.SimpleText(sub, "GRMPhone_Body", 16, 34, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end

local function closeX(f)
    local x = vgui.Create("DButton", f)
    x:SetSize(32, 28) x:SetText("")
    x.Paint = function(s, w, h)
        if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end
        draw.SimpleText("✕", "GRMPhone_Sub", w / 2, h / 2, s:IsHovered() and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    x.DoClick = function() f:Close() end
    f.PerformLayout = function(self, w) if IsValid(x) then x:SetPos(w - 40, 9) end end
end

net.Receive(NET_INFO, function()
    local msg = net.ReadString()
    local bad = net.ReadBool()
    chat.AddText(bad and C.red or C.accent, "[Телефон] ", C.text, msg)
    surface.PlaySound(bad and "buttons/button10.wav" or "buttons/button17.wav")
end)

local NET_SYNC_PH = "GRM_Phone_Sync"
net.Receive(NET_SYNC_PH, function()
    local ent = net.ReadEntity()
    local class = net.ReadString()
    if not IsValid(ent) then return end
    local rec = { class = class }
    local ok = pcall(function()
        if class == "grm_phone" or class == "grm_payphone" then
            rec.number = net.ReadString()
            rec.displayName = net.ReadString()
            rec.exchange = net.ReadString()
            rec.lineState = net.ReadString()
            rec.callId = net.ReadUInt(16)
        elseif class == "grm_pbx_station" then
            rec.exchange = net.ReadString()
            rec.active = net.ReadBool()
            rec.maxLines = net.ReadUInt(12)
        elseif class == "grm_phone_wiretap" then
            rec.targetNumber = net.ReadString()
            rec.exchange = net.ReadString()
            rec.active = net.ReadBool()
        end
    end)
    if not ok then return end
    GRM.Phone._syncCache = GRM.Phone._syncCache or {}
    GRM.Phone._syncCache[ent] = rec
end)

net.Receive(NET_TEXT, function()
    local speaker = net.ReadEntity()
    local callID = net.ReadUInt(16)
    local fromNumber = net.ReadString()
    local toNumber = net.ReadString()
    local msg = net.ReadString()
    local intercepted = net.ReadBool()
    local name = IsValid(speaker) and speaker:Nick() or "Неизвестно"
    if intercepted then
        chat.AddText(C.gold, "[ПРОСЛУШКА #" .. callID .. " " .. fromNumber .. "↔" .. toNumber .. "] ", C.accent, name, C.text, ": " .. msg)
    else
        chat.AddText(C.accent, "[ТЕЛЕФОН #" .. callID .. " " .. fromNumber .. "↔" .. toNumber .. "] ", C.teal, name, C.text, ": " .. msg)
    end
    surface.PlaySound("buttons/button17.wav")
end)

net.Receive(NET_OPEN_PHONE, function()
    local ent = net.ReadEntity()
    local number = net.ReadString()
    local name = net.ReadString()
    local exchange = net.ReadString()
    local state = net.ReadString()
    local callID = net.ReadUInt(16)

    local f = vgui.Create("DFrame")
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("phone", f) end
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetSize(420, 360)
    f:Center()
    f:MakePopup()
    f.Paint = paintFrame("СТАЦИОНАРНЫЙ ТЕЛЕФОН", name .. "  ·  № " .. number .. "  ·  АТС " .. exchange)
    closeX(f)

    local st = vgui.Create("DPanel", f)
    st:SetPos(16, 58) st:SetSize(388, 36)
    st.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("Статус: " .. state .. (callID > 0 and ("  ·  вызов #" .. callID) or ""),
            "GRMPhone_Body", 12, h / 2, C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local dial = vgui.Create("DTextEntry", f)
    dial:SetPos(16, 106) dial:SetSize(388, 32)
    dial:SetPlaceholderText("Номер телефона")
    dial:SetNumeric(true)
    skinEntry(dial)

    local dialBtn = btn(f, "Позвонить", C.green)
    dialBtn:SetPos(16, 150); dialBtn:SetSize(188, 36)
    dialBtn.DoClick = function()
        action(ent, "phone_dial", function() net.WriteString(dial:GetText()) end)
    end

    local answerBtn = btn(f, "Ответить", C.accent)
    answerBtn:SetPos(216, 150); answerBtn:SetSize(188, 36)
    answerBtn.DoClick = function() action(ent, "phone_answer") end

    local pickupBtn = btn(f, "Взять трубку", C.teal)
    pickupBtn:SetPos(16, 196); pickupBtn:SetSize(188, 36)
    pickupBtn.DoClick = function() action(ent, "phone_pickup") end

    local releaseBtn = btn(f, "Положить трубку", C.cardLight)
    releaseBtn:SetPos(216, 196); releaseBtn:SetSize(188, 36)
    releaseBtn.DoClick = function() action(ent, "phone_release") end

    local hangBtn = btn(f, "Завершить вызов", C.red)
    hangBtn:SetPos(16, 248); hangBtn:SetSize(388, 42)
    hangBtn.DoClick = function() action(ent, "phone_hangup") end

    local hint = vgui.Create("DLabel", f)
    hint:SetPos(16, 300) hint:SetSize(388, 40)
    hint:SetFont("GRMPhone_Body") hint:SetTextColor(C.dim)
    hint:SetWrap(true)
    hint:SetText("Мобильный: стрелка вверх (после «Использовать» в инвентаре). Прослушка — отдельный блок на линии.")
end)

net.Receive(NET_OPEN_PBX, function()
    local ent = net.ReadEntity()
    local exchange = net.ReadString()
    local active = net.ReadBool()
    local maxLines = net.ReadUInt(12)

    local f = vgui.Create("DFrame")
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("phone_pbx", f) end
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetSize(420, 280)
    f:Center() f:MakePopup()
    f.Paint = paintFrame("АТС / УЗЕЛ СВЯЗИ", "Линии станции и идентификатор обмена")
    closeX(f)

    local entry = vgui.Create("DTextEntry", f)
    entry:SetPos(16, 64); entry:SetSize(388, 32); entry:SetText(exchange)
    skinEntry(entry)

    local check = vgui.Create("DCheckBoxLabel", f)
    check:SetPos(16, 108); check:SetSize(300, 24)
    check:SetText("АТС активна")
    check:SetTextColor(C.text)
    check:SetFont("GRMPhone_Body")
    check:SetValue(active)

    local lbl = vgui.Create("DLabel", f)
    lbl:SetPos(16, 144); lbl:SetSize(180, 20)
    lbl:SetFont("GRMPhone_Body") lbl:SetTextColor(C.dim)
    lbl:SetText("Количество линий:")

    local lines = vgui.Create("DNumberWang", f)
    lines:SetPos(170, 140); lines:SetSize(100, 28)
    lines:SetMin(1); lines:SetMax(4095)
    lines:SetValue(maxLines > 0 and maxLines or 60)

    local hint = vgui.Create("DLabel", f)
    hint:SetPos(16, 178); hint:SetSize(388, 22)
    hint:SetFont("GRMPhone_Body") hint:SetTextColor(C.dim)
    hint:SetText("Обычно 50–70 линий на станцию.")

    local save = btn(f, "Сохранить", C.green)
    save:SetPos(16, 214); save:SetSize(388, 38)
    save.DoClick = function()
        action(ent, "pbx_set", function()
            net.WriteString(entry:GetText())
            net.WriteBool(check:GetChecked())
            net.WriteUInt(math.Clamp(tonumber(lines:GetValue()) or 60, 1, 4095), 12)
        end)
        f:Close()
    end
end)

net.Receive(NET_OPEN_WIRETAP, function()
    local ent = net.ReadEntity()
    local target = net.ReadString()
    local exchange = net.ReadString()
    local active = net.ReadBool()

    local f = vgui.Create("DFrame")
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("phone_wiretap", f) end
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetSize(440, 300)
    f:Center() f:MakePopup()
    f.Paint = paintFrame("ПРОСЛУШКА ЛИНИИ", "Целевой номер и АТС. Запись уходит в чат оператору.")
    closeX(f)

    local targetEntry = vgui.Create("DTextEntry", f)
    targetEntry:SetPos(16, 64); targetEntry:SetSize(408, 32)
    targetEntry:SetPlaceholderText("Целевой номер, например 1001")
    targetEntry:SetText(target)
    skinEntry(targetEntry)

    local exchangeEntry = vgui.Create("DTextEntry", f)
    exchangeEntry:SetPos(16, 106); exchangeEntry:SetSize(408, 32)
    exchangeEntry:SetPlaceholderText("АТС, например main")
    exchangeEntry:SetText(exchange)
    skinEntry(exchangeEntry)

    local check = vgui.Create("DCheckBoxLabel", f)
    check:SetPos(16, 150); check:SetSize(300, 24)
    check:SetText("Прослушка активна")
    check:SetTextColor(C.text)
    check:SetFont("GRMPhone_Body")
    check:SetValue(active)

    local save = btn(f, "Сохранить", C.green)
    save:SetPos(16, 188); save:SetSize(200, 36)
    save.DoClick = function()
        action(ent, "wiretap_set", function()
            net.WriteString(targetEntry:GetText())
            net.WriteString(exchangeEntry:GetText())
            net.WriteBool(check:GetChecked())
        end)
    end

    local mon = btn(f, "Слушать", C.accent)
    mon:SetPos(224, 188); mon:SetSize(200, 36)
    mon.DoClick = function() action(ent, "wiretap_monitor") end

    local stop = btn(f, "Остановить прослушку", C.red)
    stop:SetPos(16, 236); stop:SetSize(408, 36)
    stop.DoClick = function() action(ent, "wiretap_stop") end
end)

net.Receive(NET_OPEN_TERMINAL, function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or { phones = {}, exchanges = {}, calls = {} }

    local f = vgui.Create("DFrame")
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("phone_terminal", f) end
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetSize(820, 580)
    f:Center()
    f:MakePopup()
    f.Paint = paintFrame("МОНИТОРИНГ СВЯЗИ", "Телефоны, АТС и живые линии")
    closeX(f)

    local tabs = vgui.Create("DPropertySheet", f)
    tabs:Dock(FILL)
    tabs:DockMargin(10, 52, 10, 52)
    tabs.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.sidebar) end

    local function makeList(parent, columns)
        local list = vgui.Create("DListView", parent)
        list:Dock(FILL)
        list:SetPaintBackground(false)
        list:SetHeaderHeight(28)
        list:SetDataHeight(24)
        for _, col in ipairs(columns) do list:AddColumn(col) end
        return list
    end

    local phonesPanel = vgui.Create("DPanel")
    phonesPanel:SetPaintBackground(false)
    local phonesList = makeList(phonesPanel, { "Номер", "Имя", "АТС", "Статус", "CallID", "Тип" })
    for _, row in ipairs(data.phones or {}) do
        phonesList:AddLine(row.number or "", row.name or "", row.exchange or "", row.state or "", row.callID or 0, row.class or "")
    end
    tabs:AddSheet("Телефоны", phonesPanel, "icon16/telephone.png")

    local exPanel = vgui.Create("DPanel")
    exPanel:SetPaintBackground(false)
    local exList = makeList(exPanel, { "АТС", "Активна", "Занято", "Всего", "Свободно" })
    for _, row in ipairs(data.exchanges or {}) do
        exList:AddLine(row.exchange or "", row.active and "Да" or "Нет", row.used or 0, row.max or 0, math.max((row.max or 0) - (row.used or 0), 0))
    end
    tabs:AddSheet("АТС / линии", exPanel, "icon16/server.png")

    local callsPanel = vgui.Create("DPanel")
    callsPanel:SetPaintBackground(false)
    local callsList = makeList(callsPanel, { "ID", "От", "Кому", "АТС от", "АТС кому", "Ответ", "Возраст" })
    for _, row in ipairs(data.calls or {}) do
        callsList:AddLine(row.id or 0, row.from or "", row.to or "", row.fromExchange or "", row.toExchange or "", row.answered and "Да" or "Нет", row.age or 0)
    end
    tabs:AddSheet("Активные линии", callsPanel, "icon16/connect.png")

    local refresh = btn(f, "Обновить", C.accent)
    refresh:Dock(BOTTOM) refresh:DockMargin(10, 0, 10, 10) refresh:SetTall(34)
    refresh.DoClick = function()
        action(ent, "terminal_refresh")
        f:Close()
    end
end)

print("[GRM Phone] Client loaded (GRM style)")
