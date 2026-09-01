--[[--------------------------------------------------------------------
    FFD Scanner — Toolgun Module (Код 107)
    Инструмент установки сканера фракционного доступа (grm_scanner):
    никакого ввода кода — человек подходит и жмёт [E], сканер решает по
    его фракции (белый список ниже). Кейпад (FFD Keypad) оставлен только
    для PIN-кода — это ПАРА инструментов, а не конкуренты.

    ЛКМ: Разместить Сканер на поверхности
    ПКМ: Скопировать настройки с существующего Сканера
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.ffd_scanner.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["key_granted"] = "1"
TOOL.ClientConVar["key_denied"] = "2"
TOOL.ClientConVar["hold_time"] = "4"
TOOL.ClientConVar["faction"] = ""

if CLIENT then
    language.Add("tool.ffd_scanner.name", "GRM Сканер фракций")
    language.Add("tool.ffd_scanner.desc", "Размещает сканер: человек жмёт [E] — сканер проверяет его фракцию по белому списку и открывает двери")
    language.Add("tool.ffd_scanner.0", "ЛКМ: Установить Сканер | ПКМ: Скопировать настройки с объекта")
end

-- ============================================================
-- СЕРВЕРНАЯ ЛОГИКА СОЗДАНИЯ СКАНЕРА
-- ============================================================
--[[ СПИСОК ОРГАНИЗАЦИЙ ДЛЯ ПАНЕЛИ (переработка 21.08).

     Раньше панель строила список из клиентского кэша `FactionsData`. На
     живом сервере его к моменту открытия инструмента может не быть вовсе
     (публичный синк приходит позже, а после смены карты — не сразу), и
     человек видел пустое место или поле «впишите вручную». Теперь список
     запрашивается У СЕРВЕРА: он всегда знает правду.

     Заодно приходят человеческие названия и тег организации, чтобы в списке
     было «Полевая Жандармерия [ФЖ]», а не внутренний ключ. ]]
local NET_LIST_REQ = "GRM_ScannerTool_ListReq"
local NET_LIST = "GRM_ScannerTool_List"

if SERVER then
    util.AddNetworkString(NET_LIST_REQ)
    util.AddNetworkString(NET_LIST)

    local function factionRows()
        local rows = {}
        for name, f in pairs(istable(Factions) and Factions or {}) do
            if istable(f) then
                local display = name
                if GRM and GRM.Factions and GRM.Factions.DisplayName then
                    display = GRM.Factions.DisplayName(name) or name
                end
                local members = 0
                for _ in pairs(istable(f.Members) and f.Members or {}) do members = members + 1 end
                rows[#rows + 1] = {
                    name = tostring(name),
                    display = tostring(display),
                    tag = tostring(f.Tag or ""),
                    members = members,
                }
            end
        end
        table.sort(rows, function(a, b) return string.lower(a.display) < string.lower(b.display) end)
        return rows
    end

    net.Receive(NET_LIST_REQ, function(_, ply)
        if not IsValid(ply) then return end
        if GRM and GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "scanner.tool.list", { rate = 1, burst = 3 }, {}) then return end
        net.Start(NET_LIST)
        net.WriteTable(factionRows())
        net.Send(ply)
    end)

    function TOOL:SpawnScanner(ply, trace, kGranted, kDenied, holdTime, faction)
        if not IsValid(ply) or not trace.Hit then return false end

        local ent = ents.Create("grm_scanner")
        if not IsValid(ent) then return false end

        -- та же доказанная геометрия, что у кейпада (находка 121):
        -- модель лицом в +X, чистый HitNormal:Angle() без поворотов
        ent:SetPos(trace.HitPos + trace.HitNormal * 1.2)
        ent:SetAngles(trace.HitNormal:Angle())

        ent.ScannerOwner = ply
        ent.KeyGranted = math.Clamp(tonumber(kGranted) or 1, 1, 9)
        ent.KeyDenied = math.Clamp(tonumber(kDenied) or 2, 1, 9)
        ent.HoldTime = math.max(0.5, tonumber(holdTime) or 4)

        ent:Spawn()
        ent:Activate()

        ent:SetFaction(tostring(faction or ""))

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false) -- автозаморозка на стене
        end

        if duplicator and duplicator.StoreEntityModifier then
            duplicator.StoreEntityModifier(ent, "GRM_ScannerData", {
                faction = tostring(faction or ""),
                granted = tonumber(ent.KeyGranted) or 1,
                denied  = tonumber(ent.KeyDenied) or 2,
                hold    = tonumber(ent.HoldTime) or 4,
                owner   = IsValid(ply) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or "") or "",
            })
        end

        undo.Create("FFD Scanner")
            undo.AddEntity(ent)
            undo.SetPlayer(ply)
        undo.Finish()

        return true
    end
end

function TOOL:LeftClick(trace)
    if not trace.Hit then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    local kGranted = self:GetClientNumber("key_granted", 1)
    local kDenied = self:GetClientNumber("key_denied", 2)
    local holdTime = self:GetClientNumber("hold_time", 4)
    local faction = self:GetClientInfo("faction")

    local ok = self:SpawnScanner(ply, trace, kGranted, kDenied, holdTime, faction)

    if ok and GRM and GRM.Notify then
        GRM.Notify(ply, "FFD Scanner установлен — доступ по фракции стоящего рядом!", 100, 220, 100)
    end

    return ok
end

function TOOL:RightClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or ent:GetClass() ~= "grm_scanner" then return false end

    if SERVER then
        local ply = self:GetOwner()
        ply:ConCommand(string.format('ffd_scanner_faction %q', tostring(ent:GetFaction() or "")))
        ply:ConCommand(string.format('ffd_scanner_hold_time %s', tostring(ent.HoldTime or 4)))
        ply:ConCommand(string.format('ffd_scanner_key_granted %s', tostring(ent.KeyGranted or 1)))
        ply:ConCommand(string.format('ffd_scanner_key_denied %s', tostring(ent.KeyDenied or 2)))

        if GRM and GRM.Notify then
            GRM.Notify(ply, "Настройки Сканера скопированы!", 100, 220, 255)
        end
    end

    return true
end

-- ============================================================
-- VGUI ПАНЕЛЬ НАСТРОЙКИ В МЕНЮ ИНСТРУМЕНТОВ
-- ============================================================
--[[ Панель инструмента: живой список организаций с поиском, отметками и
     счётчиком выбранного. Ключевое отличие от прошлой версии — данные
     приходят с сервера, а не берутся из клиентского кэша. ]]
--[[ Список держим в ЛОКАЛЬНОЙ таблице файла, а не в поле TOOL.

     У TOOL в GMod (и в стендах) стоит метатаблица-заглушка: обращение к
     несуществующему полю возвращает функцию, а не nil. Из-за этого
     `ipairs(TOOL.FactionRows or {})` падал с «table expected, got function».
     Локальная переменная от таких сюрпризов защищена, а поле TOOL остаётся
     как витрина для других модулей. ]]
local factionRows = {}

local function requestFactions()
    if not CLIENT then return end
    net.Start(NET_LIST_REQ)
    net.SendToServer()
end

if CLIENT then
    net.Receive(NET_LIST, function()
        local rows = net.ReadTable()
        factionRows = istable(rows) and rows or {}
        hook.Run("GRM_ScannerTool_ListUpdated", factionRows)
    end)

    function TOOL.RequestFactions()
        requestFactions()
    end
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", { Description = "Сканер решает по организации стоящего рядом человека (проверка строгая — владелец и админ тоже сканируются). Ввод кода ему не нужен." })

    local function checkedSet()
        local cur = {}
        local cv = GetConVar and GetConVar("ffd_scanner_faction")
        for name in string.gmatch((cv and cv:GetString()) or "", "([^,]+)") do
            local trimmed = string.Trim(name)
            if trimmed ~= "" then cur[trimmed] = true end
        end
        return cur
    end

    local function writeChecked(set)
        local out = {}
        for name, on in pairs(set) do
            if on then out[#out + 1] = name end
        end
        table.sort(out)
        RunConsoleCommand("ffd_scanner_faction", table.concat(out, ","))
    end

    -- Строка поиска: организаций на сервере бывает три десятка.
    local search = vgui.Create("DTextEntry", panel)
    search:SetTall(24)
    search:SetPlaceholderText("Поиск организации…")
    panel:AddItem(search)

    local status = vgui.Create("DLabel", panel)
    status:SetTall(18)
    status:SetDark(true)
    panel:AddItem(status)

    local list = vgui.Create("DScrollPanel", panel)
    list:SetTall(220)
    panel:AddItem(list)

    local rebuild

    local buttons = vgui.Create("DPanel", panel)
    buttons:SetPaintBackground(false)
    buttons:SetTall(26)
    panel:AddItem(buttons)

    local function toolButton(text, wide, fn)
        local b = vgui.Create("DButton", buttons)
        b:Dock(LEFT) b:SetWide(wide) b:DockMargin(0, 0, 4, 0)
        b:SetText(text)
        b.DoClick = fn
        return b
    end

    toolButton("Все", 60, function()
        local set = {}
        for _, row in ipairs(factionRows) do set[row.name] = true end
        writeChecked(set)
        if rebuild then rebuild() end
    end)
    toolButton("Снять", 70, function()
        RunConsoleCommand("ffd_scanner_faction", "")
        if rebuild then rebuild() end
    end)
    toolButton("Обновить список", 130, function()
        requestFactions()
    end)

    rebuild = function()
        list:Clear()
        local rows = factionRows
        local cur = checkedSet()
        local filter = string.lower(string.Trim(search:GetValue() or ""))

        local shown, chosen = 0, 0
        for _ in pairs(cur) do chosen = chosen + 1 end

        for _, row in ipairs(rows) do
            local hay = string.lower(row.display .. " " .. row.name .. " " .. (row.tag or ""))
            if filter == "" or hay:find(filter, 1, true) then
                shown = shown + 1
                local cb = vgui.Create("DCheckBoxLabel", list)
                cb:Dock(TOP) cb:DockMargin(4, 0, 4, 2)
                cb:SetTall(18)
                cb:SetDark(true)
                cb:SetText(row.display ..
                    ((row.tag ~= "" and row.tag ~= row.display) and ("  [" .. row.tag .. "]") or "") ..
                    ("  · сотрудников: " .. tostring(row.members or 0)))
                cb:SetChecked(cur[row.name] == true)
                cb.facName = row.name
                cb.checked = cur[row.name] == true      -- для стендов
                cb.OnChange = function(self, value)
                    local set = checkedSet()
                    set[self.facName] = value == true or nil
                    self.checked = value == true
                    writeChecked(set)
                    if rebuild then rebuild() end
                end
            end
        end

        if #rows == 0 then
            status:SetText("Список организаций ещё не пришёл — нажмите «Обновить список».")
            local hint = vgui.Create("DTextEntry", list)
            hint:Dock(TOP) hint:DockMargin(4, 2, 4, 2)
            if hint.SetUpdateOnType then hint:SetUpdateOnType(true) end
            if hint.SetConVar then hint:SetConVar("ffd_scanner_faction") end
            hint:SetTooltip("Пока список не пришёл, можно вписать названия вручную через запятую")
        elseif shown == 0 then
            status:SetText(("Ничего не найдено · всего организаций: %d · выбрано: %d"):format(#rows, chosen))
        else
            status:SetText(("Организаций: %d · показано: %d · выбрано: %d"):format(#rows, shown, chosen))
        end
    end

    search.OnChange = function() rebuild() end
    hook.Add("GRM_ScannerTool_ListUpdated", panel, function() if IsValid(panel) then rebuild() end end)
    panel.OnRemove = function() hook.Remove("GRM_ScannerTool_ListUpdated", panel) end

    rebuild()
    requestFactions()

    panel:AddControl("Numpad", { Label = "Сигнал успешного допуска (Granted):", Command = "ffd_scanner_key_granted" })
    panel:AddControl("Numpad", { Label = "Сигнал отказа (Denied):", Command = "ffd_scanner_key_denied" })
    panel:AddControl("Slider", { Label = "Время удержания дверей (сек):", Command = "ffd_scanner_hold_time", Type = "Float", Min = 1, Max = 30 })
end
