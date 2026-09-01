--[[--------------------------------------------------------------------
    GRM Vehicle Cells v1.0.0 — один слой «ячейка транспорта» (заказ
    владельца 22.08: «ячейки только в разделе мой транспорт, а служебное?»).

    ЗАЧЕМ. Машина показывается в четырёх местах: у дилера (гараж),
    в окне гаража (личное и служебное) и во вкладке «Автопарк» организации.
    Раньше каждое окно рисовало свою карточку — отсюда и разнобой: где-то
    ячейки с превью и номером, где-то длинная серая строка.

    Теперь ячейка одна на всех:
      GRM.VehicleCells.Grid(parent)      — сетка (DIconLayout) под ячейки;
      GRM.VehicleCells.Cell(grid, info)  — сама ячейка.

    info = {
        name, class, model, plate,        -- шапка ячейки
        state = { text = "В гараже", good = true },
        lines = { {text = "...", color = ...}, ... },   -- до трёх строк
        accent = Color(...),              -- полоса сверху
        buttons = { { label, color, fn, enabled }, ... },  -- до двух кнопок
        menu = { { label, fn, icon }, ... },               -- ПКМ по ячейке
    }
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.VehicleCells = GRM.VehicleCells or {}
local VC = GRM.VehicleCells
VC.Version = "1.0.0"

VC.W, VC.H = 228, 268

local C = {
    card    = Color(22, 28, 38, 240),
    cardHov = Color(32, 42, 56, 240),
    border  = Color(38, 48, 66, 200),
    text    = Color(240, 244, 250),
    dim     = Color(155, 170, 190),
    green   = Color(55, 185, 110),
    gold    = Color(245, 195, 65),
    accent  = Color(65, 145, 235),
}
VC.Colors = C

surface.CreateFont("GRMCell_Head",  { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMCell_Body",  { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMCell_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

--- Сетка под ячейки: сама переносит их по строкам.
function VC.Grid(parent)
    if not IsValid(parent) then return nil end
    local grid = vgui.Create("DIconLayout", parent)
    grid:Dock(TOP)
    grid:DockMargin(0, 0, 6, 0)
    grid:SetSpaceX(8)
    grid:SetSpaceY(8)
    return grid
end

--- Превью модели в ячейке: без вращения, камера по габаритам.
local function preview(panel, model)
    if not IsValid(panel) then return end
    panel:SetModel(tostring(model or ""))
    local ent = panel:GetEntity()
    if not IsValid(ent) then return end
    local mn, mx = ent:GetRenderBounds()
    local size = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
    local mid = (mn + mx) * 0.5
    panel:SetFOV(28)
    panel:SetCamPos(mid + Vector(size * 1.6, size * 1.1, size * 0.65))
    panel:SetLookAt(mid)
    panel:SetMouseInputEnabled(false)
end
VC.Preview = preview

local function cellButton(parent, label, color, fn, enabled)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetEnabled(enabled ~= false)
    b.Paint = function(self, w, h)
        local col = color or C.accent
        if not self:IsEnabled() then col = Color(38, 44, 56)
        elseif self:IsHovered() then
            col = Color(math.min(255, col.r + 22), math.min(255, col.g + 22), math.min(255, col.b + 22))
        end
        draw.RoundedBox(6, 0, 0, w, h, col)
        draw.SimpleText(label, "GRMCell_Body", w / 2, h / 2, self:IsEnabled() and color_white or C.dim,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() if isfunction(fn) then fn() end end
    return b
end

--- Ячейка транспорта.
function VC.Cell(parent, info)
    if not IsValid(parent) then return nil end
    info = istable(info) and info or {}
    local buttons = istable(info.buttons) and info.buttons or {}
    local lines = istable(info.lines) and info.lines or {}
    local state = istable(info.state) and info.state or nil
    local plate = tostring(info.plate or "")

    local rows = math.min(2, #buttons)
    local cell = vgui.Create("DPanel", parent)
    cell:SetSize(VC.W, VC.H + (rows > 1 and 30 or 0))

    cell.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, self:IsHovered() and C.cardHov or C.card)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.RoundedBox(8, 0, 0, w, 4, info.accent or (state and state.good and C.green or C.gold))

        draw.SimpleText(tostring(info.name or info.class or "Транспорт"), "GRMCell_Head", 12, 134,
            C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if info.class then
            draw.SimpleText(tostring(info.class), "GRMCell_Small", 12, 152, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        --[[ Табличка номера рисуется только у РЕАЛЬНОЙ машины. У позиции
             каталога (это класс, а не экземпляр) номера быть не может —
             «БЕЗ НОМЕРА» там только путало. ]]
        local stateX = 12
        if not info.noPlate then
            local pw = 96
            draw.RoundedBox(4, 12, 172, pw, 20, plate ~= "" and Color(232, 236, 242) or Color(38, 44, 56))
            draw.SimpleText(plate ~= "" and plate or "БЕЗ НОМЕРА", "GRMCell_Small", 12 + pw / 2, 182,
                plate ~= "" and Color(20, 24, 32) or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            stateX = 118
        end

        if state then
            draw.SimpleText(tostring(state.text or ""), "GRMCell_Small", stateX, 182,
                state.good and C.green or C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        for i = 1, math.min(3, #lines) do
            local l = lines[i]
            draw.SimpleText(tostring(l.text or ""), "GRMCell_Small", 12, 198 + (i - 1) * 16,
                l.color or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    local m = vgui.Create("DModelPanel", cell)
    m:SetPos(10, 10) m:SetSize(208, 118)
    preview(m, info.model)

    local y = VC.H - 48 + (rows > 1 and 0 or 0)
    for i = 1, rows do
        local def = buttons[i] or {}
        local b = cellButton(cell, tostring(def.label or ""), def.color, def.fn, def.enabled)
        b:SetPos(10, y) b:SetSize(208, 26)
        y = y + 30
    end

    if istable(info.menu) and #info.menu > 0 then
        cell.OnMousePressed = function(_, code)
            if code ~= MOUSE_RIGHT then return end
            local menu = DermaMenu()
            for _, item in ipairs(info.menu) do
                local opt = menu:AddOption(tostring(item.label or ""), item.fn or function() end)
                if item.icon then opt:SetIcon(item.icon) end
            end
            menu:Open()
        end
    end

    return cell
end

-----------------------------------------------------------------------
-- ЕДИНЫЙ ТАБЛИЧНЫЙ СПИСОК ТРАНСПОРТА (заказ владельца 22.08):
-- «1 машина = 1 слот/ячейка, табличным списком; служебная и гражданская
--  каждая отдельно». Ячейки (VC.Cell) остались для каталога/витрины, а
-- РЕАЛЬНЫЕ машины в окнах дилера, гаража и автопарка теперь рисуются
-- строками таблицы: название, класс, номер, гараж, статус, кнопки.
-----------------------------------------------------------------------
VC.TableRowH = 50
VC.TableButtonW = 108

--- Заголовок таблицы. Названия колонок рисуются по тем же долям, что
--  и тексты строки (0..1 содержимого слева от кнопок).
function VC.TableHeader(parent, cols)
    if not IsValid(parent) then return end
    local head = vgui.Create("DPanel", parent)
    head:Dock(TOP)
    head:SetTall(28)
    head:DockMargin(0, 0, 6, 0)
    head.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(18, 24, 34, 245))
        local buttonsW = #(istable(cols) and cols or {}) > 0 and ((#cols - 0) * 0) or 0
        -- у строки кнопки занимают заранее фиксированную правую зону
        local rightW = 0
        for _, c in ipairs(istable(cols) and cols or {}) do
            if c.right then rightW = rightW + (tonumber(c.width) or VC.TableButtonW) end
        end
        local left = math.max(10, w - rightW - 10)
        local fractions = { 0.02, 0.34, 0.50, 0.68, 0.88 }
        local i = 0
        for _, c in ipairs(istable(cols) and cols or {}) do
            if not c.right then
                i = i + 1
                local x = left * (fractions[i] or 0.02)
                draw.SimpleText(tostring(c.label or ""), "GRMCell_Small", x, h / 2,
                    C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
    return head
end

--- Строка таблицы: одна реальная машина (личная или служебная).
--  info = { name, class, plate, garage, state={text,good}, accent,
--           buttons={{label,color,fn,enabled},...}, menu={...} }
function VC.TableRow(parent, info)
    if not IsValid(parent) then return nil end
    info = istable(info) and info or {}
    local buttons = istable(info.buttons) and info.buttons or {}
    local menu = istable(info.menu) and info.menu or {}
    local plate = tostring(info.plate or "")

    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(VC.TableRowH + (#buttons > 2 and 12 or 0))
    row:DockMargin(0, 0, 6, 6)

    local stats = { x = 12 }
    row.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, self:IsHovered() and C.cardHov or C.card)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.RoundedBox(8, 0, 0, w, 3, info.accent or (info.state and info.state.good and C.green or C.gold))

        local rightW = math.min(#buttons, 2) * (VC.TableButtonW + 6) + 10
        local left = math.max(10, w - rightW - 10)

        draw.SimpleText(tostring(info.name or info.class or "Транспорт"), "GRMCell_Head", 12, h / 2,
            C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(info.class or ""), "GRMCell_Small", left * 0.34, h / 2,
            C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(plate ~= "" and plate or "—", "GRMCell_Small", left * 0.50, h / 2,
            plate ~= "" and Color(230, 235, 242) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(info.garage or ""), "GRMCell_Small", left * 0.68, h / 2,
            (info.garage or "") ~= "" and C.dim or C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if info.state then
            draw.SimpleText(tostring(info.state.text or ""), "GRMCell_Small", left * 0.88, h / 2,
                info.state.good and C.green or C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local rightX = 0
    for i = 1, math.min(2, #buttons) do
        -- рисуем кнопки СПРАВА: порядок от правого края, как подписи строк
        local def = buttons[i]
        local b = vgui.Create("DButton", row)
        b:Dock(RIGHT)
        b:SetWide(VC.TableButtonW)
        b:DockMargin(3, 10, 3, 10)
        b:SetText("")
        b:SetEnabled(def.enabled ~= false)
        b.Paint = function(self, bw, bh)
            local col = def.color or C.accent
            if not self:IsEnabled() then col = C.cardLight
            elseif self:IsHovered() then
                col = Color(math.min(255, col.r + 22), math.min(255, col.g + 22), math.min(255, col.b + 22))
            end
            draw.RoundedBox(6, 0, 0, bw, bh, col)
            draw.SimpleText(tostring(def.label or ""), "GRMCell_Body", bw / 2, bh / 2,
                self:IsEnabled() and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function() if isfunction(def.fn) then def.fn() end end
        rightX = rightX + VC.TableButtonW
    end

    if #menu > 0 then
        row.OnMousePressed = function(_, code)
            if code ~= MOUSE_RIGHT then return end
            local m = DermaMenu()
            for _, item in ipairs(menu) do
                local opt = m:AddOption(tostring(item.label or ""), item.fn or function() end)
                if item.icon then opt:SetIcon(item.icon) end
            end
            m:Open()
        end
    end

    return row
end

print("[GRM VehicleCells] v" .. VC.Version .. " loaded (Client)")
