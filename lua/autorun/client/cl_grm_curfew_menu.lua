--[[--------------------------------------------------------------------
    GRM Curfew Menu v1.0.0 — меню комендантского часа (клиент)

    Открывается командой `/kom_hour` (или `/комчас`) без аргументов, а также
    консольной `grm_curfew`. Старые формы `/kom_hour 555` и `/kom_hour off`
    продолжают работать.

    Принципы (заказ владельца — «фикшенно, оптимизированно, без багов»):
      * Клиент НИЧЕГО не решает сам. Состояние и флаг доступа приходят с
        сервера; сервер повторно проверяет доступ и состояние на каждое
        действие. Кнопка «Остановить» активна только при идущем ком.часе,
        «Объявить» — только когда его нет.
      * Меню не опрашивает сервер по таймеру: сервер сам присылает свежее
        состояние всем, у кого меню открыто, как только оно меняется.
      * Обратный отсчёт считается локально от endTime — без сетевого трафика
        и без пересборки панелей в кадре.
      * Перерисовка — только Paint по готовым числам; ничего не создаётся и
        не форматируется каждый кадр (строка таймера пересобирается раз в
        секунду).
----------------------------------------------------------------------]]

if SERVER then return end

GRM = GRM or {}
GRM.Curfew = GRM.Curfew or {}
local CF = GRM.Curfew
CF.Version = "1.0.0"

local NET_MENU = "GRM_Curfew_Menu"
local NET_ACT  = "GRM_Curfew_Act"

surface.CreateFont("GRMCurfew_Title",  { font = "Roboto", size = 22, weight = 800, extended = true })
surface.CreateFont("GRMCurfew_Head",   { font = "Roboto", size = 17, weight = 700, extended = true })
surface.CreateFont("GRMCurfew_Body",   { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("GRMCurfew_Small",  { font = "Roboto", size = 13, weight = 400, extended = true })
surface.CreateFont("GRMCurfew_Timer",  { font = "Roboto", size = 40, weight = 800, extended = true })

-- Палитра GRM (та же, что в остальных меню сборки).
local C = {
    bg     = Color(16, 20, 28, 252),
    head   = Color(12, 15, 22, 255),
    card   = Color(22, 28, 38, 245),
    cardH  = Color(30, 38, 52, 245),
    border = Color(38, 48, 66, 200),
    acc    = Color(65, 145, 235),
    green  = Color(55, 185, 110),
    gold   = Color(245, 195, 65),
    red    = Color(225, 70, 70),
    redDim = Color(120, 40, 45),
    text   = Color(240, 244, 250),
    dim    = Color(155, 170, 190),
    off    = Color(58, 66, 80),
}

CF.State = CF.State or {
    canControl = false, active = false, endTime = 0, startedAt = 0,
    startedBy = "", faction = "", reason = "", minMinutes = 1, maxMinutes = 120,
}

local frame

local function click(path)
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path or "buttons/button15.wav")
    else surface.PlaySound(path or "buttons/button15.wav") end
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- Кнопка в стиле GRM с поддержкой «выключена».
local function mkButton(parent, label, baseCol, onClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Enabled = true
    b.Label = label
    b.Hint = ""
    b.Paint = function(s, w, h)
        local col = s.Enabled and (s:IsHovered() and Color(
            math.min(255, baseCol.r + 25), math.min(255, baseCol.g + 25), math.min(255, baseCol.b + 25)) or baseCol) or C.off
        draw.RoundedBox(6, 0, 0, w, h, col)
        surface.SetDrawColor(255, 255, 255, s.Enabled and 30 or 12)
        surface.DrawOutlinedRect(0, 0, w, h)
        local ty = s.Hint ~= "" and (h / 2 - 9) or (h / 2)
        draw.SimpleText(s.Label, "GRMCurfew_Head", w / 2, ty,
            s.Enabled and color_white or Color(140, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if s.Hint ~= "" then
            draw.SimpleText(s.Hint, "GRMCurfew_Small", w / 2, h / 2 + 12,
                s.Enabled and Color(235, 240, 250, 190) or Color(120, 130, 145), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    b.DoClick = function(s)
        if not s.Enabled then
            click("buttons/button10.wav")
            return
        end
        click()
        onClick(s)
    end
    return b
end

function CF.RequestState()
    net.Start(NET_MENU)
    net.SendToServer()
end

local function sendAct(act, minutes, reason)
    net.Start(NET_ACT)
        net.WriteString(tostring(act))
        net.WriteUInt(math.Clamp(math.floor(tonumber(minutes) or 10), 0, 255), 8)
        net.WriteString(string.sub(tostring(reason or ""), 1, 140))
    net.SendToServer()
end

function CF.Open()
    if IsValid(frame) then
        frame:MakePopup()
        CF.RequestState()
        return
    end

    frame = vgui.Create("DFrame")
    frame:SetSize(560, 560)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame:SetDeleteOnClose(true)
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("curfew.menu", frame) end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 52, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("КОМЕНДАНТСКИЙ ЧАС", "GRMCurfew_Title", 18, 26, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Городской режим ограничения передвижения", "GRMCurfew_Small", 300, 27, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetPos(frame:GetWide() - 42, 11) close:SetSize(30, 30) close:SetText("✕")
    close:SetFont("GRMCurfew_Head") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = function() frame:Close() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(14, 62, 14, 14) body:SetPaintBackground(false)

    -- ── Карточка состояния ─────────────────────────────────────────
    local status = vgui.Create("DPanel", body)
    status:Dock(TOP) status:SetTall(132) status:DockMargin(0, 0, 0, 10)
    status.CachedSec = -1
    status.TimerText = "--:--"
    status.Paint = function(s, w, h)
        local st = CF.State
        draw.RoundedBox(7, 0, 0, w, h, C.card)
        local stripe = st.active and C.red or C.green
        draw.RoundedBox(2, 0, 0, 5, h, stripe)

        if st.active then
            local left = math.max(0, (tonumber(st.endTime) or 0) - CurTime())
            local sec = math.floor(left)
            -- Строка таймера пересобирается раз в секунду, а не каждый кадр.
            if sec ~= s.CachedSec then
                s.CachedSec = sec
                s.TimerText = fmtTime(sec)
            end
            local pulse = 190 + math.sin(CurTime() * 3) * 55
            draw.SimpleText("РЕЖИМ АКТИВЕН", "GRMCurfew_Head", 18, 18, Color(255, 110, 110, pulse), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(s.TimerText, "GRMCurfew_Timer", w - 20, 34, C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText("до окончания", "GRMCurfew_Small", w - 20, 62, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            local who = st.startedBy ~= "" and st.startedBy or "Система"
            if st.faction ~= "" then
                local disp = (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(st.faction)) or st.faction
                who = who .. "  •  " .. disp
            end
            draw.SimpleText("Объявил: " .. who, "GRMCurfew_Body", 18, 48, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Причина: " .. (st.reason ~= "" and st.reason or "не указана"),
                "GRMCurfew_Body", 18, 76, st.reason ~= "" and C.gold or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local total = math.max(1, (tonumber(st.endTime) or 0) - (tonumber(st.startedAt) or 0))
            local frac = math.Clamp(left / total, 0, 1)
            draw.RoundedBox(4, 18, h - 26, w - 36, 12, Color(35, 42, 56))
            draw.RoundedBox(4, 18, h - 26, (w - 36) * frac, 12, C.red)
        else
            draw.SimpleText("РЕЖИМ НЕ АКТИВЕН", "GRMCurfew_Head", 18, 22, C.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Город живёт в обычном режиме. Настройте параметры ниже и объявите комендантский час.",
                "GRMCurfew_Body", 18, 52, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if st.startedBy ~= "" then
                draw.SimpleText("Последний раз объявлял: " .. st.startedBy, "GRMCurfew_Small", 18, 78, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            if not st.canControl then
                draw.SimpleText("У вас нет доступа к управлению комендантским часом.", "GRMCurfew_Small", 18, h - 22, C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- ── Длительность ───────────────────────────────────────────────
    local durCard = vgui.Create("DPanel", body)
    durCard:Dock(TOP) durCard:SetTall(108) durCard:DockMargin(0, 0, 0, 10)
    durCard.Paint = function(_, w, h)
        draw.RoundedBox(7, 0, 0, w, h, C.card)
        draw.SimpleText("ДЛИТЕЛЬНОСТЬ", "GRMCurfew_Head", 16, 18, C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local slider = vgui.Create("DNumSlider", durCard)
    slider:SetPos(16, 32) slider:SetSize(520, 32)
    slider:SetText("Минут")
    slider:SetMin(CF.State.minMinutes or 1)
    slider:SetMax(CF.State.maxMinutes or 120)
    slider:SetDecimals(0)
    slider:SetValue(10)
    slider.Label:SetFont("GRMCurfew_Body")
    slider.Label:SetTextColor(C.text)

    local presets = vgui.Create("DPanel", durCard)
    presets:SetPos(16, 68) presets:SetSize(520, 30) presets:SetPaintBackground(false)
    local px = 0
    for _, m in ipairs({ 5, 10, 15, 30, 60, 120 }) do
        local b = mkButton(presets, m .. " мин", C.head, function() slider:SetValue(m) end)
        b:SetPos(px, 0) b:SetSize(82, 28)
        px = px + 88
    end

    -- ── Причина ────────────────────────────────────────────────────
    local reasonCard = vgui.Create("DPanel", body)
    reasonCard:Dock(TOP) reasonCard:SetTall(92) reasonCard:DockMargin(0, 0, 0, 10)
    reasonCard.Paint = function(_, w, h)
        draw.RoundedBox(7, 0, 0, w, h, C.card)
        draw.SimpleText("ПРИЧИНА ОБЪЯВЛЕНИЯ", "GRMCurfew_Head", 16, 18, C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local reason = vgui.Create("DTextEntry", reasonCard)
    reason:SetPos(16, 34) reason:SetSize(520, 30)
    reason:SetFont("GRMCurfew_Body")
    reason:SetPlaceholderText("Например: массовые беспорядки в центре города")
    reason:SetUpdateOnType(true)
    reason.Paint = function(s, w, h)
        draw.RoundedBox(5, 0, 0, w, h, Color(14, 18, 26))
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        s:DrawTextEntryText(C.text, C.acc, C.text)
        if s:GetText() == "" and not s:HasFocus() then
            draw.SimpleText(s:GetPlaceholderText() or "", "GRMCurfew_Small", 8, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local counter = vgui.Create("DLabel", reasonCard)
    counter:SetPos(16, 66) counter:SetSize(520, 18)
    counter:SetFont("GRMCurfew_Small") counter:SetTextColor(C.dim)
    counter:SetText("0 / 140 символов • причина попадёт в объявление и в журнал действий")
    reason.OnValueChange = function(s, val)
        local n = string.len(val or "")
        if n > 140 then s:SetText(string.sub(val, 1, 140)) n = 140 end
        counter:SetText(n .. " / 140 символов • причина попадёт в объявление и в журнал действий")
    end

    -- ── Кнопки действий ────────────────────────────────────────────
    local actions = vgui.Create("DPanel", body)
    actions:Dock(TOP) actions:SetTall(64) actions:SetPaintBackground(false)

    local btnStart = mkButton(actions, "ОБЪЯВИТЬ КОМЕНДАНТСКИЙ ЧАС", C.red, function()
        sendAct("start", math.floor(slider:GetValue()), reason:GetValue())
    end)
    btnStart:Dock(LEFT) btnStart:SetWide(330) btnStart:DockMargin(0, 0, 8, 0)

    local btnStop = mkButton(actions, "ОСТАНОВИТЬ", C.green, function()
        sendAct("stop", 0, "")
    end)
    btnStop:Dock(FILL)

    -- ── Валидация состояния кнопок ─────────────────────────────────
    -- Дешёвая проверка 4 раза в секунду: состояние приходит с сервера,
    -- здесь только раскраска и включение/выключение кнопок.
    local function applyState()
        local st = CF.State
        slider:SetMin(st.minMinutes or 1)
        slider:SetMax(st.maxMinutes or 120)

        btnStart.Enabled = st.canControl and not st.active
        btnStop.Enabled = st.canControl and st.active

        if not st.canControl then
            btnStart.Hint = "нет доступа"
            btnStop.Hint = "нет доступа"
        else
            btnStart.Hint = st.active and "уже идёт" or ("на " .. math.floor(slider:GetValue()) .. " мин")
            btnStop.Hint = st.active and "снять режим досрочно" or "режим не активен"
        end

        slider:SetEnabled(st.canControl and not st.active)
        reason:SetEnabled(st.canControl and not st.active)
    end
    CF._apply = applyState
    applyState()

    body.Think = function()
        if (body._nextCheck or 0) > CurTime() then return end
        body._nextCheck = CurTime() + 0.25
        applyState()
    end

    frame.OnRemove = function()
        CF._apply = nil
        net.Start(NET_ACT)
            net.WriteString("close")
            net.WriteUInt(0, 8)
            net.WriteString("")
        net.SendToServer()
    end

    CF.RequestState()
end

net.Receive(NET_MENU, function()
    local st = CF.State
    st.canControl = net.ReadBool()
    st.active     = net.ReadBool()
    st.endTime    = net.ReadFloat()
    st.startedAt  = net.ReadFloat()
    st.startedBy  = net.ReadString()
    st.faction    = net.ReadString()
    st.reason     = net.ReadString()
    st.minMinutes = net.ReadUInt(8)
    st.maxMinutes = net.ReadUInt(8)

    if not IsValid(frame) then
        -- Состояние пришло по команде /kom_hour — открываем меню.
        if st.canControl then CF.Open() end
        return
    end
    if CF._apply then CF._apply() end
end)

concommand.Add("grm_curfew", function() CF.Open() end)

print("[GRM Curfew] menu v" .. CF.Version .. " loaded")
