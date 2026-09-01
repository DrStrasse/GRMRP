--[[--------------------------------------------------------------------
    GRM Doors Menu v2.0.0 — окно «Управление дверью» в стиле GRM.

    Заказ владельца (19.08): «категории владельцев дверей нормально
    редактировать; категория должна включать фракции, отделы, подотделы,
    чекбоксы лиц без фракции и т.д.; допустим, гаражная дверь категории
    "Общественная" — открывать может каждый, а блокировать нельзя; окно
    пошире и в стиле GRM».

    Что здесь:
      • боковое меню разделов вместо стандартного DPropertySheet;
      • «Обзор» — состояние двери, замок, покупка/аренда, название;
      • «Совладельцы» — выдача ключей персонажам;
      • «Доступы» — фракции, должности и категории в списке доступа двери;
      • «Категории» (суперадмин) — ПОЛНЫЙ редактор профиля категории:
        флаги поведения + дерево «организация → отделы → подотделы →
        должности» с чекбоксами;
      • «Администрирование» — владелец двери (фракция/категория/сброс) и
        доступность приватизации.

    Данные приходят одним пакетом GRM_Doors_Open (дверь, категории целиком,
    дерево организаций, признак админа) — окно ничего не запрашивает само.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Doors = GRM.Doors or {}
local D = GRM.Doors
D.MenuVersion = "2.1.0"

local NET_OPEN = "GRM_Doors_Open"
local NET_ACT  = "GRM_Doors_Act"

surface.CreateFont("GRMDoorUI_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMDoorUI_Head",   { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMDoorUI_Body",   { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMDoorUI_Small",  { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg       = Color(16, 20, 28, 252),
    sidebar  = Color(12, 15, 22, 255),
    card     = Color(22, 28, 38, 240),
    cardHov  = Color(32, 42, 56, 240),
    row      = Color(26, 33, 45, 240),
    border   = Color(38, 48, 66, 200),
    accent   = Color(65, 145, 235),
    gold     = Color(245, 195, 65),
    green    = Color(55, 185, 110),
    teal     = Color(75, 195, 170),
    red      = Color(225, 70, 70),
    text     = Color(240, 244, 250),
    dim      = Color(155, 170, 190),
}

local function act(t)
    net.Start(NET_ACT) net.WriteTable(t or {}) net.SendToServer()
end

local function money(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

local function button(parent, label, base)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Paint = function(self, w, h)
        local col = base or C.accent
        if not self:IsEnabled() then col = Color(38, 44, 56)
        elseif self:IsHovered() then col = Color(math.min(255, col.r + 24), math.min(255, col.g + 24), math.min(255, col.b + 24)) end
        draw.RoundedBox(6, 0, 0, w, h, col)
        draw.SimpleText(label, "GRMDoorUI_Body", w / 2, h / 2, self:IsEnabled() and color_white or C.dim,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function card(parent, tall, title, titleColor)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP) p:SetTall(tall or 60) p:DockMargin(0, 0, 6, 8)
    p.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        if title then draw.SimpleText(title, "GRMDoorUI_Head", 14, 12, titleColor or C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end
    end
    return p
end

local function infoRow(parent, label, value, valueColor)
    local r = vgui.Create("DPanel", parent)
    r:Dock(TOP) r:SetTall(30) r:DockMargin(0, 0, 6, 4)
    r.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.row)
        draw.SimpleText(label, "GRMDoorUI_Body", 12, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(value), "GRMDoorUI_Body", w - 12, h / 2, valueColor or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    return r
end

local function checkRow(parent, label, checked, indent, colorOn, onChange)
    local r = vgui.Create("DPanel", parent)
    r:Dock(TOP) r:SetTall(28) r:DockMargin(indent or 0, 0, 6, 3)
    r.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, C.row) end
    local chk = vgui.Create("DCheckBoxLabel", r)
    chk:Dock(FILL) chk:DockMargin(10, 0, 6, 0)
    chk:SetText(label)
    chk:SetFont("GRMDoorUI_Body")
    chk:SetTextColor(checked and (colorOn or C.text) or C.dim)
    chk:SetValue(checked and 1 or 0)
    -- Программное обновление галочки НЕ должно улетать на сервер: иначе
    -- обновление окна само себе шлёт действие и всё зацикливается.
    local silent = false
    chk.OnChange = function(_, val)
        if silent then return end
        if onChange then onChange(val) end
    end
    local function setChecked(on)
        silent = true
        chk:SetValue(on and 1 or 0)
        chk:SetTextColor(on and (colorOn or C.text) or C.dim)
        silent = false
    end
    return r, chk, setChecked
end

local function skinEntry(entry, placeholder)
    entry:SetFont("GRMDoorUI_Body")
    entry:SetTextColor(C.text)
    entry:SetCursorColor(C.text)
    if placeholder then entry:SetPlaceholderText(placeholder) end
    entry.Paint = function(self, w, h)
        draw.RoundedBox(5, 0, 0, w, h, Color(28, 36, 48))
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetText() == "" and self.GetPlaceholderText and self:GetPlaceholderText() then
            draw.SimpleText(self:GetPlaceholderText(), "GRMDoorUI_Small", 8, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return entry
end

local function skinCombo(combo)
    combo:SetFont("GRMDoorUI_Body")
    combo:SetTextColor(C.text)
    combo.Paint = function(self, w, h)
        draw.RoundedBox(5, 0, 0, w, h, Color(28, 36, 48))
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
    end
    return combo
end

local function listHas(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- Раздел, выбранный в прошлый раз: сервер перерисовывает окно после каждого
-- действия, и без этого админ каждый раз улетал бы в «Обзор».
local lastTab, lastCategory, lastScroll = "overview", nil, 0

-----------------------------------------------------------------------
-- ОКНО
-----------------------------------------------------------------------
function D.OpenMenu(ent, d, cats, facTree, canAdmin)
    if IsValid(D._frame) then D._frame:Remove() end

    local isAdmin = (d.is_admin == true) or (canAdmin == true)
    local canOwn  = d.can_own == true or isAdmin

    local f = vgui.Create("DFrame")
    D._frame = f
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_door_menu", f) end
    f:SetSize(math.Clamp(ScrW() * 0.68, 1000, 1480), math.Clamp(ScrH() * 0.80, 660, 980))
    f:Center() f:SetTitle("") f:ShowCloseButton(false) f:MakePopup() f:SetSizable(true)

    local function describeOwner(rec)
        if rec.owner_type == "player" then return tostring(rec.owner_nick or "Игрок") end
        if rec.owner_type == "faction" then return "Организация: " .. tostring(rec.owner_faction or "") end
        if rec.owner_type == "category" then
            return "Категория: " .. tostring(rec.owner_category_name ~= "" and rec.owner_category_name or rec.owner_category or "")
        end
        return "Ничья / продаётся"
    end
    local ownerDesc = describeOwner(d)

    f.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.sidebar)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("GRM · УПРАВЛЕНИЕ ДВЕРЬЮ", "GRMDoorUI_Title", 18, 15, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local sub = (d.title ~= "" and d.title or "Без названия") .. "  •  " .. ownerDesc ..
            "  •  " .. (d.locked and "ЗАКРЫТА" or "ОТКРЫТА")
        draw.SimpleText(sub, "GRMDoorUI_Small", 18, 36, d.locked and Color(235, 130, 120) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local close = button(f, "✕", C.red)
    close:SetSize(34, 30) close:SetPos(f:GetWide() - 44, 8)
    close.DoClick = function() f:Remove() end
    f.PerformLayout = function(self)
        if IsValid(close) then close:SetPos(self:GetWide() - 44, 8) end
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL) body:DockMargin(0, 46, 0, 0) body:SetPaintBackground(false)

    local sidebar = vgui.Create("DPanel", body)
    sidebar:Dock(LEFT) sidebar:SetWide(228)
    sidebar.Paint = function(_, w, h)
        draw.RoundedBoxEx(0, 0, 0, w, h, C.sidebar, false, false, true, false)
        surface.SetDrawColor(C.border) surface.DrawLine(w - 1, 0, w - 1, h)
    end

    local content = vgui.Create("DScrollPanel", body)
    content:Dock(FILL) content:DockMargin(12, 10, 12, 12)

    local tabs, tabButtons = {}, {}

    --[[ ПОЧЕМУ СПИСОК ПРЫГАЛ ВВЕРХ ПОСЛЕ ГАЛОЧКИ.
         Каждое действие (галочка фракции/роли/категории) сервер отвечает
         пересборкой окна. Позиция прокрутки запоминалась в OnVScroll — но
         туда же попадал НАШ СОБСТВЕННЫЙ программный SetScroll(0) при
         построении вкладки, и запомненная позиция стиралась в ноль.
         Теперь программные сдвиги помечаются флагом и в память не идут, а
         восстановление повторяется несколько кадров: DScrollPanel зажимает
         SetScroll по высоте холста, а она считается уже после раскладки. ]]
    local scrollSilent = false
    -- Обновление уже открытой вкладки «Категории» без пересборки (см. ниже).
    local catRefresh = nil
    local function setScroll(value)
        if not IsValid(content.VBar) then return end
        scrollSilent = true
        content.VBar:SetScroll(value)
        scrollSilent = false
    end

    local function selectTab(key)
        if key ~= lastTab then lastScroll = 0 end
        lastTab = key
        -- Старые ссылки на галочки ведут на уже уничтоженные панели.
        catRefresh = nil
        content:Clear()
        setScroll(0)
        for id, btn in pairs(tabButtons) do btn.active = (id == key) end
        if tabs[key] then tabs[key](content) end
    end

    local function addTab(key, label, builder)
        tabs[key] = builder
        local b = vgui.Create("DButton", sidebar)
        b:Dock(TOP) b:SetTall(38) b:DockMargin(6, 6, 6, 0) b:SetText("")
        b.Paint = function(self, w, h)
            local col = self.active and C.accent or (self:IsHovered() and C.cardHov or C.card)
            draw.RoundedBox(6, 0, 0, w, h, col)
            draw.SimpleText(label, "GRMDoorUI_Body", 14, h / 2, self.active and color_white or C.text,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function() selectTab(key) end
        tabButtons[key] = b
        return b
    end

    ------------------------------------------------------------------
    -- ОБЗОР
    ------------------------------------------------------------------
    addTab("overview", "Обзор", function(pnl)
        local info = card(pnl, 176, "СОСТОЯНИЕ ДВЕРИ")
        local holder = vgui.Create("DPanel", info)
        holder:Dock(FILL) holder:DockMargin(12, 36, 12, 10) holder:SetPaintBackground(false)
        infoRow(holder, "Название", d.title ~= "" and d.title or "—")
        infoRow(holder, "Владелец", ownerDesc, d.owner_type == "none" and C.dim or C.teal)
        infoRow(holder, "Замок", d.locked and "ЗАКРЫТ" or "ОТКРЫТ", d.locked and C.red or C.green)
        infoRow(holder, "Ваш доступ", d.can_access and "есть ключ" or "нет доступа", d.can_access and C.green or C.red)

        local actions = card(pnl, 56)
        local bar = vgui.Create("DPanel", actions)
        bar:Dock(FILL) bar:DockMargin(10, 10, 10, 10) bar:SetPaintBackground(false)

        local lock = button(bar, d.locked and "ОТКРЫТЬ ЗАМОК" or "ЗАКРЫТЬ ЗАМОК", d.locked and C.green or C.accent)
        lock:Dock(LEFT) lock:SetWide(200) lock:DockMargin(0, 0, 8, 0)
        lock:SetEnabled(d.can_access == true)
        lock.DoClick = function() act({ action = d.locked and "unlock" or "lock", entIndex = ent:EntIndex() }) end

        if d.can_buy then
            local buy = button(bar, "КУПИТЬ", C.green)
            buy:Dock(LEFT) buy:SetWide(150) buy:DockMargin(0, 0, 8, 0)
            buy.DoClick = function() act({ action = "claim_perm", entIndex = ent:EntIndex() }) end
            local rent = button(bar, "АРЕНДА · " .. money(d.rent_price or 0), C.accent)
            rent:Dock(LEFT) rent:SetWide(210) rent:DockMargin(0, 0, 8, 0)
            rent.DoClick = function() act({ action = "claim_rent", entIndex = ent:EntIndex() }) end
        end
        if d.is_owner then
            local rel = button(bar, "ОСВОБОДИТЬ", C.red)
            rel:Dock(RIGHT) rel:SetWide(160)
            rel.DoClick = function()
                Derma_Query("Освободить дверь? Ключи совладельцев пропадут.", "Дверь", "Освободить",
                    function() act({ action = "release", entIndex = ent:EntIndex() }) end, "Отмена")
            end
        end

        if canOwn then
            local nameCard = card(pnl, 92, "НАЗВАНИЕ ДВЕРИ")
            local te = skinEntry(vgui.Create("DTextEntry", nameCard), "Например: Гараж №3")
            te:SetPos(14, 40) te:SetSize(320, 30) te:SetText(d.title or "")
            local save = button(nameCard, "СОХРАНИТЬ", C.accent)
            save:SetPos(344, 40) save:SetSize(150, 30)
            save.DoClick = function() act({ action = "set_title", entIndex = ent:EntIndex(), title = te:GetValue() }) end
        end
    end)

    ------------------------------------------------------------------
    -- СОВЛАДЕЛЬЦЫ
    ------------------------------------------------------------------
    if canOwn then
        addTab("coowners", "Совладельцы", function(pnl)
            local add = card(pnl, 92, "ВЫДАТЬ КЛЮЧ")
            local combo = skinCombo(vgui.Create("DComboBox", add))
            combo:SetPos(14, 40) combo:SetSize(330, 30) combo:SetValue("Выберите игрока...")
            for _, p in ipairs(player.GetAll()) do
                if IsValid(p) and p ~= LocalPlayer() then
                    local nick = p:GetNWString("GRM_RPName", "")
                    combo:AddChoice((nick ~= "" and nick or p:Nick()) .. " [" .. p:Nick() .. "]", p:SteamID())
                end
            end
            local give = button(add, "ВЫДАТЬ", C.green)
            give:SetPos(354, 40) give:SetSize(150, 30)
            give.DoClick = function()
                local _, sid = combo:GetSelected()
                if sid then act({ action = "add_coowner", entIndex = ent:EntIndex(), sid = sid }) end
            end

            local list = card(pnl, 44 + math.max(1, #(d.co_owners or {})) * 34, "КЛЮЧИ НА РУКАХ")
            local holder = vgui.Create("DPanel", list)
            holder:Dock(FILL) holder:DockMargin(12, 36, 12, 8) holder:SetPaintBackground(false)
            if #(d.co_owners or {}) == 0 then
                infoRow(holder, "Совладельцев нет", "—")
            end
            for _, co in ipairs(d.co_owners or {}) do
                local r = vgui.Create("DPanel", holder)
                r:Dock(TOP) r:SetTall(30) r:DockMargin(0, 0, 6, 4)
                r.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.row)
                    draw.SimpleText(tostring(co.nick ~= "" and co.nick or co.sid), "GRMDoorUI_Body", 12, h / 2, C.text,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local del = button(r, "Забрать", C.red)
                del:Dock(RIGHT) del:SetWide(110) del:DockMargin(4, 3, 6, 3)
                del.DoClick = function() act({ action = "remove_coowner", entIndex = ent:EntIndex(), sid = co.sid }) end
            end
        end)
    end

    ------------------------------------------------------------------
    -- ДОСТУПЫ (фракции, должности, категории двери)
    ------------------------------------------------------------------
    if canOwn then
        addTab("access", "Доступы", function(pnl)
            local hint = card(pnl, 52)
            hint.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText("Отметьте, кому дверь открывается помимо владельца.", "GRMDoorUI_Body", 14, 10, C.text)
                draw.SimpleText("Категории настраиваются в разделе «Категории» и работают целым профилем.", "GRMDoorUI_Small", 14, 30, C.dim)
            end

            for _, fac in ipairs(facTree or {}) do
                local block = card(pnl, 44 + 32 + #(fac.roles or {}) * 31, tostring(fac.display or fac.name), C.teal)
                local holder = vgui.Create("DPanel", block)
                holder:Dock(FILL) holder:DockMargin(12, 36, 12, 8) holder:SetPaintBackground(false)
                checkRow(holder, "Вся организация [" .. fac.name .. "]", listHas(d.factions, fac.name), 0, C.teal, function()
                    act({ action = "toggle_acl_faction", entIndex = ent:EntIndex(), faction = fac.name })
                end)
                for _, role in ipairs(fac.roles or {}) do
                    local key = fac.name .. "|" .. role.key
                    checkRow(holder, "Должность: " .. tostring(role.display) .. "  [" .. role.key .. "]",
                        listHas(d.roles, key), 18, C.text, function()
                            act({ action = "toggle_acl_role", entIndex = ent:EntIndex(), roleKey = key })
                        end)
                end
            end

            local catBlock = card(pnl, 44 + math.max(1, #(cats or {})) * 31, "КАТЕГОРИИ ДОСТУПА")
            local catHolder = vgui.Create("DPanel", catBlock)
            catHolder:Dock(FILL) catHolder:DockMargin(12, 36, 12, 8) catHolder:SetPaintBackground(false)
            for _, c in ipairs(cats or {}) do
                checkRow(catHolder, tostring(c.name) .. "  [" .. tostring(c.id) .. "]",
                    listHas(d.categories, c.id), 0, C.gold, function()
                        act({ action = "toggle_acl_category", entIndex = ent:EntIndex(), category = c.id })
                    end)
            end
        end)
    end

    ------------------------------------------------------------------
    -- КАТЕГОРИИ (полный редактор, суперадмин)
    ------------------------------------------------------------------
    if isAdmin then
        addTab("categories", "Категории", function(pnl)
            local byID = {}
            for _, c in ipairs(cats or {}) do byID[c.id] = c end
            if not (lastCategory and byID[lastCategory]) then
                lastCategory = (cats and cats[1] and cats[1].id) or nil
            end

            local head = card(pnl, 96, "КАТЕГОРИИ ДОСТУПА К ДВЕРЯМ")
            local pick = skinCombo(vgui.Create("DComboBox", head))
            pick:SetPos(14, 40) pick:SetSize(330, 30)
            for _, c in ipairs(cats or {}) do
                pick:AddChoice(tostring(c.name) .. " [" .. tostring(c.id) .. "]", c.id, c.id == lastCategory)
            end
            if not lastCategory then pick:SetValue("Категорий пока нет") end
            pick.OnSelect = function(_, _, _, val)
                lastCategory = val
                timer.Simple(0, function() if IsValid(f) then selectTab("categories") end end)
            end

            local newBtn = button(head, "+ СОЗДАТЬ", C.green)
            newBtn:SetPos(354, 40) newBtn:SetSize(140, 30)
            newBtn.DoClick = function()
                Derma_StringRequest("Новая категория", "Системный ключ (eng, без пробелов)", "garage", function(id)
                    Derma_StringRequest("Новая категория", "Название для админов", "Гаражи", function(nm)
                        lastCategory = string.lower(tostring(id or "")):gsub("[^%w_%-]", "")
                        act({ action = "cat_create", entIndex = ent:EntIndex(), catId = id, name = nm })
                    end)
                end)
            end

            local cat = lastCategory and byID[lastCategory]
            if not cat then return end

            local renameBtn = button(head, "Переименовать", C.cardHov)
            renameBtn:SetPos(504, 40) renameBtn:SetSize(150, 30)
            renameBtn.DoClick = function()
                Derma_StringRequest("Категория", "Новое название", tostring(cat.name), function(nm)
                    act({ action = "cat_rename", entIndex = ent:EntIndex(), catId = cat.id, name = nm })
                end)
            end
            local delBtn = button(head, "Удалить", C.red)
            delBtn:SetPos(664, 40) delBtn:SetSize(120, 30)
            delBtn.DoClick = function()
                Derma_Query("Удалить категорию «" .. tostring(cat.name) .. "»?\nДвери с ней станут ничьими.",
                    "Категории", "Удалить", function()
                        lastCategory = nil
                        act({ action = "cat_delete", entIndex = ent:EntIndex(), catId = cat.id })
                    end, "Отмена")
            end

            -- Живые ссылки на галочки: по ним вкладка обновляется НА МЕСТЕ,
            -- без пересборки и без прыжка списка вверх.
            local memberRows, flagRows = {}, {}
            catRefresh = function()
                local map = {}
                for _, c in ipairs(cats or {}) do map[c.id] = c end
                local cur = lastCategory and map[lastCategory]
                if not cur then return false end
                for _, r in ipairs(memberRows) do
                    r.set(listHas(cur[r.list], r.value))
                end
                for _, r in ipairs(flagRows) do
                    local on = cur[r.key] == true
                    if r.key == "canLock" then on = cur.canLock ~= false end
                    r.set(on)
                end
                return true
            end

            -- Флаги поведения.
            local flags = D.CategoryFlags or {}
            local flagCard = card(pnl, 44 + #flags * 42, "ПОВЕДЕНИЕ КАТЕГОРИИ «" .. string.upper(tostring(cat.name)) .. "»")
            local flagHolder = vgui.Create("DPanel", flagCard)
            flagHolder:Dock(FILL) flagHolder:DockMargin(12, 36, 12, 8) flagHolder:SetPaintBackground(false)
            for _, flag in ipairs(flags) do
                local on = cat[flag.key] == true
                if flag.key == "canLock" then on = cat.canLock ~= false end
                local r = vgui.Create("DPanel", flagHolder)
                r:Dock(TOP) r:SetTall(38) r:DockMargin(0, 0, 6, 4)
                r.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.row)
                    draw.SimpleText(tostring(flag.desc or ""), "GRMDoorUI_Small", 34, 22, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
                local chk = vgui.Create("DCheckBoxLabel", r)
                chk:SetPos(10, 6) chk:SetSize(r:GetWide() - 20, 18)
                chk:Dock(NODOCK)
                chk:SetText(tostring(flag.label))
                chk:SetFont("GRMDoorUI_Body")
                chk:SetTextColor(on and C.gold or C.text)
                chk:SetValue(on and 1 or 0)
                local flagSilent = false
                chk.OnChange = function(_, val)
                    if flagSilent then return end
                    act({ action = "cat_flag", entIndex = ent:EntIndex(), catId = cat.id, flag = flag.key, value = val and true or false })
                end
                flagRows[#flagRows + 1] = { key = flag.key, set = function(state)
                    flagSilent = true
                    chk:SetValue(state and 1 or 0)
                    chk:SetTextColor(state and C.gold or C.text)
                    flagSilent = false
                end }
            end

            -- Кто входит в категорию: организации, отделы, подотделы, должности.
            for _, fac in ipairs(facTree or {}) do
                local subs = fac.subdepartments or {}
                local rows = 1 + #(fac.departments or {}) + #subs + #(fac.roles or {})
                local block = card(pnl, 44 + rows * 31, tostring(fac.display or fac.name) .. "  [" .. fac.name .. "]", C.teal)
                local holder = vgui.Create("DPanel", block)
                holder:Dock(FILL) holder:DockMargin(12, 36, 12, 8) holder:SetPaintBackground(false)

                local function member(label, list, value, indent, color)
                    local _, _, set = checkRow(holder, label, listHas(cat[list], value), indent, color, function()
                        act({ action = "cat_member", entIndex = ent:EntIndex(), catId = cat.id, list = list, value = value })
                    end)
                    memberRows[#memberRows + 1] = { list = list, value = value, set = set }
                end

                member("Вся организация", "factions", fac.name, 0, C.teal)
                for _, dept in ipairs(fac.departments or {}) do
                    member("Отдел: " .. tostring(dept.display), "departments", fac.name .. "|" .. dept.key, 16, C.accent)
                end
                for _, sub in ipairs(subs) do
                    member("Подотдел: " .. tostring(sub.display), "subdepartments", fac.name .. "|" .. sub.key, 30, C.gold)
                end
                for _, role in ipairs(fac.roles or {}) do
                    member("Должность: " .. tostring(role.display), "roles", fac.name .. "|" .. role.key, 16, C.text)
                end
            end
        end)
    end

    ------------------------------------------------------------------
    -- АДМИНИСТРИРОВАНИЕ
    ------------------------------------------------------------------
    if isAdmin then
        addTab("admin", "Администрирование", function(pnl)
            local facCard = card(pnl, 92, "ВЛАДЕЛЕЦ — ОРГАНИЗАЦИЯ")
            local facCombo = skinCombo(vgui.Create("DComboBox", facCard))
            facCombo:SetPos(14, 40) facCombo:SetSize(330, 30) facCombo:SetValue("Выберите организацию...")
            for _, fac in ipairs(facTree or {}) do facCombo:AddChoice(tostring(fac.display) .. " [" .. fac.name .. "]", fac.name) end
            local setFac = button(facCard, "НАЗНАЧИТЬ", C.accent)
            setFac:SetPos(354, 40) setFac:SetSize(150, 30)
            setFac.DoClick = function()
                local _, fn = facCombo:GetSelected()
                if fn then act({ action = "set_faction_owner", entIndex = ent:EntIndex(), faction = fn }) end
            end

            local catCard = card(pnl, 92, "ВЛАДЕЛЕЦ — КАТЕГОРИЯ")
            local catCombo = skinCombo(vgui.Create("DComboBox", catCard))
            catCombo:SetPos(14, 40) catCombo:SetSize(330, 30) catCombo:SetValue("Выберите категорию...")
            for _, c in ipairs(cats or {}) do catCombo:AddChoice(tostring(c.name) .. " [" .. tostring(c.id) .. "]", c.id) end
            local setCat = button(catCard, "НАЗНАЧИТЬ", C.accent)
            setCat:SetPos(354, 40) setCat:SetSize(150, 30)
            setCat.DoClick = function()
                local _, cid = catCombo:GetSelected()
                if cid then act({ action = "set_category_owner", entIndex = ent:EntIndex(), category = cid }) end
            end
            local editCat = button(catCard, "НАСТРОИТЬ КАТЕГОРИИ", C.gold)
            editCat:SetPos(514, 40) editCat:SetSize(210, 30)
            editCat.DoClick = function() selectTab("categories") end

            local misc = card(pnl, 120, "ПРОЧЕЕ")
            local clear = button(misc, "СБРОСИТЬ ВЛАДЕЛЬЦА", C.red)
            clear:SetPos(14, 40) clear:SetSize(240, 30)
            clear.DoClick = function() act({ action = "clear_owner", entIndex = ent:EntIndex() }) end

            local own = button(misc, d.ownable and "ПРИВАТИЗАЦИЯ РАЗРЕШЕНА (запретить)" or "ПРИВАТИЗАЦИЯ ЗАПРЕЩЕНА (разрешить)",
                d.ownable and C.green or C.red)
            own:SetPos(14, 78) own:SetSize(420, 30)
            own.DoClick = function() act({ action = "toggle_ownable", entIndex = ent:EntIndex() }) end
        end)
    end

    --[[ ЗАПОМИНАНИЕ ПРОКРУТКИ.
         OnVScroll у DScrollPanel — это НЕ уведомление, а сама механика:
         именно она двигает холст (pnlCanvas:SetPos). Своя функция поверх неё
         означала «полоса едет, страница стоит» — как и было во вкладке
         «Категории». Поэтому оригинал вызываем первым, а offset только
         запоминаем. ]]
    local baseVScroll = content.OnVScroll
    content.OnVScroll = function(pnl, offset)
        if baseVScroll then baseVScroll(pnl, offset) end
        -- Программные сдвиги (построение вкладки, восстановление) в память
        -- не пишем — иначе позиция сама себя обнуляет.
        if scrollSilent then return end
        lastScroll = math.abs(tonumber(offset) or 0)
    end

    if not tabs[lastTab] then lastTab = "overview" end
    local wantScroll = lastScroll
    selectTab(lastTab)

    --[[ ОБНОВЛЕНИЕ БЕЗ ПЕРЕСБОРКИ ОКНА.
         Сервер после каждого действия шлёт свежий снимок двери. Раньше на
         него окно создавалось ЗАНОВО — отсюда и прыжок списка вверх после
         каждой галочки в категории (восстановление прокрутки не успевало
         за раскладкой). Теперь при том же объекте окно живёт дальше:
           • изменилась только принадлежность к категории → правим галочки
             на месте, ничего не пересобирая и не двигая прокрутку;
           • изменился состав категорий или структура организаций →
             пересобираем текущую вкладку и возвращаем прокрутку. ]]
    f.GRMDoorEnt = ent
    f.GRMSignature = D.MenuSignature and D.MenuSignature(cats, facTree) or ""
    f.GRMPatch = function(newD, newCats, newFacTree, newAdmin)
        if not IsValid(f) then return end
        d = istable(newD) and newD or d
        cats = istable(newCats) and newCats or cats
        facTree = istable(newFacTree) and newFacTree or facTree
        if newAdmin ~= nil then isAdmin = (d.is_admin == true) or (newAdmin == true) end
        ownerDesc = describeOwner(d)

        local sig = D.MenuSignature and D.MenuSignature(cats, facTree) or ""
        local structureSame = (sig == f.GRMSignature)
        f.GRMSignature = sig

        if structureSame and lastTab == "categories" and catRefresh and catRefresh() then
            return
        end

        local keep = IsValid(content.VBar) and content.VBar:GetScroll() or 0
        selectTab(lastTab)
        setScroll(keep)
        lastScroll = keep
        timer.Simple(0, function()
            if not (IsValid(f) and IsValid(content)) then return end
            content:InvalidateLayout(true)
            setScroll(keep)
        end)
    end

    -- Форвард-декларация: функция вызывает саму себя из таймера.
    local restoreScroll
    restoreScroll = function(tries)
        if not (IsValid(f) and IsValid(content) and IsValid(content.VBar)) then return end
        content:InvalidateLayout(true)
        setScroll(wantScroll)
        local got = content.VBar.GetScroll and content.VBar:GetScroll() or 0
        if math.abs(got - wantScroll) > 1 and tries > 1 then
            timer.Simple(0, function() restoreScroll(tries - 1) end)
        end
    end
    if wantScroll > 0 then
        lastScroll = wantScroll
        timer.Simple(0, function() restoreScroll(8) end)
    end
end

net.Receive(NET_OPEN, function()
    local ent = net.ReadEntity()
    local d = net.ReadTable() or {}
    local cats = net.ReadTable() or {}
    local facTree = net.ReadTable() or {}
    local canAdmin = net.ReadBool()
    if not IsValid(ent) then return end
    local f = D._frame
    if IsValid(f) and f.GRMDoorEnt == ent and isfunction(f.GRMPatch) then
        f.GRMPatch(d, cats, facTree, canAdmin)
        return
    end
    D.OpenMenu(ent, d, cats, facTree, canAdmin)
end)

concommand.Add("grm_door_menu", function()
    net.Start(NET_ACT) net.WriteTable({ action = "open_menu" }) net.SendToServer()
end)
