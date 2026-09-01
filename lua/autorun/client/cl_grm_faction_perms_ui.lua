--[[--------------------------------------------------------------------
    GRM Faction Permissions UI — Client v3.0.0

    Панель настройки доступов фракций к экономическим/законодательным
    функциям ПО РОЛЯМ. Команда: grm_faction_perms
    Открывается также из «Доступы и связь» в /fmenu.

    v3.0.0 — ПОЧЕМУ БОЛЬШЕ НЕ ДЁРГАЕТ ВВЕРХ:
      Раньше любое изменение чекбокса уходило на сервер, сервер рассылал
      обновлённую таблицу доступов, клиент ловил GRM_FPermDataUpdated и
      ПОЛНОСТЬЮ пересобирал панель (parent:Clear() + новый DScrollPanel).
      Новый скролл всегда начинается сверху — отсюда и «прыжок» к началу
      списка после каждой галочки, причём на длинном списке ролей это
      делало настройку почти невозможной.

      Теперь:
        * панель строится ОДИН раз на выбранную фракцию;
        * чекбоксы живут в реестре rows[роль][доступ] и при обновлении
          данных с сервера им просто переставляется значение (SetValue) —
          никакого Clear и никакого нового скролла;
        * полная пересборка происходит ТОЛЬКО если реально изменился состав
          ролей/доступов, и даже тогда позиция скролла восстанавливается;
        * клик применяется оптимистично локально, поэтому галочка не мигает
          в ожидании ответа сервера;
        * защита от рекурсии: программная установка значения не вызывает
          OnChange и не шлёт лишний пакет на сервер.
----------------------------------------------------------------------]]

if SERVER then return end

GRM = GRM or {}
GRM.FactionPerms = GRM.FactionPerms or {}
local PERMS = GRM.FactionPerms

surface.CreateFont("GRMFPerm_Title",  { font = "Roboto", size = 18, weight = 700, extended = true })
surface.CreateFont("GRMFPerm_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMFPerm_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })

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
    text   = Color(240, 244, 250),
    dim    = Color(155, 170, 190),
}

local frame = nil
local ui = { rows = {}, posRows = {}, faction = nil, signature = nil, scroll = nil, applying = false }

local function click(path)
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path or "buttons/button15.wav")
    else surface.PlaySound(path or "buttons/button15.wav") end
end

local function mkBtn(parent, text, col, hoverCol, doClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetFont("GRMFPerm_Normal")
    b.Paint = function(s, w, h)
        local bg = s:IsHovered() and (hoverCol or C.acc) or (col or C.acc)
        draw.RoundedBox(5, 0, 0, w, h, bg)
        surface.SetDrawColor(255, 255, 255, 25)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(text, "GRMFPerm_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function()
        click()
        if doClick then doClick() end
    end
    return b
end

-- Категории доступов считаем один раз и кэшируем: раньше categories()
-- пересчитывался для КАЖДОЙ роли при каждой пересборке панели.
local catCache = nil
local function categories()
    if catCache then return catCache end
    local cats, order = {}, {}
    for id in pairs(PERMS.Permissions or {}) do
        local cat = id:match("^([^_]+)_") or "прочее"
        if not cats[cat] then cats[cat] = {} order[#order + 1] = cat end
        cats[cat][#cats[cat] + 1] = id
    end
    table.sort(order)
    local out = {}
    for _, cat in ipairs(order) do
        table.sort(cats[cat])
        out[#out + 1] = { name = cat, perms = cats[cat] }
    end
    catCache = out
    return out
end
hook.Add("GRM_FPermPermissionsChanged", "GRM_FPermUI_DropCatCache", function() catCache = nil end)

-- Подпись состава: меняется только при изменении набора ролей/доступов,
-- но НЕ при простой смене галочки.
local function structureSignature(factionName)
    local f = FactionsData and FactionsData[factionName]
    if not istable(f) then return "none" end
    local parts = { factionName }
    for _, role in ipairs(f.Roles or {}) do parts[#parts + 1] = tostring(role) end
    parts[#parts + 1] = "|pos|"
    -- Появилась или исчезла должность — панель обязана перестроиться.
    if GRM.Positions and GRM.Positions.List then
        for _, pos in ipairs(GRM.Positions.List(f)) do parts[#parts + 1] = tostring(pos.id) end
    end
    parts[#parts + 1] = "|"
    for _, cat in ipairs(categories()) do
        for _, permID in ipairs(cat.perms) do parts[#parts + 1] = permID end
    end
    return table.concat(parts, "\1")
end

-- Точечное обновление значений без пересборки панели.
local function syncValues(factionName)
    local rolePerms = PERMS.GetFactionRoles(factionName) or {}
    local posPerms = PERMS.GetFactionPositions and PERMS.GetFactionPositions(factionName) or {}
    ui.applying = true
    for role, perms in pairs(ui.rows) do
        local rp = rolePerms[role] or {}
        for permID, chk in pairs(perms) do
            if IsValid(chk) then
                local want = rp[permID] and true or false
                if chk:GetChecked() ~= want then chk:SetValue(want) end
                chk:SetTextColor(want and C.green or C.text)
            end
        end
    end
    for posID, perms in pairs(ui.posRows or {}) do
        local pp = posPerms[posID] or {}
        for permID, chk in pairs(perms) do
            if IsValid(chk) then
                local want = pp[permID] and true or false
                if chk:GetChecked() ~= want then chk:SetValue(want) end
                chk:SetTextColor(want and C.green or C.text)
            end
        end
    end
    ui.applying = false
end

local function buildPanel(parent, factionName)
    -- Сохраняем позицию скролла: даже при вынужденной полной пересборке
    -- список должен остаться там, где на него смотрел админ.
    local prevScroll = 0
    if IsValid(ui.scroll) and IsValid(ui.scroll.VBar) then prevScroll = ui.scroll.VBar:GetScroll() end

    if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(parent) else parent:Clear() end
    ui.rows = {}
    ui.posRows = {}
    ui.scroll = nil
    ui.faction = factionName
    ui.signature = structureSignature(factionName)

    if not factionName or not FactionsData or not FactionsData[factionName] then
        local lbl = vgui.Create("DLabel", parent)
        lbl:Dock(TOP) lbl:SetTall(40) lbl:SetFont("GRMFPerm_Normal") lbl:SetTextColor(C.dim)
        lbl:SetText("Выберите фракцию слева.")
        return
    end

    local f = FactionsData[factionName]
    local roles = f.Roles or {}
    local rolePerms = PERMS.GetFactionRoles(factionName) or {}

    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    ui.scroll = scroll

    local header = vgui.Create("DLabel", scroll)
    header:Dock(TOP) header:SetTall(28) header:SetFont("GRMFPerm_Title") header:SetTextColor(C.gold)
    header:SetText("Доступы по ролям: " .. (GRM.Factions.DisplayName(factionName) or factionName))

    if #roles == 0 then
        local lbl = vgui.Create("DLabel", scroll)
        lbl:Dock(TOP) lbl:SetTall(40) lbl:SetFont("GRMFPerm_Normal") lbl:SetTextColor(C.dim)
        lbl:SetText("Ролей нет — создайте во вкладке «Структура».")
        return
    end

    --[[ ДОСТУПЫ ДОЛЖНОСТЕЙ (ось v5).

         Право звания получают ВСЕ носители звания — все сержанты сразу.
         Право должности получает конкретное место в штате, поэтому
         «распоряжаться автопарком» можно отдать начальнику транспортного
         отдела, не раздавая это всем сержантам организации. ]]
    local POS = GRM.Positions
    local positions = (POS and POS.List) and POS.List(f) or {}
    if #positions > 0 then
        local posHead = vgui.Create("DLabel", scroll)
        posHead:Dock(TOP) posHead:SetTall(26) posHead:DockMargin(0, 6, 0, 2)
        posHead:SetFont("GRMFPerm_Title") posHead:SetTextColor(C.gold)
        posHead:SetText("Доступы по должностям")

        -- Наследование и замещение: по умолчанию оба выключены, чтобы
        -- ничего не раздавалось молча.
        local cfg = PERMS.PositionSettings and PERMS.PositionSettings(factionName)
            or { inherit = false, standin = false }

        local function settingRow(text, key, value)
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP) row:SetTall(30) row:DockMargin(8, 0, 0, 2)
            row.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.card) end
            local chk = vgui.Create("DCheckBoxLabel", row)
            chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
            chk:SetText(text)
            chk:SetFont("GRMFPerm_Normal")
            chk:SetTextColor(value and C.green or C.text)
            chk:SetValue(value and 1 or 0)
            chk.OnChange = function(_, val)
                if ui.applying then return end
                local v = val == true
                chk:SetTextColor(v and C.green or C.text)
                if PERMS.SetPositionSetting then
                    PERMS.SetPositionSetting(factionName, key, v)
                end
            end
        end

        settingRow("Начальник наследует доступы подчинённых должностей своего подразделения",
            "inherit", cfg.inherit)
        settingRow("Заместитель получает доступы начальника, пока того нет в сети",
            "standin", cfg.standin)

        local posPerms = PERMS.GetFactionPositions and PERMS.GetFactionPositions(factionName) or {}
        for _, pos in ipairs(positions) do
            local pp = posPerms[pos.id] or {}
            ui.posRows[pos.id] = {}

            local posCard = vgui.Create("DPanel", scroll)
            posCard:Dock(TOP) posCard:SetTall(30) posCard:DockMargin(0, 6, 0, 0)
            local kindName = (POS.KindName and POS.KindName[pos.kind]) or pos.kind
            local nodeName = POS.NodeDisplayName and POS.NodeDisplayName(f, pos.node) or pos.node
            posCard.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, C.head)
                draw.SimpleText("ДОЛЖНОСТЬ: " .. pos.name, "GRMFPerm_Normal", 10, h / 2,
                    C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(kindName .. " · " .. nodeName, "GRMFPerm_Small", w - 10, h / 2,
                    C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            for _, cat in ipairs(categories()) do
                local catLabel = vgui.Create("DLabel", scroll)
                catLabel:Dock(TOP) catLabel:SetTall(22) catLabel:SetFont("GRMFPerm_Small")
                catLabel:SetTextColor(C.dim) catLabel:DockMargin(8, 6, 0, 0)
                catLabel:SetText("— " .. cat.name:upper())

                for _, permID in ipairs(cat.perms) do
                    local row = vgui.Create("DPanel", scroll)
                    row:Dock(TOP) row:SetTall(30) row:DockMargin(8, 0, 0, 2)
                    row.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.card) end

                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                    chk:SetText(PERMS.Permissions[permID] or permID)
                    chk:SetFont("GRMFPerm_Normal")
                    chk:SetTextColor(pp[permID] and C.green or C.text)
                    chk:SetValue(pp[permID] and 1 or 0)
                    chk.OnChange = function(_, val)
                        if ui.applying then return end
                        local v = val == true
                        chk:SetTextColor(v and C.green or C.text)
                        if v then PERMS.GrantToPosition(factionName, pos.id, permID)
                        else PERMS.RevokeFromPosition(factionName, pos.id, permID) end
                    end
                    ui.posRows[pos.id][permID] = chk
                end
            end
        end

        local rolesHead = vgui.Create("DLabel", scroll)
        rolesHead:Dock(TOP) rolesHead:SetTall(30) rolesHead:DockMargin(0, 12, 0, 2)
        rolesHead:SetFont("GRMFPerm_Title") rolesHead:SetTextColor(C.gold)
        rolesHead:SetText("Доступы по званиям (действуют на всех носителей звания)")
    end

    for _, role in ipairs(roles) do
        local rp = rolePerms[role] or {}
        ui.rows[role] = {}

        local roleCard = vgui.Create("DPanel", scroll)
        roleCard:Dock(TOP) roleCard:SetTall(30) roleCard:DockMargin(0, 4, 0, 0)
        roleCard.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, C.head)
            draw.SimpleText("РОЛЬ: " .. role, "GRMFPerm_Normal", 10, h / 2, C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        for _, cat in ipairs(categories()) do
            local catLabel = vgui.Create("DLabel", scroll)
            catLabel:Dock(TOP) catLabel:SetTall(22) catLabel:SetFont("GRMFPerm_Small") catLabel:SetTextColor(C.dim)
            catLabel:SetText("— " .. cat.name:upper())
            catLabel:DockMargin(8, 6, 0, 0)

            for _, permID in ipairs(cat.perms) do
                local row = vgui.Create("DPanel", scroll)
                row:Dock(TOP) row:SetTall(30) row:DockMargin(8, 0, 0, 2)
                row.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.card) end

                local chk = vgui.Create("DCheckBoxLabel", row)
                chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                chk:SetText(PERMS.Permissions[permID] or permID)
                chk:SetFont("GRMFPerm_Normal")
                chk:SetTextColor(rp[permID] and C.green or C.text)
                chk:SetValue(rp[permID] and 1 or 0)
                chk.OnChange = function(_, val)
                    -- Программная синхронизация значений не должна улетать
                    -- обратно на сервер и вызывать новый цикл обновления.
                    if ui.applying then return end
                    local v = val == true
                    chk:SetTextColor(v and C.green or C.text)

                    -- Оптимистичное локальное применение: галочка не мигает,
                    -- пока идёт обмен с сервером.
                    PERMS.Data = PERMS.Data or {}
                    PERMS.Data[factionName] = PERMS.Data[factionName] or {}
                    PERMS.Data[factionName][role] = PERMS.Data[factionName][role] or {}
                    PERMS.Data[factionName][role][permID] = v or nil

                    if v then PERMS.GrantToRole(factionName, role, permID)
                    else PERMS.RevokeFromRole(factionName, role, permID) end
                end

                ui.rows[role][permID] = chk
            end
        end
    end

    if prevScroll > 0 and IsValid(scroll.VBar) then
        -- Восстанавливаем прокрутку после того, как Derma разложит элементы.
        timer.Simple(0, function()
            if IsValid(scroll) and IsValid(scroll.VBar) then scroll.VBar:SetScroll(prevScroll) end
        end)
    end
end

-- Обновление данных с сервера: по возможности БЕЗ пересборки.
local function onDataUpdated(right)
    if not (IsValid(frame) and IsValid(right)) then return end
    if not ui.faction then return end
    if structureSignature(ui.faction) ~= ui.signature then
        buildPanel(right, ui.faction)
    else
        syncValues(ui.faction)
    end
end

local function open()
    PERMS.Request()

    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:SetSize(900, 680)
    frame:Center()
    frame:MakePopup()
    frame:ShowCloseButton(false)
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("faction.perms", frame) end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("Доступы фракций к экономическим функциям (по ролям)", "GRMFPerm_Title", 16, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetPos(frame:GetWide() - 40, 8) close:SetSize(30, 30) close:SetText("✕")
    close:SetFont("GRMFPerm_Title") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = function() frame:Close() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(0, 46, 0, 0) body:SetPaintBackground(false)

    -- Левая колонка — список фракций
    local left = vgui.Create("DListView", body)
    left:Dock(LEFT) left:SetWide(250) left:DockMargin(8, 8, 4, 8)
    left:SetMultiSelect(false)
    left:AddColumn("Фракция")
    left:SetPaintBackground(false)
    left.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    local names = {}
    for name, f in pairs(FactionsData or {}) do
        if istable(f) then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    for _, name in ipairs(names) do
        local disp = GRM.Factions.DisplayName(name)
        local ln = left:AddLine(disp .. " [" .. name .. "]")
        ln.FactionName = name
        for _, col in pairs(ln.Columns or {}) do
            if IsValid(col) then col:SetFont("GRMFPerm_Normal") col:SetTextColor(C.text) end
        end
    end

    -- Правая колонка — доступы по ролям
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL) right:DockMargin(4, 8, 8, 8) right:SetPaintBackground(false)

    local selected = names[1]

    left.OnRowSelected = function(_, _, line)
        if IsValid(line) and line.FactionName ~= ui.faction then
            selected = line.FactionName
            buildPanel(right, selected)
        end
    end

    mkBtn(right, "Обновить", C.acc, C.gold, function() PERMS.Request() end)

    buildPanel(right, selected)

    hook.Add("GRM_FPermDataUpdated", "GRM_FPermUI_Refresh", function() onDataUpdated(right) end)
    frame.OnRemove = function()
        hook.Remove("GRM_FPermDataUpdated", "GRM_FPermUI_Refresh")
        ui.rows, ui.scroll, ui.faction, ui.signature = {}, nil, nil, nil
    end
end

PERMS.OpenUI = open

concommand.Add("grm_faction_perms", function()
    if LocalPlayer():IsSuperAdmin() or (GRM.Factions and GRM.Factions.IsLeader and GRM.Factions.IsLeader(LocalPlayer())) then
        open()
    else
        notification.AddLegacy("Только суперадмин или лидер фракции", NOTIFY_ERROR, 3)
    end
end)

print("[GRM Faction Permissions UI] v3.0.0 loaded (без прыжка скролла)")
