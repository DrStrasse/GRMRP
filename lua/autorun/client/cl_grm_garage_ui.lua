--[[--------------------------------------------------------------------
    GRM Garage UI v1.0.0 — окно гаража и админ-список гаражей.

    Окно открывается сервером (net GRM_Garage_Open) при команде /garage в
    зоне гаража или при нажатии E на стойке. Стиль — общий GRM: тёмный
    корпус, золотой заголовок, карточки.

    Разделы:
      • «Мой транспорт» — что стоит в этом гараже и что сейчас на карте:
        ВЫДАТЬ (на свободное место) / УБРАТЬ (в гараж) / ПРИПИСАТЬ СЮДА;
      • «Места стоянки» — какие места свободны, какие заняты.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.Garage = GRM.Garage or {}
local G = GRM.Garage
G.UIVersion = "1.0.0"

surface.CreateFont("GRMGar_Title", { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMGar_Head",  { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMGar_Body",  { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMGar_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg      = Color(16, 20, 28, 252),
    sidebar = Color(12, 15, 22, 255),
    card    = Color(22, 28, 38, 240),
    cardHov = Color(32, 42, 56, 240),
    border  = Color(38, 48, 66, 200),
    accent  = Color(65, 145, 235),
    gold    = Color(245, 195, 65),
    green   = Color(55, 185, 110),
    teal    = Color(75, 195, 170),
    red     = Color(225, 70, 70),
    text    = Color(240, 244, 250),
    dim     = Color(155, 170, 190),
}

local function money(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

local function button(parent, label, base)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Paint = function(self, w, h)
        local col = base
        if not self:IsEnabled() then col = Color(38, 44, 56)
        elseif self:IsHovered() then col = Color(math.min(255, base.r + 24), math.min(255, base.g + 24), math.min(255, base.b + 24)) end
        draw.RoundedBox(6, 0, 0, w, h, col)
        draw.SimpleText(label, "GRMGar_Body", w / 2, h / 2, self:IsEnabled() and color_white or C.dim,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function preview(p, model)
    if not util.IsValidModel(model or "") then return end
    p:SetModel(model)
    local e = p:GetEntity()
    if not IsValid(e) then return end
    local mn, mx = e:GetRenderBounds()
    local size = math.max((mx - mn):Length(), 30)
    p:SetFOV(34)
    p:SetCamPos(Vector(size, size, size * 0.55))
    p:SetLookAt((mn + mx) * 0.5)
    p.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, RealTime() * 15 % 360, 0)) end
end

local frame

function G.OpenWindow(data)
    if not istable(data) then return end
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetSize(math.Clamp(ScrW() * 0.72, 900, 1320), math.Clamp(ScrH() * 0.76, 620, 900))
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_garage", frame) end

    local kindName = (G.Kinds and G.Kinds[data.kind]) or "Гараж"
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.sidebar)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("ГАРАЖ · " .. tostring(data.name), "GRMGar_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local info = ("%s  •  свободных мест: %d из %d"):format(kindName, data.free or 0, #(data.slots or {}))
        if (data.doors or 0) > 0 then
            info = info .. ("  •  ворота: %d (%s)"):format(data.doors, data.doorsLocked and "закрыты" or "открыты")
        end
        if (data.fee or 0) > 0 then info = info .. "  •  выезд: " .. money(data.fee) end
        draw.SimpleText(info, "GRMGar_Small", 18, 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = button(frame, "✕", C.red)
    close:SetSize(34, 30)
    close:SetPos(frame:GetWide() - 44, 8)
    close.DoClick = function() frame:Remove() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 54, 12, 12)
    body:SetPaintBackground(false)

    -- Правая колонка: места стоянки.
    local right = vgui.Create("DPanel", body)
    right:Dock(RIGHT)
    right:SetWide(300)
    right:DockMargin(10, 0, 0, 0)
    right.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("МЕСТА СТОЯНКИ", "GRMGar_Head", 14, 16, C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local slots = vgui.Create("DScrollPanel", right)
    slots:Dock(FILL)
    slots:DockMargin(10, 44, 10, 10)
    if #(data.slots or {}) == 0 then
        local empty = vgui.Create("DPanel", slots)
        empty:Dock(TOP) empty:SetTall(64)
        empty.Paint = function(_, w, h)
            draw.SimpleText("Места не размечены.", "GRMGar_Body", 6, 10, C.dim)
            draw.SimpleText("Админ ставит их тулом «GRM: транспорт».", "GRMGar_Small", 6, 32, C.dim)
        end
    end
    for _, s in ipairs(data.slots or {}) do
        local row = vgui.Create("DPanel", slots)
        row:Dock(TOP) row:SetTall(38) row:DockMargin(0, 0, 0, 6)
        row.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(26, 33, 45))
            draw.RoundedBox(3, 0, 0, 4, h, s.free and C.green or C.red)
            draw.SimpleText(tostring(s.name or "Место"), "GRMGar_Body", 14, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(s.free and "свободно" or "занято", "GRMGar_Small", w - 12, h / 2,
                s.free and C.green or C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    -- Левая часть: транспорт.
    local list = vgui.Create("DScrollPanel", body)
    list:Dock(FILL)

    local rows = data.vehicles or {}
    if #rows == 0 then
        local empty = vgui.Create("DPanel", list)
        empty:Dock(TOP) empty:SetTall(90)
        empty.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText("Личного транспорта нет. Купите машину у дилера — она приедет в гараж.",
                "GRMGar_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    --[[ ТАБЛИЧНЫЙ СПИСОК ТРАНСПОРТА (заказ владельца 22.08): одна реальная
         машина = одна строка, служебная и личная в одном списке разными
         блоками. Личный — «МОЙ ТРАНСПОРТ», служебный — «СЛУЖЕБНЫЙ АВТОПАРК». ]]
    local VC = GRM.VehicleCells
    local rowsPresent = #rows > 0 or #(data.fleet or {}) > 0

    if #rows > 0 and VC and VC.TableRow then
        local head = vgui.Create("DPanel", list)
        head:Dock(TOP) head:SetTall(34) head:DockMargin(0, 0, 6, 6)
        head.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(26, 33, 45))
            draw.SimpleText("МОЙ ТРАНСПОРТ", "GRMGar_Body", 12, h / 2, C.gold,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("личные машины владельца  •  выдаются по местам стоянки", "GRMGar_Small",
                w - 12, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        VC.TableHeader(list, { { label = "НАЗВАНИЕ" }, { label = "КЛАСС" }, { label = "НОМЕР" },
            { label = "ГАРАЖ" }, { label = "СТАТУС" } })
    end
    for _, v in ipairs(rows) do
        if VC and VC.TableRow then
            local buttons = {
                { label = v.onMap and "УБРАТЬ В ГАРАЖ" or "ВЫДАТЬ",
                  color = v.onMap and C.accent or C.green,
                  fn = function() G.SendAction(v.onMap and "store" or "retrieve", v.id) end },
            }
            if not v.here then
                buttons[#buttons + 1] = { label = "ПРИПИСАТЬ СЮДА", color = C.cardHov,
                    fn = function() G.SendAction("sethome", v.id) end }
            end
            VC.TableRow(list, {
                name = v.name or v.class, class = v.class, plate = v.plate,
                garage = (v.homeName or "") ~= "" and v.homeName or "—",
                state = { text = v.onMap and ("на карте • " .. tostring(v.distance or 0) .. " юн.") or "в гараже",
                          good = not v.onMap },
                buttons = buttons,
            })
        end
    end

    --[[ СЛУЖЕБНАЯ ТЕХНИКА ОРГАНИЗАЦИИ (автопарк, приписанный к этому гаражу).
         Гараж и автопарк — один экран: сотрудник берёт служебную машину там
         же, где и личную, и она встаёт на свободное МЕСТО стоянки. ]]
    local fleet = data.fleet or {}
    if #fleet > 0 and VC and VC.TableRow then
        local head = vgui.Create("DPanel", list)
        head:Dock(TOP) head:SetTall(34) head:DockMargin(0, 6, 6, 6)
        head.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(26, 33, 45))
            draw.SimpleText("СЛУЖЕБНЫЙ АВТОПАРК ОРГАНИЗАЦИИ", "GRMGar_Body", 12, h / 2, C.gold,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("закуплено руководством  •  выдаётся по местам стоянки", "GRMGar_Small",
                w - 12, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        VC.TableHeader(list, { { label = "НАЗВАНИЕ" }, { label = "КЛАСС" }, { label = "НОМЕР" },
            { label = "ГАРАЖ" }, { label = "СТАТУС" } })
    end
    for _, v in ipairs(fleet) do
        if VC and VC.TableRow then
            local allowed = v.allowed ~= false
            local note = (v.allowed == false)
                and ((v.reason or "") ~= "" and v.reason or "закреплена за другими должностями")
                or (v.restriction or "")
            VC.TableRow(list, {
                name = v.name or v.class, class = v.class, plate = v.plate,
                garage = (v.homeName or "") ~= "" and v.homeName or "—",
                accent = C.gold,
                state = { text = v.onMap and "на линии" or "в гараже", good = not v.onMap },
                buttons = {
                    { label = v.onMap and "ВЕРНУТЬ В ГАРАЖ" or (allowed and "ВЫДАТЬ СЛУЖЕБНУЮ" or "НЕ ПОЛОЖЕНА"),
                      color = v.onMap and C.accent or (allowed and C.green or C.cardHov),
                      enabled = (v.onMap or allowed) == true,
                      fn = function() G.SendAction(v.onMap and "fleet_store" or "fleet_issue", v.id) end },
                },
            })
        end
    end

    -- Ворота: одна кнопка на весь набор дверей гаража.
    if (data.doors or 0) > 0 then
        local gates = button(frame, data.doorsLocked and "ОТКРЫТЬ ВОРОТА" or "ЗАКРЫТЬ ВОРОТА",
            data.doorsLocked and C.green or C.accent)
        gates:Dock(BOTTOM) gates:SetTall(36) gates:DockMargin(12, 0, 12, 8)
        gates.DoClick = function() G.SendAction("doors", "") end
    end

    local refresh = button(frame, "ОБНОВИТЬ", C.cardHov)
    refresh:Dock(BOTTOM) refresh:SetTall(32) refresh:DockMargin(12, 0, 12, 10)
    refresh.DoClick = function() G.SendAction("refresh", "") end
end

-----------------------------------------------------------------------
-- АДМИН-СПИСОК ГАРАЖЕЙ (grm_garage_admin)
-----------------------------------------------------------------------
local adminFrame, adminList

local function requestAdmin()
    net.Start(G.NetAdmin or "GRM_Garage_Admin") net.WriteString("list") net.SendToServer()
end

local function fillAdmin(rows)
    if not IsValid(adminList) then return end
    adminList:Clear()
    for _, r in ipairs(rows or {}) do
        local card = vgui.Create("DPanel", adminList)
        card:Dock(TOP) card:SetTall(74) card:DockMargin(0, 0, 6, 6)
        card.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(tostring(r.name), "GRMGar_Head", 14, 12, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(("%s • мест %d • стоек %d • ворот %d • выезд %s"):format(
                (G.Kinds and G.Kinds[r.kind]) or r.kind, r.slots or 0, r.terminals or 0, r.doors or 0, money(r.fee or 0)),
                "GRMGar_Small", 14, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local extra = tostring(r.id)
            if r.faction ~= "" then extra = extra .. "  •  " .. r.faction end
            if tostring(r.propertyID or "") ~= "" then extra = extra .. "  •  продаётся с объектом " .. r.propertyID end
            draw.SimpleText(extra, "GRMGar_Small", 14, 54, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        local del = button(card, "Удалить", C.red)
        del:Dock(RIGHT) del:SetWide(90) del:DockMargin(6, 18, 12, 18)
        del.DoClick = function()
            Derma_Query("Удалить гараж «" .. tostring(r.name) .. "»?", "Гаражи", "Удалить", function()
                net.Start(G.NetAdmin or "GRM_Garage_Admin") net.WriteString("remove") net.WriteString(r.id) net.SendToServer()
                timer.Simple(0.3, requestAdmin)
            end, "Отмена")
        end

        local tp = button(card, "Телепорт", C.accent)
        tp:Dock(RIGHT) tp:SetWide(100) tp:DockMargin(6, 18, 0, 18)
        tp.DoClick = function()
            net.Start(G.NetAdmin or "GRM_Garage_Admin") net.WriteString("goto") net.WriteString(r.id) net.SendToServer()
        end

        local rename = button(card, "Название", C.cardHov)
        rename:Dock(RIGHT) rename:SetWide(100) rename:DockMargin(6, 18, 0, 18)
        rename.DoClick = function()
            Derma_StringRequest("Гараж", "Новое название", tostring(r.name), function(val)
                net.Start(G.NetAdmin or "GRM_Garage_Admin")
                    net.WriteString("update") net.WriteString(r.id) net.WriteTable({ name = val })
                net.SendToServer()
                timer.Simple(0.3, requestAdmin)
            end)
        end
    end
end

net.Receive(G.NetAdmin or "GRM_Garage_Admin", function()
    local op = net.ReadString()
    local rows = net.ReadTable() or {}
    if op == "list" then fillAdmin(rows) elseif op == "done" then requestAdmin() end
end)

concommand.Add("grm_garage_admin", function()
    if IsValid(adminFrame) then adminFrame:Remove() end
    adminFrame = vgui.Create("DFrame")
    adminFrame:SetSize(math.Clamp(ScrW() * 0.6, 760, 1100), math.Clamp(ScrH() * 0.7, 520, 820))
    adminFrame:Center() adminFrame:SetTitle("") adminFrame:ShowCloseButton(false) adminFrame:MakePopup()
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_garage_admin", adminFrame) end
    adminFrame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.sidebar)
        draw.SimpleText("GRM · ГАРАЖИ КАРТЫ", "GRMGar_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Разметка — тулом «GRM: гаражи»", "GRMGar_Small", 18, 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local close = button(adminFrame, "✕", C.red)
    close:SetSize(34, 30) close:SetPos(adminFrame:GetWide() - 44, 8)
    close.DoClick = function() adminFrame:Remove() end

    adminList = vgui.Create("DScrollPanel", adminFrame)
    adminList:Dock(FILL) adminList:DockMargin(12, 54, 12, 12)
    requestAdmin()
end)
