--[[--------------------------------------------------------------------
    GRM Weapon Rack UI — окно оружейной стойки.

    Сетка крупных ячеек в стиле логистики: в каждой ячейке 3D-модель
    ствола (WorldModel из ArcCW), название, обвес и закрепление.
    Пустая ячейка помнит, что в ней лежало, и подсказывает это серым.
----------------------------------------------------------------------]]

if SERVER then return end

GRM = GRM or {}
GRM.WeaponRack = GRM.WeaponRack or {}
local RK = GRM.WeaponRack

-- Палитра логистики: окно должно выглядеть частью того же модуля.
local C = {
    bg     = Color(20, 25, 34, 248),
    panel  = Color(34, 43, 57, 245),
    panel2 = Color(42, 52, 68, 245),
    cell   = Color(28, 36, 48, 250),
    cellH  = Color(38, 50, 68, 250),
    accent = Color(70, 155, 255),
    green  = Color(55, 185, 105),
    red    = Color(205, 70, 65),
    yellow = Color(235, 180, 60),
    text   = Color(240, 244, 250),
    dim    = Color(165, 175, 190),
    lock   = Color(120, 130, 148),
}

surface.CreateFont("GRMRack_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMRack_Sub",    { font = "Roboto", size = 16, weight = 600, extended = true })
surface.CreateFont("GRMRack_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMRack_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })

local function button(parent, text, color, w, h)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    if w and h then b:SetSize(w, h) end
    b.Paint = function(self, pw, ph)
        local c = color
        if not self:IsEnabled() then c = C.lock
        elseif self:IsHovered() then
            c = Color(math.min(255, color.r + 28), math.min(255, color.g + 28), math.min(255, color.b + 28))
        end
        draw.RoundedBox(5, 0, 0, pw, ph, c)
        draw.SimpleText(text, "GRMRack_Normal", pw / 2, ph / 2, color_white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function act(ent, action, index, data)
    if not IsValid(ent) then return end
    net.Start(RK.NET.ACT)
        net.WriteEntity(ent)
        net.WriteString(tostring(action or ""))
        net.WriteUInt(math.floor(tonumber(index) or 0), 8)
        net.WriteTable(istable(data) and data or {})
    net.SendToServer()
end

local frame

--- Окно настройки ячейки: закрепление за должностью/званием/отделом.
local function openCellConfig(ent, cell, scope)
    local m = vgui.Create("DFrame")
    m:SetTitle("") m:SetSize(430, 300) m:Center() m:MakePopup() m:ShowCloseButton(false)
    m.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 38, C.panel)
        draw.SimpleText("Ячейка " .. cell.index .. " — закрепление", "GRMRack_Sub", 16, 19,
            C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local function label(text, y)
        local l = vgui.Create("DLabel", m)
        l:SetPos(16, y) l:SetSize(398, 18)
        l:SetFont("GRMRack_Small") l:SetTextColor(C.dim) l:SetText(text)
    end

    label("Должность (сильнее всего)", 48)
    local posCombo = vgui.Create("DComboBox", m)
    posCombo:SetPos(16, 68) posCombo:SetSize(398, 26)
    posCombo:AddChoice("— любая —", "", (cell.position or "") == "")
    for _, p in ipairs(scope.positions or {}) do
        posCombo:AddChoice(p.display, p.key, cell.position == p.key)
    end

    label("Звание", 102)
    local roleCombo = vgui.Create("DComboBox", m)
    roleCombo:SetPos(16, 122) roleCombo:SetSize(398, 26)
    roleCombo:AddChoice("— любое —", "", (cell.role or "") == "")
    for _, r in ipairs(scope.roles or {}) do
        roleCombo:AddChoice(r.display, r.key, cell.role == r.key)
    end

    label("Отдел или подотдел", 156)
    local deptCombo = vgui.Create("DComboBox", m)
    deptCombo:SetPos(16, 176) deptCombo:SetSize(398, 26)
    deptCombo:AddChoice("— любой —", "", (cell.dept or "") == "")
    for _, d in ipairs(scope.depts or {}) do
        deptCombo:AddChoice(d.display, d.key, cell.dept == d.key)
    end

    label("Подпись ячейки (необязательно)", 210)
    local labelEntry = vgui.Create("DTextEntry", m)
    labelEntry:SetPos(16, 230) labelEntry:SetSize(398, 26)
    labelEntry:SetText(cell.label or "")

    local cancel = button(m, "Отмена", C.panel2, 190, 32)
    cancel:SetPos(16, 262)
    cancel.DoClick = function() m:Close() end

    local save = button(m, "Сохранить", C.green, 190, 32)
    save:SetPos(224, 262)
    save.DoClick = function()
        local _, pos = posCombo:GetSelected()
        local _, role = roleCombo:GetSelected()
        local _, dept = deptCombo:GetSelected()
        act(ent, "configure", cell.index, {
            position = pos or "", role = role or "", dept = dept or "",
            label = labelEntry:GetValue() or "",
        })
        m:Close()
    end
end

local function openRack(ent, data)
    if IsValid(frame) then frame:Remove() end

    local cols = math.max(1, math.floor(tonumber(data.cols) or 5))
    local rows = math.max(1, math.floor(tonumber(data.rows) or 3))

    -- Крупные ячейки: ствол должен быть виден целиком.
    local cellW, cellH, gap = 188, 150, 10
    local gridW = cols * cellW + (cols - 1) * gap
    local gridH = rows * cellH + (rows - 1) * gap
    local w = math.Clamp(gridW + 56, 640, ScrW() - 60)
    local h = math.Clamp(gridH + 190, 420, ScrH() - 60)

    local f = vgui.Create("DFrame")
    frame = f
    f:SetSize(w, h) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("weaponrack", f) end
    f.Paint = function(_, pw, ph)
        draw.RoundedBox(10, 0, 0, pw, ph, C.bg)
        draw.RoundedBoxEx(10, 0, 0, pw, 58, C.panel, true, true, false, false)
        draw.SimpleText(tostring(data.title or "Оружейная стойка"), "GRMRack_Title", 20, 18, C.text)
        local sub = "Занято ячеек: " .. tostring(data.filled or 0) .. " из " .. tostring(cols * rows)
        if (data.faction or "") ~= "" then
            local disp = data.faction
            if GRM.Factions and GRM.Factions.DisplayName then disp = GRM.Factions.DisplayName(data.faction) end
            sub = disp .. "  •  " .. sub
        end
        draw.SimpleText(sub, "GRMRack_Small", 20, 40, C.dim)
    end

    local close = button(f, "ЗАКРЫТЬ", C.red, 110, 28)
    close:SetPos(w - 126, 15)
    close.DoClick = function() f:Remove() end

    -- ── СЕТКА ЯЧЕЕК ────────────────────────────────────────────────
    local scroll = vgui.Create("DScrollPanel", f)
    scroll:SetPos(20, 68)
    scroll:SetSize(w - 40, h - 68 - 82)

    local canvas = vgui.Create("DPanel", scroll)
    canvas:SetSize(gridW, gridH)
    canvas:SetPaintBackground(false)

    for _, cell in ipairs(data.cells or {}) do
        local i = cell.index
        local cx = ((i - 1) % cols) * (cellW + gap)
        local cy = math.floor((i - 1) / cols) * (cellH + gap)

        local pnl = vgui.Create("DPanel", canvas)
        pnl:SetPos(cx, cy) pnl:SetSize(cellW, cellH)

        local filled = isstring(cell.class) and cell.class ~= ""
        local allowed = cell.allowed == true

        pnl.Paint = function(self, pw, ph)
            local bg = C.cell
            if self:IsHovered() then bg = C.cellH end
            draw.RoundedBox(6, 0, 0, pw, ph, bg)
            -- Рамка показывает состояние: занята, закреплена, закрыта.
            local border = filled and C.green or C.panel2
            if not allowed then border = C.red
            elseif (cell.scope or "") ~= "" then border = C.yellow end
            surface.SetDrawColor(border)
            surface.DrawOutlinedRect(0, 0, pw, ph, filled and 2 or 1)

            draw.SimpleText("#" .. i, "GRMRack_Small", 8, 8, C.dim)
            if (cell.label or "") ~= "" then
                draw.SimpleText(cell.label, "GRMRack_Small", pw - 8, 8, C.dim, TEXT_ALIGN_RIGHT)
            end

            if filled then
                draw.SimpleText(cell.name or cell.class, "GRMRack_Normal", pw / 2, ph - 40,
                    allowed and C.text or C.lock, TEXT_ALIGN_CENTER)
                if (cell.attachments or 0) > 0 then
                    draw.SimpleText("обвес: " .. cell.attachments, "GRMRack_Small", pw / 2, ph - 24,
                        C.accent, TEXT_ALIGN_CENTER)
                end
            else
                local hint = "пусто"
                -- Память места: ячейка подсказывает, что здесь лежало.
                if cell.lastName then hint = "было: " .. cell.lastName end
                draw.SimpleText(hint, "GRMRack_Normal", pw / 2, ph / 2, C.dim, TEXT_ALIGN_CENTER)
            end

            if (cell.scope or "") ~= "" then
                draw.SimpleText(cell.scope, "GRMRack_Small", pw / 2, ph - 12,
                    allowed and C.yellow or C.red, TEXT_ALIGN_CENTER)
            end
        end

        --[[ 3D-модель ствола прямо в ячейке: берём WorldModel из ArcCW.
             Это и есть «крупная ячейка с показом модели». ]]
        if filled and (cell.model or "") ~= "" then
            local mp = vgui.Create("DModelPanel", pnl)
            mp:SetPos(10, 22) mp:SetSize(cellW - 20, cellH - 76)
            mp:SetModel(cell.model)
            mp:SetFOV(32)
            mp:SetMouseInputEnabled(false)
            mp:SetAnimated(false)
            local mdlEnt = mp:GetEntity()
            if IsValid(mdlEnt) then
                local mn, mx = mdlEnt:GetRenderBounds()
                local mid = (mn + mx) * 0.5
                local size = math.max(12, mx:Distance(mn))
                mp:SetLookAt(mid)
                mp:SetCamPos(mid + Vector(size * 0.62, size * 0.42, size * 0.30))
            end
            -- Лёгкое вращение: ствол читается лучше, чем в статике.
            mp.LayoutEntity = function(self, e)
                if IsValid(e) then e:SetAngles(Angle(0, (CurTime() * 18) % 360, 0)) end
            end
        end

        -- Клик по ячейке: взять или положить.
        local hit = vgui.Create("DButton", pnl)
        hit:SetText("") hit:Dock(FILL)
        hit.Paint = function() end
        hit.DoClick = function()
            if filled then
                if not allowed then
                    notification.AddLegacy(cell.scope ~= "" and ("Закреплено: " .. cell.scope)
                        or "Нет доступа к ячейке", NOTIFY_ERROR, 4)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                act(ent, "take", i)
            else
                if (data.activeWeapon or "") == "" then
                    notification.AddLegacy("Возьмите оружие в руки, чтобы положить", NOTIFY_ERROR, 4)
                    return
                end
                act(ent, "put", i)
            end
        end
        hit.DoRightClick = function()
            if not data.admin then return end
            local menu = DermaMenu()
            menu:AddOption("Настроить закрепление…", function()
                openCellConfig(ent, cell, data.scope or {})
            end)
            menu:Open()
        end
    end

    -- ── НИЖНЯЯ ПАНЕЛЬ ──────────────────────────────────────────────
    local bar = vgui.Create("DPanel", f)
    bar:SetPos(20, h - 74) bar:SetSize(w - 40, 54)
    bar.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, C.panel) end

    local putBtn = button(bar, (data.activeName or "") ~= ""
        and ("ПОЛОЖИТЬ: " .. data.activeName) or "ПОЛОЖИТЬ ОРУЖИЕ ИЗ РУК", C.green, 300, 34)
    putBtn:SetPos(10, 10)
    putBtn:SetEnabled((data.activeWeapon or "") ~= "")
    putBtn.DoClick = function() act(ent, "put", 0) end   -- 0 = первая свободная

    local hint = vgui.Create("DLabel", bar)
    hint:SetPos(322, 10) hint:SetSize(bar:GetWide() - 500, 34)
    hint:SetFont("GRMRack_Small") hint:SetTextColor(C.dim) hint:SetWrap(true)
    hint:SetText(data.admin
        and "Клик — взять или положить. Правый клик по ячейке — закрепить её за должностью, званием или отделом."
        or "Клик по ячейке — взять оружие. Пустая ячейка помнит, что в ней лежало.")

    if data.admin then
        local cfg = button(bar, "НАСТРОЙКИ", C.accent, 150, 34)
        cfg:SetPos(bar:GetWide() - 160, 10)
        cfg.DoClick = function()
            local m = vgui.Create("DFrame")
            m:SetTitle("") m:SetSize(420, 280) m:Center() m:MakePopup() m:ShowCloseButton(false)
            m.Paint = function(_, mw, mh)
                draw.RoundedBox(8, 0, 0, mw, mh, C.bg)
                draw.RoundedBox(8, 0, 0, mw, 38, C.panel)
                draw.SimpleText("Настройки стойки", "GRMRack_Sub", 16, 19, C.yellow,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local function lbl(text, y)
                local l = vgui.Create("DLabel", m)
                l:SetPos(16, y) l:SetSize(388, 18)
                l:SetFont("GRMRack_Small") l:SetTextColor(C.dim) l:SetText(text)
            end

            lbl("Организация-владелец", 48)
            local facCombo = vgui.Create("DComboBox", m)
            facCombo:SetPos(16, 68) facCombo:SetSize(388, 26)
            facCombo:SetValue((data.faction or "") ~= "" and data.faction or "— не задана —")
            facCombo:AddChoice("— не задана —", "")
            for name in pairs(FactionsData or {}) do facCombo:AddChoice(name, name) end

            lbl("Network ID (общая сеть со складом)", 102)
            local netEntry = vgui.Create("DTextEntry", m)
            netEntry:SetPos(16, 122) netEntry:SetSize(388, 26)
            netEntry:SetText(data.network or "")

            lbl("Название стойки", 156)
            local titleEntry = vgui.Create("DTextEntry", m)
            titleEntry:SetPos(16, 176) titleEntry:SetSize(388, 26)
            titleEntry:SetText(data.title or "")

            local modeChk = vgui.Create("DCheckBoxLabel", m)
            modeChk:SetPos(16, 210) modeChk:SetSize(388, 22)
            modeChk:SetText("Только для своей организации")
            modeChk:SetTextColor(C.text)
            modeChk:SetValue(data.factionMode ~= false)

            local saveBtn = button(m, "Сохранить", C.green, 185, 32)
            saveBtn:SetPos(16, 240)
            saveBtn.DoClick = function()
                local _, fac = facCombo:GetSelected()
                act(ent, "settings", 0, {
                    faction = fac or "", network = netEntry:GetValue() or "",
                    title = titleEntry:GetValue() or "",
                    factionMode = modeChk:GetChecked(),
                })
                m:Close()
            end
            local cancelBtn = button(m, "Отмена", C.panel2, 185, 32)
            cancelBtn:SetPos(219, 240)
            cancelBtn.DoClick = function() m:Close() end
        end

        local sizeBtn = button(bar, "СЕТКА", C.yellow, 100, 34)
        sizeBtn:SetPos(bar:GetWide() - 268, 10)
        sizeBtn.DoClick = function()
            local menu = DermaMenu()
            for _, preset in ipairs({ { 4, 2 }, { 5, 3 }, { 6, 3 }, { 6, 4 }, { 8, 4 } }) do
                menu:AddOption(preset[1] .. " × " .. preset[2] .. "  (" .. preset[1] * preset[2] .. " ячеек)",
                    function() act(ent, "resize", 0, { cols = preset[1], rows = preset[2] }) end)
            end
            menu:Open()
        end
    end
end

net.Receive(RK.NET.OPEN, function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    if not IsValid(ent) then return end
    -- Окно пересобирается свежим снимком после каждого действия.
    openRack(ent, data)
end)
