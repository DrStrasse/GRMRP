--[[--------------------------------------------------------------------
    GRM Alarm — client UI (Код 63)
----------------------------------------------------------------------]]

if not CLIENT then return end
include("autorun/sh_grm_alarm_config.lua")

GRM = GRM or {}
GRM.Alarm = GRM.Alarm or {}
local A = GRM.Alarm

local NET_OPEN_DEV = "GRM_Alarm_OpenDev"
local NET_OPEN_TRM = "GRM_Alarm_OpenTrm"
local NET_ACT      = "GRM_Alarm_Act"
local NET_NOTIFY   = "GRM_Alarm_Notify"

local THEME = {
    bg = Color(20, 24, 30, 250),
    panel = Color(30, 36, 46, 245),
    text = Color(230, 235, 242),
    dim = Color(150, 160, 175),
    green = Color(70, 180, 110),
    accent = Color(70, 140, 220),
    yellow = Color(220, 180, 70),
    red = Color(220, 70, 70),
}

surface.CreateFont("GRMAlarm_Title", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRMAlarm_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMAlarm_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

local function act(tbl)
    net.Start(NET_ACT)
        net.WriteTable(tbl or {})
    net.SendToServer()
end

local function btn(parent, text, col, w, h)
    local b = vgui.Create("DButton", parent)
    b:SetSize(w or 140, h or 28)
    b:SetText(text)
    b:SetFont("GRMAlarm_Normal")
    b:SetTextColor(color_white)
    b.Paint = function(self, ww, hh)
        local c = col or THEME.accent
        if self:IsHovered() then c = Color(math.min(255, c.r + 20), math.min(255, c.g + 20), math.min(255, c.b + 20)) end
        draw.RoundedBox(6, 0, 0, ww, hh, c)
    end
    return b
end

net.Receive(NET_NOTIFY, function()
    local ok = net.ReadBool()
    local msg = net.ReadString()
    chat.AddText(ok and THEME.green or THEME.red, "[Сигнализация] ", color_white, msg)
end)

-- Device config (sensor / hub)
net.Receive(NET_OPEN_DEV, function()
    local ent = net.ReadEntity()
    local kind = net.ReadString()
    local netID = net.ReadString()
    if not IsValid(ent) then return end

    if IsValid(A._devFrame) then A._devFrame:Remove() end
    local f = vgui.Create("DFrame")
    A._devFrame = f
    f:SetTitle("")
    f:SetSize(420, kind == "hub" and 300 or 280)
    f:Center()
    f:MakePopup()
    f.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
        local title = kind == "hub" and "Блок коммутации"
            or kind == "speaker" and "Динамик сирены" or "Датчик движения"
        draw.SimpleText(title,
            "GRMAlarm_Title", 12, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local y = 48
    local function lab(t)
        local l = vgui.Create("DLabel", f)
        l:SetPos(16, y) l:SetSize(380, 18)
        l:SetText(t) l:SetFont("GRMAlarm_Normal") l:SetTextColor(THEME.text)
        y = y + 20
    end

    lab("Подпись:")
    local label = vgui.Create("DTextEntry", f)
    label:SetPos(16, y) label:SetSize(280, 24)
    label:SetText(ent:GetLabel() or "")
    y = y + 32

    lab("Сеть (NetworkID):")
    local network = vgui.Create("DTextEntry", f)
    network:SetPos(16, y) network:SetSize(200, 24)
    network:SetText(netID or "main")
    y = y + 32

    local radius, active, mode, speakerActive
    if kind == "sensor" or ent:GetClass() == "grm_alarm_sensor" then
        local r = net.ReadUInt(16)
        local on = net.ReadBool()
        lab("Радиус датчика:")
        radius = vgui.Create("DNumberWang", f)
        radius:SetPos(16, y) radius:SetSize(100, 24)
        radius:SetMin(64) radius:SetMax(800) radius:SetValue(r > 0 and r or 220)
        y = y + 28
        active = vgui.Create("DCheckBoxLabel", f)
        active:SetPos(16, y) active:SetText("Датчик активен")
        active:SetTextColor(THEME.text) active:SetValue(on and 1 or 0)
        y = y + 28
    elseif kind == "speaker" then
        -- Код 89: динамик сирены — без режима, только Active
        net.ReadUInt(3)
        local on = net.ReadBool()
        net.ReadUInt(8)
        lab("Воет сиреной, пока активна тревога в его сети.")
        speakerActive = vgui.Create("DCheckBoxLabel", f)
        speakerActive:SetPos(16, y) speakerActive:SetText("Динамик включён")
        speakerActive:SetTextColor(THEME.text) speakerActive:SetValue(on and 1 or 0)
        y = y + 28
    else
        local m = net.ReadUInt(3)
        local alarm = net.ReadBool()
        local sc = net.ReadUInt(8)
        lab("Датчиков в сети: " .. tostring(sc) .. (alarm and "  |  ТРЕВОГА" or ""))
        lab("Режим блока:")
        mode = vgui.Create("DComboBox", f)
        mode:SetPos(16, y) mode:SetSize(260, 24)
        mode:AddChoice("1 — Выключено", 1)
        mode:AddChoice("2 — Под охраной", 2)
        mode:AddChoice("3 — Пассивный контроль", 3)
        mode:ChooseOptionID(math.Clamp(m, 1, 3))
        y = y + 36
    end

    local save = btn(f, "Сохранить", THEME.green, 120, 28)
    save:SetPos(16, f:GetTall() - 40)
    save.DoClick = function()
        act({ action = "set_label", entIndex = ent:EntIndex(), label = label:GetValue() })
        act({ action = "set_network", entIndex = ent:EntIndex(), network = network:GetValue() })
        if IsValid(radius) then
            act({
                action = "set_sensor",
                entIndex = ent:EntIndex(),
                radius = radius:GetValue(),
                active = active:GetChecked(),
            })
        end
        if IsValid(mode) then
            local _, m = mode:GetSelected()
            act({ action = "set_mode", network = network:GetValue(), mode = m or 1, entIndex = ent:EntIndex() })
        end
        if IsValid(speakerActive) then
            act({ action = "set_speaker", entIndex = ent:EntIndex(), active = speakerActive:GetChecked() })
        end
        f:Close()
    end

    if LocalPlayer():IsSuperAdmin() then
        local perm = btn(f, "Permanent", THEME.yellow, 110, 28)
        perm:SetPos(150, f:GetTall() - 40)
        perm.DoClick = function()
            act({ action = "set_permanent", entIndex = ent:EntIndex(), permanent = true })
        end
    end
end)

-- Terminal
net.Receive(NET_OPEN_TRM, function()
    local ent = net.ReadEntity()
    local netID = net.ReadString()
    local mode = net.ReadUInt(3)
    local alarm = net.ReadBool()
    local canCtrl = net.ReadBool()
    local hasHub = net.ReadBool()
    local spkCount = net.ReadUInt(8) -- Код 89
    local sensors = net.ReadTable() or {}
    local logs = net.ReadTable() or {}
    if not IsValid(ent) then return end

    if IsValid(A._trmFrame) then A._trmFrame:Remove() end
    local f = vgui.Create("DFrame")
    A._trmFrame = f
    f:SetTitle("")
    f:SetSize(720, 560)
    f:Center()
    f:MakePopup()
    f.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 36, Color(34, 40, 52), true, true, false, false)
        draw.SimpleText("Терминал охраны — сеть «" .. netID .. "»", "GRMAlarm_Title", 12, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local status = vgui.Create("DLabel", f)
    status:SetPos(12, 44)
    status:SetSize(690, 22)
    status:SetFont("GRMAlarm_Normal")
    local modeName = A.ModeName and A.ModeName(mode) or tostring(mode)
    local stCol = alarm and THEME.red or (A.ModeColors and A.ModeColors[mode]) or THEME.text
    status:SetTextColor(stCol)
    if not hasHub then
        status:SetText("Нет блока коммутации в этой сети — поставьте grm_alarm_hub" ..
            (spkCount > 0 and ("  |  динамиков: " .. tostring(spkCount)) or ""))
        status:SetTextColor(THEME.yellow)
    else
        status:SetText((alarm and "⚠ ТРЕВОГА  |  " or "") .. "Режим: " .. modeName ..
            "  |  датчиков: " .. tostring(#sensors) .. "  |  динамиков: " .. tostring(spkCount))
    end

    local sheet = vgui.Create("DPropertySheet", f)
    sheet:Dock(FILL)
    sheet:DockMargin(8, 72, 8, 8)

    -- Control
    do
        local p = vgui.Create("DPanel")
        p:SetPaintBackground(false)
        if canCtrl then
            local function modeBtn(title, m, col, x)
                local b = btn(p, title, col, 200, 36)
                b:SetPos(x, 20)
                b.DoClick = function()
                    act({ action = "set_mode", network = netID, mode = m, entIndex = ent:EntIndex() })
                    timer.Simple(0.15, function()
                        if IsValid(ent) then act({ action = "refresh_terminal", entIndex = ent:EntIndex() }) end
                    end)
                end
            end
            modeBtn("1. Выключено", 1, Color(100, 100, 110), 20)
            modeBtn("2. Под охраной", 2, THEME.green, 240)
            modeBtn("3. Пассивный контроль", 3, THEME.accent, 460)

            local reset = btn(p, "Сбросить тревогу / сирену", THEME.red, 260, 34)
            reset:SetPos(20, 80)
            reset.DoClick = function()
                act({ action = "reset_alarm", network = netID, entIndex = ent:EntIndex() })
                timer.Simple(0.15, function()
                    if IsValid(ent) then act({ action = "refresh_terminal", entIndex = ent:EntIndex() }) end
                end)
            end

            -- Код 89: строка сети терминала (раньше менялась только из меню устройства)
            local netLab = vgui.Create("DLabel", p)
            netLab:SetPos(20, 126) netLab:SetSize(400, 18)
            netLab:SetFont("GRMAlarm_Normal") netLab:SetTextColor(THEME.text)
            netLab:SetText("Сеть терминала (NetworkID):")
            local netBox = vgui.Create("DTextEntry", p)
            netBox:SetPos(20, 146) netBox:SetSize(220, 24)
            netBox:SetText(netID)
            local netBtn = btn(p, "Применить сеть", THEME.accent, 160, 24)
            netBtn:SetPos(252, 146)
            netBtn.DoClick = function()
                act({ action = "set_network", entIndex = ent:EntIndex(), network = netBox:GetValue() })
                timer.Simple(0.15, function()
                    if IsValid(ent) then act({ action = "refresh_terminal", entIndex = ent:EntIndex() }) end
                end)
            end

            local help = vgui.Create("DLabel", p)
            help:SetPos(20, 190)
            help:SetSize(660, 120)
            help:SetWrap(true)
            help:SetFont("GRMAlarm_Small")
            help:SetTextColor(THEME.dim)
            help:SetText(
                "Выключено — датчики молчат.\n" ..
                "Под охраной — движение → лог + сирена (combine_bank_alarm) из блока и всех динамиков сети.\n" ..
                "Пассивный контроль — только лог движения, без сирены.\n" ..
                "Блок коммутации обязателен в сети. Датчики, динамики и терминал — тот же NetworkID."
            )
        else
            local l = vgui.Create("DLabel", p)
            l:SetPos(20, 20)
            l:SetSize(600, 40)
            l:SetText("Только просмотр. Управление режимами недоступно.")
            l:SetTextColor(THEME.yellow)
        end
        sheet:AddSheet("Управление", p, "icon16/shield.png")
    end

    -- Sensors
    do
        local p = vgui.Create("DPanel")
        p:SetPaintBackground(false)
        local lv = vgui.Create("DListView", p)
        lv:Dock(FILL)
        lv:DockMargin(6, 6, 6, 6)
        lv:AddColumn("Метка")
        lv:AddColumn("ID")
        lv:AddColumn("R"):SetFixedWidth(50)
        lv:AddColumn("Активен"):SetFixedWidth(70)
        for _, s in ipairs(sensors) do
            lv:AddLine(tostring(s.label), tostring(s.id), tostring(s.radius), s.active and "да" or "нет")
        end
        sheet:AddSheet("Датчики", p, "icon16/transmit.png")
    end

    -- Logs
    do
        local p = vgui.Create("DPanel")
        p:SetPaintBackground(false)
        local scroll = vgui.Create("DScrollPanel", p)
        scroll:Dock(FILL)
        scroll:DockMargin(6, 6, 6, 6)
        for _, e in ipairs(logs) do
            local l = vgui.Create("DLabel", scroll)
            l:Dock(TOP)
            l:SetTall(18)
            l:DockMargin(4, 1, 4, 1)
            l:SetFont("GRMAlarm_Small")
            local col = THEME.dim
            if e.kind == "alarm" then col = THEME.red
            elseif e.kind == "motion" then col = THEME.yellow
            elseif e.kind == "mode" then col = THEME.accent end
            l:SetTextColor(col)
            l:SetText(os.date("%H:%M:%S", e.t or 0) .. " [" .. tostring(e.kind) .. "] " .. tostring(e.text))
        end
        sheet:AddSheet("Журнал", p, "icon16/page_white_text.png")
    end

    local ref = btn(f, "Обновить", THEME.accent, 100, 24)
    ref:SetPos(f:GetWide() - 120, 6)
    ref.DoClick = function()
        act({ action = "refresh_terminal", entIndex = ent:EntIndex() })
    end
end)

print("[GRM Alarm] client v1.0.0")
