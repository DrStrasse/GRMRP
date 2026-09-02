--[[--------------------------------------------------------------------
    GRM Admin Panel v1.0.0 — собственное админ-меню сборки

    Открытие: /admin, /админ, консоль grm_admin_panel (право menu.open).
    Разделы:
      Игроки        — список онлайна, состояние, все действия модерации;
      Привилегии    — группы, наследование, иммунитет, матрица полномочий;
      Назначения    — кому какая группа, срок, заметка;
      Сохранения    — сохранение/загрузка карты и модулей;
      Фракции       — быстрый переход в организационные меню;
      Модули        — что загружено, версии, очередь GRM.Boot;
      Суперадмин    — «читерские» возможности (god, невидимость, скорость,
                      деньги, предметы, строительный режим, заморозка всех).

    Оформление — единый стиль GRM (как /factions): тёмный корпус, золотой
    заголовок, боковое меню с прокруткой и авто-двумя столбцами.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Admin = GRM.Admin or {}
local AD = GRM.Admin

surface.CreateFont("GRMAdm_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMAdm_Sub",    { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMAdm_Body",   { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMAdm_Btn",    { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRMAdm_Small",  { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg        = Color(16, 20, 28, 252),
    sidebar   = Color(12, 15, 22, 255),
    card      = Color(22, 28, 38, 240),
    cardLight = Color(28, 36, 48, 240),
    cardHover = Color(36, 46, 62, 240),
    border    = Color(38, 48, 66, 200),
    accent    = Color(65, 145, 235),
    gold      = Color(245, 195, 65),
    green     = Color(55, 185, 110),
    red       = Color(225, 70, 70),
    orange    = Color(235, 150, 70),
    text      = Color(240, 244, 250),
    dim       = Color(155, 170, 190),
}

local frame, content, selected

local function btn(parent, label, col, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Paint = function(self, w, h)
        local c = col or C.accent
        if not self:IsEnabled() then c = C.cardLight
        elseif self:IsHovered() then c = Color(math.min(255, c.r + 22), math.min(255, c.g + 22), math.min(255, c.b + 22)) end
        draw.RoundedBox(6, 0, 0, w, h, c)
        draw.SimpleText(label, "GRMAdm_Btn", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() surface.PlaySound("buttons/button15.wav") if fn then fn() end end
    return b
end

local function entry(parent, placeholder)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont("GRMAdm_Body")
    e:SetTextColor(C.text)
    if placeholder then e:SetPlaceholderText(placeholder) end
    e.Paint = function(self, w, h)
        draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetText() == "" and self.GetPlaceholderText and self:GetPlaceholderText() then
            draw.SimpleText(self:GetPlaceholderText(), "GRMAdm_Small", 8, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return e
end

local function combo(parent)
    local cb = vgui.Create("DComboBox", parent)
    cb:SetFont("GRMAdm_Body")
    cb:SetTextColor(C.text)
    cb.Paint = function(self, w, h)
        draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    return cb
end

local function can(perm)
    return AD.Can and AD.Can(LocalPlayer(), perm) == true
end

local function act(op, sid, args)
    net.Start(AD.Net.ACT)
        net.WriteString(op)
        net.WriteString(tostring(sid or ""))
        net.WriteTable(istable(args) and args or {})
    net.SendToServer()
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: ИГРОКИ
-----------------------------------------------------------------------
--[[ Список игроков строится из ДВУХ источников:
       1) серверный срез (группы, иммунитет, флаги мут/клетка/фриз);
       2) локальный player.GetAll() — он есть сразу, ещё до ответа сервера.
     Раньше вкладка показывала пустоту (в том числе самого администратора),
     если ответ сервера не пришёл или пришёл раньше, чем построился раздел. ]]
local function playerRows()
    local byID, rows = {}, {}

    for _, row in ipairs((AD.Data and AD.Data.players) or {}) do
        if istable(row) and isstring(row.sid) then
            byID[row.sid] = row
            rows[#rows + 1] = row
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            local sid = tostring(ply:SteamID64() or "")
            local row = byID[sid]
            if not row then
                row = {
                    sid = sid,
                    nick = ply:Nick(),
                    rpName = ply:GetNWString("GRM_RPName", ""),
                    group = string.lower(tostring(ply:GetUserGroup() or "user")),
                    immunity = 0,
                    faction = ply:GetNWString("GRM_Faction", ""),
                    hp = ply:Health(), armor = ply:Armor(), ping = ply:Ping(),
                    alive = ply:Alive(), local_ = true,
                }
                byID[sid] = row
                rows[#rows + 1] = row
            else
                -- Живые значения берём с клиента: они свежее раза в 3 секунды.
                row.nick = ply:Nick()
                row.ping = ply:Ping()
                row.hp = ply:Health()
                row.alive = ply:Alive()
            end
            row.entity = ply
        end
    end

    table.sort(rows, function(a, b) return string.lower(a.nick or "") < string.lower(b.nick or "") end)
    return rows
end

--[[ Бан по номеру игрока (заказ владельца 19.08). Отдельный блок, потому
     что банить приходится и тех, кто уже вышел с сервера: номер ИГ-#### живёт
     в реестре, а SteamID помнить наизусть никто не обязан. ]]
local function buildBanByID(parent, canFn)
    if not canFn("mod.ban") then return end
    local box = vgui.Create("DPanel", parent)
    box:Dock(BOTTOM) box:SetTall(118) box:DockMargin(0, 8, 6, 0)
    box.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("БАН ПО ID ИГРОКА (работает и офлайн)", "GRMAdm_Small", 12, 10, C.gold)
        draw.SimpleText("Принимает ИГ-1042, ГР-4821 (найдёт игрока по персонажу) или SteamID64",
            "GRMAdm_Small", 12, 98, C.dim)
    end

    local query = vgui.Create("DTextEntry", box)
    query:SetPos(12, 30) query:SetSize(190, 28)
    query:SetPlaceholderText("ИГ-1042 / ГР-4821")

    local minutes = vgui.Create("DTextEntry", box)
    minutes:SetPos(208, 30) minutes:SetSize(70, 28)
    minutes:SetText("60")
    minutes:SetPlaceholderText("мин")

    local reason = vgui.Create("DTextEntry", box)
    reason:SetPos(284, 30) reason:SetSize(180, 28)
    reason:SetPlaceholderText("Причина")

    local find = btn(box, "НАЙТИ", C.accent, function()
        act("id_lookup", "", { query = query:GetValue() })
    end)
    find:SetPos(470, 30) find:SetSize(90, 28)

    -- Глобальный бан по железу (заказ 02.09): снимок машины и IP цели
    -- уезжают в глобальную запись, пока цель в сети; офлайн — только SteamID.
    local hw = vgui.Create("DCheckBoxLabel", box)
    hw:SetPos(12, 62) hw:SetSize(430, 20)
    hw:SetText("бан по железу: снимок машины и IP (нужен игрок в сети)")
    hw:SetValue(1) hw:SizeToContents()

    local ban = btn(box, "ЗАБАНИТЬ", C.red, function()
        local q = string.Trim(query:GetValue() or "")
        if q == "" then return end
        Derma_Query(("Забанить по номеру «%s» на %s мин?"):format(q, minutes:GetValue() or "60"),
            "Бан по ID", "Забанить", function()
                act("ban_id", "", { query = q, minutes = tonumber(minutes:GetValue()) or 60,
                    reason = reason:GetValue(),
                    hwid = not (hw.GetBool and not hw:GetBool()) })
            end, "Отмена")
    end)
    ban:SetPos(566, 30) ban:SetSize(110, 28)

    -- Снятие глобального бана: тем же полем, без поиска игрока в списке.
    local unban = btn(box, "РАЗБАНИТЬ", C.green, function()
        local q = string.Trim(query:GetValue() or "")
        if q == "" then return end
        act("unban", "", { query = q })
    end)
    unban:SetPos(682, 30) unban:SetSize(110, 28)
end

--[[ ЗОНА ОТБЫВАНИЯ БАНА (заказ владельца 21.08). Суперадмин встаёт в нужное
     место и одной кнопкой назначает точку: туда телепортирует забаненных на
     сервере, за радиус выйти нельзя. ]]
local function buildBanZone(parent, canFn)
    if not canFn("server.settings") then return end
    local box = vgui.Create("DPanel", parent)
    box:Dock(BOTTOM) box:SetTall(84) box:DockMargin(0, 8, 6, 0)
    box.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("БАН НА СЕРВЕРЕ · ЗОНА ОТБЫВАНИЯ", "GRMAdm_Small", 12, 10, C.gold)
        draw.SimpleText("Встаньте в нужном месте и нажмите «Поставить здесь». Радиус — предел свободы наказанного.",
            "GRMAdm_Small", 12, 64, C.dim)
    end

    local radius = vgui.Create("DTextEntry", box)
    radius:SetPos(12, 30) radius:SetSize(90, 28)
    radius:SetText("600")
    radius:SetPlaceholderText("радиус")

    local set = btn(box, "ПОСТАВИТЬ ЗДЕСЬ", C.gold, function()
        act("ban_point", "", { radius = tonumber(radius:GetValue()) or 600 })
    end)
    set:SetPos(108, 30) set:SetSize(180, 28)

    local show = btn(box, "ГДЕ ТОЧКА?", C.accent, function()
        RunConsoleCommand("grm_ban_zone")
    end)
    show:SetPos(294, 30) show:SetSize(140, 28)

    local list = btn(box, "СПИСОК ЗАБАНЕННЫХ", C.accent, function()
        RunConsoleCommand("grm_serverban_menu")
    end)
    list:SetPos(440, 30) list:SetSize(200, 28)
end

local function buildPlayers(pnl)
    local search = entry(pnl, "Поиск по нику, RP-имени, SteamID или номеру (ИГ-/ГР-)…")
    search:Dock(TOP) search:SetTall(30) search:DockMargin(0, 0, 0, 8)

    -- Бан по номеру игрока живёт внизу вкладки: он не требует выбранного
    -- игрока в списке и работает по офлайн-аккаунту.
    buildBanByID(pnl, can)
    buildBanZone(pnl, can)

    local split = vgui.Create("DPanel", pnl)
    split:Dock(FILL) split:SetPaintBackground(false)

    local list = vgui.Create("DScrollPanel", split)
    list:Dock(LEFT) list:SetWide(420)

    local side = vgui.Create("DScrollPanel", split)
    side:Dock(FILL) side:DockMargin(10, 0, 0, 0)

    local current = nil

    local function drawActions()
        if not IsValid(side) then return end
        side:Clear()
        if not current then
            local hint = vgui.Create("DPanel", side)
            hint:Dock(TOP) hint:SetTall(80)
            hint.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("Выберите игрока слева", "GRMAdm_Sub", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return
        end

        local head = vgui.Create("DPanel", side)
        head:Dock(TOP) head:SetTall(96) head:DockMargin(0, 0, 6, 8)
        head.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText(current.nick .. (current.rpName ~= "" and ("  ·  " .. current.rpName) or ""),
                "GRMAdm_Sub", 14, 12, C.text)
            -- Номера реестра: ИГ — игрок (по нему бан), ГР — текущий персонаж.
            local ids = "SteamID64: " .. current.sid
            if tostring(current.pid or "") ~= "" then ids = ids .. "   ·   игрок " .. current.pid end
            if tostring(current.cid or "") ~= "" then ids = ids .. "   ·   персонаж " .. current.cid end
            draw.SimpleText(ids, "GRMAdm_Small", 14, 34, C.dim)
            draw.SimpleText(("Группа: %s   ·   иммунитет %d   ·   организация: %s")
                :format(current.group, current.immunity or 0, current.faction ~= "" and current.faction or "—"),
                "GRMAdm_Small", 14, 52, C.gold)
            draw.SimpleText(("HP %d · броня %d · пинг %d · %s")
                :format(current.hp or 0, current.armor or 0, current.ping or 0, current.alive and "жив" or "мёртв"),
                "GRMAdm_Small", 14, 70, C.dim)

            local flags = {}
            if current.muted then flags[#flags + 1] = "МУТ" end
            if current.gagged then flags[#flags + 1] = "ГОЛОС" end
            if current.jailed then flags[#flags + 1] = "КЛЕТКА" end
            if current.serverBanned then flags[#flags + 1] = "БАН НА СЕРВЕРЕ" end
            if current.frozen then flags[#flags + 1] = "ЗАМОРОЗКА" end
            if current.ragdolled then flags[#flags + 1] = "РАГДОЛЛ" end
            if current.god then flags[#flags + 1] = "БОГ" end
            if #flags > 0 then
                draw.SimpleText(table.concat(flags, " · "), "GRMAdm_Small", w - 14, 12, C.orange, TEXT_ALIGN_RIGHT)
            end
        end

        local function group(title)
            local g = vgui.Create("DPanel", side)
            g:Dock(TOP) g:SetTall(26) g:DockMargin(0, 6, 6, 2) g:SetPaintBackground(false)
            g.Paint = function(_, w, h)
                draw.SimpleText(string.upper(title), "GRMAdm_Small", 2, h / 2, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        local row, rowIndex
        local function action(label, perm, op, col, args)
            if not can(perm) then return end
            if not row or rowIndex >= 3 then
                row = vgui.Create("DPanel", side)
                row:Dock(TOP) row:SetTall(36) row:DockMargin(0, 0, 6, 6) row:SetPaintBackground(false)
                rowIndex = 0
            end
            local b = btn(row, label, col or C.accent, function()
                act(op, current.sid, args)
            end)
            b:Dock(LEFT)
            b:SetWide(math.floor((side:GetWide() - 40) / 3))
            b:DockMargin(0, 0, 6, 0)
            rowIndex = rowIndex + 1
        end

        group("Перемещение")
        action("К игроку", "mod.goto", "goto_player")
        action("Притянуть", "mod.bring", "bring")
        action("Вернуть", "mod.return", "return")

        row = nil
        group("Ограничения")
        action(current.frozen and "Разморозить" or "Заморозить", "mod.freeze", "freeze", C.orange)
        action(current.muted and "Снять мут" or "Мут чата", "mod.mute", "mute", C.orange)
        action(current.gagged and "Вернуть голос" or "Мут голоса", "mod.gag", "gag", C.orange)
        action(current.jailed and "Выпустить" or "Клетка 120 с", "mod.jail", "jail", C.orange, { seconds = 120 })
        action(current.ragdolled and "Поднять" or "Рагдолл 20 с", "mod.ragdoll", "ragdoll", C.orange, { seconds = 20 })
        action("Забрать оружие", "mod.strip", "strip", C.orange)

        row = nil
        group("Состояние")
        action("Вылечить", "mod.heal", "heal", C.green, { hp = 100, armor = 100 })
        action("Воскресить", "mod.respawn", "respawn", C.green)
        action("Убить", "mod.slay", "slay", C.red)
        action(current.god and "Снять бога" or "Режим бога", "cheat.god", "god", C.gold)
        action("Невидимость", "cheat.cloak", "cloak", C.gold)
        action("Наблюдать", "mod.spectate", "spectate")

        row = nil
        group("Документы")
        action("Восстановить бланки и реестр", "docs.restore", "docs_restore", C.green)
        action("Нетеряемые: ВКЛ", "docs.restore", "docs_unlosable", C.gold)
        action("Нетеряемые: ВЫКЛ", "docs.restore", "docs_unlosable", C.orange, { off = true })
        action("Стереть документы", "docs.wipe", "docs_wipe", C.red)
        action("Стереть на всех персонажах", "docs.wipe", "docs_wipe", C.red, { account = true })

        row = nil
        group("Санкции")
        action("Предупреждение", "mod.warn", "warn", C.orange, { reason = "Соблюдайте правила" })
        action("Кик", "mod.kick", "kick", C.red, { reason = "Нарушение правил" })
        action("Глобальный бан 60 мин", "mod.ban", "ban", C.red, { minutes = 60, reason = "Нарушение правил" })
        action("Глобальный бан навсегда", "mod.ban", "ban", C.red, { minutes = 0, reason = "Нарушение правил" })
        -- Считывание машины (заказ 02.09): снимок железа цели — в консоль
        -- админу; тем же путём сервер привязывает отпечаток к бану.
        action("Снимок машины", "mod.ban", "machine", C.accent)

        --[[ БАН НА СЕРВЕРЕ (заказ владельца 21.08): срок и ПРИЧИНУ пишет
             админ, а не подставляет система. Кнопки разбана и бана стоят
             рядом — обе видны всегда, чтобы не гадать, в каком состоянии
             игрок. ]]
        if can("mod.ban") then
            row = nil
            group("Бан на сервере (деморган)")

            local box = vgui.Create("DPanel", side)
            box:Dock(TOP) box:SetTall(108) box:DockMargin(0, 0, 6, 6)
            box.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText(current.serverBanned and "ИГРОК ОТБЫВАЕТ НАКАЗАНИЕ" or "Игрок свободен",
                    "GRMAdm_Small", 12, 10, current.serverBanned and C.red or C.dim)
                draw.SimpleText("Срок в минутах (0 — бессрочно) и причина попадут игроку и в объявление",
                    "GRMAdm_Small", 12, 88, C.dim)
            end

            local minutesEntry = entry(box, "Минуты")
            minutesEntry:SetPos(12, 30) minutesEntry:SetSize(80, 28)
            minutesEntry:SetText("60")

            local reasonEntry = entry(box, "Причина бана (обязательно)")
            reasonEntry:SetPos(98, 30) reasonEntry:SetSize(330, 28)

            local banBtn = btn(box, "ЗАБАНИТЬ НА СЕРВЕРЕ", C.orange, function()
                local reason = string.Trim(reasonEntry:GetValue() or "")
                if reason == "" then
                    notification.AddLegacy("Укажите причину бана", NOTIFY_ERROR, 4)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                act("serverban", current.sid, {
                    minutes = tonumber(minutesEntry:GetValue()) or 60,
                    reason = reason,
                })
            end)
            banBtn:SetPos(12, 62) banBtn:SetSize(210, 30)

            local unbanBtn = btn(box, "РАЗБАНИТЬ НА СЕРВЕРЕ", C.green, function()
                act("unserverban", current.sid, {})
            end)
            unbanBtn:SetPos(228, 62) unbanBtn:SetSize(200, 30)
        end

        if can("cheat.money") or can("cheat.items") or can("cheat.speed") then
            row = nil
            group("Суперадмин")

            local tools = vgui.Create("DPanel", side)
            tools:Dock(TOP) tools:SetTall(84) tools:DockMargin(0, 0, 6, 6)
            tools.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, C.card) end

            local moneyEntry = entry(tools, "Сумма (минус — списать)")
            moneyEntry:SetPos(12, 12) moneyEntry:SetSize(180, 28)
            local moneyBtn = btn(tools, "Деньги", C.gold, function()
                act("money", current.sid, { value = tonumber(moneyEntry:GetValue()) or 0 })
            end)
            moneyBtn:SetPos(200, 12) moneyBtn:SetSize(110, 28)

            local itemEntry = entry(tools, "Класс оружия или предмета")
            itemEntry:SetPos(12, 46) itemEntry:SetSize(180, 28)
            local itemBtn = btn(tools, "Выдать", C.gold, function()
                act("item", current.sid, { text = itemEntry:GetValue() })
            end)
            itemBtn:SetPos(200, 46) itemBtn:SetSize(110, 28)

            local speedEntry = entry(tools, "Скорость x")
            speedEntry:SetPos(324, 12) speedEntry:SetSize(100, 28)
            speedEntry:SetText("1")
            local speedBtn = btn(tools, "Применить", C.gold, function()
                act("speed", current.sid, { value = tonumber(speedEntry:GetValue()) or 1 })
            end)
            speedBtn:SetPos(324, 46) speedBtn:SetSize(100, 28)
        end

        if can("acl.assign") then
            row = nil
            group("Группа игрока")
            local assign = vgui.Create("DPanel", side)
            assign:Dock(TOP) assign:SetTall(80) assign:DockMargin(0, 0, 6, 6)
            assign.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, C.card) end

            local cb = combo(assign)
            cb:SetPos(12, 12) cb:SetSize(220, 28)
            for id, g in pairs(AD.Data and AD.Data.groups or {}) do
                cb:AddChoice(tostring(g.name or id) .. "  [" .. id .. "]", id, id == current.group)
            end

            local days = entry(assign, "Срок в днях (0 = навсегда)")
            days:SetPos(242, 12) days:SetSize(180, 28)
            days:SetText("0")

            local note = entry(assign, "Заметка / основание")
            note:SetPos(12, 46) days:SetTall(28)
            note:SetSize(300, 28)

            local ok = btn(assign, "НАЗНАЧИТЬ", C.green, function()
                local _, gid = cb:GetSelected()
                if not gid then return end
                net.Start(AD.Net.ASSIGN)
                    net.WriteString(current.sid)
                    net.WriteString(gid)
                    net.WriteUInt(math.Clamp(math.floor(tonumber(days:GetValue()) or 0), 0, 3650), 16)
                    net.WriteString(note:GetValue() or "")
                net.SendToServer()
            end)
            ok:SetPos(322, 46) ok:SetSize(100, 28)
        end
    end

    local function rebuild()
        -- Панель могли уже пересобрать (переключение вкладки, повторный синк):
        -- сам pnl при этом остаётся валидным, а его дети — нет. Без этой
        -- проверки хук обновления игроков дёргал Clear() на удалённом списке
        -- и сыпал «Tried to use a NULL Panel!».
        if not (IsValid(list) and IsValid(search)) then return end
        list:Clear()
        local q = string.lower(string.Trim(search:GetValue() or ""))
        local rows = playerRows()
        local shown = 0

        if #rows == 0 then
            local empty = vgui.Create("DPanel", list)
            empty:Dock(TOP) empty:SetTall(70)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("Список игроков пуст — данные ещё идут с сервера…",
                    "GRMAdm_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        for _, row in ipairs(rows) do
            local hay = string.lower(tostring(row.nick or "") .. " " .. tostring(row.rpName or "") .. " "
                .. tostring(row.sid or "") .. " " .. tostring(row.pid or "") .. " " .. tostring(row.cid or ""))
            if q == "" or string.find(hay, q, 1, true) then
                shown = shown + 1
                local item = vgui.Create("DButton", list)
                item:Dock(TOP) item:SetTall(52) item:DockMargin(0, 0, 6, 6) item:SetText("")
                item.Paint = function(self, w, h)
                    local active = current and current.sid == row.sid
                    draw.RoundedBox(6, 0, 0, w, h, active and C.accent or (self:IsHovered() and C.cardHover or C.card))
                    draw.SimpleText(row.nick, "GRMAdm_Body", 12, 10, C.text)
                    local sub = (row.rpName ~= "" and row.rpName or row.sid)
                    if tostring(row.pid or "") ~= "" then sub = sub .. "  ·  " .. row.pid end
                    draw.SimpleText(sub, "GRMAdm_Small", 12, 30, active and C.text or C.dim)
                    draw.SimpleText(tostring(row.group or "user") .. (row.local_ and " ·" or ""),
                        "GRMAdm_Small", w - 12, 10, row.local_ and C.dim or C.gold, TEXT_ALIGN_RIGHT)
                    local flags = {}
                    if row.muted then flags[#flags + 1] = "мут" end
                    if row.jailed then flags[#flags + 1] = "клетка" end
                    if row.frozen then flags[#flags + 1] = "фриз" end
                    if #flags > 0 then
                        draw.SimpleText(table.concat(flags, "·"), "GRMAdm_Small", w - 12, 30, C.orange, TEXT_ALIGN_RIGHT)
                    end
                end
                item.DoClick = function()
                    current = row
                    drawActions()
                    rebuild()
                end
            end
        end
    end

    search.OnChange = rebuild
    rebuild()
    drawActions()

    -- Пока раздел открыт, раз в 5 секунд просим свежий срез: подписка на
    -- сервере живёт ограниченное время, а вкладка может висеть долго.
    local pollName = "GRM_AdminPanel_Poll"
    timer.Create(pollName, 5, 0, function()
        if not (IsValid(list) and IsValid(search)) then
            timer.Remove(pollName)
            return
        end
        if AD.Request then AD.Request() end
    end)
    list.OnRemove = function()
        timer.Remove(pollName)
        hook.Remove("GRM_AdminPlayersUpdated", "GRM_AdminPanel_Players")
    end

    -- Хук живёт ровно столько, сколько живёт СПИСОК этой вкладки.
    local hookID = "GRM_AdminPanel_Players"
    hook.Add("GRM_AdminPlayersUpdated", hookID, function()
        if not (IsValid(list) and IsValid(search)) then
            hook.Remove("GRM_AdminPlayersUpdated", hookID)
            return
        end
        -- Обновляем данные выбранного игрока, не сбивая работу администратора.
        if current then
            for _, row in ipairs(AD.Data.players or {}) do
                if row.sid == current.sid then current = row break end
            end
            if IsValid(side) then drawActions() end
        end
        rebuild()
    end)
    -- OnRemove уже назначен выше: снимает и таймер опроса, и подписку.
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: ПРИВИЛЕГИИ
-----------------------------------------------------------------------
local function buildPrivileges(pnl)
    if not can("acl.groups") then
        local warn = vgui.Create("DLabel", pnl)
        warn:Dock(TOP) warn:SetTall(40) warn:SetFont("GRMAdm_Sub") warn:SetTextColor(C.red)
        warn:SetText("Нужно право «Создание и правка групп».")
        return
    end

    local groups = table.Copy(AD.Data and AD.Data.groups or {})
    local perms = AD.Data and AD.Data.perms or {}
    local currentID = "moderator"

    local body = vgui.Create("DPanel", pnl)
    body:Dock(FILL) body:SetPaintBackground(false)

    local left = vgui.Create("DScrollPanel", body)
    left:Dock(LEFT) left:SetWide(250)

    local right = vgui.Create("DScrollPanel", body)
    right:Dock(FILL) right:DockMargin(10, 0, 0, 0)

    local rebuildLeft, rebuildRight

    rebuildRight = function()
        right:Clear()
        local group = groups[currentID]
        if not group then return end

        local head = vgui.Create("DPanel", right)
        head:Dock(TOP) head:SetTall(150) head:DockMargin(0, 0, 6, 8)
        head.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText("ГРУППА: " .. currentID, "GRMAdm_Sub", 14, 12, C.gold)
            draw.SimpleText("Название", "GRMAdm_Small", 14, 44, C.dim)
            draw.SimpleText("Наследует", "GRMAdm_Small", 300, 44, C.dim)
            draw.SimpleText("Иммунитет (0..100)", "GRMAdm_Small", 14, 96, C.dim)
        end

        local nameEntry = entry(head, "Название группы")
        nameEntry:SetPos(14, 62) nameEntry:SetSize(270, 28)
        nameEntry:SetText(tostring(group.name or currentID))
        nameEntry.OnChange = function(self) group.name = self:GetValue() end

        local inheritCombo = combo(head)
        inheritCombo:SetPos(300, 62) inheritCombo:SetSize(220, 28)
        inheritCombo:AddChoice("— нет —", "", (group.inherit or "") == "")
        for id in pairs(groups) do
            if id ~= currentID then inheritCombo:AddChoice(id, id, group.inherit == id) end
        end
        inheritCombo.OnSelect = function(_, _, _, value) group.inherit = value end

        local imm = vgui.Create("DNumberWang", head)
        imm:SetPos(14, 114) imm:SetSize(90, 26)
        imm:SetMin(0) imm:SetMax(100) imm:SetDecimals(0)
        imm:SetValue(tonumber(group.immunity) or 0)
        imm.OnValueChanged = function(_, v) group.immunity = math.floor(v) end

        local isAdmin = vgui.Create("DCheckBoxLabel", head)
        isAdmin:SetPos(130, 118) isAdmin:SetText("Админская группа")
        isAdmin:SetTextColor(C.text) isAdmin:SizeToContents()
        isAdmin:SetValue(group.admin == true)
        isAdmin.OnChange = function(_, v) group.admin = v == true end

        local isSuper = vgui.Create("DCheckBoxLabel", head)
        isSuper:SetPos(300, 118) isSuper:SetText("Суперадмин (все права)")
        isSuper:SetTextColor(C.gold) isSuper:SizeToContents()
        isSuper:SetValue(group.superadmin == true)
        isSuper.OnChange = function(_, v) group.superadmin = v == true end

        -- Матрица прав по категориям.
        local byCategory, order = {}, {}
        for _, perm in ipairs(perms) do
            local cat = perm.category or "Прочее"
            if not byCategory[cat] then byCategory[cat] = {} order[#order + 1] = cat end
            table.insert(byCategory[cat], perm)
        end
        table.sort(order)

        for _, cat in ipairs(order) do
            local cap = vgui.Create("DPanel", right)
            cap:Dock(TOP) cap:SetTall(26) cap:DockMargin(0, 8, 6, 2) cap:SetPaintBackground(false)
            cap.Paint = function(_, w, h)
                draw.SimpleText(string.upper(cat), "GRMAdm_Small", 2, h / 2, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            for _, perm in ipairs(byCategory[cat]) do
                local line = vgui.Create("DPanel", right)
                line:Dock(TOP) line:SetTall(38) line:DockMargin(0, 0, 6, 4)
                line.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.card)
                    draw.SimpleText(perm.label, "GRMAdm_Body", 12, 8, perm.danger and C.gold or C.text)
                    draw.SimpleText(perm.id .. "  ·  по умолчанию: " .. perm.minAccess, "GRMAdm_Small", 12, 23, C.dim)
                end

                local chk = vgui.Create("DCheckBoxLabel", line)
                chk:SetPos(line:GetWide() - 150, 10)
                chk:SetText("разрешено")
                chk:SetTextColor(C.dim)
                chk:SizeToContents()
                chk:SetValue(group.perms and group.perms[perm.id] == true)
                chk.OnChange = function(_, v)
                    group.perms = istable(group.perms) and group.perms or {}
                    group.perms[perm.id] = v == true or nil
                end
                line.PerformLayout = function(self, w) chk:SetPos(w - 150, 10) end
            end
        end

        local save = btn(right, "СОХРАНИТЬ ГРУППЫ И ПОЛНОМОЧИЯ", C.green, function()
            net.Start(AD.Net.SAVE)
                net.WriteTable({ groups = groups })
            net.SendToServer()
        end)
        save:Dock(TOP) save:SetTall(42) save:DockMargin(0, 10, 6, 12)
    end

    rebuildLeft = function()
        left:Clear()
        local ids = {}
        for id in pairs(groups) do ids[#ids + 1] = id end
        table.sort(ids)

        for _, id in ipairs(ids) do
            local g = groups[id]
            local item = vgui.Create("DButton", left)
            item:Dock(TOP) item:SetTall(46) item:DockMargin(0, 0, 6, 6) item:SetText("")
            item.Paint = function(self, w, h)
                local active = currentID == id
                draw.RoundedBox(6, 0, 0, w, h, active and C.accent or (self:IsHovered() and C.cardHover or C.card))
                draw.SimpleText(tostring(g.name or id), "GRMAdm_Body", 12, 8, C.text)
                draw.SimpleText(("%s · иммунитет %d"):format(id, tonumber(g.immunity) or 0), "GRMAdm_Small", 12, 26,
                    active and C.text or C.dim)
                if g.superadmin then
                    draw.SimpleText("SUPER", "GRMAdm_Small", w - 10, h / 2, C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
            item.DoClick = function() currentID = id rebuildLeft() rebuildRight() end
        end

        local add = btn(left, "+ НОВАЯ ГРУППА", C.green, function()
            Derma_StringRequest("Новая группа", "Идентификатор (латиница, без пробелов):", "helper", function(text)
                local id = string.lower(string.Trim(tostring(text or ""))):gsub("[^a-z0-9_]", "")
                if id == "" or groups[id] then return end
                groups[id] = {
                    id = id, name = id, color = { r = 160, g = 170, b = 185 },
                    inherit = "user", immunity = 10, admin = false, superadmin = false, perms = {},
                }
                currentID = id
                rebuildLeft()
                rebuildRight()
            end)
        end)
        add:Dock(TOP) add:SetTall(36) add:DockMargin(0, 4, 6, 4)

        local del = btn(left, "УДАЛИТЬ ГРУППУ", C.red, function()
            local base = { user = true, moderator = true, admin = true, superadmin = true }
            if base[currentID] then
                notification.AddLegacy("Базовые группы удалять нельзя", NOTIFY_ERROR, 4)
                return
            end
            groups[currentID] = nil
            currentID = "user"
            rebuildLeft()
            rebuildRight()
        end)
        del:Dock(TOP) del:SetTall(32) del:DockMargin(0, 0, 6, 4)
    end

    rebuildLeft()
    rebuildRight()
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: НАЗНАЧЕНИЯ
-----------------------------------------------------------------------
local function buildAssignments(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    local head = vgui.Create("DPanel", scroll)
    head:Dock(TOP) head:SetTall(56) head:DockMargin(0, 0, 6, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("ВЫДАННЫЕ ГРУППЫ", "GRMAdm_Sub", 14, 12, C.gold)
        draw.SimpleText("Назначение делается на вкладке «Игроки». Здесь — кто и что имеет сейчас.",
            "GRMAdm_Small", 14, 34, C.dim)
    end

    local rows = {}
    for sid, row in pairs(AD.Data and AD.Data.users or {}) do
        if isstring(sid) and istable(row) then rows[#rows + 1] = { sid = sid, row = row } end
    end
    table.sort(rows, function(a, b) return tostring(a.row.group) < tostring(b.row.group) end)

    if #rows == 0 then
        local empty = vgui.Create("DPanel", scroll)
        empty:Dock(TOP) empty:SetTall(60)
        empty.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText("Пока никому не выдано отдельной группы.", "GRMAdm_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    for _, item in ipairs(rows) do
        local line = vgui.Create("DPanel", scroll)
        line:Dock(TOP) line:SetTall(52) line:DockMargin(0, 0, 6, 6)
        line.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText(item.sid, "GRMAdm_Body", 12, 9, C.text)
            local until_ = tonumber(item.row["until"]) or 0
            local term = until_ > 0 and ("до " .. os.date("%d.%m.%Y %H:%M", until_)) or "бессрочно"
            draw.SimpleText(("%s · %s · выдал: %s"):format(tostring(item.row.group), term, tostring(item.row.by or "—")),
                "GRMAdm_Small", 12, 29, C.dim)
            if tostring(item.row.note or "") ~= "" then
                draw.SimpleText(tostring(item.row.note), "GRMAdm_Small", w - 12, 29, C.gold, TEXT_ALIGN_RIGHT)
            end
        end
    end
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: СОХРАНЕНИЯ, ФРАКЦИИ, МОДУЛИ, СУПЕРАДМИН
-----------------------------------------------------------------------
local function launchCard(parent, title, desc, command, col)
    local card = vgui.Create("DPanel", parent)
    card:Dock(TOP) card:SetTall(62) card:DockMargin(0, 0, 6, 6)
    card.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText(title, "GRMAdm_Sub", 14, 12, C.text)
        draw.SimpleText(desc, "GRMAdm_Small", 14, 34, C.dim)
    end
    local b = btn(card, "ОТКРЫТЬ", col or C.accent, function()
        if command == "/doc_admin" or command == "/doccfg" or command == "/docadmin" then
            net.Start("GRM_Doc_AdminGet")
            net.SendToServer()
        elseif command == "/comp_access" or command == "/pc_access" then
            if GRM.CompAccess and GRM.CompAccess.OpenMenu then GRM.CompAccess.OpenMenu()
            else net.Start("GRM_CompAccess_MenuReq") net.SendToServer() end
        elseif command:sub(1, 1) == "/" then
            if GRM.AdminHub and GRM.AdminHub.Launch then
                GRM.AdminHub.Launch(command)
            else
                LocalPlayer():ConCommand("say " .. command)
            end
        else
            RunConsoleCommand(command)
        end
        if IsValid(frame) then frame:Close() end
    end)
    b:Dock(RIGHT) b:SetWide(140) b:DockMargin(8, 14, 12, 14)
    return card
end

local function buildPersistence(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    launchCard(scroll, "Единое сохранение карты", "Телефоны, CCTV, завод, логистика, торговцы, дилеры и прочее", "/grm_persistence", C.gold)
    launchCard(scroll, "Сохранить всё сейчас", "Принудительная запись состояния модулей на диск", "grm_admin_save_all", C.green)
    launchCard(scroll, "Загрузить сохранение", "Восстановить состояние карты из последнего снимка", "grm_admin_load_all")
    launchCard(scroll, "Пермы оборудования", "Постоянные энтити на карте: список и чистка", "grm_perm_list")
    launchCard(scroll, "Двери: аудит и пересборка", "Диагностика дверей, дубликаты и фантомы", "grm_door_rebuild")
    launchCard(scroll, "Очистка мусорных пропов", "Убрать созданные игроками пропы (кроме постоянных)", "grm_admin_cleanup", C.red)
end

local function buildFactions(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    launchCard(scroll, "Организации", "Состав, структура, доступы, казна и права меню", "/factions", C.gold)
    launchCard(scroll, "Модели фракций", "Форма и внешний вид по отделам и ролям", "/models_admin")
    launchCard(scroll, "Вооружение фракций", "Выдача оружия по подразделениям", "/weapons_admin")
    launchCard(scroll, "Экономика фракций", "Бюджеты, налоги, зарплаты", "/salary_admin")
    launchCard(scroll, "Документы", "Бланки, удостоверения, цвета и доступы", "/doc_admin")
    launchCard(scroll, "Доступ служебных компьютеров", "Кому можно пользоваться каждым ПК на карте", "/comp_access", C.gold)
end

local function buildCatalog(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    local links = (GRM.AdminHub and GRM.AdminHub.MenuLinks) or {
        { "Организации", "/factions", "Состав и структура" },
        { "Экономика", "/salary_admin", "Зарплаты, бюджеты, банк" },
        { "Двери", "/door_access", "Доступы дверей" },
        { "Пожарные доступы", "/fire_access", "Рукава и очаги" },
        { "Магазин телефонов", "/phoneshop_admin", "Каталог трубок и АТС" },
        { "Телефонный доступ", "/phone_access", "Кто пользуется связью" },
        { "Розыск", "/wanted", "Дела и статьи" },
        { "Точки спавна", "/spawnmenu", "Точки по структуре" },
    }
    for _, m in ipairs(links) do
        if not m[4] then
            launchCard(scroll, m[1], m[3] or "", m[2], C.accent)
        end
    end
end

local function buildPhones(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    launchCard(scroll, "Магазин телефонов", "Мобильные и стационарные аппараты, цены и лимиты", "/phoneshop_admin", C.gold)
    launchCard(scroll, "Доступ к оборудованию связи", "Кто ставит АТС, таксофоны и прослушку", "/phone_access", C.accent)
    launchCard(scroll, "Прослушка помещений", "RoomTap: доступ и заявки", "roomtap_access", C.accent)
    launchCard(scroll, "Магазин прослушки", "Выдача аппаратуры оперативникам", "roomtap_shop")
    launchCard(scroll, "Торговец связью", "Перечитать ассортимент салона", "grm_phone_vendor_reload")
end

local function buildModules(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    local head = vgui.Create("DPanel", scroll)
    head:Dock(TOP) head:SetTall(70) head:DockMargin(0, 0, 6, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("СОСТОЯНИЕ СБОРКИ", "GRMAdm_Sub", 14, 12, C.gold)
        draw.SimpleText("Очередь загрузки и версии модулей. Подробности — консоль grm_boot_status.",
            "GRMAdm_Small", 14, 36, C.dim)
    end

    local versions = {
        { "Ядро GRM", GRM.Version or "—" },
        { "Boot (порядок загрузки)", GRM.Boot and GRM.Boot.Version or "—" },
        { "Perf (антифризы)", GRM.Perf and GRM.Perf.Version or "—" },
        { "Sound", GRM.Sound and GRM.Sound.Version or "—" },
        { "Админ-платформа", AD.Version or "—" },
        { "Фракции", (GRM.FactionCore and GRM.FactionCore.Version) or "—" },
        { "Пожарная служба", GRM.Fire and GRM.Fire.StatusVersion or "—" },
        { "Диспетчер вызовов", GRM.Fire and GRM.Fire.Dispatch and GRM.Fire.Dispatch.Version or "—" },
        { "Транспорт", GRM.VehicleDealer and GRM.VehicleDealer.Version or "—" },
        { "Торговцы", GRM.Vendor and GRM.Vendor.Version or "—" },
        { "Документы", GRM.Documents and GRM.Documents.Version or "—" },
    }
    for _, row in ipairs(versions) do
        local line = vgui.Create("DPanel", scroll)
        line:Dock(TOP) line:SetTall(34) line:DockMargin(0, 0, 6, 4)
        line.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText(row[1], "GRMAdm_Body", 12, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("v" .. tostring(row[2]), "GRMAdm_Small", w - 12, h / 2, C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    launchCard(scroll, "Очередь загрузки", "Показать время каждой задачи старта в консоли", "grm_boot_status", C.accent)
    launchCard(scroll, "Проверка звуков", "Каких звуковых файлов не хватает", "grm_sound_check", C.accent)
end

local function buildSuper(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    if not can("cheat.god") then
        local warn = vgui.Create("DPanel", scroll)
        warn:Dock(TOP) warn:SetTall(60)
        warn.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText("Раздел доступен только суперадминистратору.", "GRMAdm_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local head = vgui.Create("DPanel", scroll)
    head:Dock(TOP) head:SetTall(64) head:DockMargin(0, 0, 6, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("ВОЗМОЖНОСТИ СУПЕРАДМИНИСТРАТОРА", "GRMAdm_Sub", 14, 12, C.gold)
        draw.SimpleText("Всё действие пишется в аудит. Применяется к себе, если игрок не выбран.",
            "GRMAdm_Small", 14, 36, C.dim)
    end

    local me = tostring(LocalPlayer():SteamID64() or "")
    local rows = {
        { "Режим бога (себе)", "god", C.gold, {} },
        { "Невидимость (себе)", "cloak", C.gold, {} },
        { "Строительный режим", "buildmode", C.gold, {} },
        { "Телепорт в точку прицела", "tppos", C.accent, {} },
        { "Заморозить всех", "freezeall", C.red, {} },
        { "Разморозить всех", "unfreezeall", C.green, {} },
        { "Очистить мусорные пропы", "cleanup", C.red, {} },
    }
    for _, row in ipairs(rows) do
        local card = vgui.Create("DPanel", scroll)
        card:Dock(TOP) card:SetTall(50) card:DockMargin(0, 0, 6, 6)
        card.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText(row[1], "GRMAdm_Body", 14, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local b = btn(card, "ВЫПОЛНИТЬ", row[3], function() act(row[2], me, row[4]) end)
        b:Dock(RIGHT) b:SetWide(150) b:DockMargin(8, 9, 12, 9)
    end
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: АНАЛИЗ НАГРУЗКИ
-----------------------------------------------------------------------
local function buildAnalytics(pnl)
    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    local AN = GRM.Analytics
    local head = vgui.Create("DPanel", scroll)
    head:Dock(TOP) head:SetTall(84) head:DockMargin(0, 0, 6, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("АНАЛИЗ НАГРУЗКИ", "GRMAdm_Sub", 14, 12, C.gold)
        local snap = AN and AN.Last
        if not snap then
            draw.SimpleText("Сбор ещё не начался — данные появятся через несколько секунд.",
                "GRMAdm_Small", 14, 38, C.dim)
            return
        end
        draw.SimpleText(("Кадр/тик: среднее %.2f мс · максимум %.1f мс · всплесков %d · фоновых задач %d")
            :format(snap.tickAvgMs or 0, snap.tickMaxMs or 0, snap.spikes or 0, snap.jobs or 0),
            "GRMAdm_Small", 14, 38, C.text)
        draw.SimpleText(("Сущности: %d (GRM %d, пропов %d, транспорт %d) · двери: %d, фантомов %d")
            :format(snap.entities and snap.entities.total or 0, snap.entities and snap.entities.grm or 0,
                snap.entities and snap.entities.props or 0, snap.entities and snap.entities.vehicles or 0,
                snap.doors and snap.doors.total or 0, snap.doors and snap.doors.suspectPhantom or 0),
            "GRMAdm_Small", 14, 58, C.dim)
    end

    local function tool(title, desc, command, col)
        local card = vgui.Create("DPanel", scroll)
        card:Dock(TOP) card:SetTall(58) card:DockMargin(0, 0, 6, 6)
        card.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText(title, "GRMAdm_Body", 14, 12, C.text)
            draw.SimpleText(desc, "GRMAdm_Small", 14, 32, C.dim)
        end
        local b = btn(card, "ВЫПОЛНИТЬ", col or C.accent, function()
            RunConsoleCommand(unpack(string.Explode(" ", command)))
            chat.AddText(C.gold, "[GRM] ", C.text, "Отчёт напечатан в консоли (~): ", C.dim, command)
        end)
        b:Dock(RIGHT) b:SetWide(150) b:DockMargin(8, 11, 12, 11)
    end

    tool("Общая сводка", "Тайминги, сущности, двери, игроки, топ событий", "grm_analyze", C.gold)
    tool("Сущности по классам", "Что именно живёт на карте и в каком количестве", "grm_analyze_ents")
    tool("Двери", "Записи, бесхозные, парные и подозрение на фантомы", "grm_analyze_doors")
    tool("Игроки", "Движение, действия, состояние, пинг, AFK", "grm_analyze_players")
    tool("События и сеть", "Счётчики событий и последний профиль net", "grm_analyze_events")
    tool("Профиль хуков (10 с)", "Сколько миллисекунд съедает каждый хук GRM", "grm_analyze_hooks 10", C.orange)
    tool("Профиль сети (10 с)", "Какие net-строки шлют больше всего данных", "grm_analyze_net 10", C.orange)
    tool("Выгрузить срез", "Полный отчёт в data/grm_analytics/*.json", "grm_analyze_dump", C.green)
    tool("Фризы: отчёт", "Всплески времени кадра со срезом окружения", "grm_perf_report")
    tool("Очередь фоновых задач", "Что сейчас распределяется по кадрам", "grm_perf_queue")
    tool("Очередь загрузки карты", "Порядок и время стартовых задач", "grm_boot_status")
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: ПЕРСОНАЖИ
-----------------------------------------------------------------------
local CHAR_ROSTER = { query = "", accounts = {} }

net.Receive("GRM_Char_AdminRoster", function()
    CHAR_ROSTER = net.ReadTable() or { query = "", accounts = {} }
    hook.Run("GRM_AdminCharsUpdated")
end)

local function buildChars(pnl)
    if not can("char.manage") then
        local warn = vgui.Create("DLabel", pnl)
        warn:Dock(TOP) warn:SetTall(40) warn:SetFont("GRMAdm_Sub") warn:SetTextColor(C.red)
        warn:SetText("Нужно право «Управление персонажами и РП-именами».")
        return
    end

    local head = vgui.Create("DPanel", pnl)
    head:Dock(TOP) head:SetTall(86) head:DockMargin(0, 0, 0, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("КОНТРОЛЬ ПЕРСОНАЖЕЙ", "GRMAdm_Sub", 14, 10, C.gold)
        draw.SimpleText("Поиск по SteamID64, нику или РП-имени. Пустой запрос — все персонажи.",
            "GRMAdm_Small", 14, 32, C.dim)
    end

    local search = entry(head, "Ник, РП-имя или SteamID64…")
    search:SetPos(14, 50) search:SetSize(420, 28)
    search:SetText(tostring(CHAR_ROSTER.query or ""))

    local find = btn(head, "НАЙТИ", C.accent, function()
        act("char_search", "", { query = search:GetValue() })
    end)
    find:SetPos(442, 50) find:SetSize(110, 28)

    local hint = vgui.Create("DLabel", head)
    hint:SetFont("GRMAdm_Small"); hint:SetTextColor(C.dim)
    hint:SetText("В колонке «МОДЕЛЬ» — только имя файла; полный путь открывается кнопкой.")
    hint:SetPos(570, 56) hint:SetSize(520, 20)

    -- Резиновая сетка: блок кнопок фиксированной ширины справа.
    local BTN_W, BTN_H, BTN_GAP = 78, 28, 6
    local BTN_BLOCK = BTN_W * 5 + BTN_GAP * 4
    local COL_FAC, COL_MODEL = 210, 230
    local ROW_H = 40

    local scroll = vgui.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    local function slotRow(parent, acc, sl, i, total)
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP) row:DockMargin(12, 0, 12, i == total and 6 or 4) row:SetTall(ROW_H)
        row.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.cardLight)
            local xF = w - BTN_BLOCK - COL_FAC - COL_MODEL
            local xM = w - BTN_BLOCK - COL_MODEL
            if not sl.exists then
                draw.SimpleText("Пустой слот " .. i, "GRMAdm_Body", 10, h / 2 - 8, C.dim)
                draw.SimpleText("—", "GRMAdm_Small", xF, h / 2 - 7, C.dim)
                draw.SimpleText("—", "GRMAdm_Small", xM, h / 2 - 7, C.dim)
                return
            end
            draw.SimpleText(sl.name ~= "" and sl.name or ("Слот " .. i), "GRMAdm_Body", 10, h / 2 - 8, C.text)
            if sl.active then
                draw.SimpleText("● активен", "GRMAdm_Small", 260, h / 2 - 7, C.green)
            end
            local fac = (sl.factionName ~= "" and sl.factionName) or "гражданин"
            draw.SimpleText(fac, "GRMAdm_Small", xF, h / 2 - 7,
                (sl.factionName ~= "") and C.gold or C.dim)
            local m = sl.model ~= "" and (string.match(sl.model, "([^/\\]+)$") or sl.model) or "по умолчанию"
            draw.SimpleText(m, "GRMAdm_Small", xM, h / 2 - 7, C.dim)
        end

        if not sl.exists then return row end

        local function q() return search:GetValue() end
        local bxs = {}
        local function placeButtons()
            local w = row:GetWide()
            for k, b in ipairs(bxs) do
                b:SetPos(w - BTN_BLOCK + (k - 1) * (BTN_W + BTN_GAP), (ROW_H - BTN_H) / 2)
            end
        end

        local rename = btn(row, "ИМЯ", C.accent, function()
            Derma_StringRequest("РП-имя", "Новое имя и фамилия для " .. tostring(sl.id),
                sl.name or "", function(text)
                    act("char_rename", "", { sid = acc.sid, slot = sl.id, name = text, query = q() })
                end)
        end) rename:SetSize(BTN_W, BTN_H); bxs[#bxs + 1] = rename

        local mdl = btn(row, "МОДЕЛЬ", C.cardHov, function()
            Derma_StringRequest("Модель персонажа",
                "Путь к модели (.mdl). Пусто — снять принудительную.",
                tostring(sl.model or ""), function(text)
                    act("char_model", "", { sid = acc.sid, slot = sl.id, model = string.Trim(text or ""), query = q() })
                end)
        end) mdl:SetSize(BTN_W, BTN_H); bxs[#bxs + 1] = mdl

        local fac = btn(row, "ФРАКЦИЯ", C.cardHov, function()
            Derma_StringRequest("Фракция",
                "Ключ фракции (как в /factions). Пусто = гражданский (без сброса прав).",
                tostring(sl.factionName or ""), function(text)
                    act("char_faction", "", { sid = acc.sid, slot = sl.id, faction = string.Trim(text or ""), query = q() })
                end)
        end) fac:SetSize(BTN_W, BTN_H); bxs[#bxs + 1] = fac

        local accb = btn(row, "ДОСТУП", C.cardHov, function()
            Derma_StringRequest("Персональный доступ",
                "Capability (например wanted.civil.edit). Префикс «-» снимает право.",
                "", function(text)
                    local v = string.Trim(text or "")
                    local allow = not string.StartWith(v, "-")
                    local cap = allow and v or string.sub(v, 2)
                    act("char_access", "", { sid = acc.sid, slot = sl.id, capability = cap, allow = allow, query = q() })
                end)
        end) accb:SetSize(BTN_W, BTN_H); bxs[#bxs + 1] = accb

        local del = btn(row, "УДАЛИТЬ", C.red, function()
            Derma_Query(("Удалить персонажа «%s» (%s)?\nИмя, модель, фракция и персональные права очищены.")
                :format(sl.name ~= "" and sl.name or sl.id, sl.id),
                "Удаление персонажа", "Удалить", function()
                    act("char_delete", "", { sid = acc.sid, slot = sl.id, query = q() })
                end, "Отмена")
        end) del:SetSize(BTN_W, BTN_H); bxs[#bxs + 1] = del

        row.PerformLayout = placeButtons
        return row
    end

    local function paintRoster()
        if not IsValid(scroll) then return end
        scroll:Clear()
        local accounts = istable(CHAR_ROSTER.accounts) and CHAR_ROSTER.accounts or {}

        if #accounts == 0 then
            local empty = vgui.Create("DPanel", scroll)
            empty:Dock(TOP) empty:SetTall(70)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("Ничего не найдено. Введите запрос и нажмите «Найти».",
                    "GRMAdm_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return
        end

        for _, acc in ipairs(accounts) do
            local slots = acc.slots or {}
            local rows = 0
            for _ in ipairs(slots) do rows = rows + 1 end

            local card = vgui.Create("DPanel", scroll)
            card:Dock(TOP) card:DockMargin(0, 0, 6, 8)
            card:SetTall(36 + (rows > 0 and (22 + 4) or 0) + rows * (ROW_H + 4) + 6)
            card.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText(acc.nick ~= "" and acc.nick or acc.sid, "GRMAdm_Sub", 14, 8, C.text)
                draw.SimpleText(acc.online and "в сети" or "офлайн", "GRMAdm_Small",
                    14 + ((acc.nick ~= "" and acc.nick or acc.sid):len() * 8 + 14), 12,
                    acc.online and C.green or C.dim)
                draw.SimpleText("SteamID64: " .. tostring(acc.sid), "GRMAdm_Small", 14, 26, C.dim)
            end

            if rows == 0 then goto nextacc end

            local bar = vgui.Create("DPanel", card)
            bar:Dock(TOP) bar:DockMargin(12, 36, 12, 4) bar:SetTall(20)
            bar.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(28, 36, 50))
                draw.SimpleText("СЛОТ / ИМЯ", "GRMAdm_Small", 10, 3, C.dim)
                draw.SimpleText("ФРАКЦИЯ", "GRMAdm_Small",
                    w - BTN_BLOCK - COL_FAC - COL_MODEL, 3, C.dim)
                draw.SimpleText("МОДЕЛЬ", "GRMAdm_Small",
                    w - BTN_BLOCK - COL_MODEL, 3, C.dim)
            end

            for i, sl in ipairs(slots) do
                slotRow(card, acc, sl, i, rows)
            end
            ::nextacc::
        end
    end

    paintRoster()
    hook.Add("GRM_AdminCharsUpdated", "GRM_AdminPanel_Chars", function()
        if not IsValid(scroll) then
            hook.Remove("GRM_AdminCharsUpdated", "GRM_AdminPanel_Chars")
            return
        end
        paintRoster()
    end)
    scroll.OnRemove = function() hook.Remove("GRM_AdminCharsUpdated", "GRM_AdminPanel_Chars") end
    -- сразу запрашиваем список (пустой запрос — все персонажи)
    act("char_search", "", { query = search:GetValue() })
end

-----------------------------------------------------------------------
-- OKNO
-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- РАЗДЕЛ: АНТИЧИТ (заказ 02.09) — лента подозрений + профили GRM.AC
-----------------------------------------------------------------------
local acNet = function(key)
    local n = GRM.AntiCheat and GRM.AntiCheat.Net and GRM.AntiCheat.Net[key]
    return n or ({ FEED = "GRM_AC_Feed", QUERY = "GRM_AC_Query", CMD = "GRM_AC_Cmd" })[key]
end
AD.ACPack = AD.ACPack or { rows = {}, feed = {} }

local function acSendCmd(line)
    net.Start(acNet("CMD"))
        net.WriteString(tostring(line))
    net.SendToServer()
end
local function acQuery()
    net.Start(acNet("QUERY"))
    net.SendToServer()
end

-- Имена каналов — литералами: общий модуль античита грузится ПОЗЖЕ этого
-- файла (lua/autorun/client/* раньше lua/autorun/sh_*), в рантайме таблицы
-- уже нет — только строковые константы переживают порядок загрузки.
net.Receive("GRM_AC_Feed", function()
    local pack = net.ReadTable()
    if not istable(pack) then return end
    if pack.rows then
        AD.ACPack = pack
        hook.Run("GRM_AC_Pack")
    elseif isstring(pack.reply) then
        hook.Run("GRM_AC_Reply", pack.reply)
    end
end)

local function buildAntiCheat(pnl)
    local isAdm = can("anticheat.admin")
    local head = vgui.Create("DPanel", pnl)
    head:Dock(TOP) head:SetTall(56) head:SetPaintBackground(false)
    head.Paint = function(_, w, h)
        local pack = AD.ACPack or {}
        draw.SimpleText(("Античит · подозреваемых %d · политика %s · режим %s")
            :format(#(pack.rows or {}),
                (pack.enabled ~= false) and "включён" or "выключен",
                ({ "только журнал", "лента", "кик", "деморган", "дем+железо" })[tonumber(pack.action) or 1] or "?"),
            "GRMAdm_Sub", 2, 8, C.text)
        draw.SimpleText("Пороги: 25 — в ленту · 80 — наказание. Silent-aim, perfect-lock, стены, телепорты, solids, rapidfire. Память клиента не сканируется — это движок не может, а не мы не хотим.",
            "GRMAdm_Small", 2, 30, C.dim)
    end
    local bar = vgui.Create("DPanel", head)
    bar:Dock(RIGHT) bar:SetWide(320) bar:SetPaintBackground(false)
    local b1 = vgui.Create("DButton", bar) b1:Dock(LEFT) b1:SetWide(96)
    b1:SetText("Обновить") b1:SetFont("GRMAdm_Btn") b1.DoClick = acQuery
    local b2 = vgui.Create("DButton", bar) b2:Dock(LEFT) b2:SetWide(110) b2:DockMargin(6, 0, 0, 0)
    b2:SetText(isAdm and "Очистить всех" or "нет права")
    b2:SetFont("GRMAdm_Btn") b2:SetEnabled(isAdm)
    b2.DoClick = function() acSendCmd("clear all") acQuery() end
    local rowsBox = vgui.Create("DScrollPanel", pnl)
    rowsBox:Dock(TOP) rowsBox:SetTall(math.floor(pnl:GetTall() * 0.55))

    local feedBox = vgui.Create("DScrollPanel", pnl)
    feedBox:Dock(BOTTOM) feedBox:SetTall(150)
    feedBox.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("ЛЕНТА СОБЫТИЙ", "GRMAdm_Small", 10, 8, C.gold)
    end

    local function sevColor(sev)
        if sev == "suspect" then return C.orange end
        if sev == "action" then return C.red end
        return C.dim
    end

    local function render()
        if not IsValid(pnl) then return end
        rowsBox:Clear() feedBox:Clear()
        local pack = AD.ACPack or {}
        local rows = pack.rows or {}
        if #rows == 0 then
            local e = vgui.Create("DLabel", rowsBox)
            e:Dock(TOP) e:SetTall(30) e:SetFont("GRMAdm_Body") e:SetTextColor(C.dim)
            e:SetText("Чисто. Профили с ненулевым счётом появятся здесь.")
        end
        for _, row in ipairs(rows) do
            local line = vgui.Create("DPanel", rowsBox)
            line:Dock(TOP) line:SetTall(52) line:DockMargin(0, 0, 0, 5)
            line.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(tostring(row.nick), "GRMAdm_Sub", 12, 7, C.text)
                draw.SimpleText(("score %d · %s · %s"):format(tonumber(row.score) or 0,
                    tostring(row.kind or ""), tostring(row.note or "")),
                    "GRMAdm_Small", 12, 30, sevColor((tonumber(row.score) or 0) >= 80 and "action" or "suspect"))
                local barW = math.Clamp((tonumber(row.score) or 0) / 240 * 140, 2, 140)
                draw.RoundedBox(3, w - 170, 18, 140, 8, C.sidebar)
                draw.RoundedBox(3, w - 170, 18, barW, 8,
                    (tonumber(row.score) or 0) >= 80 and C.red or C.orange)
            end
            if isAdm then
                local clear = vgui.Create("DButton", line)
                clear:Dock(RIGHT) clear:SetWide(86) clear:DockMargin(4, 12, 10, 12)
                clear:SetText("забыть") clear:SetFont("GRMAdm_Btn")
                clear.DoClick = function() acSendCmd("clear " .. tostring(row.sid)) acQuery() end
            end
            local snap = vgui.Create("DButton", line)
            snap:Dock(RIGHT) snap:SetWide(96) snap:DockMargin(4, 12, 4, 12)
            snap:SetText("железо") snap:SetFont("GRMAdm_Btn")
            snap.DoClick = function()
                if not can("mod.ban") then return end
                for _, p in ipairs(player.GetAll()) do
                    if tostring(p:SteamID64() or "") == tostring(row.sid) then
                        act("machine", row.sid)
                        return
                    end
                end
                chat.AddText(C.orange, "[AC] игрок не в сети — снимок есть только в записях бана")
            end
        end
        for _, ev in ipairs(pack.feed or {}) do
            local e = vgui.Create("DLabel", feedBox)
            e:Dock(TOP) e:SetTall(18) e:DockMargin(10, 0, 10, 0)
            e:SetFont("GRMAdm_Small") e:SetTextColor(sevColor(ev.sev))
            e:SetText(("%s · %s"):format(ev.t and os.date("%H:%M:%S", tonumber(ev.t) or 0) or "?",
                tostring(ev.text or "")))
        end
    end
    render()
    acQuery()
    local function onPack() render() end
    hook.Add("GRM_AC_Pack", "GRM_AdminPanel_AC", onPack)
    hook.Add("GRM_AC_Reply", "GRM_AdminPanel_AC", function(text)
        if IsValid(pnl) then chat.AddText(C.gold, "[AC] ", C.text, tostring(text)) end
    end)
end

-----------------------------------------------------------------------
-- РАЗДЕЛ: КОНСОЛЬ СЕРВЕРА (заказ 02.09; право server.console)
-----------------------------------------------------------------------
AD.ConsoleLines = AD.ConsoleLines or nil
net.Receive("GRM_Admin_ConsoleOut", function()
    local pack = net.ReadTable()
    if not istable(pack) then return end
    local stamp = os.date("%H:%M:%S", tonumber(pack.t) or 0)
    local block = ("%s [%s] %s\n%s"):format(stamp, tostring(pack.admin or "?"),
        tostring(pack.line or ""), tostring(pack.text or ""))
    AD.ConsoleLines = AD.ConsoleLines or {}
    AD.ConsoleLines[#AD.ConsoleLines + 1] = block
    hook.Run("GRM_AdminConsoleLine", block)
end)

local function buildConsole(pnl)
    local warn = vgui.Create("DPanel", pnl)
    warn:Dock(TOP) warn:SetTall(34) warn:SetPaintBackground(false)
    warn.Paint = function(_, w, h)
        draw.SimpleText("Каждая строка уходит в движковый консоль-лог сервера и в аудит. Тишины не будет — коллеги с этим правом видят эхо.",
            "GRMAdm_Small", 2, h / 2, C.orange, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local out = vgui.Create("DTextEntry", pnl)
    out:Dock(FILL) out:DockMargin(0, 6, 0, 6)
    out:SetMultiline(true) out:SetReadOnly(true) out:SetFont("GRMAdm_Body")
    out:SetTextColor(C.text) out:SetBackgroundColor(C.sidebar)
    for _, l in ipairs(AD.ConsoleLines or {}) do out:SetText(out:GetValue() .. l .. "\n") end

    local rowIn = vgui.Create("DPanel", pnl)
    rowIn:Dock(BOTTOM) rowIn:SetTall(34) rowIn:SetPaintBackground(false)
    local input = vgui.Create("DTextEntry", rowIn)
    input:Dock(FILL) input:DockMargin(0, 3, 96, 3)
    input:SetFont("GRMAdm_Body") input:SetPlaceholderText("status · get <cvar> · set <cvar> <val> · bans · ac list · любая консольная строка")
    input:SetTextColor(C.text) input:SetBackgroundColor(C.card)
    local send = vgui.Create("DButton", rowIn)
    send:Dock(RIGHT) send:SetWide(88) send:SetText("выполнить") send:SetFont("GRMAdm_Btn")
    local function fire()
        local line = string.Trim(tostring(input:GetValue() or ""))
        if line == "" then return end
        input:SetText("")
        net.Start("GRM_Admin_Console")
            net.WriteString(line)
        net.SendToServer()
    end
    send.DoClick = fire
    input.OnEnter = fire

    local chips = vgui.Create("DPanel", pnl)
    chips:Dock(BOTTOM) chips:SetTall(26) chips:SetPaintBackground(false)
    for _, label in ipairs({ "status", "bans", "ac list", "ac status", "get grm_ac_action", "history" }) do
        local c = vgui.Create("DButton", chips)
        c:Dock(LEFT) c:DockMargin(0, 2, 5, 2) c:SetWide(math.max(56, 7 + #label * 6))
        c:SetText(label) c:SetFont("GRMAdm_Small")
        c.DoClick = function()
            net.Start("GRM_Admin_Console")
                net.WriteString(label)
            net.SendToServer()
        end
    end
    local function onLine(block)
        if not IsValid(out) then return end
        out:SetText(out:GetValue() .. block .. "\n")
        if IsValid(out.VBar) then out.VBar:SetScroll(out.VBar:GetCanvas():GetTall()) end
    end
    hook.Add("GRM_AdminConsoleLine", "GRM_AdminPanel_Console", onLine)
end

function AD.OpenPanel()
    if not can("menu.open") then
        notification.AddLegacy("Нет доступа к админ-меню", NOTIFY_ERROR, 4)
        return
    end
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_admin_panel", frame) end
    frame:SetSize(math.Clamp(ScrW() * 0.9, 1100, 1560), math.Clamp(ScrH() * 0.88, 700, 980))
    frame:Center()
    frame:MakePopup()
    frame:SetTitle("")
    frame:SetSizable(true)
    frame:ShowCloseButton(false)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 46, C.sidebar, true, true, false, false)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("GRM · ЦЕНТР АДМИНИСТРИРОВАНИЯ", "GRMAdm_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Ваша группа: " .. tostring(AD.GroupOf and AD.GroupOf(LocalPlayer()) or LocalPlayer():GetUserGroup()),
            "GRMAdm_Small", w - 60, 23, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(34, 30) close:SetText("")
    close.Paint = function(self, w, h)
        if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end
        draw.SimpleText("✕", "GRMAdm_Btn", w / 2, h / 2, self:IsHovered() and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() frame:Close() end
    frame.PerformLayout = function(self, w) if IsValid(close) then close:SetPos(w - 44, 8) end end
    frame.OnRemove = function()
        hook.Remove("GRM_AdminPlayersUpdated", "GRM_AdminPanel_Players")
        selected = nil
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(0, 46, 0, 0) body:SetPaintBackground(false)

    local nav = vgui.Create("DScrollPanel", body)
    nav:Dock(LEFT) nav:SetWide(230)
    nav.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, C.sidebar)
        surface.SetDrawColor(C.border)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end

    content = vgui.Create("DPanel", body)
    content:Dock(FILL) content:DockMargin(12, 10, 12, 12) content:SetPaintBackground(false)

    local buttons = {}
    local function addTab(key, label, perm, builder)
        if perm and not can(perm) then return end
        local b = vgui.Create("DButton", nav)
        b:Dock(TOP) b:SetTall(38) b:DockMargin(6, 4, 8, 0) b:SetText("")
        b.Paint = function(self, w, h)
            local active = selected == key
            if active then draw.RoundedBox(6, 0, 0, w, h, C.accent)
            elseif self:IsHovered() then draw.RoundedBox(6, 0, 0, w, h, C.cardHover) end
            draw.SimpleText(label, "GRMAdm_Btn", 14, h / 2, active and color_white or (self:IsHovered() and C.text or C.dim),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function()
            selected = key
            -- Уходя с раздела, снимаем его подписки — иначе они продолжают
            -- работать с уже удалёнными панелями.
            hook.Remove("GRM_AdminPlayersUpdated", "GRM_AdminPanel_Players")
            content:Clear()
            if isfunction(builder) then builder(content) end
        end
        buttons[key] = b
        if not selected then
            selected = key
            if isfunction(builder) then builder(content) end
        end
    end

    addTab("players", "Игроки", "menu.open", buildPlayers)
    addTab("chars", "Персонажи", "char.manage", buildChars)
    addTab("privs", "Привилегии", "acl.groups", buildPrivileges)
    addTab("assign", "Назначения", "acl.assign", buildAssignments)
    addTab("persist", "Сохранения и карта", "server.persistence", buildPersistence)
    addTab("factions", "Фракционный контроль", "server.factions", buildFactions)
    addTab("catalog", "Каталог меню", "menu.open", buildCatalog)
    addTab("phones", "Связь и телефоны", "menu.open", buildPhones)
    addTab("modules", "Модули сборки", "menu.modules", buildModules)
    addTab("analytics", "Анализ нагрузки", "menu.modules", buildAnalytics)
    addTab("super", "Суперадмин", "cheat.god", buildSuper)
    addTab("anticheat", "Античит", "anticheat.see", buildAntiCheat)
    addTab("console", "Консоль", "server.console", buildConsole)

    AD.Request()
end

hook.Add("GRM_AdminDataUpdated", "GRM_AdminPanel_Refresh", function()
    -- Справочники (группы, права) приходят несколько раз за сессию. Полная
    -- пересборка раздела на каждый такой пакет заставляла вкладку «моргать»
    -- и сбрасывала выбранного игрока. Раздел «Игроки» обновляет себя сам
    -- через GRM_AdminPlayersUpdated, поэтому здесь ничего не трогаем.
    if not (IsValid(frame) and IsValid(content)) then return end
    if selected ~= "players" then return end
    hook.Run("GRM_AdminPlayersUpdated")
end)

concommand.Add("grm_admin_panel", function() AD.OpenPanel() end)

hook.Add("PlayerSayTransform", "GRM_AdminPanel_Chat", function(ply, pack)
    if not istable(pack) or not isstring(pack[1]) then return end
    local low = string.lower(string.Trim(pack[1]))
    if low == "/admin" or low == "/админ" or low == "/grm_admin" or low == "/grm_admin_panel" then
        AD.OpenPanel()
        pack[1] = ""
        pack.SkipPlayerSay = true
    end
end)

print("[GRM Admin Panel] v1.0.0 loaded")
