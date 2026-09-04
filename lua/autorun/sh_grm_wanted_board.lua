--[[--------------------------------------------------------------------
    GRM Wanted Board v1.0.0 — «Лист розыска» в кармане.

    Быстрый просмотр общего списка разыскиваемых БЕЗ подхода к терминалу.
    Только чтение: изменить, снять или добавить запись отсюда нельзя —
    для этого по-прежнему нужен служебный компьютер либо команды.

    Что показывает:
      • общий список обеих юрисдикций с явным признаком
        «гражданский» / «военный» у каждой записи;
      • уровень розыска, статьи, сумму неоплаченных штрафов, онлайн ли
        разыскиваемый и когда запись обновлялась;
      • фильтр по юрисдикции и поиск по имени/ключу.

    Кнопки «Ориентировка своим» и «Ориентировка по волне» не меняют базу,
    а лишь передают сведения в служебные каналы (модуль bulletins) —
    поэтому они доступны только тем, у кого есть право на редактирование.

    Каналы:
      GRM_WantedBoard_Req   client → server  (Bool wantHistory)
      GRM_WantedBoard_Data  server → client  (Bool canEdit, String myJur,
                                              Table rows)

    Данные не хранятся: лист собирается на лету из GRM.Wanted.Records.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
GRM.Wanted.Board = GRM.Wanted.Board or {}

local B = GRM.Wanted.Board
B.Version = "1.0.0"

local NET_REQ  = "GRM_WantedBoard_Req"
local NET_DATA = "GRM_WantedBoard_Data"

B.MaxRows   = 200    -- потолок записей в одном пакете (лимит net 64 КБ)
B.Cooldown  = 1.0    -- секунд между запросами одного игрока

-----------------------------------------------------------------------
-- Общие хелперы
-----------------------------------------------------------------------
-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
B.CharKey = charKey

--- Человеческое название юрисдикции.
function B.JurName(j)
    return j == "military" and "Военный" or "Гражданский"
end

--- Короткая метка для таблицы.
function B.JurTag(j)
    return j == "military" and "ВОЕН" or "ГРАЖД"
end

if SERVER then
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)

    -----------------------------------------------------------------------
    -- Права
    -----------------------------------------------------------------------
    --- Кому позволено смотреть лист розыска.
    -- Основной источник истины — менеджер доступов (access.json).
    -- Фолбэк по названию фракции повторяет логику терминалов: на серверах,
    -- где доступы ещё не настроены, сотрудники не должны остаться без листа.
    function B.CanRead(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return false end
        if ply:IsSuperAdmin() then return true end

        local W = GRM.Wanted
        if W and isfunction(W.CanView) and W.CanView(ply) then return true end

        -- Спецслужбы видят всё и всегда.
        local SS = GRM.SpecialService
        if SS and isfunction(SS.IsAgent) and SS.IsAgent(ply) then return true end

        local T = GRM.CompTerminal
        if T and isfunction(T.CanManage) then
            if T.CanManage(ply, "civil") or T.CanManage(ply, "military") then return true end
        end
        return false
    end

    --- Может ли игрок рассылать ориентировки из листа.
    function B.CanBroadcast(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return false end
        if ply:IsSuperAdmin() then return true end
        local W = GRM.Wanted
        if W and isfunction(W.CanEdit) and W.CanEdit(ply) then return true end
        local T = GRM.CompTerminal
        if T and isfunction(T.CanEdit) then
            if T.CanEdit(ply, "civil") or T.CanEdit(ply, "military") then return true end
        end
        return false
    end

    -----------------------------------------------------------------------
    -- Сбор листа
    -----------------------------------------------------------------------
    local function onlineKeys()
        local set = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then set[charKey(p)] = true end
        end
        return set
    end

    --- Список разыскиваемых обеих юрисдикций.
    -- @param viewer игрок (для отметки «моё ведомство»), может быть nil
    -- @return массив записей, отсортированный по уровню и времени
    function B.Collect(viewer)
        local W = GRM.Wanted
        local rows = {}
        if not (W and istable(W.Records)) then return rows end

        local F = W.Fines
        local live = onlineKeys()

        for k, r in pairs(W.Records) do
            if istable(r) and ((tonumber(r.level) or 0) > 0 or #(r.reasons or {}) > 0) then
                local jur = r.jurisdiction == "military" and "military" or "civil"

                -- две самые свежие статьи — чтобы лист был информативен,
                -- но пакет не раздувался списком из 32 пунктов
                local top, fine = {}, 0
                local reasons = istable(r.reasons) and r.reasons or {}
                for i = #reasons, 1, -1 do
                    local c = reasons[i]
                    if istable(c) then
                        fine = fine + (tonumber(c.fine) or 0)
                        if #top < 2 then
                            top[#top + 1] = {
                                code  = tostring(c.code or ""),
                                title = tostring(c.title or ""),
                                level = tonumber(c.level) or 0,
                            }
                        end
                    end
                end

                local debt = 0
                if F and isfunction(F.DebtOf) then
                    local okDebt, res = pcall(F.DebtOf, k)
                    debt = (okDebt and tonumber(res)) or 0
                end

                rows[#rows + 1] = {
                    key          = k,
                    name         = tostring(r.name or "?"),
                    level        = tonumber(r.level) or 0,
                    jurisdiction = jur,
                    charges      = #reasons,
                    top          = top,
                    fine         = fine,
                    debt         = debt,
                    online       = live[k] == true,
                    updated      = tonumber(r.updated) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            if a.updated ~= b.updated then return a.updated > b.updated end
            return a.name < b.name
        end)

        while #rows > B.MaxRows do table.remove(rows) end
        return rows
    end

    --- Отправка листа игроку.
    function B.Send(ply)
        if not IsValid(ply) then return end
        if not B.CanRead(ply) then
            if GRM.Notify then GRM.Notify(ply, "У вас нет доступа к листу розыска.", 250, 110, 110)
            else ply:ChatPrint("[Розыск] У вас нет доступа к листу розыска.") end
            return
        end

        local W = GRM.Wanted
        local myJur = (W and isfunction(W.JurisdictionOfPlayer)) and W.JurisdictionOfPlayer(ply) or "civil"
        if W and isfunction(W.CanUseJurisdiction)
            and W.CanUseJurisdiction(ply, "civil") and W.CanUseJurisdiction(ply, "military") then
            myJur = "all"
        end

        net.Start(NET_DATA)
            net.WriteBool(B.CanBroadcast(ply))
            net.WriteString(myJur)
            net.WriteTable(B.Collect(ply))
        net.Send(ply)
    end

    net.Receive(NET_REQ, function(_, ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        ply.GRM_BoardNext = ply.GRM_BoardNext or 0
        if CurTime() < ply.GRM_BoardNext then return end
        ply.GRM_BoardNext = CurTime() + B.Cooldown
        B.Send(ply)
    end)

    -----------------------------------------------------------------------
    -- Команды: /board, /wanted_board, /лист, консольная grm_board
    -----------------------------------------------------------------------
    local BOARD_CMDS = {
        ["/board"]        = true,
        ["!board"]        = true,
        ["/wanted_board"] = true,
        ["/лист"]         = true,
        ["/листрозыска"]  = true,
    }

    local function boardCommand(ply, text)
        if not isstring(text) then return false end
        local first = string.lower(string.Explode(" ", string.Trim(text))[1] or "")
        if not BOARD_CMDS[first] then return false end
        B.Send(ply)
        return true
    end
    B.ChatCommand = boardCommand

    hook.Add("PlayerSay", "GRM_WantedBoard_Transform", function(ply, text, teamSays)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(pack) or not isstring(pack[1]) then return end
            if boardCommand(ply, pack[1]) then
                pack[1] = ""
                pack.SkipPlayerSay = true
            end

        if pack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "GRM_WantedBoard_Fallback", function(ply, text)
        if boardCommand(ply, text) then return "" end
    end)

    -- Имя grm_board намеренно НЕ занимаем: в проекте уже есть доска
    -- вакансий (sh_grm_board.lua), путаницы быть не должно.
    concommand.Add("grm_wanted_board", function(ply) if IsValid(ply) then B.Send(ply) end end)
    concommand.Add("grm_wantedlist", function(ply) if IsValid(ply) then B.Send(ply) end end)

    print("[GRM Wanted Board] сервер v" .. B.Version .. " загружен")
end

if CLIENT then
    local function theme()
        return (GRM.UI and GRM.UI.Theme) or nil
    end

    -- Фолбэк-палитра на случай, если тема XUI по какой-то причине не
    -- загрузилась: лист обязан открываться в любом случае.
    local FALLBACK = {
        bg = Color(8, 14, 23, 248), panel = Color(16, 27, 42, 245),
        panel2 = Color(22, 37, 56, 245), header = Color(10, 22, 37, 255),
        text = Color(225, 238, 247), muted = Color(132, 160, 178),
        cyan = Color(48, 204, 255), green = Color(64, 222, 147),
        amber = Color(250, 185, 63), red = Color(244, 78, 96),
        purple = Color(174, 98, 255), line = Color(55, 117, 151, 190),
    }

    local function C()
        local T = theme()
        return (T and T.Colors) or FALLBACK
    end

    surface.CreateFont("GRM_Board_Title",  { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRM_Board_Head",   { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("GRM_Board_Row",    { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRM_Board_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })

    B.Rows     = B.Rows or {}
    B.CanEdit  = false
    B.MyJur    = "civil"
    B.Filter   = "all"
    B.Search   = ""

    local function levelInfo(level)
        local W = GRM.Wanted
        local lv = (W and W.Levels and W.Levels[level]) or nil
        return (lv and lv.name) or ("Уровень " .. tostring(level)),
               (lv and lv.color) or C().amber,
               (lv and lv.short) or tostring(level)
    end

    local function money(v)
        v = math.floor(tonumber(v) or 0)
        if GRM.FormatMoney then return GRM.FormatMoney(v) end
        return string.Comma(v) .. " ℛ"
    end

    local function ago(ts)
        ts = tonumber(ts) or 0
        if ts <= 0 then return "—" end
        local d = os.time() - ts
        if d < 60 then return "только что" end
        if d < 3600 then return math.floor(d / 60) .. " мин назад" end
        if d < 86400 then return math.floor(d / 3600) .. " ч назад" end
        return os.date("%d.%m.%Y", ts)
    end

    --- Проходит ли запись текущий фильтр и поиск.
    local function visible(row)
        if B.Filter ~= "all" and row.jurisdiction ~= B.Filter then return false end
        local q = string.lower(string.Trim(B.Search or ""))
        if q == "" then return true end
        if string.find(string.lower(row.name), q, 1, true) then return true end
        if string.find(string.lower(row.key), q, 1, true) then return true end
        for _, c in ipairs(row.top or {}) do
            if string.find(string.lower(c.title or ""), q, 1, true) then return true end
            if string.find(string.lower(c.code or ""), q, 1, true) then return true end
        end
        return false
    end

    local function styledButton(parent, text, w, h, accent, onClick)
        local btn = vgui.Create("DButton", parent)
        btn:SetSize(w, h)
        btn:SetText(text)
        btn:SetFont("GRM_Board_Small")
        btn:SetTextColor(C().text)
        btn.Paint = function(self, bw, bh)
            local col = accent or C().panel2
            local a = self:IsHovered() and 255 or 190
            draw.RoundedBox(4, 0, 0, bw, bh, Color(col.r, col.g, col.b, a))
            surface.SetDrawColor(C().line)
            surface.DrawOutlinedRect(0, 0, bw, bh, 1)
        end
        btn.DoClick = function()
            surface.PlaySound("ui/buttonclick.wav")
            if onClick then onClick() end
        end
        return btn
    end

    --- Ориентировка по записи листа: база не меняется, сведения уходят
    -- в служебный канал.
    local function sendBulletin(channel, key)
        net.Start("GRM_WantedBulletin_Send")
            net.WriteString(channel)
            net.WriteString(key)
            net.WriteString("")
        net.SendToServer()
    end

    --- Строка листа.
    local function buildRow(parent, row)
        local card = vgui.Create("DPanel", parent)
        card:SetTall(58)
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 6)

        local lvName, lvColor, lvShort = levelInfo(row.level)
        local jurColor = row.jurisdiction == "military" and C().purple or C().cyan
        local jurTag   = B.JurTag(row.jurisdiction)

        -- Ширина зоны кнопок справа: текст в неё не заезжает.
        local RIGHT = B.CanEdit and 232 or 172

        card.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C().panel)
            surface.SetDrawColor(lvColor.r, lvColor.g, lvColor.b, 220)
            surface.DrawRect(0, 0, 3, h)
            surface.SetDrawColor(C().line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Плашка статуса слева: «гражданский» или «военный» видно сразу.
            surface.SetFont("GRM_Board_Small")
            local tagW = surface.GetTextSize(jurTag) + 16
            draw.RoundedBox(3, 14, 10, tagW, 17, Color(jurColor.r, jurColor.g, jurColor.b, 70))
            draw.SimpleText(jurTag, "GRM_Board_Small", 14 + tagW / 2, 19, jurColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local nameX = 14 + tagW + 10
            draw.SimpleText(row.name, "GRM_Board_Head", nameX, 19, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            if row.online then
                surface.SetFont("GRM_Board_Head")
                local nameW = surface.GetTextSize(row.name)
                draw.SimpleText("● в сети", "GRM_Board_Small", nameX + nameW + 12, 19,
                    C().green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            -- Статьи одной строкой, лишнее сворачивается в «… ещё N».
            local desc = ""
            for _, c in ipairs(row.top or {}) do
                local piece = ((c.code or "") ~= "" and (c.code .. " ") or "") .. tostring(c.title or "")
                desc = desc .. (desc ~= "" and " • " or "") .. piece
            end
            local hidden = (row.charges or 0) - #(row.top or {})
            if hidden > 0 then desc = desc .. ("  … ещё %d"):format(hidden) end
            if desc == "" then desc = "статьи не указаны" end
            draw.SimpleText(desc, "GRM_Board_Small", 14, 42, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Правая колонка сведений.
            draw.SimpleText(lvShort .. "  " .. lvName, "GRM_Board_Row", w - RIGHT - 12, 16,
                lvColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            local sub = ago(row.updated)
            if (row.debt or 0) > 0 then sub = "долг " .. money(row.debt) .. "  •  " .. sub end
            draw.SimpleText(sub, "GRM_Board_Small", w - RIGHT - 12, 40,
                (row.debt or 0) > 0 and C().red or C().muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        -- Кнопки: раскладываются в PerformLayout карточки, чтобы держаться
        -- правого края при любой ширине окна.
        local buttons = {}
        if B.CanEdit then
            buttons[#buttons + 1] = { styledButton(card, "Своим (/fr)", 108, 22, C().panel2,
                function() sendBulletin("fr", row.key) end), 224, 8 }
            buttons[#buttons + 1] = { styledButton(card, "На волну (/dep)", 108, 22, C().panel2,
                function() sendBulletin("dep", row.key) end), 224, 32 }
            buttons[#buttons + 1] = { styledButton(card, "Ключ", 100, 46, C().panel2,
                function()
                    SetClipboardText(row.key)
                    chat.AddText(C().cyan, "[Лист розыска] ", C().text, "Ключ скопирован: " .. row.key)
                end), 110, 8 }
        else
            buttons[#buttons + 1] = { styledButton(card, "Копировать ключ", 150, 24, C().panel2,
                function()
                    SetClipboardText(row.key)
                    chat.AddText(C().cyan, "[Лист розыска] ", C().text, "Ключ скопирован: " .. row.key)
                end), 162, 17 }
        end

        card.PerformLayout = function(self, w)
            for _, b in ipairs(buttons) do
                if IsValid(b[1]) then b[1]:SetPos(w - b[2], b[3]) end
            end
        end

        return card
    end

    local frame, scroll, statusLabel

    local function refill()
        if not IsValid(scroll) then return end
        scroll:Clear()

        local shown, civ, mil = 0, 0, 0
        for _, row in ipairs(B.Rows) do
            if row.jurisdiction == "military" then mil = mil + 1 else civ = civ + 1 end
            if visible(row) then
                buildRow(scroll, row)
                shown = shown + 1
            end
        end

        if shown == 0 then
            local empty = vgui.Create("DPanel", scroll)
            empty:SetTall(60)
            empty:Dock(TOP)
            empty.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("Записей не найдено", "GRM_Board_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        if IsValid(statusLabel) then
            statusLabel:SetText(("Показано: %d   •   гражданских: %d   •   военных: %d   •   всего: %d")
                :format(shown, civ, mil, #B.Rows))
        end
    end

    function B.Open()
        if IsValid(frame) then frame:Remove() end

        frame = vgui.Create("DFrame")
        frame:SetSize(math.min(940, ScrW() - 80), math.min(660, ScrH() - 80))
        frame:Center()
        frame:SetTitle("")
        frame:MakePopup()
        frame:ShowCloseButton(false)

        local T = theme()
        if T and isfunction(T.ApplyFrame) then
            T.ApplyFrame(frame, "wanted_board", "ЛИСТ РОЗЫСКА",
                "оперативная сводка • только чтение")
        else
            if GRM.UI and isfunction(GRM.UI.Track) then GRM.UI.Track("wanted_board", frame) end
            frame.Paint = function(self, w, h)
                draw.RoundedBox(9, 0, 0, w, h, C().bg)
                draw.RoundedBoxEx(9, 0, 0, w, 52, C().header, true, true, false, false)
                draw.SimpleText("ЛИСТ РОЗЫСКА", "GRM_Board_Title", 16, 20, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("оперативная сводка • только чтение", "GRM_Board_Small", 16, 40, C().cyan, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local close = styledButton(frame, "X", 28, 28, C().red, function() frame:Close() end)
            close:SetPos(frame:GetWide() - 40, 12)
        end

        -- ── Панель управления ────────────────────────────────────────
        local bar = vgui.Create("DPanel", frame)
        bar:SetPos(12, 60)
        bar:SetSize(frame:GetWide() - 24, 40)
        bar.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, C().panel) end

        local function filterBtn(label, value, x, w)
            local btn = vgui.Create("DButton", bar)
            btn:SetPos(x, 7)
            btn:SetSize(w, 26)
            btn:SetText(label)
            btn:SetFont("GRM_Board_Small")
            btn:SetTextColor(C().text)
            btn.Paint = function(self, bw, bh)
                local active = (B.Filter == value)
                local col = active and C().cyan or C().panel2
                draw.RoundedBox(4, 0, 0, bw, bh, Color(col.r, col.g, col.b, active and 90 or 210))
                surface.SetDrawColor(active and C().cyan or C().line)
                surface.DrawOutlinedRect(0, 0, bw, bh, 1)
            end
            btn.DoClick = function()
                B.Filter = value
                surface.PlaySound("ui/buttonclick.wav")
                refill()
            end
            return btn
        end

        filterBtn("Все", "all", 8, 70)
        filterBtn("Гражданские", "civil", 82, 110)
        filterBtn("Военные", "military", 196, 100)

        local search = vgui.Create("DTextEntry", bar)
        search:SetPos(306, 7)
        search:SetSize(240, 26)
        search:SetFont("GRM_Board_Small")
        search:SetPlaceholderText("Поиск: имя, ключ или статья…")
        search:SetUpdateOnType(true)
        search.OnValueChange = function(self, val)
            B.Search = val or ""
            refill()
        end

        styledButton(bar, "Обновить", 100, 26, C().panel2, function()
            net.Start(NET_REQ) net.WriteBool(false) net.SendToServer()
        end):SetPos(554, 7)

        styledButton(bar, "Закрыть", 90, 26, C().red, function()
            frame:Close()
        end):SetPos(bar:GetWide() - 98, 7)

        -- ── Список ───────────────────────────────────────────────────
        scroll = vgui.Create("DScrollPanel", frame)
        scroll:SetPos(12, 108)
        scroll:SetSize(frame:GetWide() - 24, frame:GetTall() - 108 - 40)
        local sbar = scroll:GetVBar()
        sbar:SetWide(8)
        sbar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 60)) end
        sbar.btnUp.Paint, sbar.btnDown.Paint = function() end, function() end
        sbar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C().cyan) end

        statusLabel = vgui.Create("DLabel", frame)
        statusLabel:SetPos(16, frame:GetTall() - 28)
        statusLabel:SetSize(frame:GetWide() - 32, 20)
        statusLabel:SetFont("GRM_Board_Small")
        statusLabel:SetTextColor(C().muted)
        statusLabel:SetText("Запрос данных…")

        refill()
        net.Start(NET_REQ) net.WriteBool(false) net.SendToServer()
    end

    net.Receive(NET_DATA, function()
        B.CanEdit = net.ReadBool()
        B.MyJur   = net.ReadString()
        B.Rows    = net.ReadTable() or {}
        if not IsValid(frame) then B.Open() else refill() end
    end)

    -- Локальные команды: если сервер по какой-то причине не перехватил
    -- чат, консольная команда всё равно откроет лист.
    concommand.Add("grm_board_open", function()
        net.Start(NET_REQ) net.WriteBool(false) net.SendToServer()
    end)

    print("[GRM Wanted Board] клиент v" .. B.Version .. " загружен")
end


--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("wanted", {
        label = "Розыск и ориентировки",
        version = (GRM.Wanted and GRM.Wanted.Version) or "1.0.0",
        Depends = { "access" },
        Status = function() return "доска розыска и ориентировки" end,
    })
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/board", "/wanted_board", "/лист", "/листрозыска" })
end
