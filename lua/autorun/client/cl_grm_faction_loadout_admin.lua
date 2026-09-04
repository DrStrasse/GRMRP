--[[--------------------------------------------------------------------
    GRM Faction Loadout Admin v1.0.0 — единое меню экипировки фракций
    (клиент). Заменяет старые окна /models_admin и /weapons_admin.

    ЧТО ИЗМЕНИЛОСЬ:
      * Меню подтянуто к структуре фракций: помимо «Общие / Роли / Отделы»
        появились ПОДОТДЕЛЫ (Faction Core v5, «Отдел ➔ Подотдел»). У
        подотдела есть собственные списки моделей и оружия — раньше их
        нельзя было настроить, а сервер их даже не читал.
      * Везде показываются публичные названия (DisplayName) плюс системный
        ключ в скобках — как в остальном интерфейсе фракций.
      * Дизайн GRM: тёмные карточки, боковое дерево структуры, поиск по
        фракциям и по каталогу, живой предпросмотр модели.
      * Прокрутка не сбрасывается при сохранении (та же болезнь, что чинили
        в панели доступов): списки обновляются точечно.

    ПРИОРИТЕТ ВЫДАЧИ (показан в шапке редактора):
        модели:  подотдел → роль → отдел → фракция → стандарт
        оружие:  подотдел → отдел → роль → фракция → стандарт
----------------------------------------------------------------------]]

if SERVER then return end

GRM = GRM or {}
GRM.LoadoutAdmin = GRM.LoadoutAdmin or {}
local LA = GRM.LoadoutAdmin
LA.Version = "1.0.0"

local NET_MODELS_OPEN  = "FactionsExt_AdminModelsOpen"
local NET_MODELS_DATA  = "FactionsExt_AdminModelsData"
local NET_MODELS_SAVE  = "FactionsExt_AdminModelsSave"
local NET_WEAPONS_OPEN = "FactionsExt_AdminWeaponsOpen"
local NET_WEAPONS_DATA = "FactionsExt_AdminWeaponsData"
local NET_WEAPONS_SAVE = "FactionsExt_AdminWeaponsSave"

surface.CreateFont("GRMLoad_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMLoad_Head",   { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMLoad_Body",   { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMLoad_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })

local C = {
    bg     = Color(16, 20, 28, 252),
    head   = Color(12, 15, 22, 255),
    card   = Color(22, 28, 38, 245),
    cardH  = Color(30, 38, 52, 245),
    sel    = Color(38, 62, 96, 250),
    border = Color(38, 48, 66, 200),
    acc    = Color(65, 145, 235),
    green  = Color(55, 185, 110),
    gold   = Color(245, 195, 65),
    red    = Color(225, 70, 70),
    text   = Color(240, 244, 250),
    dim    = Color(155, 170, 190),
}

local function click(path)
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path or "buttons/button15.wav")
    else surface.PlaySound(path or "buttons/button15.wav") end
end

local function trim(s) return string.Trim(tostring(s or "")) end

-----------------------------------------------------------------------
-- Модельные записи { path, skin, bodygroups }
-----------------------------------------------------------------------
local function normEntry(entry)
    if isstring(entry) then return { path = entry, skin = 0, bodygroups = {} } end
    if istable(entry) then
        local bg = {}
        for k, v in pairs(entry.bodygroups or entry.Bodygroups or entry.bg or {}) do
            bg[tonumber(k) or 0] = tonumber(v) or 0
        end
        return {
            path = tostring(entry.path or entry.model or entry.Model or entry[1] or "models/player/Group01/male_07.mdl"),
            skin = tonumber(entry.skin or entry.Skin) or 0,
            bodygroups = bg,
        }
    end
    return { path = "models/player/Group01/male_07.mdl", skin = 0, bodygroups = {} }
end

local function bgText(bg)
    if not istable(bg) then return "—" end
    local out = {}
    for k, v in pairs(bg) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    if #out == 0 then return "—" end
    table.sort(out)
    return table.concat(out, ",")
end

-----------------------------------------------------------------------
-- Общие виджеты в стиле GRM
-----------------------------------------------------------------------
local function mkBtn(parent, label, col, onClick, tall)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Label = label
    b.Paint = function(s, w, h)
        local base = col or C.acc
        local c = s:IsHovered() and Color(math.min(255, base.r + 25), math.min(255, base.g + 25), math.min(255, base.b + 25)) or base
        draw.RoundedBox(5, 0, 0, w, h, c)
        surface.SetDrawColor(255, 255, 255, 22)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(s.Label, "GRMLoad_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() click() if onClick then onClick(b) end end
    if tall then b:SetTall(tall) end
    return b
end

local function mkEntry(parent, placeholder)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont("GRMLoad_Body")
    e:SetPlaceholderText(placeholder or "")
    e.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(14, 18, 26))
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        s:DrawTextEntryText(C.text, C.acc, C.text)
        if s:GetText() == "" and not s:HasFocus() then
            draw.SimpleText(s:GetPlaceholderText() or "", "GRMLoad_Small", 7, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return e
end

-- Сохранение позиции прокрутки вокруг перестроения списка.
local function keepScroll(scroll, fn)
    local pos = 0
    if IsValid(scroll) and IsValid(scroll.VBar) then pos = scroll.VBar:GetScroll() end
    fn()
    if pos > 0 then
        timer.Simple(0, function()
            if IsValid(scroll) and IsValid(scroll.VBar) then scroll.VBar:SetScroll(pos) end
        end)
    end
end

-----------------------------------------------------------------------
-- Редактор одной модели (путь / скин / бодигруппы)
-----------------------------------------------------------------------
local function openEntryEditor(entry, onDone)
    entry = normEntry(entry)

    local f = vgui.Create("DFrame")
    f:SetSize(640, 470) f:Center() f:MakePopup() f:ShowCloseButton(false) f:SetTitle("")
    f.Paint = function(_, w, h)
        draw.RoundedBox(7, 0, 0, w, h, C.bg)
        draw.RoundedBox(7, 0, 0, w, 44, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("МОДЕЛЬ: ПУТЬ, СКИН, БОДИГРУППЫ", "GRMLoad_Head", 16, 22, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", f)
    close:SetPos(f:GetWide() - 38, 8) close:SetSize(28, 28) close:SetText("✕")
    close:SetFont("GRMLoad_Head") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = function() f:Close() end

    local preview = vgui.Create("DModelPanel", f)
    preview:SetPos(14, 56) preview:SetSize(250, 330)
    preview:SetFOV(38)

    local pathE = mkEntry(f, "models/player/...")
    pathE:SetPos(278, 60) pathE:SetSize(348, 28) pathE:SetText(entry.path)

    local skinLbl = vgui.Create("DLabel", f)
    skinLbl:SetPos(278, 96) skinLbl:SetSize(120, 20) skinLbl:SetFont("GRMLoad_Small") skinLbl:SetTextColor(C.dim)
    skinLbl:SetText("Скин")

    local skinE = vgui.Create("DNumberWang", f)
    skinE:SetPos(278, 116) skinE:SetSize(90, 26) skinE:SetMin(0) skinE:SetMax(64) skinE:SetValue(entry.skin)

    local bgLbl = vgui.Create("DLabel", f)
    bgLbl:SetPos(278, 150) bgLbl:SetSize(340, 20) bgLbl:SetFont("GRMLoad_Small") bgLbl:SetTextColor(C.dim)
    bgLbl:SetText("Бодигруппы (ползунки подтянутся из модели)")

    local bgScroll = vgui.Create("DScrollPanel", f)
    bgScroll:SetPos(278, 172) bgScroll:SetSize(348, 214)

    local current = { path = entry.path, skin = entry.skin, bodygroups = table.Copy(entry.bodygroups) }

    local function applyPreview()
        if not IsValid(preview) then return end
        preview:SetModel(current.path)
        local ent = preview:GetEntity()
        if not IsValid(ent) then return end
        ent:SetSkin(current.skin)
        for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do ent:SetBodygroup(i, 0) end
        for g, v in pairs(current.bodygroups) do ent:SetBodygroup(tonumber(g) or 0, tonumber(v) or 0) end
    end

    local function buildBodygroups()
        bgScroll:Clear()
        local ent = IsValid(preview) and preview:GetEntity()
        if not IsValid(ent) then return end
        for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do
            local count = ent:GetBodygroupCount(i) or 1
            if count > 1 then
                local sl = vgui.Create("DNumSlider", bgScroll)
                sl:Dock(TOP) sl:SetTall(34) sl:DockMargin(0, 0, 6, 2)
                sl:SetText(ent:GetBodygroupName(i) ~= "" and ent:GetBodygroupName(i) or ("Группа " .. i))
                sl:SetMin(0) sl:SetMax(count - 1) sl:SetDecimals(0)
                sl:SetValue(current.bodygroups[i] or 0)
                sl.Label:SetFont("GRMLoad_Small")
                sl.Label:SetTextColor(C.text)
                sl.OnValueChanged = function(_, v)
                    current.bodygroups[i] = math.floor(v)
                    applyPreview()
                end
            end
        end
    end

    pathE.OnEnter = function(s)
        current.path = trim(s:GetText())
        current.bodygroups = {}
        applyPreview()
        timer.Simple(0, buildBodygroups)
    end
    skinE.OnValueChanged = function(_, v) current.skin = math.floor(tonumber(v) or 0) applyPreview() end

    applyPreview()
    timer.Simple(0.05, buildBodygroups)

    local save = mkBtn(f, "СОХРАНИТЬ МОДЕЛЬ", C.green, function()
        current.path = trim(pathE:GetText())
        current.skin = math.floor(tonumber(skinE:GetValue()) or 0)
        if current.path == "" then return end
        onDone(normEntry(current))
        f:Close()
    end)
    save:SetPos(14, 398) save:SetSize(612, 36)
end

-----------------------------------------------------------------------
-- Редактор моделей выбранного узла структуры
-----------------------------------------------------------------------
local function buildModelsEditor(parent, node, list, saveFn)
    if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(parent) else parent:Clear() end
    list = istable(list) and list or {}

    local head = vgui.Create("DPanel", parent)
    head:Dock(TOP) head:SetTall(52) head:DockMargin(0, 0, 0, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText(node.title, "GRMLoad_Head", 14, 16, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(node.hint, "GRMLoad_Small", 14, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", parent)
    body:Dock(FILL) body:SetPaintBackground(false)

    local previewPanel = vgui.Create("DPanel", body)
    previewPanel:Dock(RIGHT) previewPanel:SetWide(300) previewPanel:DockMargin(8, 0, 0, 0)
    previewPanel.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("ПРЕДПРОСМОТР", "GRMLoad_Small", 12, 14, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local preview = vgui.Create("DAdjustableModelPanel", previewPanel)
    preview:Dock(FILL) preview:DockMargin(8, 26, 8, 44) preview:SetFOV(38)
    local info = vgui.Create("DLabel", previewPanel)
    info:Dock(BOTTOM) info:SetTall(40) info:DockMargin(10, 0, 10, 6)
    info:SetFont("GRMLoad_Small") info:SetTextColor(C.dim) info:SetWrap(true)
    info:SetText("Выберите модель слева")

    local function showPreview(entry)
        entry = normEntry(entry)
        if not IsValid(preview) or entry.path == "" then return end
        preview:SetModel(entry.path)
        local ent = preview:GetEntity()
        if IsValid(ent) then
            ent:SetSkin(entry.skin)
            for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do ent:SetBodygroup(i, 0) end
            for g, v in pairs(entry.bodygroups) do ent:SetBodygroup(tonumber(g) or 0, tonumber(v) or 0) end
        end
        info:SetText(entry.path .. "\nскин " .. entry.skin .. "  •  боди " .. bgText(entry.bodygroups))
    end

    local scroll = vgui.Create("DScrollPanel", body)
    scroll:Dock(FILL)

    local selectedIdx
    local rebuild
    rebuild = function()
        keepScroll(scroll, function()
            scroll:Clear()
            if #list == 0 then
                local empty = vgui.Create("DLabel", scroll)
                empty:Dock(TOP) empty:SetTall(40) empty:SetFont("GRMLoad_Body") empty:SetTextColor(C.dim)
                empty:SetText("   Список пуст — экипировка наследуется по приоритету выше.")
            end
            for idx, raw in ipairs(list) do
                local entry = normEntry(raw)
                list[idx] = entry

                local row = vgui.Create("DPanel", scroll)
                row:Dock(TOP) row:SetTall(66) row:DockMargin(0, 0, 0, 5)
                row:SetCursor("hand")
                row.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, selectedIdx == idx and C.sel or C.card)
                    draw.SimpleText(entry.path, "GRMLoad_Body", 76, 22, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("скин " .. entry.skin .. "  •  боди " .. bgText(entry.bodygroups),
                        "GRMLoad_Small", 76, 42, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                row.OnMousePressed = function()
                    selectedIdx = idx
                    showPreview(entry)
                    click("buttons/button14.wav")
                end

                local ico = vgui.Create("SpawnIcon", row)
                ico:SetPos(5, 3) ico:SetSize(60, 60)
                ico:SetModel(entry.path, entry.skin)
                ico:SetMouseInputEnabled(false) ico:SetTooltip(false)

                local del = mkBtn(row, "✕", C.red, function()
                    table.remove(list, idx)
                    selectedIdx = nil
                    saveFn(list)
                    rebuild()
                end)
                del:SetPos(row:GetWide() - 46, 18) del:SetSize(34, 30)
                del.Think = function(s) s:SetPos((s:GetParent():GetWide() or 0) - 46, 18) end

                local edit = mkBtn(row, "Настроить", C.acc, function()
                    openEntryEditor(entry, function(updated)
                        list[idx] = updated
                        saveFn(list)
                        rebuild()
                        showPreview(updated)
                    end)
                end)
                edit:SetPos(row:GetWide() - 156, 18) edit:SetSize(104, 30)
                edit.Think = function(s) s:SetPos((s:GetParent():GetWide() or 0) - 156, 18) end

                --[[ СВЯЗЬ С РЕДАКТОРОМ ПРАВИЛ (заказ владельца 27.08).
                     Раньше админ ставил модель здесь, шёл в /bodygroups_admin
                     и не находил её — области и модель приходилось искать
                     руками, а модели должностей туда вообще не попадали.
                     Теперь кнопка открывает правила СРАЗУ для этой модели и
                     этого узла: организация, отдел/подотдел, звание или
                     должность подставляются автоматически. ]]
                local rules = mkBtn(row, "Правила", C.gold, function()
                    if not (GRM.BGRules and GRM.BGRules.Request) then
                        notification.AddLegacy("Модуль правил бодигрупп не загружен", NOTIFY_ERROR, 4)
                        return
                    end
                    local focus = { model = entry.path, faction = node.faction or "" }
                    if node.scope == "role" then focus.role = node.key or ""
                    elseif node.scope == "department" then focus.dept = node.key or ""
                    elseif node.scope == "subdepartment" then focus.dept = node.key or ""
                    elseif node.scope == "position" then focus.position = node.key or "" end
                    GRM.BGRules.Request(focus)
                end)
                rules:SetPos(row:GetWide() - 266, 18) rules:SetSize(104, 30)
                rules.Think = function(s) s:SetPos((s:GetParent():GetWide() or 0) - 266, 18) end
            end
        end)
        if list[1] and not selectedIdx then showPreview(list[1]) end
    end
    rebuild()

    local add = mkBtn(parent, "+ ДОБАВИТЬ МОДЕЛЬ", C.green, function()
        openEntryEditor({ path = "models/player/Group01/male_07.mdl" }, function(entry)
            list[#list + 1] = entry
            saveFn(list)
            rebuild()
        end)
    end)
    add:Dock(BOTTOM) add:SetTall(36) add:DockMargin(0, 8, 0, 0)
end

-----------------------------------------------------------------------
-- Редактор оружия выбранного узла структуры
-----------------------------------------------------------------------
local weaponCatalogCache
local function weaponCatalog()
    if weaponCatalogCache then return weaponCatalogCache end
    local out, seen = {}, {}
    for _, w in ipairs(weapons.GetList() or {}) do
        local cls = w.ClassName or ""
        if cls ~= "" and not seen[cls] then
            seen[cls] = true
            out[#out + 1] = {
                class = cls,
                name = (w.PrintName and w.PrintName ~= "") and w.PrintName or cls,
                cat = w.Category or "Прочее",
            }
        end
    end
    table.sort(out, function(a, b)
        if a.cat == b.cat then return a.name < b.name end
        return a.cat < b.cat
    end)
    weaponCatalogCache = out
    return out
end

local function buildWeaponsEditor(parent, node, list, saveFn)
    if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(parent) else parent:Clear() end
    list = istable(list) and list or {}

    local head = vgui.Create("DPanel", parent)
    head:Dock(TOP) head:SetTall(52) head:DockMargin(0, 0, 0, 8)
    head.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText(node.title, "GRMLoad_Head", 14, 16, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(node.hint, "GRMLoad_Small", 14, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", parent)
    body:Dock(FILL) body:SetPaintBackground(false)

    -- Левая половина — выданный набор
    local setPanel = vgui.Create("DPanel", body)
    setPanel:Dock(LEFT) setPanel:SetWide(360) setPanel:DockMargin(0, 0, 8, 0)
    setPanel.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("ВЫДАЁТСЯ", "GRMLoad_Small", 12, 14, C.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local setScroll = vgui.Create("DScrollPanel", setPanel)
    setScroll:Dock(FILL) setScroll:DockMargin(8, 28, 8, 8)

    -- Правая половина — каталог
    local catPanel = vgui.Create("DPanel", body)
    catPanel:Dock(FILL) catPanel:SetPaintBackground(false)
    local search = mkEntry(catPanel, "Поиск по названию или классу...")
    search:Dock(TOP) search:SetTall(28)
    local catScroll = vgui.Create("DScrollPanel", catPanel)
    catScroll:Dock(FILL) catScroll:DockMargin(0, 6, 0, 0)

    local function inList(cls)
        for _, c in ipairs(list) do if c == cls then return true end end
        return false
    end

    local rebuildSet, rebuildCatalog

    rebuildSet = function()
        keepScroll(setScroll, function()
            setScroll:Clear()
            if #list == 0 then
                local empty = vgui.Create("DLabel", setScroll)
                empty:Dock(TOP) empty:SetTall(30) empty:SetFont("GRMLoad_Small") empty:SetTextColor(C.dim)
                empty:SetText("Пусто — оружие наследуется по приоритету выше.")
            end
            for idx, class in ipairs(list) do
                local wpn = weapons.Get(class)
                local title = (wpn and wpn.PrintName and wpn.PrintName ~= "") and wpn.PrintName or class
                local row = vgui.Create("DPanel", setScroll)
                row:Dock(TOP) row:SetTall(34) row:DockMargin(0, 0, 0, 4)
                row.Paint = function(_, w, h)
                    draw.RoundedBox(5, 0, 0, w, h, C.cardH)
                    draw.SimpleText(title, "GRMLoad_Body", 10, h / 2 - 7, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(class, "GRMLoad_Small", 10, h / 2 + 8, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local del = mkBtn(row, "✕", C.red, function()
                    table.remove(list, idx)
                    saveFn(list)
                    rebuildSet()
                    rebuildCatalog(search:GetText())
                end)
                del:Dock(RIGHT) del:SetWide(36) del:DockMargin(0, 4, 4, 4)
            end
        end)
    end

    rebuildCatalog = function(filter)
        keepScroll(catScroll, function()
            catScroll:Clear()
            filter = string.lower(trim(filter))
            local lastCat
            for _, w in ipairs(weaponCatalog()) do
                if filter == "" or string.find(string.lower(w.name .. " " .. w.class), filter, 1, true) then
                    if w.cat ~= lastCat then
                        lastCat = w.cat
                        local hdr = vgui.Create("DLabel", catScroll)
                        hdr:Dock(TOP) hdr:SetTall(20) hdr:DockMargin(0, 6, 0, 2)
                        hdr:SetFont("GRMLoad_Small") hdr:SetTextColor(C.acc)
                        hdr:SetText("— " .. tostring(lastCat):upper())
                    end
                    local has = inList(w.class)
                    local row = vgui.Create("DButton", catScroll)
                    row:Dock(TOP) row:SetTall(28) row:DockMargin(0, 0, 0, 3) row:SetText("")
                    row.Paint = function(s, pw, ph)
                        draw.RoundedBox(5, 0, 0, pw, ph, has and Color(30, 66, 48) or (s:IsHovered() and C.cardH or C.card))
                        draw.SimpleText((has and "✓  " or "+  ") .. w.name, "GRMLoad_Body", 10, ph / 2,
                            has and C.green or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(w.class, "GRMLoad_Small", pw - 10, ph / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    end
                    row.DoClick = function()
                        click()
                        if inList(w.class) then
                            for i, c in ipairs(list) do if c == w.class then table.remove(list, i) break end end
                        else
                            list[#list + 1] = w.class
                        end
                        saveFn(list)
                        rebuildSet()
                        rebuildCatalog(search:GetText())
                    end
                end
            end
        end)
    end

    search.OnChange = function(s) rebuildCatalog(s:GetText()) end
    rebuildSet()
    rebuildCatalog("")

    -- Ручной ввод класса (для оружия вне списка weapons.GetList)
    local manual = vgui.Create("DPanel", parent)
    manual:Dock(BOTTOM) manual:SetTall(34) manual:DockMargin(0, 8, 0, 0) manual:SetPaintBackground(false)
    local entry = mkEntry(manual, "вручную: classname оружия...")
    entry:Dock(FILL)
    local addBtn = mkBtn(manual, "+ Добавить", C.green, function()
        local class = trim(entry:GetText())
        if class == "" or inList(class) then return end
        list[#list + 1] = class
        entry:SetText("")
        saveFn(list)
        rebuildSet()
        rebuildCatalog(search:GetText())
    end)
    addBtn:Dock(RIGHT) addBtn:SetWide(120) addBtn:DockMargin(6, 0, 0, 0)
    entry.OnEnter = function() addBtn:DoClick() end
end

-----------------------------------------------------------------------
-- Главное окно
-----------------------------------------------------------------------
local frames = {}

local function openLoadout(kind, data)
    local isWeapons = kind == "weapons"
    if IsValid(frames[kind]) then frames[kind]:Remove() end

    local frame = vgui.Create("DFrame")
    frames[kind] = frame
    frame:SetSize(math.min(1280, ScrW() - 80), math.min(760, ScrH() - 80))
    frame:Center() frame:MakePopup() frame:ShowCloseButton(false) frame:SetTitle("")
    frame:SetDeleteOnClose(true)
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("faction.loadout." .. kind, frame) end

    local title = isWeapons and "ВООРУЖЕНИЕ ФРАКЦИЙ" or "ОДЕЖДА ФРАКЦИЙ"
    local priority = isWeapons
        and "Приоритет выдачи: подотдел → отдел → роль → фракция → стандартное"
        or  "Приоритет выдачи: подотдел → роль → отдел → фракция → стандартная"

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 50, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(title, "GRMLoad_Title", 18, 25, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(priority, "GRMLoad_Small", 300, 26, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetPos(frame:GetWide() - 42, 10) close:SetSize(30, 30) close:SetText("✕")
    close:SetFont("GRMLoad_Head") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = function() frame:Close() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(12, 58, 12, 12) body:SetPaintBackground(false)

    -- ── Колонка 1: фракции ─────────────────────────────────────────
    local facCol = vgui.Create("DPanel", body)
    facCol:Dock(LEFT) facCol:SetWide(250) facCol:DockMargin(0, 0, 8, 0)
    facCol.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end

    local facSearch = mkEntry(facCol, "Поиск организации...")
    facSearch:Dock(TOP) facSearch:SetTall(28) facSearch:DockMargin(8, 8, 8, 6)
    local facScroll = vgui.Create("DScrollPanel", facCol)
    facScroll:Dock(FILL) facScroll:DockMargin(8, 0, 8, 8)

    -- ── Колонка 2: структура ───────────────────────────────────────
    local treeCol = vgui.Create("DPanel", body)
    treeCol:Dock(LEFT) treeCol:SetWide(300) treeCol:DockMargin(0, 0, 8, 0)
    treeCol.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("СТРУКТУРА", "GRMLoad_Small", 12, 14, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local treeScroll = vgui.Create("DScrollPanel", treeCol)
    treeScroll:Dock(FILL) treeScroll:DockMargin(8, 28, 8, 8)

    -- ── Колонка 3: редактор ────────────────────────────────────────
    local editor = vgui.Create("DPanel", body)
    editor:Dock(FILL) editor:SetPaintBackground(false)

    local state = { faction = nil, node = nil }

    local function saveNode(node, list)
        local msg = isWeapons and NET_WEAPONS_SAVE or NET_MODELS_SAVE
        net.Start(msg)
            net.WriteString(node.scope)
            net.WriteString(node.faction or "")
            net.WriteString(node.key or "")
            net.WriteTable(list)
        net.SendToServer()
    end

    local function openNode(node)
        state.node = node
        local list = node.list
        if isWeapons then
            buildWeaponsEditor(editor, node, list, function(l) saveNode(node, l) end)
        else
            buildModelsEditor(editor, node, list, function(l) saveNode(node, l) end)
        end
    end

    local treeButtons = {}
    local function markActive(node)
        for _, b in pairs(treeButtons) do
            if IsValid(b) then b.Active = (b.NodeID == (node and node.id or "")) end
        end
    end

    local function addTreeItem(node, depth, colour)
        local b = vgui.Create("DButton", treeScroll)
        b:Dock(TOP) b:SetTall(node.group and 24 or 32) b:DockMargin(depth * 12, node.group and 8 or 0, 0, 3)
        b:SetText("")
        b.NodeID = node.id or ""
        b.Active = false
        b.Paint = function(s, w, h)
            if node.group then
                draw.SimpleText(node.title, "GRMLoad_Small", 4, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                return
            end
            local bg = s.Active and C.sel or (s:IsHovered() and C.cardH or Color(26, 33, 45))
            draw.RoundedBox(5, 0, 0, w, h, bg)
            draw.RoundedBox(2, 0, 0, 4, h, colour or C.acc)
            draw.SimpleText(node.title, "GRMLoad_Body", 12, h / 2 - (node.sub and 7 or 0),
                s.Active and color_white or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if node.sub then
                draw.SimpleText(node.sub, "GRMLoad_Small", 12, h / 2 + 8, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local n = #(node.list or {})
            draw.SimpleText(n > 0 and tostring(n) or "—", "GRMLoad_Small", w - 10, h / 2,
                n > 0 and C.green or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        if node.group then
            b:SetMouseInputEnabled(false)
        else
            b.DoClick = function()
                click()
                markActive(node)
                openNode(node)
            end
            treeButtons[#treeButtons + 1] = b
        end
        return b
    end

    --[[ Должности узла (ось v5). Своя форма должности сильнее формы отдела,
         поэтому её узел стоит прямо под своим подразделением — видно, что
         начальник одет иначе, чем его подчинённые. ]]
    local function positionsOfNode(fd, node)
        local out = {}
        for _, pos in ipairs(fd.posList or {}) do
            if pos.node == node then out[#out + 1] = pos end
        end
        return out
    end

    local function buildTree(factionName)
        treeScroll:Clear()
        treeButtons = {}
        state.faction = factionName

        if factionName == "__default" then
            local node = {
                id = "default", scope = "default", faction = "", key = "",
                title = isWeapons and "Стандартное оружие" or "Стандартная одежда",
                hint = "Выдаётся всем, у кого нет фракционной экипировки",
                list = data.default or {},
            }
            addTreeItem(node, 0, C.gold)
            markActive(node)
            openNode(node)
            return
        end

        local fd = (data.factions or {})[factionName]
        if not istable(fd) then return end
        local disp = fd.displayName or factionName

        local nodes = {}

        addTreeItem({ group = true, title = "ОБЩЕЕ" }, 0)
        nodes[#nodes + 1] = addTreeItem({
            id = "general", scope = "faction", faction = factionName, key = "",
            title = "Вся организация",
            sub = disp .. " [" .. factionName .. "]",
            hint = "Базовая экипировка для всех сотрудников организации",
            list = fd.general or {},
        }, 0, C.gold)

        local rootPositions = positionsOfNode(fd, "root")
        if #rootPositions > 0 then
            addTreeItem({ group = true, title = "ДОЛЖНОСТИ ОРГАНИЗАЦИИ" }, 0)
            for _, pos in ipairs(rootPositions) do
                fd.positions = fd.positions or {}
                fd.positions[pos.id] = fd.positions[pos.id] or {}
                addTreeItem({
                    id = "pos:" .. pos.id, scope = "position", faction = factionName, key = pos.id,
                    title = pos.name,
                    sub = pos.kindName .. " • ключ " .. pos.id,
                    hint = "Экипировка должности «" .. pos.name .. "» (" .. pos.kindName
                        .. "). Сильнее формы отдела и звания.",
                    list = fd.positions[pos.id],
                }, 1, C.gold)
            end
        end

        if #(fd.rolesList or {}) > 0 then
            addTreeItem({ group = true, title = "ЗВАНИЯ (РАНГИ)" }, 0)
            for _, roleKey in ipairs(fd.rolesList or {}) do
                fd.roles = fd.roles or {}
                fd.roles[roleKey] = fd.roles[roleKey] or {}
                local pub = (fd.roleNames or {})[roleKey] or roleKey
                addTreeItem({
                    id = "role:" .. roleKey, scope = "role", faction = factionName, key = roleKey,
                    title = pub,
                    sub = "звание • ключ " .. roleKey,
                    hint = "Экипировка звания «" .. pub .. "» — действует на всех носителей звания",
                    list = fd.roles[roleKey],
                }, 1, C.acc)
            end
        end

        if #(fd.deptsList or {}) > 0 then
            addTreeItem({ group = true, title = "ОТДЕЛЫ И ПОДОТДЕЛЫ" }, 0)
            for _, deptKey in ipairs(fd.deptsList or {}) do
                fd.departments = fd.departments or {}
                fd.departments[deptKey] = fd.departments[deptKey] or {}
                local pub = (fd.deptNames or {})[deptKey] or deptKey
                addTreeItem({
                    id = "dept:" .. deptKey, scope = "department", faction = factionName, key = deptKey,
                    title = pub,
                    sub = "отдел • ключ " .. deptKey,
                    hint = "Экипировка отдела «" .. pub .. "» организации " .. disp,
                    list = fd.departments[deptKey],
                }, 1, C.green)

                for _, pos in ipairs(positionsOfNode(fd, "dept:" .. deptKey)) do
                    fd.positions = fd.positions or {}
                    fd.positions[pos.id] = fd.positions[pos.id] or {}
                    addTreeItem({
                        id = "pos:" .. pos.id, scope = "position", faction = factionName, key = pos.id,
                        title = pos.name,
                        sub = pos.kindName .. " • отдел " .. pub .. " • ключ " .. pos.id,
                        hint = "Экипировка должности «" .. pos.name .. "» в отделе " .. pub
                            .. ". Сильнее формы отдела.",
                        list = fd.positions[pos.id],
                    }, 2, C.gold)
                end

                -- Подотделы этого отдела — с отступом, как в структуре фракции.
                for _, sub in ipairs(fd.subList or {}) do
                    if sub.parent == deptKey then
                        fd.subdepartments = fd.subdepartments or {}
                        fd.subdepartments[sub.id] = fd.subdepartments[sub.id] or {}
                        addTreeItem({
                            id = "sub:" .. sub.id, scope = "subdepartment", faction = factionName, key = sub.id,
                            title = sub.name,
                            sub = "подотдел • " .. pub .. " • ключ " .. sub.id,
                            hint = "Экипировка подотдела «" .. sub.name .. "» (отдел " .. pub .. ")",
                            list = fd.subdepartments[sub.id],
                        }, 2, Color(190, 140, 240))

                        for _, pos in ipairs(positionsOfNode(fd, "sub:" .. sub.id)) do
                            fd.positions = fd.positions or {}
                            fd.positions[pos.id] = fd.positions[pos.id] or {}
                            addTreeItem({
                                id = "pos:" .. pos.id, scope = "position", faction = factionName, key = pos.id,
                                title = pos.name,
                                sub = pos.kindName .. " • подотдел " .. sub.name .. " • ключ " .. pos.id,
                                hint = "Экипировка должности «" .. pos.name .. "» в подотделе "
                                    .. sub.name .. ". Самая точная в порядке выдачи.",
                                list = fd.positions[pos.id],
                            }, 3, C.gold)
                        end
                    end
                end
            end
        end

        -- Подотделы без родительского отдела (или отдел удалён) — отдельной группой.
        local orphans = {}
        for _, sub in ipairs(fd.subList or {}) do
            local hasParent = false
            for _, deptKey in ipairs(fd.deptsList or {}) do
                if sub.parent == deptKey then hasParent = true break end
            end
            if not hasParent then orphans[#orphans + 1] = sub end
        end
        if #orphans > 0 then
            addTreeItem({ group = true, title = "ПОДОТДЕЛЫ БЕЗ ОТДЕЛА" }, 0)
            for _, sub in ipairs(orphans) do
                fd.subdepartments = fd.subdepartments or {}
                fd.subdepartments[sub.id] = fd.subdepartments[sub.id] or {}
                addTreeItem({
                    id = "sub:" .. sub.id, scope = "subdepartment", faction = factionName, key = sub.id,
                    title = sub.name,
                    sub = "подотдел без отдела • ключ " .. sub.id,
                    hint = "Экипировка подотдела «" .. sub.name .. "»",
                    list = fd.subdepartments[sub.id],
                }, 1, Color(190, 140, 240))

                for _, pos in ipairs(positionsOfNode(fd, "sub:" .. sub.id)) do
                    fd.positions = fd.positions or {}
                    fd.positions[pos.id] = fd.positions[pos.id] or {}
                    addTreeItem({
                        id = "pos:" .. pos.id, scope = "position", faction = factionName, key = pos.id,
                        title = pos.name,
                        sub = pos.kindName .. " • подотдел " .. sub.name .. " • ключ " .. pos.id,
                        hint = "Экипировка должности «" .. pos.name .. "»",
                        list = fd.positions[pos.id],
                    }, 2, C.gold)
                end
            end
        end

        --[[ Должности, чьё подразделение исчезло, иначе их форма стала бы
             недоступной для правки, продолжая применяться к людям. ]]
        local shownPos = {}
        for _, node in ipairs({ "root" }) do
            for _, pos in ipairs(positionsOfNode(fd, node)) do shownPos[pos.id] = true end
        end
        for _, deptKey in ipairs(fd.deptsList or {}) do
            for _, pos in ipairs(positionsOfNode(fd, "dept:" .. deptKey)) do shownPos[pos.id] = true end
        end
        for _, sub in ipairs(fd.subList or {}) do
            for _, pos in ipairs(positionsOfNode(fd, "sub:" .. sub.id)) do shownPos[pos.id] = true end
        end
        local lostPos = {}
        for _, pos in ipairs(fd.posList or {}) do
            if not shownPos[pos.id] then lostPos[#lostPos + 1] = pos end
        end
        if #lostPos > 0 then
            addTreeItem({ group = true, title = "ДОЛЖНОСТИ БЕЗ ПОДРАЗДЕЛЕНИЯ" }, 0)
            for _, pos in ipairs(lostPos) do
                fd.positions = fd.positions or {}
                fd.positions[pos.id] = fd.positions[pos.id] or {}
                addTreeItem({
                    id = "pos:" .. pos.id, scope = "position", faction = factionName, key = pos.id,
                    title = pos.name,
                    sub = pos.kindName .. " • подразделение удалено • ключ " .. pos.id,
                    hint = "Подразделение этой должности удалено — проверьте её в разделе «Должности».",
                    list = fd.positions[pos.id],
                }, 1, C.gold)
            end
        end

        -- Открываем «всю организацию» по умолчанию.
        if IsValid(nodes[1]) then nodes[1]:DoClick() end
    end

    local function buildFactionList(filter)
        facScroll:Clear()
        filter = string.lower(trim(filter))

        local defBtn = vgui.Create("DButton", facScroll)
        defBtn:Dock(TOP) defBtn:SetTall(38) defBtn:DockMargin(0, 0, 0, 6) defBtn:SetText("")
        defBtn.Paint = function(s, w, h)
            draw.RoundedBox(5, 0, 0, w, h, state.faction == "__default" and C.sel or (s:IsHovered() and C.cardH or Color(26, 33, 45)))
            draw.RoundedBox(2, 0, 0, 4, h, C.gold)
            draw.SimpleText(isWeapons and "Стандартное оружие" or "Стандартная одежда", "GRMLoad_Body", 12, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        defBtn.DoClick = function() click() buildTree("__default") buildFactionList(facSearch:GetText()) end

        local names = {}
        for name in pairs(data.factions or {}) do names[#names + 1] = name end
        table.sort(names, function(a, b)
            local da = ((data.factions[a] or {}).displayName or a):lower()
            local db = ((data.factions[b] or {}).displayName or b):lower()
            return da < db
        end)

        for _, name in ipairs(names) do
            local fd = data.factions[name]
            local disp = fd.displayName or name
            if filter == "" or string.find(string.lower(disp .. " " .. name), filter, 1, true) then
                local b = vgui.Create("DButton", facScroll)
                b:Dock(TOP) b:SetTall(44) b:DockMargin(0, 0, 0, 5) b:SetText("")
                b.Paint = function(s, w, h)
                    draw.RoundedBox(5, 0, 0, w, h, state.faction == name and C.sel or (s:IsHovered() and C.cardH or Color(26, 33, 45)))
                    draw.RoundedBox(2, 0, 0, 4, h, C.acc)
                    draw.SimpleText(disp, "GRMLoad_Body", 12, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(("%d должн. • %d отд. • %d подотд."):format(
                        #(fd.rolesList or {}), #(fd.deptsList or {}), #(fd.subList or {})),
                        "GRMLoad_Small", 12, 31, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                b.DoClick = function() click() buildTree(name) buildFactionList(facSearch:GetText()) end
            end
        end
    end

    facSearch.OnChange = function(s) buildFactionList(s:GetText()) end
    buildFactionList("")
    buildTree("__default")
end

LA.Open = openLoadout

-----------------------------------------------------------------------
-- Приём данных и команды
-----------------------------------------------------------------------
net.Receive(NET_MODELS_DATA, function()
    local data = net.ReadTable() or {}
    if LA._pendingModels then LA._pendingModels = nil openLoadout("models", data) end
end)

net.Receive(NET_WEAPONS_DATA, function()
    local data = net.ReadTable() or {}
    if LA._pendingWeapons then LA._pendingWeapons = nil openLoadout("weapons", data) end
end)

function LA.OpenModels()
    LA._pendingModels = true
    net.Start(NET_MODELS_OPEN)
    net.SendToServer()
end

function LA.OpenWeapons()
    LA._pendingWeapons = true
    net.Start(NET_WEAPONS_OPEN)
    net.SendToServer()
end

-- Команды живут и здесь: если sh_faction_fixes на клиенте не поднялся
-- (синтаксис / порядок загрузки), кнопки фракций и чат всё равно открывают меню.
local function tryOpen(kind)
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:IsSuperAdmin() then return end
    if kind == "models" then LA.OpenModels() else LA.OpenWeapons() end
end

concommand.Add("models_admin", function() tryOpen("models") end)
concommand.Add("weapons_admin", function() tryOpen("weapons") end)

hook.Add("GRMRPChat_ClientCommand", "GRM_LoadoutAdmin_Chat", function(ply, text)
    local datapack = { tostring(text or ""), SkipPlayerSay = false }
        if ply ~= LocalPlayer() or not istable(datapack) then return end
        local msg = string.Trim(string.lower(tostring(datapack[1] or "")))
        if msg == "/models_admin" or msg == "!models_admin" then
            tryOpen("models")
            datapack[1] = ""
            datapack.SkipPlayerSay = true
            return
        end
        if msg == "/weapons_admin" or msg == "!weapons_admin" then
            tryOpen("weapons")
            datapack[1] = ""
            datapack.SkipPlayerSay = true
            return
        end

    if datapack.SkipPlayerSay == true then return true end
end)

print("[GRM Loadout Admin] v" .. LA.Version .. ": одежда и вооружение по структуре фракции")
