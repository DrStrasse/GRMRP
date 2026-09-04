-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: cl_grmrp_chat.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP порт подавляется САМИМ
    РЕЖИМОМ (GRMRPChat.SuppressAddonPort снимает все хуки/таймеры/команды с
    id «GRMChat*»; вечер-13): прежний guard «if GRMRP.Version» ловил
    только поздний reload — GMod исполняет lua/autorun аддонов ДО файлов
    режима, и на свежей карте два чата жили бок о бок (двойная Y-полоса,
    перехваты, общая DATA-история). Теперь плюс ранний guard (порядок
    reload через lua_refresh) и гейты SUPPRESSED на входах.
]]
if SERVER then return end
if (GRMRP and GRMRP.Version) or (GRMRPChat and GRMRPChat.Channels)
    then return end -- режим уже здесь/на reload: порт не рождается

if SERVER then return end

local history = {}
local histIdx = 0

-- Вечер-12.2 («запоминание»): история ВВОДА пережила рестарт — последние
-- 50 строк в DATA, отложенная запись dirty-таймером. Голый RAM означал
-- «чат ничего не помнит после перезахода» — ровно досадная мелочь из
-- «всё те же проблемы».
local INP_FILE = "grm_chat/port_input.txt"
local function saveInput()
    if not (file and file.CreateDir and file.Write and util and util.TableToJSON) then return end
    pcall(function()
        file.CreateDir("grm_chat")
        local out = {}
        for i = math.max(1, #history - 49), #history do
            out[#out + 1] = tostring(history[i])
        end
        file.Write(INP_FILE, util.TableToJSON(out))
        GRMChat._inpDirty = false
    end)
end
local function loadInput()
    pcall(function()
        if not (file and file.Exists and util and util.JSONToTable) then return end
        if not file.Exists(INP_FILE, "DATA") then return end
        local tbl = util.JSONToTable(file.Read(INP_FILE, "DATA") or "")
        if not istable(tbl) then return end
        for i = 1, #tbl do
            local s = tostring(tbl[i] or "")
            if #s > 0 then history[#history + 1] = s end
        end
        while #history > 50 do table.remove(history, 1) end
    end)
end
loadInput()
GRMChat.inputHistory = history -- виден диагностике
GRMChat.SaveInput = saveInput
if timer and timer.Create then
    timer.Create("GRMChat_InpSave", 20, 0, function()
        if GRMChat._inpDirty then saveInput() end
    end)
end
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
    -- Вечер-12: общий словарь — RP-команды ядра и команды модулей (биндер)
    -- живут в автодополнении наравне с каналами: чат и биндер видят одно и то же.
    for _, c in ipairs(GRMChat.RPCommandNames and GRMChat.RPCommandNames() or {}) do
        table.insert(out, c .. " ")
    end
    for c in pairs(GRMChat.ExternalCommands or {}) do
        table.insert(out, c .. " ")
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
    if string.lower(text) == "/clear" then
        -- лента — витрина: чистится только экран, архив истории НЕ трогается
        if GRMChat.ClearLines then GRMChat.ClearLines() end
        return
    end
    if string.lower(text) == "/chatdiag" then
        -- Самодиагностика ленты (вечер-8): строку-диагностику печатает в
        -- ту же ленту — видно её = чат рендерит; не видно = сборка старая.
        if GRMChat.Diagnose then GRMChat.Diagnose() end
        return
    end
    -- 512 по UTF-8 границе (Utf8Cut из ядра), не посередине буквы
    if #text > 512 then
        text = (GRMChat.Utf8Cut and GRMChat.Utf8Cut(text, 512))
            or string.sub(text, 1, 512)
    end
    table.insert(history, text)
    if #history > 50 then table.remove(history, 1) end
    histIdx = 0
    GRMChat._inpDirty = true

    -- Локальный эхо-каст форматром ядра; для rand-действий (try/roll) и
    -- /it результат знает только сервер — там ждём настоящую строку
    -- (echo-флаг в RP-таблице, §5.1.3).
    local first = string.match(text, "^/([%w_]+)")
    if first == nil then
        -- кириллические алиасы (/бинды) вне %w_ — сверка префиксом по реестру
        local low = string.lower(text)
        for c in pairs(GRMChat.ExternalCommands or {}) do
            if string.sub(low, 1, #c) == c then first = c:sub(2) break end
        end
    end
    if first and GRMChat.ExternalCommands
        and GRMChat.ExternalCommands["/" .. string.lower(first)] then
        -- Вечер-12 (чат ↔ модули): чужие slash-команды идут ЧЕРЕЗ движковый
        -- say — их обработчики живут в цепочке PlayerSay; наш net-канал
        -- «съел» бы их как неизвестные («/binder» из ввода не открывал биндер).
        RunConsoleCommand("say", text)
        return
    end
    local def = first and GRMChat.RP and GRMChat.RP[string.lower(first)]
    if not (def and def.echo) then
        GRMChat.AddSelfLine(text, selChan)
    end

    net.Start(GRMChat.Net.SAY)
        net.WriteString(selChan)
        net.WriteString(text)
    net.SendToServer()
end

-- Вечер-12: модули (биндер!) печатают отыгровки ЭТИМ путём. Сервер автору не
-- ретранслирует («оптимистичное эхо», §5.4.3), поэтому без локального эха
-- строки биндера в ленте/истории автора просто исчезали. SendText = тот же
-- путь, что и Enter в окне: форматер RP, история ввода, канал выбора.
GRMChat.SendText = send

local function closeInput()
    if IsValid(frame) then frame:Hide() end
    GRMChat.INPUT_OPEN = false
end

local function chanNow()
    return GRMChat.GetChannel and GRMChat.GetChannel(selChan)
end

local function toggleHistory()
    -- Вечер-12: у EditablePanel НЕТ метода :Close() (это DFrame-метод) —
    -- открытие/закрытие истории крешало фантомным вызовом, ровно тот же
    -- класс бага, что GetCanvas/SetReadOnly (проверено по dframe.lua).
    if IsValid(histPanel) then histPanel:Remove() return end
    local win = vgui.Create("EditablePanel")
    histPanel = win
    -- вечер-10: «окно истории слишком мелкое» (владелец) — было 600x400
    win:SetSize(math.Clamp(ScrW() * 0.62, 760, 1400), math.Clamp(ScrH() * 0.72, 480, 1120))
    win:Center()
    win:MakePopup()
    win.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(8, 14, 23, 245))
        surface.SetDrawColor(40, 62, 92, 140)
        surface.DrawOutlinedRect(0, 0, w, h)
        local arc = GRMChat.archive or {}
        draw.SimpleText(("История чата · %d строк · дописывается живьём · ESC — закрыть · Ctrl+C копирует")
            :format(#arc), "GRMRP_ChatChip", 14, 8, Color(132, 160, 178))
    end
    win.OnRemove = function()
        GRMChat.HIST_OPEN = false
        histPanel = nil
        if timer and timer.Remove then timer.Remove("GRMChat_HistRefr") end
        hook.Remove("OnScreenSizeChanged", "GRMChat_HistSize")
    end
    win.OnKeyCodeTyped = function(_, code)
        if code == KEY_ESCAPE then win:Remove() end
    end
    local scroll = vgui.Create("DScrollPanel", win)
    scroll:SetPos(10, 28)
    scroll:SetSize(win:GetWide() - 20, win:GetTall() - 38)
    local body = vgui.Create("DPanel", scroll)
    body:SetPaintBackground(false)
    body:Dock(TOP)
    local state = { y = 0, n = 0 }
    -- вечер-12.2: «окна» — при смене разрешения окно и скролл пересчитываются
    -- (прежде край съедал строки после alt+enter/fullscreen)
    hook.Add("OnScreenSizeChanged", "GRMChat_HistSize", function()
        if not IsValid(win) then return end
        win:SetSize(math.Clamp(ScrW() * 0.62, 760, 1400), math.Clamp(ScrH() * 0.72, 480, 1120))
        win:Center()
        if IsValid(scroll) then
            scroll:SetSize(win:GetWide() - 20, win:GetTall() - 38)
        end
    end)

    -- Вечер-12 («хранение/история»): источник — АРХИВ, а не кормовой буфер:
    -- строки ленты подметаются TTL через ~49 с, «история» оказывалась самой
    -- лентой. Архив живёт в cl_grm_chat_hud (push), пишется на диск и
    -- несёт стенные метки времени (wallT) — корректные и после рестарта.
    local function addLine(ln)
        local chan = ln.chan or { title = "·", color = { r = 200, g = 200, b = 200 } }
        local wallT = tonumber(ln.wallT) or math.max(0, math.ceil((ln.t or 0) + RealTime() - CurTime()))
        local line = vgui.Create("DLabel", body)
        line:SetText(os.date("%H:%M", wallT) ..
            "  [" .. (chan.title or "·") .. "]  " ..
            ((ln.name and #ln.name > 0) and (ln.name .. ": ") or "") .. (ln.text or ""))
        line:SetFont("GRMRP_Chat14")
        line:SetTextColor(Color(225, 238, 247))
        line:SetWrap(true)
        line:SetSelectable(true)
        line:SetWide(scroll:GetWide() - 24)
        line:SetPos(0, state.y)
        line:SizeToContents()
        local hh = math.max(18, line:GetTall())
        line:SetTall(hh)
        state.y = state.y + hh
        body:SetTall(state.y + 4)
        return line
    end
    local lastLine = nil
    -- вечер-12.2: прилипание к низу по API из dscrollpanel.lua движка
    -- (GetVBar/GetCanvas/SetScroll/GetScroll — греп gsrc; ничего выдуманного)
    local function maxScroll()
        if not IsValid(scroll) then return 0 end
        local cv = scroll.GetCanvas and scroll:GetCanvas()
        local tall = IsValid(cv) and cv:GetTall() or 0
        return math.max(0, tall - scroll:GetTall())
    end
    local function stick()
        local vb = IsValid(scroll) and scroll.GetVBar and scroll:GetVBar()
        if not (IsValid(vb) and isfunction(vb.SetScroll)) then
            if IsValid(scroll) and IsValid(lastLine) and isfunction(scroll.ScrollToChild) then
                pcall(function() scroll:ScrollToChild(lastLine) end)
            end
            return
        end
        vb:SetScroll(maxScroll())
    end
    local function atBottom()
        local vb = IsValid(scroll) and scroll.GetVBar and scroll:GetVBar()
        if not (IsValid(vb) and isfunction(vb.GetScroll)) then return true end
        return vb:GetScroll() >= maxScroll() - 4
    end
    local src = GRMChat.archive or GRMChat.lines or {}
    for i = 1, #src do lastLine = addLine(src[i]) end
    state.n = #src
    timer.Simple(0.02, function()
        if IsValid(scroll) then stick() end
    end)
    -- окно живое: пока открыто, новые строки ДОПИСЫВАЮТСЯ (не пересборка —
    -- пересборка убивала бы выделение и прокрутку)
    if timer and timer.Create then
        timer.Create("GRMChat_HistRefr", 1, 0, function()
            if not IsValid(win) or not IsValid(body) then
                timer.Remove("GRMChat_HistRefr")
                return
            end
            local arc = GRMChat.archive or {}
            if state.n >= #arc then return end
            -- если пользователь отскроллил вверх читать — НЕ утаскиваем вниз;
            -- если стоит у конца — дописка тянет ленту за собой
            local stickBottom = atBottom()
            while state.n < #arc do
                state.n = state.n + 1
                lastLine = addLine(arc[state.n])
            end
            if stickBottom then stick() end
        end)
    end
    GRMChat.HIST_OPEN = true
end


local function setChannel(id)
    if not (GRMChat.GetChannel and GRMChat.GetChannel(id)) then return end
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
        GRMChat.INPUT_OPEN = false
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
        GRMChat.INPUT_OPEN = false
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
        if GRMChat.PreviewText then
            preview:SetText(GRMChat.PreviewText(LocalPlayer():Name(), pp:GetValue(), selChan))
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
    if not GRMChat._bannered and GRMChat.AddSystem then
        GRMChat._bannered = true
        GRMChat.AddSystem("чат GRM · сборка вечер-13 (03.09) · /chatdiag · двойной чат порта и режима устранён · память ввода — переживает рестарт")
    end
    if not IsValid(frame) then build() end
    frame:Show()
    frame:SetPos(16, ScrH() - frame:GetTall() - 196)
    frame:MakePopup()
    GRMChat.INPUT_OPEN = true
    if IsValid(entry) then
        entry:RequestFocus()
        entry:SetValue(entry:GetValue() or "")
    end
end

hook.Add("OnScreenSizeChanged", "GRMChat_InputPos", function()
    if IsValid(frame) then
        frame:SetPos(16, ScrH() - frame:GetTall() - 196)
    end
end)

-- Y в песочнице: хук движковой клавиатуры + консольная команда для бинда.
hook.Add("HUDKeyPress", "GRMChat_Y", function(code, down, up, onlydown)
    if GRMChat.SUPPRESSED then return end -- вечер-13: Y принадлежит режиму
    if code == KEY_Y and GRMChat.Enabled and GRMChat.Enabled() then
        GRMChat.OpenInput()
        return true
    end
end)
concommand.Add("grm_chat_open", function()
    if GRMChat.OpenInput then GRMChat.OpenInput() end
end)
