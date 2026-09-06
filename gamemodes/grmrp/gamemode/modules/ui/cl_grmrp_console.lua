--[[ GRM:RP — кастомная консоль режима (заказ владельца 06.09, вечер-28).

    «Консоль вызывается, но там идёт консоль старого меню — конфликт
    старого и нового. Сделай кастомную консоль, но чтобы она дублировала
    со старой консоли старого меню всю информацию.»

    МОДЕЛЬ ДАННЫХ — старое меню (lua/autorun: «Консоль сервера» центра
    администрирования, заказ 02.09). Дублирование, а не переспорка:
      * канал клиента → сервера тот же: GRM.Admin.Net.CONSOLE (net.Start +
        net.WriteString) — серверные guard/право/аудит не дублируем;
      * приём — ТОЛЬКО через широковещательный хук GRM_AdminConsoleLine,
        который старая панель сама запускает после net.Receive. Второй
        net.Receive на том же канале съел бы пакет у старой панели
        (читатель net-буфера один) — вот это и был бы конфликт;
      * история: при первом открытии проигрываем накопленное старой
        панелью в GRM.Admin.ConsoleLines (строки, пришедшие до загрузки
        gamemode-скриптов, терялись бы);
      * формат блока — побайтово тот же: «HH:MM:SS [админ] строка» +
        тело ответа новой строкой (широковещательный хук несёт готовый
        блок — переформатирование не нужно и равно нарушению дубля).
    Вызовы движковой консоли (toggleconsole) и обход фильтров (ULib)
    запрещены решением веч.-27: всё ходит штатным net-каналом режима.

    ПОВЕДЕНИЕ ОКНА. Открытие/закрытие — вкладка «Консоль режима» в ESC-меню
    (пункт реестра GRMRPMenu.AddTab) и сканер GRMRPMenu_Takeover: верхний
    слой при ESC — консоль (иерархия веч.-25 сохранена). Пока открыта
    ДВИЖКОВАЯ консоль (~), окно само гаснет: две консоли на экране — тот
    самый конфликт (тот же guard стоит и в сканере меню). Клавиатурный
    захват включён ОСОЗНАННО: это консоль — пока открыта, ввод принадлежит
    ей, как у нативной. Поле вывода read-only приёмом веч.-9:
    SetKeyboardInputEnabled(false) (у DTextEntry нет SetReadOnly).
]]

if SERVER then return end

GRMRPConsole = GRMRPConsole or {}
local CON = GRMRPConsole

-- Строк в буфере вида; старше — вытесняется. Старая панель не ограничивала
-- ленту вовсе (растущий DTextEntry) — здесь это аккуратно чиним.
CON.Cap = 600
local lines = {}
local historyReplayed = false
local noticeShown = false

local COL = {
    bg = Color(8, 14, 23),
    panel = Color(16, 27, 42),
    panelHi = Color(24, 38, 58),
    accent = Color(48, 204, 255),
    text = Color(225, 238, 247),
    dim = Color(132, 160, 178),
    gold = Color(250, 185, 63),
    red = Color(244, 78, 96)
}

surface.CreateFont("GRMRP_ConBody", { font = "Consolas", size = 14,
    weight = 500, extended = true, antialias = false })
surface.CreateFont("GRMRP_ConSmall", { font = "Roboto", size = 13,
    weight = 600, extended = true, antialias = true })

--- Имя канала берём из того же реестра, что у старого меню, — имена net
--  должны сходиться сами, а не по совпадению строк в двух местах.
function CON.Channel()
    local ad = GRM and GRM.Admin
    local names = ad and ad.Net
    return isstring(names and names.CONSOLE) and names.CONSOLE or nil
end

------------------------------------------------------------------ лента
local function appendToView(block)
    local out = CON.out
    if not IsValid(out) then return end
    out:SetText((out:GetValue() or "") .. block .. "\n")
    -- DTextEntry — не DScrollPanel: VBar/GetCanvas тут фантомы (краш
    -- веч.-9 у старого меню). Движковый multiline следит за каретой:
    -- ставим карету в конец — прокрутка едет за ней (SetCaretPos —
    -- реальный метод DTextEntry, к нему и обращаемся под guard'ом).
    if out.SetCaretPos then
        pcall(function() out:SetCaretPos(#(out:GetValue() or "")) end)
    end
end

local function rebuildView()
    local out = CON.out
    if not IsValid(out) then return end
    out:SetText(table.concat(lines, "\n"))
    if out.SetCaretPos then
        pcall(function() out:SetCaretPos(#(out:GetValue() or "")) end)
    end
end

function CON.Add(block)
    block = tostring(block or "")
    if block == "" then return end
    lines[#lines + 1] = block
    local trimmed = false
    while #lines > CON.Cap do
        table.remove(lines, 1)
        trimmed = true
    end
    if not IsValid(CON.out) then return end
    if trimmed then
        -- буфер сдвинулся: «дописывать» к устаревшему полю нельзя
        rebuildView()
    else
        appendToView(block)
    end
end

-- Дубль информации: слушаем широковещательный хук старой консоли
-- (она зовёт hook.Run после того, как сама прочитала пакет).
hook.Add("GRM_AdminConsoleLine", "GRMRPConsole", function(block)
    CON.Add(block)
end)

local function replayHistory()
    if historyReplayed then return end
    historyReplayed = true
    local hist = GRM and GRM.Admin and GRM.Admin.ConsoleLines
    if not istable(hist) then return end
    -- Часть ХВОСТА истории уже могла прийти нам через хук до открытия —
    -- убираем перекрытие из буфера и лепим поверх ПОЛНУЮ историю: строки
    -- истории полностью покрывают перекрытый префикс буфера.
    local overlap = 0
    for p = math.min(#lines, #hist), 1, -1 do
        local same = true
        for i = 1, p do
            if lines[i] ~= tostring(hist[#hist - p + i]) then same = false break end
        end
        if same then overlap = p break end
    end
    local merged = {}
    for i = 1, #hist do merged[#merged + 1] = tostring(hist[i]) end
    for i = overlap + 1, #lines do merged[#merged + 1] = lines[i] end
    lines = merged
    while #lines > CON.Cap do table.remove(lines, 1) end
end

------------------------------------------------------------------ ввод
function CON.Run(line)
    line = string.Trim(tostring(line or ""))
    if line == "" then return false end
    local ch = CON.Channel()
    if not ch then
        CON.Add("[консоль режима] живого ввода нет: аддон grm " ..
            "(lua/autorun/sh_grm_admin_core.lua) не найден — окно остаётся " ..
            "дублем ленты. Установите grm_full_code.zip ЦЕЛИКОМ.")
        return false
    end
    net.Start(ch)
    net.WriteString(line)
    net.SendToServer()
    return true
end

------------------------------------------------------------------ окно
function CON.IsOpen()
    return IsValid(CON.root)
end

function CON.Close()
    if IsValid(CON.root) then CON.root:Remove() end
    CON.root = nil
    CON.out = nil
    CON.input = nil
end

function CON.Open()
    if CON.IsOpen() then return end
    replayHistory()

    local scrW, scrH = ScrW(), ScrH()
    local w = math.Clamp(scrW * 0.72, 640, 1160)
    local h = math.Clamp(scrH * 0.68, 320, 640)

    local root = vgui.Create("DPanel")
    CON.root = root
    root:SetSize(w, h)
    root:SetPos(math.floor((scrW - w) / 2), math.floor((scrH - h) / 2) - 20)
    root:MakePopup()
    root.Paint = function(s, cw, chh)
        draw.RoundedBox(8, 0, 0, cw, chh, COL.bg)
        if draw.RoundedBoxEx then
            draw.RoundedBoxEx(8, 0, 0, cw, 38, COL.panel, true, true, false, false)
        else
            draw.RoundedBox(0, 0, 0, cw, 38, COL.panel)
        end
        surface.SetDrawColor(40, 62, 92, 120)
        surface.DrawOutlinedRect(0, 0, cw, chh)
        local stamp = (GRMRPMenu and GRMRPMenu.BuildStamp) or "?"
        draw.SimpleText("Консоль режима · дубль консоли старого меню · сборка " .. stamp,
            "GRMRP_ConSmall", 14, 19, COL.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Enter — выполнить · ESC — закрыть",
            "GRMRP_ConSmall", cw - 128, 19, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", root)
    close:Dock(RIGHT)
    close:SetWide(64)
    close:SetText("")
    close.Paint = function(s, cw, chh)
        if s:IsHovered() then draw.RoundedBox(4, 4, 4, cw - 8, chh - 8, COL.red) end
        draw.SimpleText("✕", "GRMRP_ConSmall", cw / 2, chh / 2, COL.text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() CON.Close() end

    -------------------------------------------------- вывод (только чтение)
    local out = vgui.Create("DTextEntry", root)
    out:Dock(FILL)
    out:DockMargin(10, 6, 10, 4)
    out:SetMultiline(true)
    out:SetFont("GRMRP_ConBody")
    -- read-only: у DTextEntry нет SetReadOnly (движковый dtextentry.lua
    -- знает только SetEditable/SetDisabled/AllowInput) — снимаем клавиатуру
    -- и оставляем мышь: текст выделяется и копируется (приём веч.-9).
    out:SetKeyboardInputEnabled(false)
    out:SetTextColor(COL.text)
    out:SetBackgroundColor(COL.panel)
    CON.out = out
    rebuildView()

    -------------------------------------------------- строка ввода + чипы
    local rowIn = vgui.Create("DPanel", root)
    rowIn:Dock(BOTTOM)
    rowIn:SetTall(34)
    rowIn:SetPaintBackground(false)

    local input = vgui.Create("DTextEntry", rowIn)
    input:Dock(FILL)
    input:DockMargin(0, 3, 96, 3)
    input:SetFont("GRMRP_ConBody")
    input:SetPlaceholderText("status · get <cvar> · set <cvar> <val> · bans · ac list · любая консольная строка")
    input:SetTextColor(COL.text)
    input:SetBackgroundColor(COL.panelHi)
    CON.input = input

    local send = vgui.Create("DButton", rowIn)
    send:Dock(RIGHT)
    send:SetWide(88)
    send:SetText("выполнить")
    send:SetFont("GRMRP_ConSmall")
    send:SetTextColor(COL.text)
    local function fire()
        if not IsValid(input) then return end
        local line = string.Trim(tostring(input:GetValue() or ""))
        if line == "" then return end
        input:SetText("")
        pcall(CON.Run, line)
    end
    send.DoClick = fire
    input.OnEnter = fire

    local chips = vgui.Create("DPanel", root)
    chips:Dock(BOTTOM)
    chips:SetTall(26)
    chips:SetPaintBackground(false)
    for _, label in ipairs({ "status", "bans", "ac list", "ac status", "get grm_ac_action", "history" }) do
        local c = vgui.Create("DButton", chips)
        c:Dock(LEFT)
        c:DockMargin(4, 2, 5, 2)
        c:SetWide(math.max(56, 7 + #label * 6))
        c:SetText(label)
        c:SetFont("GRMRP_ConSmall")
        c:SetTextColor(COL.dim)
        c.DoClick = function() pcall(CON.Run, label) end
    end

    if not CON.Channel() and not noticeShown then
        noticeShown = true
        CON.Add("[консоль режима] это ДУБЛЬ ленты старого меню: живой ввод " ..
            "отключён — серверный канал GRM_Admin_Console не найден (нет " ..
            "аддона grm). Движковая консоль (~) работает как обычно.")
    end
    input:RequestFocus()
end

function CON.Toggle()
    if CON.IsOpen() then
        CON.Close()
    else
        CON.Open()
    end
end
